"""Letters to your circle (build 42).

A sealed letter from one person in a circle to another, held closed until a
day the sender chooses. Written to the person, not to the circle member:
either of them may leave the circle and the letter stays, and the only
thing that takes one is an account ending. The sender gives up their words
at the seal — they can take back a letter still sealed, but not reread it.
The recipient can't refuse one before the date; once opened, it lives in
their Held, and they can delete it.

Rules, in code:

- Writing is to someone the sender shares a circle with now. Not themselves.
  The body is cleaned and run through the word filter; the occasion label
  too, if given. The date is UTC, between seven days and a year from today.
- At most five sealed letters waiting for any one person, so nothing comes
  flooding in. Opened ones don't count.
- Before the day, the recipient's GET of the body is 403 `not_yet`. The
  sealed list carries the sender and the date, never a hint of the words.
- The sender's sent list is sealed status only: once sealed the body is
  behind the seal for them too. The row has `sender_can_delete` true only
  while nobody has opened it.
- The recipient's opened letters carry the full body. Deleting: the sender
  may delete only while it's sealed (and takes the envelope away); the
  recipient may delete only once it's opened.
- No notification, ever. The envelope in Held is the only signal.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..deps import (
    event, get_clock, get_current_user, get_db, get_settings, refuse_objectionable, shares_a_circle,
)
from ..models import PersonLetter, User, new_id
from ..ratelimit import per_person
from ..serialize import iso, user_brief
from ..text import clean, clean_optional

router = APIRouter(tags=["letters"])

# A letter is up to 2000 characters, long enough for real words, short
# enough to keep it a letter rather than an essay.
LETTER_MAX = 2000
OCCASION_MAX = 120
# The earliest a letter may land and the latest. A week gives the writing
# a little distance from the day it was written; a year keeps the promise
# within sight — longer and both lives have changed too much.
MIN_DAYS_AHEAD = 7
MAX_DAYS_AHEAD = 365
# At most five sealed letters waiting for any one person. Opened ones
# don't count — someone who reads theirs doesn't keep the slot blocked.
WAITING_CAP = 5


class LetterBody(BaseModel):
    recipient_id: str = Field(max_length=64)
    body: str = Field(min_length=1, max_length=LETTER_MAX)
    occasion: str | None = Field(default=None, max_length=OCCASION_MAX)
    # YYYY-MM-DD, the day the seal may be broken, in UTC.
    deliver_at: date


def _sender_payload(now: datetime, row: PersonLetter, recipient: dict) -> dict:
    """What the sender sees of a letter they wrote: who it's for, the day,
    the label, whether it's opened yet, and whether they can still take it
    back. Never the words."""
    return {
        "id": row.id,
        "recipient": recipient,
        "deliver_at": row.deliver_at.isoformat(),
        "occasion": row.occasion,
        "sealed": row.opened_at is None,
        "opened_at": iso(row.opened_at),
        "created_at": iso(row.created_at),
        "sender_can_delete": row.opened_at is None,
    }


def _recipient_sealed_payload(now: datetime, row: PersonLetter, sender: dict) -> dict:
    """What a sealed envelope shows the recipient: from whom, the day, the
    label, and whether the day has come. Never the words."""
    return {
        "id": row.id,
        "sender": sender,
        "deliver_at": row.deliver_at.isoformat(),
        "occasion": row.occasion,
        "sealed": True,
        "deliverable": now.date() >= row.deliver_at,
        "created_at": iso(row.created_at),
    }


def _recipient_opened_payload(row: PersonLetter, sender: dict) -> dict:
    """An opened letter, as the recipient sees it: the words, who wrote
    them, when it was written and when it was opened."""
    return {
        "id": row.id,
        "sender": sender,
        "deliver_at": row.deliver_at.isoformat(),
        "occasion": row.occasion,
        "sealed": False,
        "body": row.body,
        "created_at": iso(row.created_at),
        "opened_at": iso(row.opened_at),
    }


def _waiting_count(db: Session, recipient_id: str) -> int:
    """How many sealed letters are already waiting for this person. Opened
    letters don't count toward the cap."""
    return db.scalar(
        select(func.count())
        .select_from(PersonLetter)
        .where(PersonLetter.recipient_id == recipient_id, PersonLetter.opened_at.is_(None))
    ) or 0


@router.post("/me/letters/send", status_code=201, dependencies=[per_person("journal")])
def send_letter(
    body: LetterBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Seal a letter to someone in one of your circles, for a day between a
    week and a year away. The sender gives up their words at the seal."""
    if body.recipient_id == user.id:
        raise HTTPException(400, {"code": "not_yourself"})
    recipient = db.get(User, body.recipient_id)
    if recipient is None or recipient.deleted_at is not None:
        raise HTTPException(404, "not found")
    if not shares_a_circle(db, user.id, recipient.id):
        raise HTTPException(404, "not found")

    now = clock.now()
    today = now.date()
    earliest = today + timedelta(days=MIN_DAYS_AHEAD)
    latest = today + timedelta(days=MAX_DAYS_AHEAD)
    if body.deliver_at < earliest:
        raise HTTPException(400, {"code": "too_soon"})
    if body.deliver_at > latest:
        raise HTTPException(400, {"code": "too_far"})

    words = clean_optional(body.body, multiline=True)
    if words is None:
        raise HTTPException(400, {"code": "empty_letter"})
    occasion = clean_optional(body.occasion) if body.occasion is not None else None
    refuse_objectionable(words, occasion)

    if _waiting_count(db, recipient.id) >= WAITING_CAP:
        raise HTTPException(409, {"code": "inbox_full"})

    row = PersonLetter(
        id=new_id(),
        sender_id=user.id,
        recipient_id=recipient.id,
        body=words,
        occasion=occasion,
        deliver_at=body.deliver_at,
        created_at=now,
    )
    db.add(row)
    db.flush()
    event("letter_sent", letter=row.id, sender=user.id, recipient=recipient.id)
    return _sender_payload(now, row, user_brief(db, recipient.id, settings, now))


@router.get("/me/letters/sent")
def sent_letters(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Every letter you've written: sealed status only, never the words. A
    letter you've sealed is sealed from you too — you committed those words."""
    now = clock.now()
    rows = db.scalars(
        select(PersonLetter)
        .where(PersonLetter.sender_id == user.id)
        .order_by(PersonLetter.deliver_at, PersonLetter.created_at)
    ).all()
    return {
        "letters": [
            _sender_payload(now, r, user_brief(db, r.recipient_id, settings, now)) for r in rows
        ]
    }


@router.get("/me/letters/received")
def received_letters(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Every letter addressed to you: sealed ones show sender, date and
    label and whether the day has come; opened ones carry the words. Newest
    sealed first within each half, then opened by when they were opened."""
    now = clock.now()
    rows = db.scalars(
        select(PersonLetter)
        .where(PersonLetter.recipient_id == user.id)
        .order_by(PersonLetter.deliver_at, PersonLetter.created_at)
    ).all()
    sealed = []
    opened = []
    for r in rows:
        sender = user_brief(db, r.sender_id, settings, now)
        if r.opened_at is None:
            sealed.append(_recipient_sealed_payload(now, r, sender))
        else:
            opened.append(_recipient_opened_payload(r, sender))
    opened.sort(key=lambda p: p["opened_at"] or "", reverse=True)
    return {"sealed": sealed, "opened": opened}


@router.post("/me/letters/{letter_id}/open")
def open_letter(
    letter_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Break the seal on your own letter. 403 before the day. Opening a
    second time returns the same body — the server keeps the first opening."""
    row = db.get(PersonLetter, letter_id)
    if row is None or row.recipient_id != user.id:
        raise HTTPException(404, "not found")
    now = clock.now()
    if now.date() < row.deliver_at:
        raise HTTPException(403, {"code": "not_yet", "deliver_at": row.deliver_at.isoformat()})
    if row.opened_at is None:
        row.opened_at = now
        db.flush()
        event("letter_opened", letter=row.id, recipient=user.id)
    return _recipient_opened_payload(row, user_brief(db, row.sender_id, settings, now))


@router.delete("/me/letters/{letter_id}", status_code=204)
def delete_letter(
    letter_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """The sender may take back a letter while it's still sealed (the
    envelope goes from the recipient's Held with it). The recipient may
    delete one only once they've opened it — a sealed letter is a gift,
    not a message, and can't be refused before the day. Any other case
    is a 404, existence not leaked."""
    row = db.get(PersonLetter, letter_id)
    if row is None:
        raise HTTPException(404, "not found")
    if row.sender_id == user.id and row.opened_at is None:
        event("letter_withdrawn", letter=row.id, sender=user.id)
        db.delete(row)
        return
    if row.recipient_id == user.id and row.opened_at is not None:
        event("letter_discarded", letter=row.id, recipient=user.id)
        db.delete(row)
        return
    raise HTTPException(404, "not found")
