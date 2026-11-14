"""Build 53: the photo on a journal's cover.

The brief asked for each journal's most-kept photo. That ranks photos by
keeps and would let a circle see which one was kept most, so (a product
decision, 2026-11-14) a cover is the reader's own newest keep: in that
circle for its journal, anywhere for their own. Nothing about anyone
else's keeps is in it, and no keep is counted."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from .conftest import make_user

UTC = timezone.utc


def circles(api):
    return {c["name"]: c for c in api.client.get("/circles", headers=api.h).json()["circles"]}


def my_cover(api):
    return api.client.get("/me/journal", headers=api.h).json()["cover_photo_id"]


def test_no_keep_no_cover(circle):
    circle.ana.post_photo()
    assert circles(circle.ben)["floor 3"]["cover_photo_id"] is None
    assert my_cover(circle.ben) is None


def test_the_cover_is_your_own_newest_keep(circle, clock):
    first = circle.ana.post_photo().json()["id"]
    second = circle.cam.post_photo().json()["id"]
    assert circle.ben.anchor(second).status_code in (200, 201)
    clock.advance(timedelta(minutes=5))
    assert circle.ben.anchor(first).status_code in (200, 201)
    # Kept last, so it's the cover, though it was posted first.
    assert circles(circle.ben)["floor 3"]["cover_photo_id"] == first
    assert my_cover(circle.ben) == first


def test_someone_elses_keeps_never_make_your_cover(circle, clock):
    """However many keep a photo, it's on your cover only if you kept it."""
    popular = circle.ana.post_photo().json()["id"]
    mine = circle.cam.post_photo().json()["id"]
    for api in (circle.ana, circle.cam):
        api.anchor(popular)
    clock.advance(timedelta(minutes=1))
    circle.ben.anchor(mine)
    assert circles(circle.ben)["floor 3"]["cover_photo_id"] == mine
    # And Ben, who kept nothing of Ana's, is never shown hers.
    assert circles(circle.ana)["floor 3"]["cover_photo_id"] == popular


def test_each_circle_has_its_own_cover_and_yours_spans_them(circle, client, clock):
    dee = make_user(client, "dee")
    r = circle.ben.client.post("/circles", json={"name": "climbing"}, headers=circle.ben.h)
    climbing = r.json()
    assert dee.join(climbing["invite_token"]).status_code == 201
    on_floor = circle.ana.post_photo().json()["id"]
    dee.circle_id = climbing["id"]
    on_wall = dee.post_photo().json()["id"]
    circle.ben.anchor(on_floor)
    clock.advance(timedelta(minutes=1))
    circle.ben.anchor(on_wall)
    seen = circles(circle.ben)
    assert seen["floor 3"]["cover_photo_id"] == on_floor
    assert seen["climbing"]["cover_photo_id"] == on_wall
    assert my_cover(circle.ben) == on_wall


def test_a_deleted_photo_or_one_across_a_block_is_no_cover(circle, clock):
    older = circle.cam.post_photo().json()["id"]
    newer = circle.ana.post_photo().json()["id"]
    circle.ben.anchor(older)
    clock.advance(timedelta(minutes=1))
    circle.ben.anchor(newer)
    assert my_cover(circle.ben) == newer
    circle.ben.block(circle.ana.id)
    assert my_cover(circle.ben) == older
    assert circles(circle.ben)["floor 3"]["cover_photo_id"] == older
    circle.cam.delete_photo(older)
    assert my_cover(circle.ben) is None


def test_the_volume_begins_the_day_you_joined(circle, clock):
    assert circles(circle.ben)["floor 3"]["since"] == "2026-06-09"


def test_nothing_on_a_cover_counts_anything(circle):
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.anchor(pid)
    for c in circle.ben.client.get("/circles", headers=circle.ben.h).json()["circles"]:
        assert not any("count" in key or "keeps" in key or "anchors" in key for key in c)
