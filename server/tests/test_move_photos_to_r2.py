"""Step 4 (build 77): moving the photos to R2 loses none. A file leaves the
volume only once R2 has it with the same size and SHA-256, checked from the
manifest and again right before deleting; anything else is kept and named."""
from __future__ import annotations

import importlib.util
import sqlite3
from pathlib import Path

import pytest

from stanley.config import Settings
from stanley.storage import R2BlobStore

from .test_r2_deletes import FakeS3

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "move_photos_to_r2.py"
spec = importlib.util.spec_from_file_location("move_photos_to_r2", SCRIPT)
move = importlib.util.module_from_spec(spec)
spec.loader.exec_module(move)


@pytest.fixture
def world(tmp_path):
    data = tmp_path / "var"
    blobs = data / "blobs"
    files = {
        "photos/p1/orig.jpg": b"original one" * 50,
        "photos/p1/deriv.jpg": b"derivative one" * 20,
        "photos/p1/thumb.jpg": b"thumb one",
        "avatars/u1.jpg": b"a face",
        "journal-covers/u1-c.jpg": b"a cover",
        "photos/stray/deriv.jpg": b"named by nothing",
    }
    for key, data_bytes in files.items():
        path = blobs / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data_bytes)
    db = data / "stanley.db"
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE photos (blob_key TEXT, deriv_key TEXT, thumb_key TEXT)")
    con.execute("CREATE TABLE users (avatar_key TEXT, journal_cover_key TEXT)")
    con.execute("INSERT INTO photos VALUES ('photos/p1/orig.jpg','photos/p1/deriv.jpg','photos/p1/thumb.jpg')")
    con.execute("INSERT INTO users VALUES ('avatars/u1.jpg','journal-covers/u1-c.jpg')")
    con.commit()
    con.close()
    settings = Settings(data_dir=str(data), database_url=f"sqlite:///{db}", blob_dir=str(blobs), secret_key="x" * 40)
    fake = FakeS3()
    store = R2BlobStore(endpoint="https://x.r2", bucket="b", access_key="k", secret_key="s", client=fake)
    run = lambda *argv: move.main(list(argv), store=store, settings=settings)
    return run, fake, blobs, files


def test_copy_verifies_every_file_by_size_and_checksum(world):
    run, fake, blobs, files = world
    assert run("copy") == 0
    assert {k: fake.objects[("b", k)] for k in files} == files
    assert run("verify") == 0


def test_delete_local_needs_confirm(world):
    run, fake, blobs, files = world
    run("copy")
    with pytest.raises(SystemExit):
        run("delete-local")
    assert all((blobs / k).exists() for k in files)


def test_a_corrupted_copy_is_caught_and_its_file_kept(world, capsys):
    run, fake, blobs, files = world
    run("copy")
    fake.objects[("b", "photos/p1/deriv.jpg")] = b"derivative one" * 19 + b"derivative xxx"  # same size, other bytes
    assert run("verify") == 1
    assert "checksum differs" in capsys.readouterr().out
    assert run("delete-local", "--confirm") == 1
    assert (blobs / "photos/p1/deriv.jpg").exists()
    assert not (blobs / "photos/p1/thumb.jpg").exists()  # verified ones go


def test_a_wrong_size_or_missing_object_keeps_the_file(world, capsys):
    run, fake, blobs, files = world
    run("copy")
    fake.objects[("b", "avatars/u1.jpg")] = b"a fac"
    del fake.objects[("b", "journal-covers/u1-c.jpg")]
    assert run("delete-local", "--confirm") == 1
    out = capsys.readouterr().out
    assert "size 5 in R2, 6 on the volume" in out and "missing in R2" in out
    assert (blobs / "avatars/u1.jpg").exists() and (blobs / "journal-covers/u1-c.jpg").exists()


def test_a_file_changed_after_its_copy_isnt_deleted_until_copied_again(world):
    run, fake, blobs, files = world
    run("copy")
    (blobs / "photos/p1/thumb.jpg").write_bytes(b"a new thumb")
    assert run("delete-local", "--confirm") == 1
    assert (blobs / "photos/p1/thumb.jpg").read_bytes() == b"a new thumb"
    assert run("copy") == 0
    assert run("delete-local", "--confirm") == 0
    assert not any(p.is_file() for p in blobs.rglob("*"))


def test_nothing_is_deleted_from_the_volume_that_was_never_copied(world):
    run, fake, blobs, files = world
    assert run("delete-local", "--confirm") == 1
    assert all((blobs / k).exists() for k in files)


def test_reconcile_deletes_only_what_the_database_no_longer_names(world, capsys):
    run, fake, blobs, files = world
    run("copy")
    assert run("reconcile") == 0
    assert ("b", "photos/stray/deriv.jpg") in fake.objects  # only listed without --confirm
    assert "would delete photos/stray/deriv.jpg" in capsys.readouterr().out
    assert run("reconcile", "--confirm") == 0
    assert ("b", "photos/stray/deriv.jpg") not in fake.objects
    assert all(("b", k) in fake.objects for k in files if k != "photos/stray/deriv.jpg")


def test_copy_again_skips_what_was_verified(world):
    run, fake, blobs, files = world
    run("copy")
    fake.objects.clear()  # if copy re-sent, these would come back
    run("copy")
    assert not fake.objects
