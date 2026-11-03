from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import auth
from ..apple import AppleAuthError
from ..deps import event, get_apple_verifier, get_clock, get_current_user, get_db, get_settings
from ..models import User
from ..ratelimit import per_ip
from ..text import clean_optional

router = APIRouter(tags=["auth"])


class DevAuthBody(BaseModel):
    display_name: str = Field(min_length=1, max_length=80)


class AppleAuthBody(BaseModel):
    # An Apple identity token is a JWT of about a kilobyte; anything past
    # eight is not one, and isn't worth decoding.
    identity_token: str = Field(min_length=1, max_length=8192)
    # Apple includes the name only on the FIRST authorization, in the client
    # payload (not the token). Forwarded here so we can store it once.
    name: str | None = Field(default=None, max_length=80)


@router.post("/auth/dev", status_code=201, dependencies=[per_ip("auth")])
def dev_auth(body: DevAuthBody, db: Session = Depends(get_db, scope="function"), settings=Depends(get_settings), clock=Depends(get_clock)):
    """Pilot-stage auth. Returns 404 unless STANLEY_DEV_AUTH=1 — in a real
    deployment this endpoint does not exist."""
    if not settings.dev_auth:
        raise HTTPException(404, "not found")
    now = clock.now()
    # Idempotent by name (dev only): signing in with the same display name
    # returns the same dev account. This lets a seeded demo user — and repeat
    # sign-ins — resolve to one stable identity, the way Apple's `sub` does in
    # production. Only dev users (apple_sub IS NULL) are matched.
    user = db.scalars(
        select(User).where(
            User.display_name == body.display_name,
            User.apple_sub.is_(None),
            User.deleted_at.is_(None),
        )
    ).first()
    new_account = user is None
    if new_account:
        user = User(display_name=clean_optional(body.display_name), created_at=now)
        db.add(user)
        db.flush()
        event("signup", user=user.id, via="dev")
    return _signed_in(settings, user, now, new_account)


@router.post("/auth/apple", status_code=201, dependencies=[per_ip("auth")])
def apple_auth(
    body: AppleAuthBody,
    db: Session = Depends(get_db, scope="function"),
    settings=Depends(get_settings),
    clock=Depends(get_clock),
    verifier=Depends(get_apple_verifier),
):
    """Sign in with Apple (§9). Verify Apple's identity token, then create or
    look up the user by the stable `sub`, and return a Stanley JWT."""
    if verifier is None:
        raise HTTPException(503, {"code": "apple_auth_unconfigured"})
    try:
        claims = verifier.verify(body.identity_token)
    except AppleAuthError:
        raise HTTPException(401, {"code": "invalid_apple_token"})

    sub = claims.get("sub")
    if not sub:
        raise HTTPException(401, {"code": "invalid_apple_token"})

    now = clock.now()
    user = db.scalars(select(User).where(User.apple_sub == sub)).first()
    new_account = user is None
    if new_account:
        # First sign-in: this is the only time Apple gives us the name.
        name = clean_optional(body.name)
        user = User(apple_sub=sub, display_name=name, created_at=now)
        db.add(user)
        db.flush()
        event("signup", user=user.id, via="apple")
    return _signed_in(settings, user, now, new_account)


@router.post("/auth/refresh")
def refresh(
    user: User = Depends(get_current_user),
    settings=Depends(get_settings),
    clock=Depends(get_clock),
):
    """A fresh thirty-day token for a sign-in that still works (the
    production audit). The app asks once a day while it's in use, so someone
    who opens Stanley at least once a month is never signed out by the
    clock; a phone left unopened for thirty days is, and signs in again.
    An expired or refused token can't be refreshed: it's a 401, as anywhere."""
    return {"token": auth.issue_token(settings.secret_key, user.id, clock.now())}


def _signed_in(settings, user: User, now, new_account: bool) -> dict:
    """A Stanley token, and whether this sign-in made the account: the app
    walks a new account through setup (name, username, words, face) before
    the circle gate. Nothing else about the account is said here."""
    token = auth.issue_token(settings.secret_key, user.id, now)
    return {
        "token": token,
        "user": {"id": user.id, "display_name": user.display_name},
        "new_account": new_account,
    }
