from __future__ import annotations

from fastapi import Depends, HTTPException, Request
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


def require_membership(db: Session, user: User) -> tuple[Membership, Circle]:
    membership = db.scalars(
        select(Membership).where(Membership.user_id == user.id)
    ).first()
    if membership is None:
        raise HTTPException(409, {"code": "no_circle", "message": "join a circle first"})
    circle = db.get(Circle, membership.circle_id)
    return membership, circle


def member_count(db: Session, circle_id: str) -> int:
    return db.scalar(
        select(func.count()).select_from(Membership).where(Membership.circle_id == circle_id)
    )


def get_circle_photo(db: Session, user: User, photo_id: str) -> Photo:
    """A photo is reachable only inside its circle, minus blocked pairs. Any
    failure is a uniform 404 — existence is not leaked."""
    membership, _ = require_membership(db, user)
    photo = db.get(Photo, photo_id)
    if photo is None or photo.circle_id != membership.circle_id:
        raise HTTPException(404, "not found")
    if photo.owner_id is not None and photo.owner_id in blocked_ids(db, user.id):
        raise HTTPException(404, "not found")
    return photo
