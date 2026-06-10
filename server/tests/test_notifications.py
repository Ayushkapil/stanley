"""§10 as executable policy. The temptation to use decay urgency for
re-engagement will be constant; these tests are the line."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from stanley import notifications
from stanley.models import NotificationLog

from .conftest import NY, START

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
    """N3: no notifications for anchors received, comments, or others' fades."""
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
    assert ana_rows[0].body == "2 new moments from your circle today"  # ana's own absence counted out

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
