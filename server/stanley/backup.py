"""SQLite backups (audit C2). Uses the online backup API, which is safe to run
against a live WAL database — no downtime, consistent snapshot. Keeps the last
N daily snapshots and prunes older ones. Not a substitute for off-box backups,
but it turns 'one corrupted file = everything gone' into 'lose at most a day'."""
from __future__ import annotations

import logging
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

log = logging.getLogger("stanley")


def _sqlite_path(database_url: str) -> Path | None:
    if not database_url.startswith("sqlite") or ":memory:" in database_url:
        return None
    return Path(database_url.removeprefix("sqlite:///"))


def backup_database(database_url: str, backups_dir: str, keep: int = 7) -> Path | None:
    """Snapshot the DB to backups_dir/{UTC-timestamp}.db; prune to `keep` newest.
    Returns the snapshot path, or None for in-memory/non-sqlite DBs."""
    src = _sqlite_path(database_url)
    if src is None or not src.exists():
        return None

    out_dir = Path(backups_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dest = out_dir / f"{stamp}.db"

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
    for stale in snapshots[:-keep] if keep > 0 else []:
        stale.unlink(missing_ok=True)

    log.info("backup: wrote %s (keeping %d)", dest.name, keep)
    return dest
