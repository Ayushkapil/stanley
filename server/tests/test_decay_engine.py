"""The decay engine (§8.1, §13): server-authoritative, audited, and immune to
anchors (invariant A1). Decay bugs are trust bugs — these tests walk the full
lifecycle at exact boundaries."""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from stanley.models import Anchor, DecayAudit, Photo, PurgeQueueItem

from .conftest import START


def _photo_row(db, pid):
    with db() as session:
        return session.get(Photo, pid)


def _feed_ids(api):
    return [p["id"] for p in api.feed_photos()]


def test_full_lifecycle_of_an_unanchored_photo(circle, clock, sweep, db, app):
    pid = circle.ana.post_photo(caption="gone someday").json()["id"]

    clock.set(START + timedelta(hours=47, minutes=59))
    sweep()
    assert _photo_row(db, pid).state == "LIVE"

    clock.set(START + timedelta(hours=48))
    sweep()
    row = _photo_row(db, pid)
    assert row.state == "FADING"
    assert pid in _feed_ids(circle.ben)

    clock.set(START + timedelta(hours=120))
    sweep()
    assert _photo_row(db, pid).state == "LAST_LIGHT"
    assert pid in _feed_ids(circle.ben)

    clock.set(START + timedelta(hours=144))
    sweep()
    row = _photo_row(db, pid)
    assert row.state == "EXPIRED"
    assert pid not in _feed_ids(circle.ben)

    # tombstone window: queued for purge 7 days after expiry, not before
    with db() as session:
        item = session.scalars(
            select(PurgeQueueItem).where(PurgeQueueItem.photo_id == pid)
        ).one()
        assert item.purge_after == START + timedelta(hours=144, days=7)
        blob_key = session.get(Photo, pid).blob_key

    clock.set(START + timedelta(hours=144, days=6))
    sweep()
    assert app.state.storage.exists(blob_key)  # not yet

    clock.set(START + timedelta(hours=144, days=7, minutes=1))
    sweep()
    row = _photo_row(db, pid)
    assert row.state == "PURGED"
    assert row.owner_id is None and row.owner_hash is not None
    assert row.blob_key is None and row.caption is None
    assert not app.state.storage.exists(blob_key)


def test_anchored_photo_fades_on_schedule_but_blob_survives(circle, clock, sweep, db, app):
    """A1 + the retention rule: anchoring saves into private memory; it never
    alters public decay. The feed fades identically for the loved and the
    ignored."""
    pid = circle.ana.post_photo(caption="kept").json()["id"]
    assert circle.ben.anchor(pid, note="that day").status_code == 201

    clock.set(START + timedelta(hours=144))
    sweep()
    row = _photo_row(db, pid)
    assert row.state == "EXPIRED"  # expired exactly on schedule despite the anchor
    assert pid not in _feed_ids(circle.ben)

    with db() as session:
        assert (
            session.scalars(select(PurgeQueueItem).where(PurgeQueueItem.photo_id == pid)).first()
            is None
        )
    assert app.state.storage.exists(row.blob_key)

    # the anchorer's memory thread holds the full artifact
    threads = circle.ben.memories().json()["threads"]
    assert len(threads) == 1
    memory = threads[0]["memories"][0]
    assert memory["tombstone"] is False
    assert memory["note"] == "that day"
    assert memory["urls"] is not None


def test_held_photo_survives_purge_sweep_unheld_neighbor_does_not(circle, clock, sweep, db, app):
    """§8.2 retention, end to end past the tombstone window: sweeps far beyond
    expiry+7d purge the unheld photo and leave the held one whole — blob,
    caption, and the anchorer's memory thread."""
    kept = circle.ana.post_photo(caption="kept").json()["id"]
    lost = circle.ben.post_photo(caption="lost").json()["id"]
    assert circle.cam.anchor(kept).status_code == 201

    clock.set(START + timedelta(hours=144, days=8))  # well past expiry + 7d
    sweep()

    lost_row = _photo_row(db, lost)
    assert lost_row.state == "PURGED"
    assert lost_row.blob_key is None and lost_row.caption is None

    kept_row = _photo_row(db, kept)
    assert kept_row.state == "EXPIRED"  # expired on schedule, never purged
    assert kept_row.caption == "kept"
    assert app.state.storage.exists(kept_row.blob_key)

    memory = circle.cam.memories().json()["threads"][0]["memories"][0]
    assert memory["tombstone"] is False
    assert memory["caption"] == "kept"
    assert memory["urls"] is not None


def test_last_anchor_removed_starts_the_purge_clock(circle, clock, sweep, db, app):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.anchor(pid)
    clock.set(START + timedelta(hours=144))
    sweep()

    clock.set(START + timedelta(hours=150))
    assert circle.ben.unanchor(pid).status_code == 204
    with db() as session:
        item = session.scalars(
            select(PurgeQueueItem).where(PurgeQueueItem.photo_id == pid)
        ).one()
        assert item.purge_after == START + timedelta(hours=150, days=7)

    clock.set(START + timedelta(hours=150, days=7, minutes=1))
    sweep()
    assert _photo_row(db, pid).state == "PURGED"


def test_anchor_window_closes_at_expiry(circle, clock, sweep):
    pid = circle.ana.post_photo().json()["id"]
    clock.set(START + timedelta(hours=121))
    sweep()
    # LAST_LIGHT is the final rescue window — anchoring still works
    assert circle.ben.anchor(pid).status_code == 201
    assert circle.ben.unanchor(pid).status_code == 204

    clock.set(START + timedelta(hours=145))
    sweep()
    r = circle.ben.anchor(pid)
    assert r.status_code == 410
    assert r.json()["detail"]["code"] == "faded"


def test_late_sweep_walks_every_missed_state(circle, clock, sweep, db):
    """A worker that was down for a week still produces a complete, honest
    audit trail, and the purge deadline is computed from the photo's own
    schedule, not from when the sweep happened to run."""
    pid = circle.ana.post_photo().json()["id"]
    clock.set(START + timedelta(hours=150))
    sweep()
    with db() as session:
        audit = session.scalars(
            select(DecayAudit).where(DecayAudit.photo_id == pid).order_by(DecayAudit.id)
        ).all()
        steps = [(a.from_state, a.to_state) for a in audit]
        assert steps == [
            ("LIVE", "FADING"),
            ("FADING", "LAST_LIGHT"),
            ("LAST_LIGHT", "EXPIRED"),
        ]
        item = session.scalars(
            select(PurgeQueueItem).where(PurgeQueueItem.photo_id == pid)
        ).one()
        assert item.purge_after == START + timedelta(hours=144, days=7)


def test_sweep_is_idempotent(circle, clock, sweep, db):
    pid = circle.ana.post_photo().json()["id"]
    clock.set(START + timedelta(hours=49))
    sweep()
    sweep()
    sweep()
    with db() as session:
        audit = session.scalars(select(DecayAudit).where(DecayAudit.photo_id == pid)).all()
    assert len(audit) == 1


def test_feed_order_is_time_only_anchors_cannot_rank(circle, clock):
    """A1, the feed half: anchoring the older photo does not move it."""
    pid_old = circle.ana.post_photo().json()["id"]
    clock.advance(timedelta(hours=24))
    pid_new = circle.ben.post_photo().json()["id"]

    circle.cam.anchor(pid_old)
    ids = [p["id"] for p in circle.cam.feed_photos()]
    assert ids == [pid_new, pid_old]  # newest first, regardless of anchors
