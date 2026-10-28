"""The decay engine (§13). Server-authoritative; clients only render the fade.

Invariant A1 lives here structurally: nothing in this module reads anchors to
decide visibility or timing — anchors are consulted only *after* expiry, to
decide whether the blob survives for memory threads.
"""
from __future__ import annotations

import hashlib
from datetime import datetime, timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from . import physics
from .clock import Clock
from .models import Anchor, Comment, DecayAudit, Like, Photo, PhotoTag, PurgeQueueItem
from .notifications import Notifier, maybe_send_last_light_notice
from .storage import BlobStore

TOMBSTONE = timedelta(days=physics.TOMBSTONE_DAYS)


def _anchor_count(session: Session, photo_id: str) -> int:
    return session.scalar(
        select(func.count()).select_from(Anchor).where(Anchor.photo_id == photo_id)
    )


def enqueue_purge(session: Session, photo: Photo, purge_after: datetime) -> None:
    photo.purge_after = purge_after
    session.add(PurgeQueueItem(photo_id=photo.id, purge_after=purge_after))


def sweep(session: Session, clock: Clock, notifier: Notifier) -> int:
    """Advance every overdue photo one transition at a time until none are
    overdue. Idempotent: a transition moves the deadline forward (or clears
    it), so re-running is a no-op. A sweep that runs late walks a photo
    through every missed state, each with its own audit row."""
    now = clock.now()
    advanced = 0
    while True:
        overdue = session.scalars(
            select(Photo).where(
                Photo.state.in_(physics.PUBLIC_STATES),
                Photo.state_deadline.is_not(None),
                Photo.state_deadline <= now,
            )
        ).all()
        if not overdue:
            break
        for photo in overdue:
            from_state = photo.state
            to_state = physics.NEXT_STATE[from_state]
            session.add(
                DecayAudit(photo_id=photo.id, from_state=from_state, to_state=to_state, at=now)
            )
            if to_state == physics.EXPIRED:
                expiry = photo.state_deadline
                photo.state = physics.EXPIRED
                photo.state_deadline = None
                # Likes decay WITH the photo. Leaving Today is the end of them —
                # gone forever, never archived, never recountable.
                session.execute(delete(Like).where(Like.photo_id == photo.id))
                # §8.2 retention rule: blob survives purge iff ≥1 anchor at expiry.
                if _anchor_count(session, photo.id) == 0:
                    enqueue_purge(session, photo, expiry + TOMBSTONE)
            else:
                photo.state = to_state
                photo.state_deadline = physics.state_deadline(to_state, photo.taken_at)
                if to_state == physics.LAST_LIGHT:
                    maybe_send_last_light_notice(session, notifier, photo, now)
            advanced += 1
        session.flush()
    return advanced


def owner_hash_for(user_id: str) -> str:
    """The anonymous stand-in an owner leaves on a row they no longer hold: the
    scheduled purge (13) writes it, and so does the same-day redo, which
    releases the row from the owner's slot in exactly the same shape."""
    return hashlib.sha256(user_id.encode()).hexdigest()


def scrub(
    session: Session,
    storage: BlobStore,
    photo: Photo,
    now: datetime,
    *,
    owner_requested: bool,
) -> None:
    """Remove the image bytes everywhere and reduce the row.

    owner_requested=True is the §8.2 deletion override: the subject wins.
    Anchorers keep an honest tombstone and their own comment text only; the
    owner keeps the day slot (no refunds), so owner_id stays on the row.

    owner_requested=False is the scheduled purge of an unanchored photo: the
    row becomes an anonymous tombstone, owner retained only as a hash for
    abuse audit (§13).
    """
    for key in (photo.blob_key, photo.deriv_key, photo.thumb_key):
        if key:
            storage.delete(key)
    photo.blob_key = photo.deriv_key = photo.thumb_key = None
    photo.caption = None
    photo.location = None
    # Likes never outlive the photo they belonged to. A delete before expiry
    # takes its likes with it, just as expiry would have.
    session.execute(delete(Like).where(Like.photo_id == photo.id))
    # 'Who was there' tags are part of the artifact — purged with it (Part 3).
    session.execute(delete(PhotoTag).where(PhotoTag.photo_id == photo.id))

    if owner_requested:
        anchorer_ids = set(
            session.scalars(select(Anchor.user_id).where(Anchor.photo_id == photo.id)).all()
        )
        for comment in session.scalars(
            select(Comment).where(Comment.photo_id == photo.id)
        ).all():
            if comment.author_id not in anchorer_ids:
                session.delete(comment)
        photo.deleted_at = now
    else:
        for comment in session.scalars(
            select(Comment).where(Comment.photo_id == photo.id)
        ).all():
            session.delete(comment)
        if photo.owner_id is not None:
            photo.owner_hash = owner_hash_for(photo.owner_id)
            photo.owner_id = None

    session.add(
        DecayAudit(photo_id=photo.id, from_state=photo.state, to_state=physics.PURGED, at=now)
    )
    photo.state = physics.PURGED
    photo.state_deadline = None


def run_purges(session: Session, storage: BlobStore, clock: Clock) -> int:
    """Process due purge-queue items: delete blobs, verify, anonymize (§13)."""
    now = clock.now()
    purged = 0
    items = session.scalars(
        select(PurgeQueueItem).where(
            PurgeQueueItem.done.is_(False), PurgeQueueItem.purge_after <= now
        )
    ).all()
    for item in items:
        item.attempted_at = now
        photo = session.get(Photo, item.photo_id)
        if photo is not None and photo.state != physics.PURGED:
            # A late anchor can't exist (anchoring is impossible after expiry),
            # but the guard keeps the queue safe against double-entries.
            if _anchor_count(session, photo.id) == 0:
                scrub(session, storage, photo, now, owner_requested=False)
                purged += 1
        item.done = True
    session.flush()
    return purged
