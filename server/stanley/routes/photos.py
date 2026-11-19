from __future__ import annotations

import contextlib
import logging
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

CAPTION_MAX = 2000  # I4: cap caption like comments (unbounded TEXT otherwise)
# The four capture filters. The client bakes the look into the image; the
# server keeps only the name. There is no fifth, and no intensity.
FILTERS = frozenset({"mono", "grain", "dusk", "clean"})

from .. import journal, physics
from ..decay import TOMBSTONE, enqueue_purge, fade_journal, owner_hash_for, scrub
from ..deps import (
    active_circle_id,
    event,
    get_circle_photo,
    get_clock,
    get_current_user,
    get_db,
    get_notifier,
    get_settings,
    get_storage,
    refuse_objectionable,
    require_membership,
)
from ..images import BadImage, Busy, PreparedUpload, prepare_upload
from ..notifications import send_circle_post_notices
from ..ratelimit import per_person
from ..text import clean_optional
from ..models import Anchor, Comment, Like, Membership, Photo, PhotoImage, PhotoTag, User, new_id
from ..serialize import entry_extras, photo_payload, user_brief
from ..storage import delete_after_commit

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
        # A slot for the encode, waiting longer than a request would: no one
        # is waiting on this. Still busy after that, the original is let go.
        storage.put(blob_key, prepared.encode_original(wait=120))
        # Deleted while the original was encoding: the scrub found no
        # original to delete, so it's deleted here instead of stranded (on
        # R2 a stranded object would stay for good).
        if not storage.exists(deriv_key):
            storage.delete(blob_key)
    except Busy:
        log.warning("event=original_skipped reason=busy key=%s", blob_key)
    except Exception:
        # Deriv + thumb already exist and serve every surface (feed, Held,
        # export). A missing original degrades nothing user-visible.
        log.exception("background original store failed for %s", blob_key)


class AnchorBody(BaseModel):
    note: str | None = Field(default=None, max_length=500)


class CommentBody(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class ScoreBody(BaseModel):
    # Required, and null clears it.
    score: int | None
    # Builds 52 to 64 send none: the zone the post itself just gave is
    # theirs (`tz_last_seen`).
    tz: str | None = Field(default=None, max_length=64)


def valid_timezone(tz: str | None) -> bool:
    """An IANA zone this server knows ("America/New_York"). Everything that
    stores a zone checks it first: one bad zone kept as `tz_last_seen` would
    make every pass that reads it (the evening digest, the note's end of
    day, the weekly mosaic) fail for that person."""
    if not tz or len(tz) > 64:
        return False
    try:
        ZoneInfo(tz)
    except (ZoneInfoNotFoundError, ValueError):
        return False
    return True


def _parse_claim(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        claim = datetime.fromisoformat(raw)
    except ValueError:
        return None
    return claim if claim.tzinfo is not None else None


@router.post("/photos", status_code=201, dependencies=[per_person("upload")])
def capture(
    background: BackgroundTasks,
    file: UploadFile = File(...),
    tz: str = Form(...),
    caption: str | None = Form(default=None),
    location: str | None = Form(default=None),
    tagged: list[str] = Form(default=[]),
    taken_at_claim: str | None = Form(default=None),
    filter_name: str | None = Form(default=None, alias="filter"),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
    settings=Depends(get_settings),
    notifier=Depends(get_notifier),
    circle_id: str | None = Depends(active_circle_id),
):
    # The circle on screen when the shutter closed. A circle the person has
    # since left is refused (not_in_circle) rather than posted somewhere else.
    membership, _ = require_membership(db, user, circle_id)
    if not valid_timezone(tz):
        raise HTTPException(400, {"code": "bad_timezone"})

    # Location is a human-written place label, never device metadata (§9).
    location = clean_optional(location)
    if location is not None and len(location) > 120:
        raise HTTPException(400, {"code": "location_too_long"})

    # I4: caption is bounded like every other text field.
    caption = clean_optional(caption, multiline=True)
    if caption is not None and len(caption) > CAPTION_MAX:
        raise HTTPException(422, {"code": "caption_too_long"})
    # Refused before the slot is claimed, so the words cost nobody the day.
    refuse_objectionable(caption, location)

    # A label for a look that's already in the pixels. An unknown name is
    # dropped, not refused: a label must never cost someone their day.
    filter_name = (filter_name or "").strip().lower()
    filter_name = filter_name if filter_name in FILTERS else None

    now = clock.now()
    taken_at = physics.reconcile_taken_at(now, _parse_claim(taken_at_claim))

    # The slot check includes soft-deleted and purged rows: capture is a
    # commitment, and deletion does not refund the day (§8.4). This is the fast
    # path; the UNIQUE(owner_id, circle_id, local_date) constraint is the race
    # backstop. Every part of the law is this circle's: a photo posted to
    # another circle today neither spends this one's day nor starts its gap.
    in_this_circle = (Photo.owner_id == user.id, Photo.circle_id == membership.circle_id)
    existing_dates = set(db.scalars(select(Photo.local_date).where(*in_this_circle)).all())
    last_taken = db.scalar(select(func.max(Photo.taken_at)).where(*in_this_circle))
    # 8.4 redo: a released row keeps its local_date under an owner hash, so the
    # day still knows a redo was spent even though the slot itself is free.
    redos_used = db.scalar(
        select(func.count())
        .select_from(Photo)
        .where(
            Photo.owner_hash == owner_hash_for(user.id),
            Photo.circle_id == membership.circle_id,
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
    except Busy:
        # Item 13: two photos are already being worked on. Nothing is
        # claimed yet, so the day is untouched and the phone can send again.
        raise HTTPException(503, {"code": "busy"})

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
        filter=filter_name,
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
    # A bad/non-member id is ignored, not an error. No circle has more than
    # its cap in it, so a longer list is cut there, before it reaches SQL.
    wanted = {t for t in tagged[: physics.CIRCLE_CAP] if t and len(t) <= 64}
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
    event("photo_posted", photo=photo.id, circle=membership.circle_id, user=user.id)
    # §10 N5 (build 37): "{name} shared a moment" to whoever in this circle
    # asked for it. Logged with the photo, so a post that rolls back tells
    # nobody, and handed to Apple after the response, so posting never waits
    # on a push. Today's retake isn't news twice.
    send_circle_post_notices(
        db, notifier, photo, user, now, later=background, retake=redos_used > 0
    )
    return photo_payload(db, settings, now, photo, user)


@router.delete("/photos/{photo_id}", status_code=204)
def delete_photo(
    photo_id: str,
    db: Session = Depends(get_db, scope="function"),
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
            .where(
                Photo.owner_hash == owner_hash,
                Photo.circle_id == photo.circle_id,
                Photo.local_date == photo.local_date,
            )
        ) or 0
        is_today = photo.local_date == physics.local_capture_date(now, photo.taken_tz)

        # 8.2 deletion override: privacy wins, everywhere, immediately.
        scrub(db, storage, photo, now, owner_requested=True)
        event("photo_deleted", photo=photo.id, user=user.id)

        if is_today and redone_today < physics.REDOS_PER_DAY:
            # Release the row from the owner's (owner_id, circle_id,
            # local_date) slot so one repost fits. Anchorers keep the tombstone
            # scrub just wrote - it is the same anonymous shape a scheduled
            # purge leaves behind.
            photo.owner_hash = owner_hash
            photo.owner_id = None


# --- The day's entry (build 81) ----------------------------------------------
# A person's day in a circle is one entry of up to three photos. The first is
# the entry's own row (`Photo`), so everything about the entry (its decay,
# its keeps, its hearts, its stories, the day's slot and redo, the Circle
# Posts notice) stays on that row. The others are `PhotoImage` rows, added or
# taken out only while the entry's day is still the owner's own.


def _own_editable_entry(db: Session, user: User, photo_id: str, tz: str, now: datetime) -> Photo:
    """The caller's own entry, still standing, on their today; or the refusal."""
    photo = db.get(Photo, photo_id)
    if (
        photo is None
        or photo.owner_id is None
        or photo.owner_id != user.id
        or photo.deleted_at is not None
        or photo.state == physics.PURGED
        or not photo.deriv_key
    ):
        raise HTTPException(404, "not found")
    if not valid_timezone(tz):
        raise HTTPException(400, {"code": "bad_timezone"})
    # The person's own day, by the zone the phone sends now: after it ends
    # the entry is fixed for good.
    if physics.local_capture_date(now, tz) != photo.local_date:
        raise HTTPException(409, {"code": "day_over"})
    return photo


@router.post("/photos/{photo_id}/images", status_code=201, dependencies=[per_person("upload")])
def add_image(
    photo_id: str,
    background: BackgroundTasks,
    file: UploadFile = File(...),
    tz: str = Form(...),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
    settings=Depends(get_settings),
):
    """Another photo in today's entry (build 81), up to three in all. No
    notice goes to anyone (the entry already told the circle, if it asked),
    and there are no words to filter."""
    now = clock.now()
    photo = _own_editable_entry(db, user, photo_id, tz, now)
    extras = entry_extras(db, photo.id)
    if 1 + len(extras) >= physics.PHOTOS_PER_ENTRY:
        raise HTTPException(409, {"code": "entry_full"})

    data = file.file.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(413, {"code": "too_large"})
    try:
        prepared = prepare_upload(data)
    except BadImage:
        raise HTTPException(400, {"code": "bad_image"})
    except Busy:
        raise HTTPException(503, {"code": "busy"})

    image_id = new_id()
    keys = {
        "blob_key": f"{photo.id}/{image_id}/orig.jpg",
        "deriv_key": f"{photo.id}/{image_id}/deriv.jpg",
        "thumb_key": f"{photo.id}/{image_id}/thumb.jpg",
    }
    # Claim the place first: the flush takes SQLite's write lock, so the
    # entry and its photos are read again with no other add or delete
    # between that read and this commit. An entry deleted meanwhile, or
    # filled by an add from another phone, refuses this one (the row rolls
    # back with the request) before a single file is written.
    db.add(PhotoImage(
        id=image_id,
        photo_id=photo.id,
        position=max([e.position for e in extras], default=0) + 1,
        created_at=now,
        **keys,
    ))
    db.flush()
    db.refresh(photo)
    if photo.owner_id != user.id or photo.deleted_at is not None or not photo.deriv_key:
        raise HTTPException(404, "not found")
    now_extras = entry_extras(db, photo.id)
    if 1 + len(now_extras) > physics.PHOTOS_PER_ENTRY:
        raise HTTPException(409, {"code": "entry_full"})
    for position, extra in enumerate(now_extras, start=1):
        extra.position = position
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

    user.tz_last_seen = tz
    db.flush()
    background.add_task(
        _store_original_blob, storage, keys["deriv_key"], keys["blob_key"], prepared
    )
    event("entry_photo_added", photo=photo.id, user=user.id)
    return photo_payload(db, settings, now, photo, user)


@router.delete("/photos/{photo_id}/images/{image_id}")
def remove_image(
    photo_id: str,
    image_id: str,
    tz: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    storage=Depends(get_storage),
    settings=Depends(get_settings),
):
    """Take one photo out of today's entry (build 81). The entry itself stays
    (its keeps, hearts and stories with it), and so does the day's redo: to
    take the whole day back, delete the entry. Its only photo can't be taken
    out this way (409 `last_photo`)."""
    now = clock.now()
    photo = _own_editable_entry(db, user, photo_id, tz, now)
    extras = entry_extras(db, photo.id)
    if image_id == photo.id:
        if not extras:
            raise HTTPException(409, {"code": "last_photo"})
        # The first photo goes: the next one becomes the entry's own.
        first = extras.pop(0)
        for key in (photo.blob_key, photo.deriv_key, photo.thumb_key):
            delete_after_commit(db, storage, key)
        photo.blob_key, photo.deriv_key, photo.thumb_key = first.blob_key, first.deriv_key, first.thumb_key
        db.delete(first)
    else:
        gone = next((e for e in extras if e.id == image_id), None)
        if gone is None:
            raise HTTPException(404, "not found")
        extras.remove(gone)
        for key in (gone.blob_key, gone.deriv_key, gone.thumb_key):
            delete_after_commit(db, storage, key)
        db.delete(gone)
    for position, extra in enumerate(extras, start=1):
        extra.position = position
    user.tz_last_seen = tz
    db.flush()
    event("entry_photo_removed", photo=photo.id, user=user.id)
    return photo_payload(db, settings, now, photo, user)


@router.put("/photos/{photo_id}/score", dependencies=[per_person("journal")])
def set_score(
    photo_id: str,
    body: ScoreBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """The mark you leave on your day after posting its photo (build 52),
    from builds 52 to 64; build 65 marks the day itself (`PUT
    /moods/{day}`). One of five, or null to take it back. It's the day's
    mark, kept in `day_moods` and nowhere else, so it's taken only while
    the photo's day is the owner's today: a photo from a day gone by can't
    fill that day in (400 `not_today`). Anyone else's photo, or one
    deleted or purged, reads as not found. Nothing is told to anyone."""
    photo = db.get(Photo, photo_id)
    if (
        photo is None
        or photo.owner_id is None
        or photo.owner_id != user.id
        or photo.deleted_at is not None
        or photo.state == physics.PURGED
    ):
        raise HTTPException(404, "not found")
    if body.tz is not None and not valid_timezone(body.tz):
        raise HTTPException(400, {"code": "bad_timezone"})
    score = body.score
    if score is not None and not (physics.SCORE_MIN <= score <= physics.SCORE_MAX):
        raise HTTPException(400, {"code": "bad_score"})
    now = clock.now()
    if photo.local_date != journal.local_day(now, body.tz or user.tz_last_seen or "UTC"):
        raise HTTPException(400, {"code": "not_today"})
    from .moods import set_mark

    set_mark(db, user, photo.local_date, score, now)
    return {"score": score}


def _require_public(photo: Photo) -> None:
    if photo.state not in physics.PUBLIC_STATES or photo.deleted_at is not None:
        # §8.2: anchorable and commentable through LAST_LIGHT, never after.
        raise HTTPException(410, {"code": "faded"})


@router.post("/photos/{photo_id}/anchor", status_code=201)
def anchor(
    photo_id: str,
    body: AnchorBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    photo = get_circle_photo(db, user, photo_id)
    _require_public(photo)
    # A hold note is read only by the person who wrote it: cleaned, never
    # filtered.
    note = clean_optional(body.note, multiline=True)
    # Self-anchor uses the identical mechanic — one law for everyone (§8.2).
    # One statement, so two holds at once (a double tap, a retry) can't both
    # insert and turn the second into a 500: holding a held photo keeps it
    # held, and replaces the note only when one is sent.
    hold = sqlite_insert(Anchor).values(
        photo_id=photo.id, user_id=user.id, created_at=clock.now(), note=note
    )
    if body.note is not None:
        hold = hold.on_conflict_do_update(index_elements=["photo_id", "user_id"], set_={"note": note})
    else:
        hold = hold.on_conflict_do_nothing(index_elements=["photo_id", "user_id"])
    db.execute(hold)
    return {"anchored": True}


@router.delete("/photos/{photo_id}/anchor", status_code=204)
def unanchor(
    photo_id: str,
    db: Session = Depends(get_db, scope="function"),
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
    if photo.state == physics.EXPIRED and photo.owner_id == user.id:
        # Your own faded photo, let go of: your journal entry was kept by
        # that hold, and goes with it (build 26).
        fade_journal(db, photo)


@router.get("/photos/{photo_id}/anchors")
def anchor_list(
    photo_id: str,
    db: Session = Depends(get_db, scope="function"),
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
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """The like — double-tap in the client (Part 1). Possible only while the
    photo is in Today; it dies when the photo leaves. Self-liking is allowed
    (one law for everyone), idempotent. There is no count, anywhere."""
    photo = get_circle_photo(db, user, photo_id)
    _require_public(photo)
    # Atomic, like the hold: a double-tap sent twice is one like, never a 500.
    db.execute(
        sqlite_insert(Like)
        .values(photo_id=photo.id, user_id=user.id, created_at=clock.now())
        .on_conflict_do_nothing(index_elements=["photo_id", "user_id"])
    )
    return {"liked": True}


@router.delete("/photos/{photo_id}/like", status_code=204)
def unlike(
    photo_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    existing = db.get(Like, (photo_id, user.id))
    if existing is not None:
        db.delete(existing)


@router.get("/photos/{photo_id}/likes")
def like_faces(
    photo_id: str,
    db: Session = Depends(get_db, scope="function"),
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
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Opt out: remove your own 'who was there' tag from someone's photo (Part 3)."""
    existing = db.get(PhotoTag, (photo_id, user.id))
    if existing is not None:
        db.delete(existing)


@router.post("/photos/{photo_id}/comments", status_code=201, dependencies=[per_person("story")])
def add_comment(
    photo_id: str,
    body: CommentBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    photo = get_circle_photo(db, user, photo_id)
    _require_public(photo)
    words = clean_optional(body.body, multiline=True)
    if words is None:
        # Spaces aren't a story.
        raise HTTPException(400, {"code": "empty_story"})
    refuse_objectionable(words)
    comment = Comment(
        photo_id=photo.id, author_id=user.id, body=words, created_at=clock.now()
    )
    db.add(comment)
    db.flush()
    return {
        "id": comment.id,
        "body": comment.body,
        "created_at": comment.created_at.isoformat(),
    }
