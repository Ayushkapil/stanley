from __future__ import annotations

import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from . import __version__, decay, notifications
from .clock import Clock, SystemClock
from .config import Settings
from .db import Base, ensure_schema, make_engine, make_sessionmaker
from .notifications import Notifier
from .routes import auth_routes, blobs, circles, feed, me, memories, photos, safety
from .storage import BlobStore

log = logging.getLogger("stanley")


def tick(app: FastAPI) -> None:
    """One worker pass: decay sweep, purges, digests (§13, §10)."""
    with app.state.sessionmaker() as session:
        decay.sweep(session, app.state.clock, app.state.notifier)
        decay.run_purges(session, app.state.storage, app.state.clock)
        notifications.run_evening_digests(
            session, app.state.notifier, app.state.clock, app.state.settings.digest_hour
        )
        session.commit()


async def _sweep_loop(app: FastAPI) -> None:
    while True:
        try:
            await asyncio.to_thread(tick, app)
        except Exception:
            log.exception("sweep tick failed")
        await asyncio.sleep(app.state.settings.sweep_interval_seconds)


def create_app(settings: Settings | None = None, clock: Clock | None = None) -> FastAPI:
    settings = settings or Settings()
    clock = clock or SystemClock()

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
    app.state.storage = BlobStore(settings.blob_dir)
    app.state.notifier = Notifier()

    for router in (auth_routes, circles, photos, feed, me, memories, safety, blobs):
        app.include_router(router.router)

    return app
