from __future__ import annotations

import logging

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from .. import alerts, sharing
from ..deps import (
    event, get_clock, get_current_user, get_db, get_settings, my_circle_ids, require_membership, shares_a_circle,
)
from ..models import Block, CircleNote, Comment, PersonLetter, Photo, Report, User
from ..ratelimit import per_person
from .circle_letters import readable_letter
from .journal import readable_answer
from ..serialize import blocked_ids, user_brief
from ..text import clean

log = logging.getLogger("stanley")

router = APIRouter(tags=["safety"])


# How much of a reported journal page a report keeps: enough to judge it by.
PAGE_EXCERPT = 4000


class ReportBody(BaseModel):
    photo_id: str | None = Field(default=None, max_length=64)
    comment_id: str | None = Field(default=None, max_length=64)
    # An answer to the circle's question of the week (build 26).
    response_id: str | None = Field(default=None, max_length=64)
    # A note on the circle's board (build 27).
    note_id: str | None = Field(default=None, max_length=64)
    # An anonymous letter to the circle (build 42).
    circle_letter_id: str | None = Field(default=None, max_length=64)
    # A letter sent to you, once you've opened it (build 42). A sealed
    # letter has no words to report yet.
    letter_id: str | None = Field(default=None, max_length=64)
    # A page in a circle's shared journal (build 51).
    page_id: str | None = Field(default=None, max_length=64)
    # Never run through the word filter: a report may have to quote what
    # it's about.
    reason: str = Field(min_length=1, max_length=2000)


class BlockBody(BaseModel):
    user_id: str = Field(max_length=64)


@router.post("/reports", status_code=201, dependencies=[per_person("report")])
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
    if not (
        body.photo_id or body.comment_id or body.response_id or body.note_id
        or body.circle_letter_id or body.letter_id or body.page_id
    ):
        raise HTTPException(
            400, "photo_id, comment_id, response_id, note_id, circle_letter_id, letter_id or page_id required"
        )
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
    if body.response_id and readable_answer(db, user, body.response_id, clock.now()) is None:
        # Only an answer you could have read: open, in your circle, from a
        # week you were there for.
        raise HTTPException(404, "not found")
    reason = clean(body.reason, multiline=True) or "(no reason given)"
    if body.letter_id:
        # Only a letter addressed to you, and only once you've opened it.
        # A sealed letter has no words to object to yet.
        letter = db.get(PersonLetter, body.letter_id)
        if letter is None or letter.recipient_id != user.id or letter.opened_at is None:
            raise HTTPException(404, "not found")
    if body.note_id:
        # Only a note you could see: on a board you're on, by someone no
        # block stands between. It clears by midnight, sooner than a report
        # may be read, so the report keeps a copy of what it said.
        note = db.get(CircleNote, body.note_id)
        if (
            note is None
            or note.circle_id not in my_circle_ids(db, user.id)
            or note.author_id in blocked_ids(db, user.id)
        ):
            raise HTTPException(404, "not found")
        reason = f"{reason}\n\nThe note, by {note.author_id}: {note.body}"
    if body.circle_letter_id:
        # Only a letter you could have read: opened, in a circle you were
        # in when it opened. It's deleted within the week (sooner, if its
        # writer takes it back), so the report keeps its words, and who
        # wrote them. A letter is unsigned to the circle, never to the
        # person who has to act on a report; nothing of this goes back to
        # the reporter.
        letter = readable_letter(db, user, body.circle_letter_id, clock.now())
        if letter is None:
            raise HTTPException(404, "not found")
        reason = (
            f"{reason}\n\nThe letter, by {letter.author_id}, to circle {letter.circle_id} "
            f"for {letter.month:%Y-%m}: {letter.body}"
        )
    if body.page_id:
        # Only a shared page you could read: in a circle's book you're in,
        # from a day you were there for, by someone no block stands between.
        # Its writer can take it back or tear it out before a report is
        # read, so the report keeps who wrote it and how it begins. Never
        # your own.
        page = sharing.readable_page(db, user, body.page_id)
        if page is None or page.owner_id == user.id:
            raise HTTPException(404, "not found")
        reason = (
            f"{reason}\n\nThe shared page, by {page.owner_id}, in circle {page.circle_id} "
            f"for {page.day:%Y-%m-%d}: {page.body[:PAGE_EXCERPT]}"
        )
    row = Report(
        reporter_id=user.id,
        photo_id=body.photo_id,
        comment_id=body.comment_id,
        response_id=body.response_id,
        note_id=body.note_id,
        circle_letter_id=body.circle_letter_id,
        letter_id=body.letter_id,
        page_id=body.page_id,
        reason=reason,
        created_at=clock.now(),
    )
    db.add(row)
    db.flush()
    # A warning, so it shows in the host's logs (the app's INFO lines don't):
    # the 24-hour promise starts now. Nothing about who or what.
    log.warning("A report is waiting for review: %s (event=report_filed report=%s)", row.id, row.id)
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
    added = db.execute(
        sqlite_insert(Block)
        .values(blocker_id=user.id, blocked_id=body.user_id, created_at=clock.now())
        .on_conflict_do_nothing(index_elements=["blocker_id", "blocked_id"])
    )
    if added.rowcount:
        event("block", user=user.id)


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
