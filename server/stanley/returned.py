"""The Returned surface (§14): max one item per local day, surfaced quietly.

Source priority: anniversary, near-forgotten, rescue. The MVP near-forgotten
heuristic is a random eligible pick; on-device selection is the Phase 2
hardening target and deliberately does not exist here.
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
        if photo.id not in rested:
            return photo
    return None


def returned_item(
    session: Session, settings: Settings, clock: Clock, user: User, tz_name: str
) -> dict | None:
    now = clock.now()
    today = now.astimezone(ZoneInfo(tz_name)).date()

    log = session.get(ReturnedLog, (user.id, today))
    if log is not None:
        photo = session.get(Photo, log.photo_id)
        if photo is None or photo.state == physics.PURGED:
            return None
        if photo.id in _rested_ids(session, user.id):
            return None  # rested mid-day: suppressed immediately, no second pick
        anchor = session.get(Anchor, (photo.id, user.id))
        if log.source == "rescue":
            return {"source": "rescue", "photo": photo_payload(session, settings, now, photo, user)}
        if anchor is None:
            return None
        return {"source": log.source, "photo": memory_payload(session, settings, now, photo, anchor, user)}

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

    rescue = _pick_rescue(session, user, _rested_ids(session, user.id))
    if rescue is not None:
        session.add(
            ReturnedLog(user_id=user.id, local_date=today, photo_id=rescue.id, source="rescue")
        )
        return {"source": "rescue", "photo": photo_payload(session, settings, now, rescue, user)}

    return None
