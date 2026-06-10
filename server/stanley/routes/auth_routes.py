from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from .. import auth
from ..deps import get_clock, get_db, get_settings
from ..models import User

router = APIRouter(tags=["auth"])


class DevAuthBody(BaseModel):
    display_name: str = Field(min_length=1, max_length=80)


@router.post("/auth/dev", status_code=201)
def dev_auth(body: DevAuthBody, db: Session = Depends(get_db), settings=Depends(get_settings), clock=Depends(get_clock)):
    """Pilot-stage auth. Disabled unless STANLEY_DEV_AUTH=1."""
    if not settings.dev_auth:
        raise HTTPException(403, "dev auth disabled")
    now = clock.now()
    user = User(display_name=body.display_name, created_at=now)
    db.add(user)
    db.flush()
    token = auth.issue_token(settings.secret_key, user.id, now)
    return {"token": token, "user": {"id": user.id, "display_name": user.display_name}}


@router.post("/auth/apple", status_code=501)
def apple_auth():
    """Sign in with Apple is the only production auth (§9). Token verification
    against Apple's JWKS is required before any non-dev deployment."""
    raise HTTPException(501, "Sign in with Apple verification not yet implemented")
