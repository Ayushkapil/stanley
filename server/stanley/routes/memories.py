from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import physics
from ..deps import get_clock, get_current_user, get_db, get_settings
from ..models import Anchor, Photo, Rest, User
from ..serialize import blocked_ids, memory_payload, photo_payload

router = APIRouter(tags=["memories"])


def _related_photo(db: Session, user: User, photo_id: str) -> Photo:
    photo = db.get(Photo, photo_id)
    if photo is None:
        raise HTTPException(404, "not found")
    is_mine = photo.owner_id == user.id
    is_anchored = db.get(Anchor, (photo.id, user.id)) is not None
    if not (is_mine or is_anchored):
        raise HTTPException(404, "not found")
    return photo


@router.post("/memories/{photo_id}/rest", status_code=201)
def rest(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """§14: one tap, never resurfaces again, stays in the archive. The copy is
    gentle and unexplaining — no confirmation, no reason prompt, so neither is
    modeled here."""
    photo = _related_photo(db, user, photo_id)
    if db.get(Rest, (user.id, photo.id)) is None:
        db.add(Rest(user_id=user.id, photo_id=photo.id, rested_at=clock.now()))
    return {"rested": True}


@router.delete("/memories/{photo_id}/rest", status_code=204)
def unrest(
    photo_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """'Let it return' — undo a rest from the Rested view (§14)."""
    existing = db.get(Rest, (user.id, photo_id))
    if existing is not None:
        db.delete(existing)


@router.get("/memories/rested")
def rested(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """The Rested view: memories the user has set never to resurface. They are
    NOT deleted — still browsable here, each with a 'let it return' undo. Skips
    any whose underlying image is gone."""
    now = clock.now()
    rows = db.execute(
        select(Rest, Photo)
        .join(Photo, Photo.id == Rest.photo_id)
        .where(Rest.user_id == user.id, Photo.state != physics.PURGED)
        .order_by(Rest.rested_at.desc())
    ).all()
    hidden = blocked_ids(db, user.id)
    out = []
    for _, photo in rows:
        if photo.owner_id is not None and photo.owner_id in hidden:
            continue
        anchor = db.get(Anchor, (photo.id, user.id))
        if anchor is not None:
            out.append(memory_payload(db, settings, now, photo, anchor, user))
        elif photo.owner_id == user.id and photo.deriv_key:
            payload = photo_payload(db, settings, now, photo, user)
            payload.update({"tombstone": False, "note": None, "anchored_at": None})
            out.append(payload)
    return {"memories": out}
