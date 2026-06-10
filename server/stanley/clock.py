from __future__ import annotations

from datetime import datetime, timedelta, timezone


class Clock:
    def now(self) -> datetime:
        raise NotImplementedError


class SystemClock(Clock):
    def now(self) -> datetime:
        return datetime.now(timezone.utc)


class FakeClock(Clock):
    """Test clock. Decay is server-authoritative (§9), so every piece of the
    system takes time from a Clock instead of calling datetime.now directly."""

    def __init__(self, start: datetime):
        if start.tzinfo is None:
            raise ValueError("FakeClock requires an aware datetime")
        self._now = start.astimezone(timezone.utc)

    def now(self) -> datetime:
        return self._now

    def set(self, t: datetime) -> None:
        if t.tzinfo is None:
            raise ValueError("FakeClock requires an aware datetime")
        self._now = t.astimezone(timezone.utc)

    def advance(self, delta: timedelta) -> None:
        self._now += delta
