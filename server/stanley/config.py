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
    # Daily snapshots, kept seven days: the Privacy Policy promises anything
    # deleted is gone from the backups within seven days (`backup.py`).
    backups_keep: int = 7

    # Rate limits (`ratelimit.py`), on unless STANLEY_RATE_LIMITS=0. Sign-in is
    # counted per IP address, the rest per person. Each number can be raised
    # for an evening without a deploy (fly secrets set ...), e.g. a pilot
    # kickoff where a whole floor signs in from one dorm network at once.
    rate_limits: bool = field(default_factory=lambda: _env("STANLEY_RATE_LIMITS", "1") != "0")
    rate_auth_per_minute: int = field(default_factory=lambda: int(_env("STANLEY_RATE_AUTH_PER_MINUTE", "10")))
    # Ten, not five: five circles each with a day's photo and its one redo is
    # ten honest posts, and a limit must never cost someone their day.
    rate_uploads_per_hour: int = field(default_factory=lambda: int(_env("STANLEY_RATE_UPLOADS_PER_HOUR", "10")))
    rate_avatars_per_hour: int = field(default_factory=lambda: int(_env("STANLEY_RATE_AVATARS_PER_HOUR", "10")))
    rate_stories_per_hour: int = field(default_factory=lambda: int(_env("STANLEY_RATE_STORIES_PER_HOUR", "30")))
    rate_reports_per_hour: int = field(default_factory=lambda: int(_env("STANLEY_RATE_REPORTS_PER_HOUR", "20")))
    # Fly's proxy names the real client in Fly-Client-IP. Trusted only on Fly
    # (FLY_APP_NAME is set on every Fly machine), so nothing else can claim
    # an address by sending the header.
    trust_fly_client_ip: bool = field(default_factory=lambda: bool(_env_opt("FLY_APP_NAME")))

    # The World Today: keyless RSS (PBS, BBC World, Google News's local
    # pages), on unless STANLEY_NEWS=0. Off means nothing is fetched and the
    # endpoints answer an empty list.
    news_enabled: bool = field(default_factory=lambda: _env("STANLEY_NEWS", "1") != "0")
    news_interval_seconds: int = 1800  # refetch an edition every 30 minutes

    # Sign in with Apple (Part 2). Required for /auth/apple to function.
    apple_bundle_id: str | None = field(default_factory=lambda: _env_opt("APPLE_BUNDLE_ID"))
    apple_jwks_cache_seconds: int = field(default_factory=lambda: int(_env("APPLE_JWKS_CACHE_SECONDS", "86400")))

    # Push (build 18): APNs token auth. The key is the .p8 file's contents,
    # from Apple Developer → Keys, with the key's id and the team's id. All
    # three, or nothing is pushed and every notice is only logged, as before.
    # The topic is the app's bundle id. See DEPLOY.md.
    apns_key: str | None = field(default_factory=lambda: _env_opt("APNS_KEY"))
    apns_key_id: str | None = field(default_factory=lambda: _env_opt("APNS_KEY_ID"))
    apns_team_id: str | None = field(default_factory=lambda: _env_opt("APNS_TEAM_ID"))
    apns_topic: str | None = field(
        default_factory=lambda: _env_opt("APNS_TOPIC") or _env_opt("APPLE_BUNDLE_ID")
    )

    @property
    def apns_configured(self) -> bool:
        return bool(self.apns_key and self.apns_key_id and self.apns_team_id and self.apns_topic)

    # Reports (build 18): where to say "a report is waiting", for the person
    # who runs Stanley. An ntfy.sh topic URL, or anything that takes a
    # plain-text POST (`alerts.py`). Unset, a report is only logged.
    report_webhook_url: str | None = field(default_factory=lambda: _env_opt("REPORT_WEBHOOK_URL"))

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
