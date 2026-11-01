"""What the app's Report, Block and Delete need from the server (build 18):
the people you've blocked, to unblock them; whether deleting a photo gives
the day back, said before it happens; and reports only about what you could
have seen."""
from __future__ import annotations

from datetime import timedelta

from .conftest import make_user


def test_you_see_who_you_blocked_and_never_who_blocked_you(circle):
    assert circle.ana.block(circle.ben.id).status_code == 204
    assert circle.cam.block(circle.ana.id).status_code == 204
    people = circle.ana.client.get("/blocks", headers=circle.ana.h).json()["people"]
    assert [p["id"] for p in people] == [circle.ben.id]
    assert set(people[0]) == {"id", "display_name", "avatar_url"}  # a face and a name, nothing more
    circle.ana.unblock(circle.ben.id)
    assert circle.ana.client.get("/blocks", headers=circle.ana.h).json()["people"] == []


def test_only_the_owner_learns_whether_deleting_gives_the_day_back(circle, clock):
    pid = circle.ana.post_photo().json()["id"]
    mine = next(p for p in circle.ana.feed_photos() if p["id"] == pid)
    assert mine["retake_on_delete"] is True
    theirs = next(p for p in circle.ben.feed_photos() if p["id"] == pid)
    assert theirs["retake_on_delete"] is None

    assert circle.ana.delete_photo(pid).status_code == 204
    again = circle.ana.post_photo().json()["id"]
    redo = next(p for p in circle.ana.feed_photos() if p["id"] == again)
    assert redo["retake_on_delete"] is False  # the day's one redo is spent

    clock.advance(timedelta(days=1))
    assert next(p for p in circle.ana.feed_photos() if p["id"] == again)["retake_on_delete"] is False


def test_a_story_you_couldnt_have_read_cant_be_reported(circle, client):
    pid = circle.ana.post_photo().json()["id"]
    cid = circle.ben.comment(pid, "the fire alarm").json()["id"]
    outsider = make_user(client, "outsider")
    outsider.client.post("/circles", json={"name": "elsewhere"}, headers=outsider.h)
    assert outsider.report(comment_id=cid, reason="spam").status_code == 404
    assert circle.cam.report(comment_id=cid, reason="mean").status_code == 201
