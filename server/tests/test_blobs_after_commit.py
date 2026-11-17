"""D3 (build 77): a photo's files are deleted only once the database has
committed letting go of them. A rollback leaves the files with the rows that
still name them, instead of rows pointing at files that are gone."""
from __future__ import annotations

from stanley import decay
from stanley.models import Photo, User


def _files(app, db, pid):
    with db() as session:
        photo = session.get(Photo, pid)
        keys = [k for k in (photo.blob_key, photo.deriv_key, photo.thumb_key) if k]
    return keys, [app.state.storage.exists(k) for k in keys]


def test_a_rolled_back_scrub_keeps_the_files(circle, app, db, clock):
    pid = circle.ana.post_photo().json()["id"]
    keys, there = _files(app, db, pid)
    assert keys and all(there)
    with db() as session:
        photo = session.get(Photo, pid)
        decay.scrub(session, app.state.storage, photo, clock.now(), owner_requested=True)
        # Nothing is deleted before the commit...
        assert all(app.state.storage.exists(k) for k in keys)
        session.rollback()
    # ...and a rollback keeps every file, the row still naming them.
    assert _files(app, db, pid) == (keys, [True] * len(keys))


def test_a_committed_scrub_deletes_them(circle, app, db, clock):
    pid = circle.ana.post_photo().json()["id"]
    keys, _ = _files(app, db, pid)
    with db() as session:
        decay.scrub(session, app.state.storage, session.get(Photo, pid), clock.now(), owner_requested=True)
        session.commit()
    assert not any(app.state.storage.exists(k) for k in keys)


def test_deleting_a_photo_through_the_app_still_deletes_its_files(circle, app, db):
    pid = circle.ana.post_photo().json()["id"]
    keys, _ = _files(app, db, pid)
    assert circle.ana.client.delete(f"/photos/{pid}", headers=circle.ana.h).status_code == 204
    assert not any(app.state.storage.exists(k) for k in keys)


def test_a_failed_account_deletion_keeps_the_avatar(circle, app, db, monkeypatch):
    """The avatar is queued for deletion with the rest; if the deletion's
    transaction fails, the avatar is still there for the account that is."""
    from .conftest import jpeg_bytes

    r = circle.ana.client.post("/me/avatar", files={"file": ("a.jpg", jpeg_bytes(), "image/jpeg")}, headers=circle.ana.h)
    assert r.status_code == 200
    with db() as session:
        key = session.get(User, circle.ana.id).avatar_key
    assert app.state.storage.exists(key)
    with db() as session:
        from stanley.storage import delete_after_commit

        delete_after_commit(session, app.state.storage, key)
        session.rollback()
    assert app.state.storage.exists(key)
