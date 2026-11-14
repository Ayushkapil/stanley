"""The shared-journal notice (build 57, §10 N7): "{name} wrote in {circle}",
to the others in a circle when a page lands in its shared journal, or
"{name} wrote to you in {circle}" to the one person a page is written to.
Off until asked for, never to the writer, never for a private page or a
rewrite in place, never across a block, never into a muted journal, at most
one an hour per journal per person, and handed to Apple only after the
response with the page's and the circle's ids beside the words.

The suite's clock starts on Tuesday 9 June 2026, 15:00 UTC."""
from __future__ import annotations

import re
from datetime import timedelta

from sqlalchemy import select

from stanley.apns import APNs, PushDelivery, SENT
from stanley.models import NotificationLog
from stanley.notifications import Notifier

from .conftest import NY, make_user
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


def notices(db):
    with db() as s:
        return [
            (n.user_id, n.body)
            for n in s.scalars(
                select(NotificationLog).where(NotificationLog.kind == KIND).order_by(NotificationLog.id)
            ).all()
        ]


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


# --- who hears ----------------------------------------------------------------------


def test_a_circle_page_tells_the_others_and_not_the_writer(circle, db):
    everyone_asks(circle)
    assert write(circle.ana, "We climbed the water tower.", shared=True).status_code == 200
    assert sorted(notices(db)) == sorted(
        [(circle.ben.id, "ana wrote in floor 3"), (circle.cam.id, "ana wrote in floor 3")]
    )


def test_the_words_are_a_name_and_a_journal_and_nothing_else(circle, db):
    circle.ben.patch_settings(journal_posts_enabled=True)
    write(circle.ana, "12 of us climbed the water tower.", shared=True)
    [(_, body)] = notices(db)
    assert body == "ana wrote in floor 3"
    assert "water" not in body and not re.search(r"\d", body.replace("floor 3", ""))


def test_a_private_page_tells_nobody(circle, db):
    everyone_asks(circle)
    assert write(circle.ana, "Just for me.").status_code == 200
    assert write(circle.ben, "Also mine.", shared=False).status_code == 200
    assert notices(db) == []


def test_a_page_for_one_person_tells_only_them(circle, db):
    everyone_asks(circle)
    r = write(circle.ana, "For you, Ben.", shared=True, to=circle.ben.id)
    assert r.status_code == 200, r.text
    assert notices(db) == [(circle.ben.id, "ana wrote to you in floor 3")]


def test_a_rewrite_in_place_is_not_news_twice(circle, db):
    everyone_asks(circle)
    page = write(circle.ana, "A good day.", shared=True).json()
    write(circle.ana, "A good day, really.")  # left out: stays shared
    write(circle.ana, "A good day, truly.", shared=True)
    circle.ana.client.patch(
        f"/me/journal/pages/{page['id']}", json={"body": "A very good day."}, headers=circle.ana.h
    )
    share(circle.ana, page["id"])  # already there
    assert len(notices(db)) == 2  # ben and cam, once


def test_private_to_shared_by_patch_tells_the_circle(circle, db):
    circle.ben.patch_settings(journal_posts_enabled=True)
    page = write(circle.ana, "Thinking it over.").json()
    assert notices(db) == []
    assert share(circle.ana, page["id"]).status_code == 200
    assert notices(db) == [(circle.ben.id, "ana wrote in floor 3")]


def test_private_to_shared_by_writing_again_tells_the_circle(circle, db):
    circle.ben.patch_settings(journal_posts_enabled=True)
    write(circle.ana, "Thinking it over.")
    write(circle.ana, "Thinking it over. Sharing it.", shared=True)
    assert notices(db) == [(circle.ben.id, "ana wrote in floor 3")]


def test_making_a_page_private_tells_nobody(circle, db, clock):
    circle.ben.patch_settings(journal_posts_enabled=True)
    page = write(circle.ana, "A good day.", shared=True).json()
    clock.advance(timedelta(minutes=61))
    share(circle.ana, page["id"], shared=False)
    write(circle.ana, "A good day, kept.", shared=False)
    assert len(notices(db)) == 1


def test_moving_a_page_to_one_person_is_news_to_them(circle, db, clock):
    everyone_asks(circle)
    page = write(circle.ana, "A good day.", shared=True).json()
    clock.advance(timedelta(minutes=61))
    assert share(circle.ana, page["id"], to=circle.cam.id).status_code == 200
    assert notices(db)[-1] == (circle.cam.id, "ana wrote to you in floor 3")
    assert len(notices(db)) == 3
    clock.advance(timedelta(minutes=61))
    assert share(circle.ana, page["id"], to=circle.ben.id).status_code == 200
    assert notices(db)[-1] == (circle.ben.id, "ana wrote to you in floor 3")
    assert len(notices(db)) == 4


def test_another_circle_is_another_journal(circle, db, client):
    """Ana's page moves from floor 3's journal to climbing's: news there."""
    dee = make_user(client, "dee")
    r = circle.ana.client.post("/circles", json={"name": "climbing"}, headers=circle.ana.h)
    climbing = r.json()["id"]
    assert dee.join(r.json()["invite_token"]).status_code == 201
    dee.patch_settings(journal_posts_enabled=True)
    circle.ben.patch_settings(journal_posts_enabled=True)
    page = write(circle.ana, "A good day.", shared=True, circle=circle.id).json()
    assert notices(db) == [(circle.ben.id, "ana wrote in floor 3")]
    assert share(circle.ana, page["id"], circle=climbing).status_code == 200
    assert notices(db)[-1] == (dee.id, "ana wrote in climbing")
    assert len(notices(db)) == 2


# --- muting -------------------------------------------------------------------------


def test_circles_say_whether_their_journal_is_muted(circle):
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


def test_a_muted_journal_tells_that_reader_nothing(circle, db):
    everyone_asks(circle)
    mute(circle.ben, circle.id)
    write(circle.ana, "A good day.", shared=True)
    assert notices(db) == [(circle.cam.id, "ana wrote in floor 3")]
    write(circle.cam, "For you, Ben.", shared=True, to=circle.ben.id)
    assert len(notices(db)) == 1


def test_a_mute_is_for_that_circle_only(circle, db, client):
    dee = make_user(client, "dee")
    r = dee.client.post("/circles", json={"name": "climbing"}, headers=dee.h)
    climbing = r.json()["id"]
    assert circle.ben.join(r.json()["invite_token"]).status_code == 201
    circle.ben.patch_settings(journal_posts_enabled=True)
    mute(circle.ben, circle.id)
    write(circle.ana, "A good day.", shared=True, circle=circle.id)
    assert notices(db) == []
    write(dee, "Up the wall.", shared=True, circle=climbing)
    assert notices(db) == [(circle.ben.id, "dee wrote in climbing")]


def test_muting_is_for_members_only(circle, client):
    dee = make_user(client, "dee")
    dee.client.post("/circles", json={"name": "climbing"}, headers=dee.h)
    assert mute(dee, circle.id).status_code == 404
    assert mute(circle.ben, "nope").status_code == 404


# --- blocks and the hour ----------------------------------------------------------------


def test_a_block_either_way_means_no_notice(circle, db):
    everyone_asks(circle)
    circle.ben.block(circle.ana.id)  # Ben blocked the writer
    circle.ana.block(circle.cam.id)  # the writer blocked Cam
    write(circle.ana, "A good day.", shared=True)
    assert notices(db) == []


def test_one_an_hour_per_journal(circle, db, clock, client):
    """Ana writes, then Cam within the hour: Ben hears of the first alone.
    An hour on, Dee's page is news again."""
    circle.ben.patch_settings(journal_posts_enabled=True)
    dee = make_user(client, "dee")
    assert dee.join(circle.invite_token).status_code == 201
    write(circle.ana, "A good day.", shared=True)
    clock.advance(timedelta(minutes=59))
    write(circle.cam, "Mine too.", shared=True)
    assert notices(db) == [(circle.ben.id, "ana wrote in floor 3")]
    clock.advance(timedelta(minutes=2))
    write(dee, "And mine.", shared=True)
    assert notices(db) == [(circle.ben.id, "ana wrote in floor 3"), (circle.ben.id, "dee wrote in floor 3")]


def test_the_hour_is_per_journal(circle, db, client):
    """A page in another circle's journal isn't held back by this one's."""
    dee = make_user(client, "dee")
    r = dee.client.post("/circles", json={"name": "climbing"}, headers=dee.h)
    climbing = r.json()["id"]
    assert circle.ben.join(r.json()["invite_token"]).status_code == 201
    circle.ben.patch_settings(journal_posts_enabled=True)
    write(circle.ana, "A good day.", shared=True, circle=circle.id)
    write(dee, "Up the wall.", shared=True, circle=climbing)
    assert notices(db) == [(circle.ben.id, "ana wrote in floor 3"), (circle.ben.id, "dee wrote in climbing")]


def test_the_hour_doesnt_mind_other_notices(circle, db):
    circle.ben.patch_settings(journal_posts_enabled=True, circle_posts_enabled=True)
    circle.ana.post_photo()
    write(circle.cam, "A good day.", shared=True)
    assert notices(db) == [(circle.ben.id, "cam wrote in floor 3")]


def test_turning_it_off_stops_it(circle, db):
    circle.ben.patch_settings(journal_posts_enabled=True)
    circle.ben.patch_settings(journal_posts_enabled=False)
    write(circle.ana, "A good day.", shared=True)
    assert notices(db) == []


def test_a_deleted_account_hears_nothing_and_its_switch_is_cleared(circle, db, app):
    from stanley.models import User

    circle.ben.patch_settings(journal_posts_enabled=True)
    assert circle.ben.delete_me().status_code in (200, 204)
    with db() as s:
        assert s.get(User, circle.ben.id).journal_posts_enabled is False
    write(circle.ana, "A good day.", shared=True)
    assert notices(db) == []


def test_a_refused_page_tells_nobody(circle, db):
    from .test_production import SLUR_STORY

    circle.ben.patch_settings(journal_posts_enabled=True)
    assert write(circle.ana, SLUR_STORY, shared=True).status_code == 400
    assert notices(db) == []


# --- delivery -------------------------------------------------------------------------


def test_it_reaches_apple_after_the_response_with_the_pages_ids(circle, app, db):
    delivered = []
    app.state.notifier = Notifier(
        lambda user_id, kind, body, data=None: delivered.append((user_id, kind, body, data))
    )
    circle.ben.patch_settings(journal_posts_enabled=True)
    page = write(circle.ana, "A good day.", shared=True).json()
    assert delivered == [
        (circle.ben.id, KIND, "ana wrote in floor 3", {"journal_page": page["id"], "circle_id": circle.id})
    ]
    assert notices(db) == [(circle.ben.id, "ana wrote in floor 3")]


def test_circle_posts_reach_the_transport_as_they_always_did(circle, app):
    """No ids on any other notice: the transport is called as before."""
    delivered = []
    app.state.notifier = Notifier(lambda *args, **kw: delivered.append((args, kw)))
    circle.ben.patch_settings(circle_posts_enabled=True)
    circle.ana.post_photo()
    assert delivered == [((circle.ben.id, "circle_post", "ana shared a moment"), {})]


def test_a_failed_push_never_fails_the_page(circle, app, db):
    def broken(*_, **__):
        raise RuntimeError("apple is down")

    app.state.notifier = Notifier(broken)
    circle.ben.patch_settings(journal_posts_enabled=True)
    assert write(circle.ana, "A good day.", shared=True).status_code == 200
    page = write(circle.cam, "Thinking.").json()
    assert share(circle.cam, page["id"]).status_code == 200
    assert len(notices(db)) == 1  # the hour held cam's back; ana's was logged


def test_the_apns_payload_carries_the_ids_beside_aps(circle, app):
    http = FakeHTTP()
    apns, _ = _apns(http)
    notifier = Notifier(PushDelivery(apns, app.state.sessionmaker))
    notifier.attach(app.state.sessionmaker)
    app.state.notifier = notifier
    circle.ben.patch_settings(journal_posts_enabled=True)
    _register(circle.ben, "c" * 64)
    page = write(circle.ana, "A good day.", shared=True).json()
    [call] = http.calls
    assert call.json == {
        "aps": {"alert": {"body": "ana wrote in floor 3"}},
        "journal_page": page["id"],
        "circle_id": circle.id,
    }
    # No sound, no badge, as every notice.
    assert set(call.json["aps"]) == {"alert"}


def test_the_payload_without_ids_is_unchanged():
    assert APNs.payload("ana shared a moment") == {"aps": {"alert": {"body": "ana shared a moment"}}}
    assert APNs.payload("x", {"journal_page": "p", "circle_id": "c"}) == {
        "aps": {"alert": {"body": "x"}},
        "journal_page": "p",
        "circle_id": "c",
    }
    assert SENT == "sent"
