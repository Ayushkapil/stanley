"""Build 53: the photo on a journal's cover.

The brief asked for each journal's most-kept photo. That ranks photos by
keeps and would let a circle see which one was kept most, so (a product
decision, 2026-11-14, kept again on 2026-11-16) it isn't. Your own book's
cover is your own newest keep; since build 76 a circle's is the circle's
newest photo still in the light, the same for everyone in it. Nothing
about anyone else's keeps is in it, and no keep is counted."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from .conftest import make_user

UTC = timezone.utc


def circles(api):
    return {c["name"]: c for c in api.client.get("/circles", headers=api.h).json()["circles"]}


def my_cover(api):
    return api.client.get("/me/journal", headers=api.h).json()["cover_photo_id"]


def test_no_photo_no_cover(circle):
    assert circles(circle.ben)["floor 3"]["cover_photo_id"] is None
    assert circles(circle.ben)["floor 3"]["cover_url"] is None
    assert my_cover(circle.ben) is None


def test_no_keep_the_newest_photo_still_in_the_light(circle, clock):
    """With nothing kept, a circle's cover is its newest photo, and your
    own book's is your own newest: never bare while there are photos."""
    first = circle.ana.post_photo().json()["id"]
    clock.advance(timedelta(minutes=1))
    newest = circle.cam.post_photo().json()["id"]
    assert circles(circle.ben)["floor 3"]["cover_photo_id"] == newest
    assert my_cover(circle.ben) is None
    assert my_cover(circle.ana) == first


def test_a_faded_photo_is_never_a_cover_unless_you_kept_it(circle, clock, sweep):
    pid = circle.ana.post_photo().json()["id"]
    clock.advance(timedelta(hours=145))
    sweep()
    assert circles(circle.ben)["floor 3"]["cover_photo_id"] is None
    assert my_cover(circle.ana) is None


def test_the_cover_comes_with_a_signed_link(circle, client):
    pid = circle.ana.post_photo().json()["id"]
    c = circles(circle.ben)["floor 3"]
    assert c["cover_photo_id"] == pid
    assert c["cover_url"].startswith("/blobs/") and "sig=" in c["cover_url"]
    assert client.get(c["cover_url"]).status_code == 200
    journal = circle.ana.client.get("/me/journal", headers=circle.ana.h).json()
    assert journal["cover_url"] and "sig=" in journal["cover_url"]


def test_the_first_day_is_the_first_page_you_can_read(circle, clock):
    """An empty journal says nothing about when it began."""
    assert circles(circle.ben)["floor 3"]["first_day"] is None
    r = circle.ana.client.put(
        "/me/journal/today",
        json={"body": "first", "ink": "black", "tz": "America/New_York", "shared": True},
        headers=dict(circle.ana.h, **{"X-Stanley-Circle": circle.id}),
    )
    assert r.status_code == 200, r.text
    assert circles(circle.ben)["floor 3"]["first_day"] == "2026-06-09"
    circle.ben.block(circle.ana.id)
    assert circles(circle.ben)["floor 3"]["first_day"] is None


def test_your_own_cover_is_your_own_newest_keep(circle, clock):
    first = circle.ana.post_photo().json()["id"]
    clock.advance(timedelta(minutes=1))
    second = circle.cam.post_photo().json()["id"]
    assert circle.ben.anchor(second).status_code in (200, 201)
    clock.advance(timedelta(minutes=5))
    assert circle.ben.anchor(first).status_code in (200, 201)
    # Kept last, so it's your book's cover, though it was posted first;
    # the circle's is its newest photo, whatever anyone kept (build 76).
    assert my_cover(circle.ben) == first
    assert circles(circle.ben)["floor 3"]["cover_photo_id"] == second


def test_keeps_never_make_a_cover(circle, clock):
    """However many keep a photo, a circle's cover is its newest photo, the
    same for everyone; your own book's is your own newest keep, never
    anyone else's."""
    popular = circle.ana.post_photo().json()["id"]
    clock.advance(timedelta(minutes=1))
    newest = circle.cam.post_photo().json()["id"]
    for api in (circle.ana, circle.ben):
        api.anchor(popular)
    clock.advance(timedelta(minutes=1))
    circle.ben.anchor(newest)
    clock.advance(timedelta(minutes=1))
    circle.cam.anchor(popular)
    for api in (circle.ana, circle.ben, circle.cam):
        assert circles(api)["floor 3"]["cover_photo_id"] == newest
    assert my_cover(circle.ben) == newest
    assert my_cover(circle.cam) == popular


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
