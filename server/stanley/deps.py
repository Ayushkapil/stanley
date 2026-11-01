from __future__ import annotations

from fastapi import Depends, Header, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import auth
from .models import Circle, Membership, Photo, User
from .serialize import blocked_ids

_bearer = HTTPBearer(auto_error=False)


def get_settings(request: Request):
    return request.app.state.settings


def get_clock(request: Request):
    return request.app.state.clock


def get_storage(request: Request):
    return request.app.state.storage


def get_notifier(request: Request):
    return request.app.state.notifier


def get_apple_verifier(request: Request):
    return request.app.state.apple_verifier


def get_db(request: Request):
    """One session per request, committed when the endpoint returns.

    Every route takes it as `Depends(get_db, scope="function")`. That scope
    runs this teardown, and so the commit, before the response is sent.
    Under the default scope it ran after the response and after any
    background task. Capture defers the full-size original's encode to a
    background task, so the new photo stayed uncommitted for the second that
    took, and the app's own Today refresh, sent the moment the POST
    answered, read a feed without it. It also meant a 2xx could go out
    before the write was durable. `test_every_route_commits_before_it_answers`
    keeps any route from going back to the default."""
    session: Session = request.app.state.sessionmaker()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db, scope="function"),
    settings=Depends(get_settings),
    clock=Depends(get_clock),
) -> User:
    if creds is None:
        raise HTTPException(401, "missing bearer token")
    try:
        user_id = auth.decode_token(settings.secret_key, creds.credentials, clock.now())
    except auth.AuthError:
        raise HTTPException(401, "invalid token")
    user = db.get(User, user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(401, "unknown user")
    return user


def active_circle_id(
    circle: str | None = Header(default=None, alias="X-Stanley-Circle"),
) -> str | None:
    """The circle the app is showing, which it sends with every request.
    A person can be in more than one circle (build 17), and Today, capture,
    the roster and the note are each about one of them. A header rather than
    a query item, like the town for the news, so it stays out of access
    logs; it carries no more than an id the person already belongs to."""
    return circle or None


def require_membership(
    db: Session, user: User, circle_id: str | None = None
) -> tuple[Membership, Circle]:
    """The person's place in the circle this request is about.

    `circle_id` is the active circle the app sent. Without one, it's the
    circle they joined first: a build from before multiple circles never
    sends one, and it keeps seeing the only circle it knows about. Naming a
    circle they aren't in (they left it, or were removed, on another phone)
    is `not_in_circle`, never a quiet switch to another one: a photo meant
    for one circle must never land in a different one."""
    query = select(Membership).where(Membership.user_id == user.id)
    if circle_id:
        query = query.where(Membership.circle_id == circle_id)
    membership = db.scalars(
        query.order_by(Membership.joined_at, Membership.circle_id)
    ).first()
    if membership is None:
        if circle_id and my_circle_ids(db, user.id):
            raise HTTPException(409, {"code": "not_in_circle"})
        raise HTTPException(409, {"code": "no_circle", "message": "join a circle first"})
    circle = db.get(Circle, membership.circle_id)
    return membership, circle


def membership_in(db: Session, user: User, circle_id: str) -> tuple[Membership, Circle]:
    """The person's place in a circle named in the path. Not a member reads
    as not found: a circle you aren't in doesn't exist, as far as you can
    tell. Someone in no circle at all hears `no_circle`, as everywhere."""
    membership = db.get(Membership, (circle_id, user.id))
    if membership is None:
        if not my_circle_ids(db, user.id):
            raise HTTPException(409, {"code": "no_circle", "message": "join a circle first"})
        raise HTTPException(404, "not found")
    return membership, db.get(Circle, circle_id)


def my_circle_ids(db: Session, user_id: str) -> set[str]:
    return set(
        db.scalars(select(Membership.circle_id).where(Membership.user_id == user_id)).all()
    )


def shares_a_circle(db: Session, user_id: str, other_id: str) -> bool:
    """Whether two people are in any circle together. That's who may see a
    profile, or block: someone met in one circle, wherever you're looking."""
    mine = my_circle_ids(db, user_id)
    return bool(mine) and db.scalars(
        select(Membership.circle_id).where(
            Membership.user_id == other_id, Membership.circle_id.in_(mine)
        )
    ).first() is not None


def member_count(db: Session, circle_id: str) -> int:
    return db.scalar(
        select(func.count()).select_from(Membership).where(Membership.circle_id == circle_id)
    )


def get_circle_photo(db: Session, user: User, photo_id: str) -> Photo:
    """A photo is reachable only from inside its circle, minus blocked pairs:
    any circle the person is in, not just the one on screen, so a memory
    opened from Held or Returned still takes a story. Any failure is a
    uniform 404 — existence is not leaked."""
    mine = my_circle_ids(db, user.id)
    if not mine:
        raise HTTPException(409, {"code": "no_circle", "message": "join a circle first"})
    photo = db.get(Photo, photo_id)
    if photo is None or photo.circle_id not in mine:
        raise HTTPException(404, "not found")
    if photo.owner_id is not None and photo.owner_id in blocked_ids(db, user.id):
        raise HTTPException(404, "not found")
    return photo
