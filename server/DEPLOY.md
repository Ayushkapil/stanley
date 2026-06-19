# Deploying Stanley (pilot)

Stanley is a single Python process plus a reverse proxy for HTTPS. SQLite is the
database (correct at this scale); blobs live on the same disk or in R2. No
Docker required.

## What you need

- A small Linux box (1 vCPU / 1 GB is plenty for a 30-person circle) with a
  persistent disk.
- A domain name pointed at it (for auto-HTTPS).
- Python 3.11+.

## Install

```bash
git clone <repo> && cd stanley/server
python3 -m venv .venv
.venv/bin/pip install -e .            # add ".[r2]" if using Cloudflare R2
```

## Configure (environment variables)

Required for a real (non-dev) deployment:

| Var | Notes |
|-----|-------|
| `STANLEY_SECRET_KEY` | Long random string. **The server refuses to boot without it when dev auth is off.** Rotating it logs everyone out. |
| `APPLE_BUNDLE_ID` | Your app's bundle id (e.g. `app.stanley.ios`). Required for Sign in with Apple. |
| `STANLEY_DEV_AUTH` | Leave unset / `0`. `1` exposes `POST /auth/dev` (dev only). |

Storage and tuning:

| Var | Default | Notes |
|-----|---------|-------|
| `STANLEY_DATABASE_URL` | `sqlite:///var/stanley.db` | Keep on the persistent disk. |
| `STANLEY_BLOB_DIR` | `var/blobs` | Local blob store. |
| `STANLEY_BACKUPS_DIR` | `var/backups` | Daily SQLite snapshots (last 7 kept). |
| `STANLEY_RUN_SWEEPER` | `1` | In-process decay/purge/digest/backup loop. Keep on with a **single** process. |
| `BLOB_BACKEND` | `local` | Set `r2` to use Cloudflare R2 (below). |

Cloudflare R2 (optional — only when `BLOB_BACKEND=r2`):
`BLOB_R2_ENDPOINT`, `BLOB_R2_BUCKET`, `BLOB_R2_ACCESS_KEY`, `BLOB_R2_SECRET_KEY`.
Switching to R2 is a config change only — no code change.

## Run

One process. Do **not** use `--workers N`: the sweeper runs in-process, so
multiple workers would run multiple sweepers against one DB.

```bash
export STANLEY_SECRET_KEY="$(openssl rand -hex 32)"
export APPLE_BUNDLE_ID="app.stanley.ios"
.venv/bin/python -m uvicorn --factory stanley.main:create_app --host 127.0.0.1 --port 8000
```

Run it under a process supervisor so it restarts on crash/reboot — a minimal
systemd unit:

```ini
[Unit]
Description=Stanley
After=network.target

[Service]
WorkingDirectory=/opt/stanley/server
Environment=STANLEY_SECRET_KEY=...   APPLE_BUNDLE_ID=app.stanley.ios
ExecStart=/opt/stanley/server/.venv/bin/python -m uvicorn --factory stanley.main:create_app --host 127.0.0.1 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

## HTTPS (Caddy — auto-certificates)

Caddy gets and renews TLS certs automatically. `/etc/caddy/Caddyfile`:

```
stanley.example.com {
    reverse_proxy 127.0.0.1:8000
    request_body {
        max_size 20MB        # photos are capped at 15MB server-side
    }
}
```

Then `caddy run` (or run it under systemd too). The iOS client's
`STANLEY_API_BASE` should point at `https://stanley.example.com`.

## Backups

The app writes a daily SQLite snapshot to `STANLEY_BACKUPS_DIR` (last 7 kept).
That protects against corruption but lives on the same box — copy those
snapshots off-box (cron + `rclone`/`scp`) for real durability. WAL mode is on,
so snapshots are consistent while the app runs.

## Checklist before inviting the pilot

- [ ] `STANLEY_SECRET_KEY` set (boot fails otherwise) and `STANLEY_DEV_AUTH` unset.
- [ ] `APPLE_BUNDLE_ID` set; Sign in with Apple capability enabled on the app id.
- [ ] HTTPS reachable; `STANLEY_API_BASE` in the iOS release build points at it.
- [ ] Off-box backup copy scheduled.
- [ ] `PRAGMA journal_mode` reports `wal`, `PRAGMA foreign_keys` reports `1`.
