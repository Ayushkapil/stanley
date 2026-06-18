"""Shared moments (Part 3) and the community note (Part 4). Moments are a
presentation grouping over existing photos — faces, never a score. The note is
a sticky line the day erases, not a chat."""
from __future__ import annotations

from datetime import timedelta

from .conftest import make_user


# --- shared moments ----------------------------------------------------------


def _moments(items):
    return [i for i in items if i["kind"] == "moment"]


def _photo_items(items):
    return [i for i in items if i["kind"] == "photo"]


def test_two_people_same_place_make_a_moment(circle):
    a = circle.ana.post_photo(location="Dunn Meadow").json()["id"]
    b = circle.ben.post_photo(location="  dunn meadow ").json()["id"]  # case/space differ
    c = circle.cam.post_photo(location="The Library").json()["id"]  # singleton place

    items = circle.cam.feed_items()
    moments = _moments(items)
    assert len(moments) == 1
    m = moments[0]
    assert {p["id"] for p in m["photos"]} == {a, b}
    assert {f["display_name"] for f in m["members"]} == {"ana", "ben"}
    assert m["location"].strip().lower() == "dunn meadow"  # original-cased label
    # a count never appears on the moment — faces only
    assert not any("count" in k for k in m)

    # cam's lone-place photo stays a standalone photo, not a moment
    assert c in {i["photo"]["id"] for i in _photo_items(items)}


def test_singleton_location_is_not_a_moment(circle):
    circle.ana.post_photo(location="My Desk")
    items = circle.ben.feed_items()
    assert _moments(items) == []
    assert len(_photo_items(items)) == 1


def test_no_location_photos_never_group(circle):
    circle.ana.post_photo()
    circle.ben.post_photo()
    assert _moments(circle.cam.feed_items()) == []


def test_each_photo_in_a_moment_keeps_its_own_like_and_held(circle):
    a = circle.ana.post_photo(location="Lake").json()["id"]
    b = circle.ben.post_photo(location="Lake").json()["id"]

    circle.cam.like(a)      # like only a
    circle.cam.anchor(b)    # hold only b

    assert {f["display_name"] for f in circle.ana.likes_of(a).json()["faces"]} == {"cam"}
    assert circle.ben.likes_of(b).json()["faces"] == []
    assert [x["user"]["display_name"] for x in circle.ben.anchors_of(b).json()["anchors"]] == ["cam"]
    assert circle.ana.anchors_of(a).json()["anchors"] == []


def test_block_can_dissolve_a_moment(circle):
    a = circle.ana.post_photo(location="Quad").json()["id"]
    b = circle.ben.post_photo(location="Quad").json()["id"]

    assert len(_moments(circle.cam.feed_items())) == 1  # cam sees the pair

    circle.ben.block(circle.ana.id)
    items = circle.ben.feed_items()
    assert _moments(items) == []  # ana's photo hidden -> only ben's at Quad
    assert b in {i["photo"]["id"] for i in _photo_items(items)}
    assert a not in {i["photo"]["id"] for i in _photo_items(items)}


def test_moment_photo_fades_on_its_own_schedule(circle, clock, sweep):
    from .conftest import START

    a = circle.ana.post_photo(location="Trail").json()["id"]
    b = circle.ben.post_photo(location="Trail").json()["id"]
    assert len(_moments(circle.cam.feed_items())) == 1

    clock.set(START + timedelta(hours=145))  # both expire together (same day)
    sweep()
    items = circle.cam.feed_items()
    assert items == []  # the whole moment has left Today


# --- community note ----------------------------------------------------------


def test_note_set_and_shown_with_author(circle):
    r = circle.ana.set_note(circle.id, "lunch at noon, quad")
    assert r.status_code == 200, r.text
    note = circle.ben.feed().json()["note"]
    assert note["text"] == "lunch at noon, quad"
    assert note["author"]["display_name"] == "ana"
    # it is a line, not a chat: no replies/reactions fields exist
    assert set(note.keys()) == {"text", "author", "set_at"}


def test_note_last_writer_wins(circle):
    circle.ana.set_note(circle.id, "first")
    circle.ben.set_note(circle.id, "second")
    note = circle.cam.feed().json()["note"]
    assert note["text"] == "second"
    assert note["author"]["display_name"] == "ben"


def test_note_clears_at_end_of_local_day(circle, clock):
    from .conftest import START

    circle.ana.set_note(circle.id, "today only")
    assert circle.ben.feed().json()["note"]["text"] == "today only"
    # ana's tz is UTC here (never posted); note expires at next UTC midnight,
    # which is START (15:00) + 9h. Step past it.
    clock.advance(timedelta(hours=10))
    assert circle.ben.feed().json()["note"] is None


def test_note_is_length_bounded(circle):
    assert circle.ana.set_note(circle.id, "x" * 90).status_code == 200
    assert circle.ana.set_note(circle.id, "x" * 91).status_code == 422


def test_note_requires_membership(client, circle):
    loner = make_user(client, "loner")
    r = loner.set_note(circle.id, "hi")
    assert r.status_code == 409
