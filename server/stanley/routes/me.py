from __future__ import annotations

import io
import json
import re
import zipfile
from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, Query, Response, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from .. import notifications, physics, wordfilter
from ..decay import TOMBSTONE, delete_comments, enqueue_purge, owner_hash_for, scrub
from ..deps import event, get_clock, get_current_user, get_db, get_settings, get_storage, refuse_objectionable
from ..images import BadImage, process_avatar
from ..ratelimit import per_person
from ..text import clean
from ..milestones import milestone_payload, surface_due
from ..models import (
    Anchor, Block, CircleNote, CirclePrompt, Comment, JournalEntry, Like, Membership, Milestone,
    NotificationLog, Photo, PhotoTag, PromptResponse, PushToken, Rest, ReturnedLog, User, WeeklyReflection,
)
from ..serialize import avatar_url, blocked_ids, circle_name, iso, journal_body, memory_payload, user_brief
from .journal import delete_answers

router = APIRouter(tags=["me"])


# Usernames: 3-30 chars of lowercase letters, digits, "." and "_" only, and
# never starting with a digit. No hyphens; nothing else.
USERNAME_RE = re.compile(r"^(?![0-9])[a-z0-9._]{3,30}$")


class SettingsPatch(BaseModel):
    last_light_notice_enabled: bool | None = None
    digest_enabled: bool | None = None
    circle_posts_enabled: bool | None = None
    # Build 39: the two reminders, and the hour of the day each is set for.
    note_reminder_enabled: bool | None = None
    note_reminder_hour: int | None = None
    photo_reminder_enabled: bool | None = None
    photo_reminder_hour: int | None = None


def _notice_settings(user: User) -> dict:
    return {
        "last_light_notice_enabled": user.last_light_notice_enabled,
        "digest_enabled": user.digest_enabled,
        "circle_posts_enabled": user.circle_posts_enabled,
        "note_reminder_enabled": user.note_reminder_enabled,
        "note_reminder_hour": user.note_reminder_hour,
        "photo_reminder_enabled": user.photo_reminder_enabled,
        "photo_reminder_hour": user.photo_reminder_hour,
    }


# An APNs device token: hex, 32 bytes today. Room for Apple to lengthen it.
PUSH_TOKEN_RE = re.compile(r"^[0-9a-f]{64,200}$")


class PushTokenBody(BaseModel):
    token: str = Field(max_length=300)
    environment: str = Field(default="production", max_length=16)


class ProfilePatch(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=80)
    username: str | None = Field(default=None, max_length=64)
    # A real bio: multi-line free text, room to write about yourself.
    bio: str | None = Field(default=None, max_length=1000)


def _profile_payload(user: User) -> dict:
    # Identity only — no counts of any kind exist on a profile.
    return {
        "id": user.id,
        "display_name": user.display_name,
        "username": user.username,
        "bio": user.bio,
    }


@router.get("/me")
def me(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    now = clock.now()
    return _profile_payload(user) | {
        "avatar_url": avatar_url(settings, user.avatar_key, now),
        # join date for "About your account" — nothing else lives there.
        "created_at": iso(user.created_at),
        "moments_shared": moments_shared(db, user.id),
    } | _notice_settings(user)


def moments_shared(db: Session, user_id: str) -> int:
    """How many moments this person has shared, ever (build 19): faded and
    purged ones too, not the ones they deleted. Theirs alone, for the quiet
    line on their own You tab. It is only ever on `/me`: never on a member
    profile, a photo or any surface someone else sees, so it can't become a
    score. A purged photo keeps its owner only as a hash (decay §13), and so
    does a released redo, which `deleted_at` leaves out."""
    return db.scalar(
        select(func.count())
        .select_from(Photo)
        .where(
            (Photo.owner_id == user_id) | (Photo.owner_hash == owner_hash_for(user_id)),
            Photo.deleted_at.is_(None),
        )
    ) or 0


@router.post("/me/avatar", dependencies=[per_person("avatar")])
def upload_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
    storage=Depends(get_storage),
):
    """Avatar is identity, not content: a soft square, never decays, EXIF
    dropped entirely. The client crops; the server guarantees the square."""
    data = file.file.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(413, {"code": "too_large"})
    try:
        jpeg = process_avatar(data)
    except BadImage:
        raise HTTPException(400, {"code": "bad_image"})
    key = f"avatars/{user.id}.jpg"
    storage.put(key, jpeg)
    user.avatar_key = key
    return {"avatar_url": avatar_url(settings, key, clock.now())}


@router.patch("/me/profile")
def patch_profile(
    body: ProfilePatch,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    if body.display_name is not None:
        name = clean(body.display_name)
        if not name:
            raise HTTPException(400, {"code": "bad_display_name"})
        refuse_objectionable(name)
        user.display_name = name
    if body.username is not None:
        username = clean(body.username).lower()
        if not USERNAME_RE.match(username):
            raise HTTPException(400, {"code": "bad_username"})
        refuse_objectionable(username)
        taken = db.scalars(
            select(User).where(User.username == username, User.id != user.id)
        ).first()
        if taken is not None:
            raise HTTPException(409, {"code": "username_taken"})
        user.username = username
    if body.bio is not None:
        bio = clean(body.bio, multiline=True)  # newlines kept
        refuse_objectionable(bio)
        user.bio = bio
    return _profile_payload(user)


@router.get("/me/username_check")
def username_check(
    u: str = Query(max_length=64),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Real-time availability for the edit-profile sheet. Mirrors the PATCH
    validation exactly (same regex, same taken-check) so the answer here is
    the answer there. Your own current username reads as available."""
    candidate = clean(u).lower()
    if not USERNAME_RE.match(candidate) or wordfilter.is_objectionable(candidate):
        return {"valid": False, "available": False}
    taken = db.scalars(
        select(User).where(User.username == candidate, User.id != user.id)
    ).first()
    return {"valid": True, "available": taken is None}


@router.patch("/me/settings")
def patch_settings(
    body: SettingsPatch,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    if body.last_light_notice_enabled is not None:
        user.last_light_notice_enabled = body.last_light_notice_enabled
    if body.digest_enabled is not None:
        user.digest_enabled = body.digest_enabled
    if body.circle_posts_enabled is not None:
        user.circle_posts_enabled = body.circle_posts_enabled
    # A reminder's hour is one of the four on offer, nothing in between.
    for hour in (body.note_reminder_hour, body.photo_reminder_hour):
        if hour is not None and hour not in notifications.REMINDER_HOURS:
            raise HTTPException(400, {"code": "bad_reminder_hour"})
    if body.note_reminder_enabled is not None:
        user.note_reminder_enabled = body.note_reminder_enabled
    if body.note_reminder_hour is not None:
        user.note_reminder_hour = body.note_reminder_hour
    if body.photo_reminder_enabled is not None:
        user.photo_reminder_enabled = body.photo_reminder_enabled
    if body.photo_reminder_hour is not None:
        user.photo_reminder_hour = body.photo_reminder_hour
    return _notice_settings(user)


def _push_token(body: PushTokenBody) -> str:
    token = body.token.strip().lower()
    if not PUSH_TOKEN_RE.match(token) or body.environment not in ("production", "sandbox"):
        raise HTTPException(400, {"code": "bad_push_token"})
    return token


@router.post("/me/push-token", status_code=204)
def register_push_token(
    body: PushTokenBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """This phone can be reached, for whichever notices this person has turned
    on. A token belongs to one account at a time: when someone else signs in
    on the phone, it becomes theirs, so a notice never reaches a phone its
    owner has signed out of."""
    token = _push_token(body)
    now = clock.now()
    # One statement: two launches registering the same token at once can't
    # collide.
    db.execute(
        sqlite_insert(PushToken)
        .values(token=token, user_id=user.id, environment=body.environment, updated_at=now)
        .on_conflict_do_update(
            index_elements=["token"],
            set_={"user_id": user.id, "environment": body.environment, "updated_at": now},
        )
    )


@router.delete("/me/push-token", status_code=204)
def remove_push_token(
    body: PushTokenBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Signing out on a phone: nothing more reaches it for this account."""
    row = db.get(PushToken, _push_token(body))
    if row is not None and row.user_id == user.id:
        db.delete(row)


@router.get("/me/anchored")
def my_memories(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Memory threads, grouped per friend (§12). Browsing the archive counts
    as viewing for the near-forgotten heuristic."""
    now = clock.now()
    rows = db.execute(
        select(Anchor, Photo)
        .join(Photo, Photo.id == Anchor.photo_id)
        .where(Anchor.user_id == user.id)
        .order_by(Photo.taken_at)
    ).all()
    # A block hides content in both directions, and the archive is no
    # exception: while it stands, that person's photos are not shown back to
    # you. Nothing is deleted — unblocking restores the thread intact.
    hidden = blocked_ids(db, user.id)
    threads: dict[str | None, dict] = {}
    for anchor, photo in rows:
        if photo.owner_id is not None and photo.owner_id in hidden:
            continue
        anchor.last_viewed_at = now
        key = photo.owner_id or f"tombstone:{photo.owner_hash}"
        if key not in threads:
            # With a signed link to their face: the album heads each friend's
            # page with it (it was left unsigned, so Held only ever showed
            # initials).
            threads[key] = {"friend": user_brief(db, photo.owner_id, settings, now), "memories": []}
        threads[key]["memories"].append(
            memory_payload(db, settings, now, photo, anchor, user)
        )
    return {"threads": list(threads.values())}


@router.get("/me/milestones")
def my_milestones(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Private milestones (Part 4). Surfaces at most one new one per week on
    fetch, then returns all undismissed ones. No counts framed as scores."""
    surface_due(db, clock, user)
    now = clock.now()
    rows = db.scalars(
        select(Milestone)
        .where(Milestone.user_id == user.id, Milestone.dismissed.is_(False))
        .order_by(Milestone.created_at.desc())
    ).all()
    return {"milestones": [milestone_payload(db, settings, now, user, m) for m in rows]}


@router.delete("/me/milestones/{milestone_id}", status_code=204)
def dismiss_milestone(
    milestone_id: int,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Dismissed milestones don't reappear (Part 4)."""
    m = db.get(Milestone, milestone_id)
    if m is not None and m.user_id == user.id:
        m.dismissed = True


@router.get("/me/export")
def export_memories(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
):
    """Bundle the user's Held photos + captions into a zip (§15 data export).
    Held only — there is no 'all my posts' archive. Tombstones appear in the
    manifest as an honest note, with no image. With them, what the person
    wrote down for themselves (build 26): journal entries on their own held
    photos, their reflections, and their answers to their circles' questions."""
    now = clock.now()
    rows = db.execute(
        select(Anchor, Photo)
        .join(Photo, Photo.id == Anchor.photo_id)
        .where(Anchor.user_id == user.id)
        .order_by(Photo.taken_at)
    ).all()

    manifest = {
        "exported_at": iso(now),
        "display_name": user.display_name,
        "held": [],
    }
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for i, (anchor, photo) in enumerate(rows, start=1):
            entry = {
                "date": photo.taken_at.date().isoformat(),
                "caption": photo.caption,
                "location": photo.location,
                "filter": photo.filter,
                "note": anchor.note,
                "from": user_brief(db, photo.owner_id)["display_name"],
            }
            # Your own held photo: the journal entry you wrote on it.
            journal = journal_body(db, photo, user)
            if journal is not None:
                entry["journal"] = journal
            if photo.state != physics.PURGED and photo.deriv_key and storage.exists(photo.deriv_key):
                name = f"held/{i:03d}_{photo.taken_at.date().isoformat()}.jpg"
                zf.writestr(name, storage.get(photo.deriv_key))
                entry["image"] = name
            else:
                entry["image"] = None
                entry["tombstone"] = True
            manifest["held"].append(entry)
        # Build 26: your reflections, every week of them, and your answers
        # to your circles' questions. Nobody else's answers: those are theirs.
        manifest["reflections"] = [
            {"week_start": r.week_start.isoformat(), "reflection": r.body}
            for r in db.scalars(
                select(WeeklyReflection)
                .where(WeeklyReflection.owner_id == user.id)
                .order_by(WeeklyReflection.week_start)
            ).all()
        ]
        manifest["answers"] = [
            {
                "week_start": prompt.week_start.isoformat(),
                "circle": circle_name(db, prompt.circle_id),
                "question": prompt.prompt,
                "answer": row.body,
            }
            for row, prompt in db.execute(
                select(PromptResponse, CirclePrompt)
                .join(CirclePrompt, CirclePrompt.id == PromptResponse.prompt_id)
                .where(PromptResponse.user_id == user.id)
                .order_by(CirclePrompt.week_start)
            ).all()
        ]
        zf.writestr("memories.json", json.dumps(manifest, indent=2))

    return Response(
        content=buf.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": 'attachment; filename="stanley-memories.zip"'},
    )


@router.delete("/me", status_code=204)
def delete_account(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
):
    """§15: account deletion cascades, including anchored copies of my photos
    (tombstones excepted). My own gestures on others' content are withdrawn."""
    now = clock.now()
    event("account_deleted", user=user.id)

    for photo in db.scalars(select(Photo).where(Photo.owner_id == user.id)).all():
        if photo.state != physics.PURGED:
            scrub(db, storage, photo, now, owner_requested=True)

    for anchor in db.scalars(select(Anchor).where(Anchor.user_id == user.id)).all():
        photo = db.get(Photo, anchor.photo_id)
        db.delete(anchor)
        db.flush()
        if photo is not None and photo.state == physics.EXPIRED:
            remaining = db.scalar(
                select(func.count()).select_from(Anchor).where(Anchor.photo_id == photo.id)
            )
            if remaining == 0:
                enqueue_purge(db, photo, now + TOMBSTONE)

    delete_comments(db, db.scalars(select(Comment).where(Comment.author_id == user.id)).all())
    # Likes the user gave on others' photos are withdrawn — their face must not
    # linger on anyone's owner-view once they're gone (it's ephemeral anyway).
    db.execute(delete(Like).where(Like.user_id == user.id))
    # Their 'who was there' tags on others' photos go too, and their milestones.
    db.execute(delete(PhotoTag).where(PhotoTag.tagged_user_id == user.id))
    db.execute(delete(Milestone).where(Milestone.user_id == user.id))
    for rest in db.scalars(select(Rest).where(Rest.user_id == user.id)).all():
        db.delete(rest)
    for block in db.scalars(
        select(Block).where((Block.blocker_id == user.id) | (Block.blocked_id == user.id))
    ).all():
        db.delete(block)
    for membership in db.scalars(
        select(Membership).where(Membership.user_id == user.id)
    ).all():
        db.delete(membership)
    # Nothing reaches their phones again.
    db.execute(delete(PushToken).where(PushToken.user_id == user.id))
    # The note they left, what Stanley sent them and what it handed back.
    db.execute(delete(CircleNote).where(CircleNote.author_id == user.id))
    db.execute(delete(NotificationLog).where(NotificationLog.user_id == user.id))
    db.execute(delete(ReturnedLog).where(ReturnedLog.user_id == user.id))
    # What they wrote down (build 26): their reflections, their answers to
    # their circles' questions, and any journal entry their photos' scrub
    # above didn't already take.
    db.execute(delete(WeeklyReflection).where(WeeklyReflection.owner_id == user.id))
    db.execute(delete(JournalEntry).where(JournalEntry.owner_id == user.id))
    delete_answers(db, db.scalars(select(PromptResponse).where(PromptResponse.user_id == user.id)).all())

    if user.avatar_key:
        storage.delete(user.avatar_key)
    # What's left is a bare row for tombstones and reports to point at:
    # nothing that says who it was (the Privacy Policy, build 18).
    user.display_name = None
    user.username = None
    user.bio = None
    user.apple_sub = None
    user.avatar_key = None
    user.tz_last_seen = None
    user.last_light_notice_enabled = False
    user.digest_enabled = False
    user.circle_posts_enabled = False
    user.note_reminder_enabled = False
    user.photo_reminder_enabled = False
    user.deleted_at = now
