from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


@dataclass
class Settings:
    database_url: str = field(default_factory=lambda: _env("STANLEY_DATABASE_URL", "sqlite:///var/stanley.db"))
    blob_dir: str = field(default_factory=lambda: _env("STANLEY_BLOB_DIR", "var/blobs"))
    secret_key: str = field(default_factory=lambda: _env("STANLEY_SECRET_KEY", "dev-secret-do-not-ship"))
    dev_auth: bool = field(default_factory=lambda: _env("STANLEY_DEV_AUTH", "1") == "1")
    run_sweeper: bool = field(default_factory=lambda: _env("STANLEY_RUN_SWEEPER", "1") == "1")
    sweep_interval_seconds: int = 900  # §13: worker sweep every 15 minutes
    signed_url_ttl_seconds: int = 900  # §9: short-TTL signed URLs (15 min)
    digest_hour: int = 20              # §10 N1: the single evening digest slot (local time)
    max_upload_bytes: int = 15 * 1024 * 1024
