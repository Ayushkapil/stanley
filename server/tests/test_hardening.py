"""DB hardening (C2/I1/I9), capture race + orphan-blob safety (I2)."""
from __future__ import annotations

import io

import pytest
from PIL import Image
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError

from stanley.models import Anchor, Photo


def test_foreign_keys_are_enforced(app):
    """I1: inserting an anchor for a nonexistent photo must be rejected."""
    Session = app.state.sessionmaker
    with pytest.raises(IntegrityError):
        with Session() as s:
            from datetime import datetime, timezone

            s.add(Anchor(photo_id="nonexistent", user_id="nobody", created_at=datetime.now(timezone.utc)))
            s.commit()


def test_capture_race_one_wins_no_orphans(circle, app, db):
    """I2: two captures for the same user+day → one 201, one 409, and the loser
    leaves zero blobs behind."""
    # First capture succeeds.
    r1 = circle.ana.post_photo(caption="first")
    assert r1.status_code == 201
    pid = r1.json()["id"]

    blobs_before = set(_all_blob_keys(app))

    # Second capture same day → 409 slot_used, no new blobs.
    r2 = circle.ana.post_photo(caption="second")
    assert r2.status_code == 409
    assert r2.json()["detail"]["code"] == "slot_used"

    blobs_after = set(_all_blob_keys(app))
    assert blobs_after == blobs_before  # loser wrote nothing

    # exactly one photo row for ana that day
    with db() as session:
        rows = session.scalars(select(Photo).where(Photo.owner_id == circle.ana.id)).all()
    assert len(rows) == 1 and rows[0].id == pid


def test_caption_over_2000_rejected(circle):
    r = circle.ana.post_photo(caption="x" * 2001)
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "caption_too_long"


def test_bad_image_does_not_consume_slot(circle):
    """Decode happens before the slot is claimed."""
    assert circle.ana.post_photo(image=b"not an image").status_code == 400
    # the day is still available
    assert circle.ana.post_photo(caption="real one").status_code == 201


def _all_blob_keys(app):
    root = app.state.storage.root
    return [str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()]


def test_backup_creates_snapshot_and_skips_memory(tmp_path):
    """C2: backup writes a real snapshot; in-memory DBs are a no-op."""
    import sqlite3

    from stanley.backup import backup_database

    db_path = tmp_path / "x.db"
    con = sqlite3.connect(str(db_path))
    con.execute("CREATE TABLE t (x INT)")
    con.commit()
    con.close()

    dest = backup_database(f"sqlite:///{db_path}", str(tmp_path / "backups"), keep=7)
    assert dest is not None and dest.exists()
    assert backup_database("sqlite://", str(tmp_path / "b2"), keep=7) is None


def test_backup_prunes_to_keep(tmp_path):
    import sqlite3

    from stanley.backup import backup_database

    bdir = tmp_path / "backups"
    bdir.mkdir()
    # eight older snapshots already present
    for day in range(1, 9):
        (bdir / f"202601{day:02d}T000000Z.db").write_bytes(b"old")

    db_path = tmp_path / "x.db"
    con = sqlite3.connect(str(db_path))
    con.execute("CREATE TABLE t (x INT)")
    con.commit()
    con.close()
    backup_database(f"sqlite:///{db_path}", str(bdir), keep=7)

    assert len(list(bdir.glob("*.db"))) == 7  # pruned to the 7 newest


def test_community_note_upsert_no_duplicate(circle, db):
    """I6: repeated set_note replaces in place (single row)."""
    from stanley.models import CommunityNote

    circle.ana.set_note(circle.id, "first")
    circle.ben.set_note(circle.id, "second")
    with db() as session:
        notes = session.scalars(select(CommunityNote).where(CommunityNote.circle_id == circle.id)).all()
    assert len(notes) == 1
    assert notes[0].body == "second"
