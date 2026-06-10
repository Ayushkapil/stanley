"""M0 Spike 1 (§18): the one-per-day + 12h rule and the decay timeline must be
provably correct before anything is built on them. Pure-function tests plus
property tests across DST shifts, travel, and clock skew."""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from hypothesis import given, settings
from hypothesis import strategies as st

from stanley import physics

UTC = timezone.utc
T0 = datetime(2026, 6, 9, 15, 0, tzinfo=UTC)


# --- decay timeline ----------------------------------------------------------


def test_state_timeline_boundaries():
    assert physics.state_at(T0, T0) == physics.LIVE
    assert physics.state_at(T0, T0 + timedelta(hours=47, minutes=59)) == physics.LIVE
    assert physics.state_at(T0, T0 + timedelta(hours=48)) == physics.FADING
    assert physics.state_at(T0, T0 + timedelta(hours=119, minutes=59)) == physics.FADING
    assert physics.state_at(T0, T0 + timedelta(hours=120)) == physics.LAST_LIGHT
    assert physics.state_at(T0, T0 + timedelta(hours=143, minutes=59)) == physics.LAST_LIGHT
    assert physics.state_at(T0, T0 + timedelta(hours=144)) == physics.EXPIRED


def test_state_deadlines():
    assert physics.state_deadline(physics.LIVE, T0) == T0 + timedelta(hours=48)
    assert physics.state_deadline(physics.FADING, T0) == T0 + timedelta(hours=120)
    assert physics.state_deadline(physics.LAST_LIGHT, T0) == T0 + timedelta(hours=144)
    assert physics.state_deadline(physics.EXPIRED, T0) is None


def test_decay_progress_is_clamped_and_monotone():
    assert physics.decay_progress(T0, T0) == 0.0
    assert physics.decay_progress(T0, T0 - timedelta(hours=1)) == 0.0
    assert abs(physics.decay_progress(T0, T0 + timedelta(hours=72)) - 0.5) < 1e-9
    assert physics.decay_progress(T0, T0 + timedelta(hours=144)) == 1.0
    assert physics.decay_progress(T0, T0 + timedelta(days=30)) == 1.0


# --- taken_at reconciliation (§8.4) -------------------------------------------


def test_device_claim_within_tolerance_is_honored():
    claim = T0 - timedelta(minutes=9)
    assert physics.reconcile_taken_at(T0, claim) == claim


def test_stale_claim_is_ignored_no_retroactive_uploads():
    yesterday = T0 - timedelta(days=1)
    assert physics.reconcile_taken_at(T0, yesterday) == T0
    assert physics.reconcile_taken_at(T0, None) == T0


# --- one-per-day + 12h gap (§8.4) ---------------------------------------------


def test_same_local_day_blocked():
    # Five hours later, same NY calendar day: the slot check fires first.
    dates = {physics.local_capture_date(T0, "America/New_York")}
    assert (
        physics.violates_capture_rules(dates, T0, T0 + timedelta(hours=5), "America/New_York")
        == "slot_used"
    )
    # With the gap satisfied, the same Tokyo calendar day is still blocked:
    tokyo_first = datetime(2026, 6, 9, 15, 0, tzinfo=UTC)  # Jun 10 00:00 Tokyo
    tokyo_second = tokyo_first + timedelta(hours=13)  # Jun 10 13:00 Tokyo
    dates = {physics.local_capture_date(tokyo_first, "Asia/Tokyo")}
    assert (
        physics.violates_capture_rules(dates, tokyo_first, tokyo_second, "Asia/Tokyo")
        == "slot_used"
    )


def test_timezone_hopping_cannot_double_post_a_day():
    # Kiritimati (UTC+14) evening, then "hop" to UTC-12 where it's still the
    # same calendar date — blocked even though 12 hours have passed.
    first = datetime(2026, 6, 9, 8, 0, tzinfo=UTC)  # Jun 9 22:00 Kiritimati
    second = datetime(2026, 6, 9, 20, 0, tzinfo=UTC)  # Jun 9 08:00 at UTC-12
    dates = {physics.local_capture_date(first, "Pacific/Kiritimati")}
    assert physics.local_capture_date(first, "Pacific/Kiritimati") == date(2026, 6, 9)
    assert (
        physics.violates_capture_rules(dates, first, second, "Etc/GMT+12") == "slot_used"
    )


def test_real_travel_is_not_punished():
    # NY evening post, fly to Tokyo, post the next local evening (~22h later).
    first = datetime(2026, 6, 9, 23, 0, tzinfo=ZoneInfo("America/New_York")).astimezone(UTC)
    second = datetime(2026, 6, 11, 21, 0, tzinfo=ZoneInfo("Asia/Tokyo")).astimezone(UTC)
    dates = {physics.local_capture_date(first, "America/New_York")}
    assert physics.violates_capture_rules(dates, first, second, "Asia/Tokyo") is None


def test_exact_12h_gap_is_allowed():
    first = datetime(2026, 6, 9, 23, 0, tzinfo=ZoneInfo("America/New_York")).astimezone(UTC)
    second = first + timedelta(hours=12)  # 11:00 next NY day
    dates = {physics.local_capture_date(first, "America/New_York")}
    assert physics.violates_capture_rules(dates, first, second, "America/New_York") is None
    just_under = first + timedelta(hours=11, minutes=59)
    assert (
        physics.violates_capture_rules(dates, first, just_under, "America/New_York")
        == "too_soon"
    )


DST_CASES = [
    # (tz, first day, last day) — windows straddling a DST transition
    ("America/New_York", date(2026, 3, 1), date(2026, 3, 20)),  # spring forward Mar 8
    ("America/New_York", date(2026, 10, 25), date(2026, 11, 10)),  # fall back Nov 1
    ("Europe/London", date(2026, 3, 20), date(2026, 4, 5)),  # forward Mar 29
    ("Australia/Lord_Howe", date(2026, 9, 25), date(2026, 10, 15)),  # +30min shift Oct 4
]


def test_daily_rhythm_is_never_blocked_across_dst():
    """The liveness property: a person posting once a day at the same local
    hour is never rejected, including across DST shifts in both directions
    and half-hour DST zones."""
    for tz_name, start, end in DST_CASES:
        zi = ZoneInfo(tz_name)
        dates: set[date] = set()
        last = None
        day = start
        while day <= end:
            local = datetime(day.year, day.month, day.day, 20, 0, tzinfo=zi)
            t = local.astimezone(UTC)
            verdict = physics.violates_capture_rules(dates, last, t, tz_name)
            assert verdict is None, f"{tz_name} {day}: blocked with {verdict}"
            dates.add(physics.local_capture_date(t, tz_name))
            last = t
            day += timedelta(days=1)


TZS = [
    "UTC",
    "America/New_York",
    "Europe/London",
    "Asia/Tokyo",
    "Asia/Kathmandu",  # +05:45
    "Australia/Lord_Howe",  # half-hour DST
    "Pacific/Kiritimati",  # +14
    "Etc/GMT+12",  # -12
]


@settings(max_examples=200, deadline=None)
@given(
    st.lists(
        st.tuples(st.integers(0, 60 * 24 * 40), st.sampled_from(TZS)),
        max_size=40,
    )
)
def test_accepted_captures_always_satisfy_both_laws(attempts):
    """Property: fold any stream of capture attempts (any times, any claimed
    timezones) through the rule. Whatever subset is accepted must pairwise
    satisfy both laws: all gaps ≥ 12h and all local capture dates distinct."""
    base = datetime(2026, 2, 1, tzinfo=UTC)
    accepted: list[tuple[datetime, str]] = []
    dates: set[date] = set()
    last = None
    for minutes, tz_name in sorted(attempts, key=lambda a: a[0]):
        t = base + timedelta(minutes=minutes)
        if physics.violates_capture_rules(dates, last, t, tz_name) is None:
            accepted.append((t, tz_name))
            dates.add(physics.local_capture_date(t, tz_name))
            last = t

    times = [t for t, _ in accepted]
    for earlier, later in zip(times, times[1:]):
        assert later - earlier >= physics.MIN_GAP
    capture_dates = [physics.local_capture_date(t, tz) for t, tz in accepted]
    assert len(capture_dates) == len(set(capture_dates))
