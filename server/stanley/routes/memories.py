from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..deps import get_clock, get_current_user, get_db
from ..models import Anchor, Photo, Rest, User

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
    """Undoable from the archive view (§14)."""
    existing = db.get(Rest, (user.id, photo_id))
    if existing is not None:
        db.delete(existing)
