"""The circle-post notice (build 37, §10 N5): "{name} shared a moment", to
the people in the circle a photo was posted to who turned it on. Off until
asked for, never to the poster, never across a block, never twice for one
person's day in one circle, and handed to Apple only after the response."""
from __future__ import annotations

import re
from datetime import timedelta

from sqlalchemy import select

from stanley.models import NotificationLog
from stanley.notifications import Notifier

from .conftest import make_user


def _notices(db, kind="circle_post"):
    with db() as s:
        return [
            (n.user_id, n.body)
            for n in s.scalars(select(NotificationLog).where(NotificationLog.kind == kind)).all()
        ]


def test_it_is_off_until_asked_for(circle, db):
    me = circle.ben.client.get("/me", headers=circle.ben.h).json()
    assert me["circle_posts_enabled"] is False
    assert circle.ana.post_photo().status_code == 201
    assert _notices(db) == []


def test_turning_it_on_leaves_the_other_two_alone(circle):
    r = circle.ben.patch_settings(circle_posts_enabled=True)
    assert r.json() == {
        "last_light_notice_enabled": False,
        "digest_enabled": False,
        "circle_posts_enabled": True,
        "note_reminder_enabled": False,
        "note_reminder_hour": 9,
        "photo_reminder_enabled": False,
        "photo_reminder_hour": 18,
    }
    me = circle.ben.client.get("/me", headers=circle.ben.h).json()
    assert me["circle_posts_enabled"] is True
    assert me["digest_enabled"] is False


def test_whoever_asked_hears_who_shared_a_moment(circle, db):
    circle.ben.patch_settings(circle_posts_enabled=True)
    assert circle.ana.post_photo(caption="the lake", location="Griffy").status_code == 201
    # Ben asked; Cam didn't; Ana posted it.
    assert _notices(db) == [(circle.ben.id, "ana shared a moment")]


def test_the_words_are_a_name_and_nothing_else(circle, db):
    circle.ben.patch_settings(circle_posts_enabled=True)
    circle.ana.post_photo(caption="12 of us at the lake", location="Griffy")
    [(_, body)] = _notices(db)
    assert not re.search(r"\d", body)
    assert "lake" not in body and "Griffy" not in body


def test_never_to_the_poster(circle, db):
    circle.ana.patch_settings(circle_posts_enabled=True)
    circle.ana.post_photo()
    assert _notices(db) == []


def test_only_the_circle_it_was_posted_to(circle, db, client):
    """Dee shares another circle with Ana, not this one."""
    dee = make_user(client, "dee")
    r = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h)
    assert dee.join(r.json()["invite_token"]).status_code == 201
    dee.patch_settings(circle_posts_enabled=True)
    circle.ben.patch_settings(circle_posts_enabled=True)
    circle.ana.circle_id = circle.id
    circle.ana.post_photo()
    assert _notices(db) == [(circle.ben.id, "ana shared a moment")]


def test_a_block_either_way_means_no_notice(circle, db):
    circle.ben.patch_settings(circle_posts_enabled=True)
    circle.cam.patch_settings(circle_posts_enabled=True)
    circle.ben.block(circle.ana.id)  # Ben blocked the poster
    circle.ana.block(circle.cam.id)  # the poster blocked Cam
    circle.ana.post_photo()
    assert _notices(db) == []


def test_the_days_retake_is_not_news_twice(circle, db):
    circle.ben.patch_settings(circle_posts_enabled=True)
    pid = circle.ana.post_photo().json()["id"]
    circle.ana.delete_photo(pid)
    assert circle.ana.post_photo(caption="again").status_code == 201
    assert _notices(db) == [(circle.ben.id, "ana shared a moment")]


def test_the_next_day_is_news_again(circle, db, clock):
    circle.ben.patch_settings(circle_posts_enabled=True)
    circle.ana.post_photo()
    clock.advance(timedelta(hours=30))
    circle.ana.post_photo()
    assert len(_notices(db)) == 2


def test_a_refused_post_tells_nobody(circle, db):
    circle.ben.patch_settings(circle_posts_enabled=True)
    circle.ana.post_photo()
    assert circle.ana.post_photo().status_code == 409  # the day is spent
    assert len(_notices(db)) == 1


def test_turning_it_off_stops_it(circle, db):
    circle.ben.patch_settings(circle_posts_enabled=True)
    circle.ben.patch_settings(circle_posts_enabled=False)
    circle.ana.post_photo()
    assert _notices(db) == []


def test_a_deleted_account_hears_nothing(circle, db):
    circle.ben.patch_settings(circle_posts_enabled=True)
    assert circle.ben.delete_me().status_code in (200, 204)
    circle.ana.post_photo()
    assert _notices(db) == []


def test_it_reaches_apple_after_the_response(circle, app, db):
    """Handed to the transport as a background task, once the post has
    committed and answered, so posting never waits on a push."""
    delivered = []
    app.state.notifier = Notifier(lambda user_id, kind, body: delivered.append((user_id, kind, body)))
    circle.ben.patch_settings(circle_posts_enabled=True)
    assert circle.ana.post_photo().status_code == 201
    assert delivered == [(circle.ben.id, "circle_post", "ana shared a moment")]
    assert _notices(db) == [(circle.ben.id, "ana shared a moment")]


def test_a_failed_push_never_fails_the_post(circle, app, db):
    def broken(*_):
        raise RuntimeError("apple is down")

    app.state.notifier = Notifier(broken)
    circle.ben.patch_settings(circle_posts_enabled=True)
    assert circle.ana.post_photo().status_code == 201
    assert len(_notices(db)) == 1


def test_the_digest_is_still_its_own_switch(circle, db):
    circle.ben.patch_settings(digest_enabled=True)
    circle.ana.post_photo()
    assert _notices(db) == []
