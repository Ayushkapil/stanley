#!/bin/sh
# Copies the newest of Stanley's daily database snapshots off Fly, to this
# Mac (the production audit, November 2026). The server keeps seven daily
# snapshots on its own volume (backup.py) and Fly snapshots the volume every
# day for five; this is the copy that survives losing the Fly app itself.
#
#   server/scripts/pull_backup.sh            # fetch the newest snapshot
#   server/scripts/pull_backup.sh --dry-run  # say which one, fetch nothing
#
# Run it daily with launchd (server/scripts/com.stanley.pull-backup.plist,
# DEPLOY.md "Backups"). Needs `fly` signed in (fly auth login) and sqlite3,
# which macOS ships.
#
# The Privacy Policy promises anything deleted is gone from every backup
# within seven days, and this copy is a backup: anything older than six days
# here is deleted on every run, and it is kept outside iCloud-synced folders
# (Documents, Desktop), so no other copy of it is made. The snapshots hold
# people's names, captions and stories: keep this Mac's disk encrypted
# (FileVault).
set -eu

APP="${STANLEY_FLY_APP:-server-earnest-stream-9793}"
DEST="${STANLEY_BACKUP_DIR:-$HOME/Library/Application Support/Stanley/backups}"
FLY="${FLY:-$(command -v fly || echo /opt/homebrew/bin/fly)}"

newest=$("$FLY" ssh console --app "$APP" -C "sh -c 'ls -1 /data/var/backups/*.db | tail -1'" 2>/dev/null \
  | tr -d '\r' | grep '^/data/var/backups/' | tail -1)
if [ -z "$newest" ]; then
  echo "pull_backup: no snapshot found on $APP" >&2
  exit 1
fi
name=$(basename "$newest")

if [ "${1:-}" = "--dry-run" ]; then
  echo "pull_backup: newest snapshot on $APP is $name (not fetched)"
  exit 0
fi

mkdir -p "$DEST"
chmod 700 "$DEST"
if [ ! -f "$DEST/$name" ]; then
  tmp="$DEST/.$name.part"
  rm -f "$tmp"
  "$FLY" ssh sftp get --app "$APP" "$newest" "$tmp" >/dev/null
  check=$(sqlite3 "file:$tmp?mode=ro" "PRAGMA integrity_check" 2>&1 || true)
  if [ "$check" != "ok" ]; then
    rm -f "$tmp"
    echo "pull_backup: $name failed its integrity check: $check" >&2
    exit 1
  fi
  chmod 600 "$tmp"
  mv "$tmp" "$DEST/$name"
  echo "pull_backup: fetched $name"
else
  echo "pull_backup: $name already here"
fi

# Seven days at most, counted from when each was fetched (each is at most a
# day old by then): six full days here, and it's gone.
find "$DEST" -name '*.db' -type f -mtime +5 -print -delete | sed 's/^/pull_backup: deleted /'
