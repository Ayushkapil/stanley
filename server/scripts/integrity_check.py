"""Read-only integrity check of a Stanley database (the production audit).

    .venv/bin/python scripts/integrity_check.py var/stanley.db var/blobs

On Fly, with nothing written to the machine (the script is piped in):

    base64 -i scripts/integrity_check.py | tr -d '\\n' > /tmp/ic.b64
    fly ssh console -C "sh -c 'echo $(cat /tmp/ic.b64) | base64 -d | /app/.venv/bin/python - /data/var/stanley.db /data/var/blobs'"

Opens the database read-only (`mode=ro`), so it can run against the live
file. Checks SQLite's own integrity and foreign keys, then what foreign keys
can't see: rows pointing at nothing (an orphan), a deleted account with
anything of the person left, a purged photo still naming blobs or words,
and (given the blob folder) photo files with no row, or rows whose files
are gone. Prints one line per check and exits 1 if anything is wrong.
Standard library only, so it runs on the server's own Python.
"""
from __future__ import annotations

import os
import sqlite3
import sys

CHECKS: list[tuple[str, str]] = [
    # Orphans: a row whose parent is gone.
    ("photos with an owner who doesn't exist",
     "SELECT count(*) FROM photos p WHERE p.owner_id IS NOT NULL AND p.owner_id NOT IN (SELECT id FROM users)"),
    ("photos in a circle that doesn't exist",
     "SELECT count(*) FROM photos WHERE circle_id NOT IN (SELECT id FROM circles)"),
    ("stories on a photo that doesn't exist",
     "SELECT count(*) FROM comments WHERE photo_id NOT IN (SELECT id FROM photos)"),
    ("stories by someone who doesn't exist",
     "SELECT count(*) FROM comments WHERE author_id NOT IN (SELECT id FROM users)"),
    ("memberships of a circle that doesn't exist",
     "SELECT count(*) FROM memberships WHERE circle_id NOT IN (SELECT id FROM circles)"),
    ("memberships of someone who doesn't exist",
     "SELECT count(*) FROM memberships WHERE user_id NOT IN (SELECT id FROM users)"),
    ("holds of a photo that doesn't exist",
     "SELECT count(*) FROM anchors WHERE photo_id NOT IN (SELECT id FROM photos)"),
    ("likes of a photo that doesn't exist",
     "SELECT count(*) FROM likes WHERE photo_id NOT IN (SELECT id FROM photos)"),
    ("tags on a photo that doesn't exist",
     "SELECT count(*) FROM photo_tags WHERE photo_id NOT IN (SELECT id FROM photos)"),
    ("rests of a photo that doesn't exist",
     "SELECT count(*) FROM rests WHERE photo_id NOT IN (SELECT id FROM photos)"),
    ("open reports about nothing (no photo, story or answer)",
     "SELECT count(*) FROM reports WHERE photo_id IS NULL AND comment_id IS NULL"
     " AND response_id IS NULL AND resolved_at IS NULL"),
    ("purges queued for a photo that doesn't exist",
     "SELECT count(*) FROM purge_queue WHERE photo_id NOT IN (SELECT id FROM photos)"),
    ("circles started by someone who doesn't exist",
     "SELECT count(*) FROM circles WHERE created_by NOT IN (SELECT id FROM users)"),
    # Deletion: nothing of a deleted person left (Privacy Policy section 4).
    ("deleted accounts still holding a name, username, bio, Apple id or face",
     "SELECT count(*) FROM users WHERE deleted_at IS NOT NULL AND (display_name IS NOT NULL "
     "OR username IS NOT NULL OR bio IS NOT NULL OR apple_sub IS NOT NULL OR avatar_key IS NOT NULL)"),
    ("deleted accounts still in a circle",
     "SELECT count(*) FROM memberships m JOIN users u ON u.id = m.user_id WHERE u.deleted_at IS NOT NULL"),
    ("deleted accounts' photos still showing",
     "SELECT count(*) FROM photos p JOIN users u ON u.id = p.owner_id "
     "WHERE u.deleted_at IS NOT NULL AND p.state != 'PURGED'"),
    ("deleted accounts' stories, likes, holds, tags or tokens",
     "SELECT (SELECT count(*) FROM comments c JOIN users u ON u.id = c.author_id WHERE u.deleted_at IS NOT NULL)"
     " + (SELECT count(*) FROM likes l JOIN users u ON u.id = l.user_id WHERE u.deleted_at IS NOT NULL)"
     " + (SELECT count(*) FROM anchors a JOIN users u ON u.id = a.user_id WHERE u.deleted_at IS NOT NULL)"
     " + (SELECT count(*) FROM photo_tags t JOIN users u ON u.id = t.tagged_user_id WHERE u.deleted_at IS NOT NULL)"
     " + (SELECT count(*) FROM push_tokens k JOIN users u ON u.id = k.user_id WHERE u.deleted_at IS NOT NULL)"),
    # Decay: a purged photo keeps nothing but its tombstone.
    ("purged photos still naming a blob, caption or place",
     "SELECT count(*) FROM photos WHERE state = 'PURGED' AND (blob_key IS NOT NULL OR deriv_key IS NOT NULL "
     "OR thumb_key IS NOT NULL OR caption IS NOT NULL OR location IS NOT NULL)"),
    ("likes on a photo that has left Today",
     "SELECT count(*) FROM likes l JOIN photos p ON p.id = l.photo_id WHERE p.state IN ('EXPIRED', 'PURGED')"),
    ("expired photos nobody holds with no purge scheduled",
     "SELECT count(*) FROM photos p WHERE p.state = 'EXPIRED' AND p.purge_after IS NULL "
     "AND NOT EXISTS (SELECT 1 FROM anchors a WHERE a.photo_id = p.id)"),
    # Build 26: a journal entry lives as long as its photo does for its
    # owner, and what a deleted account wrote down is gone with it.
    ("journal entries outliving their photo, or on someone else's",
     "SELECT count(*) FROM journal_entries j LEFT JOIN photos p ON p.id = j.photo_id "
     "WHERE p.id IS NULL OR p.state = 'PURGED' OR p.deleted_at IS NOT NULL OR p.owner_id IS NOT j.owner_id "
     "OR (p.state = 'EXPIRED' AND NOT EXISTS "
     "(SELECT 1 FROM anchors a WHERE a.photo_id = p.id AND a.user_id = j.owner_id))"),
    ("deleted accounts' reflections, answers or journal entries",
     "SELECT (SELECT count(*) FROM weekly_reflections r JOIN users u ON u.id = r.owner_id WHERE u.deleted_at IS NOT NULL)"
     " + (SELECT count(*) FROM prompt_responses a JOIN users u ON u.id = a.user_id WHERE u.deleted_at IS NOT NULL)"
     " + (SELECT count(*) FROM journal_entries j JOIN users u ON u.id = j.owner_id WHERE u.deleted_at IS NOT NULL)"),
]


def _blob_checks(con: sqlite3.Connection, blob_dir: str) -> list[tuple[str, int]]:
    on_disk: set[str] = set()
    for root, _, files in os.walk(blob_dir):
        for name in files:
            on_disk.add(os.path.relpath(os.path.join(root, name), blob_dir))
    named: set[str] = set()
    for row in con.execute("SELECT blob_key, deriv_key, thumb_key FROM photos"):
        named.update(k for k in row if k)
    named.update(k for (k,) in con.execute("SELECT avatar_key FROM users WHERE avatar_key IS NOT NULL"))
    photo_files = {f for f in on_disk if not f.startswith("avatars/")}
    # A full-size original is written after the response (photos.py), so a
    # photo seconds old may not have one yet; a missing deriv or thumb is real.
    missing = {k for k in named - on_disk if not k.endswith("/orig.jpg")}
    return [
        ("photo files on disk that no photo names", len(photo_files - named)),
        ("photos and faces whose file is gone", len(missing)),
    ]


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    con = sqlite3.connect(f"file:{argv[0]}?mode=ro", uri=True)
    results: list[tuple[str, int]] = []
    integrity = con.execute("PRAGMA integrity_check").fetchall()
    results.append(("SQLite integrity_check problems", 0 if integrity == [("ok",)] else len(integrity)))
    results.append(("foreign keys pointing at nothing", len(con.execute("PRAGMA foreign_key_check").fetchall())))
    for label, sql in CHECKS:
        results.append((label, con.execute(sql).fetchone()[0]))
    if len(argv) > 1:
        results.extend(_blob_checks(con, argv[1]))
    empty = con.execute(
        "SELECT count(*) FROM circles WHERE id NOT IN (SELECT circle_id FROM memberships)"
    ).fetchone()[0]
    con.close()

    bad = 0
    for label, n in results:
        print(f"{'ok  ' if n == 0 else 'FAIL'}  {label}: {n}")
        bad += n > 0
    # Not a fault, worth knowing: a circle everyone left still has a code
    # that joins it.
    print(f"note  circles with nobody in them: {empty}")
    print("all clear" if bad == 0 else f"{bad} check(s) failed")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
