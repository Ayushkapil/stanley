"""Rate limits (the production audit, November 2026).

Stanley's laws already cap what a person can do (one photo a day per circle,
a like is a set membership, not a counter), so these are a backstop against
a script or a stuck client, not a product rule. They live in memory, which
is right for exactly one server process (CLAUDE.md: never more than one
uvicorn worker); a restart forgets them, which costs nothing.

- sign-in: per IP address, since there's no account yet. On Fly the address
  is the `Fly-Client-IP` header Fly's proxy sets (every request arrives from
  the proxy itself); anywhere else, the connection's own. A dorm's Wi-Fi
  can put a whole floor behind one address, so a pilot kickoff where
  everyone signs in at once may want `STANLEY_RATE_AUTH_PER_MINUTE` raised
  for the evening.
- uploads, avatars, stories and reports: per person.

Over the limit is a 429 with `{"code": "slow_down"}` and a Retry-After in
seconds. The app says it in words, and a queued capture just waits for its
next try. Nothing about who was limited is stored, and the IP address is
only ever a key in memory for the window it counts.
"""
from __future__ import annotations

import logging
import math
import threading
from collections import deque
from dataclasses import dataclass

from fastapi import Depends, HTTPException, Request

from .deps import get_current_user
from .models import User

log = logging.getLogger("stanley")


@dataclass(frozen=True)
class Limit:
    bucket: str
    count: int
    seconds: int


class RateLimiter:
    """A sliding window per (bucket, key): at most `count` hits in any
    `seconds`. Thread-safe, since sync endpoints run on a thread pool."""

    # Past this many keys, a hit sweeps out the ones whose windows are empty.
    SWEEP_AT = 10_000

    def __init__(self) -> None:
        self._hits: dict[tuple[str, str], deque[float]] = {}
        self._lock = threading.Lock()

    def hit(self, limit: Limit, key: str, now: float) -> float | None:
        """Count one hit. None if it's allowed; otherwise how many seconds
        until the oldest hit in the window ages out."""
        with self._lock:
            if len(self._hits) > self.SWEEP_AT:
                self._sweep(now)
            window = self._hits.setdefault((limit.bucket, key), deque())
            while window and window[0] <= now - limit.seconds:
                window.popleft()
            if len(window) >= limit.count:
                return max(0.0, window[0] + limit.seconds - now)
            window.append(now)
            return None

    def _sweep(self, now: float) -> None:
        # The longest window any limit uses; a key idle that long is empty.
        stale = [k for k, w in self._hits.items() if not w or w[-1] <= now - 3600]
        for k in stale:
            del self._hits[k]

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


def client_ip(request: Request) -> str:
    """Where the request came from. Behind Fly's proxy, the proxy is the
    connection, and Fly names the real client in `Fly-Client-IP`, which it
    sets itself (a client can't forge it through the proxy). Trusted only
    when running on Fly, so nothing else can pass one in."""
    if request.app.state.settings.trust_fly_client_ip:
        forwarded = request.headers.get("fly-client-ip", "").strip()
        if forwarded:
            return forwarded
    return request.client.host if request.client else "unknown"


def _check(request: Request, limit: Limit, key: str) -> None:
    settings = request.app.state.settings
    if not settings.rate_limits:
        return
    now = request.app.state.clock.now().timestamp()
    wait = request.app.state.rate_limiter.hit(limit, key, now)
    if wait is None:
        return
    log.warning("event=rate_limited bucket=%s", limit.bucket)
    raise HTTPException(
        429, {"code": "slow_down"}, headers={"Retry-After": str(max(1, math.ceil(wait)))}
    )


def _limits(request: Request) -> dict[str, Limit]:
    s = request.app.state.settings
    return {
        "auth": Limit("auth", s.rate_auth_per_minute, 60),
        "upload": Limit("upload", s.rate_uploads_per_hour, 3600),
        "avatar": Limit("avatar", s.rate_avatars_per_hour, 3600),
        "story": Limit("story", s.rate_stories_per_hour, 3600),
        "report": Limit("report", s.rate_reports_per_hour, 3600),
    }


def per_ip(bucket: str):
    """A dependency that counts this request against `bucket` for its IP."""

    def dependency(request: Request) -> None:
        _check(request, _limits(request)[bucket], client_ip(request))

    return Depends(dependency)


def per_person(bucket: str):
    """A dependency that counts this request against `bucket` for whoever
    is signed in. It reuses the request's own `get_current_user`, so the
    token is checked once."""

    def dependency(request: Request, user: User = Depends(get_current_user)) -> None:
        _check(request, _limits(request)[bucket], user.id)

    return Depends(dependency)
