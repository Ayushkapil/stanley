"""Standalone decay worker: `python -m stanley.worker --once` or looping.

In production this can be a single process next to the API, or replaced by
pg_cron once on Postgres (§9). The logic is identical either way: sweep,
purge, digest, and The World Today's headlines when they're due.
"""
from __future__ import annotations

import argparse
import time
from datetime import timedelta

from . import decay, news, notifications
from .clock import SystemClock
from .config import Settings
from .db import Base, ensure_schema, make_engine, make_sessionmaker
from .notifications import Notifier
from .storage import make_blob_store


def run_once(settings: Settings | None = None) -> None:
    settings = settings or Settings()
    engine = make_engine(settings.database_url)
    Base.metadata.create_all(engine)
    ensure_schema(engine)
    clock = SystemClock()
    notifier = Notifier()
    storage = make_blob_store(settings)
    with make_sessionmaker(engine)() as session:
        advanced = decay.sweep(session, clock, notifier)
        purged = decay.run_purges(session, storage, clock)
        digests = notifications.run_evening_digests(session, notifier, clock, settings.digest_hour)
        session.commit()
        if settings.news_enabled:
            news.refresh_if_due(
                session, clock, timedelta(seconds=settings.news_interval_seconds),
            )
            session.commit()
    print(f"sweep: {advanced} transitions, {purged} purged, {digests} digests")


def main() -> None:
    parser = argparse.ArgumentParser(description="Stanley decay worker")
    parser.add_argument("--once", action="store_true", help="run a single pass and exit")
    args = parser.parse_args()
    settings = Settings()
    if args.once:
        run_once(settings)
        return
    while True:
        run_once(settings)
        time.sleep(settings.sweep_interval_seconds)


if __name__ == "__main__":
    main()
