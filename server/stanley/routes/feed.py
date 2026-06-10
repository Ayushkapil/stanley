from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import physics
from ..deps import get_clock, get_current_user, get_db, get_settings, require_membership
from ..models import Photo, User
from ..returned import returned_item
from ..serialize import blocked_ids, photo_payload

router = APIRouter(tags=["feed"])


@router.get("/feed/today")
def today(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """The Today feed: a handful of fading photos from the circle, ordered by
    time and nothing else. Non-goal §7: never reordered by engagement; anchors
    never extend visibility (A1) — the query simply has no access to them."""
    membership, _ = require_membership(db, user)
    now = clock.now()
    hidden = blocked_ids(db, user.id)
    photos = db.scalars(
        select(Photo)
        .where(
            Photo.circle_id == membership.circle_id,
            Photo.state.in_(physics.PUBLIC_STATES),
            Photo.deleted_at.is_(None),
        )
        .order_by(Photo.taken_at.desc())
    ).all()
    return {
        "photos": [
            photo_payload(db, settings, now, p, user)
            for p in photos
            if p.owner_id not in hidden
        ]
    }


@router.get("/feed/returned")
def returned(
    tz: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    tz_name = tz or user.tz_last_seen or "UTC"
    if tz:
        user.tz_last_seen = tz
    return {"item": returned_item(db, settings, clock, user, tz_name)}
