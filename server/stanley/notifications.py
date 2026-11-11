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
N5: (build 37, a product decision on 2026-11-07, asked for twice by the
    person who builds Stanley.) A third notice, and the one exception to N1
    and N3: "{name} shared a moment", to the people in the circle a photo was
    posted to who turned it on. The only notice that carries a name, and the
    name is all it carries: no photo, caption, place or count. Never to the
    poster, never across a block either way, never for a retake of the day
    (one notice per person per circle per day, like the photo itself), and
    never for a like, hold, story, mention, note or anything else.

N6: (build 39, a product decision on 2026-11-11 by the person who builds
    Stanley.) Two reminders a person sets for themselves, and the first
    notices that ask for something: "Leave a note for your circle today" and
    "Your circle is waiting for today's moment", each at one of four hours
    of their own day they choose (9, 14, 18 or 21). Each goes at most once
    a day, only to the person who turned it on, and only when it's still
    true: no note of theirs on any board today, or no photo of theirs in any
    circle today. They carry no name, count, deadline or image (N4), and
    nothing about what anyone else did.

There is deliberately no generic "send a push" endpoint anywhere else in the
codebase; everything funnels through the functions below.

All of them are off until the person turns them on (build 18; the digest used
to go to everyone, back when it was only ever logged). A notice reaches a
phone through APNs (`apns.py`) once its log row is committed, never before: a
pass that rolls back sends nothing, so nothing is ever sent twice.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import event, select
from sqlalchemy.orm import Session

from .clock import Clock
from .models import Block, CircleNote, Membership, NotificationLog, Photo, User


def make_notifier(settings, sessionmaker) -> "Notifier":
    """A notifier for the app's sessions: pushing through APNs when the key is
    configured, and only logging when it isn't (dev, tests, and a deployment
    without a key)."""
    transport = None
    if settings.apns_configured:
        from .apns import APNs, PushDelivery

        apns = APNs(settings.apns_key, settings.apns_key_id, settings.apns_team_id, settings.apns_topic)
        transport = PushDelivery(apns, sessionmaker)
    notifier = Notifier(transport)
    notifier.attach(sessionmaker)
    return notifier


class Notifier:
    """Records every send to NotificationLog and hands the payload to a
    transport (APNs where it's configured, nothing in dev and tests) once the
    session that logged it commits. `attach` connects it to the app's
    sessions; a notice logged in a session it isn't attached to is only
    logged."""

    def __init__(self, transport=None):
        self._transport = transport
        # Where this notifier keeps a session's notices until it commits. Its
        # own key, so two notifiers on one sessionmaker never take each
        # other's.
        self._pending = f"stanley.pending_notices.{id(self)}"

    def attach(self, sessionmaker) -> None:
        event.listen(sessionmaker, "after_commit", self._deliver)
        event.listen(sessionmaker, "after_soft_rollback", self._forget)

    def send(
        self, session: Session, user_id: str, kind: str, body: str, now: datetime, later=None
    ) -> None:
        """`later`, a request's BackgroundTasks: deliver after the response
        rather than inside the commit, so a request never waits on Apple.
        Still only after the commit: a route's session commits before its
        response, and a request whose commit fails has no response to run
        its background tasks after."""
        session.add(NotificationLog(user_id=user_id, kind=kind, body=body, sent_at=now))
        if self._transport is None:
            return
        if later is not None:
            later.add_task(self._deliver_one, user_id, kind, body)
        else:
            session.info.setdefault(self._pending, []).append((user_id, kind, body))

    def _deliver_one(self, user_id: str, kind: str, body: str) -> None:
        try:
            self._transport(user_id, kind, body)
        except Exception:
            logging.getLogger("stanley").exception("notice delivery failed")

    def _deliver(self, session: Session) -> None:
        pending = session.info.pop(self._pending, [])
        for user_id, kind, body in pending:
            try:
                self._transport(user_id, kind, body)
            except Exception:
                # The notice is logged and the pass is committed; a push that
                # didn't go is a missed notice, never a failed sweep.
                logging.getLogger("stanley").exception("notice delivery failed")

    def _forget(self, session: Session, previous_transaction) -> None:
        session.info.pop(self._pending, None)


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
    # Only people who asked for it (off by default).
    users = session.scalars(
        select(User).where(User.deleted_at.is_(None), User.digest_enabled.is_(True))
    ).all()
    for user in users:
        try:
            tz = ZoneInfo(user.tz_last_seen or "UTC")
        except (ZoneInfoNotFoundError, ValueError):
            # A zone this server doesn't know (kept before zones were
            # checked, or dropped from tzdata): this person's evening is
            # UTC's, and nobody else's digest waits on it.
            tz = ZoneInfo("UTC")
        local_now = now.astimezone(tz)
        if local_now.hour != digest_hour:
            continue
        # Every circle the person is in, and still one digest a day: a second
        # circle never means a second push.
        circle_ids = session.scalars(
            select(Membership.circle_id).where(Membership.user_id == user.id)
        ).all()
        if not circle_ids:
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
        anyone = session.scalars(
            select(Photo.id).where(
                Photo.circle_id.in_(circle_ids),
                Photo.owner_id.is_not(None),
                Photo.owner_id != user.id,
                Photo.deleted_at.is_(None),
                Photo.taken_at >= day_start,
                Photo.taken_at <= now,
            ).limit(1)
        ).first()
        if anyone is None:
            continue
        # Whether anyone posted decides if there is a digest at all; how many
        # never reaches the words. A notification carries no count (N4).
        notifier.send(session, user.id, "digest", DIGEST_BODY, now)
        sent += 1
    return sent


CIRCLE_POST_KIND = "circle_post"


def circle_post_body(poster: User) -> str:
    """The poster's name and that they shared a moment: nothing about the
    photo, and no number (N4, N5)."""
    name = (poster.display_name or "").strip()
    return f"{name} shared a moment" if name else "Someone in your circle shared a moment"


def send_circle_post_notices(
    session: Session,
    notifier: Notifier,
    photo: Photo,
    poster: User,
    now: datetime,
    later=None,
    retake: bool = False,
) -> int:
    """§10 N5. Called only from a photo's capture, once its row is in the
    session. Everyone else in the photo's circle who turned the notice on
    and isn't on either side of a block with the poster. A retake of the
    day (the redo) is not news a second time. Returns sends."""
    if retake:
        return 0
    recipients = session.scalars(
        select(User)
        .join(Membership, Membership.user_id == User.id)
        .where(
            Membership.circle_id == photo.circle_id,
            User.id != poster.id,
            User.deleted_at.is_(None),
            User.circle_posts_enabled.is_(True),
        )
    ).all()
    # Both ways, as everywhere a block reaches (§15). Asked here rather than
    # through serialize.blocked_ids, which would import this module back.
    blocked = set(
        session.scalars(select(Block.blocked_id).where(Block.blocker_id == poster.id)).all()
    ) | set(session.scalars(select(Block.blocker_id).where(Block.blocked_id == poster.id)).all())
    body = circle_post_body(poster)
    sent = 0
    for user in recipients:
        if user.id in blocked:
            continue
        notifier.send(session, user.id, CIRCLE_POST_KIND, body, now, later=later)
        sent += 1
    return sent


# --- §10 N6: the two reminders a person sets for themselves -------------------

# The hours a reminder may be set for: morning, afternoon, evening, night.
REMINDER_HOURS = (9, 14, 18, 21)
NOTE_REMINDER_KIND = "note_reminder"
PHOTO_REMINDER_KIND = "photo_reminder"
NOTE_REMINDER_BODY = "Leave a note for your circle today"
PHOTO_REMINDER_BODY = "Your circle is waiting for today's moment"


def _zone(user: User) -> ZoneInfo:
    try:
        return ZoneInfo(user.tz_last_seen or "UTC")
    except (ZoneInfoNotFoundError, ValueError):
        return ZoneInfo("UTC")


def run_reminders(session: Session, notifier: Notifier, clock: Clock) -> int:
    """§10 N6. For everyone who set a reminder and whose own clock is in the
    hour they chose: one push, if they haven't had today's and it's still
    true (no note of theirs on a board today; no photo of theirs today).
    Someone in no circle has nothing to be reminded of. Returns sends."""
    now = clock.now()
    sent = 0
    users = session.scalars(
        select(User).where(
            User.deleted_at.is_(None),
            User.note_reminder_enabled.is_(True) | User.photo_reminder_enabled.is_(True),
        )
    ).all()
    for user in users:
        local_now = now.astimezone(_zone(user))
        wanted = [
            (kind, body)
            for on, hour, kind, body in (
                (user.note_reminder_enabled, user.note_reminder_hour, NOTE_REMINDER_KIND, NOTE_REMINDER_BODY),
                (user.photo_reminder_enabled, user.photo_reminder_hour, PHOTO_REMINDER_KIND, PHOTO_REMINDER_BODY),
            )
            if on and local_now.hour == hour
        ]
        if not wanted:
            continue
        circle_ids = session.scalars(
            select(Membership.circle_id).where(Membership.user_id == user.id)
        ).all()
        if not circle_ids:
            continue
        day_start = local_now.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(
            ZoneInfo("UTC")
        )
        for kind, body in wanted:
            already = session.scalars(
                select(NotificationLog.id).where(
                    NotificationLog.user_id == user.id,
                    NotificationLog.kind == kind,
                    NotificationLog.sent_at >= day_start,
                ).limit(1)
            ).first()
            if already is not None:
                continue
            if kind == NOTE_REMINDER_KIND:
                # A note lives until the end of its author's day, so one
                # that's still up is today's.
                done = session.scalars(
                    select(CircleNote.id).where(
                        CircleNote.author_id == user.id, CircleNote.expires_at > now
                    ).limit(1)
                ).first()
            else:
                done = session.scalars(
                    select(Photo.id).where(
                        Photo.owner_id == user.id,
                        Photo.local_date == local_now.date(),
                        Photo.deleted_at.is_(None),
                    ).limit(1)
                ).first()
            if done is not None:
                continue
            notifier.send(session, user.id, kind, body, now)
            sent += 1
    return sent
