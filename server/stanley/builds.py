"""Which builds of the app still connect (build 77), so code kept for old
builds can be retired on evidence rather than guesswork.

The app's own User-Agent says its build: URLSession sends "Stanley/76
CFNetwork/... Darwin/...", the app's name and CFBundleVersion, from every
build ever shipped, with no change to the app. The server keeps one row per
build number with when it was first and last seen, and nothing about who:
no account, no address, no count of anyone. At most one write an hour per
build, off the event loop.

    sqlite3 /data/var/stanley.db "SELECT * FROM client_builds ORDER BY build"
"""
from __future__ import annotations

import asyncio
import logging
import re
import time

from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from .models import ClientBuild

log = logging.getLogger("stanley.builds")

_AGENT = re.compile(rb"^Stanley/(\d{1,6})\b")
# How often a build's row is touched, at most.
WRITE_EVERY = 3600.0


def build_from(agent: bytes | None) -> int | None:
    """The build number in a User-Agent of the app's, or None."""
    if not agent:
        return None
    match = _AGENT.match(agent)
    return int(match.group(1)) if match else None


class BuildSeen:
    """A plain ASGI middleware: notes the app's build from each request's
    User-Agent, never changing the request or holding it up."""

    def __init__(self, app):
        self.app = app
        self._written: dict[int, float] = {}

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            agent = dict(scope.get("headers") or []).get(b"user-agent")
            build = build_from(agent)
            if build is not None:
                now = time.monotonic()
                last = self._written.get(build)
                if last is None or now - last >= WRITE_EVERY:
                    self._written[build] = now
                    if last is None:
                        log.info("event=build_seen build=%d", build)
                    app = scope.get("app")
                    if app is not None:
                        asyncio.get_running_loop().run_in_executor(None, _touch, app, build)
        await self.app(scope, receive, send)


def _touch(app, build: int) -> None:
    try:
        now = app.state.clock.now()
        with app.state.sessionmaker() as session:
            session.execute(
                sqlite_insert(ClientBuild)
                .values(build=build, first_seen=now, last_seen=now)
                .on_conflict_do_update(index_elements=["build"], set_={"last_seen": now})
            )
            session.commit()
    except Exception:  # never let bookkeeping touch a request
        log.exception("event=build_seen_failed build=%d", build)
