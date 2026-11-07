"""One circle's countdown (build 35): a flag on a single circle, set by hand
with scripts/set_countdown.py, returned with the circle on screen and null
for every other circle. Nothing in the API makes one."""
from __future__ import annotations

import importlib.util
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import text

from stanley.db import Base, ensure_schema, make_engine, make_sessionmaker
from stanley.models import Circle, Membership, User

from .conftest import make_user

_SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "set_countdown.py"
_spec = importlib.util.spec_from_file_location("set_countdown", _SCRIPT)
script = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(script)

INDIA = script.PRESETS["india"]


def _mine(api):
    r = api.client.get("/circles/mine", headers=api.h)
    assert r.status_code == 200, r.text
    return r.json()


def _flag(db, circle_id, countdown):
    with db() as s:
        s.get(Circle, circle_id).countdown = countdown
        s.commit()


@pytest.fixture
def two(client, circle):
    """ana and ben share 'floor 3'. ana also started 'climbing' with dee."""
    dee = make_user(client, "dee")
    r = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h)
    assert r.status_code == 201, r.text
    climbing = r.json()
    assert dee.join(climbing["invite_token"]).status_code == 201
    circle.dee = dee
    circle.climbing = climbing["id"]
    return circle


def test_no_circle_has_a_countdown_unless_one_is_set(circle):
    assert _mine(circle.ana)["countdown"] is None


def test_the_countdown_comes_with_its_own_circle_only(two, db):
    _flag(db, two.id, INDIA)
    assert _mine(two.ben)["countdown"] == INDIA
    # Someone who isn't in the flagged circle sees nothing.
    assert _mine(two.dee)["countdown"] is None
    # Someone in both sees it only while the flagged circle is on screen.
    two.ana.circle_id = two.climbing
    assert _mine(two.ana)["countdown"] is None
    two.ana.circle_id = two.id
    assert _mine(two.ana)["countdown"] == INDIA


def test_nothing_in_the_api_sets_one(circle):
    """The only way in is the script: renaming the circle can't carry one."""
    r = circle.ana.client.patch(
        f"/circles/{circle.id}", json={"name": "floor 3", "countdown": INDIA}, headers=circle.ana.h
    )
    assert r.status_code == 200
    assert _mine(circle.ana)["countdown"] is None


def test_ensure_schema_adds_the_column_to_an_older_database(app):
    engine = app.state.engine
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE circles DROP COLUMN countdown"))
    assert ensure_schema(engine) == ["circles.countdown"]
    assert ensure_schema(engine) == []


@pytest.fixture
def db_file(tmp_path, clock):
    """A database on disk, as the script meets it: one circle, no countdown."""
    path = tmp_path / "stanley.db"
    engine = make_engine(f"sqlite:///{path}")
    Base.metadata.create_all(engine)
    sessions = make_sessionmaker(engine)
    with sessions() as s:
        ana = User(display_name="Ayush K", created_at=clock.now())
        s.add(ana)
        s.flush()
        floor = Circle(name="floor 3", created_by=ana.id, created_at=clock.now())
        s.add(floor)
        s.flush()
        s.add(Membership(circle_id=floor.id, user_id=ana.id, joined_at=clock.now(), role="creator"))
        s.commit()
        circle_id = floor.id
    return path, sessions, circle_id


def test_the_script_sets_and_clears_a_countdown(db_file):
    path, sessions, circle_id = db_file
    assert script.set_countdown(str(path), circle_id, INDIA) == "floor 3"
    # Written by the script with the standard library, read back by the ORM
    # as the dict the endpoint returns.
    with sessions() as s:
        assert s.get(Circle, circle_id).countdown == INDIA
    assert script.show(str(path), circle_id) == ("floor 3", INDIA)
    script.set_countdown(str(path), circle_id, None)
    with sessions() as s:
        assert s.get(Circle, circle_id).countdown is None


def test_the_script_finds_a_persons_circles_by_name(db_file):
    path, _, circle_id = db_file
    assert script.find(str(path), "Ayush") == [(circle_id, "floor 3", "Ayush K", 1)]
    assert script.find(str(path), "Ben") == []


def test_the_script_refuses_an_unknown_circle(db_file):
    path, _, _ = db_file
    with pytest.raises(script.Invalid):
        script.set_countdown(str(path), "nope", INDIA)


@pytest.mark.parametrize(
    "change",
    [
        {"target_tz": "Chicago"},
        {"target_date": "23 Nov"},
        {"start_date": "2026-11-24"},
        {"arrives_at": "2026-11-25T02:30:00"},  # no offset
        {"home_until": "2026-11-25T02:00:00+05:30"},  # before landing
        {"messages": {"countdown": "x", "banner": "LOUD"}},
        {"label": ""},
        {"colour": "red"},
        # No emoji anywhere (build 36): the app draws its own plane and house.
        {"emoji": "✈️"},
        {"label": "India ✈️"},
        {"messages": {"home": "How's home? 🏠"}},
        {"messages": {"countdown": "{days} days ✈"}},  # without the selector too
        {"reminders": ["pack"]},
        {"reminders": {"0": "pack"}},  # the day itself has its own words
        {"reminders": {"18": "pack"}},  # before the countdown starts
        {"reminders": {"two": "pack"}},
        {"reminders": {"3": ""}},
        {"reminders": {"3": "x" * 81}},
    ],
)
def test_validate_refuses_what_it_cant_draw(change):
    with pytest.raises(script.Invalid):
        script.validate({**INDIA, **change})


def test_the_india_preset_is_the_plan():
    chicago, india = ZoneInfo("America/Chicago"), ZoneInfo("Asia/Kolkata")
    assert INDIA["target_date"] == "2026-11-23"
    assert INDIA["target_tz"] == "America/Chicago"
    assert INDIA["start_date"] == "2026-11-06"
    arrives = datetime.fromisoformat(INDIA["arrives_at"])
    # Nov 25 02:30 IST is Nov 24 15:00 in Chicago (CST, UTC-6, after DST).
    assert arrives.astimezone(chicago) == datetime(2026, 11, 24, 15, 0, tzinfo=chicago)
    until = datetime.fromisoformat(INDIA["home_until"])
    # Home lasts through 23:59 on Nov 27 IST; it's gone from Nov 28 IST.
    assert until - timedelta(minutes=1) == datetime(2026, 11, 27, 23, 59, tzinfo=india)
    script.validate(INDIA)


def test_the_india_preset_says_home_without_emoji():
    assert INDIA["messages"] == {
        "countdown": "{days} days for Home",
        "two_days": "Almost Home",
        "one_day": "Tomorrow",
        "departure": "Bags packed, hearts full. Let's go home.",
        "in_the_air": "You're in for an awesome journey!",
        "home": "How's home?",
    }
    assert "emoji" not in INDIA
    assert all(script._plain(words) for words in [INDIA["label"], *INDIA["messages"].values()])


def test_the_india_preset_tucks_in_a_note_every_three_days():
    assert INDIA["reminders"] == {
        "17": "The countdown begins!",
        "14": "Have you even started packing??",
        "11": "Shopping done? 👀",
        "8": "Cleaned your place yet?",
        "5": "Packed?? Not yet?",
        "3": "Seriously though, pack.",
        "1": "Tomorrow. TOMORROW.",
    }


def test_the_reminders_come_with_their_own_circle_only(two, db):
    _flag(db, two.id, INDIA)
    assert _mine(two.ben)["countdown"]["reminders"]["11"] == "Shopping done? 👀"
    assert _mine(two.dee)["countdown"] is None
