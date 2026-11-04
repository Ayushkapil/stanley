"""Deleting an account leaves nothing of the person (build 18, for the
Privacy Policy): what's left is a bare row for tombstones to point at, with
no name, username, words, time zone or settings, and nothing they wrote or
were sent is kept against it."""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from stanley.models import CircleNote, Comment, NotificationLog, Report, ReturnedLog, User

from .conftest import NY


def test_nothing_of_the_person_is_left(circle, db, app):
    ben = circle.ben
    assert ben.client.patch(
        "/me/profile", json={"username": "benny", "bio": "third floor, by the stairs"}, headers=ben.h
    ).status_code == 200
    ben.patch_settings(last_light_notice_enabled=True, digest_enabled=True)
    assert ben.set_note(circle.id, "pizza in the lounge").status_code in (200, 201)
    circle.ana.post_photo()
    ben.returned(tz=NY)
    with app.state.sessionmaker() as session:
        app.state.notifier.send(session, ben.id, "digest", "Something new from your circle today.", app.state.clock.now())
        session.commit()

    assert ben.delete_me().status_code == 204

    with db() as s:
        user = s.get(User, ben.id)
        assert user.deleted_at is not None
        assert (user.display_name, user.username, user.bio, user.apple_sub, user.avatar_key) == (None,) * 5
        assert user.tz_last_seen is None
        assert not user.last_light_notice_enabled and not user.digest_enabled
        assert s.scalars(select(CircleNote).where(CircleNote.author_id == ben.id)).all() == []
        assert s.scalars(select(NotificationLog).where(NotificationLog.user_id == ben.id)).all() == []
        assert s.scalars(select(ReturnedLog).where(ReturnedLog.user_id == ben.id)).all() == []


def test_a_reported_story_doesnt_stop_its_author_leaving(circle, db):
    pid = circle.ana.post_photo().json()["id"]
    cid = circle.ben.comment(pid, "remember the fire alarm").json()["id"]
    assert circle.cam.report(comment_id=cid, reason="mean").status_code == 201

    assert circle.ben.delete_me().status_code == 204

    with db() as s:
        report = s.scalars(select(Report)).one()
        # The report stays, so it can still be reviewed; the words are gone.
        assert report.comment_id is None and report.reason == "mean"


def test_a_reported_story_doesnt_stop_the_photo_being_deleted(circle):
    pid = circle.ana.post_photo().json()["id"]
    cid = circle.ben.comment(pid, "remember the fire alarm").json()["id"]
    circle.cam.report(comment_id=cid, reason="mean")
    assert circle.ana.delete_photo(pid).status_code == 204


def test_a_reported_story_doesnt_stop_the_purge(circle, clock, sweep, db):
    pid = circle.ana.post_photo().json()["id"]
    cid = circle.ben.comment(pid, "remember the fire alarm").json()["id"]
    circle.cam.report(comment_id=cid, reason="mean")
    clock.advance(timedelta(days=14))  # past its six days and the tombstone week
    sweep()
    sweep()
    with db() as s:
        assert s.get(Comment, cid) is None
        report = s.scalars(select(Report)).one()
        assert (report.comment_id, report.photo_id) == (None, pid)
