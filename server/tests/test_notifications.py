"""§10 as executable policy. The temptation to use decay urgency for
re-engagement will be constant; these tests are the line."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select, text

from stanley import notifications
from stanley.db import ensure_schema
from stanley.models import NotificationLog, PushToken, User

from .conftest import NY, START, make_user

UTC = timezone.utc


def _logs(db, **filters):
    with db() as session:
        q = select(NotificationLog)
        for key, value in filters.items():
            q = q.where(getattr(NotificationLog, key) == value)
        return session.scalars(q).all()


def test_last_light_notice_is_off_by_default(circle, clock, sweep, db):
    circle.ana.post_photo()
    clock.set(START + timedelta(hours=121))
    sweep()
    assert _logs(db) == []


def test_last_light_notice_fires_once_and_carries_no_numbers(circle, clock, sweep, db):
    circle.ana.patch_settings(last_light_notice_enabled=True)
    circle.ana.post_photo()
    clock.set(START + timedelta(hours=121))
    sweep()
    clock.set(START + timedelta(hours=130))
    sweep()

    rows = _logs(db, kind="last_light")
    assert len(rows) == 1
    assert rows[0].user_id == circle.ana.id
    assert "Tuesday" in rows[0].body
    # N4: no deadline timestamp, no countdown — no digits at all
    assert not any(ch.isdigit() for ch in rows[0].body)


def test_gestures_are_silent(circle, db):
    """N5: no notifications for anchors received, comments, or others' fades."""
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.anchor(pid, note="!")
    circle.ben.comment(pid, "what a day")
    circle.cam.anchor(pid)
    assert _logs(db) == []


def test_evening_digest_at_most_one_per_day(circle, clock, app, db):
    circle.ben.post_photo()
    circle.cam.post_photo()
    circle.ana.returned(tz=NY)  # records ana's timezone

    # 20:00 in New York on June 9
    clock.set(datetime(2026, 6, 10, 0, 0, tzinfo=UTC))

    def run():
        with app.state.sessionmaker() as session:
            n = notifications.run_evening_digests(
                session, app.state.notifier, app.state.clock, app.state.settings.digest_hour
            )
            session.commit()
        return n

    run()
    ana_rows = _logs(db, user_id=circle.ana.id, kind="digest")
    assert len(ana_rows) == 1
    # Two others posted; the words say so without a number (N4).
    assert ana_rows[0].body == notifications.DIGEST_BODY
    assert not any(ch.isdigit() for ch in ana_rows[0].body)

    # N1: running the job again the same evening sends nothing new
    run()
    assert len(_logs(db, user_id=circle.ana.id, kind="digest")) == 1
    for user in (circle.ana, circle.ben, circle.cam):
        assert len(_logs(db, user_id=user.id, kind="digest")) <= 1


def test_quiet_day_sends_no_digest(circle, clock, app, db):
    circle.ana.returned(tz=NY)
    clock.set(datetime(2026, 6, 10, 0, 0, tzinfo=UTC))
    with app.state.sessionmaker() as session:
        notifications.run_evening_digests(
            session, app.state.notifier, app.state.clock, app.state.settings.digest_hour
        )
        session.commit()
    assert _logs(db, kind="digest") == []


# --- N3: circle posts -------------------------------------------------------

def _opt_in(*users):
    for i, user in enumerate(users):
        assert user.patch_settings(circle_post_notice_enabled=True).status_code == 200
        assert user.register_device(f"{i:02d}" + "ab" * 31).status_code == 204


def test_circle_post_notice_is_off_by_default(circle, db):
    me = circle.ben.client.get("/me", headers=circle.ben.h).json()
    assert me["circle_post_notice_enabled"] is False
    circle.ben.register_device("ab" * 32)  # a device alone asks for nothing
    circle.ana.post_photo()
    assert _logs(db, kind=notifications.CIRCLE_POST) == []


def test_circle_post_reaches_opted_in_members_with_a_device(circle, db):
    _opt_in(circle.ana, circle.ben)
    # cam asked for it but has no device to tell.
    circle.cam.patch_settings(circle_post_notice_enabled=True)
    assert circle.ana.post_photo().status_code == 201

    rows = _logs(db, kind=notifications.CIRCLE_POST)
    assert [r.user_id for r in rows] == [circle.ben.id]  # never the poster
    assert rows[0].body == "ana shared a moment"
    assert not any(ch.isdigit() for ch in rows[0].body)  # N4


def test_circle_post_never_crosses_a_block(circle, client, db):
    dee = make_user(client, "dee")
    assert dee.join(circle.invite_token).status_code == 201
    _opt_in(circle.ben, circle.cam, dee)
    circle.ben.block(circle.ana.id)  # ben blocked the poster
    circle.ana.block(circle.cam.id)  # the poster blocked cam
    circle.ana.post_photo()
    assert [r.user_id for r in _logs(db, kind=notifications.CIRCLE_POST)] == [dee.id]


def test_circle_post_from_a_nameless_member_still_names_a_person(circle, db):
    _opt_in(circle.ben)
    with db() as session:
        session.get(User, circle.ana.id).display_name = None
        session.commit()
    circle.ana.post_photo()
    rows = _logs(db, kind=notifications.CIRCLE_POST)
    assert rows[0].body == "New member shared a moment"


def test_a_failed_capture_announces_nothing(circle, db):
    _opt_in(circle.ben)
    assert circle.ana.post_photo().status_code == 201
    assert circle.ana.post_photo().status_code == 409  # the day is spent
    assert len(_logs(db, kind=notifications.CIRCLE_POST)) == 1


def test_a_device_belongs_to_whoever_registered_it_last(circle, db):
    token = "cd" * 32
    for user in (circle.ben, circle.cam):
        user.patch_settings(circle_post_notice_enabled=True)
    circle.ben.register_device(token)
    circle.cam.register_device(token)  # the phone changed hands
    circle.ana.post_photo()
    assert [r.user_id for r in _logs(db, kind=notifications.CIRCLE_POST)] == [circle.cam.id]

    # ben can't unregister a device that is no longer his; cam can.
    assert circle.ben.forget_device(token).status_code == 204
    with db() as session:
        assert session.get(PushToken, token).user_id == circle.cam.id
    assert circle.cam.forget_device(token).status_code == 204
    with db() as session:
        assert session.get(PushToken, token) is None


def test_with_circle_posts_on_gestures_stay_silent(circle, db):
    _opt_in(circle.ana, circle.ben, circle.cam)
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.anchor(pid)
    circle.ben.like(pid)
    circle.ben.comment(pid, "what a day")
    circle.cam.anchor(pid)
    circle.cam.set_note(circle.id, "pizza at 8")
    # N5: the two circle-post notices for ana's photo, and nothing else.
    assert {r.kind for r in _logs(db)} == {notifications.CIRCLE_POST}
    assert len(_logs(db)) == 2


def test_account_deletion_forgets_its_devices(circle, db):
    circle.ben.register_device("ef" * 32)
    assert circle.ben.delete_me().status_code == 204
    with db() as session:
        assert session.scalars(select(PushToken)).all() == []


# --- N1: the digest can be turned off -------------------------------------

def _run_digests(app):
    with app.state.sessionmaker() as session:
        notifications.run_evening_digests(
            session, app.state.notifier, app.state.clock, app.state.settings.digest_hour
        )
        session.commit()


def test_digest_is_on_by_default_and_can_be_turned_off(circle, clock, app, db):
    me = circle.ana.client.get("/me", headers=circle.ana.h).json()
    assert me["digest_enabled"] is True
    circle.ben.post_photo()
    for user in (circle.ana, circle.cam):
        user.returned(tz=NY)
    r = circle.cam.patch_settings(digest_enabled=False)
    assert r.json() == {
        "last_light_notice_enabled": False,
        "circle_post_notice_enabled": False,
        "digest_enabled": False,
    }
    clock.set(datetime(2026, 6, 10, 0, 0, tzinfo=UTC))  # 20:00 in New York
    _run_digests(app)
    assert [r.user_id for r in _logs(db, kind="digest")] == [circle.ana.id]


def test_circle_posts_and_the_digest_are_independent(circle, clock, app, db):
    _opt_in(circle.ana)
    circle.ana.returned(tz=NY)
    circle.ben.post_photo()
    clock.set(datetime(2026, 6, 10, 0, 0, tzinfo=UTC))
    _run_digests(app)
    kinds = sorted(r.kind for r in _logs(db, user_id=circle.ana.id))
    assert kinds == ["circle_post", "digest"]


def test_existing_people_keep_their_digest_after_the_migration(circle, app, db):
    with app.state.engine.begin() as conn:
        conn.execute(text("ALTER TABLE users DROP COLUMN circle_post_notice_enabled"))
        conn.execute(text("ALTER TABLE users DROP COLUMN digest_enabled"))
    added = ensure_schema(app.state.engine)
    assert set(added) == {"users.circle_post_notice_enabled", "users.digest_enabled"}
    with db() as session:
        ana = session.get(User, circle.ana.id)
        assert ana.digest_enabled is True
        assert ana.circle_post_notice_enabled is False
