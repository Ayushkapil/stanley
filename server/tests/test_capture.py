"""Capture is a commitment (§8.4): one slot per local day, no retakes, no
refunds, EXIF scrubbed at ingest."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from io import BytesIO

from PIL import Image
from sqlalchemy import select

from stanley.models import Photo

from .conftest import NY, START, jpeg_bytes, make_user

UTC = timezone.utc


def test_capture_appears_in_circle_feed(circle):
    r = circle.ana.post_photo(caption="move-in day")
    assert r.status_code == 201, r.text
    photo = r.json()
    assert photo["state"] == "LIVE"
    assert photo["decay_progress"] == 0.0

    feed = circle.ben.feed().json()["photos"]
    assert len(feed) == 1
    assert feed[0]["owner"]["display_name"] == "ana"
    assert feed[0]["caption"] == "move-in day"
    assert feed[0]["comments"] == []
    assert feed[0]["anchored_by_me"] is False

    # the signed thumb URL actually serves the image
    thumb = circle.ben.client.get(feed[0]["urls"]["thumb"])
    assert thumb.status_code == 200
    assert thumb.content[:2] == b"\xff\xd8"  # JPEG magic


def test_second_post_same_day_is_409(circle):
    assert circle.ana.post_photo().status_code == 201
    r = circle.ana.post_photo()
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "slot_used"


def test_deleting_today_does_not_refund_the_slot(circle):
    pid = circle.ana.post_photo().json()["id"]
    assert circle.ana.delete_photo(pid).status_code == 204
    r = circle.ana.post_photo()
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "slot_used"


def test_next_day_post_is_allowed(circle, clock):
    assert circle.ana.post_photo().status_code == 201
    clock.advance(timedelta(hours=24))
    assert circle.ana.post_photo().status_code == 201


def test_min_gap_enforced_across_midnight(circle, clock):
    # 23:00 NY on Jun 9
    clock.set(datetime(2026, 6, 10, 3, 0, tzinfo=UTC))
    assert circle.ana.post_photo().status_code == 201
    # 09:00 NY next day: new calendar day but only 10h later
    clock.set(datetime(2026, 6, 10, 13, 0, tzinfo=UTC))
    r = circle.ana.post_photo()
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "too_soon"
    # 11:00 NY: exactly 12h — allowed
    clock.set(datetime(2026, 6, 10, 15, 0, tzinfo=UTC))
    assert circle.ana.post_photo().status_code == 201


def test_timezone_hop_same_local_day_blocked_via_api(circle, clock):
    # Jun 10 00:00 Tokyo
    assert circle.ana.post_photo(tz="Asia/Tokyo").status_code == 201
    clock.advance(timedelta(hours=13))  # gap satisfied, still Jun 10 in Tokyo
    r = circle.ana.post_photo(tz="Asia/Tokyo")
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "slot_used"


def test_bad_timezone_and_bad_image_rejected(circle):
    r = circle.ana.post_photo(tz="Mars/Olympus_Mons")
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "bad_timezone"
    r = circle.ana.post_photo(image=b"not an image at all")
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "bad_image"


def test_stale_device_claim_is_ignored(circle):
    """No retroactive uploads: a claim from yesterday doesn't move taken_at."""
    yesterday = (START - timedelta(days=1)).isoformat()
    r = circle.ana.post_photo(claim=yesterday)
    assert r.status_code == 201
    assert r.json()["taken_at"] == START.isoformat()
    # and the slot consumed is today's, not yesterday's
    assert circle.ana.post_photo().json()["detail"]["code"] == "slot_used"


def test_capture_requires_a_circle(client):
    loner = make_user(client, "loner")
    r = loner.post_photo()
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "no_circle"


def test_exif_is_stripped_to_timestamp_only(circle, app, db):
    """§9 hard requirement: GPS removal; allowlist of {DateTime} only."""
    src = Image.open(BytesIO(jpeg_bytes(with_exif=True)))
    assert 271 in src.getexif(), "test image must carry EXIF to be meaningful"

    pid = circle.ana.post_photo(image=jpeg_bytes(with_exif=True)).json()["id"]
    with db() as session:
        photo = session.get(Photo, pid)
        stored = app.state.storage.get(photo.blob_key)

    exif = Image.open(BytesIO(stored)).getexif()
    tags = set(exif.keys())
    assert 271 not in tags  # Make
    assert 34853 not in tags  # GPSInfo IFD pointer
    assert tags <= {306}


def test_circle_cap_is_twelve(client, circle):
    for i in range(9):
        extra = make_user(client, f"member{i}")
        r = extra.client.post(
            f"/circles/{circle.id}/join",
            json={"invite_token": circle.invite_token},
            headers=extra.h,
        )
        assert r.status_code == 201, f"member {i}: {r.text}"
    thirteenth = make_user(client, "thirteenth")
    r = thirteenth.client.post(
        f"/circles/{circle.id}/join",
        json={"invite_token": circle.invite_token},
        headers=thirteenth.h,
    )
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "circle_full"
