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
| `APPLE_BUNDLE_ID` | Your app's bundle id (e.g. `com.ayushkapileshwar.stanley`). Required for Sign in with Apple. |
| `STANLEY_DEV_AUTH` | Leave unset / `0`. `1` exposes `POST /auth/dev` (dev only). |

Storage and tuning:

| Var | Default | Notes |
|-----|---------|-------|
| `STANLEY_DATA_DIR` | `var` | **The one storage knob.** All three paths below default inside it, so on a hosted box you set only this — e.g. `/data/var` on a mounted volume. Created at startup if missing. |
| `STANLEY_DATABASE_URL` | `sqlite:///$STANLEY_DATA_DIR/stanley.db` | Override only to move the DB off the data dir. |
| `STANLEY_BLOB_DIR` | `$STANLEY_DATA_DIR/blobs` | Local blob store. |
| `STANLEY_BACKUPS_DIR` | `$STANLEY_DATA_DIR/backups` | Daily SQLite snapshots, none older than seven days (see "Backups"). |
| `STANLEY_RUN_SWEEPER` | `1` | In-process decay/purge/digest/backup loop. Keep on with a **single** process. |
| `BLOB_BACKEND` | `local` | Set `r2` to use Cloudflare R2 (below). |

Optional features:

| Var | Notes |
|-----|-------|
| `STANLEY_NEWS` | The World Today, on by default, keyless RSS. National edition: PBS News Hour (`https://www.pbs.org/newshour/feeds/rss/headlines`) for the US and for phones that haven't been located, BBC World (`https://feeds.bbci.co.uk/news/world/rss.xml`) elsewhere. Nearby edition: Google News's local feed for a town (`https://news.google.com/rss/headlines/section/geo/<town>`), only for phones with location permission. The US edition is fetched at startup and every 30 minutes; the others when someone asks. Set `STANLEY_NEWS=0` to turn it off: nothing is fetched and `GET /news/today` and `GET /news/nearby` return `[]`. The host needs outbound HTTPS to www.pbs.org, feeds.bbci.co.uk and news.google.com. **Terms:** Google's feed says it is for "a personal feed reader for personal, non-commercial use"; PBS's and the BBC's haven't been checked. A judgement call for a private pilot; revisit the sources before any wider release. |

Rate limits (the production audit, `ratelimit.py`; all optional, these are
the defaults). Each can be raised for an evening with `fly secrets set`, no
code change: a pilot kickoff where a whole dorm floor signs in from one Wi-Fi
address at once will want `STANLEY_RATE_AUTH_PER_MINUTE` at 60 or so.

| Var | Default | Notes |
|-----|---------|-------|
| `STANLEY_RATE_LIMITS` | `1` | `0` turns every limit off. |
| `STANLEY_RATE_AUTH_PER_MINUTE` | `10` | Sign-ins per IP address. On Fly the address is `Fly-Client-IP`. |
| `STANLEY_RATE_UPLOADS_PER_HOUR` | `10` | Photo posts per person (five circles, a photo and a redo in each, is ten honest posts). |
| `STANLEY_RATE_AVATARS_PER_HOUR` | `10` | Profile photo uploads per person. |
| `STANLEY_RATE_STORIES_PER_HOUR` | `30` | Stories per person. |
| `STANLEY_RATE_REPORTS_PER_HOUR` | `20` | Reports per person, so nobody can flood the operator's phone. |

Over a limit is a 429 with `{"code": "slow_down"}` and `Retry-After`; the app
says "That's a lot at once" and a queued photo waits for its next try. Each
refusal logs `event=rate_limited bucket=<name>` (never who).

Push notifications (build 18; without these, notices are logged and nothing is
pushed):

| Var | Notes |
|-----|-------|
| `APNS_KEY` | The contents of the APNs key file (`AuthKey_<KEYID>.p8`), PEM text including the `-----BEGIN PRIVATE KEY-----` lines. |
| `APNS_KEY_ID` | The key's 10-character Key ID. |
| `APNS_TEAM_ID` | The Apple Developer team id (Stanley's is `6P882KH9CZ`, the `DEVELOPMENT_TEAM` in `ios/project.yml`). |
| `APNS_TOPIC` | Optional. The app's bundle id; defaults to `APPLE_BUNDLE_ID`. |
| `REPORT_WEBHOOK_URL` | Optional. Where to say "A report is waiting for review" when someone files a report: an ntfy.sh topic URL (see "Report alerts" below). Unset, reports are only logged. |

### Setting up push (APNs) — required before notices reach phones

Stanley pushes straight to Apple (token auth over HTTP/2, `stanley/apns.py`),
no Firebase. Only two notices exist, both off until someone turns them on in
Settings → Quiet: the last-light notice for their own photo, and the evening
note when their circle has posted (at most one a day, no count, no names).

1. **Create the key.** developer.apple.com → Certificates, Identifiers &
   Profiles → Keys → **+**. Name it (e.g. "Stanley APNs"), tick **Apple Push
   Notifications service (APNs)**, choose **Sandbox & Production**, Continue,
   Register. **Download the .p8 now** — Apple lets you download it once.
   Note the **Key ID** shown on the page.
2. **Turn on Push for the App ID.** Identifiers → `com.ayushkapileshwar.stanley`
   → tick **Push Notifications** → Save. (Xcode's automatic signing usually
   does this itself the first time it archives a build with the
   `aps-environment` entitlement, which build 18 has. If the archive fails with
   a provisioning error about push, this is the step.)
3. **Give the server the key** (from `server/`):

   ```bash
   fly secrets set APNS_KEY="$(cat ~/Downloads/AuthKey_XXXXXXXXXX.p8)" \
     APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=6P882KH9CZ
   ```

   Setting secrets restarts the machine. The startup log no longer says
   "APNs isn't configured".
4. **Check it.** On a phone running a TestFlight build, Settings → Quiet →
   turn on a notice and allow notifications. `push_tokens` gains a row with
   environment `production`. A build run from Xcode registers a `sandbox`
   token, which the server sends to Apple's sandbox host. The evening note
   goes out at 20:00 in the person's own time zone when someone else in one of
   their circles posted that day.

Apple answers a dead token (app deleted, notifications turned off for good)
with 410 or `BadDeviceToken`; the server deletes that token. Any other failure
is logged and the notice is simply missed; nothing retries into a second push.

### Report alerts (ntfy) — so the 24-hour promise isn't a daily chore

The Terms promise every report is read within a day. Each report logs a
warning (`A report is waiting for review: <id>`), and with
`REPORT_WEBHOOK_URL` set it also POSTs that one line, and nothing else, to a
URL (`stanley/alerts.py`): no reporter, no photo, no reason. ntfy.sh is free
and needs no account.

1. **Pick a topic name nobody could guess.** Anyone who knows an ntfy topic's
   name can read it, so the name is the secret:

   ```bash
   python3 -c "import secrets; print('stanley-reports-' + secrets.token_hex(12))"
   ```

2. **Subscribe on your phone.** Install **ntfy** from the App Store, tap
   **+**, and subscribe to that topic name on the default server (ntfy.sh).
3. **Give the server the URL** (from `server/`):

   ```bash
   fly secrets set REPORT_WEBHOOK_URL=https://ntfy.sh/stanley-reports-<your suffix>
   ```

4. **Check it.** Report a photo from a test account; the phone shows
   "Stanley: A report is waiting for review". Then read the report itself on
   the machine (`fly ssh console`, the `reports` table).

The alert goes out after the report is saved and the response sent; if ntfy
is slow or down, the report is unaffected and the failure is logged (without
the URL).

Cloudflare R2 (optional — only when `BLOB_BACKEND=r2`):
`BLOB_R2_ENDPOINT`, `BLOB_R2_BUCKET`, `BLOB_R2_ACCESS_KEY`, `BLOB_R2_SECRET_KEY`.
Switching to R2 is a config change only — no code change.

## Run

One process. Do **not** use `--workers N`: the sweeper runs in-process, so
multiple workers would run multiple sweepers against one DB.

```bash
export STANLEY_SECRET_KEY="$(openssl rand -hex 32)"
export APPLE_BUNDLE_ID="com.ayushkapileshwar.stanley"
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
Environment=STANLEY_SECRET_KEY=...   APPLE_BUNDLE_ID=com.ayushkapileshwar.stanley
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
   | `APPLE_BUNDLE_ID` | `com.ayushkapileshwar.stanley` |
   | `STANLEY_DEV_AUTH` | `0` |
   | `STANLEY_DATA_DIR` | `/data/var` — inside the mounted volume |

4. **Deploy.** Railway assigns an HTTPS domain and injects `$PORT`, which the
   `Procfile` honours. Point the iOS release build's `STANLEY_API_BASE` at that
   domain, and use `GET /health` as the healthcheck path.

Keep the service at **one replica**. A second one would run a second decay
sweeper against the same database.

## Backups

Three copies, each kept no longer than the Privacy Policy allows ("anything
deleted is gone from our backups within seven days"):

1. **On the volume** (automatic). The server's first pass each UTC day writes
   a consistent snapshot of the database (SQLite's online backup API, safe
   while the app runs) to `STANLEY_BACKUPS_DIR`, then deletes any snapshot
   older than seven days and keeps at most seven. A deploy or restart writes
   one too. It also runs `PRAGMA optimize` daily and `VACUUM` on Sundays. This
   protects against a corrupted database, not against losing the volume.
2. **Fly volume snapshots** (automatic, off the machine). Fly snapshots the
   whole volume (database and photos) once a day and keeps each for five days:
   `fly volumes snapshots list vol_v8eygoljqj2j02kv`. Restore by creating a new
   volume from a snapshot (`fly volumes create stanley_data --snapshot-id
   <id> ...`) and attaching it. Don't raise the retention past seven days.
3. **Off Fly, on the operator's Mac** (set up once, then automatic).
   `scripts/pull_backup.sh` copies the newest snapshot down with `fly ssh
   sftp`, checks it with `PRAGMA integrity_check`, keeps it in
   `~/Library/Application Support/Stanley/backups` (not iCloud-synced), and
   deletes copies older than six days. It covers losing the Fly app itself.
   Database only: photos are on the volume (and in layer 2).

   ```bash
   server/scripts/pull_backup.sh --dry-run    # which snapshot it would fetch
   mkdir -p ~/Library/Application\ Support/Stanley
   cp server/scripts/pull_backup.sh ~/Library/Application\ Support/Stanley/
   sed "s#HOMEDIR#$HOME#g" server/scripts/com.stanley.pull-backup.plist > ~/Library/LaunchAgents/com.stanley.pull-backup.plist
   launchctl load ~/Library/LaunchAgents/com.stanley.pull-backup.plist
   ```

   It runs daily at 10:00 and logs to `~/Library/Logs/stanley-pull-backup.log`.
   Keep FileVault on: the snapshots hold names, captions and stories.

**Restoring the database** from a snapshot, without replacing a file the
running app has open: upload the snapshot beside it (`fly ssh sftp shell`,
then `put <snapshot>.db /data/var/restore.db`), point the app at it with
`fly secrets set STANLEY_DATABASE_URL=sqlite:////data/var/restore.db` (which
restarts the machine onto the restored file), then run the integrity check
below against `/data/var/restore.db`. Rows newer than the snapshot are lost;
photo files newer than it become unreferenced (harmless, and the check lists
them).

## Disk

Each photo keeps about 3 MB on the volume (a full-size original of about
2.8 MB, a 1080px copy of about 260 KB and a thumbnail of about 26 KB, measured
on Fly in November 2026). An unheld photo's files are deleted about thirteen
days after it's posted; held ones stay. A 30-person circle posting daily
therefore needs about 1.2 GB at steady state, plus every held photo, so **the
1 GB volume the app started on fills in about ten days of real use**, after
which every post fails. Extend it before the pilot (it can grow, never shrink;
about $0.15 per GB per month):

```bash
fly volumes extend vol_v8eygoljqj2j02kv --size 10 --app server-earnest-stream-9793
```

The server logs `WARNING stanley: event=disk_low free_percent=<n>` once a day
when the volume is more than three quarters full.

## Integrity check

`scripts/integrity_check.py` opens the database read-only and checks SQLite's
integrity, foreign keys, orphaned rows (a photo, story, hold, like, tag,
membership or report pointing at nothing), anything left of a deleted
account, purged photos still holding words or files, and photo files with no
row. Locally:

```bash
.venv/bin/python scripts/integrity_check.py var/stanley.db var/blobs
```

On Fly, without writing anything to the machine:

```bash
B64=$(base64 -i scripts/integrity_check.py | tr -d '\n')
fly ssh console --app server-earnest-stream-9793 -C "sh -c 'echo $B64 | base64 -d | /app/.venv/bin/python - /data/var/stanley.db /data/var/blobs'"
```

## Monitoring

- **Logs.** `fly logs --app server-earnest-stream-9793`, or the dashboard's
  Monitoring tab. Since the production audit the app's own lines reach the
  log (before, uvicorn's setup dropped everything below WARNING). One line
  per event, with opaque ids and never a name or anything someone wrote:
  `event=signup`, `photo_posted`, `photo_deleted`, `circle_created`,
  `circle_joined`, `account_deleted`, `report_filed`, `block`,
  `words_refused`, `rate_limited`, `server_error` (with the route template),
  `disk_low`, `health_failed`. Fly keeps logs for a limited time; search them
  in the dashboard (Monitoring → Logs).
- **Metrics.** CPU, memory, network, disk and HTTP response codes and
  latency for the machine: Fly dashboard → the app → Metrics (a hosted
  Grafana at `fly-metrics.net`). `fly status` and `fly machine status` from a
  terminal. Volume usage: `fly ssh console -C "df -h /data"`.
- **Uptime.** `GET /health` answers `{"status": "ok"}` only when the database
  answers a read, and 503 otherwise. Point a free monitor at it (see
  `PRODUCTION_CHECKLIST.md` for UptimeRobot's steps): every 5 minutes, alert
  on anything but 200.
- **Crashes.** The iOS app reports crashes to Sentry only in a build with a
  DSN in `ios/project.yml` (`STANLEY_SENTRY_DSN`); the server has no Sentry.
  A server error is a `server_error` line in the log and a bare
  `{"detail": {"code": "server_error"}}` to the client, never a traceback.

## Checklist before inviting the pilot

- [ ] `STANLEY_SECRET_KEY` set (boot fails otherwise) and `STANLEY_DEV_AUTH` unset.
- [ ] Persistent storage is really persistent — `STANLEY_DATA_DIR` on the mounted
      volume (Railway) or the persistent disk (VPS), not a container's local disk.
- [ ] `APPLE_BUNDLE_ID` set; Sign in with Apple capability enabled on the app id.
- [ ] Push: `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID` set and Push Notifications
      enabled on the app id (see "Setting up push" above). Without them the two
      notices are logged and never reach a phone.
- [ ] Reports reach you: `REPORT_WEBHOOK_URL` set to your ntfy topic and the
      ntfy app subscribed to it (see "Report alerts" above). Without it, check
      the logs or the `reports` table every day.
- [ ] The Privacy Policy is public at `https://<host>/privacy` (and the Terms at
      `/terms`); that URL goes in App Store Connect → App Privacy.
- [ ] News: after deploy, the logs show `news refreshed: 12 stories for
      national:us` within a few seconds of startup. If not, look for `news
      fetch for national:us failed` (outbound HTTPS to www.pbs.org), or set
      `STANLEY_NEWS=0` to turn it off. A phone with location allowed adds a
      `nearby:US:<town>` line the first time its World tab opens.
- [ ] HTTPS reachable; `STANLEY_API_BASE` in the iOS release build points at it.
- [ ] Off-box backup copy scheduled (`pull_backup.sh` under launchd, "Backups" above).
- [ ] The volume is big enough for a month of photos ("Disk" above).
- [ ] An uptime monitor watches `/health` ("Monitoring" above).
- [ ] The integrity check passes against the live database.
- [ ] `PRAGMA journal_mode` reports `wal` — that one is stored in the file.
      `foreign_keys` is **per-connection**: the app's PRAGMA listener sets it on
      every connection it opens, so an external `sqlite3` shell will always
      report `0` on the same file. That is not a fault, and not something to
      check from outside the app.
