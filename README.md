# Stanley — One Day, One Photo

Stanley is a photo app for one small circle of people, built on two structural
laws: **you may post exactly one photo per day**, and **every photo decays out
of existence within six days unless someone deliberately keeps it**. Holding a
photo is private and never counted; it saves the image for the person who held
it without changing how the photo fades for anyone else. There are no likes to
tally, no followers, no ranking, and no algorithm — Today is reverse-chronological
and nothing else. People appear as faces, never as numbers. Much of Stanley's
identity is in what it refuses: counts anywhere in the product, engagement
signals, open audiences, and notifications designed to pull you back. What's
left is a small, quiet record of a few people's days, most of which is meant to
disappear.

> **Pilot build.** Stanley is pre-release, aimed at a single real circle (a dorm
> floor; the circle ceiling is a soft 100). It has not been through TestFlight or an App Store
> review yet, and some pieces documented below are deliberately unfinished.

## Tech stack

| Layer | What it is |
| --- | --- |
| Client | Swift / SwiftUI, iOS 17+, generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| Server | FastAPI monolith (Python 3.11), single process, in-process 15-minute decay sweeper |
| Database | SQLite (WAL, foreign keys on) — the right size for one circle, deliberately not migrated away from |
| Auth | Sign in with Apple (RS256 against Apple's JWKS) → Stanley's own HS256 JWT, stored in the Keychain |
| Blobs | Local disk behind short-TTL HMAC-signed URLs; an S3-compatible (R2) backend is config-switchable |
| Crash reporting | Sentry, off unless a DSN is configured — see [PRIVACY_LABEL.md](PRIVACY_LABEL.md) |

## Layout

```
ios/                   SwiftUI client (iOS 17+)
  project.yml          XcodeGen spec — run `xcodegen generate` after adding files
  Stanley/             Today feed, capture, Held archive, profiles, settings
server/
  stanley/
    physics.py         THE LOCKED PHYSICS — decay timeline, one-per-day + 12h gap
    decay.py           state machine, purge queue, append-only audit log
    images.py          EXIF allowlist ({DateTime} only — GPS removal is a hard rule)
    storage.py         blob store + 15-minute signed URLs (no public URLs, ever)
    routes/            the HTTP surface
  scripts/             dev-only tools (demo seeding, decay time-travel)
  tests/               the contract — see below
```

## Run it locally

**Server:**

```bash
cd server
python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/python -m pytest
STANLEY_DEV_AUTH=1 STANLEY_SECRET_KEY=dev .venv/bin/python -m uvicorn --factory stanley.main:create_app
```

Run **one** uvicorn process. Each one starts its own decay sweeper, so workers
would multiply the sweep.

Optionally seed a living circle to look at — nine people, photos spread across
every decay state, and an invite code printed at the end:

```bash
cd server && .venv/bin/python scripts/seed_demo_full.py
```

**iOS app:**

```bash
cd ios && xcodegen generate && open Stanley.xcodeproj
```

Pick an iPhone simulator and Run. In debug builds the app talks to
`localhost`, so the server above is all you need. Sign in with any name to
create an account (dev auth), or use a seeded name to land in the demo circle,
then join with the invite code. The simulator has no camera, so capture uses a
generated stand-in frame; on a real device it opens the camera.

Everything is configured through the environment — `STANLEY_DATABASE_URL`,
`STANLEY_BLOB_DIR`, `STANLEY_SECRET_KEY`, `STANLEY_DEV_AUTH`, `APPLE_BUNDLE_ID`,
and the client's `STANLEY_API_BASE`. Nothing is hardcoded, and the server
refuses to boot without a signing secret once dev auth is off.

## The invariants (non-negotiable, and tested)

| Invariant | Enforced where |
| --- | --- |
| One photo per person per local calendar day, ≥12h gap | `physics.violates_capture_rules` + `UNIQUE(owner_id, local_date)` as the race backstop |
| Deleting today's photo does not refund the slot | slot check counts soft-deleted and purged rows |
| **A1**: holding never alters public decay or feed order | the decay engine and feed query never read anchors |
| **A2**: hold/like identities are owner-only; no counts anywhere | the photo payload structurally lacks the field |
| A blob survives purge iff someone held it at expiry | `decay.sweep` |
| Owner deletion purges everywhere; holders keep only an honest tombstone | `decay.scrub(owner_requested=True)` |
| EXIF stripped to `{DateTime}` — GPS removal | `images.py` allowlist |
| At most one push per day, and never one carrying a count or a deadline | `notifications.py` is the only send path |

**Decay timeline:** `LIVE` 0–48h → `FADING` 48–120h → `LAST_LIGHT` 120–144h →
`EXPIRED` (leaves Today; the image survives only if someone held it) →
`PURGED` after a 7-day tombstone. The server is authoritative; clients only
interpolate the visual fade from `decay_progress`.

**Tests:** 152, covering the hard parts — physics as Hypothesis property tests
across DST and timezone hops, the full decay lifecycle at exact boundaries,
A1/A2, deletion cascades, block bidirectionality, auth hardening, capture-race
and orphan-blob safety, and one cold-start test that walks a new user's entire
first week end to end.

```bash
cd server && .venv/bin/python -m pytest
```

## Further reading

- [server/DEPLOY.md](server/DEPLOY.md) — deploying the single-process server behind Caddy
- [PRIVACY_LABEL.md](PRIVACY_LABEL.md) — exactly what Stanley collects, as an App Store privacy-label checklist
- [CLAUDE.md](CLAUDE.md) — the locked design rules and architecture notes

## Not built yet (deliberately)

- **APNs transport** — the last-light notice and digest are recorded, not yet pushed
- **Live Sign in with Apple** — verified against a mocked signing key, not yet run on a real device
- **R2 blob backend** — wired and config-switchable, not switched on
- **CSAM hash-matching + NCMEC reporting** — required before any release beyond a closed pilot
- **Off-box backups** — daily local snapshots exist; copying them off the machine is still manual

Android, video, DMs, and multiple circles per person are permanent non-goals
for the pilot, not a backlog.

## License

All rights reserved — see [LICENSE](LICENSE). The source is public to read, not
to reuse.
