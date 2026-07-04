"""Auth hardening (C1) + Sign in with Apple (Part 2)."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from stanley.apple import APPLE_ISSUER, AppleVerifier
from stanley.config import ConfigError, Settings
from stanley.main import create_app

from .conftest import START

BUNDLE = "app.stanley.ios"


# --- C1: boot refuses without a secret ---------------------------------------


def test_boot_fails_without_secret_when_dev_auth_off():
    with pytest.raises(ConfigError):
        create_app(Settings(database_url="sqlite://", secret_key=None, dev_auth=False, run_sweeper=False))


def test_boot_succeeds_with_secret_set():
    app = create_app(
        Settings(database_url="sqlite://", secret_key="a-real-secret", dev_auth=False, run_sweeper=False)
    )
    assert app is not None


def test_dev_auth_returns_404_when_disabled(tmp_path):
    app = create_app(
        Settings(
            database_url="sqlite://",
            blob_dir=str(tmp_path),
            secret_key="a-real-secret",
            dev_auth=False,
            run_sweeper=False,
        )
    )
    client = TestClient(app)
    r = client.post("/auth/dev", json={"display_name": "mallory"})
    assert r.status_code == 404


def test_dev_auth_same_name_returns_same_user(client):
    """Dev sign-in is idempotent by name: the same display name resolves to one
    account, so a seeded demo user and repeat sign-ins stay stable."""
    first = client.post("/auth/dev", json={"display_name": "Ayush"})
    second = client.post("/auth/dev", json={"display_name": "Ayush"})
    assert first.status_code == 201 and second.status_code == 201
    assert first.json()["user"]["id"] == second.json()["user"]["id"]


def test_dev_auth_distinct_names_are_distinct_users(client):
    a = client.post("/auth/dev", json={"display_name": "Ayush"})
    b = client.post("/auth/dev", json={"display_name": "Sahana"})
    assert a.json()["user"]["id"] != b.json()["user"]["id"]


def test_expired_stanley_jwt_is_401(app, client):
    """Stanley's own JWT expires after 30 days: a stale token is 401, while a
    fresh one for the same user keeps working."""
    body = client.post("/auth/dev", json={"display_name": "ana"}).json()
    uid = body["user"]["id"]

    now = datetime.now(timezone.utc)  # PyJWT checks exp against the real clock
    stale = jwt.encode(
        {
            "sub": uid,
            "iat": int((now - timedelta(days=31)).timestamp()),
            "exp": int((now - timedelta(days=1)).timestamp()),
        },
        app.state.settings.secret_key,
        algorithm="HS256",
    )
    r = client.get("/me", headers={"Authorization": f"Bearer {stale}"})
    assert r.status_code == 401

    r = client.get("/me", headers={"Authorization": f"Bearer {body['token']}"})
    assert r.status_code == 200


# --- Part 2: Sign in with Apple ----------------------------------------------


@pytest.fixture
def apple_keypair():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return key, key.public_key()


def _apple_token(private_key, *, sub="apple-sub-123", aud=BUNDLE, iss=APPLE_ISSUER, exp_delta=timedelta(hours=1)):
    # Apple-token exp/iat are validated by PyJWT against the real system clock,
    # so use wall-clock time here (not the FakeClock used for Stanley's own JWT).
    now = datetime.now(timezone.utc)
    payload = {
        "iss": iss,
        "aud": aud,
        "sub": sub,
        "iat": int(now.timestamp()),
        "exp": int((now + exp_delta).timestamp()),
    }
    return jwt.encode(payload, private_key, algorithm="RS256")


@pytest.fixture
def apple_app(tmp_path, clock, apple_keypair):
    _, public_key = apple_keypair
    verifier = AppleVerifier(audience=BUNDLE, signing_key=public_key)
    app = create_app(
        Settings(
            database_url="sqlite://",
            blob_dir=str(tmp_path),
            secret_key="a-real-secret",
            dev_auth=False,
            run_sweeper=False,
            apple_bundle_id=BUNDLE,
        ),
        clock=clock,
        apple_verifier=verifier,
    )
    return app


def test_valid_apple_token_creates_user(apple_app, apple_keypair, clock):
    private_key, _ = apple_keypair
    clock.set(START)
    client = TestClient(apple_app)
    token = _apple_token(private_key, sub="sub-aaa")
    r = client.post("/auth/apple", json={"identity_token": token, "name": "Ana K"})
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["token"]
    assert body["user"]["display_name"] == "Ana K"

    # the Stanley JWT is usable
    me = client.get("/me", headers={"Authorization": f"Bearer {body['token']}"})
    assert me.status_code == 200
    assert me.json()["display_name"] == "Ana K"


def test_tampered_apple_token_rejected(apple_app, apple_keypair, clock):
    private_key, _ = apple_keypair
    clock.set(START)
    client = TestClient(apple_app)
    token = _apple_token(private_key)
    tampered = token[:-3] + ("aaa" if not token.endswith("aaa") else "bbb")
    r = client.post("/auth/apple", json={"identity_token": tampered})
    assert r.status_code == 401


def test_expired_apple_token_rejected(apple_app, apple_keypair, clock):
    private_key, _ = apple_keypair
    clock.set(START)
    client = TestClient(apple_app)
    token = _apple_token(private_key, exp_delta=timedelta(hours=-1))  # already expired
    r = client.post("/auth/apple", json={"identity_token": token})
    assert r.status_code == 401


def test_wrong_audience_rejected(apple_app, apple_keypair, clock):
    private_key, _ = apple_keypair
    clock.set(START)
    client = TestClient(apple_app)
    token = _apple_token(private_key, aud="com.someone.else")
    r = client.post("/auth/apple", json={"identity_token": token})
    assert r.status_code == 401


def test_second_sign_in_same_sub_returns_same_user(apple_app, apple_keypair, clock):
    private_key, _ = apple_keypair
    clock.set(START)
    client = TestClient(apple_app)
    first = client.post(
        "/auth/apple", json={"identity_token": _apple_token(private_key, sub="sub-xyz"), "name": "Ben"}
    ).json()
    # second time Apple sends no name; must not create a duplicate
    second = client.post(
        "/auth/apple", json={"identity_token": _apple_token(private_key, sub="sub-xyz")}
    ).json()
    assert first["user"]["id"] == second["user"]["id"]
    assert second["user"]["display_name"] == "Ben"  # original name retained


def test_apple_auth_unconfigured_returns_503(tmp_path, clock):
    app = create_app(
        Settings(
            database_url="sqlite://",
            blob_dir=str(tmp_path),
            secret_key="a-real-secret",
            dev_auth=False,
            run_sweeper=False,
        ),  # no apple_bundle_id, no verifier
        clock=clock,
    )
    client = TestClient(app)
    r = client.post("/auth/apple", json={"identity_token": "x"})
    assert r.status_code == 503
