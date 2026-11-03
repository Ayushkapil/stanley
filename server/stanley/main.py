from __future__ import annotations

import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager
from datetime import timedelta
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from sqlalchemy import text
from starlette.datastructures import MutableHeaders

from . import __version__, decay, legal, news, notifications
from .apple import AppleVerifier
from .backup import backup_database, maintain_database, warn_if_disk_low
from .clock import Clock, SystemClock
from .config import Settings, resolve_secret
from .db import Base, ensure_schema, make_engine, make_sessionmaker
from .notifications import make_notifier
from .ratelimit import RateLimiter
from .routes import auth_routes, blobs, circles, feed, me, memories, news as news_routes, photos, safety
from .storage import make_blob_store

log = logging.getLogger("stanley")


def configure_logging() -> None:
    """Stanley's own lines (`stanley` logger) to stdout, which is what `fly
    logs` shows. Uvicorn configures only its own loggers, so until this the
    app's INFO lines (events, backups, APNs) were dropped and only warnings
    reached the host. Once, and never twice: a test suite builds many apps."""
    if log.handlers:
        return
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s stanley: %(message)s"))
    log.addHandler(handler)
    log.setLevel(logging.INFO)
    # Still propagates: under uvicorn the root logger has no handler, so
    # nothing prints twice, and a test's log capture still sees every line.


# Every response says how a browser may treat it. Stanley has no web app: the
# only pages are /terms and /privacy (an inline stylesheet, no scripts), and
# photos are served to the phone, so the policy allows almost nothing.
SECURITY_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"x-frame-options", b"DENY"),
    (b"strict-transport-security", b"max-age=31536000; includeSubDomains"),
    (b"referrer-policy", b"no-referrer"),
    (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
    (b"cross-origin-opener-policy", b"same-origin"),
]
CONTENT_SECURITY_POLICY = (
    b"default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; "
    b"frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
)


class SecurityHeaders:
    """A plain ASGI middleware (not BaseHTTPMiddleware, which would buffer
    every response and complicate background tasks): it adds the headers to
    each response as it starts. The interactive API docs, which exist only
    with dev sign-in on, load Swagger from a CDN, so they're left without
    the content policy."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        docs = scope.get("path", "").startswith(("/docs", "/redoc"))

        async def send_with_headers(message):
            if message["type"] == "http.response.start":
                headers = MutableHeaders(scope=message)
                for name, value in SECURITY_HEADERS:
                    if name.decode() not in headers:
                        headers.append(name.decode(), value.decode())
                if not docs and "content-security-policy" not in headers:
                    headers.append("content-security-policy", CONTENT_SECURITY_POLICY.decode())
            await send(message)

        await self.app(scope, receive, send_with_headers)


def tick(app: FastAPI) -> None:
    """One worker pass: decay sweep, purges, digests (§13, §10), and a once-a-day
    backup (C2) with the database's upkeep.

    Each part stands alone (the production audit). The decay sweep commits
    before the digests run, so a digest that fails (a bad time zone, a push
    that throws) can no longer roll back a pass of fading and purging, which
    would have stopped every photo from fading until it was fixed."""
    settings: Settings = app.state.settings
    with app.state.sessionmaker() as session:
        decay.sweep(session, app.state.clock, app.state.notifier)
        decay.run_purges(session, app.state.storage, app.state.clock)
        session.commit()

    try:
        with app.state.sessionmaker() as session:
            notifications.run_evening_digests(
                session, app.state.notifier, app.state.clock, settings.digest_hour
            )
            session.commit()
    except Exception:
        log.exception("evening digests failed")

    today = app.state.clock.now().date()
    if app.state.last_backup_day != today:
        try:
            backup_database(
                settings.database_url, settings.backups_dir, settings.backups_keep, app.state.clock.now()
            )
            app.state.last_backup_day = today
        except Exception:
            log.exception("daily backup failed")
        try:
            # Optimize daily; vacuum on Sundays (UTC), after that day's backup.
            maintain_database(settings.database_url, vacuum=today.weekday() == 6)
        except Exception:
            log.exception("database maintenance failed")
        try:
            warn_if_disk_low(settings.blob_dir)
        except Exception:
            log.exception("disk check failed")


async def _sweep_loop(app: FastAPI) -> None:
    while True:
        try:
            await asyncio.to_thread(tick, app)
        except Exception:
            log.exception("sweep tick failed")
        await asyncio.sleep(app.state.settings.sweep_interval_seconds)


def refresh_news(app: FastAPI) -> None:
    """One pass of The World Today: refetch the US edition if it isn't cached
    or is due, so it is ready before anyone asks, and drop towns nobody has
    asked about lately. Other editions are fetched when someone asks. This
    runs on its own loop so that a slow feed never delays decay."""
    settings: Settings = app.state.settings
    if not settings.news_enabled:
        return
    with app.state.sessionmaker() as session:
        news.refresh_if_due(
            session,
            app.state.clock,
            timedelta(seconds=settings.news_interval_seconds),
        )
        news.forget_towns(session, app.state.clock.now())
        session.commit()


async def _news_loop(app: FastAPI) -> None:
    while True:
        try:
            await asyncio.to_thread(refresh_news, app)
        except Exception:
            log.exception("news refresh failed")
        await asyncio.sleep(app.state.settings.news_interval_seconds)


def _ensure_sqlite_dir(database_url: str) -> None:
    """Create the directory holding the SQLite file if it isn't there yet. A
    fresh host — or a volume mounted empty on first deploy — has no `var/`, and
    SQLite will not create missing parents. In-memory URLs have no path."""
    prefix = "sqlite:///"
    if not database_url.startswith(prefix):
        return
    path = database_url[len(prefix):]
    if not path or path == ":memory:":
        return
    parent = Path(path).parent
    if str(parent) not in ("", "."):
        parent.mkdir(parents=True, exist_ok=True)


def create_app(
    settings: Settings | None = None,
    clock: Clock | None = None,
    apple_verifier: AppleVerifier | None = None,
) -> FastAPI:
    settings = settings or Settings()
    clock = clock or SystemClock()
    configure_logging()

    # C1: refuse to boot without a signing secret (dev auth may use a fallback).
    settings.secret_key = resolve_secret(settings)

    _ensure_sqlite_dir(settings.database_url)
    engine = make_engine(settings.database_url)
    Base.metadata.create_all(engine)
    ensure_schema(engine)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        tasks = []
        if settings.run_sweeper:
            tasks.append(asyncio.create_task(_sweep_loop(app)))
            # The loop's first pass runs at startup, so an empty cache fills
            # as soon as the server is up rather than half an hour later.
            if settings.news_enabled:
                tasks.append(asyncio.create_task(_news_loop(app)))
        yield
        for task in tasks:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task

    # The interactive docs (/docs, /redoc, /openapi.json) only where dev
    # sign-in is on: a real deployment doesn't publish a map of its API.
    docs = settings.dev_auth
    app = FastAPI(
        title="Stanley — One Day, One Photo",
        version=__version__,
        lifespan=lifespan,
        docs_url="/docs" if docs else None,
        redoc_url="/redoc" if docs else None,
        openapi_url="/openapi.json" if docs else None,
    )
    app.add_middleware(SecurityHeaders)
    app.state.settings = settings
    app.state.rate_limiter = RateLimiter()
    app.state.clock = clock
    app.state.engine = engine
    app.state.sessionmaker = make_sessionmaker(engine)
    app.state.storage = make_blob_store(settings)
    app.state.notifier = make_notifier(settings, app.state.sessionmaker)
    if not settings.apns_configured:
        log.info("APNs isn't configured: notices are logged, not pushed (see DEPLOY.md)")
    app.state.last_backup_day = None

    # Apple verifier: injected (tests) or built from config when a bundle id set.
    if apple_verifier is None and settings.apple_bundle_id:
        apple_verifier = AppleVerifier(
            settings.apple_bundle_id, cache_seconds=settings.apple_jwks_cache_seconds
        )
    app.state.apple_verifier = apple_verifier

    for router in (auth_routes, circles, photos, feed, me, memories, safety, blobs, news_routes):
        app.include_router(router.router)

    @app.exception_handler(Exception)
    async def unexpected(request: Request, exc: Exception) -> JSONResponse:
        """Anything a route didn't expect: a 500 with a code the app turns
        into words, and nothing else. No stack trace, no exception text and
        no SQL ever reaches a client. The traceback goes to the server's
        log, where uvicorn writes it, with one event line naming the route
        (its template, so no ids) for searching."""
        route = request.scope.get("route")
        where = getattr(route, "path", "unknown")
        log.error("event=server_error method=%s route=%s error=%s", request.method, where, type(exc).__name__)
        return JSONResponse({"detail": {"code": "server_error"}}, status_code=500)

    @app.get("/health", tags=["ops"])
    def health():
        """Unauthenticated readiness probe: the process is serving and the
        database answers a read. The app asks it every few seconds while it
        can't reach Stanley, and an uptime monitor asks it every few minutes,
        so it stays one indexed read: a 503 means the database can't be read,
        which is when nothing else works either."""
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1 FROM users LIMIT 1"))
        except Exception:
            log.exception("event=health_failed")
            return JSONResponse({"status": "unavailable"}, status_code=503)
        return {"status": "ok"}

    # The Terms and the Privacy Policy, public: App Store Connect links the
    # privacy policy by URL, and anyone deciding whether to join a circle
    # should be able to read both before signing in.
    @app.get("/terms", response_class=HTMLResponse, tags=["legal"])
    def terms() -> str:
        return legal.page("Terms of Use", legal.TERMS)

    @app.get("/privacy", response_class=HTMLResponse, tags=["legal"])
    def privacy() -> str:
        return legal.page("Privacy Policy", legal.PRIVACY, legal.PRIVACY_EFFECTIVE)

    return app
