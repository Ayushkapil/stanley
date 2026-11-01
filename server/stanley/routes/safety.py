from __future__ import annotations

import logging

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import alerts
from ..deps import (
    get_clock, get_current_user, get_db, get_settings, my_circle_ids, require_membership, shares_a_circle,
)
from ..models import Block, Comment, Photo, Report, User
from ..serialize import user_brief

log = logging.getLogger("stanley")

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
    background: BackgroundTasks,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """§15: report with a 24h human-review takedown commitment (App Review
    Guideline 1.2). Pilot-stage review is manual."""
    require_membership(db, user)
    if not body.photo_id and not body.comment_id:
        raise HTTPException(400, "photo_id or comment_id required")
    if body.photo_id:
        photo = db.get(Photo, body.photo_id)
        if photo is None or photo.circle_id not in my_circle_ids(db, user.id):
            raise HTTPException(404, "not found")
    if body.comment_id:
        comment = db.get(Comment, body.comment_id)
        photo = db.get(Photo, comment.photo_id) if comment else None
        # Only a story you could have read: one on a photo in your circles.
        if photo is None or photo.circle_id not in my_circle_ids(db, user.id):
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
    # A warning, so it shows in the host's logs (the app's INFO lines don't):
    # the 24-hour promise starts now. Nothing about who or what.
    log.warning("A report is waiting for review: %s", row.id)
    # And to a phone, if there's somewhere to say it: after the commit and
    # the response, with nothing in it but that one line (`alerts.py`).
    if settings.report_webhook_url:
        background.add_task(alerts.report_waiting, settings.report_webhook_url)
    return {"id": row.id, "review_within_hours": 24}


@router.post("/blocks", status_code=204)
def block(
    body: BlockBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """§15: blocking hides all content bidirectionally within the circle. An
    abusive ex inside a circle is a small-N problem, not a large-N one. A
    block holds across every circle the two share: someone you met in one
    circle, wherever you're looking."""
    require_membership(db, user)
    if body.user_id == user.id:
        raise HTTPException(400, "cannot block yourself")
    if not shares_a_circle(db, user.id, body.user_id):
        raise HTTPException(404, "not found")
    if db.get(Block, (user.id, body.user_id)) is None:
        db.add(Block(blocker_id=user.id, blocked_id=body.user_id, created_at=clock.now()))


@router.get("/blocks")
def blocked_people(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    settings=Depends(get_settings),
    clock=Depends(get_clock),
):
    """The people you've blocked, as faces and names, so you can unblock
    them (build 18). Only your own blocks: never who has blocked you."""
    now = clock.now()
    blocks = db.scalars(
        select(Block).where(Block.blocker_id == user.id).order_by(Block.created_at)
    ).all()
    return {"people": [user_brief(db, b.blocked_id, settings, now) for b in blocks]}


@router.delete("/blocks/{user_id}", status_code=204)
def unblock(
    user_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    existing = db.get(Block, (user.id, user_id))
    if existing is not None:
        db.delete(existing)
