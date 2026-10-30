from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def _env_opt(name: str) -> str | None:
    return os.environ.get(name)


def _data_dir() -> str:
    """Where every piece of persistent state lives: the SQLite file, the blobs,
    the daily backups. One knob, because a hosted deployment gets one mounted
    volume (on Railway, /data/var). Each path below can still be overridden
    individually when they need to live apart."""
    return os.environ.get("STANLEY_DATA_DIR", "var").rstrip("/") or "var"


# Used only when dev auth is on and no real secret is configured. Never signs
# anything in a dev_auth=False (pilot/prod) deployment — startup refuses to boot
# without STANLEY_SECRET_KEY there.
DEV_FALLBACK_SECRET = "dev-only-insecure-secret"


@dataclass
class Settings:
    data_dir: str = field(default_factory=_data_dir)
    database_url: str = field(
        default_factory=lambda: _env("STANLEY_DATABASE_URL", f"sqlite:///{_data_dir()}/stanley.db")
    )
    blob_dir: str = field(default_factory=lambda: _env("STANLEY_BLOB_DIR", f"{_data_dir()}/blobs"))
    backups_dir: str = field(default_factory=lambda: _env("STANLEY_BACKUPS_DIR", f"{_data_dir()}/backups"))
    # No insecure default: None unless explicitly set. create_app() resolves this
    # (dev fallback when dev_auth, hard error otherwise).
    secret_key: str | None = field(default_factory=lambda: _env_opt("STANLEY_SECRET_KEY"))
    dev_auth: bool = field(default_factory=lambda: _env("STANLEY_DEV_AUTH", "0") == "1")
    run_sweeper: bool = field(default_factory=lambda: _env("STANLEY_RUN_SWEEPER", "1") == "1")
    sweep_interval_seconds: int = 900  # §13: worker sweep every 15 minutes
    signed_url_ttl_seconds: int = 900  # §9: short-TTL signed URLs (15 min)
    digest_hour: int = 20              # §10 N1: the single evening digest slot (local time)
    max_upload_bytes: int = 15 * 1024 * 1024
    backups_keep: int = 7

    # The World Today. Optional: with no key, nothing is fetched and the
    # endpoint answers an empty list.
    news_api_key: str | None = field(default_factory=lambda: _env_opt("NEWS_API_KEY"))
    news_interval_seconds: int = 1800  # refetch headlines every 30 minutes

    # Sign in with Apple (Part 2). Required for /auth/apple to function.
    apple_bundle_id: str | None = field(default_factory=lambda: _env_opt("APPLE_BUNDLE_ID"))
    apple_jwks_cache_seconds: int = field(default_factory=lambda: int(_env("APPLE_JWKS_CACHE_SECONDS", "86400")))

    # Blob storage backend (Part 3). "local" (disk) or "r2" (S3-compatible).
    blob_backend: str = field(default_factory=lambda: _env("BLOB_BACKEND", "local"))
    blob_r2_endpoint: str | None = field(default_factory=lambda: _env_opt("BLOB_R2_ENDPOINT"))
    blob_r2_bucket: str | None = field(default_factory=lambda: _env_opt("BLOB_R2_BUCKET"))
    blob_r2_access_key: str | None = field(default_factory=lambda: _env_opt("BLOB_R2_ACCESS_KEY"))
    blob_r2_secret_key: str | None = field(default_factory=lambda: _env_opt("BLOB_R2_SECRET_KEY"))


class ConfigError(RuntimeError):
    """Raised at startup when the deployment is misconfigured (e.g. no secret)."""


def resolve_secret(settings: Settings) -> str:
    """The signing secret, or refuse to boot. Dev auth may fall back to an
    insecure dev secret; a real (dev_auth=False) deployment must set one."""
    if settings.secret_key:
        return settings.secret_key
    if settings.dev_auth:
        return DEV_FALLBACK_SECRET
    raise ConfigError(
        "STANLEY_SECRET_KEY must be set when dev auth is disabled. "
        "Refusing to boot with no signing secret."
    )
