"""Pilot-delight round: weekly mosaic (Part 2), who-was-there tags (Part 3),
memory milestones (Part 4). (Daily prompt + atmosphere are client-only.)"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select

from stanley.models import PhotoTag

from .conftest import START, make_user

UTC = timezone.utc


# --- Part 2: weekly mosaic ---------------------------------------------------
# START is Tue 2026-06-09; the Sunday of that week is 2026-06-14.


def test_mosaic_appears_on_sunday_with_the_weeks_photos(circle, clock):
    # ana is the creator and never posts, so the creator tz stays UTC.
    circle.ben.post_photo(caption="ben")
    circle.cam.post_photo(caption="cam")
    clock.set(datetime(2026, 6, 14, 12, 0, tzinfo=UTC))  # Sunday
    mosaic = circle.ana.feed().json()["mosaic"]
    assert mosaic is not None
    assert {t["owner"]["display_name"] for t in mosaic["tiles"]} == {"ben", "cam"}
    # view-only: a tile is the photo + its caption + a face — presentation
    # only, nothing interactive, no counts or gesture state.
    assert all(
        set(t.keys()) == {"thumb", "image", "caption", "owner"} for t in mosaic["tiles"]
    )


def test_mosaic_also_on_monday_then_gone_tuesday(circle, clock):
    circle.ben.post_photo()
    assert _mosaic_on(circle, clock, datetime(2026, 6, 15, 12, 0, tzinfo=UTC)) is not None  # Monday
    assert _mosaic_on(circle, clock, datetime(2026, 6, 16, 12, 0, tzinfo=UTC)) is None      # Tuesday


def test_no_mosaic_midweek(circle, clock):
    circle.ben.post_photo()
    assert _mosaic_on(circle, clock, datetime(2026, 6, 10, 12, 0, tzinfo=UTC)) is None  # Wednesday


def test_no_mosaic_when_week_was_empty(circle, clock):
    # nobody posted; no guilt message, just nothing
    assert _mosaic_on(circle, clock, datetime(2026, 6, 14, 12, 0, tzinfo=UTC)) is None


def _mosaic_on(circle, clock, when):
    clock.set(when)
    return circle.ana.feed().json()["mosaic"]


# --- Part 3: who was there ---------------------------------------------------


def test_tags_are_faces_on_the_photo(circle):
    pid = circle.ana.post_photo(caption="lake", tagged=[circle.ben.id, circle.cam.id]).json()["id"]
    photo = [p for p in circle.ben.feed_photos() if p["id"] == pid][0]
    assert {t["display_name"] for t in photo["tagged"]} == {"ben", "cam"}


def test_non_member_tag_ignored(circle, client):
    outsider = make_user(client, "outsider")
    pid = circle.ana.post_photo(tagged=[outsider.id, circle.ben.id]).json()["id"]
    photo = circle.ana.feed_photos()[0]
    assert {t["display_name"] for t in photo["tagged"]} == {"ben"}


def test_untag_self_opt_out(circle):
    pid = circle.ana.post_photo(tagged=[circle.ben.id]).json()["id"]
    assert circle.ben.untag_me(pid).status_code == 204
    assert circle.ana.feed_photos()[0]["tagged"] == []


def test_blocked_member_tag_hidden(circle):
    pid = circle.ana.post_photo(tagged=[circle.ben.id, circle.cam.id]).json()["id"]
    circle.cam.block(circle.ben.id)
    photo = [p for p in circle.cam.feed_photos() if p["id"] == pid][0]
    assert "ben" not in {t["display_name"] for t in photo["tagged"]}


def test_tags_persist_into_held(circle, clock, sweep):
    pid = circle.ana.post_photo(tagged=[circle.ben.id]).json()["id"]
    circle.ben.anchor(pid)
    clock.set(START + timedelta(hours=145))
    sweep()
    memory = circle.ben.memories().json()["threads"][0]["memories"][0]
    assert {t["display_name"] for t in memory["tagged"]} == {"ben"}


def test_tags_purged_with_photo(circle, db):
    pid = circle.ana.post_photo(tagged=[circle.ben.id]).json()["id"]
    circle.ana.delete_photo(pid)
    with db() as s:
        assert s.scalar(select(func.count()).select_from(PhotoTag)) == 0


# --- Part 4: milestones ------------------------------------------------------


def test_circle_age_milestone_surfaces(circle, clock):
    clock.set(START + timedelta(days=31))
    ms = circle.ana.milestones().json()["milestones"]
    assert len(ms) == 1
    assert ms[0]["kind"] == "circle_age"
    assert ms[0]["title"]  # gentle, non-empty text
    assert not any("count" in k or "progress" in k for k in ms[0])  # no gamification


def test_at_most_one_milestone_per_week(circle, clock):
    clock.set(START + timedelta(days=31))
    assert len(circle.ana.milestones().json()["milestones"]) == 1
    clock.advance(timedelta(days=2))  # still within the same week
    assert len(circle.ana.milestones().json()["milestones"]) == 1


def test_milestone_dismiss_is_permanent(circle, clock):
    clock.set(START + timedelta(days=31))
    mid = circle.ana.milestones().json()["milestones"][0]["id"]
    assert circle.ana.dismiss_milestone(mid).status_code == 204
    assert circle.ana.milestones().json()["milestones"] == []


def test_held_count_milestone(circle, clock):
    for d in range(5):  # 2 photos/day × 5 days = 10 holds
        clock.set(START + timedelta(days=d, hours=1))
        b = circle.ben.post_photo().json()["id"]
        c = circle.cam.post_photo().json()["id"]
        circle.ana.anchor(b)
        circle.ana.anchor(c)
    ms = circle.ana.milestones().json()["milestones"]
    held = [m for m in ms if m["kind"] == "held_count"]
    assert held and "10" in held[0]["title"]
