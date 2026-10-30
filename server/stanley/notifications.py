"""The §10 notification policy, written as code rather than sensibility.

N1: at most one push per user per day — a single evening digest.
N2: exactly one decay-related notification exists in the entire system: the
    owner's LAST_LIGHT notice for their own photo. Fires once, never repeats,
    off by default.
N3: nothing else exists. No pushes for others' fades, for anchors, for
    comments, or for streaks — streaks do not exist.
N4: no notification may contain an engagement count, a deadline timestamp, or
    a countdown. (The digest's new-moment count is explicitly sanctioned by
    N1's wording; N4 targets urgency and judgment, not volume of moments.)

There is deliberately no generic "send a push" endpoint anywhere else in the
codebase; everything funnels through the two functions below.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from .clock import Clock
from .models import Membership, NotificationLog, Photo, User


class Notifier:
    """Records every send to NotificationLog and hands the payload to a
    transport (APNs in production, nothing in dev/tests)."""

    def __init__(self, transport=None):
        self._transport = transport

    def send(self, session: Session, user_id: str, kind: str, body: str, now: datetime) -> None:
        session.add(NotificationLog(user_id=user_id, kind=kind, body=body, sent_at=now))
        if self._transport is not None:
            self._transport(user_id, kind, body)


def maybe_send_last_light_notice(
    session: Session, notifier: Notifier, photo: Photo, now: datetime
) -> None:
    """§10 N2. Called only from the FADING -> LAST_LIGHT transition."""
    if photo.last_light_notified_at is not None:
        return
    photo.last_light_notified_at = now  # once, ever, regardless of settings churn
    if photo.owner_id is None:
        return
    owner = session.get(User, photo.owner_id)
    if owner is None or owner.deleted_at is not None or not owner.last_light_notice_enabled:
        return
    weekday = photo.taken_at.astimezone(ZoneInfo(photo.taken_tz)).strftime("%A")
    # No timestamp, no countdown (N4) — just which day the moment is from.
    notifier.send(session, owner.id, "last_light", f"Your moment from {weekday} is fading", now)


DIGEST_BODY = "Something new from your circle today."


def run_evening_digests(
    session: Session, notifier: Notifier, clock: Clock, digest_hour: int = 20
) -> int:
    """§10 N1. Sends the single daily digest to users whose local time is in
    the digest hour and who haven't received one today. Returns sends."""
    now = clock.now()
    sent = 0
    users = session.scalars(select(User).where(User.deleted_at.is_(None))).all()
    for user in users:
        tz = ZoneInfo(user.tz_last_seen or "UTC")
        local_now = now.astimezone(tz)
        if local_now.hour != digest_hour:
            continue
        membership = session.scalars(
            select(Membership).where(Membership.user_id == user.id)
        ).first()
        if membership is None:
            continue
        day_start = local_now.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(
            ZoneInfo("UTC")
        )
        already = session.scalars(
            select(NotificationLog).where(
                NotificationLog.user_id == user.id,
                NotificationLog.kind == "digest",
                NotificationLog.sent_at >= day_start,
            )
        ).first()
        if already is not None:
            continue
        n = len(
            session.scalars(
                select(Photo.id).where(
                    Photo.circle_id == membership.circle_id,
                    Photo.owner_id.is_not(None),
                    Photo.owner_id != user.id,
                    Photo.deleted_at.is_(None),
                    Photo.taken_at >= day_start,
                    Photo.taken_at <= now,
                )
            ).all()
        )
        if n == 0:
            continue
        # Whether anyone posted decides if there is a digest at all; how many
        # never reaches the words. A notification carries no count (N4).
        notifier.send(session, user.id, "digest", DIGEST_BODY, now)
        sent += 1
    return sent
