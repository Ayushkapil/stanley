"""Capture filters: four looks the client bakes into the image before upload.
The server keeps only the name, as a label. An unknown name is dropped
rather than refused, and the label goes when the photo does."""
from __future__ import annotations

import io
import json
import zipfile

import pytest

from stanley.models import Photo


@pytest.mark.parametrize("name", ["mono", "grain", "dusk", "clean"])
def test_each_filter_name_is_kept_with_the_photo(circle, name):
    r = circle.ana.post_photo(filter=name)
    assert r.status_code == 201, r.text
    assert r.json()["filter"] == name
    assert circle.ben.feed_photos()[0]["filter"] == name


def test_no_filter_is_null(circle):
    assert circle.ana.post_photo().json()["filter"] is None


@pytest.mark.parametrize("sent", ["none", "", "  ", "vivid", "sepia", "x" * 500])
def test_an_unknown_filter_is_dropped_and_the_photo_still_posts(circle, sent):
    r = circle.ana.post_photo(filter=sent)
    assert r.status_code == 201, r.text
    assert r.json()["filter"] is None


def test_filter_name_is_normalized(circle):
    assert circle.ana.post_photo(filter=" Mono ").json()["filter"] == "mono"


def test_filter_is_a_label_not_a_rerender(circle, app):
    """The bytes the server stores are the bytes the client baked. Posting the
    same image with and without a filter name yields the same derivative."""
    from .conftest import jpeg_bytes

    image = jpeg_bytes()
    plain = circle.ana.post_photo(image=image).json()
    labelled = circle.ben.post_photo(image=image, filter="dusk").json()
    a = circle.ana.client.get(plain["urls"]["image"]).content
    b = circle.ben.client.get(labelled["urls"]["image"]).content
    assert a == b


def test_owner_delete_purges_the_filter_label(circle, db):
    pid = circle.ana.post_photo(filter="grain").json()["id"]
    circle.ben.anchor(pid)
    circle.ana.delete_photo(pid)
    with db() as session:
        assert session.get(Photo, pid).filter is None


def test_export_carries_the_filter_name(circle):
    pid = circle.ana.post_photo(filter="clean").json()["id"]
    circle.ben.anchor(pid)
    zf = zipfile.ZipFile(io.BytesIO(circle.ben.export().content))
    entry = json.loads(zf.read("memories.json"))["held"][0]
    assert entry["filter"] == "clean"
