"""§15: gentle apps still carry ungentle obligations. Block, report, and the
no-public-URLs rule are MVP scope, not Phase 2."""
from __future__ import annotations

from datetime import timedelta

from .conftest import make_user


def test_block_hides_content_bidirectionally(circle):
    ana_pid = circle.ana.post_photo().json()["id"]
    ben_pid = circle.ben.post_photo().json()["id"]
    cam_pid = circle.cam.post_photo().json()["id"]

    assert circle.ben.block(circle.cam.id).status_code == 204

    ben_feed = [p["id"] for p in circle.ben.feed().json()["photos"]]
    cam_feed = [p["id"] for p in circle.cam.feed().json()["photos"]]
    assert cam_pid not in ben_feed and ana_pid in ben_feed
    assert ben_pid not in cam_feed and ana_pid in cam_feed

    # blocked content is unreachable, not just unlisted — uniform 404
    assert circle.cam.anchor(ben_pid).status_code == 404
    assert circle.cam.comment(ben_pid, "hello?").status_code == 404

    assert circle.ben.unblock(circle.cam.id).status_code == 204
    assert cam_pid in [p["id"] for p in circle.ben.feed().json()["photos"]]


def test_comments_by_blocked_member_are_hidden(circle):
    pid = circle.ana.post_photo().json()["id"]
    circle.cam.comment(pid, "from cam")
    circle.ben.block(circle.cam.id)

    ben_view = circle.ben.feed().json()["photos"][0]
    assert all(c["author"]["display_name"] != "cam" for c in ben_view["comments"])
    ana_view = circle.ana.feed().json()["photos"][0]
    assert any(c["body"] == "from cam" for c in ana_view["comments"])


def test_report_creates_reviewable_record(circle):
    pid = circle.ben.post_photo().json()["id"]
    r = circle.ana.report(photo_id=pid, reason="inappropriate")
    assert r.status_code == 201
    body = r.json()
    assert body["id"]
    assert body["review_within_hours"] == 24


def test_signed_urls_expire_and_reject_tampering(circle, clock):
    circle.ana.post_photo()
    url = circle.ben.feed().json()["photos"][0]["urls"]["thumb"]
    assert circle.ben.client.get(url).status_code == 200

    tampered = url[:-1] + ("0" if url[-1] != "0" else "1")
    assert circle.ben.client.get(tampered).status_code == 403

    clock.advance(timedelta(minutes=16))  # past the 15-minute TTL (§9)
    assert circle.ben.client.get(url).status_code == 403


def test_feed_requires_a_circle(client):
    loner = make_user(client, "loner")
    r = loner.feed()
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "no_circle"
