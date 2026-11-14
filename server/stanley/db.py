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
        # One connection per request thread. Sync routes run on AnyIO's pool
        # of 40 threads, and SQLAlchemy's default pool holds 15 (5 + 10
        # overflow), so a burst past 15 requests queued for a connection
        # rather than for SQLite. In WAL mode any number of readers run at
        # once and writers take turns (busy_timeout waits up to 5s), so the
        # pool matches the threads. A SQLite connection costs a file handle.
        engine = create_engine(
            url,
            connect_args={"check_same_thread": False},
            pool_size=10,
            max_overflow=30,
            pool_timeout=10,
        )
        _install_sqlite_pragmas(engine, wal=True)
        return engine
    return create_engine(url, pool_pre_ping=True)


def make_sessionmaker(engine):
    return sessionmaker(bind=engine, expire_on_commit=False)


# Columns added after the first release. create_all() only creates missing
# tables, so existing pilot databases get these via ALTER on startup.
_LATER_COLUMNS = {
    "users": {
        "username": "VARCHAR(30)",
        "bio": "TEXT",
        "digest_enabled": "BOOLEAN DEFAULT 0",
        # Build 37: the circle-post notice, off for everyone already here.
        "circle_posts_enabled": "BOOLEAN DEFAULT 0",
        # Build 39: the two reminders, off for everyone already here.
        "note_reminder_enabled": "BOOLEAN DEFAULT 0",
        "note_reminder_hour": "INTEGER DEFAULT 9",
        "photo_reminder_enabled": "BOOLEAN DEFAULT 0",
        "photo_reminder_hour": "INTEGER DEFAULT 18",
        # Build 45: what the person calls their journal; null is the default.
        "journal_title": "VARCHAR(60)",
    },
    # Build 50: a journal page in more than one ink; null is all one ink.
    "journal_pages": {"inks": "TEXT"},
    # Build 35: one circle's countdown, null everywhere else.
    "circles": {"countdown": "JSON"},
    "photos": {"location": "VARCHAR(120)", "filter": "VARCHAR(12)"},
    "returned_log": {"dismissed": "BOOLEAN DEFAULT 0"},
    # Build 26: a report about an answer to the circle's question.
    "reports": {
        "response_id": "VARCHAR(32) REFERENCES prompt_responses(id)",
        # Build 27: a report about a note on the circle's board.
        "note_id": "VARCHAR(32)",
        # Build 42: a report about an anonymous letter to the circle.
        "circle_letter_id": "VARCHAR(32)",
        # Build 42: a report about a sealed letter (only once it's open).
        "letter_id": "VARCHAR(32) REFERENCES person_letters(id)",
    },
}
_LATER_UNIQUE_INDEXES = [("uq_users_username", "users", "username")]
# Hot-path indexes (audit M3). Idempotent CREATE INDEX IF NOT EXISTS so existing
# pilot DBs get them without create_all (which only adds missing tables).
_LATER_INDEXES = [
    ("ix_photos_circle_state", "photos", "circle_id, state"),
    ("ix_comments_photo", "comments", "photo_id"),
    ("ix_likes_photo", "likes", "photo_id"),
    ("ix_anchors_photo", "anchors", "photo_id"),
    # The production audit: every query that runs on each request or each
    # sweep, and had been reading a whole table to answer it.
    # Which circles a person is in: nearly every request asks.
    ("ix_memberships_user", "memberships", "user_id, joined_at"),
    # Who blocked whom, from the blocked side: every photo payload asks.
    ("ix_blocks_blocked", "blocks", "blocked_id"),
    # Held, the export, milestones and Returned: a person's holds.
    ("ix_anchors_user", "anchors", "user_id"),
    # The decay sweep, every 15 minutes: what's overdue.
    ("ix_photos_state_deadline", "photos", "state, state_deadline"),
    # The day's redo, counted at every capture and delete.
    ("ix_photos_owner_hash", "photos", "owner_hash, circle_id, local_date"),
    # The purge queue, every sweep.
    ("ix_purge_queue_due", "purge_queue", "done, purge_after"),
    # One digest a day: has this person had today's?
    ("ix_notification_log_user", "notification_log", "user_id, kind, sent_at"),
    # Deleting an account: their stories, likes and tags elsewhere.
    ("ix_comments_author", "comments", "author_id"),
    ("ix_likes_user", "likes", "user_id"),
    ("ix_phototags_user", "photo_tags", "tagged_user_id"),
    # Deleting a story or photo detaches the reports about it.
    ("ix_reports_comment", "reports", "comment_id"),
    ("ix_reports_photo", "reports", "photo_id"),
    ("ix_reports_response", "reports", "response_id"),
    # Build 42: reports about a letter.
    ("ix_reports_letter", "reports", "letter_id"),
    # Build 42: Held reads a recipient's letters; the cap counts sealed ones.
    ("ix_person_letters_recipient", "person_letters", "recipient_id, deliver_at"),
    ("ix_person_letters_sender", "person_letters", "sender_id"),
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

        # Build 27: the one shared line per circle became a board with a note
        # each. The line still up (at most one per circle, never more than a
        # day old) moves onto the board as its author's note, keeping when it
        # clears; then the old table goes.
        if "community_notes" in tables:
            moved = conn.execute(text(
                "INSERT OR IGNORE INTO circle_notes "
                "(id, circle_id, author_id, body, created_at, updated_at, expires_at) "
                "SELECT lower(hex(randomblob(16))), circle_id, author_id, body, created_at, created_at, expires_at "
                "FROM community_notes "
                # A row left pointing at nothing (from before foreign keys)
                # stays behind rather than stopping the server from starting.
                "WHERE circle_id IN (SELECT id FROM circles) AND author_id IN (SELECT id FROM users)"
            ))
            conn.execute(text("DROP TABLE community_notes"))
            log.info("ensure_schema: moved %d note(s) onto the circle's board", moved.rowcount)

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

    if _photo_slot_is_per_person(engine):
        try:
            _rebuild_photos(engine)
            log.info("ensure_schema: the day's slot is now per circle")
        except Exception:
            # Nothing was changed (it's one transaction). Stanley still runs:
            # the old slot only means a second circle's photo on the same day
            # is refused as slot_used, which costs nobody a photo they'd
            # already posted. Loud, so it gets looked at.
            log.exception("ensure_schema: photos rebuild failed; the day's slot is still per person")

    return added


def _photo_slot_is_per_person(engine) -> bool:
    """Whether photos still has build 16's UNIQUE(owner_id, local_date): one
    photo a day across everything, from when a person had one circle."""
    from sqlalchemy import inspect

    inspector = inspect(engine)
    if "photos" not in inspector.get_table_names():
        return False
    return any(
        set(uc["column_names"]) == {"owner_id", "local_date"}
        for uc in inspector.get_unique_constraints("photos")
    )


def _rebuild_photos(engine) -> None:
    """Make the day's slot per circle (build 17). SQLite can't change a
    table's constraints in place, so this is its documented rebuild: a new
    table from the model, every row copied, the old one dropped and the new
    one renamed into its place, in one transaction. Foreign keys are off
    while it runs, because dropping photos would otherwise trip every anchor,
    like and comment that points at it; they're checked before committing,
    and nothing is kept if a single one would dangle. Rows keep their ids, so
    every reference still lands on the same photo. A database that already
    had dangling references (from before foreign keys were enforced) isn't
    held hostage to them: only a new one stops the rebuild."""
    from sqlalchemy import inspect
    from sqlalchemy.schema import CreateIndex, CreateTable

    from .models import Photo

    table = Photo.__table__
    have = {c["name"] for c in inspect(engine).get_columns("photos")}
    columns = ", ".join(c.name for c in table.columns if c.name in have)
    create = str(CreateTable(table).compile(engine)).strip()
    create = create.replace("CREATE TABLE photos ", "CREATE TABLE photos__rebuild ", 1)
    indexes = [str(CreateIndex(index).compile(engine)) for index in table.indexes]

    raw = engine.raw_connection()
    try:
        sqlite = raw.driver_connection
        isolation = sqlite.isolation_level
        # Autocommit, so the BEGIN and COMMIT below are the only ones, and the
        # PRAGMA lands outside any transaction (inside one, SQLite ignores it).
        sqlite.isolation_level = None
        cur = sqlite.cursor()
        cur.execute("PRAGMA foreign_keys=OFF")
        try:
            cur.execute("BEGIN")
            before = len(cur.execute("PRAGMA foreign_key_check").fetchall())
            cur.execute(create)
            cur.execute(f"INSERT INTO photos__rebuild ({columns}) SELECT {columns} FROM photos")
            cur.execute("DROP TABLE photos")
            cur.execute("ALTER TABLE photos__rebuild RENAME TO photos")
            for index in indexes:
                cur.execute(index)
            after = len(cur.execute("PRAGMA foreign_key_check").fetchall())
            if after > before:
                raise RuntimeError(f"photos rebuild would leave {after - before} new dangling references")
            cur.execute("COMMIT")
        except Exception:
            cur.execute("ROLLBACK")
            raise
        finally:
            cur.execute("PRAGMA foreign_keys=ON")
            sqlite.isolation_level = isolation
    finally:
        raw.close()
