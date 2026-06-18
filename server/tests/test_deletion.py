"""Ownership versus anchors (§5, §8.2): the subject wins. Deletion purges the
image everywhere; the anchorer keeps an honest tombstone and their own words."""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from stanley.models import Comment, Photo, PurgeQueueItem

from .conftest import START


def test_owner_delete_leaves_honest_tombstones(circle, db, app):
    pid = circle.ana.post_photo(caption="us").json()["id"]
    circle.ben.anchor(pid, note="keep")
    circle.ben.comment(pid, "lovely")
    circle.cam.comment(pid, "nice")

    with db() as session:
        blob_key = session.get(Photo, pid).blob_key

    assert circle.ana.delete_photo(pid).status_code == 204
    assert not app.state.storage.exists(blob_key)
    assert circle.ben.feed_photos() == []

    # ben (anchorer) keeps a tombstone and his own comment text only
    threads = circle.ben.memories().json()["threads"]
    memory = threads[0]["memories"][0]
    assert memory["tombstone"] is True
    assert memory["date"] == "2026-06-09"
    assert memory["note"] == "keep"
    assert [c["body"] for c in memory["comments"]] == ["lovely"]

    # cam (no anchor) keeps nothing; cam's comment is gone entirely
    assert circle.cam.memories().json()["threads"] == []
    with db() as session:
        bodies = [
            c.body for c in session.scalars(select(Comment).where(Comment.photo_id == pid))
        ]
    assert bodies == ["lovely"]


def test_owner_delete_does_not_refund_slot(circle):
    pid = circle.ana.post_photo().json()["id"]
    circle.ana.delete_photo(pid)
    r = circle.ana.post_photo()
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "slot_used"


def test_account_deletion_cascades(circle, db):
    ana_pid = circle.ana.post_photo().json()["id"]
    ben_pid = circle.ben.post_photo().json()["id"]
    circle.ben.anchor(ana_pid, note="her last one")
    circle.ana.comment(ben_pid, "see you")

    assert circle.ana.delete_me().status_code == 204

    # ana's session is dead
    assert circle.ana.feed().status_code == 401

    # ana is out of the circle roster
    members = circle.ben.client.get("/circles/mine", headers=circle.ben.h).json()["members"]
    assert {m["display_name"] for m in members} == {"ben", "cam"}

    # ana's photo: image gone, ben keeps a tombstone from a departed friend
    memory = circle.ben.memories().json()["threads"][0]["memories"][0]
    assert memory["tombstone"] is True
    threads = circle.ben.memories().json()["threads"]
    assert threads[0]["friend"]["display_name"] == "departed"

    # ana's words on others' photos are withdrawn
    ben_photo = circle.ben.feed_photos()[0]
    assert ben_photo["comments"] == []


def test_account_deletion_releases_held_anchors(circle, clock, sweep, db, app):
    """When the deleter was the only anchorer, the photo they were holding
    enters the 7-day purge queue."""
    pid = circle.ben.post_photo().json()["id"]
    circle.ana.anchor(pid)
    clock.set(START + timedelta(hours=145))
    sweep()  # expired; retained because ana holds it

    delete_time = START + timedelta(hours=150)
    clock.set(delete_time)
    assert circle.ana.delete_me().status_code == 204
    with db() as session:
        item = session.scalars(
            select(PurgeQueueItem).where(PurgeQueueItem.photo_id == pid)
        ).one()
        assert item.purge_after == delete_time + timedelta(days=7)
        blob_key = session.get(Photo, pid).blob_key

    clock.set(delete_time + timedelta(days=7, minutes=1))
    sweep()
    assert not app.state.storage.exists(blob_key)
    with db() as session:
        assert session.get(Photo, pid).state == "PURGED"
