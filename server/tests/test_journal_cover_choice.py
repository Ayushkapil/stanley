"""Build 76: the opened cover, where a journal is made one's own.

Your own journal can take a photo from your phone's library as its cover;
once chosen, nothing automatic replaces it until you put the automatic
one back. It's yours alone, as the journal's name is. Shared journals
have no chosen photo (a product decision, 2026-11-16): their cover is the
circle's newest photo, and their name is the circle's, renamed by its
organizer alone. A name is trimmed, never blank and short enough for the
cover. "Last written" is the newest day you can read, a date and never a
number."""
from __future__ import annotations

from datetime import timedelta
from io import BytesIO

from PIL import Image

from stanley import journal
from stanley.models import User

from .conftest import jpeg_bytes, make_user


def mine(api):
    return api.client.get("/me/journal", headers=api.h).json()


def choose(api, image=None):
    return api.client.post(
        "/me/journal/cover",
        files={"file": ("cover.jpg", image or jpeg_bytes(), "image/jpeg")},
        headers=api.h,
    )


def circles(api):
    return {c["name"]: c for c in api.client.get("/circles", headers=api.h).json()["circles"]}


def key_of(db, api):
    with db() as session:
        return session.get(User, api.id).journal_cover_key


def test_a_chosen_photo_is_the_cover_and_says_so(circle, client):
    assert mine(circle.ana)["cover_chosen"] is False
    r = choose(circle.ana)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["cover_chosen"] is True and body["cover_photo_id"] is None
    assert "sig=" in body["cover_url"]
    assert client.get(body["cover_url"]).status_code == 200
    j = mine(circle.ana)
    assert j["cover_chosen"] is True and "sig=" in j["cover_url"]


def test_the_automatic_cover_never_overrides_a_chosen_one(circle, clock):
    choose(circle.ana)
    pid = circle.cam.post_photo().json()["id"]
    circle.ana.anchor(pid)
    clock.advance(timedelta(minutes=5))
    j = mine(circle.ana)
    assert j["cover_chosen"] is True and j["cover_photo_id"] is None


def test_putting_the_automatic_cover_back(circle, app, db):
    pid = circle.cam.post_photo().json()["id"]
    circle.ana.anchor(pid)
    choose(circle.ana)
    key = key_of(db, circle.ana)
    assert app.state.storage.exists(key)
    r = circle.ana.client.patch("/me/journal", json={"cover": None}, headers=circle.ana.h)
    assert r.status_code == 200
    assert r.json()["cover_chosen"] is False and r.json()["cover_photo_id"] == pid
    assert key_of(db, circle.ana) is None
    assert not app.state.storage.exists(key)


def test_choosing_again_replaces_the_old_picture(circle, app, db):
    choose(circle.ana)
    first = key_of(db, circle.ana)
    choose(circle.ana)
    second = key_of(db, circle.ana)
    assert first != second
    assert not app.state.storage.exists(first) and app.state.storage.exists(second)


def test_nothing_of_the_photo_but_its_pixels(circle, app, db):
    """GPS removal is a hard rule; a cover keeps no EXIF at all."""
    src = Image.open(BytesIO(jpeg_bytes(with_exif=True)))
    assert 271 in src.getexif()
    choose(circle.ana, jpeg_bytes(with_exif=True))
    stored = app.state.storage.get(key_of(db, circle.ana))
    assert not set(Image.open(BytesIO(stored)).getexif().keys())


def test_not_a_picture_is_refused(circle):
    r = choose(circle.ana, b"not a picture at all")
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_image"


def test_a_chosen_cover_is_yours_alone(circle, clock):
    pid = circle.cam.post_photo().json()["id"]
    choose(circle.ana)
    # Nobody else's book, and no circle's, is touched by it.
    assert mine(circle.ben)["cover_chosen"] is False
    for api in (circle.ana, circle.ben):
        assert circles(api)["floor 3"]["cover_photo_id"] == pid
    assert "journal_cover" not in str(circle.ben.client.get("/circles", headers=circle.ben.h).json())


def test_renaming_trims_refuses_blank_and_fits_the_cover(circle):
    patch = lambda body: circle.ana.client.patch("/me/journal", json=body, headers=circle.ana.h)
    r = patch({"title": "  Field Notes  "})
    assert r.status_code == 200 and r.json()["title"] == "Field Notes"
    for blank in ("", "   ", "\n"):
        r = patch({"title": blank})
        assert r.status_code == 400 and r.json()["detail"]["code"] == "empty_title"
    assert mine(circle.ana)["title"] == "Field Notes"
    r = patch({"title": "x" * (journal.TITLE_MAX + 1)})
    assert r.status_code == 400 and r.json()["detail"]["code"] == "title_too_long"
    assert patch({"title": "x" * journal.TITLE_MAX}).status_code == 200
    # Sending nothing changes nothing.
    assert patch({}).json()["title"] == "x" * journal.TITLE_MAX


def test_only_the_organizer_renames_a_circle_journal(circle):
    """A shared journal takes its circle's name; renaming it renames the
    circle, which only the organizer can do."""
    cid = circles(circle.ana)["floor 3"]["id"]
    organizer = next(api for api in (circle.ana, circle.ben, circle.cam) if circles(api)["floor 3"]["is_creator"])
    other = next(api for api in (circle.ana, circle.ben, circle.cam) if api is not organizer)
    r = other.client.patch(f"/circles/{cid}", json={"name": "Hijacked"}, headers=other.h)
    assert r.status_code == 403
    r = organizer.client.patch(f"/circles/{cid}", json={"name": "Third Floor"}, headers=organizer.h)
    assert r.status_code == 200
    assert "Third Floor" in circles(other)


def test_last_written_is_the_newest_day_you_can_read(circle, clock):
    assert circles(circle.ben)["floor 3"]["last_day"] is None
    r = circle.ana.client.put(
        "/me/journal/today", json={"body": "A day.", "ink": "black", "tz": "America/New_York", "shared": True},
        headers=circle.ana.h,
    )
    assert r.status_code == 200, r.text
    day = r.json()["day"]
    for api in (circle.ana, circle.ben):
        assert circles(api)["floor 3"]["last_day"] == day
    circle.ben.block(circle.ana.id)
    assert circles(circle.ben)["floor 3"]["last_day"] is None


def test_deleting_the_account_deletes_the_cover(circle, app, db):
    choose(circle.ana)
    key = key_of(db, circle.ana)
    r = circle.ana.client.delete("/me", headers=circle.ana.h)
    assert r.status_code in (200, 204), r.text
    assert not app.state.storage.exists(key)
    assert key_of(db, circle.ana) is None


def test_the_export_carries_the_chosen_cover(circle):
    import json
    import zipfile

    choose(circle.ana)
    r = circle.ana.client.get("/me/export", headers=circle.ana.h)
    zf = zipfile.ZipFile(BytesIO(r.content))
    assert "journal-cover.jpg" in zf.namelist()
    assert json.loads(zf.read("memories.json"))["journal_cover"] == "journal-cover.jpg"
