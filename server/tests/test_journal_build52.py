"""Build 52: a journal page shared with one person, and the mark a person
may leave on their day after posting a photo.

A page shared with one person is in their circle's book only for that
person and its writer, as a `single`, never on a spread. The mark is one
of five, kept for its owner alone, and doesn't fade with its photo.

The suite's clock starts on Tuesday 9 June 2026, 15:00 UTC: 11:00 that
morning in New York."""
from __future__ import annotations

import io
import json
import zipfile
from datetime import date, timedelta

from sqlalchemy import inspect, select, text

from stanley import moderation
from stanley.db import Base, ensure_schema, make_engine
from stanley.models import DayMood, JournalPage, NotificationLog, PageHeart, Photo

from .conftest import NY, make_user
from .test_production import SLUR_STORY


def write(api, body, shared=None, to=None, circle=None, tz=NY):
    fields = {"body": body, "ink": "black", "tz": tz}
    if shared is not None:
        fields["shared"] = shared
    if to is not None:
        fields["recipient_id"] = to
    headers = dict(api.h, **({"X-Stanley-Circle": circle} if circle else {}))
    return api.client.put("/me/journal/today", json=fields, headers=headers)


def share(api, page_id, shared=True, to=None, circle=None):
    fields = {"shared": shared}
    if to is not None:
        fields["recipient_id"] = to
    headers = dict(api.h, **({"X-Stanley-Circle": circle} if circle else {}))
    return api.client.patch(f"/journal/{page_id}", json=fields, headers=headers)


def mine(api):
    return api.client.get("/me/journal", headers=api.h).json()["pages"]


def ours(api, circle_id, **query):
    return api.client.get(f"/circles/{circle_id}/journal", params=query, headers=api.h)


def singles(api, circle_id):
    """Every single a reader is sent, as (day, writer, to)."""
    return [
        (day["day"], s["writer"]["display_name"], s["to"]["display_name"])
        for day in ours(api, circle_id).json()["days"]
        for s in day["singles"]
    ]


def on_spreads(api, circle_id):
    """Every writer whose page is on a spread a reader is sent."""
    return sorted(
        spread[side]["writer"]["display_name"]
        for day in ours(api, circle_id).json()["days"]
        for spread in day["spreads"]
        for side in ("left", "right")
        if spread[side]
    )


def heart(api, page_id):
    return api.client.post(f"/journal/{page_id}/heart", headers=api.h)


def faces(api, page_id):
    return api.client.get(f"/journal/{page_id}/hearts", headers=api.h)


def hearts_on(db, page_id):
    with db() as s:
        return s.scalars(select(PageHeart.user_id).where(PageHeart.page_id == page_id)).all()


def score(api, photo_id, value):
    return api.client.put(f"/photos/{photo_id}/score", json={"score": value}, headers=api.h)


def moods(api):
    return api.client.get("/me/moods", headers=api.h).json()["moods"]


def manifest(api):
    return json.loads(zipfile.ZipFile(io.BytesIO(api.export().content)).read("memories.json"))


# --- a page shared with one person ---------------------------------------------------------------


def test_a_page_for_one_person_is_read_by_them_and_its_writer_and_nobody_else(circle):
    page = write(circle.ana, "Just for you, Ben.", shared=True, to=circle.ben.id).json()
    assert (page["shared"], page["circle_id"], page["circle_name"]) == (True, circle.id, "floor 3")
    assert page["recipient"]["id"] == circle.ben.id and page["recipient"]["display_name"] == "ben"
    for reader in (circle.ana, circle.ben):
        got = ours(reader, circle.id).json()
        (day,) = got["days"]
        assert day["day"] == "2026-06-09" and day["spreads"] == []
        (single,) = day["singles"]
        assert single["body"] == "Just for you, Ben."
        assert (single["writer"]["display_name"], single["to"]["display_name"]) == ("ana", "ben")
        assert single["mine"] is (reader is circle.ana)
    # Cam is in the circle and is sent nothing: no day, no page, no trace.
    assert ours(circle.cam, circle.id).json() == {"days": [], "next_after": None}
    assert heart(circle.cam, page["id"]).status_code == 404
    assert faces(circle.cam, page["id"]).status_code == 404
    assert circle.cam.report(page_id=page["id"], reason="x").status_code == 404
    # It's still only in its writer's own book.
    assert [p["id"] for p in mine(circle.ana)] == [page["id"]] and mine(circle.ben) == []


def test_a_page_for_one_person_is_never_on_a_spread(circle):
    write(circle.ana, "To the circle.", shared=True)
    write(circle.ben, "To the circle too.", shared=True)
    write(circle.cam, "Only for Ana.", shared=True, to=circle.ana.id)
    # Ana and Ben face each other; Cam's page isn't paired with anyone.
    for reader in (circle.ana, circle.ben, circle.cam):
        assert on_spreads(reader, circle.id) == ["ana", "ben"]
    assert singles(circle.ana, circle.id) == [("2026-06-09", "cam", "ana")]
    assert singles(circle.cam, circle.id) == [("2026-06-09", "cam", "ana")]
    assert singles(circle.ben, circle.id) == []
    # The circle's pages carry no one in particular.
    for day in ours(circle.ben, circle.id).json()["days"]:
        for spread in day["spreads"]:
            assert spread["left"]["to"] is None and spread["right"]["to"] is None


def test_singles_come_in_order_of_writer_and_make_a_day_for_those_who_read_them(client, circle, clock):
    dee = make_user(client, "dee")
    dee.join(circle.invite_token)
    write(circle.ben, "Ben to Ana.", shared=True, to=circle.ana.id)
    write(circle.cam, "Cam to Ana.", shared=True, to=circle.ana.id)
    write(dee, "Dee to Ana.", shared=True, to=circle.ana.id)
    want = sorted(
        [(circle.ben.id, "ben"), (circle.cam.id, "cam"), (dee.id, "dee")]
    )
    got = ours(circle.ana, circle.id).json()["days"][0]["singles"]
    assert [s["writer"]["display_name"] for s in got] == [name for _, name in want]
    # A day with only someone else's single isn't a day for Ben... except his own.
    assert singles(circle.ben, circle.id) == [("2026-06-09", "ben", "ana")]
    # Paging by days goes over the days a reader has something on.
    clock.advance(timedelta(days=1))
    write(circle.cam, "Wednesday, to the circle.", shared=True)
    clock.advance(timedelta(days=1))
    write(circle.ben, "Thursday, to Ana.", shared=True, to=circle.ana.id)
    first = ours(circle.ana, circle.id, limit=2).json()
    assert [d["day"] for d in first["days"]] == ["2026-06-09", "2026-06-10"]
    assert first["next_after"] == "2026-06-10"
    rest = ours(circle.ana, circle.id, after=first["next_after"]).json()
    assert [d["day"] for d in rest["days"]] == ["2026-06-11"] and rest["next_after"] is None
    assert [s["body"] for s in rest["days"][0]["singles"]] == ["Thursday, to Ana."]


def test_a_page_for_you_is_yours_to_read_whenever_you_joined(client, circle, clock):
    page = write(circle.ana, "Written before Dee came.").json()
    clock.advance(timedelta(days=1))
    dee = make_user(client, "dee")
    assert dee.join(circle.invite_token).status_code == 201
    assert share(circle.ana, page["id"], to=dee.id).status_code == 200
    assert singles(dee, circle.id) == [("2026-06-09", "ana", "dee")]
    assert heart(dee, page["id"]).json() == {"hearted": True}


def test_hearts_on_a_page_for_one_person(circle):
    page = write(circle.ana, "Just for you, Ben.", shared=True, to=circle.ben.id).json()
    assert heart(circle.ana, page["id"]).json()["detail"]["code"] == "own_page"
    assert heart(circle.cam, page["id"]).status_code == 404
    assert heart(circle.ben, page["id"]).json() == {"hearted": True}
    assert [f["display_name"] for f in faces(circle.ana, page["id"]).json()["hearts"]] == ["ben"]
    assert faces(circle.ben, page["id"]).status_code == 404
    seen = {r: ours(r, circle.id).json()["days"][0]["singles"][0] for r in (circle.ana, circle.ben)}
    assert [f["display_name"] for f in seen[circle.ana]["hearts"]] == ["ben"]
    assert (seen[circle.ben]["hearted"], seen[circle.ben]["hearts"]) == (True, None)


def test_a_page_for_one_person_can_be_reported_by_them(circle):
    page = write(circle.ana, "Just for you, Ben.", shared=True, to=circle.ben.id).json()
    assert circle.ben.report(page_id=page["id"], reason="Not okay.").status_code == 201


def test_a_page_moves_private_to_circle_to_person_to_private_and_loses_its_hearts_each_time(circle, db):
    # By PATCH.
    page = write(circle.ana, "Moving around.").json()
    assert page["recipient"] is None and page["shared"] is False
    r = share(circle.ana, page["id"]).json()
    assert (r["shared"], r["circle_id"], r["recipient"]) == (True, circle.id, None)
    heart(circle.ben, page["id"])
    heart(circle.cam, page["id"])
    assert len(hearts_on(db, page["id"])) == 2
    r = share(circle.ana, page["id"], to=circle.ben.id).json()
    assert (r["shared"], r["circle_id"], r["recipient"]["display_name"]) == (True, circle.id, "ben")
    assert hearts_on(db, page["id"]) == []
    assert on_spreads(circle.cam, circle.id) == [] and singles(circle.ben, circle.id) == [("2026-06-09", "ana", "ben")]
    heart(circle.ben, page["id"])
    # To someone else: Ben's heart doesn't follow it.
    r = share(circle.ana, page["id"], to=circle.cam.id).json()
    assert r["recipient"]["display_name"] == "cam" and hearts_on(db, page["id"]) == []
    assert singles(circle.ben, circle.id) == []
    heart(circle.cam, page["id"])
    # Sharing it again with the same person keeps the heart.
    share(circle.ana, page["id"], to=circle.cam.id)
    assert hearts_on(db, page["id"]) == [circle.cam.id]
    # Back to the whole circle, then private.
    r = share(circle.ana, page["id"]).json()
    assert r["recipient"] is None and hearts_on(db, page["id"]) == []
    heart(circle.ben, page["id"])
    r = share(circle.ana, page["id"], shared=False).json()
    assert (r["shared"], r["circle_id"], r["recipient"]) == (False, None, None)
    assert hearts_on(db, page["id"]) == []
    with db() as s:
        row = s.get(JournalPage, page["id"])
        assert (row.shared, row.circle_id, row.recipient_id) == (False, None, None)


def test_writing_todays_page_moves_it_the_same_way(circle, db):
    page = write(circle.ana, "Private first.").json()
    assert page["shared"] is False
    page = write(circle.ana, "For the circle.", shared=True).json()
    heart(circle.ben, page["id"])
    page = write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).json()
    assert page["recipient"]["display_name"] == "ben" and hearts_on(db, page["id"]) == []
    heart(circle.ben, page["id"])
    # Written again with nothing said about where: still Ben's, heart kept.
    page = write(circle.ana, "For Ben, added to.").json()
    assert page["recipient"]["display_name"] == "ben" and hearts_on(db, page["id"]) == [circle.ben.id]
    assert singles(circle.ben, circle.id) == [("2026-06-09", "ana", "ben")]
    # To the circle: Ben's heart was his, on a page that was his alone.
    page = write(circle.ana, "For everyone after all.", shared=True).json()
    assert page["recipient"] is None and hearts_on(db, page["id"]) == []
    assert on_spreads(circle.cam, circle.id) == ["ana"] and singles(circle.ben, circle.id) == []
    page = write(circle.ana, "For Cam.", shared=True, to=circle.cam.id).json()
    page = write(circle.ana, "Mine again.", shared=False).json()
    assert (page["shared"], page["circle_id"], page["recipient"]) == (False, None, None)
    for reader in (circle.ben, circle.cam):
        assert ours(reader, circle.id).json()["days"] == []


def test_a_page_cant_be_for_yourself_an_outsider_or_someone_a_block_stands_between(client, circle):
    dee = make_user(client, "dee")
    page = write(circle.ana, "Who is it for?").json()
    for to in (circle.ana.id, dee.id, "0" * 32):
        r = share(circle.ana, page["id"], to=to)
        assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_recipient"
        r = write(circle.ana, "Who is it for?", shared=True, to=to)
        assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_recipient"
    # Dee in another of Ana's circles is still not in this one.
    other = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h).json()
    dee.join(other["invite_token"])
    assert share(circle.ana, page["id"], to=dee.id, circle=circle.id).json()["detail"]["code"] == "bad_recipient"
    # A block either way.
    circle.ana.block(circle.ben.id)
    assert share(circle.ana, page["id"], to=circle.ben.id).json()["detail"]["code"] == "bad_recipient"
    circle.cam.block(circle.ana.id)
    assert share(circle.ana, page["id"], to=circle.cam.id).json()["detail"]["code"] == "bad_recipient"
    assert mine(circle.ana)[0]["shared"] is False


def test_a_block_after_sharing_hides_the_page_from_both(circle):
    page = write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).json()
    circle.ben.block(circle.ana.id)
    assert singles(circle.ben, circle.id) == [] and singles(circle.ana, circle.id) == []
    assert heart(circle.ben, page["id"]).status_code == 404
    circle.ben.unblock(circle.ana.id)
    assert singles(circle.ben, circle.id) == [("2026-06-09", "ana", "ben")]


def test_the_word_filter_is_on_a_page_for_one_person_and_not_on_a_private_one(circle):
    r = write(circle.ana, SLUR_STORY, shared=True, to=circle.ben.id)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    page = write(circle.ana, SLUR_STORY).json()
    assert page["shared"] is False
    r = share(circle.ana, page["id"], to=circle.ben.id)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    page = write(circle.ana, "Kind words.", shared=True, to=circle.ben.id).json()
    r = circle.ana.client.patch(f"/me/journal/pages/{page['id']}", json={"body": SLUR_STORY}, headers=circle.ana.h)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    assert singles(circle.ben, circle.id) == [("2026-06-09", "ana", "ben")]


def test_the_recipient_leaving_makes_the_page_its_writers_alone(circle, db):
    page = write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).json()
    heart(circle.ben, page["id"])
    assert circle.ben.leave(circle.id).status_code == 204
    kept = mine(circle.ana)
    assert [(p["body"], p["shared"], p["recipient"]) for p in kept] == [("For Ben.", False, None)]
    assert hearts_on(db, page["id"]) == []
    assert ours(circle.ana, circle.id).json()["days"] == []


def test_the_writer_leaving_does_the_same(circle, db):
    page = write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).json()
    heart(circle.ben, page["id"])
    assert circle.ana.leave(circle.id).status_code == 204
    assert [(p["shared"], p["recipient"]) for p in mine(circle.ana)] == [(False, None)]
    assert ours(circle.ben, circle.id).json()["days"] == [] and hearts_on(db, page["id"]) == []


def test_being_removed_as_the_recipient_does_the_same(circle):
    write(circle.ben, "For Cam.", shared=True, to=circle.cam.id)
    assert circle.ana.remove_member(circle.id, circle.cam.id).status_code == 204
    assert [(p["shared"], p["recipient"]) for p in mine(circle.ben)] == [(False, None)]


def test_a_page_for_someone_who_deletes_their_account_goes_back_to_its_writer(circle, db):
    page = write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).json()
    heart(circle.ben, page["id"])
    assert circle.ben.delete_me().status_code == 204
    assert [(p["body"], p["shared"], p["recipient"]) for p in mine(circle.ana)] == [("For Ben.", False, None)]
    assert hearts_on(db, page["id"]) == []
    with db() as s:
        assert s.get(JournalPage, page["id"]).recipient_id is None


def test_the_operator_takes_a_page_for_one_person_back_to_private(circle, db, clock):
    page = write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).json()
    circle.ben.report(page_id=page["id"], reason="Not okay.")
    with db() as s:
        assert moderation.take_down_page(s, page["id"], clock.now()) is True
        s.commit()
    assert [(p["shared"], p["recipient"]) for p in mine(circle.ana)] == [(False, None)]


def test_the_export_names_the_person_a_page_was_shared_with(circle, clock):
    write(circle.ana, "For Ben.", shared=True, to=circle.ben.id)
    clock.advance(timedelta(days=1))
    write(circle.ana, "For everyone.", shared=True)
    got = manifest(circle.ana)["journal"]
    assert got == [
        {"day": "2026-06-09", "ink": "black", "page": "For Ben.", "shared_with_person": "ben"},
        {"day": "2026-06-10", "ink": "black", "page": "For everyone.", "shared_with": "floor 3"},
    ]
    # Reading it doesn't put it in Ben's.
    assert b"For Ben." not in circle.ben.export().content


def test_a_page_for_one_person_notifies_nobody_and_counts_nothing(circle, db):
    page = write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).json()
    heart(circle.ben, page["id"])

    def names(value):
        if isinstance(value, dict):
            for key, inner in value.items():
                yield key
                yield from names(inner)
        elif isinstance(value, list):
            for inner in value:
                yield from names(inner)

    for payload in (ours(circle.ana, circle.id).json(), ours(circle.ben, circle.id).json(), mine(circle.ana)):
        for key in names(payload):
            assert not any(word in key for word in ("count", "total", "number", "tally")), key
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


# --- the mark on a day ----------------------------------------------------------------------------


def test_the_owner_marks_their_day_and_nobody_else_can(circle, db):
    photo = circle.ana.post_photo().json()
    assert photo["score"] is None
    r = score(circle.ana, photo["id"], 4)
    assert r.status_code == 200 and r.json() == {"score": 4}
    with db() as s:
        assert s.get(Photo, photo["id"]).score == 4
        mood = s.get(DayMood, (circle.ana.id, date(2026, 6, 9)))
        assert (mood.score, mood.photo_id) == (4, photo["id"])
    # Not anyone else's to set, or to learn exists.
    assert score(circle.ben, photo["id"], 1).status_code == 404
    assert score(circle.ben, "0" * 32, 1).status_code == 404
    with db() as s:
        assert s.get(Photo, photo["id"]).score == 4


def test_a_mark_is_one_of_five(circle):
    photo = circle.ana.post_photo().json()
    for bad in (0, 6, -1, 100):
        r = score(circle.ana, photo["id"], bad)
        assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_score"
    for good in (1, 2, 3, 4, 5):
        assert score(circle.ana, photo["id"], good).json() == {"score": good}
    assert moods(circle.ana) == [{"day": "2026-06-09", "score": 5}]


def test_null_clears_the_mark(circle, db):
    photo = circle.ana.post_photo().json()
    score(circle.ana, photo["id"], 2)
    assert score(circle.ana, photo["id"], None).json() == {"score": None}
    assert moods(circle.ana) == []
    with db() as s:
        assert s.get(Photo, photo["id"]).score is None
    # The field has to be there: an empty body isn't a clear.
    r = circle.ana.client.put(f"/photos/{photo['id']}/score", json={}, headers=circle.ana.h)
    assert r.status_code == 422


def test_my_moods_are_mine_oldest_first(circle, clock):
    first = circle.ana.post_photo().json()
    score(circle.ana, first["id"], 3)
    clock.advance(timedelta(days=1))
    second = circle.ana.post_photo().json()
    score(circle.ana, second["id"], 5)
    assert moods(circle.ana) == [{"day": "2026-06-09", "score": 3}, {"day": "2026-06-10", "score": 5}]
    assert moods(circle.ben) == []


def test_a_day_has_one_mark_whichever_circle_it_was_left_in(circle, db):
    second = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h).json()
    circle.ana.circle_id = circle.id
    here = circle.ana.post_photo().json()
    circle.ana.circle_id = second["id"]
    there = circle.ana.post_photo().json()
    score(circle.ana, here["id"], 2)
    score(circle.ana, there["id"], 4)
    assert moods(circle.ana) == [{"day": "2026-06-09", "score": 4}]
    # Clearing the photo the day's mark no longer comes from leaves it.
    score(circle.ana, here["id"], None)
    assert moods(circle.ana) == [{"day": "2026-06-09", "score": 4}]


def _keys_and_values(value, key=None):
    if isinstance(value, dict):
        for k, inner in value.items():
            yield from _keys_and_values(inner, k)
    elif isinstance(value, list):
        for inner in value:
            yield from _keys_and_values(inner, key)
    else:
        yield key, value


def test_no_one_else_is_ever_sent_the_mark(circle, clock):
    photo = circle.ana.post_photo(caption="A good one.").json()
    score(circle.ana, photo["id"], 5)
    circle.ben.anchor(photo["id"])
    circle.ben.like(photo["id"])
    circle.ben.comment(photo["id"], "I remember.")
    # Ana sees her own.
    assert [p["score"] for p in circle.ana.feed_photos()] == [5]
    # Everywhere Ben could meet Ana's photo: Today, Held, her profile,
    # Returned, and what he's rested.
    payloads = [
        circle.ben.feed().json(),
        circle.ben.memories().json(),
        circle.ben.client.get(f"/members/{circle.ana.id}", headers=circle.ben.h).json(),
        circle.ben.returned().json(),
        circle.cam.feed().json(),
        circle.cam.client.get(f"/members/{circle.ana.id}", headers=circle.cam.h).json(),
    ]
    clock.advance(timedelta(days=3))
    circle.ben.rest(photo["id"])
    payloads.append(circle.ben.rested().json())
    payloads.append(circle.ben.memories().json())
    seen_photo = False
    for payload in payloads:
        for key, value in _keys_and_values(payload):
            if key == "score":
                seen_photo = True
                assert value is None, payload
    assert seen_photo
    # Ana's own Held copy has it.
    circle.ana.anchor(photo["id"])
    held = [m for t in circle.ana.memories().json()["threads"] for m in t["memories"]]
    assert [m["score"] for m in held] == [5]


def test_a_purge_takes_the_mark_off_the_photo_and_leaves_it_on_the_day(circle, clock, sweep, db):
    photo = circle.ana.post_photo().json()
    score(circle.ana, photo["id"], 3)
    clock.advance(timedelta(days=7))
    sweep()
    clock.advance(timedelta(days=8))
    sweep()
    with db() as s:
        row = s.get(Photo, photo["id"])
        assert row.state == "PURGED" and row.owner_id is None and row.score is None
    assert moods(circle.ana) == [{"day": "2026-06-09", "score": 3}]
    # A purged photo's mark can't be changed through it.
    assert score(circle.ana, photo["id"], 1).status_code == 404


def test_deleting_the_photo_deletes_its_mark(circle, clock, db):
    photo = circle.ana.post_photo().json()
    score(circle.ana, photo["id"], 3)
    assert circle.ana.delete_photo(photo["id"]).status_code == 204
    assert moods(circle.ana) == []
    with db() as s:
        assert s.get(Photo, photo["id"]).score is None
    assert score(circle.ana, photo["id"], 2).status_code == 404
    # An older photo too, not only today's.
    clock.advance(timedelta(days=1))
    older = circle.ana.post_photo().json()
    score(circle.ana, older["id"], 4)
    clock.advance(timedelta(days=2))
    assert circle.ana.delete_photo(older["id"]).status_code == 204
    assert moods(circle.ana) == []


def test_deleting_an_account_deletes_its_marks(circle, clock, sweep, db):
    photo = circle.ana.post_photo().json()
    score(circle.ana, photo["id"], 3)
    clock.advance(timedelta(days=15))
    sweep()
    sweep()
    later = circle.ana.post_photo().json()
    score(circle.ana, later["id"], 1)
    assert len(moods(circle.ana)) == 2
    assert circle.ana.delete_me().status_code == 204
    with db() as s:
        assert s.scalars(select(DayMood)).all() == []


def test_the_export_carries_the_marks(circle, clock):
    photo = circle.ana.post_photo().json()
    score(circle.ana, photo["id"], 2)
    assert manifest(circle.ana)["moods"] == [{"day": "2026-06-09", "score": 2}]
    assert manifest(circle.ben)["moods"] == []


def test_a_mark_notifies_nobody(circle, db):
    photo = circle.ana.post_photo().json()
    score(circle.ana, photo["id"], 2)
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


def test_the_new_routes_need_a_sign_in(client):
    assert client.put("/photos/x/score", json={"score": 3}).status_code == 401
    assert client.get("/me/moods").status_code == 401


# --- an older database --------------------------------------------------------------------------


def test_an_older_database_gets_the_column_and_the_table():
    engine = make_engine("sqlite://")
    with engine.begin() as conn:
        conn.execute(text(
            "CREATE TABLE journal_pages (id VARCHAR(32) PRIMARY KEY, owner_id VARCHAR(32), day DATE, "
            "body TEXT, ink VARCHAR(8), inks TEXT, shared BOOLEAN DEFAULT 0, circle_id VARCHAR(32), "
            "created_at DATETIME, updated_at DATETIME)"
        ))
        conn.execute(text(
            "INSERT INTO journal_pages (id, owner_id, day, body, ink, shared, circle_id) "
            "VALUES ('p', 'u', '2026-06-09', 'Shared.', 'black', 1, 'c')"
        ))
        conn.execute(text(
            "CREATE TABLE photos (id VARCHAR(32) PRIMARY KEY, owner_id VARCHAR(32), circle_id VARCHAR(32), "
            "local_date DATE, state VARCHAR(12), state_deadline DATETIME, owner_hash VARCHAR(64), "
            "location VARCHAR(120), filter VARCHAR(12))"
        ))
        conn.execute(text("INSERT INTO photos (id, owner_id, circle_id, state) VALUES ('f', 'u', 'c', 'LIVE')"))
    # What the server does on startup.
    Base.metadata.create_all(engine)
    added = ensure_schema(engine)
    assert "journal_pages.recipient_id" in added and "photos.score" in added
    assert ensure_schema(engine) == []
    assert "day_moods" in inspect(engine).get_table_names()
    with engine.begin() as conn:
        # A page that was shared is still the circle's; no photo has a mark.
        assert conn.execute(text("SELECT shared, circle_id, recipient_id FROM journal_pages")).one() == (1, "c", None)
        assert conn.execute(text("SELECT score FROM photos")).one() == (None,)
