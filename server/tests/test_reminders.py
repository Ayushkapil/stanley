"""The two reminders a person sets for themselves (build 39, §10 N6): "Leave
a note for your circle today" and "Your circle is waiting for today's
moment". Off until asked for, at one of four hours of the person's own day,
once a day, and only while still true."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from stanley import notifications
from stanley.models import NotificationLog

from .conftest import NY, make_user

UTC = timezone.utc
# 9:00 in New York on June 10, 2026 (EDT is UTC-4).
NINE_AM = datetime(2026, 6, 10, 13, 0, tzinfo=UTC)
SIX_PM = datetime(2026, 6, 10, 22, 0, tzinfo=UTC)


def _notices(db):
    with db() as s:
        return [(n.user_id, n.kind, n.body) for n in s.scalars(select(NotificationLog)).all()]


@pytest.fixture
def remind(app):
    def run():
        with app.state.sessionmaker() as session:
            sent = notifications.run_reminders(session, app.state.notifier, app.state.clock)
            session.commit()
        return sent

    return run


def test_both_are_off_until_asked_for(circle, clock, remind, db):
    me = circle.ana.client.get("/me", headers=circle.ana.h).json()
    assert me["note_reminder_enabled"] is False and me["photo_reminder_enabled"] is False
    assert (me["note_reminder_hour"], me["photo_reminder_hour"]) == (9, 18)
    circle.ana.returned(tz=NY)
    for moment in (NINE_AM, SIX_PM):
        clock.set(moment)
        assert remind() == 0
    assert _notices(db) == []


def test_the_note_reminder_goes_once_at_its_hour(circle, clock, remind, db):
    circle.ana.returned(tz=NY)  # the server learns her zone
    r = circle.ana.patch_settings(note_reminder_enabled=True)
    assert r.json()["note_reminder_enabled"] is True and r.json()["photo_reminder_enabled"] is False
    clock.set(NINE_AM - timedelta(minutes=1))
    assert remind() == 0  # 8:59
    clock.set(NINE_AM + timedelta(minutes=14))
    assert remind() == 1
    assert _notices(db) == [(circle.ana.id, "note_reminder", "Leave a note for your circle today")]
    clock.set(NINE_AM + timedelta(minutes=29))
    assert remind() == 0  # once a day
    clock.set(NINE_AM + timedelta(days=1))
    assert remind() == 1  # and again tomorrow


def test_no_note_reminder_once_todays_note_is_up(circle, clock, remind, db):
    circle.ana.returned(tz=NY)
    circle.ana.patch_settings(note_reminder_enabled=True)
    clock.set(NINE_AM - timedelta(hours=1))
    assert circle.ana.set_note(circle.id, "pancakes at ten").status_code == 200
    clock.set(NINE_AM)
    assert remind() == 0
    # Yesterday's note doesn't count: it cleared at midnight.
    clock.set(NINE_AM + timedelta(days=1))
    assert remind() == 1


def test_the_photo_reminder_follows_the_hour_chosen(circle, clock, remind, db):
    circle.ana.returned(tz=NY)
    assert circle.ana.patch_settings(photo_reminder_enabled=True, photo_reminder_hour=21).status_code == 200
    clock.set(SIX_PM)
    assert remind() == 0  # she chose night, not evening
    clock.set(SIX_PM + timedelta(hours=3))
    assert remind() == 1
    assert _notices(db) == [(circle.ana.id, "photo_reminder", "Your circle is waiting for today's moment")]


def test_no_photo_reminder_once_todays_photo_is_posted(circle, clock, remind, db):
    circle.ana.returned(tz=NY)
    circle.ana.patch_settings(photo_reminder_enabled=True)
    clock.set(SIX_PM - timedelta(hours=4))
    assert circle.ana.post_photo().status_code == 201
    clock.set(SIX_PM)
    assert remind() == 0
    # Someone else's photo is not hers: ben is still reminded.
    circle.ben.returned(tz=NY)
    circle.ben.patch_settings(photo_reminder_enabled=True)
    assert remind() == 1
    assert [n[0] for n in _notices(db)] == [circle.ben.id]


def test_a_photo_given_back_by_the_redo_is_reminded_again(circle, clock, remind):
    circle.ana.returned(tz=NY)
    circle.ana.patch_settings(photo_reminder_enabled=True)
    clock.set(SIX_PM - timedelta(hours=4))
    pid = circle.ana.post_photo().json()["id"]
    assert circle.ana.delete_photo(pid).status_code in (200, 204)
    clock.set(SIX_PM)
    assert remind() == 1


def test_both_at_the_same_hour_are_two_notices_and_no_more(circle, clock, remind, db):
    circle.ana.returned(tz=NY)
    circle.ana.patch_settings(
        note_reminder_enabled=True, note_reminder_hour=18, photo_reminder_enabled=True, photo_reminder_hour=18
    )
    clock.set(SIX_PM)
    assert remind() == 2
    assert remind() == 0
    assert sorted(n[1] for n in _notices(db)) == ["note_reminder", "photo_reminder"]


def test_only_the_four_hours_on_offer(circle):
    for hour in (9, 14, 18, 21):
        assert circle.ana.patch_settings(note_reminder_hour=hour).json()["note_reminder_hour"] == hour
    for hour in (0, 3, 10, 24, -1):
        r = circle.ana.patch_settings(photo_reminder_hour=hour)
        assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_reminder_hour"
    assert circle.ana.patch_settings().json()["photo_reminder_hour"] == 18  # untouched


def test_the_words_carry_no_name_number_or_deadline(circle, clock, remind, db):
    circle.ana.returned(tz=NY)
    circle.ana.patch_settings(
        note_reminder_enabled=True, note_reminder_hour=18, photo_reminder_enabled=True
    )
    circle.ben.post_photo()
    clock.set(SIX_PM)
    remind()
    for _, _, body in _notices(db):
        assert not any(ch.isdigit() for ch in body)
        assert "ben" not in body.lower() and "ana" not in body.lower()


def test_someone_in_no_circle_is_not_reminded(client, clock, remind):
    dee = make_user(client, "dee")
    dee.patch_settings(note_reminder_enabled=True, photo_reminder_enabled=True, photo_reminder_hour=9)
    clock.set(NINE_AM)  # no zone known: her clock is UTC's, and it's 13:00 there
    assert remind() == 0
    clock.set(datetime(2026, 6, 10, 9, 0, tzinfo=UTC))
    assert remind() == 0  # the hour is right, but there's no circle to remind her of


def test_an_unknown_zone_reads_as_utc_and_stops_nobody(circle, clock, remind, db):
    circle.ana.returned(tz=NY)
    circle.ana.patch_settings(note_reminder_enabled=True)
    circle.ben.patch_settings(note_reminder_enabled=True)
    with db() as s:
        from stanley.models import User

        s.get(User, circle.ben.id).tz_last_seen = "Mars/Olympus"
        s.commit()
    clock.set(NINE_AM)
    assert remind() == 1  # ana, in New York; ben's 9:00 is UTC's
    clock.set(datetime(2026, 6, 11, 9, 30, tzinfo=UTC))
    assert remind() == 1


def test_a_deleted_account_keeps_no_reminder(circle, clock, remind, db):
    circle.cam.returned(tz=NY)
    circle.cam.patch_settings(note_reminder_enabled=True, photo_reminder_enabled=True)
    assert circle.cam.delete_me().status_code in (200, 204)
    for moment in (NINE_AM, SIX_PM):
        clock.set(moment)
        assert remind() == 0
    with db() as s:
        from stanley.models import User

        gone = s.get(User, circle.cam.id)
        assert gone.note_reminder_enabled is False and gone.photo_reminder_enabled is False


def test_the_sweep_runs_them_and_survives_them_failing(app, circle, clock, db, monkeypatch):
    from stanley.main import tick

    circle.ana.returned(tz=NY)
    circle.ana.patch_settings(note_reminder_enabled=True)
    clock.set(NINE_AM)
    tick(app)
    assert [n[1] for n in _notices(db)] == ["note_reminder"]

    def broken(*_, **__):
        raise RuntimeError("no")

    monkeypatch.setattr(notifications, "run_reminders", broken)
    tick(app)  # logged, and the pass goes on


def test_an_older_database_gains_the_columns_off(tmp_path):
    from sqlalchemy import create_engine, inspect, text

    from stanley.db import ensure_schema

    engine = create_engine(f"sqlite:///{tmp_path}/old.db")
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE users (id VARCHAR(32) PRIMARY KEY, created_at DATETIME)"))
        conn.execute(text("INSERT INTO users (id) VALUES ('u1')"))
    added = ensure_schema(engine)
    assert {"users.note_reminder_enabled", "users.photo_reminder_hour"} <= set(added)
    with engine.begin() as conn:
        row = conn.execute(text(
            "SELECT note_reminder_enabled, note_reminder_hour, photo_reminder_enabled, photo_reminder_hour FROM users"
        )).one()
    assert tuple(row) == (0, 9, 0, 18)
    assert "photo_reminder_enabled" in {c["name"] for c in inspect(engine).get_columns("users")}
