"""The identity round: profiles carry a name and words, never numbers or
keepings. A2 extends to identity surfaces — your kept grid is yours alone."""
from __future__ import annotations

from sqlalchemy import text

from stanley.db import ensure_schema

from .conftest import jpeg_bytes


def _patch_profile(api, **kw):
    return api.client.patch("/me/profile", json=kw, headers=api.h)


def test_profile_roundtrip_with_multiline_bio(circle):
    bio = "CA on floor 3.\n\nI keep photos of doors for some reason.\nAsk me about the lake."
    r = _patch_profile(circle.ana, display_name="Ana K", username="ana.k", bio=bio)
    assert r.status_code == 200, r.text
    me = circle.ana.client.get("/me", headers=circle.ana.h).json()
    assert me["display_name"] == "Ana K"
    assert me["username"] == "ana.k"
    assert me["bio"] == bio  # newlines preserved verbatim


def test_username_is_unique_and_validated(circle):
    assert _patch_profile(circle.ana, username="floor3").status_code == 200
    r = _patch_profile(circle.ben, username="floor3")
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "username_taken"
    # reclaiming your own username is a no-op, not a conflict
    assert _patch_profile(circle.ana, username="floor3").status_code == 200
    # uppercase is normalized, junk is rejected
    assert _patch_profile(circle.ben, username="BEN").status_code == 200
    assert circle.ben.client.get("/me", headers=circle.ben.h).json()["username"] == "ben"
    for bad in ("ab", "has space", "way" * 20, "emoji✨"):
        assert _patch_profile(circle.cam, username=bad).status_code == 400


def test_member_profile_shows_words_only(circle):
    """The structural guardrail: a member profile payload has no field for
    anchors, kept grids, or counts of any kind."""
    _patch_profile(circle.ana, bio="I keep doors.")
    pid = circle.ana.post_photo().json()["id"]
    circle.ana.anchor(pid, note="mine")  # ana has kept things…

    r = circle.ben.client.get(f"/members/{circle.ana.id}", headers=circle.ben.h)
    assert r.status_code == 200
    payload = r.json()
    assert payload == {
        "id": circle.ana.id,
        "display_name": "ana",
        "username": None,
        "bio": "I keep doors.",
    }
    # …and none of them leak: no anchors, no memories, no numbers
    assert not any("anchor" in k or "count" in k or "memor" in k for k in payload)


def test_member_profile_is_circle_scoped_and_block_aware(client, circle):
    from .conftest import make_user

    stranger = make_user(client, "stranger")
    r = stranger.client.get(f"/members/{circle.ana.id}", headers=stranger.h)
    assert r.status_code == 409  # no circle at all

    circle.ben.block(circle.cam.id)
    r = circle.ben.client.get(f"/members/{circle.cam.id}", headers=circle.ben.h)
    assert r.status_code == 404


def test_location_is_a_label_stored_and_shown(circle):
    r = circle.ana.post_photo(caption="dusk", location="Dunn Meadow")
    assert r.status_code == 201, r.text
    assert r.json()["location"] == "Dunn Meadow"

    feed_photo = circle.ben.feed().json()["photos"][0]
    assert feed_photo["location"] == "Dunn Meadow"
    # a label is all there is — no coordinates anywhere in the payload
    assert not any(("lat" == k or "lng" in k or "coord" in k) for k in feed_photo)

    # kept artifacts carry it too
    circle.ben.anchor(feed_photo["id"])
    memory = circle.ben.memories().json()["threads"][0]["memories"][0]
    assert memory["location"] == "Dunn Meadow"


def test_location_is_optional_and_bounded(circle, clock):
    from datetime import timedelta

    r = circle.ana.post_photo()
    assert r.json()["location"] is None
    clock.advance(timedelta(hours=24))
    r = circle.ana.post_photo(location="x" * 121)
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "location_too_long"


def test_owner_delete_purges_location_with_caption(circle, db):
    from stanley.models import Photo

    pid = circle.ana.post_photo(location="the kitchen").json()["id"]
    circle.ben.anchor(pid)
    circle.ana.delete_photo(pid)
    with db() as session:
        row = session.get(Photo, pid)
    assert row.location is None and row.caption is None


def test_ensure_schema_adds_late_columns(app):
    """Simulate a pilot database created before this round: drop the new
    columns, run the migration, and confirm they come back usable."""
    engine = app.state.engine
    with engine.begin() as conn:
        conn.execute(text("DROP INDEX IF EXISTS uq_users_username"))
        conn.execute(text("ALTER TABLE users DROP COLUMN username"))
        conn.execute(text("ALTER TABLE users DROP COLUMN bio"))
        conn.execute(text("ALTER TABLE photos DROP COLUMN location"))
    added = ensure_schema(engine)
    assert set(added) == {"users.username", "users.bio", "photos.location"}
    assert ensure_schema(engine) == []  # idempotent
