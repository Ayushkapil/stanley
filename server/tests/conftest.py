from __future__ import annotations

import io
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from stanley import decay
from stanley.clock import FakeClock
from stanley.config import Settings
from stanley.main import create_app

# Tuesday June 9 2026, 11:00 in New York. Tests that care about local time
# assume this anchor point.
START = datetime(2026, 6, 9, 15, 0, tzinfo=timezone.utc)
NY = "America/New_York"


def jpeg_bytes(with_exif: bool = False) -> bytes:
    img = Image.new("RGB", (640, 480), (200, 80, 60))
    buf = io.BytesIO()
    if with_exif:
        exif = Image.Exif()
        exif[271] = "TestCam"  # Make — must not survive ingest
        exif[306] = "2026:06:09 11:00:00"  # DateTime — the one allowed survivor
        try:
            exif.get_ifd(0x8825)[1] = "N"  # GPSLatitudeRef, best-effort embed
        except Exception:
            pass
        img.save(buf, format="JPEG", exif=exif)
    else:
        img.save(buf, format="JPEG")
    return buf.getvalue()


class Api:
    """A user-bound API helper so tests read like the product."""

    def __init__(self, client: TestClient, token: str, user: dict):
        self.client = client
        self.token = token
        self.id = user["id"]
        self.name = user["display_name"]

    @property
    def h(self) -> dict:
        return {"Authorization": f"Bearer {self.token}"}

    def post_photo(self, tz: str = NY, caption: str | None = None, location: str | None = None, image: bytes | None = None, claim: str | None = None, tagged: list[str] | None = None):
        data: dict = {"tz": tz}
        if caption is not None:
            data["caption"] = caption
        if location is not None:
            data["location"] = location
        if claim is not None:
            data["taken_at_claim"] = claim
        if tagged:
            data["tagged"] = tagged  # list → repeated form fields
        files = {"file": ("photo.jpg", image or jpeg_bytes(), "image/jpeg")}
        return self.client.post("/photos", files=files, data=data, headers=self.h)

    def untag_me(self, pid):
        return self.client.delete(f"/photos/{pid}/tags/me", headers=self.h)

    def milestones(self):
        return self.client.get("/me/milestones", headers=self.h)

    def dismiss_milestone(self, mid):
        return self.client.delete(f"/me/milestones/{mid}", headers=self.h)

    def delete_photo(self, pid):
        return self.client.delete(f"/photos/{pid}", headers=self.h)

    def feed(self):
        return self.client.get("/feed/today", headers=self.h)

    def feed_photos(self):
        """Flatten the Today feed (moments + standalone) to a list of photos."""
        out = []
        for item in self.feed().json().get("items", []):
            if item["kind"] == "photo":
                out.append(item["photo"])
            else:
                out.extend(item["photos"])
        return out

    def feed_items(self):
        return self.feed().json().get("items", [])

    def set_note(self, circle_id, text):
        return self.client.put(
            f"/circles/{circle_id}/note", json={"text": text}, headers=self.h
        )

    def returned(self, tz: str = NY):
        return self.client.get("/feed/returned", params={"tz": tz}, headers=self.h)

    def dismiss_returned(self, tz: str = NY):
        return self.client.post("/feed/returned/dismiss", params={"tz": tz}, headers=self.h)

    def rested(self):
        return self.client.get("/memories/rested", headers=self.h)

    def anchor(self, pid, note=None):
        return self.client.post(f"/photos/{pid}/anchor", json={"note": note}, headers=self.h)

    def like(self, pid):
        return self.client.post(f"/photos/{pid}/like", headers=self.h)

    def unlike(self, pid):
        return self.client.delete(f"/photos/{pid}/like", headers=self.h)

    def likes_of(self, pid):
        return self.client.get(f"/photos/{pid}/likes", headers=self.h)

    def set_avatar(self, image: bytes | None = None):
        files = {"file": ("a.jpg", image or jpeg_bytes(), "image/jpeg")}
        return self.client.post("/me/avatar", files=files, headers=self.h)

    def export(self):
        return self.client.get("/me/export", headers=self.h)

    def rotate_invite(self, circle_id):
        return self.client.post(f"/circles/{circle_id}/rotate_invite", headers=self.h)

    def remove_member(self, circle_id, uid):
        return self.client.delete(f"/circles/{circle_id}/members/{uid}", headers=self.h)

    def leave(self, circle_id):
        return self.client.post(f"/circles/{circle_id}/leave", headers=self.h)

    def join(self, circle_id, token):
        return self.client.post(
            f"/circles/{circle_id}/join", json={"invite_token": token}, headers=self.h
        )

    def unanchor(self, pid):
        return self.client.delete(f"/photos/{pid}/anchor", headers=self.h)

    def anchors_of(self, pid):
        return self.client.get(f"/photos/{pid}/anchors", headers=self.h)

    def comment(self, pid, body):
        return self.client.post(f"/photos/{pid}/comments", json={"body": body}, headers=self.h)

    def memories(self):
        return self.client.get("/me/anchored", headers=self.h)

    def rest(self, pid):
        return self.client.post(f"/memories/{pid}/rest", headers=self.h)

    def unrest(self, pid):
        return self.client.delete(f"/memories/{pid}/rest", headers=self.h)

    def block(self, uid):
        return self.client.post("/blocks", json={"user_id": uid}, headers=self.h)

    def unblock(self, uid):
        return self.client.delete(f"/blocks/{uid}", headers=self.h)

    def report(self, **kw):
        return self.client.post("/reports", json=kw, headers=self.h)

    def patch_settings(self, **kw):
        return self.client.patch("/me/settings", json=kw, headers=self.h)

    def delete_me(self):
        return self.client.delete("/me", headers=self.h)


@pytest.fixture
def clock():
    return FakeClock(START)


@pytest.fixture
def app(tmp_path, clock):
    settings = Settings(
        database_url="sqlite://",
        blob_dir=str(tmp_path / "blobs"),
        secret_key="test-secret-key-with-enough-bytes-for-hs256",
        dev_auth=True,
        run_sweeper=False,
    )
    return create_app(settings, clock=clock)


@pytest.fixture
def client(app):
    return TestClient(app)


def make_user(client: TestClient, name: str) -> Api:
    r = client.post("/auth/dev", json={"display_name": name})
    assert r.status_code == 201, r.text
    body = r.json()
    return Api(client, body["token"], body["user"])


@pytest.fixture
def circle(client):
    """Three users in one circle: ana (creator), ben, cam."""
    ana = make_user(client, "ana")
    ben = make_user(client, "ben")
    cam = make_user(client, "cam")
    r = ana.client.post("/circles", json={"name": "floor 3"}, headers=ana.h)
    assert r.status_code == 201, r.text
    info = r.json()
    for u in (ben, cam):
        rj = u.client.post(
            f"/circles/{info['id']}/join", json={"invite_token": info["invite_token"]}, headers=u.h
        )
        assert rj.status_code == 201, rj.text
    return SimpleNamespace(ana=ana, ben=ben, cam=cam, id=info["id"], invite_token=info["invite_token"])


@pytest.fixture
def sweep(app):
    """Run one worker pass (decay sweep + purges), like §13's 15-minute job."""

    def _sweep():
        with app.state.sessionmaker() as session:
            advanced = decay.sweep(session, app.state.clock, app.state.notifier)
            purged = decay.run_purges(session, app.state.storage, app.state.clock)
            session.commit()
        return advanced, purged

    return _sweep


@pytest.fixture
def db(app):
    """Factory for raw DB sessions, for assertions the API deliberately
    refuses to expose (anchor counts, purge queue, audit log)."""
    return app.state.sessionmaker
