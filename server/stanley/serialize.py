"""Response shaping. Invariant A2 is enforced structurally here: the photo
payload has no field for anchor identities or counts — only the caller's own
anchor state. Who-anchored lists exist solely on the owner-only endpoint."""
from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import physics
from .config import Settings
from .models import Anchor, Block, Comment, CommunityNote, Like, Photo, PhotoTag, User
from .storage import read_url

DEPARTED = "departed"
# Someone who signed in but has not told us their name yet. Apple hands over a
# name only on the first authorization, and only if the person agrees to share
# it, so this is an ordinary state for a brand-new member — not a departure.
# Conflating the two told every new member's circle that they had already left.
UNNAMED = "New member"


def iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt else None


def avatar_url(settings: Settings | None, key: str | None, now: datetime | None) -> str | None:
    """Avatars are identity, not content — they don't decay, but reads are still
    short-TTL signed (§9). None when there's no avatar or no signing context."""
    if not settings or not key or now is None:
        return None
    return read_url(settings, key, now)


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
    # Gone is gone: no id to resolve, or the account is deleted.
    if user is None or user.deleted_at is not None:
        return {"id": user_id, "display_name": DEPARTED, "avatar_url": None}
    # Here, just nameless. Still a face, still in the circle.
    return {
        "id": user.id,
        "display_name": user.display_name or UNNAMED,
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


def weekly_mosaic(session: Session, settings: Settings, now: datetime, circle, viewer_id: str) -> dict | None:
    """The week's photos as one ephemeral artifact (Part 2). Appears only on the
    circle creator's local Sunday and Monday; None otherwise. View-only — no
    holds, likes, comments, or counts. Empty week → None (no guilt message)."""
    creator = session.get(User, circle.created_by)
    tz = ZoneInfo(creator.tz_last_seen or "UTC") if creator else ZoneInfo("UTC")
    local = now.astimezone(tz)
    weekday = local.weekday()  # Mon=0 .. Sun=6
    if weekday == 6:        # Sunday: the week ending today
        week_end = local.date()
    elif weekday == 0:      # Monday: the week that ended yesterday
        week_end = local.date() - timedelta(days=1)
    else:
        return None
    week_start = week_end - timedelta(days=6)  # the Monday

    hidden = blocked_ids(session, viewer_id)
    photos = session.scalars(
        select(Photo)
        .where(
            Photo.circle_id == circle.id,
            Photo.local_date >= week_start,
            Photo.local_date <= week_end,
            Photo.deleted_at.is_(None),
            Photo.state != physics.PURGED,
            Photo.thumb_key.is_not(None),
        )
        .order_by(Photo.taken_at)
    ).all()
    tiles = [
        {
            "thumb": read_url(settings, p.thumb_key, now),
            # A larger derivative for the swipeable carousel, plus the caption —
            # the mosaic is still view-only, this is just presentation detail.
            "image": read_url(settings, p.deriv_key, now) if p.deriv_key else None,
            "caption": p.caption,
            "owner": user_brief(session, p.owner_id, settings, now),
        }
        for p in photos
        if p.owner_id not in hidden
    ]
    if not tiles:
        return None
    return {"week_start": week_start.isoformat(), "week_end": week_end.isoformat(), "tiles": tiles}


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


def tagged_faces(
    session: Session, photo_id: str, viewer_id: str, settings: Settings | None, now: datetime | None
) -> list[dict]:
    """'Who was there' faces (Part 3) — a memory detail. Blocked pairs are
    hidden, like everything else."""
    hidden = blocked_ids(session, viewer_id)
    rows = session.scalars(
        select(PhotoTag).where(PhotoTag.photo_id == photo_id).order_by(PhotoTag.created_at)
    ).all()
    return [
        user_brief(session, t.tagged_user_id, settings, now)
        for t in rows
        if t.tagged_user_id not in hidden
    ]


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
            "image": read_url(settings, photo.deriv_key, now),
            "thumb": read_url(settings, photo.thumb_key, now),
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
        # 'Who was there' (Part 3): part of the artifact, not a mention.
        "tagged": tagged_faces(session, photo.id, viewer.id, settings, now),
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
