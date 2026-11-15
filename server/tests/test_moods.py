"""The answer sheet (build 65): one mark a day, one of five, kept for its
owner alone in `day_moods` and nowhere else.

A mark is set only on the day it's for, and that day is its owner's own,
in the zone their phone sends: a Bloomington evening (after 7 PM EST, UTC is
already tomorrow), a Delhi small hour (before 5:30 AM IST, UTC is still
yesterday), and the night the clocks went back in the US (1 November 2026).
Yesterday can't be filled in and tomorrow can't be marked ahead. Nothing
counts, totals or averages the marks, and no circle or shared response
carries one."""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

import pytest
from sqlalchemy import select, text

from stanley.db import ensure_schema
from stanley.models import DayMood, NotificationLog, Photo

INDY = "America/Indiana/Indianapolis"
DELHI = "Asia/Kolkata"


def utc(y, mo, d, h, mi=0):
    return datetime(y, mo, d, h, mi, tzinfo=timezone.utc)


BLOOMINGTON_EVENING = (INDY, utc(2026, 11, 16, 1), "2026-11-15")  # 8 PM EST, 15 Nov
DELHI_SMALL_HOURS = (DELHI, utc(2026, 11, 15, 21, 30), "2026-11-16")  # 3 AM IST, 16 Nov
CLOCKS_BACK_NIGHT = (INDY, utc(2026, 11, 2, 3), "2026-11-01")  # 10 PM EST, 1 Nov, hours after the change
CASES = pytest.mark.parametrize(
    "zone,now,local", [BLOOMINGTON_EVENING, DELHI_SMALL_HOURS, CLOCKS_BACK_NIGHT],
    ids=["bloomington", "delhi", "clocks-back"],
)


def mark(api, day, level, tz):
    body = {"level": level}
    if tz is not None:
        body["tz"] = tz
    return api.client.put(f"/moods/{day}", json=body, headers=api.h)


def marks(api, **query):
    r = api.client.get("/moods", params=query, headers=api.h)
    assert r.status_code == 200, r.text
    return r.json()["moods"]


def shift(day: str, n: int) -> str:
    return (date.fromisoformat(day) + timedelta(days=n)).isoformat()


# --- today, and only today ----------------------------------------------------------------------


@CASES
def test_a_mark_is_set_and_changed_on_the_owners_own_day(circle, clock, zone, now, local):
    clock.set(now)
    r = mark(circle.ana, local, 2, zone)
    assert r.status_code == 200, r.text
    assert r.json() == {"day": local, "level": 2}
    assert marks(circle.ana) == [{"day": local, "level": 2}]
    # Changed, as often as wanted, while the day lasts.
    assert mark(circle.ana, local, 5, zone).json() == {"day": local, "level": 5}
    assert marks(circle.ana) == [{"day": local, "level": 5}]


@CASES
def test_yesterday_and_tomorrow_are_refused(circle, clock, zone, now, local):
    clock.set(now)
    for day in (shift(local, -1), shift(local, 1)):
        r = mark(circle.ana, day, 3, zone)
        assert r.status_code == 400, day
        assert r.json()["detail"]["code"] == "not_today"
    assert marks(circle.ana) == []


@CASES
def test_utcs_day_is_not_the_owners(circle, clock, zone, now, local):
    """The day UTC is on at that moment is the wrong one for each case."""
    clock.set(now)
    utc_day = now.date().isoformat()
    assert utc_day != local
    assert mark(circle.ana, utc_day, 3, zone).json()["detail"]["code"] == "not_today"


def test_the_day_turns_at_the_owners_midnight(circle, clock):
    # 11:59 PM in Bloomington on the 15th: the 15th takes a mark.
    clock.set(utc(2026, 11, 16, 4, 59))
    assert mark(circle.ana, "2026-11-15", 4, INDY).status_code == 200
    # A minute later it's the 16th there, and the 15th is closed for good.
    clock.set(utc(2026, 11, 16, 5, 0))
    assert mark(circle.ana, "2026-11-15", 1, INDY).json()["detail"]["code"] == "not_today"
    assert mark(circle.ana, "2026-11-16", 1, INDY).status_code == 200
    assert marks(circle.ana) == [{"day": "2026-11-15", "level": 4}, {"day": "2026-11-16", "level": 1}]


def test_the_long_day_the_clocks_went_back_is_one_day(circle, clock):
    """1 November 2026 in Indiana is 25 hours long: 1 AM EDT and 11 PM EST
    are the same day, and a mark set at the first is changed at the last."""
    clock.set(utc(2026, 11, 1, 5))  # 1 AM EDT
    assert mark(circle.ana, "2026-11-01", 2, INDY).status_code == 200
    clock.set(utc(2026, 11, 2, 4))  # 11 PM EST
    assert mark(circle.ana, "2026-11-01", 3, INDY).status_code == 200
    assert marks(circle.ana) == [{"day": "2026-11-01", "level": 3}]
    clock.set(utc(2026, 11, 2, 5))  # midnight EST: the 2nd
    assert mark(circle.ana, "2026-11-01", 4, INDY).json()["detail"]["code"] == "not_today"


def test_null_takes_todays_mark_back(circle, clock):
    clock.set(BLOOMINGTON_EVENING[1])
    mark(circle.ana, "2026-11-15", 3, INDY)
    assert mark(circle.ana, "2026-11-15", None, INDY).json() == {"day": "2026-11-15", "level": None}
    assert marks(circle.ana) == []
    # Taking back is a change to the day too: only today.
    clock.set(utc(2026, 11, 16, 15))
    mark(circle.ana, "2026-11-16", 3, INDY)
    clock.set(utc(2026, 11, 17, 15))
    assert mark(circle.ana, "2026-11-16", None, INDY).json()["detail"]["code"] == "not_today"
    assert marks(circle.ana) == [{"day": "2026-11-16", "level": 3}]


# --- taking a mark back (build 66) -----------------------------------------------------------------


@CASES
def test_a_mark_is_taken_back_on_the_owners_own_day(circle, clock, zone, now, local):
    clock.set(now)
    mark(circle.ana, local, 4, zone)
    r = mark(circle.ana, local, None, zone)
    assert r.status_code == 200, r.text
    assert r.json() == {"day": local, "level": None}
    assert marks(circle.ana) == []
    # Marked again the same day, and taken back again.
    mark(circle.ana, local, 2, zone)
    assert marks(circle.ana) == [{"day": local, "level": 2}]
    assert mark(circle.ana, local, None, zone).status_code == 200
    assert marks(circle.ana) == []


@CASES
def test_taking_back_yesterdays_or_tomorrows_is_refused(circle, clock, zone, now, local):
    # Yesterday's mark, set while it was yesterday's today.
    clock.set(now - timedelta(days=1))
    assert mark(circle.ana, shift(local, -1), 3, zone).status_code == 200
    clock.set(now)
    for day in (shift(local, -1), shift(local, 1)):
        r = mark(circle.ana, day, None, zone)
        assert r.status_code == 400, day
        assert r.json()["detail"]["code"] == "not_today"
    # What was there stays, exactly.
    assert marks(circle.ana) == [{"day": shift(local, -1), "level": 3}]


@CASES
def test_utcs_day_cant_be_taken_back_either(circle, clock, zone, now, local):
    clock.set(now)
    utc_day = now.date().isoformat()
    assert mark(circle.ana, utc_day, None, zone).json()["detail"]["code"] == "not_today"


def test_taking_back_a_day_with_no_mark_changes_nothing(circle, clock):
    clock.set(BLOOMINGTON_EVENING[1])
    mark(circle.ben, "2026-11-15", 5, INDY)
    assert mark(circle.ana, "2026-11-15", None, INDY).json() == {"day": "2026-11-15", "level": None}
    assert marks(circle.ana) == []
    # Someone else's mark on the same day is theirs, untouched.
    assert marks(circle.ben) == [{"day": "2026-11-15", "level": 5}]


def test_a_photos_dots_take_back_only_today_too(circle, clock):
    """Builds 52 to 64 take a mark back through the photo: today's only."""
    photo = circle.ana.post_photo(tz=INDY).json()
    score = lambda value: circle.ana.client.put(
        f"/photos/{photo['id']}/score", json={"score": value}, headers=circle.ana.h
    )
    assert score(4).status_code == 200
    assert score(None).status_code == 200
    assert marks(circle.ana) == []
    assert score(2).status_code == 200
    clock.advance(timedelta(days=1))
    r = score(None)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "not_today"
    assert marks(circle.ana) == [{"day": "2026-06-09", "level": 2}]


def test_a_mark_is_one_of_five(circle, clock):
    today = "2026-06-09"
    for bad in (0, 6, -1, 100):
        r = mark(circle.ana, today, bad, INDY)
        assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_level"
    for good in (1, 2, 3, 4, 5):
        assert mark(circle.ana, today, good, INDY).json()["level"] == good
    # The field has to be there: an empty body isn't a clear.
    assert circle.ana.client.put(f"/moods/{today}", json={"tz": INDY}, headers=circle.ana.h).status_code == 422


def test_the_zone_is_required_and_has_to_be_real(circle):
    assert mark(circle.ana, "2026-06-09", 3, None).status_code == 422
    r = mark(circle.ana, "2026-06-09", 3, "Mars/Olympus")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_timezone"
    r = mark(circle.ana, "June 9", 3, INDY)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_day"
    assert marks(circle.ana) == []


def test_a_photo_doesnt_need_to_be_posted_to_mark_the_day(circle, db):
    """The sheet marks the day itself. Nothing about it touches a photo."""
    assert mark(circle.ana, "2026-06-09", 4, INDY).status_code == 200
    with db() as s:
        row = s.get(DayMood, (circle.ana.id, date(2026, 6, 9)))
        assert (row.score, row.photo_id) == (4, None)
        assert s.scalars(select(Photo)).all() == []


def test_the_sheet_and_a_photos_dots_are_the_same_mark(circle, clock):
    """Builds 52 to 64 mark through today's photo; it's the same day's one
    mark, with no second copy anywhere."""
    photo = circle.ana.post_photo(tz=INDY).json()
    mark(circle.ana, "2026-06-09", 2, INDY)
    r = circle.ana.client.put(f"/photos/{photo['id']}/score", json={"score": 5}, headers=circle.ana.h)
    assert r.status_code == 200
    assert marks(circle.ana) == [{"day": "2026-06-09", "level": 5}]
    # And the old reading of them still answers for those builds.
    old = circle.ana.client.get("/me/moods", headers=circle.ana.h).json()
    assert old == {"moods": [{"day": "2026-06-09", "score": 5}]}


# --- reading them -------------------------------------------------------------------------------


def test_reading_a_stretch_of_days(circle, clock):
    for offset, level in ((0, 1), (1, 3), (2, 5), (5, 2)):
        clock.set(utc(2026, 11, 10, 15) + timedelta(days=offset))
        day = (date(2026, 11, 10) + timedelta(days=offset)).isoformat()
        assert mark(circle.ana, day, level, INDY).status_code == 200
    every = [
        {"day": "2026-11-10", "level": 1}, {"day": "2026-11-11", "level": 3},
        {"day": "2026-11-12", "level": 5}, {"day": "2026-11-15", "level": 2},
    ]
    assert marks(circle.ana) == every
    assert marks(circle.ana, **{"from": "2026-11-11", "to": "2026-11-14"}) == every[1:3]
    assert marks(circle.ana, **{"from": "2026-11-12"}) == every[2:]
    assert marks(circle.ana, to="2026-11-10") == every[:1]
    r = circle.ana.client.get("/moods", params={"from": "2026-11-12", "to": "2026-11-10"}, headers=circle.ana.h)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_range"


def test_only_your_own(circle):
    mark(circle.ana, "2026-06-09", 4, INDY)
    assert marks(circle.ben) == []
    # There's no way to name anyone else: the route takes no person.
    r = circle.ben.client.get("/moods", params={"user": circle.ana.id}, headers=circle.ben.h)
    assert r.json() == {"moods": []}


def test_the_routes_need_a_sign_in(client):
    assert client.put("/moods/2026-06-09", json={"level": 3, "tz": INDY}).status_code == 401
    assert client.get("/moods").status_code == 401


# --- never anyone else's, never counted ---------------------------------------------------------


def _walk(value, key=None):
    if isinstance(value, dict):
        for k, inner in value.items():
            yield k, None
            yield from _walk(inner, k)
    elif isinstance(value, list):
        for inner in value:
            yield from _walk(inner, key)
    else:
        yield key, value


MOOD_KEYS = {"score", "level", "mood", "moods", "mark", "marks"}


def test_no_circle_or_shared_response_carries_a_mark(circle, clock):
    photo = circle.ana.post_photo(tz=INDY, caption="A good one.").json()
    mark(circle.ana, "2026-06-09", 5, INDY)
    circle.ben.anchor(photo["id"])
    circle.ana.anchor(photo["id"])
    # A page in the circle's book, and one for Ben alone.
    circle.ana.client.put(
        "/me/journal/today", json={"body": "Ours.", "ink": "black", "tz": INDY, "shared": True},
        headers=circle.ana.h,
    )
    circle.ana.client.put(
        f"/circles/{circle.id}/notes/mine", json={"text": "Hi all", "tz": INDY}, headers=circle.ana.h
    )
    payloads = []
    for api in (circle.ana, circle.ben, circle.cam):
        payloads += [
            api.feed().json(),
            api.client.get("/circles", headers=api.h).json(),
            api.client.get("/circles/mine", headers=api.h).json(),
            api.client.get(f"/circles/{circle.id}/journal", headers=api.h).json(),
            api.client.get(f"/circles/{circle.id}/notes", headers=api.h).json(),
            api.client.get(f"/circles/{circle.id}/prompt", headers=api.h).json(),
            api.client.get(f"/circles/{circle.id}/letters/mine", headers=api.h).json(),
            api.client.get(f"/members/{circle.ana.id}", headers=api.h).json(),
            api.memories().json(),
            api.returned().json(),
        ]
    # Ana's page, moved to Ben alone, as each of them reads the book.
    page = circle.ana.client.get("/me/journal", headers=circle.ana.h).json()["pages"][0]
    circle.ana.client.patch(
        f"/journal/{page['id']}", json={"shared": True, "recipient_id": circle.ben.id}, headers=circle.ana.h
    )
    for api in (circle.ana, circle.ben):
        payloads.append(api.client.get(f"/circles/{circle.id}/journal", headers=api.h).json())
    seen = 0
    for payload in payloads:
        for key, value in _walk(payload):
            seen += 1
            assert key not in MOOD_KEYS, (key, payload)
    assert seen > 50


def test_nothing_about_the_marks_counts_anything(circle, clock):
    """No field of any mark payload is a count, a streak, an average or a
    trend, and nothing but the days and the marks themselves is sent."""
    for offset in range(4):
        clock.set(utc(2026, 11, 10, 15) + timedelta(days=offset))
        day = (date(2026, 11, 10) + timedelta(days=offset)).isoformat()
        put = mark(circle.ana, day, 3, INDY).json()
        assert set(put) == {"day", "level"}
    got = circle.ana.client.get("/moods", headers=circle.ana.h).json()
    assert set(got) == {"moods"}
    for row in got["moods"]:
        assert set(row) == {"day", "level"}
    words = ("count", "total", "streak", "average", "mean", "trend", "sum", "run", "best", "most")
    for key, _ in _walk(got):
        assert not any(word in (key or "").lower() for word in words), key


def test_a_mark_notifies_nobody(circle, db):
    mark(circle.ana, "2026-06-09", 2, INDY)
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


def test_the_export_carries_the_marks(circle):
    import io
    import json
    import zipfile

    mark(circle.ana, "2026-06-09", 4, INDY)
    manifest = json.loads(zipfile.ZipFile(io.BytesIO(circle.ana.export().content)).read("memories.json"))
    assert manifest["moods"] == [{"day": "2026-06-09", "score": 4}]


# --- the copy builds 52 to 64 kept on the photo -------------------------------------------------


def test_the_photos_copy_is_moved_to_the_day_and_cleared(app, circle, clock, db):
    """Builds 52 to 64 kept the mark on the photo beside the day's row.
    On startup a day missing its row gets it from the photo, a day that
    has one keeps it, and the photo's copy is cleared."""
    first = circle.ana.post_photo(tz=INDY).json()
    clock.advance(timedelta(days=1))
    second = circle.ana.post_photo(tz=INDY).json()
    with db() as s:
        s.get(Photo, first["id"]).score = 4  # a day without its row
        s.get(Photo, second["id"]).score = 5
        s.add(DayMood(user_id=circle.ana.id, day=date(2026, 6, 10), score=2, updated_at=clock.now()))
        s.commit()
    ensure_schema(app.state.engine)
    assert marks(circle.ana) == [{"day": "2026-06-09", "level": 4}, {"day": "2026-06-10", "level": 2}]
    with db() as s:
        assert s.scalars(select(Photo.score).where(Photo.score.is_not(None))).all() == []
    # And again, it finds nothing to do.
    ensure_schema(app.state.engine)
    with app.state.engine.connect() as conn:
        assert conn.execute(text("SELECT count(*) FROM day_moods")).scalar() == 2
