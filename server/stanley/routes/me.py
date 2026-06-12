from __future__ import annotations

import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import physics
from ..decay import TOMBSTONE, enqueue_purge, scrub
from ..deps import get_clock, get_current_user, get_db, get_settings, get_storage
from ..models import Anchor, Block, Comment, Membership, Photo, Rest, User
from ..serialize import memory_payload, user_brief

router = APIRouter(tags=["me"])


USERNAME_RE = re.compile(r"^[a-z0-9._-]{3,30}$")


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
def me(user: User = Depends(get_current_user)):
    return _profile_payload(user) | {
        "last_light_notice_enabled": user.last_light_notice_enabled,
    }


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
    threads: dict[str | None, dict] = {}
    for anchor, photo in rows:
        anchor.last_viewed_at = now
        key = photo.owner_id or f"tombstone:{photo.owner_hash}"
        if key not in threads:
            threads[key] = {"friend": user_brief(db, photo.owner_id), "memories": []}
        threads[key]["memories"].append(
            memory_payload(db, settings, now, photo, anchor, user)
        )
    return {"threads": list(threads.values())}


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

    user.display_name = None
    user.apple_sub = None
    user.avatar_key = None
    user.deleted_at = now
