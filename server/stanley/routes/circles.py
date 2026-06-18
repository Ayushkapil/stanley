from __future__ import annotations

from datetime import timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import (
    get_clock,
    get_current_user,
    get_db,
    get_settings,
    member_count,
    require_membership,
)
from ..models import Circle, CommunityNote, Membership, User, new_id
from ..serialize import avatar_url, blocked_ids, community_note_payload

router = APIRouter(tags=["circles"])


class CircleCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class JoinBody(BaseModel):
    invite_token: str


class NoteBody(BaseModel):
    text: str = Field(min_length=1, max_length=90)


def _members_payload(db: Session, circle: Circle, settings=None, now=None) -> list[dict]:
    """The circle as people — faces and names. Rendered as a cluster of avatars
    in the client, never a count."""
    rows = db.execute(
        select(Membership, User)
        .join(User, User.id == Membership.user_id)
        .where(Membership.circle_id == circle.id)
        .order_by(Membership.joined_at)
    ).all()
    return [
        {
            "id": u.id,
            "display_name": u.display_name,
            "avatar_url": avatar_url(settings, u.avatar_key, now),
            "joined_at": m.joined_at.isoformat(),
            "is_creator": circle.created_by == u.id,
        }
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
    settings=Depends(get_settings),
):
    circle = db.get(Circle, circle_id)
    if circle is None or circle.invite_token != body.invite_token:
        # A rotated code lands here: the old token no longer matches.
        raise HTTPException(404, "not found")
    _ensure_not_in_a_circle(db, user)
    if member_count(db, circle.id) >= circle.cap:
        # §16: hard cap 12 — capped intimacy is the gentleness guarantee.
        raise HTTPException(409, {"code": "circle_full"})
    now = clock.now()
    db.add(Membership(circle_id=circle.id, user_id=user.id, joined_at=now))
    db.flush()
    return {"id": circle.id, "name": circle.name, "members": _members_payload(db, circle, settings, now)}


@router.get("/circles/mine")
def my_circle(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    membership, circle = require_membership(db, user)
    return {
        "id": circle.id,
        "name": circle.name,
        "invite_token": circle.invite_token,
        "is_creator": circle.created_by == user.id,
        "members": _members_payload(db, circle, settings, clock.now()),
    }


@router.post("/circles/{circle_id}/rotate_invite")
def rotate_invite(
    circle_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Creator-only. Mints a fresh token; the old code stops joining at once."""
    _, circle = require_membership(db, user)
    if circle.id != circle_id or circle.created_by != user.id:
        raise HTTPException(403, {"code": "creator_only"})
    circle.invite_token = new_id()
    return {"invite_token": circle.invite_token}


@router.delete("/circles/{circle_id}/members/{user_id}", status_code=204)
def remove_member(
    circle_id: str,
    user_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Creator-only. Removes another member's place in the circle. Their own
    held memories stay theirs; they simply can no longer see or post here."""
    _, circle = require_membership(db, user)
    if circle.id != circle_id or circle.created_by != user.id:
        raise HTTPException(403, {"code": "creator_only"})
    if user_id == user.id:
        raise HTTPException(400, {"code": "use_leave"})
    target = db.get(Membership, (circle.id, user_id))
    if target is None:
        raise HTTPException(404, "not found")
    db.delete(target)


@router.post("/circles/{circle_id}/leave", status_code=204)
def leave_circle(
    circle_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Any member may leave. If the creator leaves, the role passes to the
    next-earliest member so the circle is never left ownerless."""
    membership, circle = require_membership(db, user)
    if circle.id != circle_id:
        raise HTTPException(404, "not found")
    db.delete(membership)
    db.flush()
    if circle.created_by == user.id:
        # user_id breaks ties so "next-earliest" is deterministic even when two
        # members joined in the same instant.
        successor = db.scalars(
            select(Membership)
            .where(Membership.circle_id == circle.id)
            .order_by(Membership.joined_at, Membership.user_id)
        ).first()
        if successor is not None:
            circle.created_by = successor.user_id
            successor.role = "creator"


@router.put("/circles/{circle_id}/note")
def set_note(
    circle_id: str,
    body: NoteBody,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Set or replace the circle's shared line (Part 4). Single active note,
    last-writer-wins. It expires at the end of the setter's local day. Not a
    chat — there is nowhere to reply, and nothing is notified."""
    membership, circle = require_membership(db, user)
    if circle.id != circle_id:
        raise HTTPException(404, "not found")
    text = body.text.strip()
    if not text:
        raise HTTPException(400, {"code": "empty_note"})

    now = clock.now()
    tz = ZoneInfo(user.tz_last_seen or "UTC")
    local_next_midnight = (now.astimezone(tz) + timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    expires_at = local_next_midnight.astimezone(ZoneInfo("UTC"))

    note = db.get(CommunityNote, circle.id)
    if note is None:
        note = CommunityNote(circle_id=circle.id)
        db.add(note)
    note.author_id = user.id
    note.body = text
    note.expires_at = expires_at
    note.created_at = now
    db.flush()
    return community_note_payload(db, settings, now, circle.id)


@router.get("/members/{user_id}")
def member_profile(
    user_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """A circle member's profile: their face, name and words, nothing else.
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
        "avatar_url": avatar_url(settings, target.avatar_key, clock.now()),
    }
