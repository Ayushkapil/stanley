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
- **The like is on Stanley's physics, not Instagram's.** Double-tap (or a tap on
  the heart, since build 12), a cosmetic heart, owner-only faces, decays *with the photo* (gone forever when it leaves
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
  late columns/indexes and bumps legacy circle caps on startup. Every route
  takes its session as `Depends(get_db, scope="function")`, so the commit
  happens before the response is sent. Under FastAPI's default scope it ran
  after the response and after any background task. A new photo then stayed
  uncommitted while its full-size original encoded, so the app's refresh
  right after posting didn't see it. A test fails if any route goes back to
  the default.
- **Blobs:** local disk by default (`BlobStore`), served via short-TTL (15 min)
  **HMAC-signed URLs** — no public URLs ever. An `R2BlobStore` (S3-compatible,
  presigned URLs) is wired behind `BLOB_BACKEND=r2`; switching is config-only.
  Image pipeline strips all EXIF except the capture timestamp (**GPS removal is a
  hard rule**) and bakes in orientation.
- **Auth:** **Sign in with Apple** (RS256 verify against Apple's JWKS, checks
  iss/aud/exp, trusts `sub`). Stanley issues its own HS256 JWT (30-day). A dev-only
  `/auth/dev` exists and returns 404 unless `STANLEY_DEV_AUTH=1`. The server
  refuses to boot without `STANLEY_SECRET_KEY` when dev auth is off.
- **Client:** SwiftUI, iOS 17+, XcodeGen project. JWT in the Keychain.
  `AppState` and `OfflineQueue` are `@MainActor`, so every observed
  property is written on the main thread, where SwiftUI reads it. In Swift
  5 mode their `async` methods used to run on a background executor, which
  was a data race. Network calls and JSON decoding still run off the main
  thread inside `APIClient`. `APIClient` is `Sendable`: the base URL is a
  `let` and the token sits behind an `OSAllocatedUnfairLock`, because it is
  set on the main actor and read by every request. API base URL
  from `STANLEY_API_BASE` (Info.plist) / env, localhost in debug. Sentry captures
  crashes only, and only when `STANLEY_SENTRY_DSN` is set (never in dev builds);
  no user is attached, so crash data stays anonymous — see `PRIVACY_LABEL.md`.

## Implemented and working

Backend and iOS unless noted. All guarded by the test suite where testable.

- **Capture** — one-a-day, 12h gap, EXIF-stripped, claim-slot-then-upload (no
  orphan blobs), caption ≤2000. The shot opens a preview with the filter pills
  under it, then Post; nothing uploads until Post.
- **Capture filters** — four looks, plus None (the default), as one row of
  `ChoicePill`s under the preview: **Mono** (a well-printed black and white),
  **Grain** (warm film: less saturation, lifted blacks, amber in the shadows,
  fine grain), **Dusk** (golden hour, deeper shadows, a soft vignette), and
  **Clean** (a held-back gray-world white balance, Apple's auto-enhance, a
  touch of clarity). One tap, no sliders, no intensity. `PhotoFilters.swift` is
  plain CoreImage with no UIKit, so a macOS harness can run it against sample
  photos. Every distance (grain, vignette, clarity) comes from the photo's own
  size, and Clean measures a 1080 copy, so the 1080 preview (the size Today
  shows) matches the full-size upload once the server scales it down. Grain,
  the warm cast and the vignette work on gamma-encoded values, because in
  CoreImage's linear light they land far too hard in the shadows. Two traps
  are documented in the code. `CIRandomGenerator`'s alpha is random, so the
  noise is made opaque before any filter reads it; otherwise it comes out as
  white specks. And None posts the camera's own JPEG untouched. The look is
  baked into the pixels on Post, so it can't change after posting. The server keeps only
  the name: `photos.filter` (`mono`/`grain`/`dusk`/`clean` or NULL), sent as
  the `filter` form field. An unknown name is dropped rather than refused,
  because a label must never cost someone their day. The name is in the photo
  payload and the export, and it's purged with the caption. Nothing renders it
  yet. On the simulator, a `SampleCapture.jpg` or `.heic` in the app's
  Documents folder stands in for the camera, so the filters can be tried on a
  real photo. The simulators' own `DCIM/100APPLE/IMG_0006.HEIC` works.
- **Today feed** — reverse-chronological, ambient fade rendered client-side from
  `decay_progress` (smoothstep, dark-mode-aware floor).
- **Decay engine** — server-authoritative state machine, idempotent sweep,
  append-only audit log, 7-day tombstone, purge with blob deletion.
- **Held (anchoring)** — press-and-hold to keep (bookmark), owner-only "held by"
  faces, full-saturation archive, tombstones, "Held" tab + per-friend threads.
- **Likes** — double-tap heart, owner-only faces, decays with the photo. The
  heart bottom-right of each photo is *your own* state only (filled if you
  liked it), never a signal to anyone else and never a number. Since build 12
  it is also a button, because real users reached for it, and a tap does what
  a double-tap does.
- **Gesture icon size** — the heart and the bookmark share one size,
  `GestureIcon`: a 22pt glyph (about 24pt tall, roughly 40% up from build 11)
  inside a 44pt target, through `@ScaledMetric` so it follows Dynamic Type.
  It applies on Today cards, shared-moment tiles, the story sheet, and
  Returned's "Keep this". The heart's whole 44pt square takes a tap. The
  caption-row bookmark gets its 44pt target from a clear background centered
  on the glyph, so the row keeps its height.
- **Story-comments** — flat, chronological, part of the artifact. Today shows
  the first one on the card; the rest sit behind "More stories" (never "2
  more" — a tally is still a count) which opens the photo with the thread.
- **Returned + rest-a-memory** — one quiet card atop Today; priority **rescue >
  anniversary > near-forgotten**; Keep / Rest (never again) / Dismiss (not now);
  a Rested view with "let it return"; tombstoned photos never resurface.
- **Circles** — circle-first onboarding (invite code), roster as avatar cluster,
  rotate invite, remove member (creator), leave (with creator succession).
- **Profiles** — display name, username, multi-line bio, avatar (soft-square,
  crop), member profiles (A2-safe: name + words + face only). A **name gate**
  (`NameGateView`) sits between sign-in and the circle gate whenever Apple gave
  us no name — it did not, for anyone who declined to share it — because the
  alternative was a new member labelled with the placeholder for a deleted
  account. Name required, username optional, shown once. A nameless member
  serializes as `UNNAMED` ("New member"); `DEPARTED` ("departed") now means
  only a genuinely deleted account.
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
  Rain, picked from a row of named pills in Settings (the chosen one filled
  with its accent; in dark mode the rest carry a hairline). Each is a `Palette`
  (`Atmosphere.swift`): an `accent` (tab bar, buttons, bookmarks, edges), an
  `ink` for labels on an accent fill, an opaque per-mode `floor` (the root and
  every screen paint the same one, so overlaps are invisible), a `card` under
  every Today card, and a `row` behind grouped-list rows (`.atmosphereRows()`,
  on every Form and List). Light mode mixes the tone into the system white.
  Dark mode is **chosen outright** per atmosphere — black mixed toward a pale
  tone came out olive and gray-brown — so each gets a saturated accent, a deep
  floor of its own hue and a card one step up: emerald, candlelight, ember,
  ice on navy, slate. Ambient only; never affects function.
- **Errors in Stanley's voice** — no status code, server `detail` string or
  system description ever reaches the screen. `APIError` maps every server
  code and bare status to a sentence; `AppState.words(for:)` covers the rest
  (unreachable, undecodable, Apple sign-in). A failed upload says the day is
  still open, which is true: the server rolls the whole request back. No
  signal never fails at all — it queues.
- **The World Today** — twelve national headlines in a **World** tab of
  their own (globe), the fourth of five: Today, Held, You, World, Settings. A
  morning paper on the counter, not a feed. Today is the circle's photos and
  nothing else. The tab is titled "The World Today", with "12 stories,
  refreshed every half hour" above the list. The list stops at the last story.
  The server fetches NewsAPI top-headlines
  (`country=us`) every 30 minutes on its own background loop. It keeps the
  last good set in a one-row `news_cache` table. Clients only ever read
  `GET /news/today` (JWT only, no circle needed), so nobody but the server
  talks to NewsAPI. The cached set is normalized once: text only (no images),
  the outlet stripped from the headline, summaries trimmed to 60 words,
  http(s) links only (anything else crashes the Safari sheet), and
  `[Removed]` stubs dropped before the twelve are counted. The twelve are
  NewsAPI's own pick, identical for everyone and shown newest first. A
  failed fetch keeps the last good set. A set older than 6h is not served,
  rather than showing yesterday's world. With no `NEWS_API_KEY` the endpoint
  returns `[]`, and the tab says "No stories right now." The tab is always
  there, even with no key. The subtitle uses the real count, never a
  hard-coded 12. That number is the size of the edition, not a tally of
  anyone's activity. A story opens in
  `SFSafariViewController`, which UIKit presents over whatever is on top
  (`StoryReader`). When Safari was a SwiftUI sheet, its own Close forced a
  second dismissal, and that closed whatever was beneath it too. There
  are no likes, saves, shares, comments or notifications. News never appears in
  Today, Held, Returned, the export or any memory surface. It loads when the
  World tab appears and on pull, never on a timer. Today's pull runs its pass
  as a separate `Task`, because SwiftUI cancels a `.refreshable` task the
  moment the state it refreshes changes.
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
- **iPhone Duo — simulator yes, hardware no.** The machine now has **Xcode
  27.1** with an **iOS 27.1** runtime and a real **iPhone Duo** device type
  (`iPhone19,4`), so the app has been run and walked on the Duo *simulator*
  (still nothing on physical hardware). The **outer (cover) display** —
  466×678pt, reported **compact**, the ordinary-iPhone path — is verified end to
  end: Today / Held / You / Settings in dark, Today in light, a real 9-person
  circle, no black bars, and iOS 27 draws the tab bar as a vertical floating
  dock on the trailing edge that the layout clears. Every screen before sign-in
  too (build 13): the launch spinner, onboarding, Welcome, the name and
  circle gates, and the Face ID lock. Welcome and the spinner used to leave a
  black band in the dock strip. The root's floor only reached as far as its
  child's frame, so `RootView` now fills the screen before painting it. Two unknowns remain. (a) The
  **inner (unfolded) panel** is still unseen: this simulator exposes no
  fold-posture control to a headless `simctl` session (powering the cover off
  does not migrate the scene, and forcing it wedges SpringBoard), and the
  Simulator GUI window binds to a different device, so the scene stays on the
  cover. Whether the 669×951pt inner panel reports **regular** to an
  iPhone-family app is therefore still not directly observed — the iPad proxy
  (below) is the nearest evidence. (b) The crease: no SDK fold geometry exists,
  so `creaseBuffer` is a conservative 20pt margin rather than a measurement. It
  is applied (`creaseSafe`) to the interactive rows that can benefit, but a
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
  the Duo's inner display is different hardware. The regular feed / Held / You
  with real content past sign-in was **not** captured on the iPad this round:
  synthetic taps were not delivered reliably to the headless iPad session
  (drags registered, discrete taps did not — and this hit both a
  `readableWidth` control and a plain one, so it is an input-tooling artifact,
  not a hit-testing regression). The same screens *are* seen with real content
  on the Duo's compact cover; the regular variants differ only by `Density`
  values, which do engage.
- **The World Today, for real.** `NEWS_API_KEY` is **not set on Fly**, so a
  build pointed at Fly shows a World tab that only ever says "No stories
  right now." Set the key, or hide the tab, before testers see it. It has been tested locally only, with sample
  headlines in the cache. NewsAPI's free Developer plan is licensed for
  development only and delays articles 24h, so testers need the paid Business
  plan or another source. Headlines are national (`COUNTRY = "us"`). Regional
  news is a `TODO(location)` in `server/stanley/news.py`, and the app requests
  no location permission.
- **Phase 2 / deferred by design:** on-device Returned selection model; CSAM
  hash-matching + NCMEC path (required before any *open* release, §15); R2 actually
  switched on; Android, video, DMs, multiple circles per user (permanent non-goals
  for the pilot).

## Tests

**214 passing** (`cd server && .venv/bin/python -m pytest`). Strong coverage of the
hard logic: physics (Hypothesis property tests across DST/timezones), full decay
lifecycle at exact boundaries, A1/A2, deletion cascades, block bidirectionality,
likes-no-count, Returned priority/dismiss/rest/tombstone, community note, shared
moments, mosaic windows, tags, milestones, auth hardening + SIWA, FK enforcement,
capture-race/orphan-blob safety, backups, nameless-vs-departed naming, the
World Today cache (fetch + store, last-good-set on failure, stale and no-key
silence, normalization, key-in-header), capture filters (the name kept, an
unknown one dropped without refusing the photo, purged on delete, exported),
and commit-before-response (capture commits before the background original
store; every route's session is function-scoped).
The filter looks themselves are checked in a macOS harness, not in pytest.
Untested by nature: real-device SIWA,
live APNs, concurrency under real load.

## Key file locations

**Server** (`server/stanley/`)
- Physics / constants: `physics.py`
- ORM models + migration: `models.py`, `db.py` (`ensure_schema`)
- Decay engine: `decay.py`; standalone worker: `worker.py`; app factory: `main.py`
- Config / secrets: `config.py`; clock abstraction: `clock.py`
- Response shaping (payloads, mosaic, note, faces): `serialize.py`
- Returned logic: `returned.py`; milestones: `milestones.py`; The World Today: `news.py`
- Auth: `auth.py` (JWT), `apple.py` (SIWA verify)
- Storage + signed URLs: `storage.py`; image pipeline: `images.py`; backups: `backup.py`
- Routes (`server/stanley/routes/`): `auth_routes.py`, `circles.py`, `photos.py`,
  `feed.py`, `me.py`, `memories.py`, `safety.py`, `blobs.py`, `news.py`
- Tests: `server/tests/`; deploy notes: `server/DEPLOY.md`; seed/dev tools:
  `server/scripts/seed_demo.py`, `server/scripts/dev_timetravel.py`

**iOS** (`ios/Stanley/`)
- App entry / root / tabs / flash / atmosphere tint: `StanleyApp.swift`
- State + API calls: `AppState.swift`; HTTP client: `APIClient.swift`; models: `Models.swift`
- Screens: `WelcomeView.swift` (sign-in), `NameGateView.swift` (name/username,
  shown once when Apple gave no name), `TodayFeedView.swift` (feed, photo card,
  moment card, mosaic card, returned card, note), `CaptureView.swift` (prompt,
  who-was-there, preview + filter pills), `PhotoFilters.swift` (the four
  looks, `FilterRenderer`), `WorldTodayView.swift` (the World tab, Safari),
  `MemoriesView.swift` (Held + Rested), `ProfileView.swift` (You +
  milestones), `SettingsView.swift`, `AboutView.swift`, `CircleGateView.swift`
- Components: `UIComponents.swift` (avatars, face cluster, faces sheet, share),
  `AvatarPicker.swift`, `Atmosphere.swift` (also `ChoicePill`), `Prompts.swift`, `AppLock.swift`,
  `Keychain.swift`
- Project gen: `ios/project.yml` (run `xcodegen generate` after adding files)

## Working with this repo

- Run the server (dev): `cd server && STANLEY_DEV_AUTH=1 STANLEY_SECRET_KEY=dev .venv/bin/python -m uvicorn --factory stanley.main:create_app`
- `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (xcode-select points at CommandLineTools on this machine).
- After changing the physics constants, the decay timeline, or any locked rule,
  re-read this file's "Locked design rules" — those changes are product decisions.
