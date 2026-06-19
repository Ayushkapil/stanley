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

    def __init__(self, *, endpoint: str, bucket: str, access_key: str, secret_key: str):
        import boto3  # lazy: only required when BLOB_BACKEND=r2

        self.bucket = bucket
        self._s3 = boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
        )

    def put(self, key: str, data: bytes) -> None:
        _check_key(key)
        self._s3.put_object(Bucket=self.bucket, Key=key, Body=data, ContentType="image/jpeg")

    def get(self, key: str) -> bytes:
        _check_key(key)
        return self._s3.get_object(Bucket=self.bucket, Key=key)["Body"].read()

    def exists(self, key: str) -> bool:
        _check_key(key)
        from botocore.exceptions import ClientError

        try:
            self._s3.head_object(Bucket=self.bucket, Key=key)
            return True
        except ClientError:
            return False

    def delete(self, key: str) -> None:
        _check_key(key)
        self._s3.delete_object(Bucket=self.bucket, Key=key)

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
