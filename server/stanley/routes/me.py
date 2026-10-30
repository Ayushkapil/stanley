from __future__ import annotations

import io
import json
import re
import zipfile
from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from .. import physics
from ..decay import TOMBSTONE, enqueue_purge, scrub
from ..deps import get_clock, get_current_user, get_db, get_settings, get_storage
from ..images import BadImage, process_avatar
from ..milestones import milestone_payload, surface_due
from ..models import Anchor, Block, Comment, Like, Membership, Milestone, Photo, PhotoTag, Rest, User
from ..serialize import avatar_url, blocked_ids, iso, memory_payload, user_brief

router = APIRouter(tags=["me"])


# Usernames: 3-30 chars of lowercase letters, digits, "." and "_" only, and
# never starting with a digit. No hyphens; nothing else.
USERNAME_RE = re.compile(r"^(?![0-9])[a-z0-9._]{3,30}$")


class SettingsPatch(BaseModel):
    last_light_notice_enabled: bool | None = None


class ProfilePatch(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=80)
    username: str | None = None
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
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    now = clock.now()
    return _profile_payload(user) | {
        "avatar_url": avatar_url(settings, user.avatar_key, now),
        # join date for "About your account" — nothing else lives there.
        "created_at": iso(user.created_at),
        "last_light_notice_enabled": user.last_light_notice_enabled,
    }


@router.post("/me/avatar")
def upload_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
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
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if body.display_name is not None:
        name = body.display_name.strip()
        if not name:
            raise HTTPException(400, {"code": "bad_display_name"})
        user.display_name = name
    if body.username is not None:
        username = body.username.strip().lower()
        if not USERNAME_RE.match(username):
            raise HTTPException(400, {"code": "bad_username"})
        taken = db.scalars(
            select(User).where(User.username == username, User.id != user.id)
        ).first()
        if taken is not None:
            raise HTTPException(409, {"code": "username_taken"})
        user.username = username
    if body.bio is not None:
        user.bio = body.bio  # newlines preserved verbatim
    return _profile_payload(user)


@router.get("/me/username_check")
def username_check(
    u: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Real-time availability for the edit-profile sheet. Mirrors the PATCH
    validation exactly (same regex, same taken-check) so the answer here is
    the answer there. Your own current username reads as available."""
    candidate = u.strip().lower()
    if not USERNAME_RE.match(candidate):
        return {"valid": False, "available": False}
    taken = db.scalars(
        select(User).where(User.username == candidate, User.id != user.id)
    ).first()
    return {"valid": True, "available": taken is None}


@router.patch("/me/settings")
def patch_settings(
    body: SettingsPatch,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if body.last_light_notice_enabled is not None:
        user.last_light_notice_enabled = body.last_light_notice_enabled
    return {"last_light_notice_enabled": user.last_light_notice_enabled}


@router.get("/me/anchored")
def my_memories(
    db: Session = Depends(get_db),
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
            threads[key] = {"friend": user_brief(db, photo.owner_id), "memories": []}
        threads[key]["memories"].append(
            memory_payload(db, settings, now, photo, anchor, user)
        )
    return {"threads": list(threads.values())}


@router.get("/me/milestones")
def my_milestones(
    db: Session = Depends(get_db),
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
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Dismissed milestones don't reappear (Part 4)."""
    m = db.get(Milestone, milestone_id)
    if m is not None and m.user_id == user.id:
        m.dismissed = True


@router.get("/me/export")
def export_memories(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
):
    """Bundle the user's Held photos + captions into a zip (§15 data export).
    Held only — there is no 'all my posts' archive. Tombstones appear in the
    manifest as an honest note, with no image."""
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
            if photo.state != physics.PURGED and photo.deriv_key and storage.exists(photo.deriv_key):
                name = f"held/{i:03d}_{photo.taken_at.date().isoformat()}.jpg"
                zf.writestr(name, storage.get(photo.deriv_key))
                entry["image"] = name
            else:
                entry["image"] = None
                entry["tombstone"] = True
            manifest["held"].append(entry)
        zf.writestr("memories.json", json.dumps(manifest, indent=2))

    return Response(
        content=buf.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": 'attachment; filename="stanley-memories.zip"'},
    )


@router.delete("/me", status_code=204)
def delete_account(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
):
    """§15: account deletion cascades, including anchored copies of my photos
    (tombstones excepted). My own gestures on others' content are withdrawn."""
    now = clock.now()

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

    for comment in db.scalars(select(Comment).where(Comment.author_id == user.id)).all():
        db.delete(comment)
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

    if user.avatar_key:
        storage.delete(user.avatar_key)
    user.display_name = None
    user.apple_sub = None
    user.avatar_key = None
    user.deleted_at = now
