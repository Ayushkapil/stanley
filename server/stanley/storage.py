from __future__ import annotations

import hashlib
import hmac
import re
from datetime import datetime
from pathlib import Path

_KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9/._-]*$")


class BlobStore:
    """Local-disk blob store mirroring S3 semantics. The production adapter
    (R2/S3, §9) shares this interface; bucket lifecycle rules back-stop the
    purge queue there."""

    def __init__(self, root: str):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        if not _KEY_RE.match(key) or ".." in key:
            raise ValueError(f"bad blob key: {key!r}")
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


def sign(secret: str, key: str, exp: int) -> str:
    msg = f"{key}|{exp}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha256).hexdigest()


def verify(secret: str, key: str, exp: int, sig: str, now: datetime) -> bool:
    if exp <= int(now.timestamp()):
        return False
    return hmac.compare_digest(sign(secret, key, exp), sig)


def signed_url(secret: str, key: str, now: datetime, ttl_seconds: int) -> str:
    """§9/§15: short-TTL signed URLs for all reads; no public URLs ever."""
    exp = int(now.timestamp()) + ttl_seconds
    return f"/blobs/{key}?exp={exp}&sig={sign(secret, key, exp)}"
