"""Push (build 18): the two notices that exist reach a phone through APNs,
only for someone who turned them on, only once their log row is committed,
and never to a phone its owner signed out of."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from sqlalchemy import select

from stanley import notifications
from stanley.apns import APNs, FAILED, GONE, SENT, PushDelivery
from stanley.config import Settings
from stanley.models import NotificationLog, PushToken
from stanley.notifications import Notifier, make_notifier

from .conftest import NY, START, make_user

UTC = timezone.utc
TOKEN_A = "a" * 64
TOKEN_B = "b" * 64


def _key():
    private = ec.generate_private_key(ec.SECP256R1())
    pem = private.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    return pem, private.public_key()


class FakeHTTP:
    def __init__(self, status=200, reason=None, raises=False):
        self.calls = []
        self.status = status
        self.reason = reason
        self.raises = raises

    def post(self, url, json, headers):
        self.calls.append(SimpleNamespace(url=url, json=json, headers=headers))
        if self.raises:
            raise OSError("no route to Apple")
        reason = self.reason
        return SimpleNamespace(status_code=self.status, json=lambda: {"reason": reason} if reason else {})


class FakeAPNs:
    """Answers per token; records what was sent."""

    def __init__(self, answers=None):
        self.answers = answers or {}
        self.sent = []

    def send(self, token, environment, body):
        self.sent.append((token, environment, body))
        return self.answers.get(token, SENT)


def _register(api, token, environment="production"):
    return api.client.post("/me/push-token", json={"token": token, "environment": environment}, headers=api.h)


def _tokens(db):
    with db() as s:
        return {t.token: (t.user_id, t.environment) for t in s.scalars(select(PushToken))}


# --- asking ------------------------------------------------------------------


def test_both_notices_are_off_until_asked_for(circle):
    me = circle.ana.client.get("/me", headers=circle.ana.h).json()
    assert me["last_light_notice_enabled"] is False
    assert me["digest_enabled"] is False
    r = circle.ana.patch_settings(digest_enabled=True)
    assert r.json() == {"last_light_notice_enabled": False, "digest_enabled": True}


def test_no_digest_for_someone_who_didnt_ask(circle, clock, app, db):
    circle.ben.post_photo()
    circle.ana.returned(tz=NY)
    clock.set(datetime(2026, 6, 10, 0, 0, tzinfo=UTC))  # 20:00 in New York
    with app.state.sessionmaker() as session:
        notifications.run_evening_digests(
            session, app.state.notifier, app.state.clock, app.state.settings.digest_hour
        )
        session.commit()
    with db() as s:
        assert s.scalars(select(NotificationLog)).all() == []


# --- tokens ------------------------------------------------------------------


def test_a_phone_registers_its_token(circle, db):
    assert _register(circle.ana, TOKEN_A.upper(), "sandbox").status_code == 204
    assert _register(circle.ana, TOKEN_A, "sandbox").status_code == 204  # again: no harm
    assert _tokens(db) == {TOKEN_A: (circle.ana.id, "sandbox")}


@pytest.mark.parametrize("token,environment", [("xyz", "production"), ("a" * 10, "production"), (TOKEN_A, "staging")])
def test_a_token_that_isnt_one_is_refused(circle, token, environment):
    r = _register(circle.ana, token, environment)
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "bad_push_token"


def test_a_phone_that_changes_hands_follows_who_signed_in(circle, db):
    _register(circle.ana, TOKEN_A)
    _register(circle.ben, TOKEN_A)  # ben signs in on ana's old phone
    assert _tokens(db) == {TOKEN_A: (circle.ben.id, "production")}


def test_signing_out_removes_only_your_own_token(circle, db):
    _register(circle.ana, TOKEN_A)
    _register(circle.ben, TOKEN_B)
    remove = lambda api, t: api.client.request(
        "DELETE", "/me/push-token", json={"token": t}, headers=api.h
    )
    assert remove(circle.ana, TOKEN_B).status_code == 204  # not hers: nothing happens
    assert remove(circle.ana, TOKEN_A).status_code == 204
    assert _tokens(db) == {TOKEN_B: (circle.ben.id, "production")}


def test_deleting_the_account_forgets_its_phones(circle, db):
    _register(circle.ana, TOKEN_A)
    _register(circle.ben, TOKEN_B)
    assert circle.ana.delete_me().status_code == 204
    assert _tokens(db) == {TOKEN_B: (circle.ben.id, "production")}


# --- after commit, never before ------------------------------------------------


def test_a_notice_goes_out_only_once_it_is_committed(app):
    sent = []
    notifier = Notifier(lambda user_id, kind, body: sent.append((user_id, kind, body)))
    notifier.attach(app.state.sessionmaker)
    now = START
    with app.state.sessionmaker() as session:
        user = make_user_row(session)
        notifier.send(session, user, "digest", "Something new", now)
        assert sent == []
        session.commit()
    assert sent == [(user, "digest", "Something new")]

    with app.state.sessionmaker() as session:
        notifier.send(session, user, "digest", "rolled back", now)
        session.rollback()
        session.commit()
    assert len(sent) == 1


def make_user_row(session):
    from stanley.models import User

    user = User(display_name="row", created_at=START)
    session.add(user)
    session.flush()
    return user.id


def test_a_delivery_that_fails_never_fails_the_pass(app, db):
    def broken(*_):
        raise RuntimeError("apple is down")

    notifier = Notifier(broken)
    notifier.attach(app.state.sessionmaker)
    with app.state.sessionmaker() as session:
        user = make_user_row(session)
        notifier.send(session, user, "digest", "x", START)
        session.commit()  # no exception
    with db() as s:
        assert len(s.scalars(select(NotificationLog)).all()) == 1


def test_last_light_reaches_every_phone_and_drops_dead_ones(circle, clock, sweep, app, db):
    apns = FakeAPNs(answers={TOKEN_B: GONE})
    notifier = Notifier(PushDelivery(apns, app.state.sessionmaker))
    notifier.attach(app.state.sessionmaker)
    app.state.notifier = notifier

    circle.ana.patch_settings(last_light_notice_enabled=True)
    _register(circle.ana, TOKEN_A)
    _register(circle.ana, TOKEN_B, "sandbox")
    _register(circle.ben, "c" * 64)
    circle.ana.post_photo()
    clock.set(START + timedelta(hours=121))
    sweep()

    assert sorted(t for t, _, _ in apns.sent) == [TOKEN_A, TOKEN_B]
    assert {e for _, e, _ in apns.sent} == {"production", "sandbox"}
    body = apns.sent[0][2]
    assert "Tuesday" in body and not any(ch.isdigit() for ch in body)
    assert set(_tokens(db)) == {TOKEN_A, "c" * 64}  # Apple gave up on B


# --- the APNs request ------------------------------------------------------------


def _apns(http, now=lambda: 1_800_000_000.0):
    pem, public = _key()
    return APNs(pem, "KEY123", "TEAM456", "com.ayushkapileshwar.stanley", client=http, now=now), public


def test_the_request_is_what_apple_asks_for(circle):
    http = FakeHTTP()
    apns, public = _apns(http)
    assert apns.send(TOKEN_A, "production", "Your moment from Tuesday is fading") == SENT
    assert apns.send(TOKEN_A, "sandbox", "x") == SENT
    first, second = http.calls
    assert first.url == f"https://api.push.apple.com/3/device/{TOKEN_A}"
    assert second.url.startswith("https://api.sandbox.push.apple.com/3/device/")
    # The words and nothing else: no sound, no badge, no data.
    assert first.json == {"aps": {"alert": {"body": "Your moment from Tuesday is fading"}}}
    assert first.headers["apns-topic"] == "com.ayushkapileshwar.stanley"
    assert first.headers["apns-push-type"] == "alert"
    assert first.headers["apns-priority"] == "5"
    bearer = first.headers["authorization"].removeprefix("bearer ")
    assert jwt.get_unverified_header(bearer) == {"alg": "ES256", "kid": "KEY123", "typ": "JWT"}
    # A fixed clock, so iat is checked by value rather than against today.
    claims = jwt.decode(bearer, public, algorithms=["ES256"], options={"verify_iat": False})
    assert claims == {"iss": "TEAM456", "iat": 1_800_000_000}


def test_the_provider_token_is_kept_for_fifty_minutes():
    t = [1_800_000_000.0]
    apns, _ = _apns(FakeHTTP(), now=lambda: t[0])
    first = apns.bearer()
    t[0] += 49 * 60
    assert apns.bearer() == first
    t[0] += 2 * 60
    assert apns.bearer() != first


@pytest.mark.parametrize(
    "status,reason,outcome",
    [
        (410, "Unregistered", GONE),
        (400, "BadDeviceToken", GONE),
        (400, "DeviceTokenNotForTopic", GONE),
        (429, "TooManyRequests", FAILED),
        (500, "InternalServerError", FAILED),
        (403, "InvalidProviderToken", FAILED),
    ],
)
def test_what_apple_answers(status, reason, outcome):
    apns, _ = _apns(FakeHTTP(status=status, reason=reason))
    assert apns.send(TOKEN_A, "production", "x") == outcome


def test_no_connection_is_a_miss_not_a_crash():
    apns, _ = _apns(FakeHTTP(raises=True))
    assert apns.send(TOKEN_A, "production", "x") == FAILED


def test_without_a_key_notices_are_only_logged(app):
    settings = Settings(database_url="sqlite://", secret_key="x", dev_auth=True, run_sweeper=False)
    settings.apns_key = None
    assert make_notifier(settings, app.state.sessionmaker)._transport is None
    pem, _ = _key()
    settings.apns_key, settings.apns_key_id, settings.apns_team_id = pem, "K", "T"
    settings.apns_topic = "com.ayushkapileshwar.stanley"
    assert isinstance(make_notifier(settings, app.state.sessionmaker)._transport, PushDelivery)


# --- renaming a circle (build 18) ----------------------------------------------------


def test_the_organizer_renames_the_circle(circle, client):
    r = circle.ana.client.patch(f"/circles/{circle.id}", json={"name": "  Collins 3  "}, headers=circle.ana.h)
    assert r.status_code == 200
    assert r.json()["name"] == "Collins 3"
    assert circle.ben.client.get("/circles/mine", headers=circle.ben.h).json()["name"] == "Collins 3"
    r = circle.ben.client.patch(f"/circles/{circle.id}", json={"name": "mine now"}, headers=circle.ben.h)
    assert r.status_code == 403
    outsider = make_user(client, "outsider")
    outsider.client.post("/circles", json={"name": "elsewhere"}, headers=outsider.h)
    r = outsider.client.patch(f"/circles/{circle.id}", json={"name": "x"}, headers=outsider.h)
    assert r.status_code == 404
    r = circle.ana.client.patch(f"/circles/{circle.id}", json={"name": "   "}, headers=circle.ana.h)
    assert r.status_code == 400
