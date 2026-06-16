"""Warmth (Part 5): the light, ephemeral gesture. Owner sees faces, never a
number; warmth decays with the photo and is gone forever when it leaves Today;
no count is stored or returned anywhere."""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import func, select

from stanley.models import Warmth

from .conftest import START


def test_warm_is_owner_visible_as_faces_never_a_count(circle):
    pid = circle.ana.post_photo().json()["id"]
    assert circle.ben.warm(pid).status_code == 201
    assert circle.cam.warm(pid).status_code == 201

    # caller sees only their own warmth state on the photo payload
    ben_view = circle.ben.feed().json()["photos"][0]
    assert ben_view["warmed_by_me"] is True
    assert not any("count" in k for k in ben_view)
    assert "warmth" not in ben_view and "warmed_by" not in ben_view

    cam_unwarmed = [p for p in circle.cam.feed().json()["photos"] if p["id"] == pid][0]
    assert cam_unwarmed["warmed_by_me"] is True  # cam warmed it too

    # owner sees who warmed — faces, with no count field
    r = circle.ana.warmth_of(pid)
    assert r.status_code == 200
    faces = r.json()["faces"]
    assert {f["display_name"] for f in faces} == {"ben", "cam"}
    assert "count" not in r.json()
    assert all("avatar_url" in f for f in faces)


def test_warmth_is_owner_only(circle):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.warm(pid)
    # only the owner may see the faces
    assert circle.ben.warmth_of(pid).status_code == 403
    assert circle.cam.warmth_of(pid).status_code == 403


def test_unwarm_removes_it(circle, db):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.warm(pid)
    assert circle.ben.unwarm(pid).status_code == 204
    assert circle.ana.warmth_of(pid).json()["faces"] == []
    with db() as session:
        assert session.scalar(select(func.count()).select_from(Warmth)) == 0


def test_warm_is_idempotent(circle, db):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.warm(pid)
    circle.ben.warm(pid)
    with db() as session:
        assert session.scalar(select(func.count()).select_from(Warmth)) == 1


def test_warmth_decays_with_the_photo_forever(circle, clock, sweep, db):
    """When the photo leaves Today (EXPIRED), its warmth is gone — even for an
    anchored photo whose blob is retained."""
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.warm(pid)
    circle.cam.anchor(pid)  # photo will be retained past expiry

    clock.set(START + timedelta(hours=144))
    sweep()
    with db() as session:
        assert session.scalar(select(func.count()).select_from(Warmth)) == 0
    # and there's no way to see it again — owner's faces list is empty
    assert circle.ana.warmth_of(pid).json()["faces"] == []


def test_cannot_warm_after_fade(circle, clock, sweep):
    pid = circle.ana.post_photo().json()["id"]
    clock.set(START + timedelta(hours=145))
    sweep()
    r = circle.ben.warm(pid)
    assert r.status_code == 410
    assert r.json()["detail"]["code"] == "faded"


def test_blocked_member_cannot_warm(circle):
    pid = circle.ben.post_photo().json()["id"]
    circle.ben.block(circle.cam.id)
    assert circle.cam.warm(pid).status_code == 404


def test_warmth_is_not_in_held_memory_payload(circle, clock, sweep):
    """Held shows the artifact, but warmth was never archived — there's nothing
    warmth-shaped in a memory payload."""
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.warm(pid)
    circle.ben.anchor(pid)
    clock.set(START + timedelta(hours=145))
    sweep()
    memory = circle.ben.memories().json()["threads"][0]["memories"][0]
    assert memory["warmed_by_me"] is False
    assert not any("count" in k for k in memory)
