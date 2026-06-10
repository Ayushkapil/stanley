"""The Returned surface (§14): anniversary > near-forgotten > rescue, max one
item per local day, and rest-a-memory as the always-available escape hatch."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from .conftest import START

UTC = timezone.utc


def _setup_anchored_memory(circle, note="kept"):
    pid = circle.ana.post_photo(caption="june ninth").json()["id"]
    assert circle.ben.anchor(pid, note=note).status_code == 201
    return pid


def test_anniversary_resurfaces_a_month_later(circle, clock, sweep):
    pid = _setup_anchored_memory(circle)
    clock.set(datetime(2026, 7, 9, 15, 0, tzinfo=UTC))  # July 9, NY morning
    sweep()  # the photo expired long ago; anchored, so retained
    item = circle.ben.returned().json()["item"]
    assert item is not None
    assert item["source"] == "anniversary"
    assert item["photo"]["id"] == pid
    assert item["photo"]["tombstone"] is False


def test_one_item_per_day_and_same_item_all_day(circle, clock, sweep):
    pid = _setup_anchored_memory(circle)
    clock.set(datetime(2026, 7, 9, 15, 0, tzinfo=UTC))
    sweep()
    first = circle.ben.returned().json()["item"]
    clock.advance(timedelta(hours=3))
    second = circle.ben.returned().json()["item"]
    assert first["photo"]["id"] == second["photo"]["id"] == pid

    # next day: no anniversary match, just-viewed, nothing to rescue -> quiet
    clock.advance(timedelta(hours=24))
    assert circle.ben.returned().json()["item"] is None


def test_near_forgotten_after_ninety_days(circle, clock, sweep):
    pid = _setup_anchored_memory(circle)
    clock.set(START + timedelta(days=100))  # Sep 17 — day-of-month 17 ≠ 9
    sweep()
    item = circle.ben.returned().json()["item"]
    assert item is not None
    assert item["source"] == "near_forgotten"
    assert item["photo"]["id"] == pid


def test_anniversary_outranks_near_forgotten(circle, clock, sweep):
    pid = _setup_anchored_memory(circle)
    clock.set(datetime(2026, 9, 9, 15, 0, tzinfo=UTC))  # 92 days later, day matches
    sweep()
    item = circle.ben.returned().json()["item"]
    assert item["source"] == "anniversary"
    assert item["photo"]["id"] == pid


def test_rescue_surfaces_own_last_light_photo(circle, clock, sweep):
    pid = circle.ana.post_photo().json()["id"]
    clock.set(START + timedelta(hours=121))
    sweep()
    item = circle.ana.returned().json()["item"]
    assert item is not None
    assert item["source"] == "rescue"
    assert item["photo"]["id"] == pid
    assert item["photo"]["state"] == "LAST_LIGHT"
    # rescue is the owner's own Returned item, not anyone else's
    assert circle.ben.returned().json()["item"] is None


def test_rest_a_memory_suppresses_resurfacing(circle, clock, sweep):
    pid = _setup_anchored_memory(circle)
    clock.set(START + timedelta(days=100))
    sweep()
    assert circle.ben.rest(pid).status_code == 201
    assert circle.ben.returned().json()["item"] is None

    # undoable from the archive (§14): un-rest and it may return
    assert circle.ben.unrest(pid).status_code == 204
    item = circle.ben.returned().json()["item"]
    assert item is not None and item["photo"]["id"] == pid


def test_rest_after_serving_suppresses_immediately(circle, clock, sweep):
    pid = _setup_anchored_memory(circle)
    clock.set(START + timedelta(days=100))
    sweep()
    served = circle.ben.returned().json()["item"]
    assert served is not None
    assert circle.ben.rest(pid).status_code == 201
    assert circle.ben.returned().json()["item"] is None

    # rested memories stay in the archive (§14)
    memories = circle.ben.memories().json()["threads"][0]["memories"]
    assert any(m["photo_id" if m["tombstone"] else "id"] == pid for m in memories)
