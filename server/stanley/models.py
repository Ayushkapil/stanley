from __future__ import annotations

import secrets
import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, false, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint, text
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
    # §10 N1: the evening digest, off by default too (build 18). Before it was
    # pushed it was only logged, for everyone; now that it reaches a phone it
    # is asked for, like the last-light notice.
    digest_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    # §10 N5 (build 37, a product decision): a notice each time someone in
    # one of your circles shares a moment. Off by default, like the others.
    # Off in the database too, as the column added to older ones is, so a
    # row written without it is off rather than refused.
    circle_posts_enabled: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    # §10 N6 (build 39, a product decision): two reminders a person may set
    # for themselves, each at an hour of their own day they choose. Off by
    # default, in the database too.
    note_reminder_enabled: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    note_reminder_hour: Mapped[int] = mapped_column(Integer, default=9, server_default=text("9"))
    photo_reminder_enabled: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    photo_reminder_hour: Mapped[int] = mapped_column(Integer, default=18, server_default=text("18"))
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
    # Build 35: something this one circle is counting toward, drawn under
    # Today's dateline (`CountdownRoute` in the app). A flag, not a feature:
    # null for every circle but the one it was set on, by hand, with
    # scripts/set_countdown.py. Nothing in the app or the API creates one.
    countdown: Mapped[dict | None] = mapped_column(JSON, nullable=True)


class Membership(Base):
    __tablename__ = "memberships"
    __table_args__ = (Index("ix_memberships_user", "user_id", "joined_at"),)

    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    joined_at: Mapped[datetime] = mapped_column(UTCDateTime)
    role: Mapped[str] = mapped_column(String(16), default="member")


class Photo(Base):
    __tablename__ = "photos"
    # The slot is per owner per circle per local calendar day, including
    # soft-deleted rows (no refunds, §8.4). Per circle since build 17, when a
    # person could be in more than one: each circle has its own day. NULL
    # owner_id rows (anonymized tombstones) don't collide. Older databases
    # had UNIQUE(owner_id, local_date); `ensure_schema` rebuilds the table.
    __table_args__ = (
        UniqueConstraint("owner_id", "circle_id", "local_date", name="uq_owner_circle_localdate"),
        Index("ix_photos_circle_state", "circle_id", "state"),  # feed query (M3)
        Index("ix_photos_state_deadline", "state", "state_deadline"),  # the decay sweep
        Index("ix_photos_owner_hash", "owner_hash", "circle_id", "local_date"),  # the day's redo
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
    # The name of the filter chosen at capture ("mono", "grain", "dusk",
    # "clean"), or None. A label only: the look is already baked into the
    # pixels the client uploaded, so nothing here ever re-renders the photo.
    filter: Mapped[str | None] = mapped_column(String(12), nullable=True)
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

    __table_args__ = (Index("ix_anchors_photo", "photo_id"), Index("ix_anchors_user", "user_id"))

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
    __table_args__ = (Index("ix_likes_photo", "photo_id"), Index("ix_likes_user", "user_id"))

    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class CircleNote(Base):
    """A sticky note on the circle's board (Part 4; one each since build 27,
    when the board replaced the single shared line). Everyone in a circle can
    pin one a day, and only its author can change it or take it down. It
    clears at the end of the author's local day, and the sweep deletes it
    then (`decay.clear_notes`). Not a chat: no replies, no reactions, no
    threads, and nothing counts them — by construction there's nowhere to
    put any of that. One row per person per circle: writing again the same
    day edits it, and the next day's starts afresh once yesterday's is gone."""

    __tablename__ = "circle_notes"
    __table_args__ = (
        UniqueConstraint("circle_id", "author_id", name="uq_circle_note_author"),
        Index("ix_circle_notes_author", "author_id"),
        Index("ix_circle_notes_expiry", "expires_at"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id"))
    author_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)


class PhotoTag(Base):
    """'Who was there' (Part 3): a memory detail, not a mention. No notification,
    not a profile link. Decays/held/purged with the photo it belongs to."""

    __tablename__ = "photo_tags"
    __table_args__ = (Index("ix_phototags_photo", "photo_id"), Index("ix_phototags_user", "tagged_user_id"))

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
    __table_args__ = (Index("ix_comments_photo", "photo_id"), Index("ix_comments_author", "author_id"))

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
    __table_args__ = (
        Index("ix_reports_comment", "comment_id"),
        Index("ix_reports_photo", "photo_id"),
        Index("ix_reports_response", "response_id"),
        Index("ix_reports_letter", "letter_id"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    reporter_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    photo_id: Mapped[str | None] = mapped_column(ForeignKey("photos.id"), nullable=True)
    comment_id: Mapped[str | None] = mapped_column(ForeignKey("comments.id"), nullable=True)
    # An answer to the circle's question of the week (build 26), which the
    # whole circle reads once the answers open.
    response_id: Mapped[str | None] = mapped_column(ForeignKey("prompt_responses.id"), nullable=True)
    # A note on the circle's board (build 27). Not a foreign key: a note
    # clears at the end of its day, sooner than a report may be read, so the
    # report keeps a copy of its words in `reason` and names it here.
    note_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    # A sealed or opened letter (build 42). Only the recipient, and only once
    # it's open, can report one — a sealed letter has no words to object to
    # yet. A foreign key: a letter outlives the circle it was written in,
    # and the report follows the letter if it's deleted (set null, like
    # photo_id and response_id).
    letter_id: Mapped[str | None] = mapped_column(ForeignKey("person_letters.id"), nullable=True)
    reason: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    resolved_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)


class Block(Base):
    __tablename__ = "blocks"
    __table_args__ = (Index("ix_blocks_blocked", "blocked_id"),)

    blocker_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    blocked_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class PurgeQueueItem(Base):
    __tablename__ = "purge_queue"
    __table_args__ = (Index("ix_purge_queue_due", "done", "purge_after"),)

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
    __table_args__ = (Index("ix_notification_log_user", "user_id", "kind", "sent_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(24))
    body: Mapped[str] = mapped_column(Text)
    sent_at: Mapped[datetime] = mapped_column(UTCDateTime)


class PushToken(Base):
    """Where a person's notices go: an APNs device token for one of their
    phones (build 18). Kept only to deliver the three notices that exist,
    and only what was asked for: the last-light notice, the evening digest
    and the circle-post notice (build 37).
    A token belongs to one account at a time (a phone changes hands when
    someone else signs in on it), goes when they sign out on that phone or
    delete the account, and goes when Apple says it's no longer valid."""

    __tablename__ = "push_tokens"
    __table_args__ = (Index("ix_push_tokens_user", "user_id"),)

    token: Mapped[str] = mapped_column(String(200), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    # "production" (TestFlight and the App Store) or "sandbox" (a build run
    # from Xcode): which APNs host the token belongs to.
    environment: Mapped[str] = mapped_column(String(12))
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime)


class NewsEdition(Base):
    """The World Today: the last good set of stories for each edition, one row
    apiece, keyed by what the edition is ("national:us", or a town's
    "nearby:US:bloomington, in"). A town's row is keyed by the town, never by
    who asked for it. Every client reads these rows rather than calling a
    feed. No user's data is involved, so nothing in deletion, export or Held
    ever looks here."""

    __tablename__ = "news_editions"

    key: Mapped[str] = mapped_column(String(120), primary_key=True)
    fetched_at: Mapped[datetime] = mapped_column(UTCDateTime)
    articles: Mapped[str] = mapped_column(Text)  # JSON list, already normalized


class JournalEntry(Base):
    """What happened today, in the photo's owner's own words (build 26): a
    private entry on their own photo. Nobody else reads it, anywhere: the
    feed never carries it, and only the owner's own requests reach it. It
    lives as long as the photo does for its owner (`journal.py`): it goes
    when the photo is deleted or purged, and when the photo fades unless its
    owner held it, or later lets go of it. One per photo."""

    __tablename__ = "journal_entries"
    __table_args__ = (Index("ix_journal_entries_owner", "owner_id"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    photo_id: Mapped[str] = mapped_column(ForeignKey("photos.id"), unique=True)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime)


class WeeklyReflection(Base):
    """How the week was (build 26), written on a Sunday evening and read by
    no one but its writer. It doesn't fade: kept until they delete it or
    their account. One per person per week, the week being the Monday it
    began, in their own time zone."""

    __tablename__ = "weekly_reflections"
    __table_args__ = (UniqueConstraint("owner_id", "week_start", name="uq_reflection_week"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    week_start: Mapped[date] = mapped_column(Date)
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class CirclePrompt(Base):
    """The circle's question of the week (build 26), one of forty, never the
    same twice within forty weeks. Made the first time anyone in the circle
    asks for this week's. The week is Monday to Monday in UTC."""

    __tablename__ = "circle_prompts"
    __table_args__ = (UniqueConstraint("circle_id", "week_start", name="uq_circle_prompt_week"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    circle_id: Mapped[str] = mapped_column(ForeignKey("circles.id"))
    prompt: Mapped[str] = mapped_column(Text)
    week_start: Mapped[date] = mapped_column(Date)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class PromptResponse(Base):
    """One person's answer to their circle's question, sealed until the
    answers open on Saturday and then read by the circle together. One each,
    never edited, and kept as part of the circle's journal until its writer
    deletes their account."""

    __tablename__ = "prompt_responses"
    __table_args__ = (
        UniqueConstraint("prompt_id", "user_id", name="uq_prompt_response_once"),
        Index("ix_prompt_responses_user", "user_id"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    prompt_id: Mapped[str] = mapped_column(ForeignKey("circle_prompts.id"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)


class PersonLetter(Base):
    """A sealed letter from one person in a circle to another, held closed
    until a day the sender chose. Written to the person: it survives either
    of them leaving the circle, and only an account ending takes it. The
    sender gives up their words at the seal — they can take back a letter
    still sealed, but not reread it. The recipient can't refuse one before
    the date, and can delete it only once they've opened it: it's a gift.
    No notification: the sealed envelope in Held is the only signal."""

    __tablename__ = "person_letters"
    __table_args__ = (
        Index("ix_person_letters_recipient", "recipient_id", "deliver_at"),
        Index("ix_person_letters_sender", "sender_id"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    sender_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    recipient_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    body: Mapped[str] = mapped_column(Text)
    # A line in the sender's own words, for the front of the envelope: "Open
    # on graduation day", or nothing. The date alone is shown with no label.
    occasion: Mapped[str | None] = mapped_column(String(120), nullable=True)
    # The day the seal may be broken, in UTC. A letter's day is the same for
    # everyone: no local-time dance, because the two people may be anywhere
    # by the time it opens. The app compares against the phone's own day.
    deliver_at: Mapped[date] = mapped_column(Date)
    opened_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime)
