"""The operator's side of a report (the production audit, November 2026).

The Terms promise every report is read within a day and that content which
breaks them is removed. Until this there was no way to do the removing short
of editing the database by hand. This is that way, run on the server:

    fly ssh console -C "/app/.venv/bin/python -m stanley.moderation list"
    ... show <report id>          the report, and a 15-minute link to the photo
    ... photo <photo id> [--preserve /data/evidence]   take a photo down
    ... story <story id>          take a story down
    ... answer <answer id>        take down an answer to the circle's question
    ... note <note id>            take a note off a circle's board
    ... circle-letter <letter id> take down an anonymous letter to a circle
    ... letter <letter id>        take a letter away (build 42)
    ... page <page id>            take a page out of a shared journal (build
                                  51): it goes back to its writer's own book
    ... resolve <report id>       close a report that needed nothing removed
    ... account <user id>         end an account (the Terms, section 6)

Taking a photo down is the owner's own delete (`decay.scrub`, the subject
wins): the image goes everywhere at once, holders keep "a memory was here"
and their own words. With `--preserve`, the photo's files and what's known
about it are copied to a folder first, for the one case where the law
requires keeping it: child sexual abuse material must be reported to NCMEC
and preserved for a year (18 U.S.C. 2258A), never deleted outright and never
looked at more than needed (PRODUCTION_CHECKLIST.md, CSAM). Every action
resolves the reports about what it removed and logs one event line.
"""
from __future__ import annotations

import argparse
import json
import logging
import shutil
from datetime import datetime
from pathlib import Path

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from . import physics, sharing
from .decay import delete_comments, scrub
from .models import (
    CircleLetter, CircleNote, CirclePrompt, Comment, JournalPage, PersonLetter, Photo, PromptResponse, Report,
    User,
)

log = logging.getLogger("stanley")


def open_reports(session: Session) -> list[Report]:
    """Reports nobody has closed, oldest first: the order the 24 hours run out."""
    return list(
        session.scalars(select(Report).where(Report.resolved_at.is_(None)).order_by(Report.created_at)).all()
    )


def _resolve_about(
    session: Session,
    now: datetime,
    *,
    photo_id: str | None = None,
    comment_id: str | None = None,
    response_id: str | None = None,
) -> int:
    conditions = []
    if photo_id:
        conditions.append(Report.photo_id == photo_id)
    if comment_id:
        conditions.append(Report.comment_id == comment_id)
    if response_id:
        conditions.append(Report.response_id == response_id)
    reports = session.scalars(
        select(Report).where(Report.resolved_at.is_(None), or_(*conditions))
    ).all()
    for report in reports:
        report.resolved_at = now
    return len(reports)


def resolve(session: Session, report_id: str, now: datetime) -> bool:
    report = session.get(Report, report_id)
    if report is None or report.resolved_at is not None:
        return False
    report.resolved_at = now
    log.info("event=report_resolved report=%s", report_id)
    return True


def preserve_photo(session: Session, storage, photo: Photo, folder: str) -> Path:
    """Copy a photo's files and facts aside before it's taken down. The
    folder should be on the encrypted volume, readable only by the operator."""
    dest = Path(folder) / photo.id
    dest.mkdir(parents=True, exist_ok=True)
    for key in (photo.blob_key, photo.deriv_key, photo.thumb_key):
        if key and storage.exists(key):
            (dest / key.split("/")[-1]).write_bytes(storage.get(key))
    owner = session.get(User, photo.owner_id) if photo.owner_id else None
    facts = {
        "photo_id": photo.id,
        "owner_id": photo.owner_id,
        # What Stanley knows of who posted it, kept before an account is
        # ended, since ending it erases these. There is no email, no phone
        # and no IP address to give: Stanley never keeps them.
        "owner_display_name": owner.display_name if owner else None,
        "owner_username": owner.username if owner else None,
        "owner_since": owner.created_at.isoformat() if owner else None,
        "circle_id": photo.circle_id,
        "taken_at": photo.taken_at.isoformat(),
        "created_at": photo.created_at.isoformat(),
        "taken_tz": photo.taken_tz,
        "caption": photo.caption,
        "location": photo.location,
        "reports": [
            {"id": r.id, "reporter_id": r.reporter_id, "reason": r.reason, "created_at": r.created_at.isoformat()}
            for r in session.scalars(select(Report).where(Report.photo_id == photo.id)).all()
        ],
    }
    (dest / "facts.json").write_text(json.dumps(facts, indent=2))
    return dest


def take_down_photo(
    session: Session, storage, photo_id: str, now: datetime, preserve: str | None = None
) -> bool:
    photo = session.get(Photo, photo_id)
    if photo is None or photo.state == physics.PURGED:
        return False
    if preserve:
        preserve_photo(session, storage, photo, preserve)
    scrub(session, storage, photo, now, owner_requested=True)
    resolved = _resolve_about(session, now, photo_id=photo_id)
    log.warning("event=photo_taken_down photo=%s preserved=%s reports_resolved=%d",
                photo_id, "yes" if preserve else "no", resolved)
    return True


def take_down_story(session: Session, comment_id: str, now: datetime) -> bool:
    comment = session.get(Comment, comment_id)
    if comment is None:
        return False
    photo_id = comment.photo_id
    # Resolve first: deleting the story re-points its reports at the photo.
    resolved = _resolve_about(session, now, comment_id=comment_id)
    delete_comments(session, [comment])
    log.warning("event=story_taken_down photo=%s reports_resolved=%d", photo_id, resolved)
    return True


def take_down_answer(session: Session, response_id: str, now: datetime) -> bool:
    """An answer to a circle's question, removed for everyone (build 26)."""
    from .routes.journal import delete_answers

    row = session.get(PromptResponse, response_id)
    if row is None:
        return False
    resolved = _resolve_about(session, now, response_id=response_id)
    delete_answers(session, [row])
    log.warning("event=answer_taken_down reports_resolved=%d", resolved)
    return True


def take_down_letter(session: Session, letter_id: str, now: datetime) -> bool:
    """A letter (build 42), removed for everyone. The reports about it
    detach (set null) so a report can still be closed."""
    letter = session.get(PersonLetter, letter_id)
    if letter is None:
        return False
    reports = session.scalars(
        select(Report).where(Report.resolved_at.is_(None), Report.letter_id == letter_id)
    ).all()
    for report in reports:
        report.resolved_at = now
    session.execute(
        Report.__table__.update().where(Report.letter_id == letter_id).values(letter_id=None)
    )
    session.delete(letter)
    log.warning("event=letter_taken_down reports_resolved=%d", len(reports))
    return True


def take_down_note(session: Session, note_id: str, now: datetime) -> bool:
    """A note off a circle's board, for everyone (build 27). The reports about
    it keep their copy of its words."""
    note = session.get(CircleNote, note_id)
    if note is None:
        return False
    reports = session.scalars(
        select(Report).where(Report.resolved_at.is_(None), Report.note_id == note_id)
    ).all()
    for report in reports:
        report.resolved_at = now
    session.delete(note)
    log.warning("event=note_taken_down reports_resolved=%d", len(reports))
    return True


def take_down_circle_letter(session: Session, letter_id: str, now: datetime) -> bool:
    """An anonymous letter to a circle, removed for everyone (build 42). The
    reports about it keep their copy of its words and who wrote them."""
    letter = session.get(CircleLetter, letter_id)
    if letter is None:
        return False
    reports = session.scalars(
        select(Report).where(Report.resolved_at.is_(None), Report.circle_letter_id == letter_id)
    ).all()
    for report in reports:
        report.resolved_at = now
    session.delete(letter)
    session.flush()
    log.warning("event=circle_letter_taken_down reports_resolved=%d", len(reports))
    return True


def take_down_page(session: Session, page_id: str, now: datetime) -> bool:
    """A page taken out of a circle's shared journal (build 51). It isn't
    deleted: it goes back to being its writer's alone, in their own book,
    and the hearts left on it go. The reports about it keep who wrote it
    and how it began."""
    page = session.get(JournalPage, page_id)
    if page is None:
        return False
    reports = session.scalars(
        select(Report).where(Report.resolved_at.is_(None), Report.page_id == page_id)
    ).all()
    for report in reports:
        report.resolved_at = now
    sharing.unshare(session, [page.id])
    session.flush()
    log.warning("event=page_taken_down reports_resolved=%d", len(reports))
    return True


def _about(r: Report) -> str:
    if r.page_id:
        return f"shared page {r.page_id}"
    if r.circle_letter_id:
        return f"circle letter {r.circle_letter_id}"
    if r.note_id:
        return f"note {r.note_id}"
    if r.comment_id:
        return f"story {r.comment_id}"
    if r.response_id:
        return f"answer {r.response_id}"
    if r.letter_id:
        return f"letter {r.letter_id}"
    if r.photo_id:
        return f"photo {r.photo_id}"
    return "(what it was about is gone)"


class _At:
    def __init__(self, now: datetime):
        self._now = now

    def now(self) -> datetime:
        return self._now


def terminate_account(session: Session, storage, user_id: str, now: datetime) -> bool:
    """End someone's account for breaking the Terms: exactly what deleting
    it themselves does (everything of theirs erased, their photos removed
    from holders too), run by the operator. It doesn't stop them signing in
    with Apple again as a new, empty account; a lasting ban would need a list
    of refused Apple ids, which Stanley doesn't keep."""
    from .routes.me import delete_account

    user = session.get(User, user_id)
    if user is None or user.deleted_at is not None:
        return False
    delete_account(db=session, user=user, clock=_At(now), storage=storage)
    log.warning("event=account_terminated user=%s", user_id)
    return True


def _main(argv: list[str] | None = None) -> int:  # pragma: no cover - a thin shell over the above
    from .clock import SystemClock
    from .config import Settings, resolve_secret
    from .db import make_engine, make_sessionmaker
    from .storage import make_blob_store, read_url

    parser = argparse.ArgumentParser(prog="python -m stanley.moderation", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    show = sub.add_parser("show")
    show.add_argument("report")
    show.add_argument("--host", default="https://server-earnest-stream-9793.fly.dev")
    photo = sub.add_parser("photo")
    photo.add_argument("photo")
    photo.add_argument("--preserve", help="copy the photo and its facts here first (CSAM: required)")
    story = sub.add_parser("story")
    story.add_argument("story")
    answer = sub.add_parser("answer")
    answer.add_argument("answer")
    note = sub.add_parser("note")
    note.add_argument("note")
    circle_letter = sub.add_parser("circle-letter")
    circle_letter.add_argument("letter")
    letter = sub.add_parser("letter")
    letter.add_argument("letter")
    page = sub.add_parser("page")
    page.add_argument("page")
    res = sub.add_parser("resolve")
    res.add_argument("report")
    acct = sub.add_parser("account")
    acct.add_argument("user")
    args = parser.parse_args(argv)

    settings = Settings()
    settings.secret_key = resolve_secret(settings)
    session = make_sessionmaker(make_engine(settings.database_url))()
    storage = make_blob_store(settings)
    now = SystemClock().now()
    with session:
        if args.cmd == "list":
            for r in open_reports(session):
                print(f"{r.id}  {r.created_at:%Y-%m-%d %H:%M}Z  {_about(r)}  {r.reason[:60]!r}")
            return 0
        if args.cmd == "show":
            r = session.get(Report, args.report)
            if r is None:
                print("no such report")
                return 1
            print(f"report {r.id} by {r.reporter_id} at {r.created_at:%Y-%m-%d %H:%M}Z\nreason: {r.reason}")
            if r.comment_id:
                c = session.get(Comment, r.comment_id)
                print(f"story {r.comment_id}: {c.body if c else '(gone)'}")
            if r.response_id:
                a = session.get(PromptResponse, r.response_id)
                q = session.get(CirclePrompt, a.prompt_id) if a else None
                print(f"answer {r.response_id} by {a.user_id if a else '?'}: {a.body if a else '(gone)'}")
                if q is not None:
                    print(f"to the question of the week of {q.week_start} in circle {q.circle_id}: {q.prompt}")
            if r.circle_letter_id:
                # Unsigned to its circle; the operator sees who wrote it,
                # here and in the report's own copy above.
                letter = session.get(CircleLetter, r.circle_letter_id)
                if letter is None:
                    print(f"letter {r.circle_letter_id}: (gone; the report above kept its words and its writer)")
                else:
                    print(
                        f"letter {letter.id} by {letter.author_id} to circle {letter.circle_id} "
                        f"for {letter.month:%Y-%m}: {letter.body}"
                    )
            if r.page_id:
                pg = session.get(JournalPage, r.page_id)
                if pg is None or not pg.shared:
                    print(f"shared page {r.page_id}: (taken back or torn out; the report above kept how it began)")
                else:
                    print(f"shared page {pg.id} by {pg.owner_id} in circle {pg.circle_id} for {pg.day}")
                    print(f"body: {pg.body}")
            if r.letter_id:
                le = session.get(PersonLetter, r.letter_id)
                if le is None:
                    print(f"letter {r.letter_id}: (gone)")
                else:
                    print(f"letter {r.letter_id} from {le.sender_id} to {le.recipient_id} for {le.deliver_at}")
                    print(f"occasion: {le.occasion!r}\nbody: {le.body}")
            p = session.get(Photo, r.photo_id) if r.photo_id else None
            if p is not None:
                print(f"photo {p.id} state {p.state} caption {p.caption!r}")
                if p.deriv_key:
                    print("view (15 minutes):", args.host + read_url(settings, p.deriv_key, now))
            return 0
        if args.cmd == "photo":
            ok = take_down_photo(session, storage, args.photo, now, args.preserve)
        elif args.cmd == "story":
            ok = take_down_story(session, args.story, now)
        elif args.cmd == "answer":
            ok = take_down_answer(session, args.answer, now)
        elif args.cmd == "note":
            ok = take_down_note(session, args.note, now)
        elif args.cmd == "circle-letter":
            ok = take_down_circle_letter(session, args.letter, now)
        elif args.cmd == "letter":
            ok = take_down_letter(session, args.letter, now)
        elif args.cmd == "page":
            ok = take_down_page(session, args.page, now)
        elif args.cmd == "account":
            ok = terminate_account(session, storage, args.user, now)
        else:
            ok = resolve(session, args.report, now)
        session.commit()
        print("done" if ok else "nothing to do (not found, or already gone)")
        return 0 if ok else 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(_main())
