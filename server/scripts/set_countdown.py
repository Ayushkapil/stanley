"""Set, show or clear one circle's countdown (build 35).

A countdown is a flag on a single circle, never a feature: the app draws it
under Today's dateline only when the circle on screen has one, and nothing in
the app or the API makes one. This is the only way in.

    .venv/bin/python scripts/set_countdown.py var/stanley.db find Ayush
    .venv/bin/python scripts/set_countdown.py var/stanley.db show <circle_id>
    .venv/bin/python scripts/set_countdown.py var/stanley.db set <circle_id> india
    .venv/bin/python scripts/set_countdown.py var/stanley.db set <circle_id> path/to/countdown.json
    .venv/bin/python scripts/set_countdown.py var/stanley.db clear <circle_id>

`find` lists the circles a person is in (by the start of their name), so the
right circle can be picked by id. On Fly, piped in so nothing but the row is
written to the machine:

    base64 -i scripts/set_countdown.py | tr -d '\\n' > /tmp/sc.b64
    fly ssh console -C "sh -c 'echo $(cat /tmp/sc.b64) | base64 -d | /app/.venv/bin/python - /data/var/stanley.db find Ayush'"

The fields:
  label               what it's counting toward ("India")
  start_date          the day the plane leaves the origin dot (YYYY-MM-DD)
  target_date         the day itself, in target_tz (YYYY-MM-DD)
  target_tz           an IANA zone; the countdown's days are counted in it
  arrives_at          optional, ISO 8601 with its offset: when the plane lands
                      (the trip's own zone, not target_tz)
  home_until          optional, ISO 8601 with its offset: when it all goes
  messages            optional words for each phase; {days} (the whole days
                      left on the app's clock) and {label} are filled in

  reminders           optional notes tucked in on certain days, keyed by the
                      calendar days left ({"14": "Have you even started
                      packing??"}); each shows on its day only

No emoji in the label or the messages (build 36): the app draws the plane
and the house, and the words are only words, so a symbol there is refused.
A reminder may carry one, the way a friend's note might.

Standard library only, so it runs on the server's own Python.
"""
from __future__ import annotations

import json
import sqlite3
import sys
import unicodedata
from datetime import date, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MESSAGE_KEYS = {"countdown", "two_days", "one_day", "departure", "in_the_air", "home"}

PRESETS = {
    # Ayush's circle, home for Thanksgiving. Departure is Nov 23 in Chicago;
    # landing is Nov 25 02:30 IST (Nov 24 15:00 CST); it all goes at the
    # start of Nov 28 IST, i.e. after 23:59 on Nov 27 there. The words since
    # build 36: "for Home", and no emoji.
    "india": {
        "label": "India",
        "start_date": "2026-11-06",
        "target_date": "2026-11-23",
        "target_tz": "America/Chicago",
        "arrives_at": "2026-11-25T02:30:00+05:30",
        "home_until": "2026-11-28T00:00:00+05:30",
        "messages": {
            "countdown": "{days} days for Home",
            "two_days": "Almost Home",
            "one_day": "Tomorrow",
            "departure": "Bags packed, hearts full. Let's go home.",
            "in_the_air": "You're in for an awesome journey!",
            "home": "How's home?",
        },
        # Every three days or so, a note tucked into the page (build 36).
        "reminders": {
            "17": "The countdown begins!",
            "14": "Have you even started packing??",
            "11": "Shopping done? 👀",
            "8": "Cleaned your place yet?",
            "5": "Packed?? Not yet?",
            "3": "Seriously though, pack.",
            "1": "Tomorrow. TOMORROW.",
        },
    },
}


class Invalid(ValueError):
    pass


def _day(value, field: str) -> date:
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        raise Invalid(f"{field} must be YYYY-MM-DD, not {value!r}")


def _plain(text: str) -> bool:
    """No emoji or other pictographs: nothing in Unicode's "other symbol"
    category, and no variation selector asking for an emoji's picture."""
    return not any(unicodedata.category(ch) == "So" or 0xFE00 <= ord(ch) <= 0xFE0F for ch in text)


def _moment(value, field: str) -> datetime:
    try:
        moment = datetime.fromisoformat(value)
    except (TypeError, ValueError):
        raise Invalid(f"{field} must be ISO 8601, not {value!r}")
    if moment.tzinfo is None:
        raise Invalid(f"{field} needs its offset (e.g. +05:30), or it means nothing")
    return moment


def validate(data: dict) -> dict:
    """The countdown as it will be stored, or Invalid saying what's wrong."""
    if not isinstance(data, dict):
        raise Invalid("a countdown is a JSON object")
    unknown = set(data) - {"label", "start_date", "target_date", "target_tz",
                           "arrives_at", "home_until", "messages", "reminders"}
    if unknown:
        raise Invalid(f"unknown fields: {sorted(unknown)}")
    label = data.get("label")
    if not isinstance(label, str) or not label.strip() or len(label) > 40:
        raise Invalid("label must be a few words")
    if not _plain(label):
        raise Invalid("no emoji in the label: the app draws its own plane")
    start = _day(data.get("start_date"), "start_date")
    target = _day(data.get("target_date"), "target_date")
    if start > target:
        raise Invalid("start_date comes after target_date")
    try:
        ZoneInfo(data.get("target_tz") or "")
    except (ZoneInfoNotFoundError, ValueError):
        raise Invalid(f"target_tz must be an IANA zone, not {data.get('target_tz')!r}")
    arrives = _moment(data["arrives_at"], "arrives_at") if data.get("arrives_at") else None
    until = _moment(data["home_until"], "home_until") if data.get("home_until") else None
    if until and not arrives:
        raise Invalid("home_until needs arrives_at")
    if arrives and until and until <= arrives:
        raise Invalid("home_until must come after arrives_at")
    messages = data.get("messages") or {}
    if not isinstance(messages, dict) or set(messages) - MESSAGE_KEYS:
        raise Invalid(f"messages may only have {sorted(MESSAGE_KEYS)}")
    if not all(isinstance(v, str) and v.strip() for v in messages.values()):
        raise Invalid("every message needs words")
    if not all(_plain(v) for v in messages.values()):
        raise Invalid("no emoji in a message: the app draws its own plane and house")
    reminders = data.get("reminders") or {}
    if not isinstance(reminders, dict):
        raise Invalid("reminders is an object of days left to words")
    span = (target - start).days
    for days, words in reminders.items():
        if not (isinstance(days, str) and days.isdigit() and 1 <= int(days) <= span):
            raise Invalid(f"a reminder's key is the days left, 1 to {span}, not {days!r}")
        if not isinstance(words, str) or not words.strip() or len(words) > 80:
            raise Invalid("a reminder is a short line of words")
    return data


def _connect(path: str, write: bool) -> sqlite3.Connection:
    mode = "rw" if write else "ro"
    return sqlite3.connect(f"file:{path}?mode={mode}", uri=True)


def find(path: str, name: str) -> list[tuple[str, str, str, bool]]:
    """Circles whose members' names start with `name`, ignoring case (SQLite's
    LIKE), with whose each one is, since "Ayush" also matches "ayush"."""
    with _connect(path, write=False) as conn:
        return conn.execute(
            "SELECT c.id, c.name, u.display_name, c.created_by = u.id FROM circles c "
            "JOIN memberships m ON m.circle_id = c.id JOIN users u ON u.id = m.user_id "
            "WHERE u.display_name LIKE ? AND u.deleted_at IS NULL ORDER BY m.joined_at",
            (f"{name}%",),
        ).fetchall()


def show(path: str, circle_id: str):
    with _connect(path, write=False) as conn:
        row = conn.execute("SELECT name, countdown FROM circles WHERE id = ?", (circle_id,)).fetchone()
    if row is None:
        raise Invalid(f"no circle {circle_id}")
    return row[0], (json.loads(row[1]) if row[1] else None)


def set_countdown(path: str, circle_id: str, data: dict | None) -> str:
    """Writes the countdown (None clears it) and returns the circle's name."""
    value = None if data is None else json.dumps(validate(data), ensure_ascii=False)
    conn = _connect(path, write=True)
    try:
        with conn:
            name = conn.execute("SELECT name FROM circles WHERE id = ?", (circle_id,)).fetchone()
            if name is None:
                raise Invalid(f"no circle {circle_id}")
            conn.execute("UPDATE circles SET countdown = ? WHERE id = ?", (value, circle_id))
    finally:
        conn.close()
    return name[0]


def _load(spec: str) -> dict:
    if spec in PRESETS:
        return PRESETS[spec]
    with open(spec, encoding="utf-8") as f:
        return json.load(f)


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in {"find", "show", "set", "clear"}:
        print(__doc__)
        return 2
    path, command = argv[0], argv[1]
    try:
        if command == "find":
            for cid, name, member, created in find(path, argv[2]):
                print(f"{cid}  {name}  ({member}{', created it' if created else ''})")
        elif command == "show":
            name, countdown = show(path, argv[2])
            print(name)
            print(json.dumps(countdown, ensure_ascii=False, indent=2))
        elif command == "set":
            if len(argv) < 4:
                print("set needs a circle id and a preset or a JSON file")
                return 2
            name = set_countdown(path, argv[2], _load(argv[3]))
            print(f"countdown set on {name}")
        else:
            name = set_countdown(path, argv[2], None)
            print(f"countdown cleared on {name}")
    except Invalid as e:
        print(f"refused: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
