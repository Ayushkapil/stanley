from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_clock, get_current_user, get_db, require_membership
from ..models import Block, Comment, Membership, Photo, Report, User

router = APIRouter(tags=["safety"])


class ReportBody(BaseModel):
    photo_id: str | None = None
    comment_id: str | None = None
    reason: str = Field(min_length=1, max_length=2000)


class BlockBody(BaseModel):
    user_id: str


@router.post("/reports", status_code=201)
def report(
    body: ReportBody,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """§15: report with a 24h human-review takedown commitment (App Review
    Guideline 1.2). Pilot-stage review is manual."""
    membership, _ = require_membership(db, user)
    if not body.photo_id and not body.comment_id:
        raise HTTPException(400, "photo_id or comment_id required")
    if body.photo_id:
        photo = db.get(Photo, body.photo_id)
        if photo is None or photo.circle_id != membership.circle_id:
            raise HTTPException(404, "not found")
    if body.comment_id:
        comment = db.get(Comment, body.comment_id)
        if comment is None:
            raise HTTPException(404, "not found")
    row = Report(
        reporter_id=user.id,
        photo_id=body.photo_id,
        comment_id=body.comment_id,
        reason=body.reason,
        created_at=clock.now(),
    )
    db.add(row)
    db.flush()
    return {"id": row.id, "review_within_hours": 24}


@router.post("/blocks", status_code=204)
def block(
    body: BlockBody,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """§15: blocking hides all content bidirectionally within the circle. An
    abusive ex inside a circle is a small-N problem, not a large-N one."""
    membership, _ = require_membership(db, user)
    if body.user_id == user.id:
        raise HTTPException(400, "cannot block yourself")
    target = db.get(Membership, (membership.circle_id, body.user_id))
    if target is None:
        raise HTTPException(404, "not found")
    if db.get(Block, (user.id, body.user_id)) is None:
        db.add(Block(blocker_id=user.id, blocked_id=body.user_id, created_at=clock.now()))


@router.delete("/blocks/{user_id}", status_code=204)
def unblock(
    user_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    existing = db.get(Block, (user.id, user_id))
    if existing is not None:
        db.delete(existing)
