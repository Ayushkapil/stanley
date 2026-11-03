"""SQLite backups (audit C2) and upkeep. Uses the online backup API, which is
safe to run against a live WAL database — no downtime, consistent snapshot.
Not a substitute for off-box backups (`scripts/pull_backup.sh`, DEPLOY.md),
but it turns 'one corrupted file = everything gone' into 'lose at most a
day'.

Retention is by age as well as count (the production audit): the Privacy
Policy promises that anything deleted is gone from the backups within seven
days, and a count alone doesn't keep that. A server stopped for three days
comes back holding seven snapshots, the oldest ten days old. So a snapshot
older than `keep` days is deleted whatever the count, and at most `keep`
are ever kept (a day with several deploys makes several)."""
from __future__ import annotations

import logging
import shutil
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

log = logging.getLogger("stanley")

_STAMP = "%Y%m%dT%H%M%SZ"


def _sqlite_path(database_url: str) -> Path | None:
    if not database_url.startswith("sqlite") or ":memory:" in database_url:
        return None
    return Path(database_url.removeprefix("sqlite:///"))


def _taken(snapshot: Path) -> datetime | None:
    try:
        return datetime.strptime(snapshot.stem, _STAMP).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def backup_database(
    database_url: str, backups_dir: str, keep: int = 7, now: datetime | None = None
) -> Path | None:
    """Snapshot the DB to backups_dir/{UTC-timestamp}.db, then prune: nothing
    older than `keep` days, and no more than the `keep` newest. Returns the
    snapshot path, or None for in-memory/non-sqlite DBs."""
    src = _sqlite_path(database_url)
    if src is None or not src.exists():
        return None

    now = now or datetime.now(timezone.utc)
    out_dir = Path(backups_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / f"{now.strftime(_STAMP)}.db"

    source = sqlite3.connect(str(src))
    try:
        target = sqlite3.connect(str(dest))
        try:
            source.backup(target)  # consistent online snapshot
        finally:
            target.close()
    finally:
        source.close()

    snapshots = sorted(out_dir.glob("*.db"))
    cutoff = now - timedelta(days=keep)
    for snapshot in snapshots:
        taken = _taken(snapshot)
        if taken is not None and taken < cutoff and snapshot != dest:
            snapshot.unlink(missing_ok=True)
    snapshots = sorted(out_dir.glob("*.db"))
    for stale in snapshots[:-keep] if keep > 0 else []:
        stale.unlink(missing_ok=True)

    log.info("backup: wrote %s (keeping %d days)", dest.name, keep)
    return dest


def warn_if_disk_low(path: str, floor: float = 0.25) -> float | None:
    """A WARNING in the host's logs when the volume holding `path` is more
    than three quarters full: each photo keeps about 3 MB (its full-size
    original, then two smaller copies), so a busy circle fills a small
    volume in days, and a full disk refuses every photo. Returns the free
    fraction, or None when there's nothing at `path` to measure."""
    if not Path(path).exists():
        return None
    usage = shutil.disk_usage(path)
    free = usage.free / usage.total
    if free < floor:
        log.warning("event=disk_low free_percent=%d free_mb=%d", int(free * 100), usage.free // 2**20)
    return free


def maintain_database(database_url: str, *, vacuum: bool) -> None:
    """Daily upkeep, after the backup: `PRAGMA optimize` (refreshes the query
    planner's statistics where they've drifted), and on the weekly pass a
    `VACUUM`, which rewrites the file without the pages deletions and purges
    left empty, then a WAL checkpoint so the -wal file shrinks too. VACUUM
    holds the write lock while it runs: milliseconds at Stanley's size, and a
    request that meets it waits (busy_timeout), it doesn't fail."""
    path = _sqlite_path(database_url)
    if path is None or not path.exists():
        return
    con = sqlite3.connect(str(path), timeout=30)
    try:
        con.execute("PRAGMA optimize")
        if vacuum:
            con.execute("VACUUM")
            con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    finally:
        con.close()
    log.info("maintenance: optimize%s", " + vacuum" if vacuum else "")
