"""The two gestures (§8.2, §8.3) and invariant A2: anchor identities are
owner-only; the circle sees no faces, no counts, no kept badges."""
from __future__ import annotations

from datetime import timedelta


def test_anchor_identities_are_owner_only(circle):
    pid = circle.ana.post_photo().json()["id"]
    assert circle.ben.anchor(pid, note="keeping this").status_code == 201

    # A2, structural half: the photo payload simply has no field for it.
    for viewer in (circle.cam, circle.ben, circle.ana):
        payload = viewer.feed().json()["photos"][0]
        assert "anchors" not in payload
        assert not any("count" in k for k in payload)

    # A2, endpoint half: the owner's quiet list, and only the owner's.
    r = circle.ana.anchors_of(pid)
    assert r.status_code == 200
    names = [a["user"]["display_name"] for a in r.json()["anchors"]]
    assert names == ["ben"]
    assert circle.cam.anchors_of(pid).status_code == 403
    assert circle.ben.anchors_of(pid).status_code == 403


def test_self_anchor_is_the_same_law(circle):
    pid = circle.ana.post_photo().json()["id"]
    assert circle.ana.anchor(pid, note="my own day").status_code == 201
    memory = circle.ana.memories().json()["threads"][0]["memories"][0]
    assert memory["note"] == "my own day"


def test_comments_are_flat_and_chronological(circle, clock):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.comment(pid, "the lake!")
    clock.advance(timedelta(minutes=5))
    circle.cam.comment(pid, "we stayed til midnight")

    payload = circle.ana.feed().json()["photos"][0]
    bodies = [c["body"] for c in payload["comments"]]
    assert bodies == ["the lake!", "we stayed til midnight"]
    authors = [c["author"]["display_name"] for c in payload["comments"]]
    assert authors == ["ben", "cam"]
    # no reply threading exists, structurally
    assert all("parent" not in c and "replies" not in c for c in payload["comments"])


def test_commenting_closes_at_expiry(circle, clock, sweep):
    pid = circle.ana.post_photo().json()["id"]
    clock.advance(timedelta(hours=121))
    sweep()
    assert circle.ben.comment(pid, "still here").status_code == 201  # LAST_LIGHT ok
    clock.advance(timedelta(hours=24))
    sweep()
    assert circle.ben.comment(pid, "too late").status_code == 410


def test_unanchored_expiry_takes_comments_with_it(circle, clock, sweep, db):
    """§8.3: when a photo expires unanchored, its comments expire with it."""
    from sqlalchemy import select

    from stanley.models import Comment

    pid = circle.ana.post_photo().json()["id"]
    circle.ben.comment(pid, "ephemeral")
    clock.advance(timedelta(hours=144, days=7, minutes=5))
    sweep()
    with db() as session:
        remaining = session.scalars(select(Comment).where(Comment.photo_id == pid)).all()
    assert remaining == []


def test_anchored_artifact_keeps_photo_caption_and_comments(circle, clock, sweep):
    pid = circle.ana.post_photo(caption="bonfire").json()["id"]
    circle.ben.comment(pid, "best night")
    circle.ben.anchor(pid)
    clock.advance(timedelta(hours=145))
    sweep()
    memory = circle.ben.memories().json()["threads"][0]["memories"][0]
    assert memory["tombstone"] is False
    assert memory["caption"] == "bonfire"
    assert [c["body"] for c in memory["comments"]] == ["best night"]
