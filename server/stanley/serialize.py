"""Response shaping. Invariant A2 is enforced structurally here: the photo
payload has no field for anchor identities or counts — only the caller's own
anchor state. Who-anchored lists exist solely on the owner-only endpoint."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import physics
from .config import Settings
from .models import Anchor, Block, Comment, Photo, User
from .storage import signed_url

DEPARTED = "departed"


def iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt else None


def blocked_ids(session: Session, user_id: str) -> set[str]:
    """Blocking hides content bidirectionally within the circle (§15)."""
    out = set(
        session.scalars(select(Block.blocked_id).where(Block.blocker_id == user_id)).all()
    )
    out.update(
        session.scalars(select(Block.blocker_id).where(Block.blocked_id == user_id)).all()
    )
    return out


def user_brief(session: Session, user_id: str | None) -> dict:
    user = session.get(User, user_id) if user_id else None
    if user is None or user.deleted_at is not None or not user.display_name:
        return {"id": user_id, "display_name": DEPARTED}
    return {"id": user.id, "display_name": user.display_name}


def comment_payload(session: Session, comment: Comment) -> dict:
    return {
        "id": comment.id,
        "author": user_brief(session, comment.author_id),
        "body": comment.body,
        "created_at": iso(comment.created_at),
    }


def visible_comments(session: Session, photo_id: str, viewer_id: str) -> list[dict]:
    hidden = blocked_ids(session, viewer_id)
    comments = session.scalars(
        select(Comment)
        .where(Comment.photo_id == photo_id, Comment.deleted_at.is_(None))
        .order_by(Comment.created_at)  # flat, chronological (§8.3)
    ).all()
    return [comment_payload(session, c) for c in comments if c.author_id not in hidden]


def photo_payload(
    session: Session,
    settings: Settings,
    now: datetime,
    photo: Photo,
    viewer: User,
) -> dict:
    urls = None
    if photo.deriv_key and photo.thumb_key:
        urls = {
            "image": signed_url(settings.secret_key, photo.deriv_key, now, settings.signed_url_ttl_seconds),
            "thumb": signed_url(settings.secret_key, photo.thumb_key, now, settings.signed_url_ttl_seconds),
        }
    my_anchor = session.get(Anchor, (photo.id, viewer.id))
    return {
        "id": photo.id,
        "owner": user_brief(session, photo.owner_id),
        "taken_at": iso(photo.taken_at),
        "caption": photo.caption,
        # A typed place label, part of the memory like the caption. Never
        # coordinates, never a map link (§9: EXIF GPS is stripped at ingest).
        "location": photo.location,
        "state": photo.state,
        "decay_progress": physics.decay_progress(photo.taken_at, now),
        # §13: clients interpolate the fade between syncs from this deadline.
        "state_deadline": iso(photo.state_deadline),
        "urls": urls,
        "comments": visible_comments(session, photo.id, viewer.id),
        "anchored_by_me": my_anchor is not None,
        "my_anchor_note": my_anchor.note if my_anchor else None,
    }


def memory_payload(
    session: Session,
    settings: Settings,
    now: datetime,
    photo: Photo,
    anchor: Anchor,
    viewer: User,
) -> dict:
    if photo.state == physics.PURGED:
        # §8.2 deletion override: an honest tombstone plus the viewer's own
        # comment text only. The loss is acknowledged, not hidden.
        own_comments = session.scalars(
            select(Comment)
            .where(
                Comment.photo_id == photo.id,
                Comment.author_id == viewer.id,
                Comment.deleted_at.is_(None),
            )
            .order_by(Comment.created_at)
        ).all()
        return {
            "tombstone": True,
            "photo_id": photo.id,
            "date": photo.taken_at.date().isoformat(),
            "note": anchor.note,
            "anchored_at": iso(anchor.created_at),
            "comments": [comment_payload(session, c) for c in own_comments],
        }
    payload = photo_payload(session, settings, now, photo, viewer)
    payload.update(
        {"tombstone": False, "note": anchor.note, "anchored_at": iso(anchor.created_at)}
    )
    return payload
