from __future__ import annotations

import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI

from . import __version__, decay, notifications
from .apple import AppleVerifier
from .backup import backup_database
from .clock import Clock, SystemClock
from .config import Settings, resolve_secret
from .db import Base, ensure_schema, make_engine, make_sessionmaker
from .notifications import Notifier
from .routes import auth_routes, blobs, circles, feed, me, memories, photos, safety
from .storage import make_blob_store

log = logging.getLogger("stanley")


def tick(app: FastAPI) -> None:
    """One worker pass: decay sweep, purges, digests (§13, §10), and a once-a-day
    backup (C2)."""
    settings: Settings = app.state.settings
    with app.state.sessionmaker() as session:
        decay.sweep(session, app.state.clock, app.state.notifier)
        decay.run_purges(session, app.state.storage, app.state.clock)
        notifications.run_evening_digests(
            session, app.state.notifier, app.state.clock, settings.digest_hour
        )
        session.commit()

    today = app.state.clock.now().date()
    if app.state.last_backup_day != today:
        try:
            backup_database(settings.database_url, settings.backups_dir, settings.backups_keep)
            app.state.last_backup_day = today
        except Exception:
            log.exception("daily backup failed")


async def _sweep_loop(app: FastAPI) -> None:
    while True:
        try:
            await asyncio.to_thread(tick, app)
        except Exception:
            log.exception("sweep tick failed")
        await asyncio.sleep(app.state.settings.sweep_interval_seconds)


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

    # C1: refuse to boot without a signing secret (dev auth may use a fallback).
    settings.secret_key = resolve_secret(settings)

    _ensure_sqlite_dir(settings.database_url)
    engine = make_engine(settings.database_url)
    Base.metadata.create_all(engine)
    ensure_schema(engine)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        task = None
        if settings.run_sweeper:
            task = asyncio.create_task(_sweep_loop(app))
        yield
        if task is not None:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task

    app = FastAPI(
        title="Stanley — One Day, One Photo",
        version=__version__,
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.clock = clock
    app.state.engine = engine
    app.state.sessionmaker = make_sessionmaker(engine)
    app.state.storage = make_blob_store(settings)
    app.state.notifier = Notifier()
    app.state.last_backup_day = None

    # Apple verifier: injected (tests) or built from config when a bundle id set.
    if apple_verifier is None and settings.apple_bundle_id:
        apple_verifier = AppleVerifier(
            settings.apple_bundle_id, cache_seconds=settings.apple_jwks_cache_seconds
        )
    app.state.apple_verifier = apple_verifier

    for router in (auth_routes, circles, photos, feed, me, memories, safety, blobs):
        app.include_router(router.router)

    @app.get("/health", tags=["ops"])
    def health() -> dict[str, str]:
        """Unauthenticated readiness probe for the host platform. Deliberately
        touches no database: it answers "this process is up and serving", which
        is the question a load balancer restarts on."""
        return {"status": "ok"}

    return app
