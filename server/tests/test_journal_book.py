"""The journal as a book (build 45): a page a day in the writer's own words
and ink, and what they call the journal. Nobody else reads any of it.

The suite's clock starts on Tuesday 9 June 2026, 15:00 UTC: 11:00 that
morning in New York, and already midnight on Wednesday the 10th in Tokyo."""
from __future__ import annotations

import io
import json
import zipfile
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import select, text

from stanley import journal
from stanley.db import ensure_schema, make_engine
from stanley.models import JournalPage, NotificationLog, User

from .conftest import NY
from .test_production import SLUR_STORY

TOKYO = "Asia/Tokyo"


def write(api, body, ink="black", tz=NY):
    return api.client.put("/me/journal/today", json={"body": body, "ink": ink, "tz": tz}, headers=api.h)


def book(api, **query):
    return api.client.get("/me/journal", params=query, headers=api.h)


def edit(api, page_id, **fields):
    return api.client.patch(f"/me/journal/pages/{page_id}", json=fields, headers=api.h)


def tear_out(api, page_id):
    return api.client.delete(f"/me/journal/pages/{page_id}", headers=api.h)


def name(api, title):
    return api.client.put("/me/journal/title", json={"title": title}, headers=api.h)


def days(api):
    return [(p["day"], p["body"]) for p in book(api).json()["pages"]]


# --- writing a page -------------------------------------------------------------------------------


def test_a_page_is_written_and_read_back(circle):
    r = write(circle.ana, "Rain all morning.\nThe lawn after.", ink="blue")
    assert r.status_code == 200
    page = r.json()
    assert (page["day"], page["body"], page["ink"]) == ("2026-06-09", "Rain all morning.\nThe lawn after.", "blue")
    got = book(circle.ana).json()
    assert got["pages"] == [page] and got["next_after"] is None and got["title"] is None


def test_one_page_a_day_and_writing_again_replaces_it(circle, clock, db):
    first = write(circle.ana, "First go.").json()
    clock.advance(timedelta(hours=3))
    second = write(circle.ana, "What I meant.", ink="red").json()
    assert second["id"] == first["id"] and second["created_at"] == first["created_at"]
    assert second["updated_at"] != first["updated_at"]
    assert days(circle.ana) == [("2026-06-09", "What I meant.")]
    with db() as s:
        assert len(s.scalars(select(JournalPage)).all()) == 1


def test_the_day_is_the_writers_own(circle):
    # The same moment is Tuesday in New York and Wednesday in Tokyo.
    assert write(circle.ana, "Morning here.", tz=NY).json()["day"] == "2026-06-09"
    assert write(circle.ben, "Past midnight here.", tz=TOKYO).json()["day"] == "2026-06-10"


def test_the_zone_is_remembered_and_a_bad_one_is_refused(circle, db):
    r = write(circle.ana, "Where am I.", tz="Mars/Olympus")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_timezone"
    write(circle.ana, "Here.", tz=TOKYO)
    with db() as s:
        assert s.get(User, circle.ana.id).tz_last_seen == TOKYO
    # With none sent, the last one the phone gave stands.
    r = circle.ana.client.put("/me/journal/today", json={"body": "Still here."}, headers=circle.ana.h)
    assert r.json()["day"] == "2026-06-10"


def test_a_new_day_is_a_new_page_and_the_book_reads_oldest_first(circle, clock):
    write(circle.ana, "Tuesday.")
    clock.advance(timedelta(days=1))
    write(circle.ana, "Wednesday.")
    clock.advance(timedelta(days=2))
    write(circle.ana, "Friday.")
    assert days(circle.ana) == [("2026-06-09", "Tuesday."), ("2026-06-10", "Wednesday."), ("2026-06-12", "Friday.")]


def test_the_book_comes_a_stretch_at_a_time(circle, clock):
    for i in range(5):
        write(circle.ana, f"Day {i}.")
        clock.advance(timedelta(days=1))
    first = book(circle.ana, limit=2).json()
    assert [p["body"] for p in first["pages"]] == ["Day 0.", "Day 1."] and first["next_after"] == "2026-06-10"
    second = book(circle.ana, limit=2, after=first["next_after"]).json()
    assert [p["body"] for p in second["pages"]] == ["Day 2.", "Day 3."]
    last = book(circle.ana, limit=2, after=second["next_after"]).json()
    assert [p["body"] for p in last["pages"]] == ["Day 4."] and last["next_after"] is None


def test_only_three_inks(circle):
    for ink in journal.INKS:
        assert write(circle.ana, "In ink.", ink=ink).json()["ink"] == ink
    r = write(circle.ana, "In green.", ink="green")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_ink"
    page = book(circle.ana).json()["pages"][0]
    r = edit(circle.ana, page["id"], ink="violet")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_ink"


def test_a_page_is_cleaned_and_keeps_its_lines(circle):
    page = write(circle.ana, "  One line.\r\n\r\nAnother\x00 one‮.\t  ").json()
    assert page["body"] == "One line.\n\nAnother one."


def test_a_blank_page_is_not_a_page(circle):
    r = write(circle.ana, "   \n\n  ")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "empty_page"
    assert circle.ana.client.put("/me/journal/today", json={"body": ""}, headers=circle.ana.h).status_code == 422
    assert book(circle.ana).json()["pages"] == []


def test_a_page_is_as_long_as_a_day_needs_and_no_longer_than_a_request_should_be(circle):
    long = ("A sentence about the day. " * 400).strip()  # about ten thousand characters
    assert write(circle.ana, long).json()["body"] == long
    assert write(circle.ana, "x" * (journal.PAGE_MAX + 1)).status_code == 422


def test_a_private_page_isnt_run_past_the_word_filter(circle):
    """The filter is for what a circle reads. A page nobody else can read
    that refused its writer's own account of their day would protect no one."""
    assert write(circle.ana, SLUR_STORY).status_code == 200


# --- changing one ---------------------------------------------------------------------------------


def test_editing_a_page_keeps_its_day(circle, clock):
    page = write(circle.ana, "Tuesday.").json()
    clock.advance(timedelta(days=4))
    r = edit(circle.ana, page["id"], body="Tuesday, looking back.")
    assert r.status_code == 200
    changed = r.json()
    assert (changed["day"], changed["body"], changed["ink"]) == ("2026-06-09", "Tuesday, looking back.", "black")
    assert changed["updated_at"] != page["updated_at"]
    assert days(circle.ana) == [("2026-06-09", "Tuesday, looking back.")]


def test_changing_only_the_ink_leaves_the_words(circle):
    page = write(circle.ana, "In black.").json()
    changed = edit(circle.ana, page["id"], ink="red").json()
    assert (changed["body"], changed["ink"]) == ("In black.", "red")


def test_an_edit_cant_blank_a_page(circle):
    page = write(circle.ana, "Words.").json()
    r = edit(circle.ana, page["id"], body="  \n ")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "empty_page"
    assert days(circle.ana) == [("2026-06-09", "Words.")]


def test_tearing_a_page_out(circle):
    page = write(circle.ana, "Not this one.").json()
    assert tear_out(circle.ana, page["id"]).status_code == 204
    assert book(circle.ana).json()["pages"] == []
    assert tear_out(circle.ana, page["id"]).status_code == 404
    # The day is free again: a page written after it is a new one.
    assert write(circle.ana, "This one.").json()["id"] != page["id"]


# --- nobody else's --------------------------------------------------------------------------------


def test_nobody_else_can_read_change_or_remove_a_page(circle):
    page = write(circle.ana, "Mine.").json()
    assert book(circle.ben).json()["pages"] == []
    assert edit(circle.ben, page["id"], body="Ben's now.").status_code == 404
    assert edit(circle.ben, page["id"], ink="red").status_code == 404
    assert tear_out(circle.ben, page["id"]).status_code == 404
    assert days(circle.ana) == [("2026-06-09", "Mine.")]


def test_a_page_is_in_nothing_anyone_else_is_sent(circle):
    words = "Nobody reads this but me."
    write(circle.ana, words)
    name(circle.ana, "Ana's secret book")
    circle.ana.post_photo(caption="lawn")
    seen = [
        circle.ben.feed().text,
        circle.ben.client.get(f"/members/{circle.ana.id}", headers=circle.ben.h).text,
        circle.ben.client.get("/circles/mine", headers=circle.ben.h).text,
        circle.ben.client.get("/me", headers=circle.ben.h).text,
        circle.ben.memories().text,
    ]
    for body in seen:
        assert words not in body and "secret book" not in body


def test_the_book_needs_a_sign_in(client):
    assert client.get("/me/journal").status_code == 401
    assert client.put("/me/journal/today", json={"body": "x"}).status_code == 401
    assert client.put("/me/journal/title", json={"title": "x"}).status_code == 401


def test_writing_a_page_notifies_nobody(circle, db):
    write(circle.ana, "Quietly.")
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


def test_nothing_about_the_book_counts_anything(circle):
    write(circle.ana, "One.")

    def keys(value):
        if isinstance(value, dict):
            for k, v in value.items():
                yield k
                yield from keys(v)
        elif isinstance(value, list):
            for v in value:
                yield from keys(v)

    for key in keys(book(circle.ana).json()):
        assert "count" not in key and "total" not in key and "streak" not in key


# --- what it's called -----------------------------------------------------------------------------


def test_naming_the_journal(circle):
    assert name(circle.ana, "  The Third Floor Years ").json() == {"title": "The Third Floor Years"}
    assert book(circle.ana).json()["title"] == "The Third Floor Years"
    assert book(circle.ben).json()["title"] is None
    # Blank puts the app's own title back.
    assert name(circle.ana, "   ").json() == {"title": None}
    assert book(circle.ana).json()["title"] is None


def test_a_title_is_cleaned_and_bounded(circle):
    assert name(circle.ana, "Mine\x00‮\nalone").json()["title"] == "Minealone"
    r = name(circle.ana, "x" * (journal.TITLE_MAX + 1))
    assert r.status_code == 400 and r.json()["detail"]["code"] == "title_too_long"
    assert name(circle.ana, "x" * journal.TITLE_MAX).status_code == 200


# --- pace, leaving, exporting, and the database ---------------------------------------------------


def test_pages_are_written_at_the_pace_of_other_writing(app, circle):
    app.state.settings.rate_limits = True
    app.state.rate_limiter.reset()
    for i in range(30):
        assert write(circle.ana, f"draft {i}").status_code == 200
    r = write(circle.ana, "one more")
    assert r.status_code == 429 and r.json()["detail"]["code"] == "slow_down"


def test_deleting_an_account_takes_the_journal(circle, db):
    write(circle.ben, "Ben's day.")
    name(circle.ben, "Ben's book")
    write(circle.ana, "Ana's day.")
    assert circle.ben.delete_me().status_code == 204
    with db() as s:
        assert s.scalars(select(JournalPage.body)).all() == ["Ana's day."]
        assert s.get(User, circle.ben.id).journal_title is None


def test_the_export_carries_the_journal(circle, clock):
    write(circle.ana, "Tuesday.", ink="blue")
    clock.advance(timedelta(days=1))
    write(circle.ana, "Wednesday.")
    name(circle.ana, "Summer")
    manifest = json.loads(zipfile.ZipFile(io.BytesIO(circle.ana.export().content)).read("memories.json"))
    assert manifest["journal_title"] == "Summer"
    assert manifest["journal"] == [
        {"day": "2026-06-09", "ink": "blue", "page": "Tuesday."},
        {"day": "2026-06-10", "ink": "black", "page": "Wednesday."},
    ]
    assert b"Tuesday." not in circle.ben.export().content


def test_an_older_database_gets_the_title_column():
    engine = make_engine("sqlite://")
    with engine.begin() as conn:
        conn.execute(text(
            "CREATE TABLE users (id VARCHAR(32) PRIMARY KEY, apple_sub VARCHAR(255), display_name VARCHAR(80), "
            "avatar_key VARCHAR(255), tz_last_seen VARCHAR(64), last_light_notice_enabled BOOLEAN, "
            "created_at DATETIME, deleted_at DATETIME)"
        ))
    assert "users.journal_title" in ensure_schema(engine)
    assert ensure_schema(engine) == []


def test_the_day():
    noon = datetime(2026, 6, 9, 15, 0, tzinfo=timezone.utc)
    assert journal.local_day(noon, NY) == date(2026, 6, 9)
    assert journal.local_day(noon, TOKYO) == date(2026, 6, 10)
    assert journal.local_day(noon, "Nowhere/At_All") == date(2026, 6, 9)
