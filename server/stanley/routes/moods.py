"""The mark on your day (build 52; its own store since build 65, the answer
sheet). One of five, no labels, kept for its owner alone: `day_moods`, one
row per person per day, the only place a mark lives.

It's set only on the day it's for, and only on that day as its owner lives
it: their own midnight, in the zone the phone sends (`tz`), never UTC's. A
day gone by stays as it was, marked or not: nothing fills in a missed day
(the brief: "the gaps are part of the record"). Nothing here counts, totals,
averages or compares the marks, and none of it is in anything sent to
anyone else."""
from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from .. import journal, physics
from ..deps import get_clock, get_current_user, get_db
from ..models import DayMood, User
from ..ratelimit import per_person
from .photos import valid_timezone

router = APIRouter(tags=["moods"])


class MoodBody(BaseModel):
    # Required, and null takes today's mark back.
    level: int | None
    # The sender's zone, an IANA name: whose today it is.
    tz: str = Field(max_length=64)


def mood_payload(row: DayMood) -> dict:
    return {"day": row.day.isoformat(), "level": row.score}


def set_mark(db: Session, user: User, day: date, level: int | None, now) -> None:
    """Today's mark set, changed or (None) taken back. The caller has
    already made sure `day` is the person's own today."""
    if level is None:
        db.execute(delete(DayMood).where(DayMood.user_id == user.id, DayMood.day == day))
        return
    db.execute(
        sqlite_insert(DayMood)
        .values(user_id=user.id, day=day, score=level, photo_id=None, updated_at=now)
        .on_conflict_do_update(
            index_elements=["user_id", "day"],
            set_={"score": level, "photo_id": None, "updated_at": now},
        )
    )


@router.put("/moods/{day}", dependencies=[per_person("journal")])
def put_mood(
    day: str,
    body: MoodBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """Mark today, change today's mark, or (`level: null`) take it back.
    Any other day is refused (400 `not_today`): yesterday can't be filled
    in after the fact and tomorrow can't be marked ahead of time."""
    if not valid_timezone(body.tz):
        raise HTTPException(400, {"code": "bad_timezone"})
    try:
        asked = date.fromisoformat(day)
    except ValueError:
        raise HTTPException(400, {"code": "bad_day"})
    level = body.level
    if level is not None and not (physics.SCORE_MIN <= level <= physics.SCORE_MAX):
        raise HTTPException(400, {"code": "bad_level"})
    now = clock.now()
    if asked != journal.local_day(now, body.tz):
        raise HTTPException(400, {"code": "not_today"})
    user.tz_last_seen = body.tz
    set_mark(db, user, asked, level, now)
    return {"day": asked.isoformat(), "level": level}


@router.get("/moods")
def get_moods(
    since: date | None = Query(default=None, alias="from"),
    until: date | None = Query(default=None, alias="to"),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Your own marks, oldest first, from `from` to `to` (both days
    included; either may be left out). Nobody else's, ever: there's no
    way to ask for anyone but yourself."""
    if since is not None and until is not None and since > until:
        raise HTTPException(400, {"code": "bad_range"})
    query = select(DayMood).where(DayMood.user_id == user.id)
    if since is not None:
        query = query.where(DayMood.day >= since)
    if until is not None:
        query = query.where(DayMood.day <= until)
    rows = db.scalars(query.order_by(DayMood.day)).all()
    return {"moods": [mood_payload(row) for row in rows]}
