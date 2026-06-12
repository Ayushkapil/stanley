from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import get_clock, get_current_user, get_db, member_count, require_membership
from ..models import Circle, Membership, User
from ..serialize import blocked_ids

router = APIRouter(tags=["circles"])


class CircleCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class JoinBody(BaseModel):
    invite_token: str


def _members_payload(db: Session, circle: Circle) -> list[dict]:
    rows = db.execute(
        select(Membership, User)
        .join(User, User.id == Membership.user_id)
        .where(Membership.circle_id == circle.id)
        .order_by(Membership.joined_at)
    ).all()
    return [
        {"id": u.id, "display_name": u.display_name, "joined_at": m.joined_at.isoformat()}
        for m, u in rows
        if u.deleted_at is None
    ]


def _ensure_not_in_a_circle(db: Session, user: User) -> None:
    existing = db.scalars(select(Membership).where(Membership.user_id == user.id)).first()
    if existing is not None:
        # §16: one circle per person at MVP.
        raise HTTPException(409, {"code": "already_in_circle"})


@router.post("/circles", status_code=201)
def create_circle(
    body: CircleCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    _ensure_not_in_a_circle(db, user)
    now = clock.now()
    circle = Circle(name=body.name, created_by=user.id, created_at=now)
    db.add(circle)
    db.flush()
    db.add(Membership(circle_id=circle.id, user_id=user.id, joined_at=now, role="creator"))
    # The invite token is the circle-first onboarding act (§4): one link or QR
    # at a table, and the feed is alive from the first session.
    return {"id": circle.id, "name": circle.name, "invite_token": circle.invite_token}


@router.post("/circles/{circle_id}/join", status_code=201)
def join_circle(
    circle_id: str,
    body: JoinBody,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    circle = db.get(Circle, circle_id)
    if circle is None or circle.invite_token != body.invite_token:
        raise HTTPException(404, "not found")
    _ensure_not_in_a_circle(db, user)
    if member_count(db, circle.id) >= circle.cap:
        # §16: hard cap 12 — capped intimacy is the gentleness guarantee.
        raise HTTPException(409, {"code": "circle_full"})
    db.add(Membership(circle_id=circle.id, user_id=user.id, joined_at=clock.now()))
    db.flush()
    return {"id": circle.id, "name": circle.name, "members": _members_payload(db, circle)}


@router.get("/circles/mine")
def my_circle(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    _, circle = require_membership(db, user)
    return {"id": circle.id, "name": circle.name, "members": _members_payload(db, circle)}


@router.get("/members/{user_id}")
def member_profile(
    user_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """A circle member's profile: their name and their words, nothing else.
    Invariant A2 extends to identity surfaces — keepings are owner-private, so
    this payload structurally has no field for anchors, kept grids, or counts."""
    membership, _ = require_membership(db, user)
    target_membership = db.get(Membership, (membership.circle_id, user_id))
    if target_membership is None or user_id in blocked_ids(db, user.id):
        raise HTTPException(404, "not found")
    target = db.get(User, user_id)
    if target is None or target.deleted_at is not None:
        raise HTTPException(404, "not found")
    return {
        "id": target.id,
        "display_name": target.display_name,
        "username": target.username,
        "bio": target.bio,
    }
