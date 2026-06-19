"""Sign in with Apple identity-token verification (Part 2).

Apple issues the client an identity_token (an RS256 JWT). We verify it against
Apple's published public keys and trust its `sub` claim as the user's permanent
Apple ID. The JWKS is cached (PyJWKClient handles that with a lifespan); an
unknown `kid` triggers a refresh.
"""
from __future__ import annotations

import jwt
from jwt import PyJWKClient

APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"


class AppleAuthError(Exception):
    pass


class AppleVerifier:
    """Verifies Apple identity tokens.

    Production: pass `audience` (your bundle id); keys are fetched from Apple and
    cached for `cache_seconds`.
    Tests: pass `signing_key` (a public key) to verify locally without network —
    the real decode path (signature, aud, iss, exp) still runs.
    """

    def __init__(self, audience, jwks_url=APPLE_KEYS_URL, cache_seconds=86400, signing_key=None):
        self.audience = audience
        self._static_key = signing_key
        self._client = None if signing_key is not None else PyJWKClient(
            jwks_url, cache_keys=True, lifespan=cache_seconds
        )

    def verify(self, identity_token: str) -> dict:
        try:
            key = self._static_key
            if key is None:
                key = self._client.get_signing_key_from_jwt(identity_token).key
            return jwt.decode(
                identity_token,
                key,
                algorithms=["RS256"],
                audience=self.audience,
                issuer=APPLE_ISSUER,
            )
        except jwt.PyJWTError as exc:
            raise AppleAuthError(str(exc)) from exc
        except Exception as exc:  # JWKS fetch / unknown kid / network
            raise AppleAuthError(str(exc)) from exc
