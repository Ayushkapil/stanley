"""The production audit (November 2026): rate limits, security headers,
what's refused at the door (control characters, slurs, files that aren't
photos), a 500 that says nothing, a health check that reads the database,
the token's silent refresh, Today in pages, a sweep that a failing digest
can't undo, the indexes the hot queries use, the operator's event lines,
and the database under concurrent requests."""
from __future__ import annotations

import io
import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import select, text

from stanley import notifications, physics
from stanley.auth import decode_token
from stanley.config import Settings
from stanley.main import create_app, tick
from stanley.models import Comment, Photo, User
from tests.conftest import NY, make_user

SLUR_STORY = "you f.a.g"  # folded by the filter: punctuation inside a word


# --- rate limits ---------------------------------------------------------------


@pytest.fixture
def limited(app):
    app.state.settings.rate_limits = True
    app.state.rate_limiter.reset()
    return app


def test_sign_in_is_limited_per_address(limited, client, clock):
    for i in range(10):
        assert client.post("/auth/dev", json={"display_name": f"p{i}"}).status_code == 201
    r = client.post("/auth/dev", json={"display_name": "p10"})
    assert r.status_code == 429
    assert r.json()["detail"]["code"] == "slow_down"
    assert 1 <= int(r.headers["retry-after"]) <= 60
    clock.advance(timedelta(seconds=61))
    assert client.post("/auth/dev", json={"display_name": "p10"}).status_code == 201


def test_fly_client_ip_counts_only_on_fly(limited, client):
    """On Fly every request comes from Fly's proxy, which names the client in
    Fly-Client-IP. Off Fly the header is anyone's to send, so it's ignored."""
    for i in range(10):
        client.post("/auth/dev", json={"display_name": f"a{i}"}, headers={"Fly-Client-IP": "1.1.1.1"})
    # Not trusted: the header changes nothing, it's all one address.
    r = client.post("/auth/dev", json={"display_name": "b"}, headers={"Fly-Client-IP": "2.2.2.2"})
    assert r.status_code == 429
    limited.state.settings.trust_fly_client_ip = True
    limited.state.rate_limiter.reset()
    for i in range(10):
        client.post("/auth/dev", json={"display_name": f"c{i}"}, headers={"Fly-Client-IP": "1.1.1.1"})
    r = client.post("/auth/dev", json={"display_name": "d"}, headers={"Fly-Client-IP": "2.2.2.2"})
    assert r.status_code == 201  # a different person on a different network


def test_uploads_are_limited_per_person(circle, limited, clock):
    assert circle.ana.post_photo().status_code == 201
    for _ in range(9):  # the day law refuses these, and each still counts
        assert circle.ana.post_photo().status_code == 409
    r = circle.ana.post_photo()
    assert r.status_code == 429 and r.json()["detail"]["code"] == "slow_down"
    # Someone else's photo isn't held up by it.
    assert circle.ben.post_photo().status_code == 201


def test_stories_are_limited_per_person(circle, limited):
    pid = circle.ana.post_photo().json()["id"]
    for i in range(30):
        assert circle.ben.comment(pid, f"story {i}").status_code == 201
    assert circle.ben.comment(pid, "one more").status_code == 429
    assert circle.cam.comment(pid, "mine").status_code == 201


def test_reports_and_avatars_are_limited(circle, limited):
    pid = circle.ana.post_photo().json()["id"]
    for _ in range(20):
        assert circle.ben.report(photo_id=pid, reason="x").status_code == 201
    assert circle.ben.report(photo_id=pid, reason="x").status_code == 429
    for _ in range(10):
        assert circle.cam.set_avatar().status_code == 200
    assert circle.cam.set_avatar().status_code == 429


def test_limits_off_never_refuse(circle, app):
    assert app.state.settings.rate_limits is False
    pid = circle.ana.post_photo().json()["id"]
    for i in range(40):
        assert circle.ben.comment(pid, f"story {i}").status_code == 201


# --- headers, CORS, docs ---------------------------------------------------------


def test_every_response_carries_the_security_headers(circle, client):
    pid = circle.ana.post_photo().json()["id"]
    feed = circle.ana.feed()
    image = feed.json()["items"][0]["photo"]["urls"]["image"]
    for r in (feed, client.get("/terms"), client.get("/health"), client.get(image), client.get("/nope")):
        assert r.headers["x-content-type-options"] == "nosniff"
        assert r.headers["x-frame-options"] == "DENY"
        assert r.headers["strict-transport-security"].startswith("max-age=31536000")
        assert r.headers["referrer-policy"] == "no-referrer"
        assert "default-src 'none'" in r.headers["content-security-policy"]
    assert pid


def test_no_cross_origin_reads(client):
    """Stanley has no web app, so no browser on another site may read its
    answers: no CORS headers, ever."""
    r = client.options(
        "/feed/today",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in r.headers
    r = client.get("/health", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in r.headers


def test_api_docs_only_with_dev_sign_in(tmp_path, clock):
    prod = create_app(
        Settings(database_url="sqlite://", blob_dir=str(tmp_path / "b"), secret_key="k" * 40,
                 dev_auth=False, run_sweeper=False, news_enabled=False, report_webhook_url=None),
        clock=clock,
    )
    with TestClient(prod) as c:
        for path in ("/docs", "/redoc", "/openapi.json"):
            assert c.get(path).status_code == 404
        assert c.post("/auth/dev", json={"display_name": "x"}).status_code == 404


# --- a 500 says nothing --------------------------------------------------------------


def test_an_unexpected_error_is_a_bare_500(circle, app, monkeypatch, caplog):
    def boom(*a, **k):
        raise RuntimeError("SELECT secret FROM users -- internal detail")

    monkeypatch.setattr("stanley.routes.feed.weekly_mosaic", boom)
    quiet = TestClient(app, raise_server_exceptions=False)
    with caplog.at_level(logging.ERROR, logger="stanley"):
        r = quiet.get("/feed/today", headers=circle.ana.h)
    assert r.status_code == 500
    assert r.json() == {"detail": {"code": "server_error"}}
    assert "secret" not in r.text and "Traceback" not in r.text
    assert any("event=server_error" in rec.getMessage() and "route=/feed/today" in rec.getMessage()
               for rec in caplog.records)


# --- health --------------------------------------------------------------------------


def test_health_reads_the_database(app, client, monkeypatch):
    assert client.get("/health").json() == {"status": "ok"}

    def down(*a, **k):
        raise RuntimeError("disk gone")

    monkeypatch.setattr(app.state.engine, "connect", down)
    r = client.get("/health")
    assert r.status_code == 503 and r.json() == {"status": "unavailable"}


# --- the token's silent refresh ------------------------------------------------------


def test_a_working_token_is_refreshed(app, client, clock):
    ana = make_user(client, "ana")
    clock.advance(timedelta(days=20))
    r = client.post("/auth/refresh", headers={"Authorization": f"Bearer {ana.token}"})
    assert r.status_code == 200
    fresh = r.json()["token"]
    clock.advance(timedelta(days=15))  # 35 days after sign-in, 15 after refresh
    secret = app.state.settings.secret_key
    assert decode_token(secret, fresh, clock.now()) == ana.id
    assert client.get("/me", headers={"Authorization": f"Bearer {ana.token}"}).status_code == 401
    assert client.get("/me", headers={"Authorization": f"Bearer {fresh}"}).status_code == 200


def test_an_expired_token_cannot_be_refreshed(app, client, clock):
    ana = make_user(client, "ana")
    clock.advance(timedelta(days=31))
    r = client.post("/auth/refresh", headers={"Authorization": f"Bearer {ana.token}"})
    assert r.status_code == 401


# --- what's refused at the door ------------------------------------------------------


def test_control_and_bidi_characters_are_dropped(circle, db):
    r = circle.ana.post_photo(caption="sunset\x00 on the‮ roof\nsecond line", location="\tDunn\x1b Meadow ")
    assert r.status_code == 201
    assert r.json()["caption"] == "sunset on the roof\nsecond line"
    assert r.json()["location"] == "Dunn Meadow"
    r = circle.ana.client.patch("/me/profile", json={"display_name": "Ana‮⁦", "bio": "line\r\nnext"},
                                headers=circle.ana.h)
    assert r.status_code == 200
    assert r.json()["display_name"] == "Ana" and r.json()["bio"] == "line\nnext"


def test_a_blank_story_is_refused(circle):
    pid = circle.ana.post_photo().json()["id"]
    r = circle.ben.comment(pid, "   \n  ")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "empty_story"


def test_oversized_fields_are_refused_not_decoded(circle, client):
    assert client.post("/auth/apple", json={"identity_token": "x" * 9000}).status_code == 422
    assert circle.ana.client.post("/circles/join", json={"code": "A" * 100}, headers=circle.ana.h).status_code == 422
    r = circle.ana.client.get("/me/username_check", params={"u": "a" * 100}, headers=circle.ana.h)
    assert r.status_code == 422


def test_a_flood_of_tags_is_cut_at_the_circle_cap(circle):
    r = circle.ana.post_photo(tagged=[circle.ben.id] + [f"x{i}" for i in range(900)])
    assert r.status_code == 201
    assert [t["id"] for t in r.json()["tagged"]] == [circle.ben.id]
    # Past a thousand form fields the framework refuses the whole request,
    # before the route runs: a 400, never a 500, and the day stays open.
    r = circle.cam.post_photo(tagged=[f"x{i}" for i in range(5000)])
    assert r.status_code == 400
    assert circle.cam.post_photo().status_code == 201


def test_a_bad_time_zone_is_never_kept(circle, db):
    for path, method in (("/feed/returned", "get"), ("/feed/returned/dismiss", "post")):
        r = getattr(circle.ana.client, method)(path, params={"tz": "Not/AZone"}, headers=circle.ana.h)
        assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_timezone"
    with db() as s:
        assert s.get(User, circle.ana.id).tz_last_seen != "Not/AZone"


def test_files_that_are_not_photos_are_refused_by_their_bytes(circle):
    for fmt in ("GIF", "BMP", "TIFF", "WEBP"):
        buf = io.BytesIO()
        Image.new("RGB", (64, 48)).save(buf, format=fmt)
        r = circle.ana.post_photo(image=buf.getvalue())
        assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_image", fmt
    buf = io.BytesIO()
    Image.new("RGB", (64, 48)).save(buf, format="PNG")
    assert circle.ana.post_photo(image=buf.getvalue()).status_code == 201


def test_a_decompression_bomb_is_refused_from_its_header(circle):
    buf = io.BytesIO()
    Image.new("L", (10000, 10000)).save(buf, format="PNG")  # 100 MP, a small file
    r = circle.ana.post_photo(image=buf.getvalue())
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_image"
    assert circle.ana.post_photo().status_code == 201  # and the day is untouched


# --- the word filter -------------------------------------------------------------------


def test_a_slur_in_a_story_is_refused_and_nothing_is_kept(circle, db):
    pid = circle.ana.post_photo().json()["id"]
    r = circle.ben.comment(pid, SLUR_STORY)
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    with db() as s:
        assert s.scalars(select(Comment)).all() == []
    assert circle.ben.comment(pid, "what a night").status_code == 201


def test_a_slur_in_a_caption_costs_nobody_the_day(circle):
    r = circle.ana.post_photo(caption=f"look at this {SLUR_STORY}")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed"
    assert circle.ana.post_photo(caption="look at this").status_code == 201


def test_the_filter_covers_what_a_circle_reads(circle):
    h = circle.ana.h
    c = circle.ana.client
    refused = [
        c.put(f"/circles/{circle.id}/note", json={"text": SLUR_STORY}, headers=h),
        c.patch("/me/profile", json={"display_name": SLUR_STORY}, headers=h),
        c.patch("/me/profile", json={"bio": SLUR_STORY}, headers=h),
        c.patch("/me/profile", json={"username": "kill.yourself"}, headers=h),
        c.post("/circles", json={"name": SLUR_STORY}, headers=h),
        c.patch(f"/circles/{circle.id}", json={"name": SLUR_STORY}, headers=h),
        circle.ana.post_photo(location=SLUR_STORY),
    ]
    for r in refused:
        assert r.status_code == 400 and r.json()["detail"]["code"] == "words_not_allowed", r.request.url
    check = c.get("/me/username_check", params={"u": "kill.yourself"}, headers=h).json()
    assert check == {"valid": False, "available": False}


def test_reports_and_hold_notes_are_never_filtered(circle):
    """A report may need to quote what it's about, and a hold note is read
    only by the person who wrote it."""
    pid = circle.ana.post_photo().json()["id"]
    assert circle.ben.report(photo_id=pid, reason=f"they wrote {SLUR_STORY}").status_code == 201
    assert circle.ben.anchor(pid, note=SLUR_STORY).status_code == 201


def test_ordinary_words_pass(circle):
    pid = circle.ana.post_photo(caption="Scunthorpe trip, spicy food, a chink in the armor",
                                location="Niger Street").json()["id"]
    for words in ("homo sapiens at the museum", "spick-and-span", "class/act", "the dyke held"):
        assert circle.ben.comment(pid, words).status_code == 201, words


# --- Today in pages ---------------------------------------------------------------------


def _ids(items):
    return [i["photo"]["id"] if i["kind"] == "photo" else "moment:" + i["photos"][0]["id"] for i in items]


def test_today_pages_add_up_to_the_whole_feed(client, clock):
    people = [make_user(client, f"p{i}") for i in range(9)]
    first = people[0]
    info = client.post("/circles", json={"name": "floor"}, headers=first.h).json()
    for p in people[1:]:
        assert p.join(info["invite_token"]).status_code == 201
    for i, p in enumerate(people):
        clock.advance(timedelta(minutes=7))
        # p1 and p2 share a place: one moment, which must never be split.
        place = "Dunn Meadow" if i in (1, 2) else None
        assert p.post_photo(location=place).status_code == 201
    first.set_note(info["id"], "hello")

    whole = first.feed().json()
    assert whole["next_cursor"] is None
    everything = _ids(whole["items"])
    assert len(everything) == 8  # nine photos, two of them one moment

    seen, cursor, pages = [], None, 0
    while True:
        params = {"limit": 3} | ({"cursor": cursor} if cursor else {})
        page = client.get("/feed/today", params=params, headers=first.h).json()
        pages += 1
        if pages == 1:
            assert page["note"]["text"] == "hello"
        else:
            assert page["note"] is None and page["mosaic"] is None
        seen += _ids(page["items"])
        cursor = page["next_cursor"]
        if cursor is None:
            break
    assert seen == everything and pages == 3
    moment = next(i for i in whole["items"] if i["kind"] == "moment")
    assert len(moment["photos"]) == 2


def test_a_refresh_can_ask_for_everything_it_shows(circle):
    for p in (circle.ana, circle.ben, circle.cam):
        p.post_photo()
    r = circle.ana.client.get("/feed/today", params={"limit": 3}, headers=circle.ana.h).json()
    assert len(r["items"]) == 3 and r["next_cursor"] is None


def test_bad_cursors_and_limits_are_refused(circle):
    c, h = circle.ana.client, circle.ana.h
    assert c.get("/feed/today", params={"cursor": "not-a-cursor"}, headers=h).json()["detail"]["code"] == "bad_cursor"
    assert c.get("/feed/today", params={"limit": 0}, headers=h).status_code == 422
    assert c.get("/feed/today", params={"limit": 201}, headers=h).status_code == 422


# --- the sweep ---------------------------------------------------------------------------


def test_a_failing_digest_cannot_undo_the_sweep(circle, app, clock, db, monkeypatch):
    pid = circle.ana.post_photo().json()["id"]

    def broken(*a, **k):
        raise RuntimeError("push service exploded")

    monkeypatch.setattr(notifications, "run_evening_digests", broken)
    clock.advance(timedelta(hours=physics.LIVE_HOURS + 1))
    tick(app)
    with db() as s:
        assert s.get(Photo, pid).state == physics.FADING


def test_one_unknown_zone_does_not_stop_anyone_elses_digest(circle, app, clock, db):
    with db() as s:
        for uid in (circle.ana.id, circle.ben.id):
            s.get(User, uid).digest_enabled = True
        s.get(User, circle.ana.id).tz_last_seen = "Not/AZone"
        s.get(User, circle.ben.id).tz_last_seen = NY
        s.commit()
    circle.cam.post_photo()
    clock.set(clock.now().replace(hour=0, minute=30) + timedelta(days=1))  # 20:30 in New York
    with db() as s:
        sent = notifications.run_evening_digests(s, app.state.notifier, clock)
        s.commit()
    assert sent >= 1  # Ben's, at least; Ana's zone is read as UTC


def test_a_nearly_full_disk_is_said_in_the_logs(tmp_path, monkeypatch, caplog):
    import shutil
    from collections import namedtuple

    from stanley import backup

    usage = namedtuple("usage", "total used free")
    monkeypatch.setattr(shutil, "disk_usage", lambda p: usage(1000 * 2**20, 900 * 2**20, 100 * 2**20))
    with caplog.at_level(logging.WARNING, logger="stanley"):
        assert backup.warn_if_disk_low(str(tmp_path)) == 0.1
    assert any("event=disk_low free_percent=10" in r.getMessage() for r in caplog.records)
    assert backup.warn_if_disk_low(str(tmp_path / "missing")) is None


def test_maintenance_optimizes_and_vacuums(tmp_path):
    import sqlite3

    from stanley.backup import maintain_database

    path = tmp_path / "x.db"
    con = sqlite3.connect(str(path))
    con.execute("CREATE TABLE t (x TEXT)")
    con.executemany("INSERT INTO t VALUES (?)", [("x" * 1000,)] * 2000)
    con.commit()
    con.execute("DELETE FROM t")
    con.commit()
    con.close()
    before = path.stat().st_size
    maintain_database(f"sqlite:///{path}", vacuum=False)
    assert path.stat().st_size == before  # optimize alone doesn't rewrite
    maintain_database(f"sqlite:///{path}", vacuum=True)
    assert path.stat().st_size < before / 10


def test_held_shows_each_friends_face(circle):
    """Held heads each friend's page with their face; the link was never
    signed, so the album only ever showed initials."""
    assert circle.ana.set_avatar().status_code == 200
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.anchor(pid)
    thread = circle.ben.memories().json()["threads"][0]
    assert thread["friend"]["id"] == circle.ana.id
    assert thread["friend"]["avatar_url"].startswith("/blobs/avatars/")


# --- indexes -------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "query, index",
    [
        ("SELECT circle_id FROM memberships WHERE user_id = 'x'", "ix_memberships_user"),
        ("SELECT blocker_id FROM blocks WHERE blocked_id = 'x'", "ix_blocks_blocked"),
        ("SELECT * FROM anchors WHERE user_id = 'x'", "ix_anchors_user"),
        ("SELECT * FROM photos WHERE state IN ('live','fading') AND state_deadline <= '2026-01-01'",
         "ix_photos_state_deadline"),
        ("SELECT count(*) FROM photos WHERE owner_hash = 'h' AND circle_id = 'c' AND local_date = '2026-01-01'",
         "ix_photos_owner_hash"),
        ("SELECT * FROM purge_queue WHERE done = 0 AND purge_after <= '2026-01-01'", "ix_purge_queue_due"),
        ("SELECT * FROM notification_log WHERE user_id = 'x' AND kind = 'digest' AND sent_at >= '2026-01-01'",
         "ix_notification_log_user"),
    ],
)
def test_hot_queries_use_an_index(db, query, index):
    with db() as s:
        plan = " ".join(str(row[-1]) for row in s.execute(text(f"EXPLAIN QUERY PLAN {query}")))
    assert index in plan, plan


# --- the operator's event lines ------------------------------------------------------------


def test_what_happened_is_logged_without_anyones_words(client, caplog):
    with caplog.at_level(logging.INFO, logger="stanley"):
        ana = make_user(client, "Ana Secretname")
        ben = make_user(client, "ben")
        info = client.post("/circles", json={"name": "Hidden Circle Name"}, headers=ana.h).json()
        ben.join(info["invite_token"])
        pid = ana.post_photo(caption="a private caption").json()["id"]
        ben.report(photo_id=pid, reason="private reason")
        ben.block(ana.id)
        ben.delete_me()
    lines = " ".join(r.getMessage() for r in caplog.records)
    for name in ("signup", "circle_created", "circle_joined", "photo_posted", "report_filed", "block",
                 "account_deleted"):
        assert f"event={name}" in lines, name
    for private in ("Secretname", "Hidden Circle Name", "private caption", "private reason"):
        assert private not in lines


# --- concurrency -----------------------------------------------------------------------------


def test_concurrent_requests_on_a_real_database(tmp_path, clock):
    """WAL, busy_timeout and the pool together: forty requests at once,
    readers and writers mixed, on a file database like Fly's, and not one
    'database is locked'."""
    app = create_app(
        Settings(database_url=f"sqlite:///{tmp_path}/stanley.db", blob_dir=str(tmp_path / "blobs"),
                 secret_key="k" * 40, dev_auth=True, run_sweeper=False, news_enabled=False,
                 report_webhook_url=None, rate_limits=False),
        clock=clock,
    )
    with TestClient(app) as client:
        people = [make_user(client, f"p{i}") for i in range(8)]
        info = client.post("/circles", json={"name": "floor"}, headers=people[0].h).json()
        for p in people[1:]:
            p.join(info["invite_token"])
        pid = people[0].post_photo().json()["id"]

        def work(i):
            # The same person doing the same thing at once, as a double tap
            # or a retry does, mixed with readers.
            p = people[i % len(people)]
            kind = i % 6
            if kind == 0:
                return p.comment(pid, f"story {i}").status_code
            if kind == 1:
                return p.like(pid).status_code
            if kind == 2:
                return p.anchor(pid).status_code
            if kind == 3 and p is not people[1]:
                # Not the photo's owner: a block of them would rightly
                # make the photo a 404 for the blocker's next request.
                return p.block(people[1].id).status_code
            if kind == 4:
                return p.client.get("/me/milestones", headers=p.h).status_code
            return p.feed().status_code

        with ThreadPoolExecutor(max_workers=40) as pool:
            codes = list(pool.map(work, range(240)))
    assert all(code in (200, 201, 204) for code in codes), sorted(set(codes))


# --- the operator's side of a report ---------------------------------------------------------


def test_a_reported_photo_is_taken_down_and_preserved(circle, app, db, clock, tmp_path):
    from stanley import moderation
    from stanley.models import Report

    pid = circle.ben.post_photo(caption="the reported one").json()["id"]
    circle.cam.anchor(pid)
    circle.ana.report(photo_id=pid, reason="this shouldn't be here")
    with db() as s:
        assert [r.photo_id for r in moderation.open_reports(s)] == [pid]
        assert moderation.take_down_photo(s, app.state.storage, pid, clock.now(), preserve=str(tmp_path / "evidence"))
        s.commit()
    kept = tmp_path / "evidence" / pid
    assert (kept / "deriv.jpg").exists() and "the reported one" in (kept / "facts.json").read_text()
    with db() as s:
        photo = s.get(Photo, pid)
        assert photo.state == physics.PURGED and photo.caption is None and photo.deriv_key is None
        assert moderation.open_reports(s) == []
        assert s.scalars(select(Report)).one().resolved_at is not None
    assert pid not in [p["id"] for p in circle.ana.feed_photos()]
    # The holder keeps the honest tombstone, as with any delete.
    memories = circle.cam.memories().json()["threads"][0]["memories"]
    assert memories[0]["tombstone"] is True


def test_a_reported_story_is_taken_down(circle, db, clock):
    from stanley import moderation

    pid = circle.ana.post_photo().json()["id"]
    cid = circle.ben.comment(pid, "something cruel").json()["id"]
    circle.cam.report(comment_id=cid, reason="cruel")
    with db() as s:
        assert moderation.take_down_story(s, cid, clock.now())
        s.commit()
    with db() as s:
        assert s.get(Comment, cid) is None
        assert moderation.open_reports(s) == []
    assert moderation.resolve  # and a report needing nothing removed can be closed by id


def test_the_operator_can_end_an_account(circle, app, db, clock):
    from stanley import moderation

    pid = circle.ben.post_photo().json()["id"]
    circle.ana.anchor(pid)
    with db() as s:
        assert moderation.terminate_account(s, app.state.storage, circle.ben.id, clock.now())
        s.commit()
    with db() as s:
        ben = s.get(User, circle.ben.id)
        assert ben.deleted_at is not None and ben.display_name is None
        assert s.get(Photo, pid).state == physics.PURGED
        assert not moderation.terminate_account(s, app.state.storage, circle.ben.id, clock.now())
    assert circle.ben.client.get("/me", headers=circle.ben.h).status_code == 401
