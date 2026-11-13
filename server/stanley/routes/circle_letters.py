"""Letters to the circle (build 42): once a month, one unsigned letter each
to the whole circle, sealed until the month is over and then read together
for seven days. The months and the moment they open are in
`circle_letters.py`; who may read and write what is here.

The one rule everything here is built round: **a letter leaves the server
as its id and its words, and nothing else.** No author, no name, no face,
no tone, no time written, no flag saying whose it is. The app knows which
letter is its own person's only because it asked for that one by itself
(`/letters/mine`), never from the list everyone gets. Nothing here counts
anything, and nothing here sends a notification.
"""
from __future__ import annotations

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from .. import circle_letters, decay
from ..deps import get_clock, get_current_user, get_db, membership_in, refuse_objectionable
from ..models import Circle, CircleLetter, Membership, User, new_id
from ..ratelimit import per_person
from ..serialize import iso
from ..text import clean_optional
from .journal import _zone

router = APIRouter(tags=["letters"])


class LetterBody(BaseModel):
    body: str = Field(min_length=1, max_length=circle_letters.LETTER_MAX)
    # The phone's zone, so the month is the writer's own.
    tz: str | None = Field(default=None, max_length=64)


def _sealed(letter: CircleLetter | None) -> dict | None:
    """Your own letter, back to you: the only payload a letter goes out in
    to one person alone, and still nothing in it but its id and words."""
    return {"id": letter.id, "body": letter.body} if letter else None


def _mine(db: Session, circle_id: str, user_id: str, month: date) -> CircleLetter | None:
    return db.scalars(
        select(CircleLetter).where(
            CircleLetter.circle_id == circle_id,
            CircleLetter.author_id == user_id,
            CircleLetter.month == month,
        )
    ).first()


def _opened(db: Session, circle_id: str, month: date) -> bool:
    """That month's letters are out in this circle: writing for it is over."""
    return db.scalars(
        select(CircleLetter.id)
        .where(
            CircleLetter.circle_id == circle_id,
            CircleLetter.month == month,
            CircleLetter.revealed_at.is_not(None),
        )
        .limit(1)
    ).first() is not None


def _reading(db: Session, membership: Membership, now: datetime) -> tuple[date, datetime] | None:
    """The month of letters this member can read right now, and when it
    opened: one that opened within the last seven days, while they were in
    the circle. Letters are written to the people who were there; someone
    who joins afterwards doesn't read them."""
    return db.execute(
        select(CircleLetter.month, CircleLetter.revealed_at)
        .where(
            CircleLetter.circle_id == membership.circle_id,
            CircleLetter.revealed_at.is_not(None),
            CircleLetter.revealed_at > now - circle_letters.VISIBLE_FOR,
            CircleLetter.revealed_at >= membership.joined_at,
        )
        .order_by(CircleLetter.revealed_at.desc())
        .limit(1)
    ).first()


def _state(db: Session, clock, membership: Membership, circle: Circle, user: User, tz: str) -> dict:
    """What the card in Today needs: the month being written for, your own
    letter for it, when it opens, and whether last month's are out to read.
    The same whoever else has or hasn't written: nothing here says."""
    now = clock.now()
    decay.open_letters(db, clock, circle.id)
    month = circle_letters.month_of(now, tz)
    writable = not _opened(db, circle.id, month)
    reading = _reading(db, membership, now)
    return {
        "month": circle_letters.label(month),
        # Whether this month can still be written for. False only for
        # someone whose own month outlasted the circle's (a traveller).
        "open": writable,
        "reveals_at": iso(circle_letters.opens_at(month, [*decay.letter_zones(db, circle.id), tz])),
        "letter": _sealed(_mine(db, circle.id, user.id, month)) if writable else None,
        "revealed": {
            "month": circle_letters.label(reading[0]),
            "revealed_at": iso(reading[1]),
            "fades_at": iso(circle_letters.fades_at(reading[1])),
            # Yours among them, if you wrote one and haven't taken it back:
            # so the app can offer to delete it, and not to report it.
            "letter": _sealed(_mine(db, circle.id, user.id, reading[0])),
        } if reading else None,
    }


@router.get("/circles/{circle_id}/letters/mine")
def my_letter(
    circle_id: str,
    tz: str | None = Query(default=None, max_length=64),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """Your letter this month, when the month's letters open, and whether
    last month's are out. Nothing about who else has written, or how many."""
    membership, circle = membership_in(db, user, circle_id)
    return _state(db, clock, membership, circle, user, _zone(user, tz))


@router.post("/circles/{circle_id}/letters", dependencies=[per_person("journal")])
def write_letter(
    circle_id: str,
    body: LetterBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """Write this month's letter, or rewrite it: one each, sealed until the
    month's letters open, and closed to changes from then on, so nobody
    writes having read the rest."""
    membership, circle = membership_in(db, user, circle_id)
    tz = _zone(user, body.tz)
    words = clean_optional(body.body, multiline=True)
    if words is None:
        raise HTTPException(400, {"code": "empty_circle_letter"})
    refuse_objectionable(words)
    now = clock.now()
    decay.open_letters(db, clock, circle.id)
    month = circle_letters.month_of(now, tz)
    if _opened(db, circle.id, month):
        raise HTTPException(409, {"code": "circle_letters_opened"})
    # One statement, so two taps at once are one letter, never a 500.
    # Rewriting keeps its id, which is random and says nothing of when.
    db.execute(
        sqlite_insert(CircleLetter)
        .values(
            id=new_id(), circle_id=circle.id, author_id=user.id, body=words, month=month,
            revealed_at=None, created_at=now, updated_at=now,
        )
        .on_conflict_do_update(
            index_elements=["circle_id", "author_id", "month"], set_={"body": words, "updated_at": now}
        )
    )
    return _state(db, clock, membership, circle, user, tz)


@router.delete("/circles/{circle_id}/letters/mine", status_code=204)
def delete_my_letter(
    circle_id: str,
    month: str | None = Query(default=None, max_length=7),
    tz: str | None = Query(default=None, max_length=64),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """Take your letter back: this month's while it's sealed, or (naming the
    month) one that has opened, which then goes for everyone. Only ever
    your own."""
    _, circle = membership_in(db, user, circle_id)
    if month is None:
        which = circle_letters.month_of(clock.now(), _zone(user, tz))
    else:
        which = circle_letters.parse(month)
        if which is None:
            raise HTTPException(400, {"code": "bad_month"})
    db.execute(
        delete(CircleLetter).where(
            CircleLetter.circle_id == circle.id,
            CircleLetter.author_id == user.id,
            CircleLetter.month == which,
        )
    )


@router.get("/circles/{circle_id}/letters/reveal")
def read_letters(
    circle_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """The circle's letters, once they've opened and for seven days after:
    to everyone who was in the circle then, whether they wrote or not.
    Sealed before, and gone after (403 either way).

    Each letter is its id and its words. They come in the order of their
    ids, which are random: the same shuffle for everyone, every time, and
    nothing to do with when each was written. A block hides nothing here,
    on purpose (`circle_letters.py`)."""
    membership, circle = membership_in(db, user, circle_id)
    now = clock.now()
    decay.open_letters(db, clock, circle.id)
    reading = _reading(db, membership, now)
    if reading is None:
        raise HTTPException(403, {"code": "circle_letters_sealed"})
    month, revealed_at = reading
    rows = db.execute(
        select(CircleLetter.id, CircleLetter.body)
        .where(
            CircleLetter.circle_id == circle.id,
            CircleLetter.month == month,
            CircleLetter.revealed_at.is_not(None),
        )
        .order_by(CircleLetter.id)
    ).all()
    return {
        "month": circle_letters.label(month),
        "revealed_at": iso(revealed_at),
        "fades_at": iso(circle_letters.fades_at(revealed_at)),
        "letters": [{"id": letter_id, "body": words} for letter_id, words in rows],
    }


def readable_letter(db: Session, user: User, letter_id: str, now: datetime) -> CircleLetter | None:
    """A letter this person could have read: opened, not yet gone, in a
    circle they were in when it opened. What a report may be about."""
    row = db.get(CircleLetter, letter_id)
    membership = db.get(Membership, (row.circle_id, user.id)) if row else None
    if (
        membership is None
        or row.revealed_at is None
        or row.revealed_at <= now - circle_letters.VISIBLE_FOR
        or row.revealed_at < membership.joined_at
    ):
        return None
    return row
