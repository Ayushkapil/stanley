# Stanley — One Day, One Photo

A small-circle photo app governed by two structural laws: each person may post
**exactly one photo per day**, and every photo **decays out of existence within
six days unless someone deliberately anchors it**. The only gestures are
anchoring (private keeping, no counts ever) and story-comments (co-remembering,
not judging). The product's identity lives in what it refuses: counts, ranking,
algorithmic ordering, open audiences, re-engagement notifications.

This repo implements the [system specification](#spec) — currently the backend
(M0–M4 server-side scope). The iOS client (SwiftUI) is the next milestone.

## Layout

```
server/             FastAPI monolith (Python 3.11+)
  stanley/
    physics.py      THE LOCKED PHYSICS — decay timeline, one-per-day + 12h rule
    decay.py        server-authoritative state machine, purge queue, audit log
    notifications.py§10 policy as code (digest, last-light notice, nothing else)
    returned.py     resurfacing: anniversary > near-forgotten > rescue
    images.py       EXIF allowlist ({DateTime} only — GPS removal is hard req)
    storage.py      blob store + 15-min signed URLs (no public URLs ever)
    routes/         the §12 API surface
  tests/            56 tests: the M0 gate (property tests across DST/travel/
                    clock-skew), full decay lifecycle, invariants A1/A2,
                    deletion semantics, notification policy
```

## Run

```bash
cd server
python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/python -m pytest                      # the contract
.venv/bin/python -m uvicorn --factory stanley.main:create_app --reload
.venv/bin/python -m stanley.worker --once       # manual decay sweep
```

Dev auth is on by default (`POST /auth/dev {"display_name": "ana"}` → JWT).
Config via env: `STANLEY_DATABASE_URL` (SQLite default, Postgres for prod),
`STANLEY_BLOB_DIR`, `STANLEY_SECRET_KEY`, `STANLEY_DEV_AUTH`, `STANLEY_RUN_SWEEPER`.

## The invariants (non-negotiable, tested)

| Invariant | Where enforced | Where tested |
|---|---|---|
| One photo / person / local calendar day, ≥12h gap | `physics.violates_capture_rules` | `test_physics.py` (incl. Hypothesis property tests across DST shifts, timezone hopping, half-hour zones) |
| Deleting today's photo does not refund the slot | slot check includes soft-deleted rows | `test_capture.py`, `test_deletion.py` |
| **A1**: anchors never alter public decay or feed order | decay engine never reads anchors pre-expiry; feed query has no access to them | `test_decay_engine.py` |
| **A2**: anchor identities owner-only; no counts anywhere | photo payload structurally lacks the field; owner-only endpoint | `test_gestures.py` |
| Blob survives purge iff ≥1 anchor at expiry; last unanchor starts the 7-day clock | `decay.sweep` / unanchor route | `test_decay_engine.py` |
| Owner deletion purges everywhere; anchorers keep tombstone + own comment text only | `decay.scrub(owner_requested=True)` | `test_deletion.py` |
| §10: ≤1 push/day, single last-light notice (off by default), no notification for gestures, no digits of urgency | `notifications.py` is the only send path | `test_notifications.py` |
| EXIF stripped to `{DateTime}`; GPS removal | `images.py` allowlist | `test_capture.py` |
| All decay transitions audited append-only | `DecayAudit` rows in every transition | `test_decay_engine.py` (late-sweep walk, idempotency) |

## Decay timeline (the §16 resolved knob)

`LIVE` 0–48h → `FADING` 48–120h → `LAST_LIGHT` 120–144h → `EXPIRED` (leaves
Today; blob retained iff anchored) → `PURGED` +7 days (blob deleted, row
anonymized to a hash). Server-authoritative; clients only interpolate the fade
from `decay_progress` + `state_deadline`.

## Not yet built (deliberately)

- **iOS client** (SwiftUI, capture-only camera, circle-first onboarding) — M1+
- **Sign in with Apple verification** — `/auth/apple` is a 501 stub; dev auth
  gates the pilot
- **APNs transport** — the `Notifier` transport hook is where it plugs in
- **S3/R2 adapter** — `BlobStore` is local-disk with the same interface
- **CSAM hash-matching + data export** — required before any release beyond
  the pilot circle (§15)
- **On-device Returned selection** — the Phase 2 hardening target; the MVP
  heuristic is a random eligible pick by design

## Spec

Built from the Project Stanley critical analysis & system specification v0.1
(June 2026): one circle per person (cap 12, mutual by construction), Today +
Returned surfaces, anchor + story-comment gestures, §7 permanent non-goals,
§10 notification policy as hard requirements.
