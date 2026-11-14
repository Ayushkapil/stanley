"""The shared journal (build 51): pages a person has put in a circle's book.

A journal page is its writer's alone until they share it with a circle
(`journal_pages.shared`, `circle_id`); then that circle reads it, in a book
of facing pages, and each reader may leave one heart on it. This module is
the part other routes need: taking a page (or someone's pages) back out of
a circle's book, and whether a reader may see a page at all.

Since build 52 a page can be shared with one person in the circle instead
of all of it (`recipient_id`): its writer and that person read it, nobody
else, and it's never paired on a spread. The routes
themselves are in `routes/journal.py`; who faces whom on a day is
`journal.pairings`.
"""
from __future__ import annotations

from datetime import date

from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from . import journal
from .models import JournalPage, Membership, PageHeart, User
from .serialize import blocked_ids


def joined_day(membership: Membership, user: User) -> date:
    """The first day of a circle's book someone reads: the day they joined,
    on their own calendar (as the circle's questions are read from the week
    they joined). What was shared before they were there wasn't shared with
    them."""
    return journal.local_day(membership.joined_at, user.tz_last_seen or "UTC")


def drop_hearts(db: Session, page_id: str) -> None:
    """The hearts left on a page where it was: it's going somewhere else
    (another circle's book, one person, or back to its writer alone)."""
    db.execute(delete(PageHeart).where(PageHeart.page_id == page_id))


def unshare(db: Session, page_ids: list[str]) -> None:
    """Pages going back to being their writer's alone. The hearts left on
    them go: they were left on a page in the circle's book (or by the one
    person it was shared with)."""
    if not page_ids:
        return
    db.execute(delete(PageHeart).where(PageHeart.page_id.in_(page_ids)))
    db.execute(
        update(JournalPage)
        .where(JournalPage.id.in_(page_ids))
        .values(shared=False, circle_id=None, recipient_id=None)
        .execution_options(synchronize_session="fetch")
    )


def leave_book(db: Session, circle_id: str, user_id: str) -> None:
    """Someone going from a circle (leaving, or removed): their pages come
    out of its book and stay in their own, the pages written to them alone
    there go back to their writers' (build 52), and the hearts they left on
    its pages go with them."""
    theirs = db.scalars(
        select(JournalPage.id).where(
            JournalPage.circle_id == circle_id,
            (JournalPage.owner_id == user_id) | (JournalPage.recipient_id == user_id),
        )
    ).all()
    unshare(db, list(theirs))
    in_book = select(JournalPage.id).where(JournalPage.circle_id == circle_id, JournalPage.shared.is_(True))
    db.execute(delete(PageHeart).where(PageHeart.user_id == user_id, PageHeart.page_id.in_(in_book)))


def forget_person(db: Session, user_id: str) -> None:
    """An account being deleted: every heart they left, and every heart
    left on their pages, before the pages themselves go. A page someone
    wrote to them alone goes back to its writer's (build 52)."""
    to_them = db.scalars(select(JournalPage.id).where(JournalPage.recipient_id == user_id)).all()
    unshare(db, list(to_them))
    theirs = select(JournalPage.id).where(JournalPage.owner_id == user_id)
    db.execute(delete(PageHeart).where((PageHeart.user_id == user_id) | PageHeart.page_id.in_(theirs)))


def readable_page(db: Session, user: User, page_id: str) -> JournalPage | None:
    """A shared page this person can read. One in a circle's book: in a
    circle they're in, from a day they were there for, by someone no block
    stands between (their own included). One shared with a person (build
    52): its writer and that person only, whatever day they joined, while
    no block stands between them. Anything else doesn't exist, as far as
    they can tell."""
    row = db.get(JournalPage, page_id)
    if row is None or not row.shared or row.circle_id is None:
        return None
    membership = db.get(Membership, (row.circle_id, user.id))
    if membership is None:
        return None
    blocked = blocked_ids(db, user.id)
    if row.recipient_id is not None:
        if user.id not in (row.owner_id, row.recipient_id):
            return None
        if row.owner_id in blocked or row.recipient_id in blocked:
            return None
        return row
    if row.day < joined_day(membership, user):
        return None
    if row.owner_id in blocked:
        return None
    return row
