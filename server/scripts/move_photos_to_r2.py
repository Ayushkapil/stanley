"""Move Stanley's photos and pictures from the Fly volume to Cloudflare R2
(step 4, build 77), without losing one.

Run on the Fly machine, where the files and the R2 credentials are:

    fly ssh console -a server-earnest-stream-9793 -C "/app/.venv/bin/python /app/scripts/move_photos_to_r2.py plan"

The steps, in order:

    plan          what's on the volume, what the database names, R2 reachable
    copy          every file on the volume put in R2 under the same key, then
                  checked: its size from R2, and a SHA-256 of what R2 hands
                  back against the file's own; the results kept in a manifest
    verify        every file again, and every key the database names: in R2,
                  the same size, the same SHA-256 as on the volume
    reconcile     after the switch: R2 objects the database no longer names
                  (deleted between the copy and the switch) are listed, and
                  with --confirm deleted, so a deleted photo doesn't linger
    delete-local  with --confirm only: deletes a file from the volume only if
                  the manifest has it verified AND, checked again right then,
                  R2 has it with the same size and SHA-256. Anything else is
                  kept and named.

Nothing here deletes from the volume unless asked to with delete-local
--confirm, and then only file by file after its own check. The credentials
come from the environment (BLOB_R2_ENDPOINT, BLOB_R2_BUCKET,
BLOB_R2_ACCESS_KEY, BLOB_R2_SECRET_KEY); none is printed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from stanley.config import Settings  # noqa: E402
from stanley.storage import R2BlobStore  # noqa: E402

MANIFEST_NAME = "r2-migration.json"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def local_files(root: Path) -> dict[str, Path]:
    """Every file under the blob folder, by its key (its path under it)."""
    return {
        str(path.relative_to(root)): path
        for path in sorted(root.rglob("*"))
        if path.is_file() and not path.name.startswith(".")
    }


def referenced_keys(database: Path) -> set[str]:
    """Every blob key the database names: photos' three files (and those of
    an entry's further photos, build 81), avatars, and chosen journal covers.
    Read-only."""
    con = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        keys: set[str] = set()
        for (a, b, c) in con.execute("SELECT blob_key, deriv_key, thumb_key FROM photos"):
            keys.update(k for k in (a, b, c) if k)
        # An entry's further photos (build 81). Without them, reconcile
        # would delete every second and third photo of a day from R2.
        has_extras = con.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='photo_images'"
        ).fetchone()
        if has_extras:
            for (a, b, c) in con.execute("SELECT blob_key, deriv_key, thumb_key FROM photo_images"):
                keys.update(k for k in (a, b, c) if k)
        for (avatar, cover) in con.execute("SELECT avatar_key, journal_cover_key FROM users"):
            keys.update(k for k in (avatar, cover) if k)
        return keys
    finally:
        con.close()


def r2_store(settings: Settings) -> R2BlobStore:
    missing = [name for name, value in (
        ("BLOB_R2_ENDPOINT", settings.blob_r2_endpoint),
        ("BLOB_R2_BUCKET", settings.blob_r2_bucket),
        ("BLOB_R2_ACCESS_KEY", settings.blob_r2_access_key),
        ("BLOB_R2_SECRET_KEY", settings.blob_r2_secret_key),
    ) if not value]
    if missing:
        sys.exit(f"move_photos_to_r2: not set: {', '.join(missing)}")
    return R2BlobStore(
        endpoint=settings.blob_r2_endpoint, bucket=settings.blob_r2_bucket,
        access_key=settings.blob_r2_access_key, secret_key=settings.blob_r2_secret_key,
    )


def check_one(store: R2BlobStore, key: str, data: bytes) -> str | None:
    """None when R2 has `key` with this size and this SHA-256; else why not."""
    size = store.size(key)
    if size is None:
        return "missing in R2"
    if size != len(data):
        return f"size {size} in R2, {len(data)} on the volume"
    if sha256(store.get(key)) != sha256(data):
        return "checksum differs"
    return None


class Manifest:
    def __init__(self, path: Path):
        self.path = path
        self.entries: dict[str, dict] = {}
        if path.exists():
            self.entries = json.loads(path.read_text())["objects"]

    def save(self) -> None:
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"objects": self.entries}, indent=1, sort_keys=True))
        tmp.replace(self.path)


def cmd_plan(settings, files, referenced, manifest, store, args) -> int:
    size = sum(p.stat().st_size for p in files.values())
    print(f"on the volume: {len(files)} files, {size / 2**20:.1f} MB")
    print(f"named by the database: {len(referenced)} keys")
    missing_local = sorted(referenced - set(files))
    unnamed = sorted(set(files) - referenced)
    print(f"named but not on the volume (already broken, nothing to move): {len(missing_local)}")
    print(f"on the volume but named by nothing (strays; moved too, see reconcile): {len(unnamed)}")
    print(f"verified in the manifest so far: {sum(1 for e in manifest.entries.values() if e.get('verified'))}")
    if store is not None:
        store.size("move-photos-to-r2-probe")  # raises if R2 can't be reached or refuses
        print(f"R2 reachable: bucket {settings.blob_r2_bucket}")
    return 0


def cmd_copy(settings, files, referenced, manifest, store, args) -> int:
    failed = 0
    for i, (key, path) in enumerate(files.items(), 1):
        data = path.read_bytes()
        digest = sha256(data)
        entry = manifest.entries.get(key)
        if entry and entry.get("verified") and entry.get("sha256") == digest and entry.get("size") == len(data):
            continue  # done before, and the file hasn't changed since
        store.put(key, data)
        why = check_one(store, key, data)
        manifest.entries[key] = {
            "size": len(data), "sha256": digest, "verified": why is None,
            "problem": why, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        if why:
            failed += 1
            print(f"NOT VERIFIED {key}: {why}")
        if i % 50 == 0:
            manifest.save()
    manifest.save()
    done = sum(1 for k in files if manifest.entries.get(k, {}).get("verified"))
    print(f"copied and verified: {done} of {len(files)} files; failed: {failed}")
    return 0 if done == len(files) else 1


def cmd_verify(settings, files, referenced, manifest, store, args) -> int:
    bad = 0
    for key, path in files.items():
        why = check_one(store, key, path.read_bytes())
        if why:
            bad += 1
            print(f"BAD {key}: {why}")
    named_missing = sorted(k for k in referenced if k in files and store.size(k) is None)
    for key in named_missing:
        print(f"NAMED BY THE DATABASE, NOT IN R2: {key}")
    print(f"files checked: {len(files)}; bad: {bad}; named keys missing in R2: {len(named_missing)}")
    return 0 if not bad and not named_missing else 1


def cmd_reconcile(settings, files, referenced, manifest, store, args) -> int:
    in_r2 = store.keys()
    # What the database names is read again AFTER R2 is listed: a photo
    # posted (or one added to a day's entry) between `main` reading the
    # database and the listing is in R2 but wasn't named then, and would
    # otherwise be deleted as a stray.
    database = Path(settings.database_url.removeprefix("sqlite:///"))
    if database.exists():
        referenced = referenced | referenced_keys(database)
    stray = sorted(k for k in in_r2 if k not in referenced)
    for key in stray:
        print(f"{'deleting' if args.confirm else 'would delete'} {key}")
        if args.confirm:
            store.delete(key)
    print(f"in R2: {len(in_r2)}; named by nothing: {len(stray)}{'' if args.confirm else ' (run with --confirm to delete)'}")
    return 0


def cmd_delete_local(settings, files, referenced, manifest, store, args) -> int:
    if not args.confirm:
        sys.exit("delete-local deletes files from the volume: run it with --confirm")
    deleted, kept = 0, 0
    for key, path in files.items():
        data = path.read_bytes()
        entry = manifest.entries.get(key)
        if not entry or not entry.get("verified") or entry.get("sha256") != sha256(data) or entry.get("size") != len(data):
            kept += 1
            print(f"KEPT {key}: not verified in the manifest as it is now")
            continue
        why = check_one(store, key, data)  # once more, right before deleting
        if why:
            kept += 1
            print(f"KEPT {key}: {why}")
            continue
        path.unlink()
        entry["deleted_locally"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        deleted += 1
    manifest.save()
    print(f"deleted from the volume: {deleted}; kept: {kept}")
    return 0 if kept == 0 else 1


COMMANDS = {
    "plan": cmd_plan, "copy": cmd_copy, "verify": cmd_verify,
    "reconcile": cmd_reconcile, "delete-local": cmd_delete_local,
}


def main(argv: list[str] | None = None, *, store: R2BlobStore | None = None, settings: Settings | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("command", choices=sorted(COMMANDS))
    parser.add_argument("--confirm", action="store_true")
    args = parser.parse_args(argv)
    settings = settings or Settings()
    root = Path(settings.blob_dir)
    database = Path(settings.database_url.removeprefix("sqlite:///"))
    manifest = Manifest(Path(settings.data_dir) / MANIFEST_NAME)
    files = local_files(root) if root.exists() else {}
    referenced = referenced_keys(database) if database.exists() else set()
    if store is None and (args.command != "plan" or os.environ.get("BLOB_R2_BUCKET")):
        store = r2_store(settings)
    return COMMANDS[args.command](settings, files, referenced, manifest, store, args)


if __name__ == "__main__":
    sys.exit(main())
