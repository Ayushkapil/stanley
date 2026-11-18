"""Build 79: a face is a new file each time it changes, so a phone can keep
faces by name and never show an old one; and it's 256px, enough for the
largest place one is drawn."""
from __future__ import annotations

from io import BytesIO

from PIL import Image

from stanley.models import User

from .conftest import jpeg_bytes


def key_of(db, api):
    with db() as session:
        return session.get(User, api.id).avatar_key


def upload(api):
    return api.client.post("/me/avatar", files={"file": ("a.jpg", jpeg_bytes(), "image/jpeg")}, headers=api.h)


def test_a_new_face_is_a_new_file_and_the_old_one_goes(circle, app, db):
    assert upload(circle.ana).status_code == 200
    first = key_of(db, circle.ana)
    assert upload(circle.ana).status_code == 200
    second = key_of(db, circle.ana)
    assert first != second and second.startswith(f"avatars/{circle.ana.id}-")
    assert not app.state.storage.exists(first) and app.state.storage.exists(second)


def test_the_link_names_the_new_file(circle):
    before = upload(circle.ana).json()["avatar_url"].split("?")[0]
    after = upload(circle.ana).json()["avatar_url"].split("?")[0]
    assert before != after


def test_a_face_is_256_at_most(circle, app, db):
    upload(circle.ana)
    img = Image.open(BytesIO(app.state.storage.get(key_of(db, circle.ana))))
    assert max(img.size) <= 256 and img.size[0] == img.size[1]


def test_an_old_unversioned_face_is_replaced_and_deleted(circle, app, db):
    """A face uploaded before build 79 lives at avatars/<id>.jpg; changing it
    moves it to a versioned name and deletes the old file."""
    old = f"avatars/{circle.ana.id}.jpg"
    app.state.storage.put(old, jpeg_bytes())
    with db() as session:
        session.get(User, circle.ana.id).avatar_key = old
        session.commit()
    upload(circle.ana)
    assert key_of(db, circle.ana) != old and not app.state.storage.exists(old)
