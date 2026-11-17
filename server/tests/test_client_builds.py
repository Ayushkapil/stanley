"""Build 77: which builds of the app connect, from the User-Agent the app
already sends, with nothing about who."""
from __future__ import annotations

import time

from sqlalchemy import select

from stanley.builds import build_from
from stanley.models import ClientBuild


def test_the_build_is_read_from_the_apps_own_user_agent():
    assert build_from(b"Stanley/76 CFNetwork/3826.400.120 Darwin/25.0.0") == 76
    assert build_from(b"Stanley/13 CFNetwork/1568 Darwin/24") == 13
    for other in (None, b"", b"curl/8.7.1", b"Mozilla/5.0", b"StanleyX/3", b"Stanley/abc"):
        assert build_from(other) is None


def test_a_build_that_connects_is_kept_with_nothing_about_who(client, db):
    client.get("/health", headers={"User-Agent": "Stanley/76 CFNetwork/3826 Darwin/25"})
    client.get("/health", headers={"User-Agent": "Stanley/55 CFNetwork/3826 Darwin/25"})
    client.get("/health", headers={"User-Agent": "Stanley/76 CFNetwork/3826 Darwin/25"})
    client.get("/health", headers={"User-Agent": "curl/8.7.1"})
    # The row is written off the request, so give it a moment.
    deadline = time.monotonic() + 3
    while True:
        with db() as session:
            rows = session.scalars(select(ClientBuild).order_by(ClientBuild.build)).all()
            seen = [(r.build, bool(r.first_seen and r.last_seen)) for r in rows]
        if len(seen) == 2 or time.monotonic() > deadline:
            break
        time.sleep(0.02)
    assert seen == [(55, True), (76, True)]
    # One row per build: no account, address or tally column.
    assert set(ClientBuild.__table__.columns.keys()) == {"build", "first_seen", "last_seen"}
