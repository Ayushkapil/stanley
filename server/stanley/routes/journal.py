"""Writing things down (build 26): the private journal entry on your own
photo, your reflection on the week, and the circle's question of the week.
The weeks and the questions are in `journal.py`; who may read and write
what is here, route by route. Nothing here counts anything, and nothing
here sends a notification."""
from __future__ import annotations

import base64
import binascii
import json
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import and_, or_, select, update
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from .. import journal, physics
from ..decay import forget_journal
from ..deps import get_clock, get_current_user, get_db, get_settings, membership_in, refuse_objectionable
from ..models import (
    Anchor, CirclePrompt, JournalEntry, JournalPage, Membership, Photo, PromptResponse, Report, User,
    WeeklyReflection, new_id,
)
from ..ratelimit import per_person
from ..serialize import blocked_ids, iso, user_brief
from ..storage import read_url
from ..text import clean, clean_optional
from .photos import valid_timezone

router = APIRouter(tags=["journal"])

# Reflections and the circle's past questions come a page at a time.
PAGE = 20
PAGE_MAX = 50


class JournalBody(BaseModel):
    body: str = Field(min_length=1, max_length=journal.JOURNAL_MAX)


class ReflectionBody(BaseModel):
    body: str = Field(min_length=1, max_length=journal.REFLECTION_MAX)
    # The phone's zone, so the week is the writer's own.
    tz: str | None = Field(default=None, max_length=64)


class InkRun(BaseModel):
    """A stretch of a page written in one ink (build 50)."""

    ink: str = Field(max_length=8)
    text: str = Field(max_length=journal.PAGE_MAX)


class TodaysPageBody(BaseModel):
    body: str = Field(min_length=1, max_length=journal.PAGE_MAX)
    ink: str = Field(default="black", max_length=8)
    # The page ink by ink, when it's in more than one. When it's sent, it
    # is the page: `body` and `ink` are for a server that doesn't know it.
    runs: list[InkRun] | None = Field(default=None, max_length=journal.RUNS_MAX)
    # The phone's zone, so the day is the writer's own.
    tz: str | None = Field(default=None, max_length=64)


class PagePatch(BaseModel):
    body: str | None = Field(default=None, min_length=1, max_length=journal.PAGE_MAX)
    ink: str | None = Field(default=None, max_length=8)
    runs: list[InkRun] | None = Field(default=None, max_length=journal.RUNS_MAX)


class JournalTitleBody(BaseModel):
    # Blank puts the app's own title back.
    title: str = Field(max_length=200)


class AnswerBody(BaseModel):
    body: str = Field(min_length=1, max_length=journal.ANSWER_MAX)


def _cursor(week: date, key: str) -> str:
    raw = f"{week.isoformat()}|{key}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _parse_cursor(cursor: str) -> tuple[date, str]:
    """Where the last page ended: its last week and id, opaque to the app."""
    try:
        raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)).decode()
        week, key = raw.split("|", 1)
        start = date.fromisoformat(week)
    except (binascii.Error, UnicodeDecodeError, ValueError):
        raise HTTPException(400, {"code": "bad_cursor"})
    if not key:
        raise HTTPException(400, {"code": "bad_cursor"})
    return start, key


def _before(columns, cursor: str | None):
    """Rows after the cursor, newest first by (week, id)."""
    if cursor is None:
        return True
    week, key = _parse_cursor(cursor)
    week_col, id_col = columns
    return or_(week_col < week, and_(week_col == week, id_col < key))


# --- The journal entry on your own photo -------------------------------------


def _own_photo(db: Session, user: User, photo_id: str) -> Photo:
    """Your own photo, still there. Anyone else's reads as not found: whether
    someone wrote about their photo isn't anyone else's to learn."""
    photo = db.get(Photo, photo_id)
    if (
        photo is None
        or photo.owner_id is None
        or photo.owner_id != user.id
        or photo.deleted_at is not None
        or photo.state == physics.PURGED
    ):
        raise HTTPException(404, "not found")
    return photo


def _entry(db: Session, photo_id: str) -> JournalEntry | None:
    return db.scalars(select(JournalEntry).where(JournalEntry.photo_id == photo_id)).first()


def _entry_payload(entry: JournalEntry) -> dict:
    return {
        "photo_id": entry.photo_id,
        "body": entry.body,
        "created_at": iso(entry.created_at),
        "updated_at": iso(entry.updated_at),
    }


@router.get("/photos/{photo_id}/journal")
def read_entry(
    photo_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """Your entry on your own photo, fetched only when you open it."""
    entry = _entry(db, _own_photo(db, user, photo_id).id)
    if entry is None:
        raise HTTPException(404, "not found")
    return _entry_payload(entry)


@router.put("/photos/{photo_id}/journal", dependencies=[per_person("journal")])
def write_entry(
    photo_id: str,
    body: JournalBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """Write or rewrite your entry. Only while the photo is still yours to
    look at: in Today, or held by you after it leaves."""
    photo = _own_photo(db, user, photo_id)
    if photo.state not in physics.PUBLIC_STATES and db.get(Anchor, (photo.id, user.id)) is None:
        raise HTTPException(410, {"code": "faded"})
    words = clean_optional(body.body, multiline=True)
    if words is None:
        raise HTTPException(400, {"code": "empty_entry"})
    refuse_objectionable(words)
    now = clock.now()
    # One statement, so a double tap on Keep is one entry, never a 500.
    db.execute(
        sqlite_insert(JournalEntry)
        .values(id=new_id(), photo_id=photo.id, owner_id=user.id, body=words, created_at=now, updated_at=now)
        .on_conflict_do_update(index_elements=["photo_id"], set_={"body": words, "updated_at": now})
    )
    return _entry_payload(_entry(db, photo.id))


@router.delete("/photos/{photo_id}/journal", status_code=204)
def delete_entry(
    photo_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    photo = db.get(Photo, photo_id)
    if photo is None or photo.owner_id is None or photo.owner_id != user.id:
        raise HTTPException(404, "not found")
    forget_journal(db, photo.id)


# --- Your reflection on the week ---------------------------------------------


def _week_photos(db: Session, settings, now: datetime, user: User, week_start: date) -> list[dict]:
    """Your own photos from that week that are still there for you: in
    Today, or held by you. The rest have faded, and a reflection doesn't
    bring them back. In the order they were taken, from any of your circles."""
    held = set(db.scalars(select(Anchor.photo_id).where(Anchor.user_id == user.id)).all())
    photos = db.scalars(
        select(Photo)
        .where(
            Photo.owner_id == user.id,
            Photo.local_date >= week_start,
            Photo.local_date <= journal.week_end(week_start),
            Photo.deleted_at.is_(None),
            Photo.state != physics.PURGED,
            Photo.thumb_key.is_not(None),
        )
        .order_by(Photo.taken_at)
    ).all()
    return [
        {
            "id": p.id,
            "taken_at": iso(p.taken_at),
            "thumb": read_url(settings, p.thumb_key, now),
            "image": read_url(settings, p.deriv_key, now) if p.deriv_key else None,
            "caption": p.caption,
            # Held by you: at full light, as in Held. Otherwise it's still
            # in Today and fades as it does there.
            "held": p.id in held,
            "decay_progress": physics.decay_progress(p.taken_at, now),
        }
        for p in photos
        if p.state in physics.PUBLIC_STATES or p.id in held
    ]


def _reflection_payload(db: Session, settings, now: datetime, user: User, row: WeeklyReflection) -> dict:
    return {
        "id": row.id,
        "week_start": row.week_start.isoformat(),
        "week_end": journal.week_end(row.week_start).isoformat(),
        "body": row.body,
        "created_at": iso(row.created_at),
        "photos": _week_photos(db, settings, now, user, row.week_start),
    }


def _zone(user: User, tz: str | None) -> str:
    if tz is not None and not valid_timezone(tz):
        raise HTTPException(400, {"code": "bad_timezone"})
    if tz:
        user.tz_last_seen = tz
    return tz or user.tz_last_seen or "UTC"


@router.post("/me/reflections", status_code=201, dependencies=[per_person("journal")])
def write_reflection(
    body: ReflectionBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """This week's reflection: the server says which week (its Monday, in
    the writer's zone), and there is one per week."""
    tz = _zone(user, body.tz)
    words = clean_optional(body.body, multiline=True)
    if words is None:
        raise HTTPException(400, {"code": "empty_reflection"})
    refuse_objectionable(words)
    now = clock.now()
    week = journal.reflection_week(now, tz)
    written = db.execute(
        sqlite_insert(WeeklyReflection)
        .values(id=new_id(), owner_id=user.id, week_start=week, body=words, created_at=now)
        .on_conflict_do_nothing(index_elements=["owner_id", "week_start"])
    )
    if not written.rowcount:
        raise HTTPException(409, {"code": "already_reflected"})
    row = db.scalars(
        select(WeeklyReflection).where(WeeklyReflection.owner_id == user.id, WeeklyReflection.week_start == week)
    ).one()
    return _reflection_payload(db, settings, now, user, row)


@router.get("/me/reflections")
def my_reflections(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
    limit: int = Query(default=PAGE, ge=1, le=PAGE_MAX),
    cursor: str | None = Query(default=None, max_length=200),
):
    """Every reflection you've written, newest week first, a page at a time."""
    rows = db.scalars(
        select(WeeklyReflection)
        .where(
            WeeklyReflection.owner_id == user.id,
            _before((WeeklyReflection.week_start, WeeklyReflection.id), cursor),
        )
        .order_by(WeeklyReflection.week_start.desc(), WeeklyReflection.id.desc())
        .limit(limit + 1)
    ).all()
    page, more = rows[:limit], len(rows) > limit
    now = clock.now()
    return {
        "reflections": [_reflection_payload(db, settings, now, user, r) for r in page],
        "next_cursor": _cursor(page[-1].week_start, page[-1].id) if more else None,
    }


@router.get("/me/reflections/this-week")
def this_week(
    tz: str | None = Query(default=None, max_length=64),
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """The week a reflection written now would be about: its days, your
    photos from it still there for you, and the reflection if it's written.
    The app asks on Sunday evening; the server doesn't hold to the hour."""
    tz_name = _zone(user, tz)
    now = clock.now()
    week = journal.reflection_week(now, tz_name)
    row = db.scalars(
        select(WeeklyReflection).where(WeeklyReflection.owner_id == user.id, WeeklyReflection.week_start == week)
    ).first()
    return {
        "week_start": week.isoformat(),
        "week_end": journal.week_end(week).isoformat(),
        "photos": _week_photos(db, settings, now, user, week),
        "reflection": _reflection_payload(db, settings, now, user, row) if row else None,
    }


def _own_reflection(db: Session, user: User, reflection_id: str) -> WeeklyReflection:
    row = db.get(WeeklyReflection, reflection_id)
    if row is None or row.owner_id != user.id:
        raise HTTPException(404, "not found")
    return row


@router.get("/me/reflections/{reflection_id}")
def read_reflection(
    reflection_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    row = _own_reflection(db, user, reflection_id)
    return _reflection_payload(db, settings, clock.now(), user, row)


@router.delete("/me/reflections/{reflection_id}", status_code=204)
def delete_reflection(
    reflection_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """A reflection never fades, but its writer can always take it back."""
    db.delete(_own_reflection(db, user, reflection_id))


# --- The journal as a book: a page a day --------------------------------------
#
# Build 45. What someone writes in their journal on a day, in the ink they
# chose. Nobody else reads it, anywhere: every route here is about the
# caller's own pages, and anyone else's id answers 404. The slur filter
# isn't on these: it's for what a circle reads (`wordfilter.py`), and a
# private page that refused someone's own account of their day would be
# keeping no one safe. Nothing here counts or notifies.

BOOK_PAGE = 100
BOOK_PAGE_MAX = 200


def page_runs(row: JournalPage) -> list[dict] | None:
    """A page that's in more than one ink, as its stretches: each ink and
    the words in it, in order, adding up to `body`. None for a page that's
    all one ink (or whose record of them doesn't fit its words)."""
    if not row.inks:
        return None
    try:
        kept = json.loads(row.inks)
        if sum(n for _, n in kept) != len(row.body):
            return None
    except (ValueError, TypeError):
        return None
    runs, at = [], 0
    for ink, n in kept:
        runs.append({"ink": ink, "text": row.body[at : at + n]})
        at += n
    return runs


def _page_payload(row: JournalPage) -> dict:
    return {
        "id": row.id,
        "day": row.day.isoformat(),
        "body": row.body,
        "ink": row.ink,
        "runs": page_runs(row),
        "created_at": iso(row.created_at),
        "updated_at": iso(row.updated_at),
    }


def _ink(value: str) -> str:
    if value not in journal.INKS:
        raise HTTPException(400, {"code": "bad_ink"})
    return value


def _words(value: str) -> str:
    words = clean(value, multiline=True)
    if not words:
        raise HTTPException(400, {"code": "empty_page"})
    return words


def _inked(runs: list[InkRun]) -> tuple[str, str, str | None]:
    """A page sent ink by ink: its words, the ink it begins in, and what's
    kept of the rest (None when it comes to one ink). Each stretch is
    cleaned like any text but keeps its own ends, since a space between
    two inks is the page's; only the page's ends are trimmed."""
    parts: list[list] = []
    for run in runs:
        ink = _ink(run.ink)
        words = clean(run.text, multiline=True, trim=False)
        if not words:
            continue
        if parts and parts[-1][0] == ink:
            parts[-1][1] += words
        else:
            parts.append([ink, words])
    while parts and not (lead := parts[0][1].lstrip()):
        parts.pop(0)
    if parts:
        parts[0][1] = lead
    while parts and not (tail := parts[-1][1].rstrip()):
        parts.pop()
    if parts:
        parts[-1][1] = tail
    body = "".join(words for _, words in parts)
    if not body:
        raise HTTPException(400, {"code": "empty_page"})
    if len(body) > journal.PAGE_MAX:
        raise HTTPException(422, "page too long")
    inks = json.dumps([[ink, len(words)] for ink, words in parts]) if len(parts) > 1 else None
    return body, parts[0][0], inks


def _own_page(db: Session, user: User, page_id: str) -> JournalPage:
    row = db.get(JournalPage, page_id)
    if row is None or row.owner_id != user.id:
        raise HTTPException(404, "not found")
    return row


@router.get("/me/journal")
def my_journal(
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    limit: int = Query(default=BOOK_PAGE, ge=1, le=BOOK_PAGE_MAX),
    after: date | None = Query(default=None),
):
    """Your journal: what you call it, and its written pages from the
    first day, oldest first as a book is read, a stretch at a time
    (`after` is the last day of the stretch before)."""
    rows = db.scalars(
        select(JournalPage)
        .where(JournalPage.owner_id == user.id, True if after is None else JournalPage.day > after)
        .order_by(JournalPage.day)
        .limit(limit + 1)
    ).all()
    stretch, more = rows[:limit], len(rows) > limit
    return {
        "title": user.journal_title,
        "pages": [_page_payload(r) for r in stretch],
        "next_after": stretch[-1].day.isoformat() if more else None,
    }


@router.put("/me/journal/today", dependencies=[per_person("journal")])
def write_today(
    body: TodaysPageBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """Today's page: the server says which day (the writer's own, from the
    zone the phone sends). One a day: writing again replaces what was
    there, it doesn't add to it."""
    tz = _zone(user, body.tz)
    if body.runs:
        words, ink, inks = _inked(body.runs)
    else:
        words, ink, inks = _words(body.body), _ink(body.ink), None
    now = clock.now()
    day = journal.local_day(now, tz)
    db.execute(
        sqlite_insert(JournalPage)
        .values(
            id=new_id(), owner_id=user.id, day=day, body=words, ink=ink, inks=inks, created_at=now, updated_at=now
        )
        .on_conflict_do_update(
            index_elements=["owner_id", "day"],
            set_={"body": words, "ink": ink, "inks": inks, "updated_at": now},
        )
    )
    row = db.scalars(
        select(JournalPage).where(JournalPage.owner_id == user.id, JournalPage.day == day)
    ).one()
    db.refresh(row)
    return _page_payload(row)


@router.patch("/me/journal/pages/{page_id}", dependencies=[per_person("journal")])
def edit_page(
    page_id: str,
    body: PagePatch,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
):
    """Rewrite a page you've written, or change its ink. Its day stays.
    Sent ink by ink (`runs`), that's the page. Sent as words or one ink,
    the page is all one ink again: new words have nowhere to keep the old
    stretches, and a change of ink is the whole page's."""
    row = _own_page(db, user, page_id)
    if body.runs:
        row.body, row.ink, row.inks = _inked(body.runs)
    else:
        if body.body is not None:
            row.body = _words(body.body)
            row.inks = None
        if body.ink is not None:
            row.ink = _ink(body.ink)
            row.inks = None
    row.updated_at = clock.now()
    return _page_payload(row)


@router.delete("/me/journal/pages/{page_id}", status_code=204)
def delete_page(
    page_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """A page never fades, but its writer can always tear it out."""
    db.delete(_own_page(db, user, page_id))


@router.put("/me/journal/title")
def name_journal(
    body: JournalTitleBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
):
    """What the journal is called, on its cover. Blank is the app's own."""
    title = clean(body.title)
    if len(title) > journal.TITLE_MAX:
        raise HTTPException(400, {"code": "title_too_long"})
    user.journal_title = title or None
    return {"title": user.journal_title}


# --- The circle's question of the week ----------------------------------------


def current_prompt(db: Session, circle_id: str, now: datetime) -> CirclePrompt:
    """The circle's question this week, chosen the first time anyone asks:
    one it hasn't had in its last thirty-nine weeks of questions."""
    week = journal.question_week(now)
    this_week = select(CirclePrompt).where(CirclePrompt.circle_id == circle_id, CirclePrompt.week_start == week)
    found = db.scalars(this_week).first()
    if found is not None:
        return found
    recent = db.scalars(
        select(CirclePrompt.prompt)
        .where(CirclePrompt.circle_id == circle_id)
        .order_by(CirclePrompt.week_start.desc())
        .limit(len(journal.QUESTIONS) - 1)
    ).all()
    # Two people opening Today at once both choose; one choice is kept,
    # and both see it.
    db.execute(
        sqlite_insert(CirclePrompt)
        .values(
            id=new_id(), circle_id=circle_id, prompt=journal.pick_question(list(recent)),
            week_start=week, created_at=now,
        )
        .on_conflict_do_nothing(index_elements=["circle_id", "week_start"])
    )
    return db.scalars(this_week).one()


def _prompt_payload(prompt: CirclePrompt) -> dict:
    return {
        "id": prompt.id,
        "text": prompt.prompt,
        "week_start": prompt.week_start.isoformat(),
        "week_end": journal.week_end(prompt.week_start).isoformat(),
        "reveals_at": iso(journal.reveals_at(prompt.week_start)),
    }


def _answer_payload(db: Session, settings, now: datetime, row: PromptResponse) -> dict:
    return {
        "id": row.id,
        "author": user_brief(db, row.user_id, settings, now),
        "body": row.body,
        "created_at": iso(row.created_at),
    }


def _answers(db: Session, settings, now: datetime, prompt: CirclePrompt, viewer: User) -> list[dict]:
    """A week's answers, in the order they were written, without anyone a
    block stands between."""
    hidden = blocked_ids(db, viewer.id)
    rows = db.scalars(
        select(PromptResponse)
        .where(PromptResponse.prompt_id == prompt.id)
        .order_by(PromptResponse.created_at, PromptResponse.id)
    ).all()
    return [_answer_payload(db, settings, now, r) for r in rows if r.user_id not in hidden]


def _first_week(membership: Membership) -> date:
    """The first week a member reads: the one they joined in. The weeks
    before were answered for the people who were here then."""
    return journal.question_week(membership.joined_at)


def _mine(db: Session, prompt: CirclePrompt, user: User) -> PromptResponse | None:
    return db.scalars(
        select(PromptResponse).where(PromptResponse.prompt_id == prompt.id, PromptResponse.user_id == user.id)
    ).first()


def _question(db: Session, settings, now: datetime, prompt: CirclePrompt, user: User) -> dict:
    mine = _mine(db, prompt, user)
    return {
        "prompt": _prompt_payload(prompt),
        "response": _answer_payload(db, settings, now, mine) if mine else None,
        "revealed": journal.revealed(prompt.week_start, now),
    }


@router.get("/circles/{circle_id}/prompt")
def this_weeks_question(
    circle_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """This week's question, your answer if you've given one, and whether
    the answers are open. Nothing about who else has answered, or how many."""
    _, circle = membership_in(db, user, circle_id)
    now = clock.now()
    return _question(db, settings, now, current_prompt(db, circle.id, now), user)


@router.post("/circles/{circle_id}/prompt/respond", status_code=201, dependencies=[per_person("journal")])
def answer(
    circle_id: str,
    body: AnswerBody,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Your answer, once, sealed until Saturday. Answering closes when the
    answers open, so nobody answers having read the rest."""
    _, circle = membership_in(db, user, circle_id)
    now = clock.now()
    prompt = current_prompt(db, circle.id, now)
    if journal.revealed(prompt.week_start, now):
        raise HTTPException(409, {"code": "question_closed"})
    words = clean_optional(body.body, multiline=True)
    if words is None:
        raise HTTPException(400, {"code": "empty_answer"})
    refuse_objectionable(words)
    written = db.execute(
        sqlite_insert(PromptResponse)
        .values(id=new_id(), prompt_id=prompt.id, user_id=user.id, body=words, created_at=now)
        .on_conflict_do_nothing(index_elements=["prompt_id", "user_id"])
    )
    if not written.rowcount:
        raise HTTPException(409, {"code": "already_answered"})
    return _question(db, settings, now, prompt, user)


@router.get("/circles/{circle_id}/prompt/responses")
def this_weeks_answers(
    circle_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
):
    """Everyone's answers to this week's question, once they're open: to
    everyone in the circle, answered or not. Sealed before (403)."""
    _, circle = membership_in(db, user, circle_id)
    now = clock.now()
    prompt = current_prompt(db, circle.id, now)
    if not journal.revealed(prompt.week_start, now):
        raise HTTPException(403, {"code": "not_revealed"})
    return {"prompt": _prompt_payload(prompt), "responses": _answers(db, settings, now, prompt, user)}


@router.get("/circles/{circle_id}/prompts")
def circle_journal(
    circle_id: str,
    db: Session = Depends(get_db, scope="function"),
    user: User = Depends(get_current_user),
    clock=Depends(get_clock),
    settings=Depends(get_settings),
    limit: int = Query(default=PAGE, ge=1, le=PAGE_MAX),
    cursor: str | None = Query(default=None, max_length=200),
):
    """The circle journal: every week's question whose answers are open,
    newest first, with what everyone said, from the week you joined on. A
    week nobody answered (that you can see) isn't a page."""
    membership, circle = membership_in(db, user, circle_id)
    now = clock.now()
    rows = db.scalars(
        select(CirclePrompt)
        .where(
            CirclePrompt.circle_id == circle.id,
            CirclePrompt.week_start <= journal.last_revealed_week(now),
            CirclePrompt.week_start >= _first_week(membership),
            _before((CirclePrompt.week_start, CirclePrompt.id), cursor),
        )
        .order_by(CirclePrompt.week_start.desc(), CirclePrompt.id.desc())
        .limit(limit + 1)
    ).all()
    page, more = rows[:limit], len(rows) > limit
    weeks = []
    for prompt in page:
        answers = _answers(db, settings, now, prompt, user)
        if answers:
            weeks.append(_prompt_payload(prompt) | {"responses": answers})
    return {
        "prompts": weeks,
        "next_cursor": _cursor(page[-1].week_start, page[-1].id) if more else None,
    }


def readable_answer(db: Session, user: User, response_id: str, now: datetime) -> PromptResponse | None:
    """An answer this person could have read: open, in a circle they're in,
    from a week they were there for. What a report may be about."""
    row = db.get(PromptResponse, response_id)
    prompt = db.get(CirclePrompt, row.prompt_id) if row else None
    membership = db.get(Membership, (prompt.circle_id, user.id)) if prompt else None
    if (
        membership is None
        or not journal.revealed(prompt.week_start, now)
        or prompt.week_start < _first_week(membership)
    ):
        return None
    return row


def delete_answers(db: Session, answers) -> None:
    """Delete answers. A report about one outlives it, so it can still be
    closed, but no longer points at words that are gone."""
    for row in answers:
        db.execute(update(Report).where(Report.response_id == row.id).values(response_id=None))
        db.delete(row)
