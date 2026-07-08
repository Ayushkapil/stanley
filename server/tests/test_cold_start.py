"""The cold-start story: one end-to-end walk through a brand-new user's whole
first week. If this test passes, the product works — account, circle, capture,
feed, decay, holding, and the archive all in one narrative."""
from __future__ import annotations

from datetime import timedelta

from .conftest import START, make_user


def test_new_user_first_week_end_to_end(client, clock, sweep):
    # A founder starts the circle; a brand-new user creates an account and
    # joins with the short invite code.
    founder = make_user(client, "founder")
    newcomer = make_user(client, "newcomer")
    r = founder.client.post("/circles", json={"name": "floor three"}, headers=founder.h)
    assert r.status_code == 201
    code = r.json()["invite_token"]
    assert newcomer.join(code).status_code == 201

    # First photo. It lands LIVE, at zero decay, visible to both sides.
    r = newcomer.post_photo(caption="day one")
    assert r.status_code == 201, r.text
    pid = r.json()["id"]
    assert r.json()["state"] == "LIVE"
    for viewer in (founder, newcomer):
        feed = viewer.feed_photos()
        assert [p["id"] for p in feed] == [pid]
        assert feed[0]["caption"] == "day one"

    # Past a day boundary (and the LIVE window): the server has advanced the
    # photo's decay, and the client-facing progress has moved with it.
    clock.set(START + timedelta(hours=49))
    sweep()
    photo = founder.feed_photos()[0]
    assert photo["state"] == "FADING"
    assert 0.0 < photo["decay_progress"] < 1.0

    # The founder reaches for it — holding is what makes it survivable.
    assert founder.anchor(pid, note="week one").status_code == 201
    threads = founder.memories().json()["threads"]
    assert len(threads) == 1
    memory = threads[0]["memories"][0]
    assert memory["id"] == pid
    assert memory["tombstone"] is False

    # Past the whole public life: gone from Today for everyone…
    clock.set(START + timedelta(hours=145))
    sweep()
    for viewer in (founder, newcomer):
        assert viewer.feed_photos() == []

    # …but whole in the holder's archive: image intact, note intact.
    memory = founder.memories().json()["threads"][0]["memories"][0]
    assert memory["tombstone"] is False
    assert memory["note"] == "week one"
    assert memory["urls"] is not None
