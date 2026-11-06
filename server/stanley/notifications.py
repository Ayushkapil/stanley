"""The §10 notification policy, written as code rather than sensibility.

N1: at most one evening digest per user per day. On by default, and anyone
    can turn it off.
N2: exactly one decay-related notification exists in the entire system: the
    owner's LAST_LIGHT notice for their own photo. Fires once, never repeats,
    off by default.
N3: one circle notification: when someone in your circle posts, "{name}
    shared a moment". Off by default. It goes only to members who turned it
    on and have a device registered, never to the poster, and never across a
    block in either direction. The name only: no image, no caption, no count.
N4: no notification may contain an engagement count, a deadline timestamp, or
    a countdown.
N5: nothing else exists. No pushes for likes, holds, comments, tags, the
    community note, others' fades, or streaks (streaks do not exist).

N3 was an explicit product decision (2026-11-06). Before it, N1 capped every
push at one a day; someone who turns circle posts on can now get one per post.

There is deliberately no generic "send a push" endpoint anywhere else in the
codebase; everything funnels through the functions below.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from .clock import Clock
from .models import Membership, NotificationLog, Photo, PushToken, User
from .serialize import UNNAMED, blocked_ids


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
        if not user.digest_enabled:
            continue
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


CIRCLE_POST = "circle_post"


def notify_circle_of_post(
    session: Session, notifier: Notifier, photo: Photo, now: datetime
) -> int:
    """§10 N3. Called once, from a successful capture, in the same transaction:
    a capture that rolls back tells no one. Returns sends."""
    poster = session.get(User, photo.owner_id) if photo.owner_id else None
    if poster is None or poster.deleted_at is not None:
        return 0
    hidden = blocked_ids(session, poster.id)  # both directions
    recipients = session.scalars(
        select(User)
        .join(Membership, Membership.user_id == User.id)
        .where(
            Membership.circle_id == photo.circle_id,
            User.id != poster.id,
            User.deleted_at.is_(None),
            User.circle_post_notice_enabled.is_(True),
            User.id.in_(select(PushToken.user_id)),
        )
    ).all()
    # Who, and nothing else (N3, N4). A nameless member is still a person.
    body = f"{poster.display_name or UNNAMED} shared a moment"
    sent = 0
    for user in recipients:
        if user.id in hidden:
            continue
        notifier.send(session, user.id, CIRCLE_POST, body, now)
        sent += 1
    return sent
