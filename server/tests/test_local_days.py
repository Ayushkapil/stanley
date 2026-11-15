"""Whose day it is (build 64). Every boundary a person lives as "today"
turns at their own midnight, in the zone their phone sends, not at
midnight UTC. Each is held three ways: a Bloomington evening (after 7 PM
EST, UTC is already tomorrow), a Delhi small hour (before 5:30 AM IST,
UTC is still yesterday), and the night the clocks went back in the US
(1 November 2026)."""
from __future__ import annotations

import io
import json
import zipfile
from datetime import datetime, timezone

import pytest
from sqlalchemy import select

from stanley.models import CircleNote

INDY = "America/Indiana/Indianapolis"
DELHI = "Asia/Kolkata"


def utc(y, mo, d, h, mi=0):
    return datetime(y, mo, d, h, mi, tzinfo=timezone.utc)


# Three moments where the person's day and UTC's differ.
BLOOMINGTON_EVENING = (INDY, utc(2026, 11, 16, 1), "2026-11-15")  # 8 PM EST, 15 Nov
DELHI_SMALL_HOURS = (DELHI, utc(2026, 11, 15, 21, 30), "2026-11-16")  # 3 AM IST, 16 Nov
CLOCKS_BACK_NIGHT = (INDY, utc(2026, 11, 2, 3), "2026-11-01")  # 10 PM EST, 1 Nov, hours after the change
CASES = pytest.mark.parametrize(
    "zone,now,local", [BLOOMINGTON_EVENING, DELHI_SMALL_HOURS, CLOCKS_BACK_NIGHT],
    ids=["bloomington", "delhi", "clocks-back"],
)


def _add_days(day: str, n: int) -> str:
    from datetime import date, timedelta
    return (date.fromisoformat(day) + timedelta(days=n)).isoformat()


# --- a sealed letter's week ---------------------------------------------------


def _send(sender, recipient_id, deliver_at, tz=None):
    data = {"recipient_id": recipient_id, "body": "Dear friend,", "deliver_at": deliver_at}
    if tz is not None:
        data["tz"] = tz
    return sender.client.post("/me/letters/send", json=data, headers=sender.h)


@CASES
def test_a_letter_is_a_week_from_the_senders_own_today(circle, clock, zone, now, local):
    clock.set(now)
    # The first day the picker offers is a week from the sender's today.
    r = _send(circle.ana, circle.ben.id, _add_days(local, 7), tz=zone)
    assert r.status_code == 201, r.text
    assert r.json()["deliver_at"] == _add_days(local, 7)
    # And the day before it is too soon, whatever UTC's day is.
    r = _send(circle.ana, circle.cam.id, _add_days(local, 6), tz=zone)
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "too_soon"


def test_a_letter_from_an_older_build_uses_the_zone_last_seen(circle, clock):
    zone, now, local = BLOOMINGTON_EVENING
    clock.set(now)
    circle.ana.post_photo(tz=zone)  # the phone said where it is
    r = _send(circle.ana, circle.ben.id, _add_days(local, 7))
    assert r.status_code == 201, r.text


def test_a_letter_with_a_zone_nobody_knows_is_refused(circle, clock):
    r = _send(circle.ana, circle.ben.id, _add_days("2026-06-09", 10), tz="Mars/Olympus")
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "bad_timezone"


# --- a note on the board -------------------------------------------------------


def _pin(u, circle_id, text, tz=None):
    body = {"text": text}
    if tz is not None:
        body["tz"] = tz
    return u.client.put(f"/circles/{circle_id}/notes/mine", json=body, headers=u.h)


def _expires(db, circle_id, author_id):
    with db() as session:
        note = session.scalars(
            select(CircleNote).where(CircleNote.circle_id == circle_id, CircleNote.author_id == author_id)
        ).one()
        return note.expires_at.replace(tzinfo=None)


@pytest.mark.parametrize(
    "zone,now,clears",
    [
        (INDY, utc(2026, 11, 16, 1), datetime(2026, 11, 16, 5)),  # 8 PM EST: clears at its midnight
        (DELHI, utc(2026, 11, 15, 21, 30), datetime(2026, 11, 16, 18, 30)),  # 3 AM IST: at the next midnight there
        (INDY, utc(2026, 11, 1, 2), datetime(2026, 11, 1, 4)),  # 10 PM EDT, 31 Oct: midnight still EDT
        (INDY, utc(2026, 11, 1, 17), datetime(2026, 11, 2, 5)),  # noon EST, 1 Nov: midnight now EST
    ],
    ids=["bloomington", "delhi", "before-the-change", "after-the-change"],
)
def test_a_note_clears_at_the_end_of_its_writers_own_day(circle, clock, db, zone, now, clears):
    clock.set(now)
    # A first note, before the phone has sent its zone with anything else.
    r = _pin(circle.ana, circle.id, "Pizza on the floor at nine", tz=zone)
    assert r.status_code == 200, r.text
    assert _expires(db, circle.id, circle.ana.id) == clears


def test_the_zone_sent_with_a_note_beats_the_one_last_seen(circle, clock, db):
    clock.set(utc(2026, 11, 16, 1))
    circle.ana.post_photo(tz="America/New_York")  # last seen somewhere else
    _pin(circle.ana, circle.id, "Back in Delhi", tz=DELHI)
    # 6:30 AM IST on the 16th: the note runs to the next midnight in Delhi.
    assert _expires(db, circle.id, circle.ana.id) == datetime(2026, 11, 16, 18, 30)


def test_a_note_with_a_zone_nobody_knows_is_refused(circle):
    r = _pin(circle.ana, circle.id, "hello", tz="Mars/Olympus")
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "bad_timezone"


# --- the day a held photo is dated by ------------------------------------------


@CASES
def test_a_held_photo_is_dated_by_its_posters_day(circle, clock, zone, now, local):
    clock.set(now)
    pid = circle.ana.post_photo(tz=zone).json()["id"]
    circle.ben.anchor(pid, note="kept")

    manifest = json.loads(zipfile.ZipFile(io.BytesIO(circle.ben.export().content)).read("memories.json"))
    entry = manifest["held"][0]
    assert entry["date"] == local
    assert local in entry["image"]

    # Deleted by its poster, the tombstone keeps the same day.
    circle.ana.delete_photo(pid)
    memory = circle.ben.memories().json()["threads"][0]["memories"][0]
    assert memory["tombstone"] is True
    assert memory["date"] == local


# --- already the person's own: held here so they stay so -----------------------


@pytest.mark.parametrize(
    "zone,first,second,third",
    [
        # Bloomington: 7:30 AM and 8 PM on the 15th are one day (UTC's 15th
        # and 16th); 8 AM on the 16th is the next.
        (INDY, utc(2026, 11, 15, 12, 30), utc(2026, 11, 16, 1), utc(2026, 11, 16, 13)),
        # Delhi: 4 AM and 6 PM on the 16th are one day (UTC's 15th and
        # 16th); 6 PM on the 17th is the next.
        (DELHI, utc(2026, 11, 15, 22, 30), utc(2026, 11, 16, 12, 30), utc(2026, 11, 17, 12, 30)),
        # The change: 1 AM EDT and 11 PM EST on 1 Nov are one day, 25
        # hours long; 2 AM EST on the 2nd is the next.
        (INDY, utc(2026, 11, 1, 5), utc(2026, 11, 2, 4), utc(2026, 11, 2, 7)),
    ],
    ids=["bloomington", "delhi", "clocks-back"],
)
def test_one_photo_a_day_is_the_posters_own_day(circle, clock, zone, first, second, third):
    clock.set(first)
    assert circle.ana.post_photo(tz=zone).status_code == 201
    clock.set(second)  # past the 12-hour gap, the same local day
    r = circle.ana.post_photo(tz=zone)
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "slot_used"
    clock.set(third)
    assert circle.ana.post_photo(tz=zone).status_code == 201


@CASES
def test_a_journal_page_is_the_writers_own_day(client, clock, zone, now, local):
    from .conftest import make_user

    me = make_user(client, "dee")
    clock.set(now)
    r = me.client.put("/me/journal/today", json={"body": "A long day.", "ink": "black", "tz": zone}, headers=me.h)
    assert r.status_code == 200, r.text
    assert r.json()["day"] == local
