"""The Returned surface (§14): max one item per local day, surfaced quietly.

Source priority: RESCUE (own photo in last-light, time-critical) > ANNIVERSARY
(a held memory from this day a month/year ago) > NEAR-FORGOTTEN (a held memory
unseen in 90+ days). Only HELD memories resurface — plus your own last-light
photos for rescue — so holding is what makes a memory eligible to return. The
near-forgotten heuristic is a random eligible pick; a selection model is the
Phase 2 hardening target and deliberately does not exist here.
"""
from __future__ import annotations

import random
from datetime import timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import physics
from .clock import Clock
from .config import Settings
from .models import Anchor, Photo, Rest, ReturnedLog, User
from .serialize import memory_payload, photo_payload

ANNIVERSARY_MIN_DAYS = 28  # "a prior year/month": at least a month back
NEAR_FORGOTTEN = timedelta(days=90)


def _rested_ids(session: Session, user_id: str) -> set[str]:
    return set(session.scalars(select(Rest.photo_id).where(Rest.user_id == user_id)).all())


def _anchored_candidates(session: Session, user: User) -> list[tuple[Anchor, Photo]]:
    rows = session.execute(
        select(Anchor, Photo)
        .join(Photo, Photo.id == Anchor.photo_id)
        .where(Anchor.user_id == user.id, Photo.state != physics.PURGED)
    ).all()
    rested = _rested_ids(session, user.id)
    return [(a, p) for a, p in rows if p.id not in rested]


def _pick_anniversary(session, user, today):
    eligible = [
        (a, p)
        for a, p in _anchored_candidates(session, user)
        if p.local_date.day == today.day and (today - p.local_date).days >= ANNIVERSARY_MIN_DAYS
    ]
    return random.choice(eligible) if eligible else None


def _pick_near_forgotten(session, user, now):
    cutoff = now - NEAR_FORGOTTEN
    eligible = [
        (a, p)
        for a, p in _anchored_candidates(session, user)
        if (a.last_viewed_at or a.created_at) <= cutoff
    ]
    return random.choice(eligible) if eligible else None


def _pick_rescue(session, user, rested):
    # Own photo in its final fading window that the user hasn't already kept
    # (an anchor means it survives — no rescue needed) and hasn't rested.
    photos = session.scalars(
        select(Photo)
        .where(
            Photo.owner_id == user.id,
            Photo.state == physics.LAST_LIGHT,
            Photo.deleted_at.is_(None),
        )
        .order_by(Photo.state_deadline)
    ).all()
    for photo in photos:
        if photo.id in rested:
            continue
        if session.get(Anchor, (photo.id, user.id)) is not None:
            continue  # already held → already safe
        return photo
    return None


def returned_item(
    session: Session, settings: Settings, clock: Clock, user: User, tz_name: str
) -> dict | None:
    now = clock.now()
    today = now.astimezone(ZoneInfo(tz_name)).date()
    rested = _rested_ids(session, user.id)

    log = session.get(ReturnedLog, (user.id, today))
    if log is not None:
        if log.dismissed:
            return None  # "not now" for today
        photo = session.get(Photo, log.photo_id)
        if photo is None or photo.state == physics.PURGED:
            return None
        if photo.id in rested:
            return None  # rested mid-day: suppressed immediately, no second pick
        if log.source == "rescue":
            if session.get(Anchor, (photo.id, user.id)) is not None:
                return None  # kept it — it's safe now, the card's work is done
            return {"source": "rescue", "photo": photo_payload(session, settings, now, photo, user)}
        anchor = session.get(Anchor, (photo.id, user.id))
        if anchor is None:
            return None
        return {"source": log.source, "photo": memory_payload(session, settings, now, photo, anchor, user)}

    # Fresh pick for the day, in priority order.
    rescue = _pick_rescue(session, user, rested)
    if rescue is not None:
        session.add(
            ReturnedLog(user_id=user.id, local_date=today, photo_id=rescue.id, source="rescue")
        )
        return {"source": "rescue", "photo": photo_payload(session, settings, now, rescue, user)}

    picked = _pick_anniversary(session, user, today)
    source = "anniversary"
    if picked is None:
        picked = _pick_near_forgotten(session, user, now)
        source = "near_forgotten"
    if picked is not None:
        anchor, photo = picked
        anchor.last_viewed_at = now
        session.add(ReturnedLog(user_id=user.id, local_date=today, photo_id=photo.id, source=source))
        return {"source": source, "photo": memory_payload(session, settings, now, photo, anchor, user)}

    return None
