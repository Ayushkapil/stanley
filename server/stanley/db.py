from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import DateTime, TypeDecorator, create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from sqlalchemy.pool import StaticPool


class Base(DeclarativeBase):
    pass


class UTCDateTime(TypeDecorator):
    """Stores aware-UTC datetimes as naive UTC and restores tzinfo on read.

    SQLite drops timezone info on round-trip; normalizing here means the rest
    of the codebase only ever sees aware UTC datetimes. Naive input is a bug
    and is rejected loudly.
    """

    impl = DateTime
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("naive datetime passed to UTCDateTime column")
        return value.astimezone(timezone.utc).replace(tzinfo=None)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value.replace(tzinfo=timezone.utc)


def _install_sqlite_pragmas(engine, *, wal: bool) -> None:
    """Per-connection PRAGMAs (audit C2 + I1 + I9):
      - WAL: readers don't block the writer; far fewer 'database is locked'.
      - busy_timeout: wait up to 5s for a lock instead of failing instantly.
      - foreign_keys=ON: SQLite enforces FKs off by default — turn them on so
        orphaned rows are impossible.
    WAL is skipped for in-memory DBs (it's a no-op there)."""

    @event.listens_for(engine, "connect")
    def _set_pragmas(dbapi_conn, _record):
        cur = dbapi_conn.cursor()
        if wal:
            cur.execute("PRAGMA journal_mode=WAL")
        cur.execute("PRAGMA busy_timeout=5000")
        cur.execute("PRAGMA foreign_keys=ON")
        cur.close()


def make_engine(url: str):
    if url.startswith("sqlite"):
        if url in ("sqlite://", "sqlite:///:memory:") or ":memory:" in url:
            engine = create_engine(
                url,
                connect_args={"check_same_thread": False},
                poolclass=StaticPool,
            )
            _install_sqlite_pragmas(engine, wal=False)
            return engine
        Path(url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
        engine = create_engine(url, connect_args={"check_same_thread": False})
        _install_sqlite_pragmas(engine, wal=True)
        return engine
    return create_engine(url, pool_pre_ping=True)


def make_sessionmaker(engine):
    return sessionmaker(bind=engine, expire_on_commit=False)


# Columns added after the first release. create_all() only creates missing
# tables, so existing pilot databases get these via ALTER on startup.
_LATER_COLUMNS = {
    "users": {"username": "VARCHAR(30)", "bio": "TEXT"},
    "photos": {"location": "VARCHAR(120)", "filter": "VARCHAR(12)"},
    "returned_log": {"dismissed": "BOOLEAN DEFAULT 0"},
}
_LATER_UNIQUE_INDEXES = [("uq_users_username", "users", "username")]
# Hot-path indexes (audit M3). Idempotent CREATE INDEX IF NOT EXISTS so existing
# pilot DBs get them without create_all (which only adds missing tables).
_LATER_INDEXES = [
    ("ix_photos_circle_state", "photos", "circle_id, state"),
    ("ix_comments_photo", "comments", "photo_id"),
    ("ix_likes_photo", "likes", "photo_id"),
    ("ix_anchors_photo", "anchors", "photo_id"),
]
# Tables left behind by a rename. Their data was ephemeral by design, so a drop
# is safe — "warmth" became "likes" (same mechanic, cosmetic heart), and
# "news_cache" (one row of headlines) became "news_editions".
_LEGACY_TABLES = ["warmth", "news_cache"]


def ensure_schema(engine) -> list[str]:
    """Tiny forward-only migration: add missing late columns + indexes, bump
    legacy circle caps, drop renamed legacy tables. Returns the columns added."""
    import logging

    from sqlalchemy import inspect, text

    from .physics import CIRCLE_CAP

    log = logging.getLogger("stanley")
    inspector = inspect(engine)
    added = []
    with engine.begin() as conn:
        tables = set(inspector.get_table_names())
        for table, columns in _LATER_COLUMNS.items():
            if table not in tables:
                continue
            have = {c["name"] for c in inspector.get_columns(table)}
            for name, ddl in columns.items():
                if name not in have:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"))
                    added.append(f"{table}.{name}")
        for index, table, column in _LATER_UNIQUE_INDEXES:
            if table in tables:
                conn.execute(
                    text(f"CREATE UNIQUE INDEX IF NOT EXISTS {index} ON {table} ({column})")
                )
        for index, table, columns in _LATER_INDEXES:
            if table in tables:
                conn.execute(
                    text(f"CREATE INDEX IF NOT EXISTS {index} ON {table} ({columns})")
                )
        # I7: circles created before the cap was raised keep their old per-row
        # cap. Bump them so the pilot isn't silently capped at the old value.
        if "circles" in tables:
            result = conn.execute(
                text("UPDATE circles SET cap = :cap WHERE cap < :cap"), {"cap": CIRCLE_CAP}
            )
            if result.rowcount:
                log.info("ensure_schema: raised cap to %d on %d circle(s)", CIRCLE_CAP, result.rowcount)
        for table in _LEGACY_TABLES:
            if table in tables:
                conn.execute(text(f"DROP TABLE {table}"))

        # Migrate old 32-char hex invite tokens to the short XXXX-XXXX format.
        # Existing circles get a new code; the old long string is unusable anyway
        # since the new join endpoint validates only the short format.
        if "circles" in tables:
            import re
            import secrets as _sec
            _CH = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

            def _gen():
                c = [_sec.choice(_CH) for _ in range(8)]
                return f"{''.join(c[:4])}-{''.join(c[4:])}"

            rows = conn.execute(text("SELECT id, invite_token FROM circles")).fetchall()
            for cid, token in rows:
                if token and re.match(r"^[0-9a-f]{32}$", str(token)):
                    conn.execute(
                        text("UPDATE circles SET invite_token = :t WHERE id = :id"),
                        {"t": _gen(), "id": cid},
                    )

    return added
