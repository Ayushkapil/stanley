"""Apple Push Notification service, directly (build 18): token auth over
HTTP/2, no third party in between.

Only three notices ever travel this way, and only to someone who turned
them on (§10): the owner's last-light notice, the evening digest, and since
build 37 "{name} shared a moment" (N5). The text is the notice's own, with
no count, deadline or countdown (N4), no sound, and nothing in it but the
words.

Token auth: an ES256 JWT signed with the team's APNs key (a .p8 from Apple
Developer → Keys), naming the key and the team. Apple accepts one for up to
an hour and asks that it not be minted more often than every twenty
minutes, so one is kept for fifty. See DEPLOY.md for the key.
"""
from __future__ import annotations

import logging
import threading
import time

import jwt

log = logging.getLogger("stanley")

HOSTS = {
    "production": "https://api.push.apple.com",
    "sandbox": "https://api.sandbox.push.apple.com",
}

# A device token Apple says will never work again: drop it. Anything else
# (a 5xx, a 429, our own auth trouble) leaves it for next time.
_GONE_REASONS = {"BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"}

SENT, GONE, FAILED = "sent", "gone", "failed"


class APNs:
    def __init__(self, key_pem: str, key_id: str, team_id: str, topic: str, client=None, now=time.time):
        self._key = key_pem
        self._key_id = key_id
        self._team_id = team_id
        self._topic = topic
        self._client = client
        self._now = now
        self._lock = threading.Lock()
        self._jwt: tuple[str, float] | None = None

    def _http(self):
        if self._client is None:
            import httpx

            # HTTP/2 is required by APNs. One client, reused, so pushes in a
            # pass share a connection.
            self._client = httpx.Client(http2=True, timeout=10)
        return self._client

    def bearer(self) -> str:
        """The provider token, minted at most every fifty minutes."""
        with self._lock:
            now = self._now()
            if self._jwt is None or now - self._jwt[1] > 50 * 60:
                token = jwt.encode(
                    {"iss": self._team_id, "iat": int(now)},
                    self._key,
                    algorithm="ES256",
                    headers={"kid": self._key_id},
                )
                self._jwt = (token, now)
            return self._jwt[0]

    @staticmethod
    def payload(body: str) -> dict:
        """The words and nothing else: no sound, no badge, no data."""
        return {"aps": {"alert": {"body": body}}}

    def send(self, device_token: str, environment: str, body: str) -> str:
        """SENT, GONE (drop the token) or FAILED (keep it, try another day)."""
        host = HOSTS.get(environment, HOSTS["production"])
        try:
            response = self._http().post(
                f"{host}/3/device/{device_token}",
                json=self.payload(body),
                headers={
                    "authorization": f"bearer {self.bearer()}",
                    "apns-topic": self._topic,
                    "apns-push-type": "alert",
                    # 5: delivered when it suits the phone's power, not at once.
                    # Nothing Stanley says is urgent.
                    "apns-priority": "5",
                },
            )
        except Exception:
            log.exception("apns: request failed")
            return FAILED
        if response.status_code == 200:
            return SENT
        reason = ""
        try:
            reason = response.json().get("reason", "")
        except Exception:
            pass
        if response.status_code == 410 or reason in _GONE_REASONS:
            return GONE
        log.warning("apns: %s %s", response.status_code, reason)
        return FAILED


class PushDelivery:
    """The notifier's transport once APNs is configured: every phone the
    person has signed in on, in its own session, after the notice's log row
    is committed. Tokens Apple has given up on are deleted."""

    def __init__(self, apns: APNs, sessionmaker):
        self._apns = apns
        self._sessionmaker = sessionmaker

    def __call__(self, user_id: str, kind: str, body: str) -> None:
        from sqlalchemy import select

        from .models import PushToken

        with self._sessionmaker() as session:
            tokens = session.scalars(select(PushToken).where(PushToken.user_id == user_id)).all()
            for token in tokens:
                if self._apns.send(token.token, token.environment, body) == GONE:
                    session.delete(token)
            session.commit()
