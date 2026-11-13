"""Letters to your circle (build 42). Writing, sealing, waiting, breaking
the seal, and every edge: who may delete, the cap, the word filter, the
date bounds, account deletions on either side, reports."""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

import pytest

from .conftest import make_user


def _iso_deliver(clock, days: int) -> str:
    return (clock.now().date() + timedelta(days=days)).isoformat()


def _send(sender, recipient_id: str, days: int, *, body: str = "Dear friend,", occasion: str | None = None, clock=None):
    data = {
        "recipient_id": recipient_id,
        "body": body,
        "deliver_at": _iso_deliver(clock, days),
    }
    if occasion is not None:
        data["occasion"] = occasion
    return sender.client.post("/me/letters/send", json=data, headers=sender.h)


def _sent(u):
    return u.client.get("/me/letters/sent", headers=u.h)


def _received(u):
    return u.client.get("/me/letters/received", headers=u.h)


def _open(u, letter_id: str):
    return u.client.post(f"/me/letters/{letter_id}/open", headers=u.h)


def _delete(u, letter_id: str):
    return u.client.delete(f"/me/letters/{letter_id}", headers=u.h)


def test_send_writes_a_sealed_letter_and_vanishes_the_body_from_the_sender(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="I meant to say.", occasion="Open on your birthday", clock=clock)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["sealed"] is True
    assert body["sender_can_delete"] is True
    assert body["occasion"] == "Open on your birthday"
    assert "body" not in body  # the sender gives up the words at the seal
    assert body["recipient"]["id"] == circle.ben.id

    sent = _sent(circle.ana).json()["letters"]
    assert len(sent) == 1
    assert "body" not in sent[0]
    assert sent[0]["sealed"] is True


def test_recipient_sees_a_sealed_envelope_only_before_the_day(circle, clock):
    _send(circle.ana, circle.ben.id, 10, body="Hello.", clock=clock)
    inbox = _received(circle.ben).json()
    assert len(inbox["sealed"]) == 1 and not inbox["opened"]
    env = inbox["sealed"][0]
    assert env["sender"]["id"] == circle.ana.id
    assert env["deliverable"] is False
    assert "body" not in env


def test_cannot_open_before_the_day(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="Not yet.", clock=clock)
    letter_id = r.json()["id"]
    attempt = _open(circle.ben, letter_id)
    assert attempt.status_code == 403
    assert attempt.json()["detail"]["code"] == "not_yet"


def test_opens_on_the_day_and_lives_afterwards(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="On the day.", clock=clock)
    letter_id = r.json()["id"]
    clock.advance(timedelta(days=10))
    opened = _open(circle.ben, letter_id)
    assert opened.status_code == 200
    body = opened.json()
    assert body["sealed"] is False
    assert body["body"] == "On the day."

    inbox = _received(circle.ben).json()
    assert not inbox["sealed"]
    assert len(inbox["opened"]) == 1 and inbox["opened"][0]["body"] == "On the day."


def test_recipient_cannot_delete_a_sealed_letter_but_can_once_opened(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="Gift.", clock=clock)
    letter_id = r.json()["id"]
    assert _delete(circle.ben, letter_id).status_code == 404  # sealed, not yours to refuse
    clock.advance(timedelta(days=10))
    _open(circle.ben, letter_id)
    assert _delete(circle.ben, letter_id).status_code == 204
    assert _received(circle.ben).json() == {"sealed": [], "opened": []}


def test_sender_may_withdraw_a_sealed_letter_but_not_an_opened_one(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="Withdrawn.", clock=clock)
    letter_id = r.json()["id"]
    # Sealed: the envelope vanishes from both sides.
    assert _delete(circle.ana, letter_id).status_code == 204
    assert _sent(circle.ana).json() == {"letters": []}
    assert _received(circle.ben).json() == {"sealed": [], "opened": []}

    r2 = _send(circle.ana, circle.ben.id, 10, body="Kept.", clock=clock)
    lid2 = r2.json()["id"]
    clock.advance(timedelta(days=10))
    _open(circle.ben, lid2)
    assert _delete(circle.ana, lid2).status_code == 404  # opened, out of their hands


def test_sender_never_sees_the_words_back_even_in_sent(circle, clock):
    _send(circle.ana, circle.ben.id, 10, body="Very private.", clock=clock)
    for entry in _sent(circle.ana).json()["letters"]:
        assert "body" not in entry


def test_cap_is_five_sealed_letters_waiting_per_recipient(circle, clock):
    for i in range(5):
        r = _send(circle.ana, circle.ben.id, 10 + i, body=f"#{i}", clock=clock)
        assert r.status_code == 201
    over = _send(circle.ana, circle.ben.id, 20, body="over", clock=clock)
    assert over.status_code == 409 and over.json()["detail"]["code"] == "inbox_full"
    # Opened letters don't count toward the cap.
    letter_id = _sent(circle.ana).json()["letters"][0]["id"]
    clock.advance(timedelta(days=10))
    _open(circle.ben, letter_id)
    again = _send(circle.ana, circle.ben.id, 30, body="after open", clock=clock)
    assert again.status_code == 201


def test_cap_is_across_senders(circle, clock):
    for i in range(5):
        _send(circle.ana, circle.ben.id, 10 + i, body=f"a{i}", clock=clock)
    over = _send(circle.cam, circle.ben.id, 20, body="from cam", clock=clock)
    assert over.status_code == 409


def test_date_bounds(circle, clock):
    too_soon = _send(circle.ana, circle.ben.id, 6, body="early", clock=clock)
    assert too_soon.status_code == 400 and too_soon.json()["detail"]["code"] == "too_soon"
    too_far = _send(circle.ana, circle.ben.id, 400, body="far", clock=clock)
    assert too_far.status_code == 400 and too_far.json()["detail"]["code"] == "too_far"
    ok = _send(circle.ana, circle.ben.id, 7, body="at the floor", clock=clock)
    assert ok.status_code == 201
    ok2 = _send(circle.ana, circle.ben.id, 365, body="at the ceiling", clock=clock)
    assert ok2.status_code == 201


def test_cannot_write_to_someone_outside_the_circle(circle, clock, client):
    outsider = make_user(client, "zed")
    r = _send(circle.ana, outsider.id, 10, body="hi", clock=clock)
    assert r.status_code == 404


def test_cannot_write_to_yourself(circle, clock):
    r = _send(circle.ana, circle.ana.id, 10, body="hello me", clock=clock)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "not_yourself"


def test_word_filter_covers_body_and_occasion(circle, clock, monkeypatch):
    from stanley import wordfilter
    monkeypatch.setattr(wordfilter, "is_objectionable", lambda *texts: any(t and "bad" in t for t in texts))
    bad_body = _send(circle.ana, circle.ben.id, 10, body="this is bad", clock=clock)
    assert bad_body.status_code == 400 and bad_body.json()["detail"]["code"] == "words_not_allowed"
    bad_occ = _send(circle.ana, circle.ben.id, 10, body="fine", occasion="bad day", clock=clock)
    assert bad_occ.status_code == 400 and bad_occ.json()["detail"]["code"] == "words_not_allowed"


def test_letter_body_is_cleaned(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="   plain ‎ words   ", clock=clock)
    assert r.status_code == 201
    letter_id = r.json()["id"]
    clock.advance(timedelta(days=10))
    body = _open(circle.ben, letter_id).json()["body"]
    assert body == "plain ‎ words"  # whitespace trimmed; LTR mark left alone


def test_letter_body_cannot_be_empty_or_too_long(circle, clock):
    blank = _send(circle.ana, circle.ben.id, 10, body="   ", clock=clock)
    assert blank.status_code == 400
    too_big = _send(circle.ana, circle.ben.id, 10, body="x" * 2001, clock=clock)
    assert too_big.status_code == 422  # pydantic max_length


def test_letter_survives_either_leaving_the_circle(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="still yours.", clock=clock)
    letter_id = r.json()["id"]
    assert circle.ana.leave(circle.id).status_code == 204  # creator succession is tested elsewhere
    clock.advance(timedelta(days=10))
    body = _open(circle.ben, letter_id)
    assert body.status_code == 200 and body.json()["body"] == "still yours."


def test_letter_disappears_when_sender_deletes_account(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="mine.", clock=clock)
    assert circle.ana.delete_me().status_code == 204
    assert _received(circle.ben).json() == {"sealed": [], "opened": []}


def test_letter_disappears_when_recipient_deletes_account(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="yours.", clock=clock)
    assert circle.ben.delete_me().status_code == 204
    # The sender's row is gone too: both halves of a letter are the letter.
    assert _sent(circle.ana).json() == {"letters": []}


def test_opening_is_idempotent(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="twice", clock=clock)
    letter_id = r.json()["id"]
    clock.advance(timedelta(days=10))
    first = _open(circle.ben, letter_id).json()
    opened_at = first["opened_at"]
    clock.advance(timedelta(hours=1))
    second = _open(circle.ben, letter_id).json()
    assert second["opened_at"] == opened_at  # the first opening is the one kept


def test_someone_else_cannot_open_your_letter(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="not for cam", clock=clock)
    letter_id = r.json()["id"]
    clock.advance(timedelta(days=10))
    assert _open(circle.cam, letter_id).status_code == 404


def test_report_only_after_opening_and_only_by_recipient(circle, clock):
    r = _send(circle.ana, circle.ben.id, 10, body="read me", clock=clock)
    letter_id = r.json()["id"]
    # Sealed: nothing to object to yet.
    sealed_report = circle.ben.report(letter_id=letter_id, reason="too soon")
    assert sealed_report.status_code == 404
    clock.advance(timedelta(days=10))
    _open(circle.ben, letter_id)
    # Not the recipient: never.
    assert circle.cam.report(letter_id=letter_id, reason="not mine").status_code == 404
    ok = circle.ben.report(letter_id=letter_id, reason="mean")
    assert ok.status_code == 201


def test_moderation_takedown_detaches_the_report(circle, clock, db):
    from stanley.moderation import take_down_letter
    r = _send(circle.ana, circle.ben.id, 10, body="mean", clock=clock)
    letter_id = r.json()["id"]
    clock.advance(timedelta(days=10))
    _open(circle.ben, letter_id)
    rep = circle.ben.report(letter_id=letter_id, reason="mean")
    report_id = rep.json()["id"]
    with db() as session:
        assert take_down_letter(session, letter_id, clock.now()) is True
        session.commit()
    # Report lives on with letter_id null.
    from stanley.models import PersonLetter, Report
    with db() as session:
        assert session.get(PersonLetter, letter_id) is None
        row = session.get(Report, report_id)
        assert row is not None and row.letter_id is None and row.resolved_at is not None


def test_full_lifecycle_no_notification_is_ever_logged(circle, clock, app):
    """A letter never notifies anyone — not when written, not on the day."""
    from stanley.models import NotificationLog
    r = _send(circle.ana, circle.ben.id, 10, body="quiet", clock=clock)
    clock.advance(timedelta(days=10))
    _open(circle.ben, r.json()["id"])
    with app.state.sessionmaker() as session:
        from sqlalchemy import select
        kinds = set(session.scalars(select(NotificationLog.kind)).all())
    assert all("letter" not in k for k in kinds)
