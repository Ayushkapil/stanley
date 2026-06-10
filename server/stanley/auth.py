from __future__ import annotations

from datetime import datetime, timedelta

import jwt

TOKEN_TTL_DAYS = 30
ALGORITHM = "HS256"


class AuthError(Exception):
    pass


def issue_token(secret: str, user_id: str, now: datetime) -> str:
    payload = {
        "sub": user_id,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(days=TOKEN_TTL_DAYS)).timestamp()),
    }
    return jwt.encode(payload, secret, algorithm=ALGORITHM)


def decode_token(secret: str, token: str) -> str:
    try:
        payload = jwt.decode(token, secret, algorithms=[ALGORITHM])
    except jwt.PyJWTError as exc:
        raise AuthError(str(exc)) from exc
    sub = payload.get("sub")
    if not sub:
        raise AuthError("token missing sub")
    return sub
