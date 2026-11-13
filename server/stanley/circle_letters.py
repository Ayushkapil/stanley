"""Letters to the circle (build 42): once a month, each person may write the
whole circle one letter, unsigned. Pure functions only, like `physics.py`:
the months, the moment a month's letters open, and how long they stay.

What a letter is, and who learns what:

- One per person per circle per month, 500 characters at most, written or
  rewritten any time in the writer's own month and sealed until the month
  is over. Nobody is told who has written, or how many have.
- A month's letters open together, once, at the first moment the month is
  over for everyone in the circle: each member's own midnight, by the time
  zone their phone last gave. For a circle in one place that is midnight
  there. It is one moment and not each reader's own midnight because a
  letter that turned up hours after the rest, or changed after others had
  read it, would say which part of the world it came from.
- Opened, a letter is its words and nothing else. The server keeps who
  wrote it, so its writer can change or delete it and so a reported letter
  can be acted on, and never sends that to any phone: not a name, not a
  face, not a tone, not when it was written. They come out in the order of
  their ids, which are random, never the order they were written in.
- Blocks don't hide a letter. Hiding it would name its writer: block
  someone, see which letter goes.
- They're read for seven days and then deleted, not archived.

Nothing here counts anything, and nothing sends a notification.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Iterable
from zoneinfo import ZoneInfo

LETTER_MAX = 500

# How long a month's letters are read for once they've opened.
VISIBLE_FOR = timedelta(days=7)

# The first place on Earth a month ends (UTC+14; the name's sign is POSIX's,
# so it reads backwards). No month is over anywhere before it's over here.
EARLIEST_ZONE = "Etc/GMT-14"


def _zone(name: str | None) -> ZoneInfo | None:
    """A zone by name, or nothing: one bad name kept on a person long ago
    must not stop a circle's letters from opening."""
    if not name:
        return None
    try:
        return ZoneInfo(name)
    except Exception:
        return None


def month_of(now: datetime, tz: str) -> date:
    """The month it is for someone in that zone, as its first day."""
    local = now.astimezone(_zone(tz) or timezone.utc)
    return date(local.year, local.month, 1)


def next_month(month: date) -> date:
    return date(month.year + (month.month == 12), month.month % 12 + 1, 1)


def month_end(month: date, tz: str) -> datetime:
    """The moment that month is over in that zone: midnight as its last day
    ends, which is the first instant of the next month there."""
    after = next_month(month)
    local = datetime(after.year, after.month, 1, tzinfo=_zone(tz) or timezone.utc)
    return local.astimezone(timezone.utc)


def opens_at(month: date, zones: Iterable[str | None]) -> datetime:
    """When a circle's letters for that month open: once the month is over
    for every one of those zones, so everyone reads them together and nobody
    is still writing. With no zone known, the month's end in UTC."""
    ends = [month_end(month, name) for name in {z for z in zones if _zone(z) is not None}]
    return max(ends) if ends else month_end(month, "UTC")


def fades_at(revealed_at: datetime) -> datetime:
    """When opened letters are gone."""
    return revealed_at + VISIBLE_FOR


def label(month: date) -> str:
    """ "2026-11": how a month is named to the app."""
    return f"{month.year:04d}-{month.month:02d}"


def parse(text: str) -> date | None:
    """A month as the app names it, or nothing."""
    try:
        year, month = text.split("-")
        if len(year) != 4 or len(month) != 2:
            return None
        return date(int(year), int(month), 1)
    except ValueError:
        return None
