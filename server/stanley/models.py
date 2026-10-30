from __future__ import annotations

import secrets
import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, UTCDateTime
from .physics import CIRCLE_CAP, LIVE


def new_id() -> str:
    return uuid.uuid4().hex


# No I/O/0/1 to avoid visual confusion when read aloud or hand-typed.
_INVITE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def new_invite_code() -> str:
    """Short human-friendly invite code in XXXX-XXXX format."""
    chars = [secrets.choice(_INVITE_CHARS) for _ in range(8)]
    return f"{''.join(chars[:4])}-{''.join(chars[4:])}"


class User(Base):
    __tablename__ = "users"
    __table_args__ = (Index("uq_users_username", "username", unique=True),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    apple_sub: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(80), nullable=True)
    username: Mapped[str | None] = mapped_column(String(30), nullable=True)
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    tz_last_seen: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # §10 N2: the last-light notice is off by default, offerable in settings.
    last_light_notice_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)


class Circle(Base):
    __tablename__ = "circles"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(80))
    created_by: Mapped[str] = mapped_column(ForeignKey("users.id"))
    cap: Mapped[int] = mapped_column(Integer, default=CIRCLE_CAP)
    invite_token: Mapped[str] = mapped_column(String(9), unique=True, default=new_invite_code)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class Membership(Base):
    __tablename__ = "memberships"

    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    joined_at: Mapped[datetime] = mapped_column(UTCDateTime)
    role: Mapped[str] = mapped_column(String(16), default="member")


class Photo(Base):
    __tablename__ = "photos"
    # The slot is per owner per local calendar day, including soft-deleted rows
    # (no refunds, §8.4). NULL owner_id rows (anonymized tombstones) don't collide.
    __table_args__ = (
        UniqueConstraint("owner_id", "local_date", name="uq_owner_localdate"),
        Index("ix_photos_circle_state", "circle_id", "state"),  # feed query (M3)
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    owner_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id"))
    blob_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    deriv_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    thumb_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    taken_at: Mapped[datetime] = mapped_column(UTCDateTime)
    taken_tz: Mapped[str] = mapped_column(String(64))
    local_date: Mapped[date] = mapped_column(Date)
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)
    # A human-written place label ("Dunn Meadow"), never coordinates. EXIF GPS
    # is stripped at ingest (§9); location is memory detail, not device data.
    location: Mapped[str | None] = mapped_column(String(120), nullable=True)
    state: Mapped[str] = mapped_column(String(12), default=LIVE)
    state_deadline: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    last_light_notified_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    purge_after: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    # §13: after purge the row is reduced to an anonymous tombstone; the owner
    # survives only as a hash, for abuse audit.
    owner_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)


class Anchor(Base):
    """A durable per-person reference (§8.2). Not a state of the photo."""

    __tablename__ = "anchors"

    __table_args__ = (Index("ix_anchors_photo", "photo_id"),)

    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_viewed_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)


class Like(Base):
    """The like — a heart in the UI, but on Stanley's physics, not Instagram's.

    A like decays WITH the photo: when the photo leaves Today (EXPIRED), every
    like row for it is deleted forever — never archived, never recountable.
    Owner-only visibility (the owner sees faces, never a number); nobody else
    sees likes at all. There is no count, anywhere — the heart is cosmetic.
    """

    __tablename__ = "likes"
    __table_args__ = (Index("ix_likes_photo", "photo_id"),)

    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class CommunityNote(Base):
    """One short shared line for the whole circle (Part 4) — a sticky note the
    day erases, not a chat. Single active row per circle (last-writer-wins);
    it stops showing at the end of the author's local day. No replies, no
    reactions, no threads — by construction there's nowhere to put them."""

    __tablename__ = "community_notes"

    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id"), primary_key=True)
    author_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(String(90))
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class PhotoTag(Base):
    """'Who was there' (Part 3): a memory detail, not a mention. No notification,
    not a profile link. Decays/held/purged with the photo it belongs to."""

    __tablename__ = "photo_tags"
    __table_args__ = (Index("ix_phototags_photo", "photo_id"),)

    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"), primary_key=True)
    tagged_user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class Milestone(Base):
    """Quiet, private reflections (Part 4). Surfaced at most one per week, shown
    once, dismissable. (kind, mkey) makes each milestone fire exactly once."""

    __tablename__ = "milestones"
    __table_args__ = (
        UniqueConstraint("user_id", "kind", "mkey", name="uq_milestone_once"),
        Index("ix_milestones_user", "user_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(24))
    mkey: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    dismissed: Mapped[bool] = mapped_column(Boolean, default=False)


class Comment(Base):
    """Story additions (§8.3): flat, chronological, part of the artifact."""

    __tablename__ = "comments"
    __table_args__ = (Index("ix_comments_photo", "photo_id"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"))
    author_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)


class Rest(Base):
    """'Rest a memory' (§14): retired from resurfacing, kept in the archive."""

    __tablename__ = "rests"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"), primary_key=True)
    rested_at: Mapped[datetime] = mapped_column(UTCDateTime)


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    reporter_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    photo_id: Mapped[str | None] = mapped_column(ForeignKey("photos.id"), nullable=True)
    comment_id: Mapped[str | None] = mapped_column(ForeignKey("comments.id"), nullable=True)
    reason: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    resolved_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)


class Block(Base):
    __tablename__ = "blocks"

    blocker_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    blocked_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class PurgeQueueItem(Base):
    __tablename__ = "purge_queue"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"))
    purge_after: Mapped[datetime] = mapped_column(UTCDateTime)
    attempted_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    done: Mapped[bool] = mapped_column(Boolean, default=False)


class DecayAudit(Base):
    """Append-only (§13). Decay bugs are trust bugs; 'my photo vanished early'
    must be answerable."""

    __tablename__ = "decay_audit"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    photo_id: Mapped[str] = mapped_column(String(32))
    from_state: Mapped[str] = mapped_column(String(12))
    to_state: Mapped[str] = mapped_column(String(12))
    at: Mapped[datetime] = mapped_column(UTCDateTime)


class ReturnedLog(Base):
    """§14: max one resurfaced item per user per local day; repeat calls the
    same day get the same item."""

    __tablename__ = "returned_log"

    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    local_date: Mapped[date] = mapped_column(Date, primary_key=True)
    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"))
    source: Mapped[str] = mapped_column(String(16))
    # "Not now" for today (distinct from rest, which is forever). Cleared with
    # the day, since the row is keyed by local_date.
    dismissed: Mapped[bool] = mapped_column(Boolean, default=False)


class NotificationLog(Base):
    """Every push the system ever sends, for §10 policy enforcement and audit."""

    __tablename__ = "notification_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(24))
    body: Mapped[str] = mapped_column(Text)
    sent_at: Mapped[datetime] = mapped_column(UTCDateTime)


class NewsCache(Base):
    """The World Today: the last good set of headlines, in a single row. The
    background refresh is the only writer, and every client reads this row
    rather than calling NewsAPI. No user's data is involved, so nothing in
    deletion, export or Held ever looks here."""

    __tablename__ = "news_cache"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    fetched_at: Mapped[datetime] = mapped_column(UTCDateTime)
    articles: Mapped[str] = mapped_column(Text)  # JSON list, already normalized
