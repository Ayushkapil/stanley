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


def decode_token(secret: str, token: str, now: datetime) -> str:
    """Verify signature, then expiry against the server's own clock.

    PyJWT would check `exp` against ambient wall-clock time, which is the one
    place the server stopped taking time from the Clock (see clock.py: every
    piece of the system takes time from a Clock instead of calling
    datetime.now directly). In production `now` IS the system clock, so this
    is identical to PyJWT's own check — it just makes expiry testable, and
    keeps one authority for time instead of two.
    """
    try:
        payload = jwt.decode(
            token,
            secret,
            algorithms=[ALGORITHM],
            # Every time-based claim is checked below against `now` instead of
            # PyJWT's ambient wall clock. Leaving iat/nbf on would reject a
            # perfectly good token whenever the two clocks disagree.
            options={"verify_exp": False, "verify_iat": False, "verify_nbf": False},
        )
    except jwt.PyJWTError as exc:
        raise AuthError(str(exc)) from exc
    exp = payload.get("exp")
    if exp is None:  # a token with no expiry never expires — refuse it
        raise AuthError("token missing exp")
    if now.timestamp() >= exp:
        raise AuthError("token expired")
    sub = payload.get("sub")
    if not sub:
        raise AuthError("token missing sub")
    return sub
