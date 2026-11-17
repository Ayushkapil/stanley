from __future__ import annotations

import hashlib
import hmac
import re
from datetime import datetime
from pathlib import Path

_KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9/._-]*$")


def _check_key(key: str) -> None:
    if not _KEY_RE.match(key) or ".." in key:
        raise ValueError(f"bad blob key: {key!r}")


class LocalBlobStore:
    """Local-disk blob store. Reads are served by the /blobs route behind a
    short-TTL HMAC signature (no public URLs)."""

    backend = "local"

    def __init__(self, root: str):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        _check_key(key)
        return self.root / key

    def put(self, key: str, data: bytes) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def get(self, key: str) -> bytes:
        return self._path(key).read_bytes()

    def exists(self, key: str) -> bool:
        return self._path(key).is_file()

    def delete(self, key: str) -> None:
        path = self._path(key)
        if path.is_file():
            path.unlink()


# Back-compat alias: tests and older imports use BlobStore.
BlobStore = LocalBlobStore


class R2BlobStore:
    """S3-compatible (Cloudflare R2) blob store. Wired but not the default —
    deploying to R2 is a config change (BLOB_BACKEND=r2), not a code change.
    Reads use presigned GET URLs with the same short TTL as local."""

    backend = "r2"

    def __init__(self, *, endpoint: str, bucket: str, access_key: str, secret_key: str, client=None):
        self.bucket = bucket
        if client is not None:  # a test's stand-in for S3
            self._s3 = client
            return
        import boto3
        from botocore.config import Config

        # R2 takes the region "auto" and v4 signatures; presigned links made
        # without them can be refused.
        self._s3 = boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name="auto",
            config=Config(signature_version="s3v4", retries={"max_attempts": 5, "mode": "standard"}),
        )

    def put(self, key: str, data: bytes) -> None:
        _check_key(key)
        self._s3.put_object(Bucket=self.bucket, Key=key, Body=data, ContentType="image/jpeg")

    def get(self, key: str) -> bytes:
        _check_key(key)
        return self._s3.get_object(Bucket=self.bucket, Key=key)["Body"].read()

    def exists(self, key: str) -> bool:
        return self.size(key) is not None

    def size(self, key: str) -> int | None:
        """The object's size in bytes, or None when there's no such object.
        Any other failure (credentials, the network) is raised, never taken
        for "not there": the migration's verification leans on this."""
        _check_key(key)
        from botocore.exceptions import ClientError

        try:
            return int(self._s3.head_object(Bucket=self.bucket, Key=key)["ContentLength"])
        except ClientError as error:
            code = str(error.response.get("Error", {}).get("Code", ""))
            status = error.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
            if code in ("404", "NoSuchKey", "NotFound") or status == 404:
                return None
            raise

    def delete(self, key: str) -> None:
        _check_key(key)
        self._s3.delete_object(Bucket=self.bucket, Key=key)

    def keys(self) -> list[str]:
        """Every key in the bucket (the migration's reconcile)."""
        paginator = self._s3.get_paginator("list_objects_v2")
        return [obj["Key"] for page in paginator.paginate(Bucket=self.bucket) for obj in page.get("Contents", [])]

    def presigned_url(self, key: str, ttl_seconds: int) -> str:
        return self._s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=ttl_seconds,
        )


def make_blob_store(settings):
    """Pick the blob backend from config. Defaults to local disk."""
    if settings.blob_backend == "r2":
        return R2BlobStore(
            endpoint=settings.blob_r2_endpoint,
            bucket=settings.blob_r2_bucket,
            access_key=settings.blob_r2_access_key,
            secret_key=settings.blob_r2_secret_key,
        )
    return LocalBlobStore(settings.blob_dir)


# --- read URLs ---------------------------------------------------------------


def sign(secret: str, key: str, exp: int) -> str:
    msg = f"{key}|{exp}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha256).hexdigest()


def verify(secret: str, key: str, exp: int, sig: str, now: datetime) -> bool:
    if exp <= int(now.timestamp()):
        return False
    return hmac.compare_digest(sign(secret, key, exp), sig)


def signed_url(secret: str, key: str, now: datetime, ttl_seconds: int) -> str:
    """Local backend: short-TTL signed path served by /blobs (§9/§15)."""
    exp = int(now.timestamp()) + ttl_seconds
    return f"/blobs/{key}?exp={exp}&sig={sign(secret, key, exp)}"


_r2_singleton: R2BlobStore | None = None


def read_url(settings, key: str, now: datetime) -> str:
    """Backend-aware read URL. Local → signed /blobs path; R2 → presigned URL.
    Either way it's short-lived and there are no public URLs."""
    ttl = settings.signed_url_ttl_seconds
    if settings.blob_backend == "r2":
        global _r2_singleton
        if _r2_singleton is None:
            _r2_singleton = make_blob_store(settings)
        return _r2_singleton.presigned_url(key, ttl)
    return signed_url(settings.secret_key, key, now, ttl)


# --- Deleting a blob once the database has let it go (D3, build 77) ---------
#
# A file deleted inside a request or a sweep pass was gone at once, while the
# row that stopped pointing at it was only gone if the transaction committed.
# A rollback after that left rows pointing at files that no longer existed:
# broken photos. Now a deletion is queued on the session and done only after
# it commits; if it rolls back, the files stay with the rows that still name
# them. Like the notifier's pushes, which also wait for the commit.

import logging as _logging

from sqlalchemy import event as _event
from sqlalchemy.orm import Session as _Session

_DOOMED = "stanley.blobs_after_commit"
_log = _logging.getLogger("stanley.storage")


def delete_after_commit(session: _Session, storage, key: str | None) -> None:
    """Delete `key` from `storage` once `session` commits; never if it
    rolls back."""
    if key:
        session.info.setdefault(_DOOMED, []).append((storage, key))


@_event.listens_for(_Session, "after_commit")
def _delete_committed(session: _Session) -> None:
    for storage, key in session.info.pop(_DOOMED, []):
        try:
            storage.delete(key)
        except Exception:  # a file left behind is tidied by nothing worse than disk
            _log.exception("event=blob_delete_failed key=%s", key)


@_event.listens_for(_Session, "after_rollback")
def _keep_on_rollback(session: _Session) -> None:
    session.info.pop(_DOOMED, None)
