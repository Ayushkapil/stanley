"""Profiles as pages of the shared journal (build 19): since when, a quiet
organizer mark, and the photos still in the light. No number about anyone on
anyone else's screen: how many moments you've shared is on /me alone. And a
story's @mentions are stored as written, @[user id], for the app to resolve."""
from __future__ import annotations

from datetime import timedelta

from .conftest import make_user


def _member(viewer, who):
    r = viewer.client.get(f"/members/{who.id}", headers=viewer.h)
    assert r.status_code == 200, r.text
    return r.json()


def test_a_profile_is_a_page_not_a_scoreboard(circle):
    page = _member(circle.ben, circle.ana)
    assert set(page) == {
        "id", "display_name", "username", "bio", "avatar_url",
        "member_since", "is_organizer", "photos",
    }
    assert page["is_organizer"] is True and page["member_since"]
    assert _member(circle.ana, circle.ben)["is_organizer"] is False


def test_their_photos_still_in_the_light(circle, clock, sweep, client):
    first = circle.ben.post_photo(caption="first").json()["id"]
    assert [p["id"] for p in _member(circle.ana, circle.ben)["photos"]] == [first]
    # A circle Ben is in and Ana isn't: not hers to see.
    elsewhere = make_user(client, "dee")
    made = elsewhere.client.post("/circles", json={"name": "elsewhere"}, headers=elsewhere.h).json()
    assert circle.ben.join(made["invite_token"]).status_code == 201
    circle.ben.circle_id = made["id"]
    there = circle.ben.post_photo(caption="elsewhere")
    assert there.status_code == 201
    circle.ben.circle_id = None
    assert [p["id"] for p in _member(elsewhere, circle.ben)["photos"]] == [there.json()["id"]]
    assert [p["id"] for p in _member(circle.ana, circle.ben)["photos"]] == [first]
    # Past its public life, it leaves the page as it leaves Today.
    clock.advance(timedelta(hours=150))
    sweep()
    assert _member(circle.ana, circle.ben)["photos"] == []


def test_how_many_moments_is_yours_alone(circle, clock, sweep):
    me = lambda: circle.ana.client.get("/me", headers=circle.ana.h).json()["moments_shared"]
    assert me() == 0
    pid = circle.ana.post_photo().json()["id"]
    assert me() == 1
    circle.ana.delete_photo(pid)  # today's, redone: it didn't happen
    assert me() == 0
    circle.ana.post_photo()
    clock.advance(timedelta(days=14))  # faded and purged: it still happened
    sweep()
    sweep()
    assert me() == 1
    assert "moments_shared" not in _member(circle.ben, circle.ana)


def test_a_mention_is_stored_as_written(circle):
    pid = circle.ana.post_photo().json()["id"]
    body = f"remember when @[{circle.ben.id}] fell asleep in the lounge"
    assert circle.cam.comment(pid, body).status_code == 201
    stories = next(p for p in circle.ana.feed_photos() if p["id"] == pid)["comments"]
    assert stories[0]["body"] == body
