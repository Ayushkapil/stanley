"""Memory milestones (Part 4): quiet, private, infrequent reflections — never
push, never gamified. At most one new milestone surfaces per week. Each fires
once (uniqueness on kind+mkey) and is dismissable.

A milestone row stores only kind + mkey; the display text and any faces/photos
are computed at read time from live data, so nothing is duplicated or stale.
"""
from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import physics
from .clock import Clock
from .config import Settings
from .models import Anchor, Membership, Milestone, Photo, User
from .serialize import iso, read_url, user_brief

WEEK = timedelta(days=7)

# circle-age thresholds, longest first (we surface the biggest one reached).
_AGE_STEPS = [(365, "1y"), (182, "6m"), (91, "3m"), (30, "1m")]
_AGE_LABEL = {
    "1m": "It's been a month.",
    "3m": "It's been three months.",
    "6m": "It's been six months.",
    "1y": "It's been a year.",
}
_HELD_STEPS = [100, 50, 25, 10]
_HELD_BY_STEPS = [50, 25, 10, 5]


def _existing(session: Session, user_id: str) -> set[tuple[str, str]]:
    rows = session.execute(
        select(Milestone.kind, Milestone.mkey).where(Milestone.user_id == user_id)
    ).all()
    return {(k, m) for k, m in rows}


def _surfaced_recently(session: Session, user_id: str, now: datetime) -> bool:
    cutoff = now - WEEK
    row = session.scalars(
        select(Milestone).where(Milestone.user_id == user_id, Milestone.created_at >= cutoff)
    ).first()
    return row is not None


def _membership(session: Session, user_id: str) -> Membership | None:
    return session.scalars(select(Membership).where(Membership.user_id == user_id)).first()


def _held_count(session: Session, user_id: str) -> int:
    return session.scalar(
        select(func.count()).select_from(Anchor).where(Anchor.user_id == user_id)
    )


def _candidate(session: Session, clock: Clock, user: User) -> tuple[str, str] | None:
    """Highest-priority milestone the user is eligible for and hasn't seen yet."""
    now = clock.now()
    seen = _existing(session, user.id)
    membership = _membership(session, user.id)

    # 1) circle age
    if membership is not None:
        elapsed = (now - membership.joined_at).days
        for days, key in _AGE_STEPS:
            if elapsed >= days and ("circle_age", key) not in seen:
                return ("circle_age", key)

    # 2) first day (after a month in the circle)
    if membership is not None and (now - membership.joined_at).days >= 30:
        if ("first_day", membership.circle_id) not in seen:
            has_first = session.scalars(
                select(Photo.id).where(
                    Photo.circle_id == membership.circle_id,
                    Photo.state != physics.PURGED,
                    Photo.thumb_key.is_not(None),
                )
            ).first()
            if has_first is not None:
                return ("first_day", membership.circle_id)

    # 3) someone has kept many of your moments
    rows = session.execute(
        select(Anchor.user_id, func.count())
        .join(Photo, Photo.id == Anchor.photo_id)
        .where(Photo.owner_id == user.id, Anchor.user_id != user.id)
        .group_by(Anchor.user_id)
        .order_by(func.count().desc())
    ).all()
    for friend_id, n in rows:
        for step in _HELD_BY_STEPS:
            if n >= step and ("held_by", f"{friend_id}:{step}") not in seen:
                return ("held_by", f"{friend_id}:{step}")

    # 4) how many you've kept
    held = _held_count(session, user.id)
    for step in _HELD_STEPS:
        if held >= step and ("held_count", str(step)) not in seen:
            return ("held_count", str(step))

    # 5) your oldest kept memory (once)
    if not any(k == "oldest" for k, _ in seen):
        oldest = session.scalars(
            select(Photo)
            .join(Anchor, Anchor.photo_id == Photo.id)
            .where(Anchor.user_id == user.id, Photo.state != physics.PURGED)
            .order_by(Photo.taken_at)
        ).first()
        if oldest is not None and (now - oldest.taken_at).days >= 30:
            return ("oldest", oldest.taken_at.strftime("%Y-%m"))

    return None


def surface_due(session: Session, clock: Clock, user: User) -> None:
    """Surface at most one new milestone, and only if none surfaced in 7 days."""
    if _surfaced_recently(session, user.id, clock.now()):
        return
    cand = _candidate(session, clock, user)
    if cand is None:
        return
    kind, mkey = cand
    session.add(Milestone(user_id=user.id, kind=kind, mkey=mkey, created_at=clock.now()))
    session.flush()


def milestone_payload(
    session: Session, settings: Settings, now: datetime, user: User, m: Milestone
) -> dict:
    base = {"id": m.id, "kind": m.kind, "created_at": iso(m.created_at)}
    if m.kind == "circle_age":
        return base | {"title": _AGE_LABEL.get(m.mkey, "Time has passed."),
                       "body": "You've been in your circle this long."}
    if m.kind == "held_count":
        return base | {"title": f"You've kept {m.mkey} memories.",
                       "body": "Quietly, one at a time."}
    if m.kind == "oldest":
        try:
            label = datetime.strptime(m.mkey, "%Y-%m").strftime("%B %Y")
        except ValueError:
            label = m.mkey
        return base | {"title": f"Your oldest kept memory is from {label}."}
    if m.kind == "held_by":
        friend_id, step = m.mkey.split(":", 1)
        face = user_brief(session, friend_id, settings, now)
        return base | {
            "title": f"{face['display_name']} has kept {step} of your moments.",
            "faces": [face],
        }
    if m.kind == "first_day":
        circle_id = m.mkey
        first = session.scalars(
            select(Photo)
            .where(
                Photo.circle_id == circle_id,
                Photo.state != physics.PURGED,
                Photo.thumb_key.is_not(None),
            )
            .order_by(Photo.taken_at)
        ).first()
        tiles = []
        if first is not None:
            same_day = session.scalars(
                select(Photo)
                .where(
                    Photo.circle_id == circle_id,
                    Photo.local_date == first.local_date,
                    Photo.state != physics.PURGED,
                    Photo.thumb_key.is_not(None),
                )
                .order_by(Photo.taken_at)
            ).all()
            tiles = [read_url(settings, p.thumb_key, now) for p in same_day]
        return base | {"title": "Your first day.", "body": "Where it started.", "photos": tiles}
    return base | {"title": "A small milestone."}
