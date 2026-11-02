from __future__ import annotations

from datetime import timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from ..deps import (
    active_circle_id,
    get_clock,
    get_current_user,
    get_db,
    get_settings,
    member_count,
    membership_in,
    my_circle_ids,
    require_membership,
    shares_a_circle,
)
from .. import physics
from ..models import Circle, CommunityNote, Membership, Photo, User, new_id, new_invite_code
from ..physics import CIRCLES_PER_PERSON
from ..serialize import avatar_url, blocked_ids, community_note_payload, iso, photo_payload

# Said once, in words rather than a number: the cap is a guardrail, not a goal.
CIRCLE_FULL_MESSAGE = "Stanley works best with people you actually know."

router = APIRouter(tags=["circles"])


class CircleCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class JoinBody(BaseModel):
    invite_token: str


class JoinCodeBody(BaseModel):
    code: str  # short XXXX-XXXX code


class NoteBody(BaseModel):
    text: str = Field(min_length=1, max_length=90)


class RenameBody(BaseModel):
    name: str = Field(min_length=1, max_length=80)


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


def _ensure_room_for_another(db: Session, user: User, circle: Circle | None = None) -> None:
    """A person can be in a few circles (build 17), each with its own day.
    Joining one you're already in is `already_in_circle`; past five, the
    answer is no, said in words by the app, never as a tally."""
    if circle is not None and db.get(Membership, (circle.id, user.id)) is not None:
        raise HTTPException(409, {"code": "already_in_circle"})
    held = db.scalar(
        select(func.count()).select_from(Membership).where(Membership.user_id == user.id)
    )
    if held >= CIRCLES_PER_PERSON:
        raise HTTPException(409, {"code": "too_many_circles"})


@router.post("/circles", status_code=201)
def create_circle(
    body: CircleCreate,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    _ensure_room_for_another(db, user)
    now = clock.now()
    circle = Circle(name=body.name, created_by=user.id, created_at=now)
    db.add(circle)
    db.flush()
    db.add(Membership(circle_id=circle.id, user_id=user.id, joined_at=now, role="creator"))
    # The invite token is the circle-first onboarding act (§4): one link or QR
    # at a table, and the feed is alive from the first session.
    return {"id": circle.id, "name": circle.name, "invite_token": circle.invite_token}


@router.post("/circles/join", status_code=201)
def join_by_code(
    body: JoinCodeBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Join a circle using the short human-friendly code (XXXX-XXXX).
    Case-insensitive; hyphens are normalised so NECR7KX4 == NECR-7KX4."""
    raw = body.code.strip().upper().replace(" ", "")
    # Accept code with or without the hyphen
    if len(raw) == 8 and "-" not in raw:
        raw = f"{raw[:4]}-{raw[4:]}"
    circle = db.scalars(select(Circle).where(Circle.invite_token == raw)).first()
    if circle is None:
        raise HTTPException(404, "not found")
    _ensure_room_for_another(db, user, circle)
    if member_count(db, circle.id) >= circle.cap:
        raise HTTPException(409, {"code": "circle_full", "message": CIRCLE_FULL_MESSAGE})
    now = clock.now()
    db.add(Membership(circle_id=circle.id, user_id=user.id, joined_at=now))
    db.flush()
    return {"id": circle.id, "name": circle.name, "members": _members_payload(db, circle, settings, now)}


@router.post("/circles/{circle_id}/join", status_code=201)
def join_circle(
    circle_id: str,
    body: JoinBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    circle = db.get(Circle, circle_id)
    if circle is None or circle.invite_token != body.invite_token:
        # A rotated code lands here: the old token no longer matches.
        raise HTTPException(404, "not found")
    _ensure_room_for_another(db, user, circle)
    if member_count(db, circle.id) >= circle.cap:
        # §16: a soft ceiling, not a wall — see physics.CIRCLE_CAP.
        raise HTTPException(409, {"code": "circle_full", "message": CIRCLE_FULL_MESSAGE})
    now = clock.now()
    db.add(Membership(circle_id=circle.id, user_id=user.id, joined_at=now))
    db.flush()
    return {"id": circle.id, "name": circle.name, "members": _members_payload(db, circle, settings, now)}


@router.get("/circles")
def my_circles(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Every circle the person is in, in the order they joined, for the
    switcher atop Today. Names only: no member counts, no activity, nothing
    that ranks one circle above another."""
    rows = db.execute(
        select(Membership, Circle)
        .join(Circle, Circle.id == Membership.circle_id)
        .where(Membership.user_id == user.id)
        .order_by(Membership.joined_at, Membership.circle_id)
    ).all()
    return {
        "circles": [
            {"id": c.id, "name": c.name, "is_creator": c.created_by == user.id}
            for _, c in rows
        ]
    }


@router.get("/circles/mine")
def my_circle(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
    circle_id: str | None = Depends(active_circle_id),
):
    """The circle on screen: the one the app names, else the first joined."""
    membership, circle = require_membership(db, user, circle_id)
    return {
        "id": circle.id,
        "name": circle.name,
        "invite_token": circle.invite_token,
        "is_creator": circle.created_by == user.id,
        "members": _members_payload(db, circle, settings, clock.now()),
    }


@router.patch("/circles/{circle_id}")
def rename_circle(
    circle_id: str,
    body: RenameBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Creator-only (build 18): what the circle is called, as everyone in it
    sees it atop Today."""
    _, circle = membership_in(db, user, circle_id)
    if circle.created_by != user.id:
        raise HTTPException(403, {"code": "creator_only"})
    name = body.name.strip()
    if not name:
        raise HTTPException(400, {"code": "empty_circle_name"})
    circle.name = name
    return {"id": circle.id, "name": circle.name}


@router.post("/circles/{circle_id}/rotate_invite")
def rotate_invite(
    circle_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Creator-only. Mints a fresh token; the old code stops joining at once."""
    _, circle = membership_in(db, user, circle_id)
    if circle.created_by != user.id:
        raise HTTPException(403, {"code": "creator_only"})
    circle.invite_token = new_invite_code()
    return {"invite_token": circle.invite_token}


@router.delete("/circles/{circle_id}/members/{user_id}", status_code=204)
def remove_member(
    circle_id: str,
    user_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Creator-only. Removes another member's place in the circle. Their own
    held memories stay theirs; they simply can no longer see or post here."""
    _, circle = membership_in(db, user, circle_id)
    if circle.created_by != user.id:
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
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Any member may leave. If the creator leaves, the role passes to the
    next-earliest member so the circle is never left ownerless. Leaving one
    circle leaves the others as they were."""
    membership, circle = membership_in(db, user, circle_id)
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
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Set or replace the circle's shared line (Part 4). Single active note,
    last-writer-wins. It expires at the end of the setter's local day. Not a
    chat — there is nowhere to reply, and nothing is notified."""
    membership, circle = membership_in(db, user, circle_id)
    text = body.text.strip()
    if not text:
        raise HTTPException(400, {"code": "empty_note"})

    now = clock.now()
    tz = ZoneInfo(user.tz_last_seen or "UTC")
    local_next_midnight = (now.astimezone(tz) + timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    expires_at = local_next_midnight.astimezone(ZoneInfo("UTC"))

    # I6: atomic last-writer-wins — no get-or-create PK race.
    db.execute(
        sqlite_insert(CommunityNote)
        .values(circle_id=circle.id, author_id=user.id, body=text, expires_at=expires_at, created_at=now)
        .on_conflict_do_update(
            index_elements=["circle_id"],
            set_={"author_id": user.id, "body": text, "expires_at": expires_at, "created_at": now},
        )
    )
    db.flush()
    return community_note_payload(db, settings, now, circle.id)


@router.get("/members/{user_id}")
def member_profile(
    user_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
    active: str | None = Depends(active_circle_id),
):
    """A circle member's profile, a page in the shared journal (build 19):
    their face, name and words, since when they've been in the circle, a
    quiet mark if they started it, and their photos still in the light.
    Invariant A2 extends to identity surfaces — keepings are owner-private, so
    this payload structurally has no field for anchors, kept grids, or counts
    (not even how many moments they've shared: that number is theirs alone,
    on `/me`). The photos are their own posts in circles you share, which Today
    already shows you. Anyone you share a circle with, whichever circle is on
    screen."""
    _, circle = require_membership(db, user, active)
    if not shares_a_circle(db, user.id, user_id) or user_id in blocked_ids(db, user.id):
        raise HTTPException(404, "not found")
    target = db.get(User, user_id)
    if target is None or target.deleted_at is not None:
        raise HTTPException(404, "not found")
    now = clock.now()
    shared = my_circle_ids(db, user.id) & my_circle_ids(db, target.id)
    # "Member since": of the circle on screen when they're in it, else of the
    # first circle you share.
    here = db.get(Membership, (circle.id, target.id))
    since = here or db.scalars(
        select(Membership)
        .where(Membership.user_id == target.id, Membership.circle_id.in_(shared))
        .order_by(Membership.joined_at)
    ).first()
    live = db.scalars(
        select(Photo)
        .where(
            Photo.owner_id == target.id,
            Photo.circle_id.in_(shared),
            Photo.state.in_(physics.PUBLIC_STATES),
            Photo.deleted_at.is_(None),
        )
        .order_by(Photo.taken_at.desc())  # newest first, and nothing else
        .limit(12)
    ).all()
    return {
        "id": target.id,
        "display_name": target.display_name,
        "username": target.username,
        "bio": target.bio,
        "avatar_url": avatar_url(settings, target.avatar_key, now),
        "member_since": iso(since.joined_at) if since else None,
        "is_organizer": here is not None and circle.created_by == target.id,
        "photos": [photo_payload(db, settings, now, p, user) for p in live],
    }
