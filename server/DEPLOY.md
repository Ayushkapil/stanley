# Deploying Stanley (pilot)

Stanley is a single Python process plus a reverse proxy for HTTPS. SQLite is the
database (correct at this scale); blobs live on the same disk or in R2. No
Docker required.

Two ways to run it: **a Linux box you manage** (below), or **[Railway](#railway-managed-alternative)**,
which builds from the repo and handles HTTPS for you. Either way it is one
process — never two, because the decay sweeper runs in-process.

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
| `STANLEY_DATA_DIR` | `var` | **The one storage knob.** All three paths below default inside it, so on a hosted box you set only this — e.g. `/data/var` on a mounted volume. Created at startup if missing. |
| `STANLEY_DATABASE_URL` | `sqlite:///$STANLEY_DATA_DIR/stanley.db` | Override only to move the DB off the data dir. |
| `STANLEY_BLOB_DIR` | `$STANLEY_DATA_DIR/blobs` | Local blob store. |
| `STANLEY_BACKUPS_DIR` | `$STANLEY_DATA_DIR/backups` | Daily SQLite snapshots (last 7 kept). |
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

## Railway (managed alternative)

Railway builds straight from the GitHub repo and terminates HTTPS for you — no
box, no systemd, no Caddy. The root `Procfile` and `requirements.txt` are all it
needs; it auto-detects Python from them, so there is deliberately no Dockerfile.

1. **New Project → Deploy from GitHub repo →** pick this repo.
2. **Add a persistent volume mounted at `/data`.** Without one, the SQLite file
   and every photo sit on the container's ephemeral disk and are destroyed on
   the next deploy. This is the step that actually matters.
3. **Set the environment variables:**

   | Var | Value |
   |-----|-------|
   | `STANLEY_SECRET_KEY` | a long random string — `openssl rand -hex 32` |
   | `APPLE_BUNDLE_ID` | `app.stanley.ios` |
   | `STANLEY_DEV_AUTH` | `0` |
   | `STANLEY_DATA_DIR` | `/data/var` — inside the mounted volume |

4. **Deploy.** Railway assigns an HTTPS domain and injects `$PORT`, which the
   `Procfile` honours. Point the iOS release build's `STANLEY_API_BASE` at that
   domain, and use `GET /health` as the healthcheck path.

Keep the service at **one replica**. A second one would run a second decay
sweeper against the same database.

## Backups

The app writes a daily SQLite snapshot to `STANLEY_BACKUPS_DIR` (last 7 kept).
That protects against corruption but lives on the same box — copy those
snapshots off-box (cron + `rclone`/`scp`) for real durability. WAL mode is on,
so snapshots are consistent while the app runs.

## Checklist before inviting the pilot

- [ ] `STANLEY_SECRET_KEY` set (boot fails otherwise) and `STANLEY_DEV_AUTH` unset.
- [ ] Persistent storage is really persistent — `STANLEY_DATA_DIR` on the mounted
      volume (Railway) or the persistent disk (VPS), not a container's local disk.
- [ ] `APPLE_BUNDLE_ID` set; Sign in with Apple capability enabled on the app id.
- [ ] HTTPS reachable; `STANLEY_API_BASE` in the iOS release build points at it.
- [ ] Off-box backup copy scheduled.
- [ ] `PRAGMA journal_mode` reports `wal`, `PRAGMA foreign_keys` reports `1`.
