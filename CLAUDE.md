# Stanley — One Day, One Photo

## What it is

Stanley is a small-circle photo app built on two structural laws: each person may
post **exactly one photo per day**, and every photo **decays out of existence
within six days unless someone deliberately keeps (anchors) it**. The only social
gestures are *holding* (a private act of keeping, never counted) and
*story-comments* (co-remembering). The product's identity lives as much in what it
refuses — counts, ranking, algorithmic ordering, open audiences, re-engagement
notifications — as in what it does. The pilot target is one real circle (a dorm
floor); the circle ceiling is a soft 100. Codename: Stanley.

## Locked design rules (do not violate without an explicit product decision)

These are invariants, not preferences. Most are enforced structurally in code and
guarded by tests; treat a change to any of them as a spec change.

- **One photo per person per local calendar day**, plus a 12-hour minimum gap.
  Enforced server-side by `UNIQUE(owner_id, local_date)` + an app check; a race
  returns 409, never a double post. Capture is in-app only (no camera roll).
  **One redo per local day:** deleting *today's* photo refunds the slot exactly
  once (the row is released to an anonymous tombstone, so holders keep theirs);
  a second delete spends the day for good, and deleting an older photo never
  refunds — decay has already started on it.
- **Decay-unless-anchored.** A photo runs `LIVE → FADING → LAST_LIGHT → EXPIRED →
  PURGED` on a fixed clock (48h / 120h / 144h public life, then a 7-day tombstone).
  Holding it makes the blob survive purge; it never changes the photo's public
  decay or feed position. (Invariant **A1**: the decay engine and feed query never
  read anchors.)
- **No counts, ever — anywhere.** No like/hold/follower/view/post counts in the
  DB, the API, or any screen. People are shown as **faces, never numbers**. Owner-
  only "who held / who liked" lists show avatars, never a tally. (Invariant **A2**:
  hold/like identities are owner-only; the photo payload has no field for them.)
- **The like is on Stanley's physics, not Instagram's.** Double-tap, a cosmetic
  heart, owner-only faces, decays *with the photo* (gone forever when it leaves
  Today). Never archived, never recountable.
- **No algorithmic feed.** Today is reverse-chronological and nothing else. No
  ranking, no engagement signals, no recommendation.
- **Notifications are almost nothing.** The only push that exists is the owner's
  single LAST_LIGHT notice for their own photo (off by default). At most one
  evening digest per day. No notification may carry a count, deadline, or
  countdown. No round has added a new notification.
- **The subject wins on deletion.** Owner delete purges the image everywhere;
  anchorers keep an honest tombstone ("a memory was here") plus their own comment
  text only.
- **One circle per person**, mutual by construction, **soft cap 100** — a
  guardrail against an audience, never a target. Nothing nudges toward it.

The authoritative source for the physics constants is
[`server/stanley/physics.py`](server/stanley/physics.py) — pure functions, no I/O.

## Architecture

- **Backend:** FastAPI monolith (Python 3.11), sync endpoints. Single process; an
  in-process asyncio loop runs the decay/purge/digest **sweep every 15 minutes**
  and a daily SQLite backup. `GET /health` is the unauthenticated readiness
  probe hosts poll; all persistent state lives under `STANLEY_DATA_DIR`
  (default `var/`), created at startup. (`server/stanley/worker.py` is the same logic as a
  standalone process if ever needed. Do **not** run multiple uvicorn workers — each
  would run its own sweeper.)
- **Database:** SQLite with a per-connection PRAGMA listener: **WAL**,
  `busy_timeout=5000`, **`foreign_keys=ON`**. SQLite is the correct DB at this
  scale — do not migrate away. A tiny forward-only migration (`ensure_schema`) adds
  late columns/indexes and bumps legacy circle caps on startup.
- **Blobs:** local disk by default (`BlobStore`), served via short-TTL (15 min)
  **HMAC-signed URLs** — no public URLs ever. An `R2BlobStore` (S3-compatible,
  presigned URLs) is wired behind `BLOB_BACKEND=r2`; switching is config-only.
  Image pipeline strips all EXIF except the capture timestamp (**GPS removal is a
  hard rule**) and bakes in orientation.
- **Auth:** **Sign in with Apple** (RS256 verify against Apple's JWKS, checks
  iss/aud/exp, trusts `sub`). Stanley issues its own HS256 JWT (30-day). A dev-only
  `/auth/dev` exists and returns 404 unless `STANLEY_DEV_AUTH=1`. The server
  refuses to boot without `STANLEY_SECRET_KEY` when dev auth is off.
- **Client:** SwiftUI, iOS 17+, XcodeGen project. JWT in the Keychain. API base URL
  from `STANLEY_API_BASE` (Info.plist) / env, localhost in debug. Sentry captures
  crashes only, and only when `STANLEY_SENTRY_DSN` is set (never in dev builds);
  no user is attached, so crash data stays anonymous — see `PRIVACY_LABEL.md`.

## Implemented and working

Backend and iOS unless noted. All guarded by the test suite where testable.

- **Capture** — one-a-day, 12h gap, EXIF-stripped, claim-slot-then-upload (no
  orphan blobs), caption ≤2000.
- **Today feed** — reverse-chronological, ambient fade rendered client-side from
  `decay_progress` (smoothstep, dark-mode-aware floor).
- **Decay engine** — server-authoritative state machine, idempotent sweep,
  append-only audit log, 7-day tombstone, purge with blob deletion.
- **Held (anchoring)** — press-and-hold to keep (bookmark), owner-only "held by"
  faces, full-saturation archive, tombstones, "Held" tab + per-friend threads.
- **Likes** — double-tap heart, owner-only faces, decays with the photo. The
  heart bottom-right of each photo is *your own* state only (filled if you
  liked it), never a signal to anyone else and never a number.
- **Story-comments** — flat, chronological, part of the artifact. Today shows
  the first one on the card; the rest sit behind "More stories" (never "2
  more" — a tally is still a count) which opens the photo with the thread.
- **Returned + rest-a-memory** — one quiet card atop Today; priority **rescue >
  anniversary > near-forgotten**; Keep / Rest (never again) / Dismiss (not now);
  a Rested view with "let it return"; tombstoned photos never resurface.
- **Circles** — circle-first onboarding (invite code), roster as avatar cluster,
  rotate invite, remove member (creator), leave (with creator succession).
- **Profiles** — display name, username, multi-line bio, avatar (soft-square,
  crop), member profiles (A2-safe: name + words + face only).
- **Community note** — one shared line atop Today, last-writer-wins, clears at end
  of the setter's local day. Not a chat.
- **Shared moments** — photos with the same location label on the same local day by
  2+ people group into one view-only card; each photo keeps its own decay/like/hold.
- **Daily prompt** (client only) — a deterministic-by-date whisper in the capture
  screen; optional, never tracked.
- **Weekly mosaic** — the week's photos as an ephemeral card, creator's local
  Sun/Mon only, view-only.
- **Who-was-there tags** — optional member tags, faces on the photo and into Held,
  block-aware, self opt-out, purged/decayed with the photo. Not a mention.
- **Memory milestones** — private, ≤1/week, dismissable cards in the You tab
  (circle age, held counts, oldest kept, "[name] kept N of yours", first day).
- **Offline capture queue** (client) — no signal means the moment is kept
  locally and sent when the network returns, with a quiet "waiting to upload"
  card where it will land. The day law is claimed **locally** at the shutter,
  so a queued capture closes the camera exactly as a posted one does. A
  server refusal (another device used the slot) strands it honestly: the owner
  can save it to Photos or discard it, never a silent loss.
- **Adaptive density** (client) — `Density(horizontalSizeClass)` in
  `Layout.swift` is the single source for every size that differs between the
  iPhone Duo's two displays: compact is the outer display (and every ordinary
  iPhone, which keeps today's behaviour exactly), regular is the inner one.
  Inner gets larger cards, a side-by-side shared moment, a two-column Held
  magazine, a horizontal profile header, a 600pt readable Settings column and a
  bigger Returned photo, and a readable column on onboarding as well as
  Settings. Only density and arrangement change — no feature is gated to either
  surface. `isLargeCanvas()` exists for enhancements that need real estate,
  never for gating, and is currently unused. Screen metrics come from
  `Density.canvasBounds()` — the window scene's own screen, not `UIScreen.main`,
  which on a two-display foldable names the primary display rather than the one
  the app is on.
- **Seasonal atmosphere** — Auto (season by hemisphere) + Spring/Warm/Fall/Cool/
  Rain; ambient tint + faint wash only; never affects function.
- **Safety/privacy** — bidirectional block (enforced on the feed, direct photo
  access, member profiles, **and the Held/Rested archive** — a blocked person's
  photos are hidden, never deleted; unblocking restores the thread intact),
  report (24h takedown), account deletion
  with cascading blob purge, signed URLs, Face ID app lock (off by default),
  memories export (zip).

## Open items (not yet built / not yet done)

- **Deploy for real.** Stood up on **Fly** (`server/fly.toml`) — a third path
  beyond the two [`server/DEPLOY.md`](server/DEPLOY.md) documents, and the one
  actually in use. Live at `https://server-earnest-stream-9793.fly.dev`, `GET
  /health` returns `ok`, `STANLEY_SECRET_KEY` and `STANLEY_DATA_DIR`
  (`/data/var`, on the `stanley_data` volume) and `APPLE_BUNDLE_ID`
  (`com.ayushkapileshwar.stanley`) all deployed, `STANLEY_DEV_AUTH=0`. Sign in
  with Apple is configured: `POST /auth/apple` rejects a bad token with 401
  rather than answering 503 `apple_auth_unconfigured`.
- **TestFlight build.** Needs a **paid** Apple Developer Program membership: a
  free personal team cannot provision Sign in with Apple (Xcode refuses outright)
  and its profiles expire weekly. Also needs the capability enabled on the App ID
  — `STANLEY_API_BASE` for the release config is set (build 4 points at the Fly
  host; Debug still falls back to localhost).
- **Live SIWA verification.** The Apple flow is tested against a mocked signing key
  (faithful to the verify path); it has not been run end-to-end on a real device.
- **APNs transport.** `Notifier` records every send to `NotificationLog` but the
  transport hook is unset — the last-light notice and digest are logged, not
  actually pushed. Wire APNs before the pilot relies on either.
- **Off-box backups.** Daily local SQLite snapshots exist (keep 7); copying them
  off the box (cron + rclone/scp) is still manual.
- **A cleanup/polish pass** (planned) — tidy any remaining rough edges before the
  pilot.
- **Offline queue across midnight.** The server refuses retroactive uploads, so
  a capture queued at 23:50 and sent at 00:10 lands on the *new* day and spends
  that slot. The local claim was for the old one. Rare, and acceptable for the
  pilot, but it is a real seam.
- **iPhone Duo on real hardware.** Xcode 26.6 ships only an iOS 26.5 runtime —
  no Duo device type, no iOS 27 — so nothing has been seen on the real device.
  Two specific unknowns: (a) whether the inner display actually reports a
  **regular** horizontal size class to an iPhone-family app; the whole layout
  hinges on that, and if it reports compact the inner display silently keeps the
  outer layout. (b) The crease: no SDK fold geometry exists, so `creaseBuffer`
  is a conservative 20pt margin rather than a measurement. It is now actually
  applied (`creaseSafe`) to the interactive rows that can benefit, but a
  full-width or centred control — the onboarding button, the comment field —
  still straddles a vertical crease **by construction**, and no outer inset can
  change that: the crease runs down the middle, so clearing it would mean
  shoving the control entirely to one side. Treated like a photo crossing the
  fold: acceptable.
- **Regular-size-class surfaces are unverified past sign-in.** The app is
  iPhone-family (`TARGETED_DEVICE_FAMILY: "1"`), so an iPad runs it letterboxed
  in compatibility mode and reports *compact* — an iPad is only a valid proxy
  with the family temporarily widened to `"1,2"`. Done that way twice; the
  second time confirmed more than "it doesn't crash": with the readable column
  applied to onboarding, the 600pt cap visibly fires at 744pt, which proves
  iPad mini portrait really does report **regular** and that the whole
  `Density` pipeline resolves to `.room`. What that does *not* prove is (a) —
  the Duo's inner display is different hardware. Past sign-in is still unseen:
  signing in needs a human to type, so the feed, Held, You and Settings
  layouts remain compiled and never looked at.
- **Phase 2 / deferred by design:** on-device Returned selection model; CSAM
  hash-matching + NCMEC path (required before any *open* release, §15); R2 actually
  switched on; Android, video, DMs, multiple circles per user (permanent non-goals
  for the pilot).

## Tests

**175 passing** (`cd server && .venv/bin/python -m pytest`). Strong coverage of the
hard logic: physics (Hypothesis property tests across DST/timezones), full decay
lifecycle at exact boundaries, A1/A2, deletion cascades, block bidirectionality,
likes-no-count, Returned priority/dismiss/rest/tombstone, community note, shared
moments, mosaic windows, tags, milestones, auth hardening + SIWA, FK enforcement,
capture-race/orphan-blob safety, backups. Untested by nature: real-device SIWA,
live APNs, concurrency under real load.

## Key file locations

**Server** (`server/stanley/`)
- Physics / constants: `physics.py`
- ORM models + migration: `models.py`, `db.py` (`ensure_schema`)
- Decay engine: `decay.py`; standalone worker: `worker.py`; app factory: `main.py`
- Config / secrets: `config.py`; clock abstraction: `clock.py`
- Response shaping (payloads, mosaic, note, faces): `serialize.py`
- Returned logic: `returned.py`; milestones: `milestones.py`
- Auth: `auth.py` (JWT), `apple.py` (SIWA verify)
- Storage + signed URLs: `storage.py`; image pipeline: `images.py`; backups: `backup.py`
- Routes (`server/stanley/routes/`): `auth_routes.py`, `circles.py`, `photos.py`,
  `feed.py`, `me.py`, `memories.py`, `safety.py`, `blobs.py`
- Tests: `server/tests/`; deploy notes: `server/DEPLOY.md`; seed/dev tools:
  `server/scripts/seed_demo.py`, `server/scripts/dev_timetravel.py`

**iOS** (`ios/Stanley/`)
- App entry / root / tabs / flash / atmosphere tint: `StanleyApp.swift`
- State + API calls: `AppState.swift`; HTTP client: `APIClient.swift`; models: `Models.swift`
- Screens: `WelcomeView.swift` (sign-in), `TodayFeedView.swift` (feed, photo card,
  moment card, mosaic card, returned card, note), `CaptureView.swift` (prompt,
  who-was-there), `MemoriesView.swift` (Held + Rested), `ProfileView.swift` (You +
  milestones), `SettingsView.swift`, `AboutView.swift`, `CircleGateView.swift`
- Components: `UIComponents.swift` (avatars, face cluster, faces sheet, share),
  `AvatarPicker.swift`, `Atmosphere.swift`, `Prompts.swift`, `AppLock.swift`,
  `Keychain.swift`
- Project gen: `ios/project.yml` (run `xcodegen generate` after adding files)

## Working with this repo

- Run the server (dev): `cd server && STANLEY_DEV_AUTH=1 STANLEY_SECRET_KEY=dev .venv/bin/python -m uvicorn --factory stanley.main:create_app`
- `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (xcode-select points at CommandLineTools on this machine).
- After changing the physics constants, the decay timeline, or any locked rule,
  re-read this file's "Locked design rules" — those changes are product decisions.
