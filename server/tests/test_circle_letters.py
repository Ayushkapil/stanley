"""Letters to the circle (build 42): one unsigned letter each a month,
sealed until the month is over for everyone in the circle, read together
for seven days, then gone.

The suite's clock starts on Tuesday 9 June 2026, 15:00 UTC (11:00 in New
York). June ends in New York on 1 July at 04:00 UTC, and in Honolulu six
hours later."""
from __future__ import annotations

import io
import json
import zipfile
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import select, text, update

from stanley import circle_letters, decay, moderation
from stanley.db import ensure_schema, make_engine
from stanley.models import CircleLetter, NotificationLog, Report

from .conftest import NY, START, make_user
from .test_production import SLUR_STORY

HONOLULU = "Pacific/Honolulu"
JULY_NY = datetime(2026, 7, 1, 4, 0, tzinfo=timezone.utc)
JULY_HONOLULU = datetime(2026, 7, 1, 10, 0, tzinfo=timezone.utc)
WEEK = timedelta(days=7)


def write(api, circle_id, body, tz=NY):
    return api.client.post(f"/circles/{circle_id}/letters", json={"body": body, "tz": tz}, headers=api.h)


def mine(api, circle_id, tz=NY):
    return api.client.get(f"/circles/{circle_id}/letters/mine", params={"tz": tz}, headers=api.h)


def reveal(api, circle_id):
    return api.client.get(f"/circles/{circle_id}/letters/reveal", headers=api.h)


def take_back(api, circle_id, month=None, tz=NY):
    params = {"tz": tz} | ({"month": month} if month else {})
    return api.client.delete(f"/circles/{circle_id}/letters/mine", params=params, headers=api.h)


def bodies(response):
    return sorted(letter["body"] for letter in response.json()["letters"])


def everyone_writes(circle, clock):
    """Ana, then Ben, then Cam, a minute apart, all in New York."""
    for api, words in ((circle.ana, "From A."), (circle.ben, "From B."), (circle.cam, "From C.")):
        assert write(api, circle.id, words).status_code == 200
        clock.advance(timedelta(minutes=1))


def walk(value):
    """Every key and every string in a JSON value."""
    if isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from walk(v)
    elif isinstance(value, list):
        for v in value:
            yield from walk(v)
    elif isinstance(value, str):
        yield value


# --- writing ---------------------------------------------------------------------------


def test_a_letter_is_written_read_back_and_rewritten(circle, db):
    r = write(circle.ana, circle.id, "  I think we should all slow down a little.  ")
    assert r.status_code == 200, r.text
    state = r.json()
    assert state["month"] == "2026-06" and state["open"] is True
    assert state["letter"]["body"] == "I think we should all slow down a little."
    assert state["reveals_at"] == JULY_NY.isoformat()
    assert state["revealed"] is None
    first = state["letter"]["id"]
    # Writing again is the same letter, changed: one a month.
    again = write(circle.ana, circle.id, "Slower, and kinder.").json()["letter"]
    assert again == {"id": first, "body": "Slower, and kinder."}
    assert mine(circle.ana, circle.id).json()["letter"] == again
    with db() as s:
        assert s.scalars(select(CircleLetter.body)).all() == ["Slower, and kinder."]


def test_a_new_month_is_a_new_letter(circle, clock, db):
    write(circle.ana, circle.id, "June's.")
    clock.set(JULY_NY + timedelta(hours=1))
    state = write(circle.ana, circle.id, "July's.").json()
    assert state["month"] == "2026-07" and state["letter"]["body"] == "July's."
    with db() as s:
        rows = s.execute(select(CircleLetter.month, CircleLetter.body).order_by(CircleLetter.month)).all()
    assert rows == [(date(2026, 6, 1), "June's."), (date(2026, 7, 1), "July's.")]


def test_nobody_can_tell_who_has_written_or_how_many(circle):
    """What Ben is told about the month is the same before and after the
    others write, down to the byte."""
    before = mine(circle.ben, circle.id).content
    write(circle.ana, circle.id, "One.")
    write(circle.cam, circle.id, "Two.")
    assert mine(circle.ben, circle.id).content == before
    assert mine(circle.ben, circle.id).json() == {
        "month": "2026-06", "open": True, "reveals_at": JULY_NY.isoformat(), "letter": None, "revealed": None,
    }
    # And what Ana gets back from writing says nothing of Cam's.
    assert "Two." not in write(circle.ana, circle.id, "One, again.").text


def test_words_are_cleaned_bounded_and_filtered(circle):
    assert write(circle.ana, circle.id, "   \n ").json()["detail"]["code"] == "empty_circle_letter"
    assert write(circle.ana, circle.id, "x" * 500).status_code == 200
    assert write(circle.ana, circle.id, "x" * 501).status_code == 422
    r = write(circle.ana, circle.id, SLUR_STORY)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    assert write(circle.ana, circle.id, "fine", tz="Mars/Olympus").json()["detail"]["code"] == "bad_timezone"
    # The refused ones changed nothing.
    assert mine(circle.ana, circle.id).json()["letter"]["body"] == "x" * 500


def test_only_people_in_the_circle(circle, client):
    eve = make_user(client, "eve")
    assert write(eve, circle.id, "hello").status_code == 409  # in no circle at all
    eve.client.post("/circles", json={"name": "elsewhere"}, headers=eve.h)
    for r in (write(eve, circle.id, "hello"), mine(eve, circle.id), reveal(eve, circle.id), take_back(eve, circle.id)):
        assert r.status_code == 404


def test_writing_is_limited_at_the_pace_of_stories(app, circle):
    app.state.settings.rate_limits = True
    app.state.rate_limiter.reset()
    for i in range(30):
        assert write(circle.ana, circle.id, f"draft {i}").status_code == 200
    r = write(circle.ana, circle.id, "one more")
    assert r.status_code == 429 and r.json()["detail"]["code"] == "slow_down"


# --- the reveal ------------------------------------------------------------------------


def test_letters_are_sealed_until_the_month_ends_then_open_to_everyone(circle, clock):
    everyone_writes(circle, clock)
    dee = make_user(circle.ana.client, "dee")  # in the circle, and wrote nothing
    dee.join(circle.invite_token)
    mine(dee, circle.id)
    clock.set(JULY_NY - timedelta(seconds=1))
    for api in (circle.ana, dee):
        r = reveal(api, circle.id)
        assert r.status_code == 403 and r.json()["detail"]["code"] == "circle_letters_sealed"
        assert mine(api, circle.id).json()["revealed"] is None
    clock.set(JULY_NY)
    for api in (circle.ana, circle.ben, circle.cam, dee):
        r = reveal(api, circle.id)
        assert r.status_code == 200, r.text
        assert bodies(r) == ["From A.", "From B.", "From C."]
        assert r.json()["month"] == "2026-06"
        assert r.json()["revealed_at"] == JULY_NY.isoformat()
        assert r.json()["fades_at"] == (JULY_NY + WEEK).isoformat()


def test_a_letter_leaves_the_server_as_its_id_and_words_and_nothing_else(circle, clock, db):
    everyone_writes(circle, clock)
    clock.set(JULY_NY)
    payload = reveal(circle.ben, circle.id).json()
    assert set(payload) == {"month", "revealed_at", "fades_at", "letters"}
    assert all(set(letter) == {"id", "body"} for letter in payload["letters"])
    with db() as s:
        rows = s.scalars(select(CircleLetter)).all()
        times = {r.created_at.isoformat() for r in rows} | {r.updated_at.isoformat() for r in rows}
    said = set(walk(payload))
    for person in (circle.ana, circle.ben, circle.cam):
        assert person.id not in said and person.name not in said
    assert not (said & times)
    assert not ({"author", "author_id", "user", "user_id", "mine", "created_at", "updated_at", "count"} & said)
    # Ben's own letter is named to him only where he asks for his own.
    own = mine(circle.ben, circle.id).json()["revealed"]
    assert own["letter"]["body"] == "From B." and set(own["letter"]) == {"id", "body"}
    assert set(own) == {"month", "revealed_at", "fades_at", "letter"}
    assert circle.ana.id not in mine(circle.ben, circle.id).text


def test_the_order_is_the_ids_not_the_order_written(circle, clock, db):
    everyone_writes(circle, clock)  # Ana first, Cam last
    with db() as s:
        for person, new in ((circle.ana, "c" * 32), (circle.ben, "b" * 32), (circle.cam, "a" * 32)):
            s.execute(update(CircleLetter).where(CircleLetter.author_id == person.id).values(id=new))
        s.commit()
    clock.set(JULY_NY)
    shown = reveal(circle.ana, circle.id).json()["letters"]
    assert [letter["body"] for letter in shown] == ["From C.", "From B.", "From A."]
    # The same for everyone, every time.
    assert reveal(circle.cam, circle.id).json()["letters"] == shown
    assert reveal(circle.ana, circle.id).json()["letters"] == shown


def test_a_letter_cannot_be_changed_once_they_are_open(circle, clock):
    everyone_writes(circle, clock)
    clock.set(JULY_NY + timedelta(minutes=10))
    assert reveal(circle.ben, circle.id).status_code == 200
    # Writing now is July's letter; June's is as it was.
    state = write(circle.ana, circle.id, "Having read the rest...").json()
    assert state["month"] == "2026-07"
    assert bodies(reveal(circle.ben, circle.id)) == ["From A.", "From B.", "From C."]
    # Someone whose own June outlasted the circle's (their phone now says
    # Honolulu) can't add to what everyone has already read.
    r = write(circle.cam, circle.id, "A late one.", tz=HONOLULU)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "circle_letters_opened"
    state = mine(circle.cam, circle.id, tz=HONOLULU).json()
    assert state["month"] == "2026-06" and state["open"] is False and state["letter"] is None
    assert bodies(reveal(circle.ben, circle.id)) == ["From A.", "From B.", "From C."]


def test_the_letters_wait_for_the_last_midnight_in_the_circle(circle, clock):
    """One moment for everyone: when June is over for the member furthest
    west, so nobody is still writing while others read."""
    write(circle.ana, circle.id, "From New York.")
    write(circle.ben, circle.id, "From Honolulu.", tz=HONOLULU)
    assert mine(circle.ana, circle.id).json()["reveals_at"] == JULY_HONOLULU.isoformat()
    clock.set(JULY_NY + timedelta(hours=1))
    assert reveal(circle.ana, circle.id).status_code == 403
    # Ben's June isn't over: he can still change his.
    assert write(circle.ben, circle.id, "From Honolulu, later.", tz=HONOLULU).status_code == 200
    clock.set(JULY_HONOLULU)
    assert bodies(reveal(circle.ana, circle.id)) == ["From Honolulu, later.", "From New York."]
    assert reveal(circle.ana, circle.id).json()["revealed_at"] == JULY_HONOLULU.isoformat()


def test_the_sweep_opens_them_with_nobody_asking(circle, clock, db):
    everyone_writes(circle, clock)
    clock.set(JULY_NY - timedelta(minutes=5))
    with db() as s:
        assert decay.open_letters(s, clock) == 0
        s.commit()
    clock.set(JULY_NY + timedelta(minutes=20))  # the sweep comes by late
    with db() as s:
        assert decay.open_letters(s, clock) == 3
        assert decay.open_letters(s, clock) == 0  # once
        s.commit()
        # Stamped with the moment they opened, not the moment it was noticed.
        assert {r for r in s.scalars(select(CircleLetter.revealed_at)).all()} == {JULY_NY}


def test_someone_who_joins_after_they_open_does_not_read_them(circle, clock):
    everyone_writes(circle, clock)
    clock.set(JULY_NY + timedelta(days=1))
    assert reveal(circle.ana, circle.id).status_code == 200
    dee = make_user(circle.ana.client, "dee")
    dee.join(circle.invite_token)
    assert reveal(dee, circle.id).status_code == 403
    assert mine(dee, circle.id).json()["revealed"] is None


def test_a_block_hides_no_letter(circle, clock):
    """Hiding a blocked person's letter would say which one was theirs."""
    everyone_writes(circle, clock)
    clock.set(JULY_NY)
    before = reveal(circle.ben, circle.id).json()
    assert circle.ben.block(circle.ana.id).status_code == 204
    assert reveal(circle.ben, circle.id).json() == before
    assert reveal(circle.ana, circle.id).json() == before


# --- seven days, then gone -------------------------------------------------------------


def test_they_are_read_for_seven_days_then_deleted(circle, clock, db):
    everyone_writes(circle, clock)
    clock.set(JULY_NY + WEEK - timedelta(seconds=1))
    assert reveal(circle.cam, circle.id).status_code == 200
    with db() as s:
        assert decay.clear_letters(s, clock) == 0
    # Gone on the hour, whether or not the sweep has been by.
    clock.set(JULY_NY + WEEK)
    assert reveal(circle.cam, circle.id).status_code == 403
    assert mine(circle.cam, circle.id).json()["revealed"] is None
    with db() as s:
        assert s.scalars(select(CircleLetter)).all() != []
        assert decay.clear_letters(s, clock) == 3
        s.commit()
        assert s.scalars(select(CircleLetter)).all() == []


def test_a_sealed_letter_is_never_cleared(circle, clock, db):
    write(circle.ana, circle.id, "Still sealed.")
    clock.advance(timedelta(days=20))
    with db() as s:
        assert decay.clear_letters(s, clock) == 0
        assert decay.open_letters(s, clock) == 0


# --- taking one back -------------------------------------------------------------------


def test_the_writer_takes_their_letter_back_before_and_after(circle, clock):
    everyone_writes(circle, clock)
    assert take_back(circle.ana, circle.id).status_code == 204  # sealed: this month's
    assert mine(circle.ana, circle.id).json()["letter"] is None
    assert take_back(circle.ana, circle.id).status_code == 204  # nothing there: still fine
    clock.set(JULY_NY)
    assert bodies(reveal(circle.ana, circle.id)) == ["From B.", "From C."]
    # Opened: named by its month, and it goes for everyone.
    assert take_back(circle.ben, circle.id, month="2026-06").status_code == 204
    assert bodies(reveal(circle.cam, circle.id)) == ["From C."]
    assert mine(circle.ben, circle.id).json()["revealed"]["letter"] is None
    # Only ever your own: Ben's delete took nothing of Cam's, and without a
    # month it's about July, where nobody has written.
    assert take_back(circle.ben, circle.id).status_code == 204
    assert bodies(reveal(circle.cam, circle.id)) == ["From C."]
    assert take_back(circle.ben, circle.id, month="June").json()["detail"]["code"] == "bad_month"


def test_leaving_takes_a_sealed_letter_and_leaves_an_opened_one(circle, clock, db):
    everyone_writes(circle, clock)
    assert circle.ben.leave(circle.id).status_code == 204
    assert circle.ana.remove_member(circle.id, circle.cam.id).status_code == 204
    with db() as s:
        assert s.scalars(select(CircleLetter.body)).all() == ["From A."]
    # Opened letters stay their week: one going with its writer would say
    # whose it was (and the organizer could remove people to find out).
    dee = make_user(circle.ana.client, "dee")
    dee.join(circle.invite_token)
    write(dee, circle.id, "From D.")
    clock.set(JULY_NY)
    assert bodies(reveal(circle.ana, circle.id)) == ["From A.", "From D."]
    assert circle.ana.remove_member(circle.id, dee.id).status_code == 204
    assert bodies(reveal(circle.ana, circle.id)) == ["From A.", "From D."]


def test_deleting_an_account_takes_their_letters(circle, clock, db):
    everyone_writes(circle, clock)
    clock.set(JULY_NY)
    write(circle.ben, circle.id, "Ben's July.")
    assert circle.ben.delete_me().status_code == 204
    with db() as s:
        assert sorted(s.scalars(select(CircleLetter.body)).all()) == ["From A.", "From C."]
    assert bodies(reveal(circle.ana, circle.id)) == ["From A.", "From C."]


def test_the_export_carries_your_own_letters_only(circle, clock):
    everyone_writes(circle, clock)
    manifest = json.loads(zipfile.ZipFile(io.BytesIO(circle.ana.export().content)).read("memories.json"))
    assert manifest["letters"] == [{"month": "2026-06", "circle": "floor 3", "letter": "From A."}]
    assert b"From B." not in circle.ana.export().content


# --- reports ---------------------------------------------------------------------------


def test_a_letter_can_be_reported_once_open_and_the_report_knows_who_wrote_it(circle, clock, db):
    everyone_writes(circle, clock)
    with db() as s:
        bens = s.scalars(select(CircleLetter.id).where(CircleLetter.author_id == circle.ben.id)).one()
    assert circle.ana.report(circle_letter_id=bens, reason="cruel").status_code == 404  # sealed: unread
    clock.set(JULY_NY)
    reveal(circle.ana, circle.id)
    r = circle.ana.report(circle_letter_id=bens, reason="cruel")
    assert r.status_code == 201, r.text
    # The reporter learns nothing about whose it was.
    assert set(r.json()) == {"id", "review_within_hours"} and circle.ben.id not in r.text
    with db() as s:
        report = s.get(Report, r.json()["id"])
        assert report.circle_letter_id == bens
        assert circle.ben.id in report.reason and "From B." in report.reason and circle.id in report.reason
    # Its writer takes it back: the report still has the words and the writer.
    take_back(circle.ben, circle.id, month="2026-06")
    with db() as s:
        report = s.get(Report, r.json()["id"])
        assert "From B." in report.reason and report.resolved_at is None


def test_the_operator_takes_a_letter_down(circle, clock, db):
    everyone_writes(circle, clock)
    clock.set(JULY_NY)
    shown = {letter["body"]: letter["id"] for letter in reveal(circle.ana, circle.id).json()["letters"]}
    report = circle.ana.report(circle_letter_id=shown["From C."], reason="a threat").json()["id"]
    with db() as s:
        assert moderation.take_down_circle_letter(s, shown["From C."], clock.now())
        assert not moderation.take_down_circle_letter(s, shown["From C."], clock.now())
        s.commit()
    assert bodies(reveal(circle.ben, circle.id)) == ["From A.", "From B."]
    with db() as s:
        assert s.get(Report, report).resolved_at is not None


def test_only_a_letter_you_could_read_can_be_reported(circle, clock, db):
    everyone_writes(circle, clock)
    clock.set(JULY_NY)
    letter = reveal(circle.ana, circle.id).json()["letters"][0]["id"]
    clock.advance(timedelta(minutes=1))
    dee = make_user(circle.ana.client, "dee")
    dee.join(circle.invite_token)  # after they opened
    assert dee.report(circle_letter_id=letter, reason="x").status_code == 404
    assert circle.ana.report(circle_letter_id="nope", reason="x").status_code == 404
    clock.set(JULY_NY + WEEK)  # gone
    assert circle.ana.report(circle_letter_id=letter, reason="x").status_code == 404


# --- what it never does ----------------------------------------------------------------


def test_nothing_here_sends_a_notification(circle, clock, db):
    everyone_writes(circle, clock)
    clock.set(JULY_NY)
    with db() as s:
        decay.open_letters(s, clock)
        s.commit()
    reveal(circle.ben, circle.id)
    clock.set(JULY_NY + WEEK)
    with db() as s:
        decay.clear_letters(s, clock)
        s.commit()
        assert s.scalars(select(NotificationLog)).all() == []


# --- the months, and the database ------------------------------------------------------


def test_the_months():
    assert circle_letters.month_of(START, NY) == date(2026, 6, 1)
    # 1 July, 02:00 UTC: already July in London, still June in New York.
    early = datetime(2026, 7, 1, 2, 0, tzinfo=timezone.utc)
    assert circle_letters.month_of(early, "Europe/London") == date(2026, 7, 1)
    assert circle_letters.month_of(early, NY) == date(2026, 6, 1)
    assert circle_letters.next_month(date(2026, 12, 1)) == date(2027, 1, 1)
    assert circle_letters.month_end(date(2026, 6, 1), NY) == JULY_NY
    assert circle_letters.month_end(date(2026, 12, 1), "Asia/Kolkata") == datetime(
        2026, 12, 31, 18, 30, tzinfo=timezone.utc
    )
    # The last midnight among them; a zone nobody can read is passed over,
    # and with none at all it's the month's end in UTC.
    assert circle_letters.opens_at(date(2026, 6, 1), [NY, "Asia/Kolkata", HONOLULU, None, "Mars/Olympus"]) == JULY_HONOLULU
    assert circle_letters.opens_at(date(2026, 6, 1), []) == datetime(2026, 7, 1, tzinfo=timezone.utc)
    assert circle_letters.opens_at(date(2026, 6, 1), ["Mars/Olympus"]) == datetime(2026, 7, 1, tzinfo=timezone.utc)
    # Nowhere is a month over before it's over at UTC+14.
    assert circle_letters.month_end(date(2026, 6, 1), circle_letters.EARLIEST_ZONE) == datetime(
        2026, 6, 30, 10, 0, tzinfo=timezone.utc
    )
    assert circle_letters.label(date(2026, 6, 1)) == "2026-06"
    assert circle_letters.parse("2026-06") == date(2026, 6, 1)
    for bad in ("June", "2026-13", "2026-6", "26-06", "2026-06-01", ""):
        assert circle_letters.parse(bad) is None


def test_an_older_database_gets_the_report_column():
    """A database from before build 42 has reports without the letter column."""
    engine = make_engine("sqlite://")
    with engine.begin() as conn:
        conn.execute(text(
            "CREATE TABLE reports (id VARCHAR(32) PRIMARY KEY, reporter_id VARCHAR(32), photo_id VARCHAR(32), "
            "comment_id VARCHAR(32), response_id VARCHAR(32), note_id VARCHAR(32), letter_id VARCHAR(32), reason TEXT, "
            "created_at DATETIME, resolved_at DATETIME)"
        ))
    assert ensure_schema(engine) == ["reports.circle_letter_id"]
    assert ensure_schema(engine) == []
