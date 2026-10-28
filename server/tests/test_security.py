"""Pre-release security pass: isolation, injection, auth, uploads, spam.

These are adversarial by design — each one tries to get something it should
not be able to get, from the outside, through the real API.
"""
from __future__ import annotations

import io
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from PIL import Image
from sqlalchemy import func, select

from stanley.models import Like, Photo

from .conftest import NY, jpeg_bytes, make_user

# Payloads that must be stored as inert text, never interpreted.
INJECTION = "'; DROP TABLE photos; --"
XSS = "<script>alert('xss')</script>"
SECOND_ORDER = "Robert'); DROP TABLE users; --"


# --- cross-circle isolation --------------------------------------------------


@pytest.fixture
def outsider(client):
    """A user in a different circle entirely."""
    other = make_user(client, "outsider")
    r = other.client.post("/circles", json={"name": "another floor"}, headers=other.h)
    assert r.status_code == 201
    return other


def test_outsider_cannot_reach_another_circles_photo(circle, outsider):
    """Every path to someone else's circle is a uniform 404 — reachability
    never leaks existence."""
    pid = circle.ana.post_photo(caption="ours").json()["id"]

    assert outsider.anchor(pid).status_code == 404
    assert outsider.like(pid).status_code == 404
    assert outsider.comment(pid, "hello").status_code == 404
    assert outsider.unanchor(pid).status_code in (204, 404)  # no-op or not found
    # Owner-only surfaces stay owner-only even for a stranger.
    assert outsider.anchors_of(pid).status_code in (403, 404)
    assert outsider.likes_of(pid).status_code in (403, 404)
    # And it is simply not in their feed.
    assert pid not in [p["id"] for p in outsider.feed_photos()]


def test_outsider_cannot_delete_another_users_photo(circle, outsider, db):
    pid = circle.ana.post_photo().json()["id"]
    assert outsider.delete_photo(pid).status_code == 404
    with db() as s:
        assert s.get(Photo, pid).deleted_at is None  # still intact


def test_circle_member_cannot_delete_someone_elses_photo(circle, db):
    """Same circle is not the same as same owner."""
    pid = circle.ana.post_photo().json()["id"]
    assert circle.ben.delete_photo(pid).status_code == 404
    with db() as s:
        assert s.get(Photo, pid).deleted_at is None


# --- blocking, across every surface -----------------------------------------


def test_block_hides_content_on_every_path(circle, clock):
    """A block must hold on the feed, memories, likes, comments, moments,
    mosaic and returned alike — one leak is the whole guarantee."""
    ana_pid = circle.ana.post_photo(caption="ana here", location="Collins").json()["id"]
    circle.ben.post_photo(caption="ben here", location="Collins")
    circle.ben.anchor(ana_pid, note="kept before the block")
    circle.ben.comment(ana_pid, "said before the block")

    circle.ben.block(circle.ana.id)

    # Today: gone, including inside any shared moment.
    assert ana_pid not in [p["id"] for p in circle.ben.feed_photos()]
    for item in circle.ben.feed_items():
        if item["kind"] != "photo":
            assert ana_pid not in [p["id"] for p in item.get("photos", [])]

    # Direct access is 404 in both directions.
    assert circle.ben.like(ana_pid).status_code == 404
    assert circle.ben.comment(ana_pid, "after").status_code == 404
    assert circle.ben.anchor(ana_pid).status_code == 404

    # Member profile is hidden both ways.
    assert circle.ben.client.get(f"/members/{circle.ana.id}", headers=circle.ben.h).status_code == 404
    assert circle.ana.client.get(f"/members/{circle.ben.id}", headers=circle.ana.h).status_code == 404

    # The archive honours it too: a held photo from a blocked person is not
    # served back while the block stands (it is hidden, never deleted).
    held = [m["id"] for t in circle.ben.memories().json()["threads"] for m in t["memories"]]
    assert ana_pid not in held
    assert circle.ben.rested().status_code == 200

    # Unblocking restores the kept memory untouched.
    circle.ben.unblock(circle.ana.id)
    held_again = [m["id"] for t in circle.ben.memories().json()["threads"] for m in t["memories"]]
    assert ana_pid in held_again
    circle.ben.block(circle.ana.id)

    # Returned and mosaic are reachable and never carry the blocked photo.
    r = circle.ben.returned()
    assert r.status_code == 200
    item = r.json().get("item")
    if item is not None:
        assert item.get("photo", {}).get("id") != ana_pid
    feed = circle.ben.feed().json()
    if feed.get("mosaic"):
        for tile in feed["mosaic"].get("tiles", []):
            assert tile.get("owner", {}).get("id") != circle.ana.id


# --- injection and markup ----------------------------------------------------


def test_sql_injection_payloads_are_inert_text(circle, db):
    """Parameter binding means these are stored verbatim and nothing runs."""
    r = circle.ana.post_photo(caption=INJECTION, location=SECOND_ORDER)
    assert r.status_code == 201
    pid = r.json()["id"]
    assert r.json()["caption"] == INJECTION
    assert r.json()["location"] == SECOND_ORDER

    assert circle.ben.comment(pid, INJECTION).status_code == 201
    assert circle.ana.client.patch(
        "/me/profile", json={"bio": INJECTION, "username": "ana"}, headers=circle.ana.h
    ).status_code == 200
    assert circle.ana.set_note(circle.id, SECOND_ORDER).status_code in (200, 201)

    # The tables are all still there, with the row still in them.
    with db() as s:
        assert s.get(Photo, pid) is not None
        assert s.scalar(select(func.count()).select_from(Photo)) >= 1
    assert circle.ben.feed_photos()[0]["caption"] == INJECTION


def test_markup_is_stored_verbatim_never_interpreted(circle):
    """SwiftUI's Text renders plain strings, so the server's job is simply to
    hand back exactly what was written — no escaping, no stripping, no HTML."""
    r = circle.ana.post_photo(caption=XSS)
    assert r.status_code == 201
    assert r.json()["caption"] == XSS
    assert circle.ben.feed_photos()[0]["caption"] == XSS

    circle.ana.client.patch("/me/profile", json={"bio": XSS}, headers=circle.ana.h)
    assert circle.ana.client.get("/me", headers=circle.ana.h).json()["bio"] == XSS

    circle.ana.set_note(circle.id, XSS)
    note = circle.ben.feed().json().get("note")
    assert note is None or note["text"] == XSS

    # And the response is JSON, not a document — nothing can execute.
    r = circle.ben.feed()
    assert r.headers["content-type"].startswith("application/json")


# --- tokens ------------------------------------------------------------------


@pytest.mark.parametrize(
    "token",
    [
        "",                       # empty
        "not-a-jwt",              # malformed
        "a.b.c",                  # three segments, still junk
        "Bearer Bearer nested",   # confused prefix
        "e" * 4000,               # absurdly long
    ],
)
def test_malformed_tokens_are_401_never_500(client, token):
    r = client.get("/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401, f"{token[:20]!r} -> {r.status_code}"


def test_token_signed_with_the_wrong_secret_is_401(app, client):
    body = client.post("/auth/dev", json={"display_name": "ana"}).json()
    now = datetime.now(timezone.utc)
    forged = jwt.encode(
        {
            "sub": body["user"]["id"],
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(days=1)).timestamp()),
        },
        "not-the-servers-secret",
        algorithm="HS256",
    )
    assert client.get("/me", headers={"Authorization": f"Bearer {forged}"}).status_code == 401


def test_alg_none_token_is_rejected(app, client):
    """The classic JWT downgrade: an unsigned token must never be trusted."""
    body = client.post("/auth/dev", json={"display_name": "ana"}).json()
    unsigned = jwt.encode({"sub": body["user"]["id"]}, key="", algorithm="none")
    assert client.get("/me", headers={"Authorization": f"Bearer {unsigned}"}).status_code == 401


def test_missing_authorization_header_is_401(client):
    assert client.get("/me").status_code == 401


# --- uploads -----------------------------------------------------------------


def test_non_image_renamed_as_jpeg_is_rejected(circle):
    r = circle.ana.post_photo(image=b"MZ\x90\x00this is an executable, not a photo")
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "bad_image"


def test_zero_byte_upload_is_rejected(circle):
    # Posted directly: the conftest helper substitutes a real JPEG for empty
    # bytes (b"" is falsy), which would quietly defeat the point of the test.
    files = {"file": ("photo.jpg", b"", "image/jpeg")}
    r = circle.ana.client.post(
        "/photos", files=files, data={"tz": NY}, headers=circle.ana.h
    )
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "bad_image"


def test_oversized_upload_is_rejected_before_decode(circle, app):
    too_big = b"\xff\xd8\xff" + b"\x00" * (app.state.settings.max_upload_bytes + 1024)
    r = circle.ana.post_photo(image=too_big)
    assert r.status_code == 413
    assert r.json()["detail"]["code"] == "too_large"
    # and the day is untouched by a refused upload
    assert circle.ana.post_photo().status_code == 201


def test_decompression_bomb_does_not_crash_capture(circle):
    """A small file that claims enormous dimensions is refused, not fatal."""
    buf = io.BytesIO()
    Image.new("RGB", (12000, 12000), (3, 3, 3)).save(buf, format="JPEG")
    r = circle.ana.post_photo(image=buf.getvalue())
    assert r.status_code in (201, 400, 413)  # handled either way, never a 500


def test_avatar_rejects_non_image(circle):
    r = circle.ana.set_avatar(image=b"definitely not an image")
    assert r.status_code == 400


# --- spam / idempotency ------------------------------------------------------


def test_like_spam_cannot_duplicate_rows(circle, db):
    """No rate limiter yet, so the guarantee has to be structural: the like is
    a set membership, not a counter. 200 calls leave exactly one row."""
    pid = circle.ana.post_photo().json()["id"]
    for _ in range(200):
        assert circle.ben.like(pid).status_code == 201
    with db() as s:
        rows = s.scalar(
            select(func.count()).select_from(Like).where(Like.photo_id == pid)
        )
    assert rows == 1
    # and unliking repeatedly is equally harmless
    for _ in range(20):
        assert circle.ben.unlike(pid).status_code == 204
    with db() as s:
        assert s.scalar(select(func.count()).select_from(Like).where(Like.photo_id == pid)) == 0


def test_anchor_spam_is_idempotent(circle, db):
    from stanley.models import Anchor

    pid = circle.ana.post_photo().json()["id"]
    for _ in range(100):
        assert circle.ben.anchor(pid, note="mine").status_code == 201
    with db() as s:
        assert s.scalar(
            select(func.count()).select_from(Anchor).where(Anchor.photo_id == pid)
        ) == 1


def test_health_is_open_and_cheap(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_blocked_user_cannot_see_the_blockers_content_anywhere(circle):
    """The direction that matters most for safety: Ana is blocked by Ben, so
    Ben's content must be unreachable to Ana on every path she can call."""
    ben_pid = circle.ben.post_photo(caption="ben's", location="Collins").json()["id"]
    circle.ana.anchor(ben_pid, note="kept before")
    circle.ben.block(circle.ana.id)

    assert ben_pid not in [p["id"] for p in circle.ana.feed_photos()]
    for item in circle.ana.feed_items():
        if item["kind"] != "photo":
            assert ben_pid not in [p["id"] for p in item.get("photos", [])]
    assert circle.ana.like(ben_pid).status_code == 404
    assert circle.ana.anchor(ben_pid).status_code == 404
    assert circle.ana.comment(ben_pid, "nope").status_code == 404
    assert circle.ana.client.get(f"/members/{circle.ben.id}", headers=circle.ana.h).status_code == 404

    held = [m["id"] for t in circle.ana.memories().json()["threads"] for m in t["memories"]]
    assert ben_pid not in held
    assert circle.ana.rested().status_code == 200
    assert circle.ana.returned().status_code == 200
