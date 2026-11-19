"""Build 81: the unit is the day, not the photo. A person's day in a circle is
one entry of up to three photos, added (or one taken out) only while that day
is still theirs; keeps, hearts and decay belong to the entry."""
from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from stanley.models import Photo, PhotoImage

from .conftest import NY, START, jpeg_bytes

# The fields every build from 17 on reads in a photo. Swift's Codable ignores
# keys it doesn't know, so an older build is fine as long as these are here,
# with the shapes it expects, and `urls` is one photo.
OLD_FIELDS = {
    "id", "owner", "taken_at", "caption", "location", "filter", "state",
    "decay_progress", "state_deadline", "urls", "comments", "anchored_by_me",
    "my_anchor_note", "liked_by_me", "tagged", "retake_on_delete", "has_journal",
}


def add(api, pid, tz=NY, image=None):
    files = {"file": ("photo.jpg", image or jpeg_bytes(), "image/jpeg")}
    return api.client.post(f"/photos/{pid}/images", files=files, data={"tz": tz}, headers=api.h)


def remove(api, pid, image_id, tz=NY):
    return api.client.delete(f"/photos/{pid}/images/{image_id}", params={"tz": tz}, headers=api.h)


def posted(api):
    r = api.post_photo()
    assert r.status_code == 201, r.text
    return r.json()


def test_a_second_entry_on_the_same_day_is_refused(circle):
    posted(circle.ana)
    assert circle.ana.post_photo().status_code == 409


def test_a_third_photo_is_taken_and_a_fourth_refused(circle):
    pid = posted(circle.ana)["id"]
    r2 = add(circle.ana, pid)
    assert r2.status_code == 201, r2.text
    r3 = add(circle.ana, pid)
    assert r3.status_code == 201, r3.text
    images = r3.json()["images"]
    assert len(images) == 3
    assert images[0]["id"] == pid
    r4 = add(circle.ana, pid)
    assert r4.status_code == 409
    assert r4.json()["detail"]["code"] == "entry_full"


def test_every_photo_in_the_entry_is_served(circle):
    pid = posted(circle.ana)["id"]
    add(circle.ana, pid)
    feed = circle.ben.feed_photos()
    assert len(feed) == 1  # one card for the day
    for image in feed[0]["images"]:
        for link in (image["image"], image["thumb"]):
            got = circle.ben.client.get(link)
            assert got.status_code == 200
            assert got.content[:2] == b"\xff\xd8"


def test_adding_and_removing_work_within_the_day(circle):
    pid = posted(circle.ana)["id"]
    extra = add(circle.ana, pid).json()["images"][1]["id"]
    r = remove(circle.ana, pid, extra)
    assert r.status_code == 200, r.text
    assert [i["id"] for i in r.json()["images"]] == [pid]
    # Taking one out leaves room for another.
    assert add(circle.ana, pid).status_code == 201


def test_both_are_refused_the_next_day(circle, clock):
    pid = posted(circle.ana)["id"]
    extra = add(circle.ana, pid).json()["images"][1]["id"]
    # 11:00 in New York on posting day; 14 hours on is 01:00 the next day.
    clock.set(START + timedelta(hours=14))
    r_add = add(circle.ana, pid)
    assert r_add.status_code == 409
    assert r_add.json()["detail"]["code"] == "day_over"
    r_remove = remove(circle.ana, pid, extra)
    assert r_remove.status_code == 409
    assert r_remove.json()["detail"]["code"] == "day_over"
    mine = next(p for p in circle.ana.feed_photos() if p["id"] == pid)
    assert mine["editable_today"] is False


def test_the_only_photo_cannot_be_taken_out(circle):
    pid = posted(circle.ana)["id"]
    r = remove(circle.ana, pid, pid)
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "last_photo"


def test_taking_out_the_first_photo_moves_the_next_up(circle, app, db):
    first = posted(circle.ana)
    pid = first["id"]
    with db() as s:
        old_deriv = s.get(Photo, pid).deriv_key
    second = add(circle.ana, pid).json()["images"][1]["id"]
    third = add(circle.ana, pid).json()["images"][2]["id"]
    r = remove(circle.ana, pid, pid)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["id"] == pid  # the entry is the same entry
    assert len(body["images"]) == 2
    assert body["images"][1]["id"] == third
    assert not app.state.storage.exists(old_deriv)
    with db() as s:
        photo = s.get(Photo, pid)
        assert photo.deriv_key.startswith(f"{pid}/{second}/")
        rows = s.scalars(select(PhotoImage).where(PhotoImage.photo_id == pid)).all()
        assert [(r.id, r.position) for r in rows] == [(third, 1)]


def test_nobody_else_can_add_or_remove(circle):
    pid = posted(circle.ana)["id"]
    extra = add(circle.ana, pid).json()["images"][1]["id"]
    assert add(circle.ben, pid).status_code == 404
    assert remove(circle.ben, pid, extra).status_code == 404


def test_editable_today_is_the_owners_alone(circle):
    pid = posted(circle.ana)["id"]
    mine = next(p for p in circle.ana.feed_photos() if p["id"] == pid)
    assert mine["editable_today"] is True
    theirs = next(p for p in circle.ben.feed_photos() if p["id"] == pid)
    assert theirs["editable_today"] is None


def test_an_old_shaped_response_is_still_one_photo(circle):
    """A build from before entries reads `urls`: one photo, the entry's
    first, with every field it has always read."""
    pid = posted(circle.ana)["id"]
    add(circle.ana, pid)
    add(circle.ana, pid)
    for photo in (circle.ben.feed_photos()[0], circle.ana.feed_photos()[0]):
        assert OLD_FIELDS <= set(photo)
        assert photo["id"] == pid
        assert set(photo["urls"]) == {"image", "thumb"}
        assert isinstance(photo["urls"]["image"], str)
        assert photo["urls"]["image"] == photo["images"][0]["image"]
        got = circle.ben.client.get(photo["urls"]["image"])
        assert got.status_code == 200


def test_no_count_rides_on_an_entry(circle):
    pid = posted(circle.ana)["id"]
    add(circle.ana, pid)
    photo = circle.ben.feed_photos()[0]
    assert not any("count" in key or key.startswith("n_") for key in photo)
    for image in photo["images"]:
        assert set(image) == {"id", "image", "thumb"}


def test_hearts_and_keeps_attach_to_the_entry_not_a_photo(circle):
    pid = posted(circle.ana)["id"]
    extra = add(circle.ana, pid).json()["images"][1]["id"]
    # A further photo is not something to heart or keep on its own.
    assert circle.ben.like(extra).status_code == 404
    assert circle.ben.anchor(extra).status_code == 404
    assert circle.ben.like(pid).status_code in (200, 201, 204)
    assert circle.ben.anchor(pid).status_code in (200, 201)
    photo = circle.ben.feed_photos()[0]
    assert photo["liked_by_me"] is True
    assert photo["anchored_by_me"] is True
    # Taking a photo out leaves the entry's heart and keep where they are.
    remove(circle.ana, pid, extra)
    photo = circle.ben.feed_photos()[0]
    assert photo["liked_by_me"] is True
    assert photo["anchored_by_me"] is True


def test_a_kept_entry_keeps_every_photo_through_purge(circle, clock, sweep, app):
    pid = posted(circle.ana)["id"]
    add(circle.ana, pid)
    circle.ben.anchor(pid)
    clock.set(START + timedelta(days=20))
    sweep()
    held = circle.ben.memories().json()
    memory = next(m for t in held["threads"] for m in t["memories"] if m.get("id") == pid)
    assert memory["tombstone"] is False
    assert len(memory["images"]) == 2
    for image in memory["images"]:
        assert circle.ben.client.get(image["image"]).status_code == 200


def test_an_unkept_entry_takes_every_photo_with_it(circle, clock, sweep, app, db):
    pid = posted(circle.ana)["id"]
    add(circle.ana, pid)
    with db() as s:
        keys = [k for r in s.scalars(select(PhotoImage)).all() for k in (r.deriv_key, r.thumb_key)]
    assert keys and all(app.state.storage.exists(k) for k in keys)
    clock.set(START + timedelta(days=20))
    sweep()
    sweep()
    assert not any(app.state.storage.exists(k) for k in keys)
    with db() as s:
        assert s.scalars(select(PhotoImage)).all() == []


def test_deleting_the_entry_takes_every_photo_and_keeps_the_redo(circle, app, db):
    pid = posted(circle.ana)["id"]
    add(circle.ana, pid)
    with db() as s:
        keys = [k for r in s.scalars(select(PhotoImage)).all() for k in (r.deriv_key, r.thumb_key)]
    assert circle.ana.delete_photo(pid).status_code == 204
    assert not any(app.state.storage.exists(k) for k in keys)
    # Today's one redo, as before: the day can be taken again once.
    assert circle.ana.post_photo().status_code == 201


def test_removing_a_photo_does_not_spend_the_redo(circle):
    pid = posted(circle.ana)["id"]
    extra = add(circle.ana, pid).json()["images"][1]["id"]
    remove(circle.ana, pid, extra)
    assert circle.ana.delete_photo(pid).status_code == 204
    assert circle.ana.post_photo().status_code == 201


def test_reconcile_names_every_photo_of_an_entry(circle, app, db, tmp_path):
    """The R2 reconcile deletes what the database doesn't name; it must name
    an entry's further photos, or it would delete them."""
    import sqlite3

    from scripts import move_photos_to_r2 as move

    pid = posted(circle.ana)["id"]
    add(circle.ana, pid)
    with db() as s:
        extra = s.scalars(select(PhotoImage)).one()
        wanted = {extra.deriv_key, extra.thumb_key, extra.blob_key}
    path = tmp_path / "copy.db"
    with db() as s:
        raw = s.connection().connection.driver_connection
        out = sqlite3.connect(path)
        raw.backup(out)
        out.close()
    assert wanted <= move.referenced_keys(path)


def test_an_add_that_loses_a_race_writes_nothing(circle, app, db, monkeypatch):
    """Two phones adding at once to an entry with room for one: the one that
    commits second is refused, with no row and no file left behind."""
    from stanley.routes import photos as photo_routes

    pid = posted(circle.ana)["id"]
    add(circle.ana, pid)
    real = photo_routes.prepare_upload

    def meanwhile(data):
        # The other phone's add lands while this one's image is being read.
        with db() as s:
            s.add(PhotoImage(photo_id=pid, position=2, blob_key=None,
                             deriv_key=f"{pid}/other/deriv.jpg", thumb_key=f"{pid}/other/thumb.jpg",
                             created_at=START))
            s.commit()
        return real(data)

    monkeypatch.setattr(photo_routes, "prepare_upload", meanwhile)
    before = set(p.relative_to(app.state.storage.root).as_posix() for p in app.state.storage.root.rglob("*") if p.is_file()) if hasattr(app.state.storage, "root") else None
    r = add(circle.ana, pid)
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "entry_full"
    with db() as s:
        assert len(s.scalars(select(PhotoImage).where(PhotoImage.photo_id == pid)).all()) == 2
    if before is not None:
        after = set(p.relative_to(app.state.storage.root).as_posix() for p in app.state.storage.root.rglob("*") if p.is_file())
        assert after == before


def test_an_add_to_an_entry_deleted_meanwhile_writes_nothing(circle, app, db, monkeypatch):
    from stanley import decay
    from stanley.routes import photos as photo_routes

    pid = posted(circle.ana)["id"]
    real = photo_routes.prepare_upload

    def meanwhile(data):
        with db() as s:
            decay.scrub(s, app.state.storage, s.get(Photo, pid), START, owner_requested=True)
            s.commit()
        return real(data)

    monkeypatch.setattr(photo_routes, "prepare_upload", meanwhile)
    assert add(circle.ana, pid).status_code == 404
    with db() as s:
        assert s.scalars(select(PhotoImage)).all() == []
