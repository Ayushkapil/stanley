"""Step 4 (build 77): with photos on Cloudflare R2, every way a photo or a
picture leaves Stanley removes the object from R2, not just the database
row: the decay purge, the poster deleting it (and the day's redo), account
deletion (photos, avatar, chosen cover), the operator's takedown, and a
journal cover replaced or put back to automatic.

The store is the real `R2BlobStore`, with an in-memory S3 under it that
answers as R2 does, so what's checked is what's left in the bucket. One
test uses botocore's own Stubber to check the wire call itself."""
from __future__ import annotations

from datetime import timedelta

import pytest
from botocore.exceptions import ClientError

from stanley import moderation
from stanley.models import Photo, User
from stanley.storage import R2BlobStore

from .conftest import jpeg_bytes


class FakeS3:
    """Just enough of an S3 client: a dict of objects, R2's answers."""

    def __init__(self):
        self.objects: dict[tuple[str, str], bytes] = {}
        self.deleted: list[str] = []

    def put_object(self, Bucket, Key, Body, ContentType=None):
        self.objects[(Bucket, Key)] = bytes(Body)
        return {}

    def get_object(self, Bucket, Key):
        import io

        if (Bucket, Key) not in self.objects:
            raise ClientError({"Error": {"Code": "NoSuchKey"}, "ResponseMetadata": {"HTTPStatusCode": 404}}, "GetObject")
        return {"Body": io.BytesIO(self.objects[(Bucket, Key)])}

    def head_object(self, Bucket, Key):
        if (Bucket, Key) not in self.objects:
            raise ClientError({"Error": {"Code": "404"}, "ResponseMetadata": {"HTTPStatusCode": 404}}, "HeadObject")
        return {"ContentLength": len(self.objects[(Bucket, Key)])}

    def delete_object(self, Bucket, Key):
        self.objects.pop((Bucket, Key), None)
        self.deleted.append(Key)
        return {}

    def generate_presigned_url(self, op, Params, ExpiresIn):
        return f"https://example.r2/{Params['Key']}?X-Amz-Expires={ExpiresIn}"

    def keys(self):
        return {key for (_bucket, key) in self.objects}

    def get_paginator(self, op):
        fake = self

        class Pages:
            def paginate(self, Bucket):
                yield {"Contents": [{"Key": k} for (b, k) in sorted(fake.objects) if b == Bucket]}

        return Pages()


@pytest.fixture
def s3(app):
    fake = FakeS3()
    app.state.storage = R2BlobStore(endpoint="https://x.r2", bucket="stanley-photos", access_key="k", secret_key="s", client=fake)
    return fake


def photo_keys(db, pid):
    with db() as session:
        p = session.get(Photo, pid)
        return {k for k in (p.blob_key, p.deriv_key, p.thumb_key) if k}


def test_a_posted_photo_lands_in_r2(circle, db, s3):
    pid = circle.ana.post_photo().json()["id"]
    keys = photo_keys(db, pid)
    assert len(keys) == 3 and keys <= s3.keys()


def test_the_decay_purge_removes_it_from_r2(circle, db, s3, clock, sweep):
    pid = circle.ana.post_photo().json()["id"]
    keys = photo_keys(db, pid)
    clock.advance(timedelta(hours=145))
    sweep()
    clock.advance(timedelta(days=8))
    sweep()
    with db() as session:
        assert session.get(Photo, pid).blob_key is None
    assert not keys & s3.keys()


def test_the_poster_deleting_it_removes_it_from_r2(circle, db, s3, clock):
    pid = circle.ana.post_photo().json()["id"]
    keys = photo_keys(db, pid)
    clock.advance(timedelta(hours=13))  # an older photo, no redo
    assert circle.ana.client.delete(f"/photos/{pid}", headers=circle.ana.h).status_code == 204
    assert not keys & s3.keys()


def test_the_days_redo_removes_it_from_r2(circle, db, s3):
    pid = circle.ana.post_photo().json()["id"]
    keys = photo_keys(db, pid)
    assert circle.ana.client.delete(f"/photos/{pid}", headers=circle.ana.h).status_code == 204
    assert not keys & s3.keys()


def test_account_deletion_removes_photos_avatar_and_cover_from_r2(circle, db, s3):
    pid = circle.ana.post_photo().json()["id"]
    photos = photo_keys(db, pid)
    assert circle.ana.client.post("/me/avatar", files={"file": ("a.jpg", jpeg_bytes(), "image/jpeg")}, headers=circle.ana.h).status_code == 200
    assert circle.ana.client.post("/me/journal/cover", files={"file": ("c.jpg", jpeg_bytes(), "image/jpeg")}, headers=circle.ana.h).status_code == 200
    with db() as session:
        user = session.get(User, circle.ana.id)
        pictures = {user.avatar_key, user.journal_cover_key}
    assert (photos | pictures) <= s3.keys()
    r = circle.ana.client.delete("/me", headers=circle.ana.h)
    assert r.status_code in (200, 204), r.text
    assert not (photos | pictures) & s3.keys()


def test_the_operators_takedown_removes_it_from_r2(circle, app, db, s3, clock, tmp_path):
    pid = circle.ana.post_photo().json()["id"]
    keys = photo_keys(db, pid)
    with db() as session:
        assert moderation.take_down_photo(session, app.state.storage, pid, clock.now(), preserve=str(tmp_path / "evidence"))
        session.commit()
    assert not keys & s3.keys()
    # The evidence was copied aside before the object went.
    assert len(list((tmp_path / "evidence" / pid).iterdir())) >= 3


def test_a_replaced_cover_and_a_reset_cover_leave_r2(circle, db, s3):
    post = lambda: circle.ana.client.post("/me/journal/cover", files={"file": ("c.jpg", jpeg_bytes(), "image/jpeg")}, headers=circle.ana.h)
    key_now = lambda: db().__enter__().get(User, circle.ana.id).journal_cover_key
    assert post().status_code == 200
    first = key_now()
    assert post().status_code == 200
    second = key_now()
    assert first not in s3.keys() and second in s3.keys()
    assert circle.ana.client.patch("/me/journal", json={"cover": None}, headers=circle.ana.h).status_code == 200
    assert second not in s3.keys()


def test_a_rolled_back_delete_leaves_the_object(circle, app, db, s3, clock):
    """D3 holds on R2 too: nothing leaves the bucket until the commit."""
    from stanley import decay

    pid = circle.ana.post_photo().json()["id"]
    keys = photo_keys(db, pid)
    with db() as session:
        decay.scrub(session, app.state.storage, session.get(Photo, pid), clock.now(), owner_requested=True)
        session.rollback()
    assert keys <= s3.keys()


def test_nothing_is_left_in_r2_after_every_path(circle, db, s3):
    """After an account is deleted, nothing of it is left in the bucket."""
    circle.ana.post_photo()
    circle.ana.client.post("/me/avatar", files={"file": ("a.jpg", jpeg_bytes(), "image/jpeg")}, headers=circle.ana.h)
    with db() as session:
        mine = {k for (k,) in session.query(Photo.deriv_key).filter(Photo.owner_id == circle.ana.id)}
    circle.ana.client.delete("/me", headers=circle.ana.h)
    leftover = {k for k in s3.keys() if circle.ana.id in k or k in mine}
    assert not leftover


def test_the_real_client_sends_delete_object_to_the_bucket():
    """The wire call: botocore's Stubber asserts DeleteObject goes to this
    bucket and key, and a missing object is "not there", while a refusal
    (bad credentials) is raised, never taken for "not there"."""
    from botocore.stub import Stubber

    store = R2BlobStore(endpoint="https://acct.r2.cloudflarestorage.com", bucket="stanley-photos", access_key="k", secret_key="s")
    with Stubber(store._s3) as stub:
        stub.add_response("delete_object", {}, {"Bucket": "stanley-photos", "Key": "photos/abc/thumb.jpg"})
        store.delete("photos/abc/thumb.jpg")
        stub.add_client_error("head_object", service_error_code="404", http_status_code=404,
                              expected_params={"Bucket": "stanley-photos", "Key": "photos/abc/thumb.jpg"})
        assert store.size("photos/abc/thumb.jpg") is None
        stub.add_client_error("head_object", service_error_code="AccessDenied", http_status_code=403)
        with pytest.raises(ClientError):
            store.size("photos/abc/thumb.jpg")
        stub.assert_no_pending_responses()


def test_presigned_links_are_v4_for_region_auto():
    store = R2BlobStore(endpoint="https://acct.r2.cloudflarestorage.com", bucket="stanley-photos", access_key="k", secret_key="s")
    url = store.presigned_url("photos/abc/thumb.jpg", 900)
    assert "X-Amz-Algorithm=AWS4-HMAC-SHA256" in url and "auto" in url and "X-Amz-Expires=900" in url
