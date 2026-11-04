"""Writing things down (build 26): the private journal entry on your own
photo, the reflection on your week, and the circle's question of the week.

The suite's clock starts on Tuesday 9 June 2026, 15:00 UTC (11:00 in New
York): that week began on Monday 8 June, its answers open on Saturday 13 June
at 00:00 UTC, and its Sunday evening in New York is 14 June."""
from __future__ import annotations

import io
import json
import zipfile
from datetime import date, datetime, timedelta, timezone

import pytest
from sqlalchemy import select, text

from stanley import journal, moderation
from stanley.db import ensure_schema, make_engine
from stanley.models import (
    CirclePrompt, JournalEntry, NotificationLog, PromptResponse, Report, WeeklyReflection,
)

from .conftest import NY, START, make_user
from .test_production import SLUR_STORY

SATURDAY = datetime(2026, 6, 13, 0, 0, tzinfo=timezone.utc)
SUNDAY_EVENING = datetime(2026, 6, 14, 22, 0, tzinfo=timezone.utc)  # 18:00 in New York


def put_entry(api, pid, body):
    return api.client.put(f"/photos/{pid}/journal", json={"body": body}, headers=api.h)


def get_entry(api, pid):
    return api.client.get(f"/photos/{pid}/journal", headers=api.h)


def reflect(api, body, tz=NY):
    return api.client.post("/me/reflections", json={"body": body, "tz": tz}, headers=api.h)


def question(api, circle_id):
    return api.client.get(f"/circles/{circle_id}/prompt", headers=api.h)


def answer(api, circle_id, body):
    return api.client.post(f"/circles/{circle_id}/prompt/respond", json={"body": body}, headers=api.h)


def answers(api, circle_id):
    return api.client.get(f"/circles/{circle_id}/prompt/responses", headers=api.h)


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


# --- the journal entry on your own photo -------------------------------------------------


def test_the_owner_writes_reads_rewrites_and_deletes_their_entry(circle):
    pid = circle.ana.post_photo().json()["id"]
    assert get_entry(circle.ana, pid).status_code == 404  # nothing written yet
    r = put_entry(circle.ana, pid, "  The fire alarm at 2am, and everyone on the lawn.  ")
    assert r.status_code == 200, r.text
    assert r.json()["body"] == "The fire alarm at 2am, and everyone on the lawn."
    first = r.json()
    r = put_entry(circle.ana, pid, "Pancakes after.")
    assert r.json()["body"] == "Pancakes after."
    assert r.json()["created_at"] == first["created_at"]  # one entry, rewritten
    assert get_entry(circle.ana, pid).json()["body"] == "Pancakes after."
    assert circle.ana.client.delete(f"/photos/{pid}/journal", headers=circle.ana.h).status_code == 204
    assert get_entry(circle.ana, pid).status_code == 404


def test_nobody_else_can_reach_an_entry(circle, client):
    pid = circle.ana.post_photo().json()["id"]
    put_entry(circle.ana, pid, "Only mine.")
    outsider = make_user(client, "zed")
    for someone in (circle.ben, outsider):
        assert get_entry(someone, pid).status_code == 404
        assert put_entry(someone, pid, "Mine now.").status_code == 404
        assert someone.client.delete(f"/photos/{pid}/journal", headers=someone.h).status_code == 404
    assert get_entry(circle.ana, pid).json()["body"] == "Only mine."


def test_the_feed_says_only_to_the_owner_that_an_entry_exists_never_what_it_says(circle):
    pid = circle.ana.post_photo(caption="lawn").json()["id"]
    put_entry(circle.ana, pid, "Words for no one else.")
    for viewer, flag in ((circle.ana, True), (circle.ben, None)):
        feed = viewer.feed().json()
        assert "Words for no one else." not in list(walk(feed))
        assert [p["has_journal"] for p in viewer.feed_photos() if p["id"] == pid] == [flag]
    other = circle.ben.post_photo().json()["id"]
    assert [p["has_journal"] for p in circle.ben.feed_photos() if p["id"] == other] == [False]


def test_an_entry_is_bounded_cleaned_and_filtered(circle, db):
    pid = circle.ana.post_photo().json()["id"]
    assert put_entry(circle.ana, pid, "x" * 1001).status_code == 422
    assert put_entry(circle.ana, pid, "x" * 1000).status_code == 200
    r = put_entry(circle.ana, pid, "   \n  ")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "empty_entry"
    r = put_entry(circle.ana, pid, SLUR_STORY)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    with db() as s:
        assert s.scalars(select(JournalEntry.body)).all() == ["x" * 1000]  # the refusal kept nothing


def test_an_entry_fades_with_the_photo_unless_its_owner_held_it(circle, clock, sweep, db):
    kept = circle.ana.post_photo().json()["id"]
    put_entry(circle.ana, kept, "I held this one.")
    circle.ana.anchor(kept)
    clock.advance(timedelta(days=1))
    others_hold = circle.ana.post_photo().json()["id"]
    put_entry(circle.ana, others_hold, "Ben held this one, not me.")
    circle.ben.anchor(others_hold)
    clock.advance(timedelta(days=1))
    faded = circle.ana.post_photo().json()["id"]
    put_entry(circle.ana, faded, "Nobody held this one.")

    clock.advance(timedelta(days=7))
    sweep()
    assert get_entry(circle.ana, kept).json()["body"] == "I held this one."
    # Ben keeps the photo, not Ana's words, which she could no longer reach.
    assert get_entry(circle.ana, others_hold).status_code == 404
    assert get_entry(circle.ana, faded).status_code == 404
    with db() as s:
        assert s.scalars(select(JournalEntry.photo_id)).all() == [kept]

    # Held shows her entry below her own photo, and nobody else's memory of
    # it carries the words.
    mine = [m for t in circle.ana.memories().json()["threads"] for m in t["memories"]]
    assert [(m["id"], m["journal"]) for m in mine] == [(kept, "I held this one.")]
    circle.ben.anchor(kept)  # too late: it's faded, so this changes nothing
    bens = [m for t in circle.ben.memories().json()["threads"] for m in t["memories"]]
    assert all(m.get("journal") is None for m in bens)

    # A held photo can still be written about; letting go of it takes the
    # entry with the hold.
    assert put_entry(circle.ana, kept, "Still thinking about it.").status_code == 200
    assert put_entry(circle.ana, faded, "Too late.").status_code == 410
    circle.ana.unanchor(kept)
    assert get_entry(circle.ana, kept).status_code == 404


def test_deleting_or_purging_the_photo_takes_the_entry(circle, clock, sweep, db):
    gone = circle.ana.post_photo().json()["id"]
    put_entry(circle.ana, gone, "Deleted soon.")
    circle.ben.anchor(gone)
    assert circle.ana.delete_photo(gone).status_code == 204
    assert get_entry(circle.ana, gone).status_code == 404
    clock.advance(timedelta(days=1))
    purged = circle.ana.post_photo().json()["id"]
    put_entry(circle.ana, purged, "Purged soon.")
    clock.advance(timedelta(days=15))
    sweep()
    sweep()
    with db() as s:
        assert s.scalars(select(JournalEntry)).all() == []


# --- your reflection on the week --------------------------------------------------------------


def test_a_reflection_is_for_the_week_it_was_written_in_one_a_week(circle, clock):
    clock.set(SUNDAY_EVENING)
    r = reflect(circle.ana, "A week of small fires and big pancakes.")
    assert r.status_code == 201, r.text
    body = r.json()
    assert (body["week_start"], body["week_end"]) == ("2026-06-08", "2026-06-14")
    again = reflect(circle.ana, "Another go.")
    assert again.status_code == 409 and again.json()["detail"]["code"] == "already_reflected"


def test_a_reflection_sent_just_after_midnight_stays_with_its_sunday(client, clock):
    ana = make_user(client, "ana")
    clock.set(datetime(2026, 6, 15, 4, 30, tzinfo=timezone.utc))  # Monday 00:30 in New York
    assert reflect(ana, "Late, but still Sunday's.").json()["week_start"] == "2026-06-08"
    clock.set(datetime(2026, 6, 22, 11, 0, tzinfo=timezone.utc))  # the next Monday, 07:00
    assert reflect(ana, "This one starts a week.").json()["week_start"] == "2026-06-22"


def test_reflections_are_listed_newest_first_a_page_at_a_time_and_only_to_their_writer(circle, clock):
    clock.set(SUNDAY_EVENING)
    ids = []
    for week in range(5):
        ids.append(reflect(circle.ana, f"Week {week}.").json()["id"])
        clock.advance(timedelta(days=7))
    h = circle.ana.h
    page = circle.ana.client.get("/me/reflections", params={"limit": 2}, headers=h).json()
    assert [r["body"] for r in page["reflections"]] == ["Week 4.", "Week 3."]
    seen = [r["id"] for r in page["reflections"]]
    while page["next_cursor"]:
        page = circle.ana.client.get(
            "/me/reflections", params={"limit": 2, "cursor": page["next_cursor"]}, headers=h
        ).json()
        seen += [r["id"] for r in page["reflections"]]
    assert seen == ids[::-1]
    assert circle.ana.client.get(f"/me/reflections/{ids[0]}", headers=h).json()["body"] == "Week 0."
    assert circle.ben.client.get("/me/reflections", headers=circle.ben.h).json()["reflections"] == []
    assert circle.ben.client.get(f"/me/reflections/{ids[0]}", headers=circle.ben.h).status_code == 404
    assert circle.ben.client.delete(f"/me/reflections/{ids[0]}", headers=circle.ben.h).status_code == 404
    assert circle.ana.client.delete(f"/me/reflections/{ids[0]}", headers=h).status_code == 204
    assert circle.ana.client.get(f"/me/reflections/{ids[0]}", headers=h).status_code == 404
    r = circle.ana.client.get("/me/reflections", params={"cursor": "nonsense"}, headers=h)
    assert r.status_code == 400


def test_the_week_shows_your_own_photos_still_alive_or_held_by_you(circle, clock, sweep):
    clock.advance(timedelta(minutes=1))  # joined after floor 3, which stays her first
    family = circle.ana.client.post("/circles", json={"name": "family"}, headers=circle.ana.h).json()["id"]
    clock.set(datetime(2026, 6, 8, 15, 0, tzinfo=timezone.utc))  # Monday
    kept = circle.ana.post_photo(caption="monday").json()["id"]
    circle.ana.anchor(kept)
    circle.ana.circle_id = family
    faded = circle.ana.post_photo(caption="monday, for family").json()["id"]  # nobody holds it
    circle.ana.circle_id = None
    clock.advance(timedelta(days=1))
    tuesday = circle.ana.post_photo(caption="tuesday").json()["id"]
    circle.ben.anchor(tuesday)  # Ben's keeping isn't Ana's
    circle.ben.post_photo()  # not hers
    clock.advance(timedelta(days=3))
    friday = circle.ana.post_photo(caption="friday").json()["id"]
    clock.advance(timedelta(days=1))
    saturday = circle.ana.post_photo(caption="saturday").json()["id"]
    circle.ana.delete_photo(saturday)

    clock.set(SUNDAY_EVENING)  # Monday's photos have had their six days
    sweep()
    week = circle.ana.client.get("/me/reflections/this-week", params={"tz": NY}, headers=circle.ana.h).json()
    assert (week["week_start"], week["week_end"], week["reflection"]) == ("2026-06-08", "2026-06-14", None)
    assert [(p["id"], p["held"]) for p in week["photos"]] == [(kept, True), (tuesday, False), (friday, False)]
    assert faded not in [p["id"] for p in week["photos"]]
    assert all(p["thumb"] and p["image"] for p in week["photos"])

    reflect(circle.ana, "Mostly the lawn.")
    week = circle.ana.client.get("/me/reflections/this-week", params={"tz": NY}, headers=circle.ana.h).json()
    assert week["reflection"]["body"] == "Mostly the lawn."
    assert [p["id"] for p in week["reflection"]["photos"]] == [kept, tuesday, friday]


def test_a_reflection_never_fades(circle, clock, sweep):
    clock.set(SUNDAY_EVENING)
    rid = reflect(circle.ana, "Kept.").json()["id"]
    clock.advance(timedelta(days=400))
    sweep()
    assert circle.ana.client.get(f"/me/reflections/{rid}", headers=circle.ana.h).json()["body"] == "Kept."


def test_a_reflection_is_bounded_cleaned_and_filtered(circle, clock):
    clock.set(SUNDAY_EVENING)
    assert reflect(circle.ana, "x" * 501).status_code == 422
    r = reflect(circle.ana, " \n ")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "empty_reflection"
    r = reflect(circle.ana, SLUR_STORY)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    r = reflect(circle.ana, "fine", tz="Mars/Olympus")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_timezone"
    assert reflect(circle.ana, "x" * 500).status_code == 201


# --- the circle's question of the week -----------------------------------------------------------


def test_everyone_in_a_circle_gets_the_same_question_this_week(circle, client):
    q = question(circle.ana, circle.id).json()
    assert q["prompt"]["text"] in journal.QUESTIONS
    assert (q["prompt"]["week_start"], q["prompt"]["week_end"]) == ("2026-06-08", "2026-06-14")
    assert datetime.fromisoformat(q["prompt"]["reveals_at"]) == SATURDAY
    assert (q["response"], q["revealed"]) == (None, False)
    assert question(circle.ben, circle.id).json()["prompt"] == q["prompt"]
    outsider = make_user(client, "zed")
    other = outsider.client.post("/circles", json={"name": "elsewhere"}, headers=outsider.h).json()
    assert question(outsider, circle.id).status_code == 404  # a circle you aren't in doesn't exist
    assert question(outsider, other["id"]).json()["prompt"]["id"] != q["prompt"]["id"]


def test_answers_are_sealed_until_saturday_then_read_by_everyone(circle, clock):
    r = answer(circle.ana, circle.id, "  The quiet after the alarm.  ")
    assert r.status_code == 201, r.text
    assert r.json()["response"]["body"] == "The quiet after the alarm."
    again = answer(circle.ana, circle.id, "Second thoughts.")
    assert again.status_code == 409 and again.json()["detail"]["code"] == "already_answered"
    clock.advance(timedelta(minutes=1))
    answer(circle.ben, circle.id, "Leaving the radiator on.")
    # Sealed: not even someone who answered can read the others yet, and
    # your own answer comes back only to you.
    sealed = answers(circle.ana, circle.id)
    assert sealed.status_code == 403 and sealed.json()["detail"]["code"] == "not_revealed"
    assert question(circle.ana, circle.id).json()["response"]["body"] == "The quiet after the alarm."
    assert question(circle.cam, circle.id).json()["response"] is None
    assert "Leaving the radiator on." not in list(walk(question(circle.ana, circle.id).json()))

    clock.set(SATURDAY - timedelta(seconds=1))
    assert answers(circle.cam, circle.id).status_code == 403
    clock.set(SATURDAY)
    assert question(circle.ana, circle.id).json()["revealed"] is True
    for reader in (circle.ana, circle.ben, circle.cam):  # cam never answered
        got = answers(reader, circle.id).json()
        assert [(a["author"]["display_name"], a["body"]) for a in got["responses"]] == [
            ("ana", "The quiet after the alarm."),
            ("ben", "Leaving the radiator on."),
        ]
    late = answer(circle.cam, circle.id, "Now that I've read yours...")
    assert late.status_code == 409 and late.json()["detail"]["code"] == "question_closed"


def test_nothing_about_the_question_counts_anyone(circle, clock):
    answer(circle.ana, circle.id, "One.")
    answer(circle.ben, circle.id, "Two.")
    clock.set(SATURDAY)
    for payload in (question(circle.cam, circle.id).json(), answers(circle.cam, circle.id).json()):
        keys = {k for k in walk(payload) if isinstance(k, str)}
        assert not any("count" in k or k.startswith("n_") or k == "total" for k in keys)
    assert set(answers(circle.cam, circle.id).json()) == {"prompt", "responses"}


def test_a_new_question_each_week_none_again_within_forty_weeks(circle, clock):
    seen = []
    for _ in range(40):
        seen.append(question(circle.ana, circle.id).json()["prompt"]["text"])
        clock.advance(timedelta(days=7))
    assert len(set(seen)) == 40
    # The forty-first may be any of them again, but not last week's.
    assert question(circle.ana, circle.id).json()["prompt"]["text"] != seen[-1]


def test_pick_question_skips_the_last_thirty_nine():
    recent = journal.QUESTIONS[:39]
    for _ in range(20):
        assert journal.pick_question(recent) == journal.QUESTIONS[39]


def test_a_block_hides_answers_both_ways(circle, clock):
    for api, words in ((circle.ana, "Ana's."), (circle.ben, "Ben's."), (circle.cam, "Cam's.")):
        answer(api, circle.id, words)
        clock.advance(timedelta(minutes=1))
    circle.ana.block(circle.ben.id)
    clock.set(SATURDAY)
    said = lambda api: [a["body"] for a in answers(api, circle.id).json()["responses"]]  # noqa: E731
    assert said(circle.ana) == ["Ana's.", "Cam's."]
    assert said(circle.ben) == ["Ben's.", "Cam's."]
    assert said(circle.cam) == ["Ana's.", "Ben's.", "Cam's."]


def test_an_answer_is_bounded_cleaned_and_filtered(circle):
    assert answer(circle.ana, circle.id, "x" * 301).status_code == 422
    r = answer(circle.ana, circle.id, "\n\n")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "empty_answer"
    r = answer(circle.ana, circle.id, SLUR_STORY)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    assert answer(circle.ana, circle.id, "x" * 300).status_code == 201


def test_the_circle_journal_keeps_every_answered_week_from_when_you_joined(circle, client, clock):
    weeks = []
    for week in range(4):
        q = question(circle.ana, circle.id).json()["prompt"]
        weeks.append(q["text"])
        if week != 2:  # nobody answered the third week
            answer(circle.ana, circle.id, f"Ana, week {week}.")
            clock.advance(timedelta(minutes=1))
            answer(circle.ben, circle.id, f"Ben, week {week}.")
        clock.advance(timedelta(days=7))
    # Now in week four's Tuesday: its answers aren't open, so it isn't here.
    question(circle.ana, circle.id)
    answer(circle.ana, circle.id, "Still sealed.")
    h = circle.cam.h
    page = circle.cam.client.get(f"/circles/{circle.id}/prompts", params={"limit": 2}, headers=h).json()
    got = page["prompts"]
    while page["next_cursor"]:
        page = circle.cam.client.get(
            f"/circles/{circle.id}/prompts", params={"limit": 2, "cursor": page["next_cursor"]}, headers=h
        ).json()
        got += page["prompts"]
    assert [p["text"] for p in got] == [weeks[3], weeks[1], weeks[0]]
    assert [a["body"] for a in got[0]["responses"]] == ["Ana, week 3.", "Ben, week 3."]
    assert "Still sealed." not in list(walk(got))

    # Someone who joins now reads from this week on, not what the circle
    # wrote before they were in it.
    dee = make_user(client, "dee")
    dee.join(circle.invite_token)
    assert dee.client.get(f"/circles/{circle.id}/prompts", headers=dee.h).json()["prompts"] == []
    clock.set(clock.now() + timedelta(days=4))  # this week's Saturday
    assert [p["text"] for p in dee.client.get(f"/circles/{circle.id}/prompts", headers=dee.h).json()["prompts"]] == [
        question(circle.ana, circle.id).json()["prompt"]["text"]
    ]


def test_an_answer_can_be_reported_once_it_can_be_read_and_taken_down(circle, clock, db, app):
    answer(circle.ben, circle.id, "Something cruel.")
    with db() as s:
        rid = s.scalars(select(PromptResponse.id)).one()
    assert circle.ana.report(response_id=rid, reason="cruel").status_code == 404  # not readable yet
    clock.set(SATURDAY)
    r = circle.ana.report(response_id=rid, reason="cruel")
    assert r.status_code == 201
    with db() as s:
        assert moderation.take_down_answer(s, rid, clock.now())
        s.commit()
    assert answers(circle.cam, circle.id).json()["responses"] == []
    with db() as s:
        report = s.get(Report, r.json()["id"])
        assert report.resolved_at is not None and report.response_id is None


def test_nothing_here_sends_a_notification(circle, clock, db):
    pid = circle.ana.post_photo().json()["id"]
    put_entry(circle.ana, pid, "quiet")
    answer(circle.ana, circle.id, "quiet")
    clock.set(SATURDAY)
    answers(circle.ben, circle.id)
    clock.set(SUNDAY_EVENING)
    reflect(circle.ana, "quiet")
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


def test_writing_is_limited_at_the_pace_of_stories(app, circle):
    app.state.settings.rate_limits = True
    app.state.rate_limiter.reset()
    pid = circle.ana.post_photo().json()["id"]
    for i in range(30):
        assert put_entry(circle.ana, pid, f"draft {i}").status_code == 200
    r = answer(circle.ana, circle.id, "one more")
    assert r.status_code == 429 and r.json()["detail"]["code"] == "slow_down"


# --- leaving, exporting, and the database --------------------------------------------------------


def test_deleting_an_account_takes_everything_they_wrote_down(circle, clock, db):
    pid = circle.ben.post_photo().json()["id"]
    put_entry(circle.ben, pid, "Ben's day.")
    answer(circle.ben, circle.id, "Ben's answer.")
    clock.advance(timedelta(minutes=1))
    answer(circle.ana, circle.id, "Ana's answer.")
    clock.set(SATURDAY)
    with db() as s:
        bens = s.scalars(select(PromptResponse.id).where(PromptResponse.user_id == circle.ben.id)).one()
    report = circle.ana.report(response_id=bens, reason="mean").json()["id"]
    clock.set(SUNDAY_EVENING)
    reflect(circle.ben, "Ben's week.")
    assert circle.ben.delete_me().status_code == 204
    with db() as s:
        assert s.scalars(select(JournalEntry)).all() == []
        assert s.scalars(select(WeeklyReflection)).all() == []
        assert s.scalars(select(PromptResponse.body)).all() == ["Ana's answer."]
        assert s.get(Report, report).response_id is None  # the report outlives the answer
    assert [a["body"] for a in answers(circle.cam, circle.id).json()["responses"]] == ["Ana's answer."]


def test_the_export_carries_what_you_wrote_down(circle, clock):
    pid = circle.ana.post_photo(caption="lawn").json()["id"]
    circle.ana.anchor(pid)
    put_entry(circle.ana, pid, "The alarm.")
    answer(circle.ana, circle.id, "The quiet.")
    clock.set(SUNDAY_EVENING)
    reflect(circle.ana, "A good one.")
    manifest = json.loads(zipfile.ZipFile(io.BytesIO(circle.ana.export().content)).read("memories.json"))
    assert manifest["held"][0]["journal"] == "The alarm."
    assert manifest["reflections"] == [{"week_start": "2026-06-08", "reflection": "A good one."}]
    [given] = manifest["answers"]
    assert (given["answer"], given["circle"], given["week_start"]) == ("The quiet.", "floor 3", "2026-06-08")
    assert given["question"] in journal.QUESTIONS
    # Ben's export has none of Ana's words.
    bens = circle.ben.export().content
    assert b"The alarm." not in bens and b"The quiet." not in bens


def test_an_older_database_gets_the_report_column():
    """A database from before build 26 has reports without the answer
    column (SQLite can't drop a column a foreign key names, so the old
    table is made as it was)."""
    engine = make_engine("sqlite://")
    with engine.begin() as conn:
        conn.execute(text(
            "CREATE TABLE reports (id VARCHAR(32) PRIMARY KEY, reporter_id VARCHAR(32), photo_id VARCHAR(32), "
            "comment_id VARCHAR(32), reason TEXT, created_at DATETIME, resolved_at DATETIME)"
        ))
    # And build 27's note column with it.
    assert ensure_schema(engine) == ["reports.response_id", "reports.note_id"]
    assert ensure_schema(engine) == []
    with engine.begin() as conn:
        indexes = {row[1] for row in conn.execute(text("PRAGMA index_list(reports)"))}
    assert "ix_reports_response" in indexes


def test_the_weeks():
    assert journal.question_week(START) == date(2026, 6, 8)
    assert journal.reveals_at(date(2026, 6, 8)) == SATURDAY
    assert journal.last_revealed_week(START) == date(2026, 6, 1)
    assert journal.last_revealed_week(SATURDAY) == date(2026, 6, 8)
    # A reflection's week is the writer's own: Sunday night in Tokyo is
    # already Monday morning in UTC... and it's still Sunday's week there.
    assert journal.reflection_week(datetime(2026, 6, 14, 12, 0, tzinfo=timezone.utc), "Asia/Tokyo") == date(2026, 6, 8)
    assert journal.reflection_week(datetime(2026, 6, 14, 22, 0, tzinfo=timezone.utc), "Asia/Tokyo") == date(2026, 6, 15)
