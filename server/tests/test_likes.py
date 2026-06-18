"""The like (Part 1): a heart in the UI, Stanley's physics underneath. Owner
sees faces, never a number; likes decay with the photo and are gone forever
when it leaves Today; no count is stored or returned anywhere."""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import func, select

from stanley.models import Like

from .conftest import START


def test_like_is_owner_visible_as_faces_never_a_count(circle):
    pid = circle.ana.post_photo().json()["id"]
    assert circle.ben.like(pid).status_code == 201
    assert circle.cam.like(pid).status_code == 201

    # caller sees only their own like state on the photo payload
    ben_view = [p for p in circle.ben.feed_photos() if p["id"] == pid][0]
    assert ben_view["liked_by_me"] is True
    assert not any("count" in k for k in ben_view)
    assert "likes" not in ben_view and "liked_by" not in ben_view

    cam_view = [p for p in circle.cam.feed_photos() if p["id"] == pid][0]
    assert cam_view["liked_by_me"] is True

    # owner sees who liked — faces, with no count field
    r = circle.ana.likes_of(pid)
    assert r.status_code == 200
    faces = r.json()["faces"]
    assert {f["display_name"] for f in faces} == {"ben", "cam"}
    assert "count" not in r.json()
    assert all("avatar_url" in f for f in faces)


def test_likes_are_owner_only(circle):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.like(pid)
    assert circle.ben.likes_of(pid).status_code == 403
    assert circle.cam.likes_of(pid).status_code == 403


def test_unlike_removes_it(circle, db):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.like(pid)
    assert circle.ben.unlike(pid).status_code == 204
    assert circle.ana.likes_of(pid).json()["faces"] == []
    with db() as session:
        assert session.scalar(select(func.count()).select_from(Like)) == 0


def test_like_is_idempotent(circle, db):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.like(pid)
    circle.ben.like(pid)
    with db() as session:
        assert session.scalar(select(func.count()).select_from(Like)) == 1


def test_likes_decay_with_the_photo_forever(circle, clock, sweep, db):
    """When the photo leaves Today (EXPIRED), its likes are gone — even for an
    anchored photo whose blob is retained."""
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.like(pid)
    circle.cam.anchor(pid)  # photo retained past expiry

    clock.set(START + timedelta(hours=144))
    sweep()
    with db() as session:
        assert session.scalar(select(func.count()).select_from(Like)) == 0
    assert circle.ana.likes_of(pid).json()["faces"] == []


def test_cannot_like_after_fade(circle, clock, sweep):
    pid = circle.ana.post_photo().json()["id"]
    clock.set(START + timedelta(hours=145))
    sweep()
    r = circle.ben.like(pid)
    assert r.status_code == 410
    assert r.json()["detail"]["code"] == "faded"


def test_blocked_member_cannot_like(circle):
    pid = circle.ben.post_photo().json()["id"]
    circle.ben.block(circle.cam.id)
    assert circle.cam.like(pid).status_code == 404


def test_likes_are_not_in_held_memory_payload(circle, clock, sweep):
    """Held shows the artifact, but likes were never archived — nothing
    like-shaped survives in a memory payload."""
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.like(pid)
    circle.ben.anchor(pid)
    clock.set(START + timedelta(hours=145))
    sweep()
    memory = circle.ben.memories().json()["threads"][0]["memories"][0]
    assert memory["liked_by_me"] is False
    assert not any("count" in k for k in memory)
