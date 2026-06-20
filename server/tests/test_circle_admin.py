"""Settings + safety round: invite rotation, member removal, leaving, avatars,
and the held-memories export."""
from __future__ import annotations

import io
import json
import zipfile
from datetime import timedelta

from PIL import Image

from .conftest import START, make_user


def _wide_jpeg() -> bytes:
    img = Image.new("RGB", (800, 400), (120, 90, 200))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    return buf.getvalue()


# --- invite rotation ---------------------------------------------------------


def test_rotate_invite_invalidates_old_code(client, circle):
    old = circle.invite_token
    r = circle.ana.rotate_invite(circle.id)
    assert r.status_code == 200
    new = r.json()["invite_token"]
    assert new != old

    latecomer = make_user(client, "late")
    assert latecomer.join(old).status_code == 404  # old code is dead
    assert latecomer.join(new).status_code == 201  # new code works


def test_invite_code_format_and_case_insensitivity(client, circle):
    """Short code is XXXX-XXXX; join accepts lower-case and no-hyphen variants."""
    code = circle.invite_token
    assert len(code) == 9 and code[4] == "-"  # XXXX-XXXX format
    latecomer = make_user(client, "lc")
    # Case-insensitive
    assert latecomer.join(code.lower()).status_code == 201


def test_invite_code_no_hyphen_accepted(client, circle):
    """Users can omit the hyphen when typing a code manually."""
    code_no_hyphen = circle.invite_token.replace("-", "")
    latecomer = make_user(client, "lc2")
    assert latecomer.join(code_no_hyphen).status_code == 201


def test_rotate_invite_is_creator_only(circle):
    r = circle.ben.rotate_invite(circle.id)
    assert r.status_code == 403
    assert r.json()["detail"]["code"] == "creator_only"


# --- remove member -----------------------------------------------------------


def test_creator_removes_member(circle):
    assert circle.ana.remove_member(circle.id, circle.cam.id).status_code == 204
    # cam is out: no circle, so the feed is gone
    assert circle.cam.feed().json()["detail"]["code"] == "no_circle"
    # ana and ben remain
    members = {m["display_name"] for m in circle.ana.client.get("/circles/mine", headers=circle.ana.h).json()["members"]}
    assert members == {"ana", "ben"}


def test_non_creator_cannot_remove(circle):
    r = circle.ben.remove_member(circle.id, circle.cam.id)
    assert r.status_code == 403
    assert r.json()["detail"]["code"] == "creator_only"


def test_creator_cannot_remove_self_via_remove(circle):
    r = circle.ana.remove_member(circle.id, circle.ana.id)
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "use_leave"


# --- leave -------------------------------------------------------------------


def test_member_can_leave(circle):
    assert circle.cam.leave(circle.id).status_code == 204
    assert circle.cam.feed().json()["detail"]["code"] == "no_circle"


def test_creator_leaving_transfers_ownership(circle):
    assert circle.ana.leave(circle.id).status_code == 204
    # The circle is never left ownerless: exactly one remaining member becomes
    # creator and can act as one. (Which one is a deterministic tiebreak, not
    # something this invariant test should pin down.)
    creators = [
        api
        for api in (circle.ben, circle.cam)
        if api.client.get("/circles/mine", headers=api.h).json()["is_creator"]
    ]
    assert len(creators) == 1
    assert creators[0].rotate_invite(circle.id).status_code == 200


def test_leaver_keeps_their_held_memories(circle, clock, sweep):
    """Leaving doesn't strip your keepsakes — the held archive is personal."""
    pid = circle.ana.post_photo().json()["id"]
    circle.ben.anchor(pid, note="before I left")
    assert circle.ben.leave(circle.id).status_code == 204
    threads = circle.ben.memories().json()["threads"]
    assert threads and threads[0]["memories"][0]["note"] == "before I left"


# --- avatars -----------------------------------------------------------------


def test_avatar_upload_appears_everywhere_as_face(circle):
    r = circle.ana.set_avatar(_wide_jpeg())
    assert r.status_code == 200, r.text
    url = r.json()["avatar_url"]
    assert url

    # the bytes serve, and are a square (center-cropped server-side)
    img_resp = circle.ana.client.get(url)
    assert img_resp.status_code == 200
    img = Image.open(io.BytesIO(img_resp.content))
    assert img.width == img.height

    # own profile, members roster, and member-profile all carry the face
    assert circle.ana.client.get("/me", headers=circle.ana.h).json()["avatar_url"]
    roster = circle.ben.client.get("/circles/mine", headers=circle.ben.h).json()["members"]
    ana_row = [m for m in roster if m["display_name"] == "ana"][0]
    assert ana_row["avatar_url"] and ana_row["is_creator"] is True
    member = circle.ben.client.get(f"/members/{circle.ana.id}", headers=circle.ben.h).json()
    assert member["avatar_url"]


def test_avatar_rejects_non_image(circle):
    r = circle.ana.set_avatar(b"not an image")
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "bad_image"


def test_me_includes_join_date(circle):
    me = circle.ana.client.get("/me", headers=circle.ana.h).json()
    assert me["created_at"] is not None
    # nothing count-shaped sneaks into the identity payload
    assert not any("count" in k for k in me)


# --- export ------------------------------------------------------------------


def test_export_bundles_held_photos_and_captions(circle):
    pid = circle.ana.post_photo(caption="the lake", location="Dunn Meadow").json()["id"]
    circle.ben.anchor(pid, note="kept this")

    r = circle.ben.export()
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/zip"

    zf = zipfile.ZipFile(io.BytesIO(r.content))
    names = zf.namelist()
    assert "memories.json" in names
    manifest = json.loads(zf.read("memories.json"))
    assert len(manifest["held"]) == 1
    entry = manifest["held"][0]
    assert entry["caption"] == "the lake"
    assert entry["location"] == "Dunn Meadow"
    assert entry["note"] == "kept this"
    assert entry["from"] == "ana"
    assert entry["image"] in names  # the jpeg is in the bundle


def test_export_renders_tombstone_for_deleted_original(circle):
    pid = circle.ana.post_photo(caption="gone").json()["id"]
    circle.ben.anchor(pid, note="kept")
    circle.ana.delete_photo(pid)  # owner purges the image

    zf = zipfile.ZipFile(io.BytesIO(circle.ben.export().content))
    manifest = json.loads(zf.read("memories.json"))
    entry = manifest["held"][0]
    assert entry["image"] is None
    assert entry.get("tombstone") is True
    assert entry["note"] == "kept"


def test_account_deletion_clears_avatar_and_given_likes(circle, db, app):
    from sqlalchemy import func, select

    from stanley.models import Like, User

    circle.ana.set_avatar()
    pid = circle.ben.post_photo().json()["id"]
    circle.ana.like(pid)
    with db() as session:
        avatar_key = session.get(User, circle.ana.id).avatar_key
    assert app.state.storage.exists(avatar_key)

    assert circle.ana.delete_me().status_code == 204
    assert not app.state.storage.exists(avatar_key)
    with db() as session:
        assert session.scalar(select(func.count()).select_from(Like)) == 0
