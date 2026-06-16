from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import physics
from ..decay import TOMBSTONE, enqueue_purge, scrub
from ..deps import (
    get_circle_photo,
    get_clock,
    get_current_user,
    get_db,
    get_settings,
    get_storage,
    require_membership,
)
from ..images import BadImage, process_upload
from ..models import Anchor, Comment, Photo, User, Warmth, new_id
from ..serialize import photo_payload, user_brief

router = APIRouter(tags=["photos"])


class AnchorBody(BaseModel):
    note: str | None = Field(default=None, max_length=500)


class CommentBody(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


def _parse_claim(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        claim = datetime.fromisoformat(raw)
    except ValueError:
        return None
    return claim if claim.tzinfo is not None else None


@router.post("/photos", status_code=201)
def capture(
    file: UploadFile = File(...),
    tz: str = Form(...),
    caption: str | None = Form(default=None),
    location: str | None = Form(default=None),
    taken_at_claim: str | None = Form(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
    settings=Depends(get_settings),
):
    membership, _ = require_membership(db, user)
    try:
        ZoneInfo(tz)
    except (ZoneInfoNotFoundError, ValueError):
        raise HTTPException(400, {"code": "bad_timezone"})

    # Location is a human-written place label, never device metadata (§9).
    location = (location or "").strip() or None
    if location is not None and len(location) > 120:
        raise HTTPException(400, {"code": "location_too_long"})

    now = clock.now()
    taken_at = physics.reconcile_taken_at(now, _parse_claim(taken_at_claim))

    # The slot check includes soft-deleted and purged rows: capture is a
    # commitment, and deletion does not refund the day (§8.4).
    existing_dates = set(
        db.scalars(select(Photo.local_date).where(Photo.owner_id == user.id)).all()
    )
    last_taken = db.scalar(
        select(func.max(Photo.taken_at)).where(Photo.owner_id == user.id)
    )
    violation = physics.violates_capture_rules(existing_dates, last_taken, taken_at, tz)
    if violation is not None:
        raise HTTPException(409, {"code": violation})

    data = file.file.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(413, {"code": "too_large"})
    try:
        processed = process_upload(data)
    except BadImage:
        raise HTTPException(400, {"code": "bad_image"})

    photo_id = new_id()
    keys = {
        "blob_key": f"{photo_id}/orig.jpg",
        "deriv_key": f"{photo_id}/deriv.jpg",
        "thumb_key": f"{photo_id}/thumb.jpg",
    }
    storage.put(keys["blob_key"], processed.original)
    storage.put(keys["deriv_key"], processed.derivative)
    storage.put(keys["thumb_key"], processed.thumbnail)

    photo = Photo(
        id=photo_id,
        owner_id=user.id,
        circle_id=membership.circle_id,
        taken_at=taken_at,
        taken_tz=tz,
        local_date=physics.local_capture_date(taken_at, tz),
        caption=caption,
        location=location,
        state=physics.LIVE,
        state_deadline=physics.state_deadline(physics.LIVE, taken_at),
        created_at=now,
        **keys,
    )
    db.add(photo)
    user.tz_last_seen = tz
    db.flush()
    return photo_payload(db, settings, now, photo, user)


@router.delete("/photos/{photo_id}", status_code=204)
def delete_photo(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
):
    photo = db.get(Photo, photo_id)
    if photo is None or photo.owner_id != user.id:
        raise HTTPException(404, "not found")
    if photo.state != physics.PURGED:
        # §8.2 deletion override: privacy wins, everywhere, immediately.
        scrub(db, storage, photo, clock.now(), owner_requested=True)


def _require_public(photo: Photo) -> None:
    if photo.state not in physics.PUBLIC_STATES or photo.deleted_at is not None:
        # §8.2: anchorable and commentable through LAST_LIGHT, never after.
        raise HTTPException(410, {"code": "faded"})


@router.post("/photos/{photo_id}/anchor", status_code=201)
def anchor(
    photo_id: str,
    body: AnchorBody,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    photo = get_circle_photo(db, user, photo_id)
    _require_public(photo)
    existing = db.get(Anchor, (photo.id, user.id))
    if existing is not None:
        existing.note = body.note if body.note is not None else existing.note
        return {"anchored": True}
    # Self-anchor uses the identical mechanic — one law for everyone (§8.2).
    db.add(Anchor(photo_id=photo.id, user_id=user.id, created_at=clock.now(), note=body.note))
    return {"anchored": True}


@router.delete("/photos/{photo_id}/anchor", status_code=204)
def unanchor(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    photo = db.get(Photo, photo_id)
    if photo is None:
        raise HTTPException(404, "not found")
    existing = db.get(Anchor, (photo.id, user.id))
    if existing is None:
        return
    db.delete(existing)
    db.flush()
    remaining = db.scalar(
        select(func.count()).select_from(Anchor).where(Anchor.photo_id == photo.id)
    )
    if remaining == 0 and photo.state == physics.EXPIRED:
        # §8.2 retention rule: the last anchor letting go starts the 7-day clock.
        enqueue_purge(db, photo, clock.now() + TOMBSTONE)


@router.get("/photos/{photo_id}/anchors")
def anchor_list(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """The owner's quiet list of who held this. Invariant A2: owner-only; the
    circle never sees who kept a moment, nor how many did — faces, no count."""
    photo = db.get(Photo, photo_id)
    if photo is None:
        raise HTTPException(404, "not found")
    if photo.owner_id != user.id:
        raise HTTPException(403, "owner only")
    now = clock.now()
    rows = db.scalars(
        select(Anchor).where(Anchor.photo_id == photo.id).order_by(Anchor.created_at)
    ).all()
    return {
        "anchors": [
            {
                "user": user_brief(db, a.user_id, settings, now),
                "created_at": a.created_at.isoformat(),
                "note": a.note,
            }
            for a in rows
        ]
    }


@router.post("/photos/{photo_id}/warm", status_code=201)
def warm(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """Warmth — the light, ephemeral gesture (Part 5). Double-tap in the
    client. Possible only while the photo is in Today; it dies when the photo
    leaves. Self-warming is allowed (one law for everyone), idempotent."""
    photo = get_circle_photo(db, user, photo_id)
    _require_public(photo)
    if db.get(Warmth, (photo.id, user.id)) is None:
        db.add(Warmth(photo_id=photo.id, user_id=user.id, created_at=clock.now()))
    return {"warmed": True}


@router.delete("/photos/{photo_id}/warm", status_code=204)
def unwarm(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    existing = db.get(Warmth, (photo_id, user.id))
    if existing is not None:
        db.delete(existing)


@router.get("/photos/{photo_id}/warmth")
def warmth_faces(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Who warmed this — faces, for the owner's eyes only, never a number.
    Mirrors the anchor list: the circle sees nothing, and there is no count
    field anywhere in the response."""
    photo = db.get(Photo, photo_id)
    if photo is None:
        raise HTTPException(404, "not found")
    if photo.owner_id != user.id:
        raise HTTPException(403, "owner only")
    now = clock.now()
    warmers = db.scalars(
        select(Warmth).where(Warmth.photo_id == photo.id).order_by(Warmth.created_at)
    ).all()
    return {
        "faces": [user_brief(db, w.user_id, settings, now) for w in warmers],
    }


@router.post("/photos/{photo_id}/comments", status_code=201)
def add_comment(
    photo_id: str,
    body: CommentBody,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    photo = get_circle_photo(db, user, photo_id)
    _require_public(photo)
    comment = Comment(
        photo_id=photo.id, author_id=user.id, body=body.body, created_at=clock.now()
    )
    db.add(comment)
    db.flush()
    return {
        "id": comment.id,
        "body": comment.body,
        "created_at": comment.created_at.isoformat(),
    }
