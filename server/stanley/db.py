from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import DateTime, TypeDecorator, create_engine
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


def make_engine(url: str):
    if url.startswith("sqlite"):
        if url in ("sqlite://", "sqlite:///:memory:") or ":memory:" in url:
            return create_engine(
                url,
                connect_args={"check_same_thread": False},
                poolclass=StaticPool,
            )
        Path(url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
        return create_engine(url, connect_args={"check_same_thread": False})
    return create_engine(url, pool_pre_ping=True)


def make_sessionmaker(engine):
    return sessionmaker(bind=engine, expire_on_commit=False)


# Columns added after the first release. create_all() only creates missing
# tables, so existing pilot databases get these via ALTER on startup.
_LATER_COLUMNS = {
    "users": {"username": "VARCHAR(30)", "bio": "TEXT"},
    "photos": {"location": "VARCHAR(120)"},
    "returned_log": {"dismissed": "BOOLEAN DEFAULT 0"},
}
_LATER_UNIQUE_INDEXES = [("uq_users_username", "users", "username")]
# Tables left behind by a rename. Their data was ephemeral by design, so a drop
# is safe — "warmth" became "likes" (same mechanic, cosmetic heart).
_LEGACY_TABLES = ["warmth"]


def ensure_schema(engine) -> list[str]:
    """Tiny forward-only migration: add any missing late columns, drop renamed
    legacy tables. Returns the list of columns added (for logging/tests)."""
    from sqlalchemy import inspect, text

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
        for table in _LEGACY_TABLES:
            if table in tables:
                conn.execute(text(f"DROP TABLE {table}"))
    return added
