"""The locked physics (spec §8). Pure functions only — no I/O, no DB.

Every constant here is part of the product's emotional contract; changing one
is a product decision, not a refactor. The decay timeline is the resolved
"decay severity" knob from §16 and ships behind config only in the sense that
this module is the single place it lives.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

# --- Decay timeline (§8.1) ---------------------------------------------------
LIVE_HOURS = 48              # fully visible
FADING_END_HOURS = 120       # progressive fade ends
LAST_LIGHT_END_HOURS = 144   # total public life: 6 days
TOMBSTONE_DAYS = 7           # EXPIRED -> PURGED for unanchored photos

# --- Capture rules (§8.4) ----------------------------------------------------
MIN_GAP = timedelta(hours=12)                  # between consecutive captures
DEVICE_CLAIM_TOLERANCE = timedelta(minutes=10)  # taken_at reconciliation

# --- Circle shape (§16) -------------------------------------------------------
CIRCLE_CAP = 12

# --- States -------------------------------------------------------------------
LIVE = "LIVE"
FADING = "FADING"
LAST_LIGHT = "LAST_LIGHT"
EXPIRED = "EXPIRED"
PURGED = "PURGED"

PUBLIC_STATES = (LIVE, FADING, LAST_LIGHT)

NEXT_STATE = {LIVE: FADING, FADING: LAST_LIGHT, LAST_LIGHT: EXPIRED}

_STATE_END_HOURS = {
    LIVE: LIVE_HOURS,
    FADING: FADING_END_HOURS,
    LAST_LIGHT: LAST_LIGHT_END_HOURS,
}


def state_deadline(state: str, taken_at: datetime) -> datetime | None:
    """When `state` ends, for a photo captured at `taken_at`. None for terminal states."""
    hours = _STATE_END_HOURS.get(state)
    return taken_at + timedelta(hours=hours) if hours is not None else None


def state_at(taken_at: datetime, now: datetime) -> str:
    elapsed = now - taken_at
    if elapsed < timedelta(hours=LIVE_HOURS):
        return LIVE
    if elapsed < timedelta(hours=FADING_END_HOURS):
        return FADING
    if elapsed < timedelta(hours=LAST_LIGHT_END_HOURS):
        return LAST_LIGHT
    return EXPIRED


def decay_progress(taken_at: datetime, now: datetime) -> float:
    """0..1 across the photo's whole public life. Ambient, never numeric in UI."""
    total = LAST_LIGHT_END_HOURS * 3600.0
    elapsed = (now - taken_at).total_seconds()
    return max(0.0, min(1.0, elapsed / total))


def local_capture_date(taken_at_utc: datetime, tz_name: str) -> date:
    return taken_at_utc.astimezone(ZoneInfo(tz_name)).date()


def reconcile_taken_at(server_now: datetime, device_claim: datetime | None) -> datetime:
    """§8.4: taken_at is server-received time reconciled with the device claim
    (tolerance ±10 min). An out-of-tolerance claim is ignored, not rejected —
    no retroactive uploads, but a slightly skewed clock isn't punished."""
    if device_claim is not None and abs(device_claim - server_now) <= DEVICE_CLAIM_TOLERANCE:
        return device_claim
    return server_now


def violates_capture_rules(
    existing_local_dates: set[date],
    last_taken_at: datetime | None,
    new_taken_at: datetime,
    tz_name: str,
) -> str | None:
    """The one-per-day law (§8.4): one photo per local calendar day at capture,
    plus a 12-hour minimum gap that blunts timezone-hopping without punishing
    real travel. Returns an error code or None if the capture is allowed.

    `existing_local_dates` must include soft-deleted photos: deleting today's
    photo does not refund the slot.
    """
    if local_capture_date(new_taken_at, tz_name) in existing_local_dates:
        return "slot_used"
    if last_taken_at is not None and new_taken_at - last_taken_at < MIN_GAP:
        return "too_soon"
    return None
