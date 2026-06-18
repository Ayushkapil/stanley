"""Response shaping. Invariant A2 is enforced structurally here: the photo
payload has no field for anchor identities or counts — only the caller's own
anchor state. Who-anchored lists exist solely on the owner-only endpoint."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import physics
from .config import Settings
from .models import Anchor, Block, Comment, CommunityNote, Like, Photo, User
from .storage import signed_url

DEPARTED = "departed"


def iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt else None


def avatar_url(settings: Settings | None, key: str | None, now: datetime | None) -> str | None:
    """Avatars are identity, not content — they don't decay, but reads are still
    short-TTL signed (§9). None when there's no avatar or no signing context."""
    if not settings or not key or now is None:
        return None
    return signed_url(settings.secret_key, key, now, settings.signed_url_ttl_seconds)


def blocked_ids(session: Session, user_id: str) -> set[str]:
    """Blocking hides content bidirectionally within the circle (§15)."""
    out = set(
        session.scalars(select(Block.blocked_id).where(Block.blocker_id == user_id)).all()
    )
    out.update(
        session.scalars(select(Block.blocker_id).where(Block.blocked_id == user_id)).all()
    )
    return out


def user_brief(
    session: Session,
    user_id: str | None,
    settings: Settings | None = None,
    now: datetime | None = None,
) -> dict:
    """A person, reduced to a face and a name — never a number. Pass settings+now
    to include a signed avatar URL."""
    user = session.get(User, user_id) if user_id else None
    if user is None or user.deleted_at is not None or not user.display_name:
        return {"id": user_id, "display_name": DEPARTED, "avatar_url": None}
    return {
        "id": user.id,
        "display_name": user.display_name,
        "avatar_url": avatar_url(settings, user.avatar_key, now),
    }


def community_note_payload(
    session: Session, settings: Settings, now: datetime, circle_id: str
) -> dict | None:
    """The active community note (Part 4), or None. A note stops showing at the
    end of the author's local day — same as everything else, it's gone by then."""
    note = session.get(CommunityNote, circle_id)
    if note is None or now >= note.expires_at:
        return None
    return {
        "text": note.body,
        "author": user_brief(session, note.author_id, settings, now),
        "set_at": iso(note.created_at),
    }


def comment_payload(
    session: Session, comment: Comment, settings: Settings | None = None, now: datetime | None = None
) -> dict:
    return {
        "id": comment.id,
        "author": user_brief(session, comment.author_id, settings, now),
        "body": comment.body,
        "created_at": iso(comment.created_at),
    }


def visible_comments(
    session: Session,
    photo_id: str,
    viewer_id: str,
    settings: Settings | None = None,
    now: datetime | None = None,
) -> list[dict]:
    hidden = blocked_ids(session, viewer_id)
    comments = session.scalars(
        select(Comment)
        .where(Comment.photo_id == photo_id, Comment.deleted_at.is_(None))
        .order_by(Comment.created_at)  # flat, chronological (§8.3)
    ).all()
    return [comment_payload(session, c, settings, now) for c in comments if c.author_id not in hidden]


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
    my_like = session.get(Like, (photo.id, viewer.id))
    return {
        "id": photo.id,
        "owner": user_brief(session, photo.owner_id, settings, now),
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
        "comments": visible_comments(session, photo.id, viewer.id, settings, now),
        "anchored_by_me": my_anchor is not None,
        "my_anchor_note": my_anchor.note if my_anchor else None,
        # The caller's own like state only — never a count, never who else.
        "liked_by_me": my_like is not None,
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
