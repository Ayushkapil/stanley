"""The shared journal (build 51): a page its writer puts in a circle's book,
read there as facing pages, two people's pages from the same day. Everything
not shared stays its writer's alone.

The suite's clock starts on Tuesday 9 June 2026, 15:00 UTC: 11:00 that
morning in New York."""
from __future__ import annotations

import io
import json
import zipfile
from datetime import date, timedelta

from sqlalchemy import select, text

from stanley import journal, moderation
from stanley.db import ensure_schema, make_engine
from stanley.models import JournalPage, NotificationLog, PageHeart, Report

from .conftest import NY, make_user
from .test_production import SLUR_STORY


def write(api, body, shared=None, circle=None, ink="black", tz=NY, runs=None):
    fields = {"body": body, "ink": ink, "tz": tz}
    if shared is not None:
        fields["shared"] = shared
    if runs is not None:
        fields["runs"] = [{"ink": i, "text": t} for i, t in runs]
    headers = dict(api.h, **({"X-Stanley-Circle": circle} if circle else {}))
    return api.client.put("/me/journal/today", json=fields, headers=headers)


def share(api, page_id, shared=True, circle=None):
    headers = dict(api.h, **({"X-Stanley-Circle": circle} if circle else {}))
    return api.client.patch(f"/journal/{page_id}", json={"shared": shared}, headers=headers)


def mine(api):
    return api.client.get("/me/journal", headers=api.h).json()["pages"]


def ours(api, circle_id, **query):
    return api.client.get(f"/circles/{circle_id}/journal", params=query, headers=api.h)


def spreads(api, circle_id):
    """The circle's book as (day, [(left writer, right writer)]): names, in order."""
    out = []
    for day in ours(api, circle_id).json()["days"]:
        pairs = [
            (s["left"]["writer"]["display_name"], s["right"]["writer"]["display_name"] if s["right"] else None)
            for s in day["spreads"]
        ]
        out.append((day["day"], pairs))
    return out


def pages(api, circle_id):
    """Every page of the circle's book a reader is sent, by writer's name."""
    out = {}
    for day in ours(api, circle_id).json()["days"]:
        for spread in day["spreads"]:
            for side in ("left", "right"):
                if spread[side]:
                    out[spread[side]["writer"]["display_name"]] = spread[side]
    return out


def heart(api, page_id):
    return api.client.post(f"/journal/{page_id}/heart", headers=api.h)


def faces(api, page_id):
    return api.client.get(f"/journal/{page_id}/hearts", headers=api.h)


# --- private and shared ---------------------------------------------------------------------------


def test_a_private_page_is_only_in_its_writers_book(circle):
    page = write(circle.ana, "For me.").json()
    assert (page["shared"], page["circle_id"], page["circle_name"]) == (False, None, None)
    assert [p["body"] for p in mine(circle.ana)] == ["For me."]
    for reader in (circle.ana, circle.ben, circle.cam):
        assert ours(reader, circle.id).json() == {"days": [], "next_after": None}
    assert mine(circle.ben) == []


def test_a_shared_page_is_in_the_circles_book_and_still_in_its_writers(circle):
    page = write(circle.ana, "For all of us.", shared=True, ink="blue").json()
    assert (page["shared"], page["circle_id"], page["circle_name"]) == (True, circle.id, "floor 3")
    assert [p["id"] for p in mine(circle.ana)] == [page["id"]]
    for reader in (circle.ana, circle.ben, circle.cam):
        got = ours(reader, circle.id).json()
        assert [d["day"] for d in got["days"]] == ["2026-06-09"]
        only = got["days"][0]["spreads"]
        # One writer: their page, and nothing facing it.
        assert len(only) == 1 and only[0]["right"] is None
        assert (only[0]["left"]["body"], only[0]["left"]["ink"]) == ("For all of us.", "blue")
        assert only[0]["left"]["writer"]["display_name"] == "ana"
        assert only[0]["left"]["mine"] is (reader is circle.ana)
    # It's nobody else's page for being read: not in their own books.
    assert mine(circle.ben) == []


def test_a_page_goes_from_private_to_shared_and_back(circle):
    page = write(circle.ana, "Thinking about it.").json()
    assert ours(circle.ben, circle.id).json()["days"] == []
    r = share(circle.ana, page["id"])
    assert r.status_code == 200 and r.json()["shared"] is True and r.json()["circle_name"] == "floor 3"
    assert list(pages(circle.ben, circle.id)) == ["ana"]
    r = share(circle.ana, page["id"], shared=False)
    assert r.status_code == 200
    assert (r.json()["shared"], r.json()["circle_id"], r.json()["body"]) == (False, None, "Thinking about it.")
    assert ours(circle.ben, circle.id).json()["days"] == []
    # Still the writer's, as it always was.
    assert [p["body"] for p in mine(circle.ana)] == ["Thinking about it."]


def test_only_the_writer_shares_a_page(circle):
    page = write(circle.ana, "Mine to share.").json()
    assert share(circle.ben, page["id"]).status_code == 404
    assert mine(circle.ana)[0]["shared"] is False


def test_writing_again_leaves_a_page_where_it_was_unless_told(circle):
    write(circle.ana, "Shared this morning.", shared=True)
    # Written again with nothing said about where: still shared.
    page = write(circle.ana, "Shared, and added to.").json()
    assert page["shared"] is True
    assert pages(circle.ben, circle.id)["ana"]["body"] == "Shared, and added to."
    # Written again privately: out of the book.
    page = write(circle.ana, "Private after all.", shared=False).json()
    assert (page["shared"], page["circle_id"]) == (False, None)
    assert ours(circle.ben, circle.id).json()["days"] == []
    # And a new page with nothing said is private.
    assert write(circle.ben, "Ben's day.").json()["shared"] is False


def test_a_shared_page_keeps_its_inks(circle):
    write(circle.ana, "x", shared=True, runs=[("black", "Morning. "), ("red", "Evening.")])
    got = pages(circle.ben, circle.id)["ana"]
    assert got["body"] == "Morning. Evening."
    assert got["runs"] == [{"ink": "black", "text": "Morning. "}, {"ink": "red", "text": "Evening."}]


def test_sharing_needs_a_circle_youre_in(client, circle):
    dee = make_user(client, "dee")
    r = write(dee, "Nobody to share with.", shared=True)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "no_circle"
    r = write(circle.ana, "Not that circle.", shared=True, circle="0" * 32)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "not_in_circle"
    assert mine(circle.ana) == []
    # Not a member reads as not found.
    other = dee.client.post("/circles", json={"name": "elsewhere"}, headers=dee.h).json()
    assert ours(circle.ana, other["id"]).status_code == 404


def test_a_page_is_shared_with_the_circle_on_screen(client, circle):
    second = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h).json()
    page = write(circle.ana, "For the climbers.", shared=True, circle=second["id"]).json()
    assert (page["circle_id"], page["circle_name"]) == (second["id"], "climbing")
    assert ours(circle.ben, circle.id).json()["days"] == []
    assert list(pages(circle.ana, second["id"])) == ["ana"]
    # Moved to the other circle's book: one page, one book.
    cam_heart_target = share(circle.ana, page["id"], circle=circle.id).json()
    assert cam_heart_target["circle_id"] == circle.id
    assert ours(circle.ana, second["id"]).json()["days"] == []
    assert list(pages(circle.ben, circle.id)) == ["ana"]


# --- the word filter --------------------------------------------------------------------------------


def test_the_word_filter_is_on_shared_pages_and_not_private_ones(circle):
    r = write(circle.ana, SLUR_STORY, shared=True)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    assert mine(circle.ana) == []
    # Privately it's hers to write.
    page = write(circle.ana, SLUR_STORY).json()
    assert page["shared"] is False
    # But it can't then be put in the book,
    r = share(circle.ana, page["id"])
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    assert ours(circle.ben, circle.id).json()["days"] == []
    # nor can a shared page be rewritten into it.
    page = write(circle.ben, "Fine words.", shared=True).json()
    r = circle.ben.client.patch(f"/me/journal/pages/{page['id']}", json={"body": SLUR_STORY}, headers=circle.ben.h)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    assert pages(circle.ana, circle.id)["ben"]["body"] == "Fine words."


# --- facing pages -----------------------------------------------------------------------------------


def test_two_writers_on_a_day_face_each_other_and_everyone_sees_the_same(circle):
    write(circle.ana, "Ana's Tuesday.", shared=True)
    write(circle.ben, "Ben's Tuesday.", shared=True)
    seen = [spreads(reader, circle.id) for reader in (circle.ana, circle.ben, circle.cam)]
    assert seen[0] == seen[1] == seen[2]
    (day, pairs), = seen[0]
    assert day == "2026-06-09" and len(pairs) == 1 and set(pairs[0]) == {"ana", "ben"}


def test_an_odd_one_out_has_a_page_alone_and_a_day_nobody_wrote_isnt_there(circle, clock):
    for api, who in ((circle.ana, "Ana"), (circle.ben, "Ben"), (circle.cam, "Cam")):
        write(api, f"{who} on Tuesday.", shared=True)
    clock.advance(timedelta(days=2))  # Wednesday: nobody writes
    write(circle.cam, "Cam on Thursday.", shared=True)
    got = spreads(circle.ben, circle.id)
    assert [day for day, _ in got] == ["2026-06-09", "2026-06-11"]
    tuesday = got[0][1]
    # Three writers: a pair, then one alone, and the one alone comes last.
    assert len(tuesday) == 2 and None not in tuesday[0] and tuesday[1][1] is None
    assert {name for pair in tuesday for name in pair if name} == {"ana", "ben", "cam"}
    assert got[1][1] == [("cam", None)]
    assert got == spreads(circle.ana, circle.id) == spreads(circle.cam, circle.id)


def test_pairing_is_a_pure_function_that_turns_with_the_days():
    ids = ["a", "b", "c", "d"]
    day = date(2026, 6, 9)
    first = journal.pairings(day, "circle", ids)
    # The same whatever order the writers come in, and whoever asks.
    assert first == journal.pairings(day, "circle", list(reversed(ids))) == journal.pairings(day, "circle", ids + ["a"])
    # Everyone is in exactly one spread.
    assert sorted(x for pair in first for x in pair) == ids
    # Over three days each writer faces each of the other three once.
    partners = {i: set() for i in ids}
    for offset in range(3):
        for a, b in journal.pairings(day + timedelta(days=offset), "circle", ids):
            partners[a].add(b)
            partners[b].add(a)
    assert all(partners[i] == set(ids) - {i} for i in ids)
    # An odd number: one alone, last, and a different person each day.
    alone = []
    for offset in range(3):
        pairs = journal.pairings(day + timedelta(days=offset), "circle", ["a", "b", "c"])
        assert len(pairs) == 2 and pairs[0][1] is not None and pairs[1][1] is None
        alone.append(pairs[1][0])
    assert sorted(alone) == ["a", "b", "c"]
    # One writer faces nobody; nobody writing is no spread at all.
    assert journal.pairings(day, "circle", ["a"]) == [("a", None)]
    assert journal.pairings(day, "circle", []) == []
    # Another circle turns its own wheel.
    assert any(
        journal.pairings(day + timedelta(days=n), "circle", ids) != journal.pairings(day + timedelta(days=n), "other", ids)
        for n in range(3)
    )


def test_the_book_comes_a_stretch_of_days_at_a_time(circle, clock):
    for n in range(5):
        write(circle.ana, f"Day {n}.", shared=True)
        clock.advance(timedelta(days=1))
    first = ours(circle.ben, circle.id, limit=2).json()
    assert [d["day"] for d in first["days"]] == ["2026-06-09", "2026-06-10"] and first["next_after"] == "2026-06-10"
    rest = ours(circle.ben, circle.id, limit=10, after=first["next_after"]).json()
    assert [d["day"] for d in rest["days"]] == ["2026-06-11", "2026-06-12", "2026-06-13"]
    assert rest["next_after"] is None


def test_a_member_reads_from_the_day_they_joined(client, circle, clock):
    write(circle.ana, "Before Dee.", shared=True)
    clock.advance(timedelta(days=1))
    dee = make_user(client, "dee")
    assert dee.join(circle.invite_token).status_code == 201
    write(circle.ben, "With Dee here.", shared=True)
    assert [day for day, _ in spreads(dee, circle.id)] == ["2026-06-10"]
    # Those who were there read both.
    assert [day for day, _ in spreads(circle.cam, circle.id)] == ["2026-06-09", "2026-06-10"]
    # And a page from before her time can't be hearted or reported by her.
    before = mine(circle.ana)[0]["id"]
    assert heart(dee, before).status_code == 404
    assert dee.report(page_id=before, reason="x").status_code == 404


def test_a_block_hides_a_page_both_ways_and_leaves_the_pairing_alone(circle):
    for api, who in ((circle.ana, "Ana"), (circle.ben, "Ben"), (circle.cam, "Cam")):
        write(api, f"{who} here.", shared=True)
    before = spreads(circle.cam, circle.id)
    assert circle.ana.block(circle.ben.id).status_code == 204
    assert sorted(pages(circle.ana, circle.id)) == ["ana", "cam"]
    assert sorted(pages(circle.ben, circle.id)) == ["ben", "cam"]
    # Whoever no block touches sees the book as it was.
    assert spreads(circle.cam, circle.id) == before
    # A page that can't be read can't be hearted either.
    assert heart(circle.ana, mine(circle.ben)[0]["id"]).status_code == 404


# --- hearts -----------------------------------------------------------------------------------------


def test_a_heart_is_seen_by_the_writer_as_a_face_and_by_nobody_else(circle):
    page = write(circle.ana, "A good day.", shared=True).json()
    r = heart(circle.ben, page["id"])
    assert r.status_code == 200 and r.json() == {"hearted": True}
    # The writer: who, as a face. Never how many.
    got = pages(circle.ana, circle.id)["ana"]
    assert [f["display_name"] for f in got["hearts"]] == ["ben"] and got["hearted"] is False
    assert [f["display_name"] for f in faces(circle.ana, page["id"]).json()["hearts"]] == ["ben"]
    # Ben: that his own is there, and nothing of anyone else's.
    assert (pages(circle.ben, circle.id)["ana"]["hearted"], pages(circle.ben, circle.id)["ana"]["hearts"]) == (True, None)
    # Cam: nothing at all.
    assert (pages(circle.cam, circle.id)["ana"]["hearted"], pages(circle.cam, circle.id)["ana"]["hearts"]) == (False, None)
    assert faces(circle.ben, page["id"]).status_code == 404
    assert faces(circle.cam, page["id"]).status_code == 404
    # The writer's own book says nothing of hearts either way.
    assert "hearts" not in mine(circle.ana)[0]


def test_a_heart_is_one_each_and_a_second_tap_takes_it_back(circle, db):
    page = write(circle.ana, "A good day.", shared=True).json()
    assert heart(circle.ben, page["id"]).json() == {"hearted": True}
    assert heart(circle.cam, page["id"]).json() == {"hearted": True}
    # (Left in the same instant on the suite's clock, so in either order.)
    assert sorted(f["display_name"] for f in faces(circle.ana, page["id"]).json()["hearts"]) == ["ben", "cam"]
    assert heart(circle.ben, page["id"]).json() == {"hearted": False}
    assert [f["display_name"] for f in faces(circle.ana, page["id"]).json()["hearts"]] == ["cam"]
    with db() as s:
        assert len(s.scalars(select(PageHeart)).all()) == 1


def test_no_heart_on_your_own_page_or_on_a_private_one(circle):
    page = write(circle.ana, "Mine.", shared=True).json()
    r = heart(circle.ana, page["id"])
    assert r.status_code == 400 and r.json()["detail"]["code"] == "own_page"
    private = write(circle.ben, "Ben's own.").json()
    assert heart(circle.cam, private["id"]).status_code == 404
    assert faces(circle.ben, private["id"]).status_code == 404


def test_nothing_about_the_shared_journal_counts_anything(circle):
    page = write(circle.ana, "A good day.", shared=True).json()
    heart(circle.ben, page["id"])
    heart(circle.cam, page["id"])

    def names(value):
        if isinstance(value, dict):
            for key, inner in value.items():
                yield key
                yield from names(inner)
        elif isinstance(value, list):
            for inner in value:
                yield from names(inner)

    for payload in (
        ours(circle.ana, circle.id).json(), ours(circle.ben, circle.id).json(),
        faces(circle.ana, page["id"]).json(), heart(circle.ben, page["id"]).json(), mine(circle.ana),
    ):
        for key in names(payload):
            assert not any(word in key for word in ("count", "total", "number", "tally")), key
    # And no number anywhere in what a reader is sent about a page.
    got = pages(circle.cam, circle.id)["ana"]
    assert not any(isinstance(v, int) and not isinstance(v, bool) for v in got.values())


def test_taking_a_page_back_takes_the_hearts_off_it(circle, db):
    page = write(circle.ana, "A good day.", shared=True).json()
    heart(circle.ben, page["id"])
    share(circle.ana, page["id"], shared=False)
    with db() as s:
        assert s.scalars(select(PageHeart)).all() == []
    share(circle.ana, page["id"])
    assert pages(circle.ana, circle.id)["ana"]["hearts"] == []


# --- leaving, deleting, reporting -------------------------------------------------------------------


def test_leaving_a_circle_takes_your_pages_out_of_its_book_and_keeps_them_in_yours(circle, db):
    theirs = write(circle.ana, "Ana's page.", shared=True).json()
    page = write(circle.ben, "Ben's page.", shared=True).json()
    heart(circle.ana, page["id"])
    heart(circle.ben, theirs["id"])
    assert circle.ben.leave(circle.id).status_code == 204
    assert sorted(pages(circle.cam, circle.id)) == ["ana"]
    kept = mine(circle.ben)
    assert [(p["body"], p["shared"], p["circle_id"]) for p in kept] == [("Ben's page.", False, None)]
    # The heart he left went with him; the one left on his page went with the page.
    assert pages(circle.ana, circle.id)["ana"]["hearts"] == []
    with db() as s:
        assert s.scalars(select(PageHeart)).all() == []


def test_being_removed_does_the_same(circle):
    write(circle.cam, "Cam's page.", shared=True)
    assert circle.ana.remove_member(circle.id, circle.cam.id).status_code == 204
    assert ours(circle.ben, circle.id).json()["days"] == []
    assert [(p["body"], p["shared"]) for p in mine(circle.cam)] == [("Cam's page.", False)]


def test_tearing_out_a_shared_page_takes_it_from_the_book(circle, db):
    page = write(circle.ana, "A good day.", shared=True).json()
    heart(circle.ben, page["id"])
    assert circle.ana.client.delete(f"/me/journal/pages/{page['id']}", headers=circle.ana.h).status_code == 204
    assert ours(circle.ben, circle.id).json()["days"] == []
    with db() as s:
        assert s.scalars(select(PageHeart)).all() == [] and s.scalars(select(JournalPage)).all() == []


def test_deleting_an_account_takes_its_pages_and_its_hearts(circle, db):
    page = write(circle.ana, "Ana's page.", shared=True).json()
    bens = write(circle.ben, "Ben's page.", shared=True).json()
    heart(circle.ben, page["id"])
    heart(circle.ana, bens["id"])
    assert circle.ben.delete_me().status_code == 204
    assert sorted(pages(circle.cam, circle.id)) == ["ana"]
    assert pages(circle.ana, circle.id)["ana"]["hearts"] == []
    with db() as s:
        assert s.scalars(select(PageHeart)).all() == []
        assert s.scalars(select(JournalPage.body)).all() == ["Ana's page."]


def test_a_shared_page_can_be_reported_and_the_report_keeps_how_it_began(circle, db):
    page = write(circle.ana, "Something Ben objects to.", shared=True).json()
    r = circle.ben.report(page_id=page["id"], reason="This isn't okay.")
    assert r.status_code == 201
    with db() as s:
        report = s.scalars(select(Report)).one()
        assert report.page_id == page["id"] and report.reporter_id == circle.ben.id
        assert "This isn't okay." in report.reason
        assert f"by {circle.ana.id}" in report.reason and "Something Ben objects to." in report.reason
    # Not your own, not a private one, not one you can't read.
    assert circle.ana.report(page_id=page["id"], reason="x").status_code == 404
    private = write(circle.cam, "Cam's own.").json()
    assert circle.ben.report(page_id=private["id"], reason="x").status_code == 404


def test_the_operator_takes_a_page_out_of_the_book_not_out_of_the_journal(circle, db, clock):
    page = write(circle.ana, "Something Ben objects to.", shared=True).json()
    heart(circle.cam, page["id"])
    circle.ben.report(page_id=page["id"], reason="This isn't okay.")
    with db() as s:
        assert moderation.take_down_page(s, page["id"], clock.now()) is True
        assert moderation.take_down_page(s, "0" * 32, clock.now()) is False
        s.commit()
    assert ours(circle.ben, circle.id).json()["days"] == []
    assert [(p["body"], p["shared"]) for p in mine(circle.ana)] == [("Something Ben objects to.", False)]
    with db() as s:
        assert s.scalars(select(Report)).one().resolved_at is not None
        assert s.scalars(select(PageHeart)).all() == []


def test_sharing_and_hearts_notify_nobody(circle, db):
    page = write(circle.ana, "A good day.", shared=True).json()
    heart(circle.ben, page["id"])
    share(circle.ana, page["id"], shared=False)
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


def test_a_shared_page_doesnt_fade(circle, clock, sweep):
    write(circle.ana, "Still here.", shared=True)
    clock.advance(timedelta(days=400))
    sweep()
    assert pages(circle.ben, circle.id)["ana"]["body"] == "Still here."


def test_the_export_says_which_pages_are_shared_and_with_whom(circle, clock):
    write(circle.ana, "Shared.", shared=True)
    clock.advance(timedelta(days=1))
    write(circle.ana, "Private.")
    manifest = json.loads(zipfile.ZipFile(io.BytesIO(circle.ana.export().content)).read("memories.json"))
    assert manifest["journal"] == [
        {"day": "2026-06-09", "ink": "black", "page": "Shared.", "shared_with": "floor 3"},
        {"day": "2026-06-10", "ink": "black", "page": "Private."},
    ]
    # Reading a page doesn't put it in your export.
    assert b"Shared." not in circle.ben.export().content


def test_the_shared_journal_needs_a_sign_in(client, circle):
    assert client.get(f"/circles/{circle.id}/journal").status_code == 401
    assert client.patch("/journal/x", json={"shared": True}).status_code == 401
    assert client.post("/journal/x/heart").status_code == 401
    assert client.get("/journal/x/hearts").status_code == 401


def test_an_older_database_gets_the_sharing_columns():
    engine = make_engine("sqlite://")
    with engine.begin() as conn:
        conn.execute(text(
            "CREATE TABLE journal_pages (id VARCHAR(32) PRIMARY KEY, owner_id VARCHAR(32), day DATE, "
            "body TEXT, ink VARCHAR(8), inks TEXT, created_at DATETIME, updated_at DATETIME)"
        ))
        conn.execute(text(
            "INSERT INTO journal_pages (id, owner_id, day, body, ink) VALUES ('p', 'u', '2026-06-09', 'Old.', 'black')"
        ))
    added = ensure_schema(engine)
    assert "journal_pages.shared" in added and "journal_pages.circle_id" in added
    assert ensure_schema(engine) == []
    with engine.begin() as conn:
        # Every page there was is private.
        assert conn.execute(text("SELECT shared, circle_id FROM journal_pages")).one() == (0, None)
