"""The readiness probe (§13 ops): unauthenticated, cheap, always 200 while
the process is serving."""
from __future__ import annotations


def test_health_is_200_without_auth(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
