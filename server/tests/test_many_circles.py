"""More than one circle (build 17): a person can be in up to five, one is on
screen at a time, and each has its own day. The app names the circle on
screen in an X-Stanley-Circle header; without it, a request is about the
circle joined first, which is what every earlier build sees."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import inspect, text
from sqlalchemy.exc import IntegrityError

from stanley import notifications, physics
from stanley.db import Base, ensure_schema, make_engine
from stanley.models import Anchor, Circle, Membership, NotificationLog, Photo, User

from .conftest import NY, make_user

UTC = timezone.utc


@pytest.fixture
def two(client, circle, clock):
    """ana and ben share 'floor 3' (the circle fixture). ana also started
    'climbing', a minute later, with dee in it and nobody from the floor."""
    dee = make_user(client, "dee")
    clock.set(clock.now() + timedelta(minutes=1))
    r = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h)
    assert r.status_code == 201, r.text
    climbing = r.json()
    assert dee.join(climbing["invite_token"]).status_code == 201
    circle.dee = dee
    circle.floor = circle.id
    circle.climbing = climbing["id"]
    return circle


def test_a_second_circle_is_joined_and_listed_in_join_order(two):
    r = two.ana.client.get("/circles", headers=two.ana.h)
    assert r.status_code == 200
    circles = r.json()["circles"]
    assert [c["name"] for c in circles] == ["floor 3", "climbing"]
    # Names, nothing that ranks or counts a circle. (Build 53 adds the
    # reader's own cover photo, if any, and the day they joined.)
    assert all(set(c) == {"id", "name", "is_creator", "cover_photo_id", "since"} for c in circles)
    assert all(c["is_creator"] for c in circles)


def test_the_day_is_per_circle(two):
    ana = two.ana
    ana.circle_id = two.floor
    assert ana.post_photo().status_code == 201
    # The same day, the same person, another circle: its own day.
    ana.circle_id = two.climbing
    assert ana.post_photo().status_code == 201
    # And each circle's day is still spent once.
    for circle_id in (two.floor, two.climbing):
        ana.circle_id = circle_id
        r = ana.post_photo()
        assert r.status_code == 409
        assert r.json()["detail"]["code"] == "slot_used"


def test_the_gap_is_per_circle(two, clock):
    """A photo in one circle never starts another circle's twelve hours."""
    ana = two.ana
    ana.circle_id = two.floor
    clock.set(datetime(2026, 6, 10, 3, 30, tzinfo=UTC))  # 23:30 June 9, NY
    assert ana.post_photo().status_code == 201
    clock.set(datetime(2026, 6, 10, 4, 30, tzinfo=UTC))  # 00:30 June 10, NY
    assert ana.post_photo().json()["detail"]["code"] == "too_soon"
    ana.circle_id = two.climbing
    assert ana.post_photo().status_code == 201


def test_the_redo_is_per_circle(two):
    ana = two.ana
    ana.circle_id = two.floor
    floor_photo = ana.post_photo().json()["id"]
    ana.circle_id = two.climbing
    assert ana.post_photo().status_code == 201
    # Deleting today's floor photo refunds the floor's day, once.
    ana.circle_id = two.floor
    assert ana.delete_photo(floor_photo).status_code == 204
    assert ana.post_photo().status_code == 201
    # Climbing's day was never touched by it.
    ana.circle_id = two.climbing
    assert ana.post_photo().json()["detail"]["code"] == "slot_used"


def test_the_slot_constraint_is_per_circle(two, db):
    """The race backstop: the database itself allows one row per owner per
    circle per day, and one in each circle."""
    day = datetime(2026, 6, 9, tzinfo=UTC).date()
    now = datetime(2026, 6, 9, 15, tzinfo=UTC)

    def row(circle_id):
        return Photo(
            owner_id=two.ana.id, circle_id=circle_id, taken_at=now, taken_tz=NY,
            local_date=day, state=physics.LIVE, created_at=now,
        )

    with db() as s:
        s.add_all([row(two.floor), row(two.climbing)])
        s.commit()
    with db() as s:
        s.add(row(two.floor))
        with pytest.raises(IntegrityError):
            s.commit()


def test_today_shows_the_circle_on_screen(two):
    ana, ben, dee = two.ana, two.ben, two.dee
    floor_photo = ben.post_photo(caption="floor").json()["id"]
    climbing_photo = dee.post_photo(caption="wall").json()["id"]

    ana.circle_id = two.floor
    assert [p["id"] for p in ana.feed_photos()] == [floor_photo]
    ana.circle_id = two.climbing
    assert [p["id"] for p in ana.feed_photos()] == [climbing_photo]
    # No header: the circle joined first, as every earlier build sees it.
    ana.circle_id = None
    assert [p["id"] for p in ana.feed_photos()] == [floor_photo]
    assert ana.client.get("/circles/mine", headers=ana.h).json()["name"] == "floor 3"


def test_a_photo_goes_to_the_circle_on_screen(two):
    two.ana.circle_id = two.climbing
    pid = two.ana.post_photo().json()["id"]
    assert pid in [p["id"] for p in two.dee.feed_photos()]
    assert pid not in [p["id"] for p in two.ben.feed_photos()]


def test_a_circle_you_are_not_in_is_refused_never_swapped(two, db):
    ben = two.ben
    ben.circle_id = two.climbing  # ben was never in it
    r = ben.post_photo()
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "not_in_circle"
    assert ben.feed().json()["detail"]["code"] == "not_in_circle"
    with db() as s:
        assert s.query(Photo).filter(Photo.owner_id == ben.id).count() == 0


def test_left_circle_on_another_phone_is_not_in_circle(two):
    ana = two.ana
    assert ana.leave(two.climbing).status_code == 204
    ana.circle_id = two.climbing
    assert ana.feed().json()["detail"]["code"] == "not_in_circle"
    # The circle that's left is untouched, and the other one is still hers.
    ana.circle_id = two.floor
    assert ana.feed().status_code == 200
    assert [c["name"] for c in ana.client.get("/circles", headers=ana.h).json()["circles"]] == ["floor 3"]
    assert two.dee.feed().status_code == 200


def test_five_circles_and_no_more(client):
    eve = make_user(client, "eve")
    for i in range(physics.CIRCLES_PER_PERSON):
        r = eve.client.post("/circles", json={"name": f"circle {i}"}, headers=eve.h)
        assert r.status_code == 201, r.text
    r = eve.client.post("/circles", json={"name": "one more"}, headers=eve.h)
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "too_many_circles"

    host = make_user(client, "host")
    code = host.client.post("/circles", json={"name": "elsewhere"}, headers=host.h).json()["invite_token"]
    r = eve.join(code)
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "too_many_circles"


def test_joining_a_circle_you_are_in_says_so(two):
    r = two.ben.join(two.invite_token)
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "already_in_circle"


def test_gestures_reach_any_of_your_circles(two):
    """A memory opened from Held or Returned isn't always from the circle on
    screen. It still takes a like, a hold and a story."""
    pid = two.dee.post_photo().json()["id"]
    ana = two.ana
    ana.circle_id = two.floor
    assert ana.like(pid).status_code == 201
    assert ana.anchor(pid).status_code == 201
    assert ana.comment(pid, "the overhang").status_code == 201
    # Still nothing for someone who shares no circle with it.
    assert two.ben.like(pid).status_code == 404


def test_held_gathers_every_circle_and_names_each(two):
    ana = two.ana
    floor_photo = two.ben.post_photo().json()["id"]
    climbing_photo = two.dee.post_photo().json()["id"]
    assert ana.anchor(floor_photo).status_code == 201
    assert ana.anchor(climbing_photo).status_code == 201
    for circle_id in (two.floor, two.climbing, None):
        ana.circle_id = circle_id
        memories = {
            m["id"]: m["circle_name"]
            for t in ana.memories().json()["threads"]
            for m in t["memories"]
        }
        assert memories == {floor_photo: "floor 3", climbing_photo: "climbing"}


def test_profiles_and_blocks_follow_any_shared_circle(two, client):
    ana, ben, dee = two.ana, two.ben, two.dee
    # ana and dee share only climbing; that's enough, whatever's on screen.
    ana.circle_id = two.floor
    assert ana.client.get(f"/members/{dee.id}", headers=ana.h).status_code == 200
    # ben and dee share nothing.
    assert ben.client.get(f"/members/{dee.id}", headers=ben.h).status_code == 404
    assert ben.block(dee.id).status_code == 404
    assert ana.block(dee.id).status_code == 204


def test_one_digest_a_day_however_many_circles(two, clock, app, db):
    two.ben.post_photo()
    two.dee.post_photo()
    two.ana.returned(tz=NY)  # records ana's timezone
    two.ana.patch_settings(digest_enabled=True)
    clock.set(datetime(2026, 6, 10, 0, 0, tzinfo=UTC))  # 20:00 in New York
    for _ in range(2):
        with app.state.sessionmaker() as session:
            notifications.run_evening_digests(
                session, app.state.notifier, app.state.clock, app.state.settings.digest_hour
            )
            session.commit()
    with db() as s:
        rows = s.query(NotificationLog).filter_by(user_id=two.ana.id, kind="digest").all()
    assert len(rows) == 1
    assert rows[0].body == notifications.DIGEST_BODY


def test_a_digest_comes_from_a_second_circle_alone(two, clock, app, db):
    two.dee.post_photo()  # only climbing had anything today
    two.ana.returned(tz=NY)
    two.ana.patch_settings(digest_enabled=True)
    clock.set(datetime(2026, 6, 10, 0, 0, tzinfo=UTC))
    with app.state.sessionmaker() as session:
        notifications.run_evening_digests(
            session, app.state.notifier, app.state.clock, app.state.settings.digest_hour
        )
        session.commit()
    with db() as s:
        assert s.query(NotificationLog).filter_by(user_id=two.ana.id, kind="digest").count() == 1


# --- the migration ----------------------------------------------------------

_OLD_SLOT = "CONSTRAINT uq_owner_localdate UNIQUE (owner_id, local_date)"


def _build_16_database(path):
    """A database as build 16 left it: today's schema, except that photos
    carries the old one-a-day-per-person constraint."""
    # make_engine, so every connection has foreign keys on, as in production.
    engine = make_engine(f"sqlite:///{path}")
    Base.metadata.create_all(engine)
    with engine.begin() as conn:
        create = conn.execute(
            text("SELECT sql FROM sqlite_master WHERE type='table' AND name='photos'")
        ).scalar()
        assert "uq_owner_circle_localdate" in create
        old = create.replace(
            "CONSTRAINT uq_owner_circle_localdate UNIQUE (owner_id, circle_id, local_date)", _OLD_SLOT
        )
        conn.execute(text("DROP TABLE photos"))
        conn.execute(text(old))
        conn.execute(text("CREATE INDEX ix_photos_circle_state ON photos (circle_id, state)"))
    return engine


def test_a_build_16_database_gets_a_per_circle_day(tmp_path):
    from sqlalchemy.orm import Session

    engine = _build_16_database(tmp_path / "old.db")
    now = datetime(2026, 6, 9, 15, tzinfo=UTC)
    with Session(engine) as s:
        s.add_all([
            User(id="u1", display_name="ana", created_at=now),
            User(id="u2", display_name="ben", created_at=now),
        ])
        s.flush()  # no relationships declared, so the order is ours to give
        s.add_all([
            Circle(id="c1", name="floor", created_by="u1", created_at=now),
            Circle(id="c2", name="climbing", created_by="u1", created_at=now),
        ])
        s.flush()
        s.add(Photo(
            id="p1", owner_id="u1", circle_id="c1", taken_at=now, taken_tz=NY,
            local_date=now.date(), caption="kept", location="the roof", filter="mono",
            state=physics.LIVE, created_at=now,
        ))
        s.flush()
        s.add(Anchor(photo_id="p1", user_id="u2", created_at=now, note="mine"))
        s.commit()

    ensure_schema(engine)

    inspector = inspect(engine)
    slots = [set(uc["column_names"]) for uc in inspector.get_unique_constraints("photos")]
    assert {"owner_id", "circle_id", "local_date"} in slots
    assert {"owner_id", "local_date"} not in slots
    assert "ix_photos_circle_state" in {i["name"] for i in inspector.get_indexes("photos")}
    with engine.connect() as conn:
        assert conn.execute(text("PRAGMA foreign_key_check")).fetchall() == []
    with Session(engine) as s:
        photo = s.get(Photo, "p1")
        assert (photo.caption, photo.location, photo.filter) == ("kept", "the roof", "mono")
        assert s.get(Anchor, ("p1", "u2")).note == "mine"
        # The same day, another circle: allowed now.
        s.add(Photo(
            id="p2", owner_id="u1", circle_id="c2", taken_at=now + timedelta(minutes=1),
            taken_tz=NY, local_date=now.date(), state=physics.LIVE, created_at=now,
        ))
        s.commit()
        # The same circle: still once.
        s.add(Photo(
            id="p3", owner_id="u1", circle_id="c1", taken_at=now + timedelta(minutes=2),
            taken_tz=NY, local_date=now.date(), state=physics.LIVE, created_at=now,
        ))
        with pytest.raises(IntegrityError):
            s.commit()

    # Run again, as every startup does: nothing left to change.
    ensure_schema(engine)
    with Session(engine) as s:
        assert {p.id for p in s.query(Photo)} == {"p1", "p2"}


def test_foreign_keys_are_back_on_after_the_rebuild(tmp_path):
    """The rebuild turns foreign keys off on its connection, which the pool
    then hands to the next request. They have to be back on."""
    engine = _build_16_database(tmp_path / "old.db")
    ensure_schema(engine)
    for _ in range(3):
        with engine.connect() as conn:
            assert conn.execute(text("PRAGMA foreign_keys")).scalar() == 1
    raw = engine.raw_connection()
    try:
        assert raw.driver_connection.isolation_level is not None
    finally:
        raw.close()
