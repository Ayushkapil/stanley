from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import auth
from ..apple import AppleAuthError
from ..deps import get_apple_verifier, get_clock, get_db, get_settings
from ..models import User

router = APIRouter(tags=["auth"])


class DevAuthBody(BaseModel):
    display_name: str = Field(min_length=1, max_length=80)


class AppleAuthBody(BaseModel):
    identity_token: str
    # Apple includes the name only on the FIRST authorization, in the client
    # payload (not the token). Forwarded here so we can store it once.
    name: str | None = Field(default=None, max_length=80)


@router.post("/auth/dev", status_code=201)
def dev_auth(body: DevAuthBody, db: Session = Depends(get_db), settings=Depends(get_settings), clock=Depends(get_clock)):
    """Pilot-stage auth. Returns 404 unless STANLEY_DEV_AUTH=1 — in a real
    deployment this endpoint does not exist."""
    if not settings.dev_auth:
        raise HTTPException(404, "not found")
    now = clock.now()
    user = User(display_name=body.display_name, created_at=now)
    db.add(user)
    db.flush()
    token = auth.issue_token(settings.secret_key, user.id, now)
    return {"token": token, "user": {"id": user.id, "display_name": user.display_name}}


@router.post("/auth/apple", status_code=201)
def apple_auth(
    body: AppleAuthBody,
    db: Session = Depends(get_db),
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
    if user is None:
        # First sign-in: this is the only time Apple gives us the name.
        name = (body.name or "").strip() or None
        user = User(apple_sub=sub, display_name=name, created_at=now)
        db.add(user)
        db.flush()

    token = auth.issue_token(settings.secret_key, user.id, now)
    return {"token": token, "user": {"id": user.id, "display_name": user.display_name}}
