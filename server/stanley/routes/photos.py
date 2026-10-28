from __future__ import annotations

import contextlib
import logging
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

CAPTION_MAX = 2000  # I4: cap caption like comments (unbounded TEXT otherwise)

from .. import physics
from ..decay import TOMBSTONE, enqueue_purge, owner_hash_for, scrub
from ..deps import (
    get_circle_photo,
    get_clock,
    get_current_user,
    get_db,
    get_settings,
    get_storage,
    require_membership,
)
from ..images import BadImage, PreparedUpload, prepare_upload
from ..models import Anchor, Comment, Like, Membership, Photo, PhotoTag, User, new_id
from ..serialize import photo_payload, user_brief

log = logging.getLogger("stanley")

router = APIRouter(tags=["photos"])


def _store_original_blob(
    storage, deriv_key: str, blob_key: str, prepared: PreparedUpload
) -> None:
    """Encode + store the full-size original AFTER the response — the heaviest
    JPEG encode must not sit between the shutter and the user's confirmation.
    The photo may have been deleted in the meantime; scrub removes every blob,
    so a missing derivative means don't write (no DB session here, on purpose —
    this runs outside the request's transaction). A delete landing mid-encode
    can still strand one unreferenced file, never signed for and harmless at
    pilot scale."""
    if not storage.exists(deriv_key):
        return
    try:
        storage.put(blob_key, prepared.encode_original())
    except Exception:
        # Deriv + thumb already exist and serve every surface (feed, Held,
        # export). A missing original degrades nothing user-visible.
        log.exception("background original store failed for %s", blob_key)


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
    background: BackgroundTasks,
    file: UploadFile = File(...),
    tz: str = Form(...),
    caption: str | None = Form(default=None),
    location: str | None = Form(default=None),
    tagged: list[str] = Form(default=[]),
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

    # I4: caption is bounded like every other text field.
    if caption is not None and len(caption) > CAPTION_MAX:
        raise HTTPException(422, {"code": "caption_too_long"})

    now = clock.now()
    taken_at = physics.reconcile_taken_at(now, _parse_claim(taken_at_claim))

    # The slot check includes soft-deleted and purged rows: capture is a
    # commitment, and deletion does not refund the day (§8.4). This is the fast
    # path; the UNIQUE(owner_id, local_date) constraint is the race backstop.
    existing_dates = set(
        db.scalars(select(Photo.local_date).where(Photo.owner_id == user.id)).all()
    )
    last_taken = db.scalar(
        select(func.max(Photo.taken_at)).where(Photo.owner_id == user.id)
    )
    # 8.4 redo: a released row keeps its local_date under an owner hash, so the
    # day still knows a redo was spent even though the slot itself is free.
    redos_used = db.scalar(
        select(func.count())
        .select_from(Photo)
        .where(
            Photo.owner_hash == owner_hash_for(user.id),
            Photo.local_date == physics.local_capture_date(taken_at, tz),
        )
    ) or 0
    violation = physics.violates_capture_rules(
        existing_dates, last_taken, taken_at, tz, redos_used
    )
    if violation is not None:
        raise HTTPException(409, {"code": violation})

    # Decode/validate the image BEFORE claiming the slot, so a bad image never
    # burns a day. Only the feed-facing deriv+thumb are encoded here; the
    # full-size original is deferred past the response (see _store_original_blob).
    data = file.file.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(413, {"code": "too_large"})
    try:
        prepared = prepare_upload(data)
    except BadImage:
        raise HTTPException(400, {"code": "bad_image"})

    # I2: claim the slot (flush the row) FIRST. If a concurrent request already
    # took today, the UNIQUE constraint fires here — return 409 with ZERO blobs
    # written, no orphans.
    photo_id = new_id()
    keys = {
        "blob_key": f"{photo_id}/orig.jpg",
        "deriv_key": f"{photo_id}/deriv.jpg",
        "thumb_key": f"{photo_id}/thumb.jpg",
    }
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
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, {"code": "slot_used"})

    # Slot is ours; now upload what the feed needs immediately. If a blob write
    # fails, clean up any partial blobs and let the row roll back (get_db) so
    # the user can retry the day. The original is stored after the response.
    written: list[str] = []
    try:
        for key, blob in (
            (keys["deriv_key"], prepared.derivative),
            (keys["thumb_key"], prepared.thumbnail),
        ):
            storage.put(key, blob)
            written.append(key)
    except Exception:
        for key in written:
            with contextlib.suppress(Exception):
                storage.delete(key)
        raise HTTPException(503, {"code": "upload_failed"})

    background.add_task(
        _store_original_blob, storage, keys["deriv_key"], keys["blob_key"], prepared
    )

    # 'Who was there' (Part 3): tag only real members of this circle, deduped.
    # A bad/non-member id is ignored, not an error.
    wanted = {t for t in tagged if t}
    if wanted:
        members = set(
            db.scalars(
                select(Membership.user_id).where(
                    Membership.circle_id == membership.circle_id,
                    Membership.user_id.in_(wanted),
                )
            ).all()
        )
        for uid in members:
            db.add(PhotoTag(photo_id=photo.id, tagged_user_id=uid, created_at=now))

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
        now = clock.now()
        # 8.4 redo: deleting *today's* photo refunds the slot once. Decided
        # before scrubbing, while the row still belongs to the owner.
        owner_hash = owner_hash_for(user.id)
        redone_today = db.scalar(
            select(func.count())
            .select_from(Photo)
            .where(Photo.owner_hash == owner_hash, Photo.local_date == photo.local_date)
        ) or 0
        is_today = photo.local_date == physics.local_capture_date(now, photo.taken_tz)

        # 8.2 deletion override: privacy wins, everywhere, immediately.
        scrub(db, storage, photo, now, owner_requested=True)

        if is_today and redone_today < physics.REDOS_PER_DAY:
            # Release the row from the owner's (owner_id, local_date) slot so one
            # repost fits. Anchorers keep the tombstone scrub just wrote - it is
            # the same anonymous shape a scheduled purge leaves behind.
            photo.owner_hash = owner_hash
            photo.owner_id = None


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


@router.post("/photos/{photo_id}/like", status_code=201)
def like(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """The like — double-tap in the client (Part 1). Possible only while the
    photo is in Today; it dies when the photo leaves. Self-liking is allowed
    (one law for everyone), idempotent. There is no count, anywhere."""
    photo = get_circle_photo(db, user, photo_id)
    _require_public(photo)
    if db.get(Like, (photo.id, user.id)) is None:
        db.add(Like(photo_id=photo.id, user_id=user.id, created_at=clock.now()))
    return {"liked": True}


@router.delete("/photos/{photo_id}/like", status_code=204)
def unlike(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    existing = db.get(Like, (photo_id, user.id))
    if existing is not None:
        db.delete(existing)


@router.get("/photos/{photo_id}/likes")
def like_faces(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Who liked this — faces, for the owner's eyes only, never a number.
    Mirrors the anchor list: the circle sees nothing, and there is no count
    field anywhere in the response."""
    photo = db.get(Photo, photo_id)
    if photo is None:
        raise HTTPException(404, "not found")
    if photo.owner_id != user.id:
        raise HTTPException(403, "owner only")
    now = clock.now()
    likers = db.scalars(
        select(Like).where(Like.photo_id == photo.id).order_by(Like.created_at)
    ).all()
    return {
        "faces": [user_brief(db, lk.user_id, settings, now) for lk in likers],
    }


@router.delete("/photos/{photo_id}/tags/me", status_code=204)
def untag_me(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Opt out: remove your own 'who was there' tag from someone's photo (Part 3)."""
    existing = db.get(PhotoTag, (photo_id, user.id))
    if existing is not None:
        db.delete(existing)


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
