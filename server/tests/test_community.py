"""Shared moments (Part 3) and the circle's board of notes (Part 4). Moments
are a presentation grouping over existing photos — faces, never a score. A
note is a sticky note the day erases, one each, not a chat."""
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


# --- the circle's board: a note each (build 27) --------------------------------------


def put_note(api, circle_id, text):
    return api.client.put(f"/circles/{circle_id}/notes/mine", json={"text": text}, headers=api.h)


def take_down(api, circle_id):
    return api.client.delete(f"/circles/{circle_id}/notes/mine", headers=api.h)


def board(api, circle_id):
    return api.client.get(f"/circles/{circle_id}/notes", headers=api.h).json()["notes"]


def said(notes):
    return [(n["author"]["display_name"], n["text"]) for n in notes]


def test_everyone_pins_their_own_note_and_the_board_shows_them_all(circle, clock):
    r = put_note(circle.ana, circle.id, "lunch at noon, quad")
    assert r.status_code == 200, r.text
    assert set(r.json()) == {"id", "text", "author", "set_at", "updated_at"}
    clock.advance(timedelta(minutes=5))
    put_note(circle.ben, circle.id, "who has a phone charger")
    clock.advance(timedelta(minutes=5))
    put_note(circle.cam, circle.id, "laundry room is free")
    expected = [("cam", "laundry room is free"), ("ben", "who has a phone charger"), ("ana", "lunch at noon, quad")]
    # Newest first, in the feed's first page and on its own.
    assert said(circle.ana.feed().json()["notes"]) == expected
    assert said(board(circle.ben, circle.id)) == expected
    # A build before the board shows one: the newest.
    assert circle.ana.feed().json()["note"]["text"] == "laundry room is free"


def test_writing_again_edits_your_note_and_never_anyone_elses(circle, clock):
    first = put_note(circle.ana, circle.id, "first").json()
    clock.advance(timedelta(minutes=1))
    put_note(circle.ben, circle.id, "ben's")
    clock.advance(timedelta(minutes=30))
    again = put_note(circle.ana, circle.id, "first, fixed").json()
    assert (again["id"], again["set_at"]) == (first["id"], first["set_at"])  # the same note
    assert again["updated_at"] != first["updated_at"]
    assert said(board(circle.cam, circle.id)) == [("ben", "ben's"), ("ana", "first, fixed")]
    # Taking yours down takes only yours.
    assert take_down(circle.ben, circle.id).status_code == 204
    assert said(board(circle.cam, circle.id)) == [("ana", "first, fixed")]
    assert take_down(circle.ben, circle.id).status_code == 204  # nothing left of his to take


def test_the_old_note_path_writes_your_own(circle):
    """A build before the board PUTs /note: it's the caller's own note now,
    never a replacement for someone else's."""
    assert circle.ana.set_note(circle.id, "ana's").status_code == 200
    assert circle.ben.set_note(circle.id, "ben's").status_code == 200
    assert sorted(said(board(circle.cam, circle.id))) == [("ana", "ana's"), ("ben", "ben's")]


def test_notes_clear_at_the_end_of_their_authors_day(circle, clock, sweep, db, app):
    from stanley import decay
    from stanley.models import CircleNote

    old = put_note(circle.ana, circle.id, "today only").json()
    assert said(board(circle.ben, circle.id)) == [("ana", "today only")]
    # Ana's zone is UTC here (she's never posted): midnight is START + 9h.
    clock.advance(timedelta(hours=9))
    assert board(circle.ben, circle.id) == [] and circle.ben.feed().json()["note"] is None
    with db() as s:
        assert decay.clear_notes(s, app.state.clock) == 1
        s.commit()
        assert s.scalars(__import__("sqlalchemy").select(CircleNote)).all() == []
    # The next day's is a new note.
    new = put_note(circle.ana, circle.id, "a new day").json()
    assert new["id"] != old["id"]


def test_tomorrows_note_starts_afresh_even_before_the_sweep(circle, clock):
    put_note(circle.ana, circle.id, "monday")
    clock.advance(timedelta(hours=10))  # past her midnight, no sweep
    r = put_note(circle.ana, circle.id, "tuesday").json()
    assert r["set_at"] == clock.now().isoformat()
    assert said(board(circle.ben, circle.id)) == [("ana", "tuesday")]


def test_a_block_hides_notes_both_ways(circle):
    for api in (circle.ana, circle.ben, circle.cam):
        put_note(api, circle.id, f"{api.name}'s note")
    circle.ana.block(circle.ben.id)
    assert {n["author"]["display_name"] for n in board(circle.ana, circle.id)} == {"ana", "cam"}
    assert {n["author"]["display_name"] for n in board(circle.ben, circle.id)} == {"ben", "cam"}
    assert len(board(circle.cam, circle.id)) == 3


def test_leaving_takes_your_note_off_that_board(circle, client):
    put_note(circle.ben, circle.id, "bye")
    put_note(circle.cam, circle.id, "still here")
    circle.ben.leave(circle.id)
    circle.ana.remove_member(circle.id, circle.cam.id)
    assert board(circle.ana, circle.id) == []


def test_nothing_on_the_board_counts_anyone(circle):
    for api in (circle.ana, circle.ben):
        put_note(api, circle.id, "hello")
    body = circle.cam.client.get(f"/circles/{circle.id}/notes", headers=circle.cam.h).json()
    assert set(body) == {"notes"}
    assert all(set(n) == {"id", "text", "author", "set_at", "updated_at"} for n in body["notes"])


def test_a_note_is_length_bounded_and_needs_words(circle):
    assert put_note(circle.ana, circle.id, "x" * 200).status_code == 200
    assert put_note(circle.ana, circle.id, "x" * 201).status_code == 422
    r = put_note(circle.ana, circle.id, "   ")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "empty_note"


def test_note_requires_membership(client, circle):
    loner = make_user(client, "loner")
    assert loner.set_note(circle.id, "hi").status_code == 409
    assert put_note(loner, circle.id, "hi").status_code == 409
    other = make_user(client, "other")
    elsewhere = other.client.post("/circles", json={"name": "elsewhere"}, headers=other.h).json()["id"]
    assert put_note(circle.ana, elsewhere, "hi").status_code == 404  # not her circle
    assert circle.ana.client.get(f"/circles/{elsewhere}/notes", headers=circle.ana.h).status_code == 404


def test_a_note_can_be_reported_with_a_copy_of_its_words(circle, db, app, clock):
    from stanley import moderation
    from stanley.models import CircleNote, Report

    note = put_note(circle.ben, circle.id, "something cruel").json()
    r = circle.ana.report(note_id=note["id"], reason="cruel")
    assert r.status_code == 201
    with db() as s:
        report = s.get(Report, r.json()["id"])
        assert report.note_id == note["id"]
        assert "something cruel" in report.reason and circle.ben.id in report.reason
        assert moderation.take_down_note(s, note["id"], clock.now())
        s.commit()
        assert s.get(CircleNote, note["id"]) is None
        assert s.get(Report, r.json()["id"]).resolved_at is not None
    assert board(circle.cam, circle.id) == []
    # A note you couldn't see can't be reported: gone, or on another board.
    assert circle.ana.report(note_id="nope", reason="x").status_code == 404
    zed = make_user(circle.ana.client, "zed")
    zed.client.post("/circles", json={"name": "elsewhere"}, headers=zed.h)
    theirs = put_note(circle.ben, circle.id, "on floor 3's board").json()
    assert zed.report(note_id=theirs["id"], reason="x").status_code == 404


def test_an_older_database_moves_its_note_onto_the_board(tmp_path):
    from sqlalchemy import text

    from stanley.db import Base, ensure_schema, make_engine

    engine = make_engine(f"sqlite:///{tmp_path}/old.db")
    Base.metadata.create_all(engine)
    with engine.begin() as conn:
        conn.execute(text("INSERT INTO users (id, display_name, last_light_notice_enabled, digest_enabled, created_at) "
                          "VALUES ('u1', 'ana', 0, 0, '2026-06-01 00:00:00')"))
        conn.execute(text("INSERT INTO circles (id, name, created_by, cap, invite_token, created_at) "
                          "VALUES ('c1', 'floor', 'u1', 100, 'AAAA-BBBB', '2026-06-01 00:00:00')"))
        conn.execute(text("CREATE TABLE community_notes (circle_id VARCHAR(32) PRIMARY KEY, author_id VARCHAR(32), "
                          "body VARCHAR(90), expires_at DATETIME, created_at DATETIME)"))
        conn.execute(text("INSERT INTO community_notes VALUES ('c1', 'u1', 'pizza at 9', "
                          "'2026-06-10 04:00:00.000000', '2026-06-09 15:00:00.000000')"))
        # One pointing at a circle that's gone: left behind, not a failed start.
        conn.execute(text("INSERT INTO community_notes VALUES ('gone', 'u1', 'lost', "
                          "'2026-06-10 04:00:00.000000', '2026-06-09 15:00:00.000000')"))
    ensure_schema(engine)
    with engine.begin() as conn:
        tables = {r[0] for r in conn.execute(text("SELECT name FROM sqlite_master WHERE type='table'"))}
        rows = conn.execute(text("SELECT circle_id, author_id, body, expires_at FROM circle_notes")).all()
    assert "community_notes" not in tables
    assert [tuple(r) for r in rows] == [("c1", "u1", "pizza at 9", "2026-06-10 04:00:00.000000")]
    ensure_schema(engine)  # and again, with nothing left to move
