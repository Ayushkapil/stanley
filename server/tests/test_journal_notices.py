"""Written to you (§10 N7; build 57's shared-journal notice, narrowed in
build 59 by "Reverse one locked rule, narrowly"). A page shared with one
person tells that person, "{name} wrote you a page"; a sealed letter tells
its recipient, "{name} sent you a letter". A page in the whole circle's
journal tells nobody, nor does a private page. Off until asked for, never
to the writer, never for a rewrite in place, never across a block, never
while the circle is muted, at most one an hour from each sender to each
recipient, no count anywhere, and handed to Apple only after the response
with the ids the app needs beside the words.

The suite's clock starts on Tuesday 9 June 2026, 15:00 UTC."""
from __future__ import annotations

import re
from datetime import timedelta

from sqlalchemy import select

from stanley.apns import APNs, PushDelivery, SENT
from stanley.models import NotificationLog
from stanley.notifications import Notifier

from .conftest import NY, make_user
from .test_letters import _send as send_letter
from .test_push import FakeHTTP, _apns, _register

KIND = "journal_page"


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


def mute(api, circle_id, muted=True):
    return api.client.put(f"/circles/{circle_id}/journal/mute", json={"muted": muted}, headers=api.h)


LETTER = "letter"


def notices(db, kinds=(KIND, LETTER)):
    with db() as s:
        return [
            (n.user_id, n.body)
            for n in s.scalars(
                select(NotificationLog).where(NotificationLog.kind.in_(kinds)).order_by(NotificationLog.id)
            ).all()
        ]


def letter(sender, to, clock, body="Dear friend,"):
    r = send_letter(sender, to.id, 10, body=body, clock=clock)
    assert r.status_code == 201, r.text
    return r.json()


def everyone_asks(circle):
    for api in (circle.ana, circle.ben, circle.cam):
        assert api.patch_settings(journal_posts_enabled=True).status_code == 200


# --- asking ----------------------------------------------------------------------


def test_it_is_off_until_asked_for(circle, db):
    me = circle.ben.client.get("/me", headers=circle.ben.h).json()
    assert me["journal_posts_enabled"] is False
    assert write(circle.ana, "A good day.", shared=True).status_code == 200
    assert notices(db) == []


def test_turning_it_on_leaves_the_others_alone(circle):
    r = circle.ben.patch_settings(journal_posts_enabled=True)
    assert r.json() == {
        "last_light_notice_enabled": False,
        "digest_enabled": False,
        "circle_posts_enabled": False,
        "note_reminder_enabled": False,
        "note_reminder_hour": 9,
        "photo_reminder_enabled": False,
        "photo_reminder_hour": 18,
        "journal_posts_enabled": True,
    }
    me = circle.ben.client.get("/me", headers=circle.ben.h).json()
    assert me["journal_posts_enabled"] is True
    assert me["circle_posts_enabled"] is False


def test_circle_posts_is_its_own_switch(circle, db):
    circle.ben.patch_settings(circle_posts_enabled=True)
    write(circle.ana, "A good day.", shared=True)
    assert notices(db) == []


# --- the whole circle's journal: nobody, ever -----------------------------------------


def test_a_circle_page_tells_nobody(circle, db, clock):
    """Whole-circle pages are ambient: written there, shared there from
    private, moved there from one person, or moved to another circle's
    book, they notify no one, however many asked."""
    everyone_asks(circle)
    page = write(circle.ana, "We climbed the water tower.", shared=True).json()
    assert write(circle.ben, "Me too.", shared=True).status_code == 200
    mine = write(circle.cam, "Thinking it over.").json()
    assert share(circle.cam, mine["id"]).status_code == 200
    clock.advance(timedelta(hours=2))
    assert share(circle.ana, page["id"], to=circle.ben.id).status_code == 200
    clock.advance(timedelta(hours=2))
    assert share(circle.ana, page["id"]).status_code == 200  # back to the whole circle
    with db() as s:
        everything = s.scalars(select(NotificationLog)).all()
    # The one notice is the page made Ben's, and no other kind went out.
    assert [(n.user_id, n.kind, n.body) for n in everything] == [
        (circle.ben.id, KIND, "ana wrote you a page")
    ]


def test_a_circle_page_in_another_circle_tells_nobody_either(circle, db, client):
    dee = make_user(client, "dee")
    r = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h)
    climbing = r.json()["id"]
    assert dee.join(r.json()["invite_token"]).status_code == 201
    dee.patch_settings(journal_posts_enabled=True)
    everyone_asks(circle)
    page = write(circle.ana, "A good day.", shared=True, circle=circle.id).json()
    assert share(circle.ana, page["id"], circle=climbing).status_code == 200
    assert notices(db) == []


def test_a_private_page_tells_nobody_not_even_its_writer(circle, db):
    everyone_asks(circle)
    assert write(circle.ana, "Just for me.").status_code == 200
    assert write(circle.ben, "Also mine.", shared=False).status_code == 200
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


# --- a page for one person ----------------------------------------------------------------


def test_a_page_for_one_person_tells_only_them(circle, db):
    everyone_asks(circle)
    r = write(circle.ana, "For you, Ben.", shared=True, to=circle.ben.id)
    assert r.status_code == 200, r.text
    assert notices(db) == [(circle.ben.id, "ana wrote you a page")]


def test_the_words_are_a_name_and_nothing_else(circle, db, clock):
    circle.ben.patch_settings(journal_posts_enabled=True)
    write(circle.ana, "12 of us climbed the water tower.", shared=True, to=circle.ben.id)
    clock.advance(timedelta(hours=2))
    letter(circle.cam, circle.ben, clock, body="3 things I never said")
    bodies = [body for _, body in notices(db)]
    assert bodies == ["ana wrote you a page", "cam sent you a letter"]
    for body in bodies:
        assert "water" not in body and "things" not in body and "floor" not in body
        assert not re.search(r"\d", body)


def test_a_rewrite_in_place_is_not_news_twice(circle, db, clock):
    everyone_asks(circle)
    page = write(circle.ana, "For you.", shared=True, to=circle.ben.id).json()
    clock.advance(timedelta(hours=2))
    write(circle.ana, "For you, really.")  # left out: stays where it is
    circle.ana.client.patch(
        f"/me/journal/pages/{page['id']}", json={"body": "For you, truly."}, headers=circle.ana.h
    )
    share(circle.ana, page["id"], to=circle.ben.id)  # already there
    assert notices(db) == [(circle.ben.id, "ana wrote you a page")]


def test_private_to_one_person_is_news_to_them(circle, db):
    circle.ben.patch_settings(journal_posts_enabled=True)
    page = write(circle.ana, "Thinking it over.").json()
    assert share(circle.ana, page["id"], to=circle.ben.id).status_code == 200
    assert notices(db) == [(circle.ben.id, "ana wrote you a page")]


def test_making_a_page_private_tells_nobody(circle, db, clock):
    circle.ben.patch_settings(journal_posts_enabled=True)
    page = write(circle.ana, "For you.", shared=True, to=circle.ben.id).json()
    clock.advance(timedelta(hours=2))
    share(circle.ana, page["id"], shared=False)
    write(circle.ana, "Kept.", shared=False)
    assert len(notices(db)) == 1


def test_moving_a_page_to_another_person_is_news_to_them(circle, db, clock):
    everyone_asks(circle)
    page = write(circle.ana, "A good day.", shared=True, to=circle.cam.id).json()
    assert share(circle.ana, page["id"], to=circle.ben.id).status_code == 200
    assert notices(db) == [(circle.cam.id, "ana wrote you a page"), (circle.ben.id, "ana wrote you a page")]


# --- a letter ---------------------------------------------------------------------------


def test_a_letter_tells_only_its_recipient(circle, db, clock):
    everyone_asks(circle)
    letter(circle.ana, circle.ben, clock)
    assert notices(db) == [(circle.ben.id, "ana sent you a letter")]


def test_letters_to_the_circle_tell_nobody(circle, db):
    """Unsigned, to everyone: a notice would say who wrote it."""
    everyone_asks(circle)
    r = circle.ana.client.post(
        f"/circles/{circle.id}/letters", json={"body": "To all of you.", "tz": NY}, headers=circle.ana.h
    )
    assert r.status_code in (200, 201), r.text
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


def test_a_letter_taken_back_or_refused_tells_nobody_more(circle, db, clock):
    from .test_production import SLUR_STORY

    circle.ben.patch_settings(journal_posts_enabled=True)
    assert send_letter(circle.ana, circle.ben.id, 10, body=SLUR_STORY, clock=clock).status_code == 400
    assert send_letter(circle.ana, circle.ana.id, 10, clock=clock).status_code == 400
    assert notices(db) == []


# --- muting -------------------------------------------------------------------------


def test_circles_say_whether_they_are_muted(circle):
    [c] = circle.ben.client.get("/circles", headers=circle.ben.h).json()["circles"]
    assert c["journal_muted"] is False
    assert mute(circle.ben, circle.id).json() == {"muted": True}
    [c] = circle.ben.client.get("/circles", headers=circle.ben.h).json()["circles"]
    assert c["journal_muted"] is True
    assert mute(circle.ben, circle.id, muted=False).json() == {"muted": False}
    [c] = circle.ben.client.get("/circles", headers=circle.ben.h).json()["circles"]
    assert c["journal_muted"] is False
    # Ben's mute is Ben's: nobody else's changes.
    mute(circle.ben, circle.id)
    [c] = circle.cam.client.get("/circles", headers=circle.cam.h).json()["circles"]
    assert c["journal_muted"] is False


def test_a_muted_circle_tells_that_reader_nothing(circle, db, clock):
    everyone_asks(circle)
    mute(circle.ben, circle.id)
    write(circle.cam, "For you, Ben.", shared=True, to=circle.ben.id)
    letter(circle.ana, circle.ben, clock)
    assert notices(db) == []
    write(circle.ana, "For you, Cam.", shared=True, to=circle.cam.id)
    assert notices(db) == [(circle.cam.id, "ana wrote you a page")]


def test_a_mute_is_for_that_circle_only(circle, db, client):
    dee = make_user(client, "dee")
    r = dee.client.post("/circles", json={"name": "climbing"}, headers=dee.h)
    climbing = r.json()["id"]
    assert circle.ben.join(r.json()["invite_token"]).status_code == 201
    circle.ben.patch_settings(journal_posts_enabled=True)
    mute(circle.ben, circle.id)
    write(circle.ana, "For you.", shared=True, to=circle.ben.id, circle=circle.id)
    assert notices(db) == []
    write(dee, "Up the wall, for you.", shared=True, to=circle.ben.id, circle=climbing)
    assert notices(db) == [(circle.ben.id, "dee wrote you a page")]


def test_a_letter_is_quiet_if_any_shared_circle_is_muted(circle, db, client, clock):
    """Ana and Ben share floor 3 and climbing; Ben muted climbing alone.
    A letter isn't in either, and the mute wins."""
    r = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h)
    climbing = r.json()["id"]
    assert circle.ben.join(r.json()["invite_token"]).status_code == 201
    circle.ben.patch_settings(journal_posts_enabled=True)
    mute(circle.ben, climbing)
    letter(circle.ana, circle.ben, clock)
    assert notices(db) == []


def test_muting_is_for_members_only(circle, client):
    dee = make_user(client, "dee")
    dee.client.post("/circles", json={"name": "climbing"}, headers=dee.h)
    assert mute(dee, circle.id).status_code == 404
    assert mute(circle.ben, "nope").status_code == 404


# --- blocks and the hour ----------------------------------------------------------------


def test_a_block_either_way_means_no_notice(circle, db, clock):
    everyone_asks(circle)
    circle.ben.block(circle.ana.id)  # Ben blocked the writer
    circle.ana.block(circle.cam.id)  # the writer blocked Cam
    write(circle.ana, "For Ben.", shared=True, to=circle.ben.id)
    clock.advance(timedelta(hours=2))
    for to in (circle.ben, circle.cam):
        send_letter(circle.ana, to.id, 10, clock=clock)  # refused or not, quiet
    assert notices(db) == []


def test_one_an_hour_from_each_sender_to_each_recipient(circle, db, clock):
    """Ana writes Ben a page, then a letter inside the hour: the second is
    dropped, not stacked or summed. Cam inside the same hour still reaches
    Ben; an hour after Ana's first, Ana does again."""
    everyone_asks(circle)
    write(circle.ana, "For Ben.", shared=True, to=circle.ben.id)
    clock.advance(timedelta(minutes=30))
    letter(circle.ana, circle.ben, clock)
    assert notices(db) == [(circle.ben.id, "ana wrote you a page")]
    write(circle.cam, "For Ben too.", shared=True, to=circle.ben.id)
    assert notices(db)[-1] == (circle.ben.id, "cam wrote you a page")
    clock.advance(timedelta(minutes=31))
    letter(circle.ana, circle.ben, clock, body="Again,")
    assert notices(db) == [
        (circle.ben.id, "ana wrote you a page"),
        (circle.ben.id, "cam wrote you a page"),
        (circle.ben.id, "ana sent you a letter"),
    ]
    # The quiet hour is per recipient too: Ana to Cam is its own.
    write(circle.ana, "For Cam.", shared=True, to=circle.cam.id)  # replaces the day's page
    assert notices(db)[-1] == (circle.cam.id, "ana wrote you a page")
    assert not any("2" in body for _, body in notices(db))


def test_the_hour_doesnt_mind_other_notices(circle, db):
    circle.ben.patch_settings(journal_posts_enabled=True, circle_posts_enabled=True)
    circle.cam.post_photo()
    write(circle.cam, "For Ben.", shared=True, to=circle.ben.id)
    assert notices(db) == [(circle.ben.id, "cam wrote you a page")]


def test_turning_it_off_stops_it(circle, db, clock):
    circle.ben.patch_settings(journal_posts_enabled=True)
    circle.ben.patch_settings(journal_posts_enabled=False)
    write(circle.ana, "For Ben.", shared=True, to=circle.ben.id)
    letter(circle.ana, circle.ben, clock)
    assert notices(db) == []


def test_a_deleted_account_hears_nothing_and_its_switch_is_cleared(circle, db, app):
    from stanley.models import User

    circle.ben.patch_settings(journal_posts_enabled=True)
    assert circle.ben.delete_me().status_code in (200, 204)
    with db() as s:
        assert s.get(User, circle.ben.id).journal_posts_enabled is False
    write(circle.ana, "For Ben.", shared=True, to=circle.ben.id)
    assert notices(db) == []


def test_a_refused_page_tells_nobody(circle, db):
    from .test_production import SLUR_STORY

    circle.ben.patch_settings(journal_posts_enabled=True)
    assert write(circle.ana, SLUR_STORY, shared=True, to=circle.ben.id).status_code == 400
    assert notices(db) == []


# --- delivery, and no count in any payload ------------------------------------------------


def test_it_reaches_apple_after_the_response_with_the_ids(circle, app, db, clock):
    delivered = []
    app.state.notifier = Notifier(
        lambda user_id, kind, body, data=None: delivered.append((user_id, kind, body, data))
    )
    circle.ben.patch_settings(journal_posts_enabled=True)
    circle.cam.patch_settings(journal_posts_enabled=True)
    page = write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).json()
    sealed = letter(circle.ana, circle.cam, clock)
    assert delivered == [
        (circle.ben.id, KIND, "ana wrote you a page", {"journal_page": page["id"], "circle_id": circle.id}),
        (circle.cam.id, LETTER, "ana sent you a letter", {"letter": sealed["id"]}),
    ]


def test_circle_posts_reach_the_transport_as_they_always_did(circle, app):
    """No ids on any other notice: the transport is called as before."""
    delivered = []
    app.state.notifier = Notifier(lambda *args, **kw: delivered.append((args, kw)))
    circle.ben.patch_settings(circle_posts_enabled=True)
    circle.ana.post_photo()
    assert delivered == [((circle.ben.id, "circle_post", "ana shared a moment"), {})]


def test_a_failed_push_never_fails_the_page_or_the_letter(circle, app, db, clock):
    def broken(*_, **__):
        raise RuntimeError("apple is down")

    app.state.notifier = Notifier(broken)
    circle.ben.patch_settings(journal_posts_enabled=True)
    assert write(circle.ana, "For Ben.", shared=True, to=circle.ben.id).status_code == 200
    assert send_letter(circle.cam, circle.ben.id, 10, clock=clock).status_code == 201
    assert len(notices(db)) == 2


def test_the_apns_payloads_carry_ids_and_no_count(circle, app, clock):
    """Every field of what Apple is handed: the words, and ids. No badge,
    no sound, no number anywhere, no field that could hold one."""
    http = FakeHTTP()
    apns, _ = _apns(http)
    notifier = Notifier(PushDelivery(apns, app.state.sessionmaker))
    notifier.attach(app.state.sessionmaker)
    app.state.notifier = notifier
    circle.ben.patch_settings(journal_posts_enabled=True)
    _register(circle.ben, "c" * 64)
    page = write(circle.ana, "12 lines for you.", shared=True, to=circle.ben.id).json()
    sealed = letter(circle.cam, circle.ben, clock, body="5 reasons")
    assert [call.json for call in http.calls] == [
        {"aps": {"alert": {"body": "ana wrote you a page"}}, "journal_page": page["id"], "circle_id": circle.id},
        {"aps": {"alert": {"body": "cam sent you a letter"}}, "letter": sealed["id"]},
    ]
    for call in http.calls:
        assert set(call.json["aps"]) == {"alert"}  # no badge, no sound
        assert not re.search(r"\d", call.json["aps"]["alert"]["body"])
        assert not any("count" in key or "badge" in key or "number" in key for key in call.json)
        for key, value in call.json.items():
            if key != "aps":
                assert isinstance(value, str)  # an id, never a number


def test_no_logged_notice_of_any_kind_carries_a_count(circle, db, clock):
    everyone_asks(circle)
    write(circle.ana, "For Ben.", shared=True, to=circle.ben.id)
    write(circle.cam, "For Ben.", shared=True, to=circle.ben.id)
    letter(circle.ana, circle.cam, clock)
    with db() as s:
        for n in s.scalars(select(NotificationLog)).all():
            assert not re.search(r"\d", n.body), n.body


def test_the_payload_without_ids_is_unchanged():
    assert APNs.payload("ana shared a moment") == {"aps": {"alert": {"body": "ana shared a moment"}}}
    assert APNs.payload("x", {"letter": "l"}) == {"aps": {"alert": {"body": "x"}}, "letter": "l"}
    assert SENT == "sent"
