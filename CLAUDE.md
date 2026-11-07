# Stanley — One Day, One Photo

## What it is

Stanley is a small-circle photo app built on two structural laws: each person may
post **exactly one photo per day** in each circle they're in, and every photo **decays out of existence
within six days unless someone deliberately keeps (anchors) it**. The only social
gestures are *holding* (a private act of keeping, never counted),
*story-comments* (co-remembering) and, since build 26, the circle's *question
of the week* (answered privately, read together). The product's identity lives as much in what it
refuses — counts, ranking, algorithmic ordering, open audiences, re-engagement
notifications — as in what it does. The pilot target is one real circle (a dorm
floor); the circle ceiling is a soft 100. Codename: Stanley.

## Locked design rules (do not violate without an explicit product decision)

These are invariants, not preferences. Most are enforced structurally in code and
guarded by tests; treat a change to any of them as a spec change.

- **One photo per person per circle per local calendar day**, plus a 12-hour
  minimum gap. Enforced server-side by `UNIQUE(owner_id, circle_id,
  local_date)` + an app check; a race returns 409, never a double post. Per
  circle since build 17 (a product decision, with multiple circles; it was
  `UNIQUE(owner_id, local_date)`): a photo goes to the circle on screen, and
  that circle's day, gap and redo are its own. A photo in one circle never
  spends or delays another's. The photo is taken with the in-app camera
  or, since build 16 (a product decision from pilot feedback), chosen from
  the library with the system picker, of any age; either way it is the
  day's one photo and spends the slot the same. Since build 17 every photo is
  cropped to 3:4 before it posts (`PhotoShape`).
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
  **One exception, a product decision (build 19):** how many moments *you*
  have shared, shown only to you on your own You tab ("You've shared 12
  moments. Only you see this."). It's only ever on `/me`, never on a member
  profile, a photo or anything someone else sees, so it can't be compared or
  become a score. Every other count is still forbidden.
- **The like is on Stanley's physics, not Instagram's.** Double-tap (or a tap on
  the heart, since build 12), a cosmetic heart, owner-only faces, decays *with the photo* (gone forever when it leaves
  Today). Never archived, never recountable.
- **No algorithmic feed.** Today is reverse-chronological and nothing else. No
  ranking, no engagement signals, no recommendation.
- **Notifications are almost nothing.** Two exist, and both are **off until
  the person turns them on** in Settings → Quiet: the owner's single
  LAST_LIGHT notice for their own photo, and at most one evening digest a day
  ("Something new from your circle today.", when someone else in one of
  their circles posted). No notification may carry a count, deadline,
  countdown, name or image. No round has added a new notification. Build 18
  made them real pushes (APNs, `apns.py`) and, because of that, made the
  digest opt-in (it had gone to everyone back when it was only logged). A
  brief asking for "3 new moments today" was kept to words: the count would
  break this rule.
- **The subject wins on deletion.** Owner delete purges the image everywhere;
  anchorers keep an honest tombstone ("a memory was here") plus their own comment
  text only.
- **What a person writes down for themselves stays theirs** (build 26). A
  journal entry on your own photo and a weekly reflection are read by no one
  else, anywhere: the feed never carries an entry (only an owner-only
  `has_journal` flag, None for anyone else), and every route about one
  answers 404 to anyone but its writer. An entry lives as long as the photo
  does for its owner (in Today, then only while the owner holds it); a
  reflection never fades. Answers to the circle's question are sealed until
  that week's Saturday, 00:00 UTC (403 before), then open to the whole
  circle at once, whether they answered or not; answering closes when they
  open; a member reads from the week they joined. None of it counts anyone
  ("how many answered" doesn't exist), none of it notifies, and the word
  filter covers all three.
- **The board's notes are everyone's own and the day's alone** (build 27).
  One note per person per circle per day, changed or taken down only by its
  author, gone at the end of their day (deleted, not archived). No replies,
  no reactions, no notification and no count of how many there are.
- **Up to five circles per person** (build 17, a product decision from pilot
  feedback; it had been one, a permanent non-goal), each mutual by
  construction, each with a **soft cap 100** — a guardrail against an
  audience, never a target. Nothing nudges toward either limit. Today shows
  one circle at a time, the one on screen; nothing is mixed or ranked across
  them. `CIRCLES_PER_PERSON` in `physics.py`.

The authoritative source for the physics constants is
[`server/stanley/physics.py`](server/stanley/physics.py) — pure functions, no I/O.

## Architecture

- **Backend:** FastAPI monolith (Python 3.11), sync endpoints. Single process; an
  in-process asyncio loop runs the decay/purge/digest **sweep every 15 minutes**
  and a daily SQLite backup. `GET /health` is the unauthenticated readiness
  probe hosts poll; it reads the database and answers 503 when it can't
  (the production audit). All persistent state lives under `STANLEY_DATA_DIR`
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
  hard rule**) and bakes in orientation. On the phone every photo and face is
  a `SignedImage` (build 21; it was `AsyncImage`). A page left open past 15
  minutes held links that had run out, so a photo first scrolled to then was
  refused (403) and stayed gray for good (seen on the simulator: seven 403s
  after 16 minutes). Now a 403 asks for fresh links
  (`AppState.linksExpired`: Today, the circle, Held and the profile fetched
  again, at most once every 30 seconds, and `reloads` bumped for views that
  keep their own copy), and the photo loads from the new one. Photos once
  loaded are kept in memory by blob path, not link (`PhotoMemory`), so
  renewed links don't send every photo back to gray; faces aren't, since an
  avatar's path stays the same when it changes.
- **Auth:** **Sign in with Apple** (RS256 verify against Apple's JWKS, checks
  iss/aud/exp, trusts `sub`). Stanley issues its own HS256 JWT (30-day). A dev-only
  `/auth/dev` exists and returns 404 unless `STANLEY_DEV_AUTH=1`. The server
  refuses to boot without `STANLEY_SECRET_KEY` when dev auth is off.
- **The circle on screen** (build 17): the app names it in an
  `X-Stanley-Circle` header on every request (`APIClient.circleId`, behind a
  lock like the token; a header, like the town for the news, so it stays out
  of access logs). `deps.require_membership` reads it; without one, a
  request is about the circle joined first, which is all a build before 17
  ever sees. A circle the person isn't in is `not_in_circle`, never a quiet
  switch to another, so a photo can't land in the wrong circle; the app then
  falls back to a circle they're in. Per-photo gestures (like, hold, story,
  report) reach a photo in any of the person's circles, since Held and
  Returned aren't about the circle on screen; profiles and blocks follow any
  shared circle. A queued capture carries the circle it was taken for.
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
  Since the production audit a crash carries a short trail of fixed words
  (`Trail.swift`: "opened Held", "posted a photo"), and Sentry's automatic
  trail (taps, screens, request URLs) and failed-request capture are off.
- **The production audit** (November 3, 2026; `PRODUCTION_CHECKLIST.md` has
  every item, its state, and the steps left by hand). On the server: rate
  limits in memory (`ratelimit.py`: sign-in 10/minute per IP, from
  `Fly-Client-IP` only on Fly; per person 10 posts, 10 avatars, 30 stories,
  20 reports an hour; 429 `slow_down`; env-tunable; off in the test fixture);
  every free-text field cleaned (`text.py`: control and bidi-override
  characters out, NFC); a slur filter on what a circle reads (`wordfilter.py`,
  salted hashes in `blocklist.txt`, whole words after folding the usual
  dodges; 400 `words_not_allowed`; never on reports or hold notes); uploads
  judged by their first bytes (JPEG, PNG, HEIF) and refused over 50
  megapixels before decoding; security headers on every response (HSTS, CSP,
  nosniff, DENY); `/docs` and `/openapi.json` only with dev sign-in; a JSON
  500 (`server_error`) for anything unexpected, never a traceback; the
  app's own log lines reaching `fly logs`, with `event=` lines for sign-ups,
  posts, circles, deletions, reports, blocks and refusals (opaque ids only);
  thirteen more indexes; like, hold, block, rest, push token and milestone
  writes as one `INSERT … ON CONFLICT` (a double tap was a 500); the sweep
  committing before the digest (one bad time zone, which `/feed/returned`
  used to store unchecked, would have stopped all decay); backups pruned by
  age as well as count; `PRAGMA optimize` daily and `VACUUM` on Sundays; a
  daily `event=disk_low` warning; the pool sized to the thread pool.
  Operator tools: `python -m stanley.moderation` (list, show, take a photo,
  story or (build 26) an answer down, with evidence preserved for a photo,
  resolve, end an account),
  `scripts/integrity_check.py` (read-only), `scripts/pull_backup.sh` (a copy
  off Fly, launchd plist beside it). Screenshots: `scripts/seed_screenshots.py`
  and `scripts/scenes.py` (photos drawn in code). Fixed on the way: Held's
  friend faces never loaded (`/me/anchored` left the avatar link unsigned),
  and build 24's root ink outranked `role: .destructive`, turning Leave
  Circle, Reset Code, Delete Account and Block black (`destructiveInk()`).
  The Privacy Policy changed (the crash trail) and has its own date,
  November 3, 2026 (`PRIVACY_EFFECTIVE`, `Legal.privacyEffective`). Build 26
  changed both documents (the journal: what's kept, who reads it, how long,
  the export, and Content in the Terms), so the Terms are November 3 too. Build 27's board changed the policy again
  (notes deleted at the end of their day; a report keeps a reported note's
  words), so it's November 4.

## Implemented and working

Backend and iOS unless noted. All guarded by the test suite where testable.

- **Capture** — one-a-day, 12h gap, EXIF-stripped, claim-slot-then-upload (no
  orphan blobs), caption ≤2000. The shot opens a preview with the filter pills
  under it, then Post; nothing uploads until Post. Today's photo is taken from
  a **"+" at the end of Today's masthead** (`NewPhotoButton`, build 29): a
  thin plus, light weight, 22pt (scaling with Dynamic Type) in a 44pt
  target, in the atmosphere's accent, with nothing around it, on the line
  with the circle's name where a navigation bar's button would be. It's
  always there: with today's photo already up, the sheet opens on it and
  says "Today's moment is out there. Come back tomorrow."; it's dimmed only
  while a queued capture holds the day. It replaced the **floating camera
  button** (`CaptureButton`), which sat over the photos: a solid disc in
  builds 16 to 27 that pilot users found heavy, an outline ring in build
  28, and before build 16 a gray disc they called outdated. Only the empty
  Today still draws that ring, at 44pt inside its sheet (build 31), as the
  page's one thing to do. With
  the floating camera gone, so went its Duo placement (`HomeView` drew it in
  the side dock's column) and its hiding while the keyboard was up;
  `SideDockReader` stays, so the tab bar's floor (`SolidTabBar`) knows
  when the bar is a side dock. The
  sheet (build 15) is laid out like composing
  a memory: before the photo, an empty print holding the day's
  prompt (tapping it opens the camera) and the rule in a line beneath;
  after it, the photo as a print (build 21; it had 20pt corners). Both are `PhotoShape` (3:4, the
  camera's own 4:3 held upright; build 17), as wide as the sheet allows and
  no taller than 55% of the screen, so the place and the pills show on the
  Duo's cover. Since build 31 it gives up height so nothing starts under
  the footer, before the shutter or after (the QA audit found "In your
  words" under Post): the photo is the sheet's height between the bar and
  the footer less what's beneath it, measured (`fittedPhotoHeight`, never
  under 260pt; the height is held while the caption is being typed). **The frame is the crop** (build 17): a photo of another
  shape (most library photos) fills it and drags to choose what's in it,
  and any photo pinches in closer (`Framing.swift`, the same arithmetic as
  the avatar crop). "Drag to frame it" shows until it's moved, and thirds
  while it moves. On Post the look goes on at full size and then exactly
  the frame is cut from it (`FilterRenderer.jpeg(_:_:crop:)`), so what's
  posted is what was framed; a camera shot left as it came posts the
  camera's own JPEG untouched. With more than one circle the sheet says whose
  day it is ("for Climbing Club"). **Where it was** sits right under the photo (build 16; on the card
  below the pills it was out of sight on the Duo's cover), then the filter
  pills, then the caption line, then who-was-there. The foot of the sheet
  is **Take photo**, a full-width accent button (`WideButton`, 52pt, the
  palette's ink, shared with setup), with **Choose from library** under it;
  after the photo it's **Post**, which holds a spinner while posting. A
  library photo (`LibraryPhoto.swift`) goes through the same preview,
  filters, place, caption and post. It's read with ImageIO's thumbnail path
  (upright, at most 4096px, never decoded at full size) and re-encoded from
  its pixels, so its metadata, GPS included, never leaves the phone. The
  picker is `PhotosPicker`, out of process, and needs no Photos permission.
- **Places** (client only, build 14; location since build 15) — the capture
  screen's place line, right under the photo, opens a picker (`Places.swift`) with a search bar,
  **Here** (where the phone is, with location allowed), **Favorites**
  (starred, at most 10), **Recent** (the last five used, favorites
  excluded), and search over the person's *own* places only. Anything new
  can be used exactly as typed. `PlaceBook` keeps them in UserDefaults keyed
  by user id, so a shared phone doesn't mix people, and an expired sign-in
  keeps them. Deleting the account erases them. A place is recorded when the
  photo posts or queues, not when it's picked. **After the shutter**, with
  location allowed (asked right then, the first time), the place fills in
  from where the phone is (`Whereabouts`): the landmark or campus Apple's
  geocoder names ("Indiana University"), else the neighborhood, else the
  town; only the town under approximate location. A **library photo** is
  named from the location in its own metadata instead (`Whereabouts.place
  (at:)`, no permission needed), never from where the phone is, since it
  could be from anywhere. It never overwrites a place already chosen. A
  filled place shows a pencil, and a location glyph while it's the
  suggestion; it stays the person's to edit or clear. Coordinates never reach Stanley's
  server: only the label on the photo does, as before, and GPS is still
  stripped from the image. No maps or places search.
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
- **Today in pages** (the production audit) — `GET /feed/today?limit=20`
  answers twenty entries and a `next_cursor` (base64 of the last entry's time
  and id); the app asks for the next page when a spinner at the end comes
  into view (`AppState.loadMoreToday`), and a refresh asks for everything
  already showing in one request (`limit` = what's loaded, at most 200), so a
  like deep in the page never folds Today back to twenty. Moments are
  grouped before the page is cut. No `limit` is everything, as builds before
  this expect; the note and mosaic come with the first page only. Checked on
  the simulator with 33 entries.
- **Silent sign-in refresh** (the production audit) — `POST /auth/refresh`
  trades a working token for a fresh thirty days; the app asks at most once
  a day, at launch and on coming to the front (`refreshSignInIfDue`).
- **Today feed** — reverse-chronological, ambient fade rendered client-side from
  `decay_progress` (smoothstep, dark-mode-aware floor). Since build 17 it's a
  **shared journal, not a card feed** (pilot users said it was "just
  Instagram"). Since build 20 it opens like the morning paper, with no
  navigation bar: a **masthead** (`TodayMasthead`), the circle's name written
  large in a hand (`CircleSwitcher`, still the menu of circles, in ink not
  the accent), the paper's double rule, the date in small capitals and a
  hairline. The circle's board of sticky notes is on the first page. Each day
  has a mark written in a hand, "Today", "Yesterday", then the weekday, with
  the date beside it and the line ruled off (`JournalDay`, `DayMark`). Each
  photo is a **print laid on paper**: `PhotoShape` 3:4, filled and clipped,
  never letterboxed, inside a border of photo paper (`asPrint`, warm white;
  in dark mode a lamplit gray), cut nearly square, with a soft shadow. It
  lies up to 0.9° off square, decided by its id (`PrintTilt`). The bookmark
  and the heart sit in its bottom-right corner. Beneath it, in ink on the
  page: the poster's first name and the time in Noteworthy (`PrintByline`,
  `Font.hand`; a tap opens their profile; it was on a dark capsule on the
  photo until build 20), then caption, place, who was there, the stories and
  "What do you remember?", with no chrome. A day's entries are divided by a
  thin rule, the paper's, not by a gap. A shared moment is a run of signed
  prints under its place, written by hand. The mosaic and Returned are
  sheets of their own tucked into the journal (`paperInsert`, grained paper
  edged in a hairline), with their photos as prints. **The tab bar sits on
  the atmosphere's floor** (build 31, `SolidTabBar` in `StanleyApp.swift`):
  iOS 26's glass took on the light of the photo beneath it and the selected
  tab's ink vanished (the warm charcoal over a dark photo in light mode, the
  warm white over a light one in dark), and the glass ignores
  `toolbarBackground`. So each tab lays a band of its floor at 95% under the
  bar, the height of the page's bottom inset, fading into the page over its
  top 16pt; before iOS 26 the bar's own background takes the same floor.
  Not on the Duo's side dock, which the page clears. The bar no longer folds
  to the current tab as Today scrolls (it did from build 17,
  `tabBarMinimizeBehavior(.onScrollDown)`): folded, it was a small pill on
  an empty band. Checked on the 17 Pro over light and dark photos in both
  modes, and on the Duo's cover. **Each entry arrives as it's
  scrolled to** (build 24, `Entrance`): it fades in and settles up by 20pt
  over 0.3s, once per entry (a refresh keeps the entries it had, so they
  stay put; one scrolled far off and back arrives again), only a fade
  under Reduce Motion. Pilot users said the app felt light; this is weight
  without a feature.
- **Decay engine** — server-authoritative state machine, idempotent sweep,
  append-only audit log, 7-day tombstone, purge with blob deletion.
- **Held (anchoring)** — press-and-hold to keep (bookmark), owner-only "held by"
  faces, full-saturation archive, tombstones, "Held" tab + per-friend threads.
  Held gathers every circle a person is in; each memory carries its
  `circle_name`, shown as a small tag (`CircleTag`) once there's more than
  one circle to tell apart. Since build 20 the Held tab is **a photo album**:
  a masthead ("Held", "The one place nothing fades", Rested as a moon at its
  end), a section head per friend ("Kept from", their name in a hand, their
  face; your own photos are "Kept from Me" since the polish pass), and each memory a print on its photo paper exactly as in Today
  (`asPrint`: barely rounded, a soft shadow), staggered left and right and
  leaning with its side, left, right, left, by a Today print's slight
  amount, with its caption written beneath in a hand and the place and
  "held" date in small capitals. A tombstone is a blank print with "A memory
  was here" written on it. Builds 20 to 23 slipped each print into four
  black photo corners (`PhotoCorners`, since removed); pilot users called
  them cringe. The phone keeps swipe to rest; the Duo's inner display, two
  prints to a line, keeps the long press.
- **Likes** — double-tap heart, owner-only faces, decays with the photo. The
  heart bottom-right of each photo (the bookmark beside it, on the photo too,
  since build 17) is *your own* state only (filled if you
  liked it), never a signal to anyone else and never a number. Since build 12
  it is also a button, because real users reached for it, and a tap does what
  a double-tap does. A double-tap that likes plays a white heart in the
  middle of the photo, 0.8 → 1.2 → 1 in half a second and then faded out,
  like Instagram's (build 18; Reduce Motion drops the scale). It used to wash
  the whole photo pink, which pilot users found strange; the photo is never
  tinted now. A tap on the corner heart only fills it, and a double-tap on a
  photo already liked unlikes it without the pop.
- **Haptics** (build 21, `Haptics.swift`; refined in the polish pass, build
  28) — only the deliberate social gestures, never opening stories,
  scrolling, swiping the board, tab switches or navigation, each a quiet
  confirmation: a **soft** impact when the double-tap heart appears (not the
  corner heart's tap, nor an unlike); a medium one when a photo is held,
  however it's held (the long-press menu's Hold, the bookmark, Returned's
  Keep this; letting go is quiet); the system's success when today's photo
  is up (not when it's only queued); a light impact as a pull to refresh
  lets go (Today, Held, You, World), once; a light tap when your note is on
  the board, and one when your answer to the circle's question is in (both
  after the server says so, so a note or an answer that didn't save gets
  none). The long-press menu's light tap is the system's own, played as a
  context menu opens, so Stanley adds none. All five checked in the
  simulator's log in build 28. With System Haptics off, iOS
  keeps them silent. Each logs `haptic: …` at debug level (subsystem
  `com.ayushkapileshwar.stanley`, category `haptics`), which is how they're
  checked on a simulator, which has no haptic engine. **Long press is the
  menu:** on a print the context menu takes the press before the
  press-and-hold gesture can, so holding by long press means long press →
  Hold (checked: no anchor request without it). **The shutter** (`Shutter`,
  system sound 1108, silenced by the ring switch): the system camera plays
  its own at the moment of capture, so Stanley adds none to a camera photo
  (a second click after Use Photo would be seconds late); only the
  simulator's stand-in frame, which Stanley takes itself, plays it. A
  library photo is chosen, not taken: no sound.
- **A tap on the tab you're on** (build 22, `TabTaps.swift`) — Today, Held,
  You and World scroll back to their top, animated; already at the top, the
  tap runs the pull's own refresh (and feels like one: the same light
  impact). `HomeView`'s selection binding counts a re-tap into
  `AppState.tabTaps`, and each page watches its count (`onTabTap`, on the
  scroll view itself, with a `ScrollViewReader` scrolling to the masthead's
  id). Whether a page is at its top is read with `onScrollGeometryChange`,
  iOS 18 and up; on iOS 17 it's never known, so a tap only ever scrolls.
  Settings has nowhere to go. There's no way to show the pull's spinner
  from code, so the refresh is quiet. Checked on the Duo: Today scrolled
  back to its masthead on a tap with no haptic, and at the top a tap fetched
  the feed with the refresh haptic; Held the same.
- **Gesture icon size** — the heart and the bookmark share one size,
  `GestureIcon`: a 22pt glyph (about 24pt tall, roughly 40% up from build 11)
  inside a 44pt target, through `@ScaledMetric` so it follows Dynamic Type.
  It applies on Today's prints, shared-moment prints, the story sheet, and
  Returned's "Keep this". Each marker's whole 44pt square takes a tap.
- **Story-comments** — flat, chronological, part of the artifact. Today shows
  the first one on the card and the newest beneath it; any between sit
  behind "More stories" (never "2 more" — a tally is still a count) which
  opens the photo with the thread. **A tap on a story line's words opens
  the same sheet** (build 24; people tapped them expecting the thread): in
  Today each line's name and words carry a `stanley-stories://<photo id>`
  link (`StoryLine.link`), beside the mentions' own, and the card's
  `openURL` opens the sheet for one and a profile for the other. The
  colors are set on every run, so no word turns link-blue. The rest of the
  comment area, beside and between the lines, opens the sheet too, from a
  tap target laid behind the lines (never over them, so the words' own
  links stay theirs). The sheet's own
  lines and a profile's carry no such link. The newest is there so a story just added
  appears right above the field it was written in: with only the first
  shown, a second story vanished behind "More stories" the moment it posted
  and read as a story that wouldn't post. Return sends a story as Add does
  (it used to close the keyboard and leave the words unsent). A story that
  fails to send comes back into the field. The stories sheet shows what was
  just added even when it was opened from a profile's prints, whose copy of
  the photo Today's refresh never reaches.
  Every story line is `StoryLine.text`: the name **bold** in the primary
  color, two spaces, the words in the secondary color, so two people's lines
  never run together. The empty field asks "What do you remember?"
  (`StoryLine.prompt`; it used to say "Add to the story…", which read like
  Instagram Stories). **Mentions** (build 19, `Mentions.swift`): typing @ in
  a story offers the circle's people in a bar right above the keyboard
  (`MentionBar`, fed by `AppState.mentionOffer`; a keyboard `ToolbarItem`
  declared inside Today's lazy list never appeared). A pick shows "@Name" in
  the field and is sent as `@[<user id>]`, which the server stores as plain
  text, untouched. Every phone draws it back as the person's name, bold, in
  their own watercolor tone (ten: coral, sage, dusty blue, clay, gold,
  lavender, rose, slate teal, olive, plum, each with a deeper light-mode
  ink and a paler dark-mode one), as a link that opens their profile.
  Tones are assigned per circle on the phone (`MentionTones`, UserDefaults),
  everyone in the roster in join order, so the first ten never share one.
  Someone no longer in the circle reads as "someone". **Being mentioned
  sends nothing**: no push, no badge, nothing new on the server. A mention
  isn't a who-was-there tag.
- **Returned + rest-a-memory** — one quiet card atop Today; priority **rescue >
  anniversary > near-forgotten**; Keep / Rest (never again) / Dismiss (not now);
  a Rested view with "let it return"; tombstoned photos never resurface.
- **Circles** — circle-first onboarding (invite code), roster as avatar cluster,
  rotate invite, remove member (creator), leave (with creator succession).
  **More than one** (build 17): up to five, `GET /circles` lists them by
  name in join order (no counts), and the circle's name atop Today is a
  menu of them, with "Join another circle". That opens the circle gate as a
  sheet (`CircleGateView(another: true)`); Settings has it too, and a circle
  picker once there's more than one. Joining or starting one shows it. The
  gate is the journal's first page (build 31; the QA audit found it the one
  plain system form left): a masthead ("Your circle", or "Another circle"
  from inside the app), a line in a hand, then two slips taped into the
  page (`GateSlip`: `paperInsert` under `Tape`, a little off square; no
  tape in the dark room), "Join your circle" with the code written on a
  ruled line and **Join**, and, after an "or" between rules, "Start a
  circle" with its name and **Start it**, both `WideButton`s; Return sends
  either. Sign out (or Cancel) stays in the bar. The
  one on screen is remembered per account; leaving it brings up another, or
  the gate if none is left. A sixth is `too_many_circles`, said in words.
- **Profiles** — display name, username, multi-line bio, avatar (soft-square,
  crop), member profiles (A2-safe: no holds, likes or counts). Since build 19
  a member's profile is **a page of the shared journal** (`MemberProfileView`):
  the atmosphere's card color with a paper grain (`Paper.swift`), the name
  large in a hand (SF Rounded in build 19), "Member since October 2026" (of
  the circle on screen, else the first one you share) between hairlines in
  small capitals with "· organizer" on whoever started it, their words or
  "Still writing this part…" in a hand, then "Still in the light": up to
  twelve of their own photos still public in circles you share, newest first,
  as small prints that fade as they do in Today, each opening with its
  stories. All from `GET /members/{id}` (`member_since`, `is_organizer`,
  `photos`). **Type** (build 19): every personal name and page title
  (`Font.keepsake`) is SF Rounded; it was a serif, and serif now belongs to
  the World tab alone. **The You tab** (build 20) is the inside cover of the
  journal: a masthead ("You", "Kept since July 2026", Edit at its end), then
  a bookplate in a double rule ("This journal belongs to", your photo pasted
  in a little crooked, your name written on a line, @username in small
  capitals, your words in a hand), the moments line, the circle under a
  section head ("Kept with" and its name) as a cluster of friends
  (`CircleCards`, the polish pass): round 52pt faces overlapping 9pt at
  their edges, each ringed in a 1pt hairline of photo paper (the page's
  black in the dark room) so one reads against the next, a first name small
  in a hand beneath, "organizer" in small capitals on whoever started it,
  scrolling when there are more than fit. Each opens that person's profile.
  At the row's end is **Invite** (build 33, from the HCI audit): a
  face-sized ring in the accent with a plus and "Invite" in the hand, which
  opens the invite page as a sheet (`InviteSheet` around Settings'
  `InviteCodeView`: the code, Copy, Share, Reset for the organizer, Done).
  The section shows with nobody else in the circle yet, just the card. Copy
  says "Copied" on its own row, since the app's flash sits under a sheet.
  Milestones are slips tucked in (`paperInsert`), and what you've held is a
  page of small prints under "Only you see this · Held". **Setup**
  (`SetupView`, build 16) walks a new account through four screens between
  sign-in and the circle gate: "What should we call you?" (required, no
  Skip), "Pick a username" (live check, Skip), "Write a little about
  yourself" (Skip), "Add a photo of yourself" (Skip). Each saves as it goes
  (`patchProfile`, only that field) and starts from what the profile holds.
  The server says `new_account: true` on the sign-in that made the account;
  the phone keeps a per-account flag until setup's last step, so quitting
  halfway brings it back. Anyone with no name gets setup too, as the old
  name gate did (Apple gives a name only on the first authorization, and
  only if shared). A server without `new_account` reads as false. **Avatars**
  (`AvatarPicker.swift`, build 16): one `AvatarChooser` for the You tab's
  face, the edit sheet's photo row and setup. The crop is a full-screen
  "Move and Scale" (it was a sheet, whose drag-to-dismiss fought the photo's
  drag, and whose item was rebuilt on every redraw). Cancel and Choose are in
  a real navigation bar (build 17): drawn at the foot they were too low to
  tap on some phones, and a drawn top row put Choose under the Duo cover's
  front camera. Drag and pinch work at
  once, the photo clamped to always cover the window, and the framed square
  cut from the photo's own pixels at up to 1024px. Setup and the circle gate
  each have a plain **Sign out** in the top bar, because Settings is past
  both. There's no confirmation, the same as Settings. The
  username field's live availability check sends `u` as a query item. Until
  build 13 it was percent-encoded into the path and got a 404, so it never
  ran (the server still validates on save). A nameless member
  serializes as `UNNAMED` ("New member"); `DEPARTED` ("departed") now means
  only a genuinely deleted account.
- **The circle's board** (build 27; it was one shared line, the
  **community note**, last-writer-wins until then) — a board of sticky notes
  atop Today, under the masthead (`NoteBoard.swift`). Everyone in the circle
  can pin one note a day (≤200 characters, the word filter on it), and only
  its author can change it or take it down: there's no way to address
  anyone else's. It clears at the end of the author's local day and the
  sweep deletes it then (`decay.clear_notes`, every pass beside the photos'
  decay); the next day's is a new note. `circle_notes` (id, circle, author,
  body, created/updated, `expires_at`; one row per person per circle,
  yesterday's deleted before today's is written). `PUT /circles/{id}/notes/
  mine` pins or edits yours, `DELETE` takes it down, `GET /circles/{id}/notes`
  is the board, and Today's first page carries the same list as `notes`,
  newest first, minus anyone a block stands between. For builds before the
  board, `PUT /circles/{id}/note` writes the caller's own note and the
  feed's `note` is the newest one. `ensure_schema` moves the old table's
  line onto the board as its author's note and drops `community_notes`.
  Leaving a circle, or being removed, takes your note off its board;
  deleting the account takes them all. A note can be reported
  (`reports.note_id`, not a foreign key since a note outlives no day: the
  report keeps a copy of its words in `reason`), and `moderation.py note
  <id>` takes one down. **The look:** each note a pastel sticky (a pale
  paper with its author's mention tone at 15%; lamplit in dark mode, never
  black) under a strip of tape, tilted −3° to +3° by its id, with its words
  in a hand and "— Ruby" beneath. Since the polish pass (build 28) the board
  is **a row you swipe through**: one note in view, full width, with 20pt of
  the next showing on the right, every note as tall as the tallest, and a
  row of 6pt dots beneath in the atmosphere's accent (faint, the one in
  view stronger; past nine they slide with you). Yours comes first, or a
  yellow "Leave a note for your circle…" until it's written; then everyone
  else's, newest first. One note alone: no peek, no dots, nothing to
  swipe. A tap on yours (or the blank) writes; long press reports someone
  else's. Build 27's overlapping corkboard (`BoardLayout`) and its "See
  all notes" sheet (`AllNotesSheet`) are gone: the board took too much of
  a phone's screen, and the swipe reaches every note. No replies, no reactions, no notification, and
  nothing counts them.
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
- **Writing things down** (build 26; `journal.py` for the weeks and the
  forty questions, `routes/journal.py`, `Writing.swift`). Three kinds, all
  on the journal's paper in a hand, none counted or notified, the word filter
  and the stories' rate (a `journal` bucket at `rate_stories_per_hour`) on
  every write:
  - **A private journal entry** ("Anything else about today?"):
    `journal_entries`, one per photo, ≤1000. `PUT/GET/DELETE
    /photos/{id}/journal`, owner only (404 for anyone else, and for a photo
    deleted or purged); writing needs the photo in Today or held by its
    owner (410 `faded` otherwise). Right after a photo posts (not one sent
    later from the queue) a slip under the print asks, with "Not now";
    doing nothing skips it, and it's gone at the next launch
    (`AppState.journalOffer`). A written one shows a small book beside the
    faces button on your own print, and the photo's menu has Write in Your
    Journal / Your Journal Entry; both open `JournalEntrySheet` (read,
    rewrite, delete). In Held, your own held photo carries it beneath, "Only
    you see this" (`memory_payload`'s `journal`, owner only). It goes with
    the photo: `decay.scrub` deletes it (owner delete, redo, purge,
    takedown); at expiry `fade_journal` deletes it unless the *owner* holds
    the photo (someone else's hold keeps the photo, not the owner's words);
    the owner letting go of a faded photo takes it too.
  - **The weekly reflection** ("How was your week?"): `weekly_reflections`,
    one per person per week (409 `already_reflected`), ≤500, never fades.
    `POST /me/reflections` (the server sets the week: the Monday of the
    writer's own week, in the zone the phone sends, with Monday before 6am
    still the week just ended, so a send at 00:01 isn't filed under the new
    week), `GET /me/reflections` (newest first, cursor pages of 20),
    `GET /me/reflections/this-week` (the week's days, your own photos from
    it still in Today or held by you, and the reflection once written),
    `GET` and `DELETE /me/reflections/{id}` (the writer alone; delete is a
    long press, since a reflection never leaves otherwise). On Sunday from
    6pm to midnight on the phone's clock (`ReflectionWindow`; the server
    doesn't hold to the hour) the You tab opens with a slip, the week's
    photos as small prints, which opens `ReflectionSheet`; it leaves at
    midnight (a `TimelineView` checks each minute) and once it's written.
    Past ones are the **Journal** section at the foot of the You tab, each a
    page with the week's dates, the words, and that week's photos still
    there. A Debug build launched with `STANLEY_SUNDAY_EVENING=1` opens the
    window on any day, for the simulator.
  - **The circle's question of the week**: `circle_prompts` (one per circle
    per UTC week, chosen the first time anyone asks, never one of its last
    thirty-nine) and `prompt_responses` (one each, ≤300, never edited).
    `GET /circles/{id}/prompt` (the question, your own answer, `revealed`),
    `POST /circles/{id}/prompt/respond` (409 `already_answered`, 409
    `question_closed` once open), `GET /circles/{id}/prompt/responses` (403
    `not_revealed` before Saturday 00:00 UTC; then everyone's, in the order
    written, minus anyone a block stands between), and `GET
    /circles/{id}/prompts`, the **circle journal** (every opened week from
    the one you joined in, newest first, weeks nobody wrote skipped). A
    slip under the note in Today (`QuestionSlip`): a line to answer on with
    Answer at its end (below it the keyboard hid it), then "You answered"
    behind a lock with your words, then "See what everyone said", a sheet
    with each name in its mention tone and the words in a hand. The reveal
    is said in the reader's own time, from `reveals_at`: "Your answer is
    private until Friday at 7 PM" in Bloomington, because "until Saturday"
    would be broken by hours there. The circle journal opens from the
    circle's name atop Today and from Settings → Circle. An answer can be
    reported once it can be read (`reports.response_id`, `moderation.py
    answer <id>`); deleting an account deletes its answers and detaches
    their reports.
  Deleting an account deletes all three; the export carries entries on your
  held photos, your reflections and your answers. Checked on the iPhone 17
  Pro simulator against a scratch copy of the screenshot circle, including a
  server clock moved to Saturday for the reveal, in light and dark.
- **Offline capture queue** (client) — no signal means the moment is kept
  locally and sent when the network returns (when Stanley answers again,
  `AppState.checkConnection`, or on Today's next pass; one send at a time),
  with a quiet "waiting to upload"
  card where it will land. The day law is claimed **locally** at the shutter,
  so a queued capture closes the camera exactly as a posted one does. A
  server refusal (another device used the slot) strands it honestly: the owner
  can save it to Photos or discard it, never a silent loss. Per circle since
  build 17: at most one waiting in each, each carrying its circle and sent
  there. One queued by an older build goes to the first circle joined.
- **Adaptive density** (client) — `Density(horizontalSizeClass)` in
  `Layout.swift` is the single source for every size that differs between the
  iPhone Duo's two displays: compact is the outer display (and every ordinary
  iPhone, which keeps today's behaviour exactly), regular is the inner one.
  Inner gets a 560pt journal column, a side-by-side shared moment, a two-column Held
  magazine, a horizontal profile header, a 600pt readable Settings column and a
  bigger Returned photo, and a readable column on onboarding as well as
  Settings. Only density and arrangement change — no feature is gated to either
  surface. `isLargeCanvas()` exists for enhancements that need real estate,
  never for gating, and is currently unused. Screen metrics come from
  `Density.canvasBounds()` — the window scene's own screen, not `UIScreen.main`,
  which on a two-display foldable names the primary display rather than the one
  the app is on.
- **Atmosphere** — neutral by default, personality by choice (build 16).
  **Auto** is Stanley's own quiet look, no longer the season: warm paper
  (#F6F0E4 since build 20; it was #F8F6F1) and white cards in light mode, true black and a #1A1A1A card in
  dark, with a warm-charcoal / warm-white accent, so tabs and buttons are
  black and white with a little warmth. The five moods (Spring, Warm, Fall,
  Cool, Rain) are picked from a **menu** in Settings (a `Picker` with
  `.menu`; the pill row is gone). Each is a `Palette` (`Atmosphere.swift`):
  an `accent` (tab bar, buttons, bookmarks, edges), an `ink` for labels on
  an accent fill, an opaque per-mode `floor` (the root and every screen
  paint the same one, so overlaps are invisible), a `card` under every
  Today card, a `row` behind grouped-list rows (`.atmosphereRows()`, on
  every Form and List), and a `toggle` (the accent, except Auto's dark
  white, which would hide a switch's knob). Light mode mixes the tone into
  the system white. **Dark mode** is black with about 5% of the tone in the
  floor and 6% in the card (Rain 3% and 4%: fog, barely there); the mood
  lives in the accent. Pilot users called build 10–15's colored dark floors
  "terrible" and "artificial". Build 20 redrew the moods from real palette
  sources, each shifted off the obvious color so neighbors don't blur and
  none reads as a stock one: Spring is moss, not mint; Warm is honey, not
  amber; Fall is terracotta, not pumpkin; Cool is slate, not sky; Rain is
  fog on a window. Auto's accent and floor are a little warmer. Ambient
  only; never affects function. Since build 33, Spring's and Warm's light
  accents are darker in lightness alone, to 3:1 on their own card (moss
  `6F955B`, honey `B57C29`; they were 2.5:1), with their inks deepened so
  a label on the accent stays at 4.5:1. Dark accents unchanged.
  **The dark room** (build 24, `DarkRoom` in `Journal.swift`): pilot users
  kept saying dark mode looked bad, so dark mode stopped being the journal
  at night and is a photo gallery in a dark room. Pure black (#000000)
  floor and card in every mood, no paper and no grain anywhere
  (`PaperGrainView` draws nothing in dark); a photo is the card, bare on
  black with 4pt corners and no paper, shadow or lean (`asPrint` and
  `pastedFace` in dark); words in a warm white (#F0EBE3, `DarkRoom.ink`,
  set once at the root by `darkRoomInk()` and the only foreground change,
  so `.secondary` is that white at half strength); every rule, hairline and
  box in #2A2A2A (`DarkRoom.line`), barely there; a paper insert (mosaic,
  Returned, empty states, milestones) is the same black boxed in that rule;
  the sticky note keeps its lamplit yellow, without grain; Settings rows
  keep their step up from black. Only the tab bar and the accents carry the
  atmosphere. Light mode is the journal exactly as before: in light,
  `darkRoomInk()` hands back `.foreground` and every dark-room branch is
  off.
- **Spacing** (the polish pass, build 28, `Spacing` in `Layout.swift`) —
  one unit and its half and double, so every gap looks chosen: 8pt inside
  one thing, 16pt between sections (the masthead and the board, the board
  and the question, the question and the first day, any tucked-in card and
  what follows it, a day's mark and its first print, either side of the
  rule between two prints, a print and the next in Held, the grids on You),
  32pt before a new chapter (a new day in Today, a headed section on You, a
  friend's page in Held) and at the foot of every page above the tab bar
  (Today, Held, You, World). The page's side margin stays 20.
- **The journal's visual language** (build 20, `Journal.swift`; in light
  mode since build 24, dark mode being the dark room above): the World
  tab's morning paper set the bar and every main page now matches it. Every
  page is paper (`atmosphereWash` lays the paper grain over the floor, so
  sheets, Settings' pages and the capture sheet are grained too). Main pages
  have a masthead (`JournalMasthead`) instead of a navigation bar
  (`journalPage()`, with a strip of the page under the status bar); pages
  pushed from them keep theirs. Every masthead (Today's, World's and the
  shared one) ends with 10pt of room under its hairline (build 22; pilot
  users wanted the title to breathe before the page begins). Thin rules (`Rule`) where other apps draw
  boxes; sections headed between a heavy rule and a hairline
  (`JournalSectionHead`); datelines and labels in small capitals
  (`smallCaps`). The paper keeps the serif; the journal writes in a hand
  (`Font.hand`, Noteworthy) for anything a person would write themselves:
  names, day marks, captions, bios, notes. Photos are prints on paper
  (`asPrint`, `PrintStock`), never cards. Only the look changed: every
  action, gesture and menu is where it was, Edit and Rested having moved
  into their mastheads. **Build 21 carried it to the edges:**
  - **Empty Today** (`TodayEmptyPage`): a sheet tucked into the page, "Nothing
    here yet." and "Your circle's first moment is waiting." in a hand, a
    rule, "Photos live for six days, then they're gone." in small capitals,
    with (since the QA audit, build 30) the camera inside the sheet; at
    90pt below it, it fell under the tab bar once the note row and the
    question were above it. Since build 31 it's shorter, so its foot clears
    the tab bar with a three-line question above it: "Nothing here yet.",
    then a 44pt camera ring with "Take today's photo" and "Your circle's
    first moment is waiting." beside it as one button, then the rule and
    the six days in small capitals, and 32pt of room beneath. Only once
    Today has answered (`todayLoaded`), so it never flashes up while photos
    load, and not while a capture waits to go up.
  - **Empty Held**: a sheet with a blank print (since build 24; four photo
    corners around nothing before) and "Nothing held yet. When you press
    and hold someone's moment, it lives here, long after it fades." The
    brief said "forever"; the subject wins
    on deletion, so it doesn't promise that. Shown only once Held has
    answered (`memoriesLoaded`); offline before that it says "Not here yet."
  - **Onboarding** (`OnboardingView`): the three pages, same words, on
    grained paper: "Stanley" in small capitals, a thing laid on the page (one
    print; three prints fading; four faces in watercolor tones), the
    headline in a hand on one line over the paper's double rule, the words
    beneath, ink dots for the page, and `WideButton` for Get started. The
    prints are an evening sky drawn in code, not photos.
  - **Today's photo already shared**: the capture sheet opens on the photo
    itself, a crooked print, and "Today's moment is out there. Come back
    tomorrow." with Done and no camera (`AppState.sharedToday`: your photo
    taken today still in Today in this circle). `slot_used` from the server
    says the same words (`APIError.sharedToday`); it used to say "You've
    already shared today's moment."
  - **Capture**: the frame is a print (photo paper, a hairline corner) before
    the shutter and after; the day's prompt and "One photo. This is today's."
    are in a hand; the place is written in a hand on a ruled line, and the
    caption is "In your words" in small capitals over a hand-written line,
    not boxed cards; "Who was there?" in small capitals with names in a hand.
- **Settings** (build 18), grouped the way iOS groups its own, every row in a
  group: **Circle** (Name, editable by the organizer through `PATCH
  /circles/{id}`; Members; **Invite Code**, one row opening its own page with
  the code, Copy Code, Share Invite and, for the organizer, Reset Code behind
  a confirmation; Join Another Circle; Leave Circle, red and last),
  **Appearance**, **Quiet** (the two notices, with the reason there are so
  few), **Privacy & Security** (Require Face ID or Touch ID, whichever the
  phone has, Export My Memories, and About
  Your Account, a page with name, username and join date, then Sign Out,
  Blocked and Delete Account, one level down), and **About** (About Stanley,
  Terms of Use, Privacy Policy, Acknowledgements (Sentry's MIT notice, the
  production audit), and the version, "Stanley 0.2.0 (36)", at the
  foot). Build 26 put **Circle Journal** in Circle, under Members.
  With more than one circle, a **Circle** picker heads the Circle group
  (build 30; documented earlier but missing until the QA audit).
  Since build 20 it sits on the journal's paper under its own masthead
  ("Settings", "Stanley, and how it's kept"), with section heads in small
  capitals; the rows themselves are unchanged.
- **Push** (build 18) — APNs directly, token auth (ES256 JWT, kept fifty
  minutes) over HTTP/2 (`httpx[http2]`), `apns.py`. `Notifier` logs each
  notice and hands it to the transport only **after the session commits**
  (`after_commit` on the sessionmaker), so a pass that rolls back sends
  nothing. `PushDelivery` sends to every phone the person signed in on
  (`push_tokens`, one row per token, `production` or `sandbox`) and deletes a
  token Apple calls dead (410, `BadDeviceToken`, `DeviceTokenNotForTopic`). A
  failed push is logged and missed, never retried into a second one. Without
  `APNS_KEY`/`APNS_KEY_ID`/`APNS_TEAM_ID` the notifier only logs. The app
  (`Push.swift`, an `AppDelegate` for the token) asks for permission **when a
  notice is turned on**, not at first launch, since both are off by default;
  if iOS refuses, the switch goes back off and a row opens iOS Settings. With
  permission, every launch and sign-in registers and sends the token (`POST
  /me/push-token`); sign-out removes it (`DELETE /me/push-token`), and a
  token follows whoever signed in on that phone last. Alerts are words only:
  no sound, no badge, priority 5. Checked on the simulator with `simctl push`
  of the server's own payload.
- **Terms and Privacy** (build 18) — final copy, public at `/terms` and
  `/privacy` (plain HTML, no scripts; the privacy URL is the one App Store
  Connect wants), with `/support` beside them since build 34 (App Store
  Connect's Support URL: "Stanley Support", the contact address linked,
  "We'll get back to you within 48 hours", no effective date; server only,
  not in the app) and shown natively from Settings and from Welcome ("By
  signing in, you agree to the Terms of Use and the Privacy Policy", both
  links). One source, `server/stanley/legal.py`; the app's `Legal.swift`
  carries the same words and `test_legal.py` fails if they drift. About
  Stanley is the product story in three paragraphs. **Full versions**
  (build 18, effective November 1, 2026): the Privacy Policy in eleven
  numbered sections (about 1,950 words) and the Terms in eighteen (about
  2,050), the brief's seventeen plus Apple's minimum terms (section 17,
  before Contact). Lines may be `- ` list items or `## ` subheadings. Every
  claim is meant to be what the code does, checked against it when written:
  no email requested from Apple, the capture time the only metadata kept,
  coordinates only ever between the phone and Apple's geocoder, the town and
  country in headers and keyed by town, deletion immediate and out of the
  seven daily backups within seven days, held copies gone when the poster
  deletes, an exported copy beyond reach, the publisher's site when an
  article opens. Change the words with the code, and `PRIVACY_LABEL.md`.
  No straight double quotes or backslashes in the text (it's pasted into
  Swift literals). Not reviewed by a lawyer. **Set for reading, not in the
  journal look** (after build 25): legal text should look like legal text.
  In the app, `LegalDocumentView` is a plain white page (black in dark
  mode), no paper, grain or hand: the system font, a large title that folds
  into the bar, "Stanley" and the effective date under it, a divider, bold
  section headers, 5pt line spacing, a 680pt column, and the contact address
  (`Legal.contact`) a mailto link in the system's blue. On the web, `/terms`
  and `/privacy` (`legal.page`, the URLs App Store Connect links) are a white
  page with a 680px column, the system sans-serif at 16px, Stanley's name
  above the title, the effective date beneath it, bold headers, the contact
  address linked wherever it appears, a footer linking both documents, and
  a tighter layout under 480px. Still no scripts and nothing fetched from
  elsewhere; the CSP allows the inline stylesheet only. **Build 26** added
  the journal to both: entries and reflections only ever shown to you,
  answers sealed until Saturday at midnight UTC ("Friday afternoon or
  evening in the United States") and then read by the circle, from the week
  a member joined; how long each is kept; the export; and journal entries,
  reflections and answers as Content in the Terms (both effective November
  3, 2026, not yet deployed).
- **Errors in Stanley's voice** — no status code, server `detail` string or
  system description ever reaches the screen. `APIError` maps every server
  code and bare status to a sentence; `AppState.words(for:)` covers the rest
  (unreachable, undecodable, Apple sign-in). A failed upload says the day is
  still open, which is true: the server rolls the whole request back. No
  signal never fails at all — it queues. **An error is said over whatever
  is showing** (build 32, `Spoken` in `StanleyApp.swift`): a UIKit alert
  from the topmost view controller, tinted with the accent. It was a
  SwiftUI alert on the root, which closed any open sheet to show itself, so
  a note that didn't pin lost its words and a refused post would have lost
  its framed photo (the HCI audit's one critical finding). A sign-in the server turns down
  (a bare 401 on a request that carried a token: expired, secret rotated,
  account gone) signs out **automatically**. `APIClient.onTokenRejected`
  hands `AppState` the token that was refused, and the app signs out only if
  that's still the token it holds, so a late answer can't undo a fresh
  sign-in. It says why once (`APIError.signedOut`), and every other failure
  from the same cause stays quiet. It used to say "Sign out in Settings",
  which the name and circle gates can't reach.
  **Offline** (build 21) is a state, not an alert. A page that can't load for
  want of a connection (`AppState.missed`, every passive load) sets
  `AppState.offline`: each masthead says "Offline · it all catches up when
  you're back" under its dateline (`OfflineLine`), what was showing stays, and
  Held and World say they're waiting rather than empty. Something the person
  did (a story, a like) still says it didn't go through. While offline the app
  asks `GET /health` every 8 seconds, and when the network path or the app
  comes back to the front; once it answers, Today, the circle, Held and the
  profile load again, the paper if it's empty, anything queued goes up, and
  `reloads` tells the rest (member pages, Rested, milestones, Blocked, the
  Quiet switches, failed photos). Launched offline, it shows "Stanley can't be
  reached right now" and opens by itself: it used to fall through to the
  circle gate, as if the person had no circle, and stay there, and every tab
  raised the same alert, once per failed request.
- **The World Today** — the news in a **World** tab of its own (globe), the
  fourth of five: Today, Held, You, World, Settings. A morning paper on the
  counter, not a feed. Today is the circle's photos and nothing else. Since
  build 15 there are **two editions** (`server/stanley/news.py`), all
  keyless RSS, on by default, off with `STANLEY_NEWS=0`:
  - **National**, with summaries: **PBS News Hour**
    (`pbs.org/newshour/feeds/rss/headlines`) for a phone in the US, and for
    any phone that hasn't been located, since the pilot is in the US; **BBC
    World** (`feeds.bbci.co.uk/news/world/rss.xml`) for a phone located
    anywhere else. Twelve stories, each with the one- or two-sentence summary
    it was published with, trimmed to 60 words. `GET /news/today`, the
    country in an `X-Stanley-Country` header. Build 14 used Google News's top
    stories, which carry no summaries (Google's `<description>` is a cluster
    of other outlets' links), so an in-app reader had nothing to read. The
    country is never the region in Settings: on the simulators (and likely on
    the user's own phone) that's `en_IN`, and a student from abroad keeps
    their home region while living in Bloomington.
  - **Nearby**, headlines only: Google News's local feed for the town the
    phone is in (`news.google.com/rss/headlines/section/geo/<town>`, which
    redirects to that town's topic). Six stories, shown first as "Near
    Bloomington". `GET /news/nearby`, with the town ("Bloomington, IN",
    percent-encoded) in `X-Stanley-Town`. Only with location permission; no
    town, no section. Where the phone is goes in headers, never the query
    string, so it stays out of access logs. The server keys the cache by
    town, never by who asked, caps it at 50 towns, and drops a town nobody
    has asked about for a day.
  Each edition is one row of `news_editions` (key, fetched_at, articles;
  `news_cache` is dropped on startup), written by upsert. The background loop
  fills the US edition at startup and every 30 minutes; any other edition is
  fetched when someone asks and it's missing or 30 minutes old (a 5s
  timeout). Clients read only the server, so nobody but the server talks to
  the feeds. Parsing is ElementTree (no external entities, expat caps
  expansion), capped at 2 MB. Normalized once: text only, the outlet
  stripped from Google's headlines, http(s) links only (anything else
  crashes the Safari sheet), repeats dropped by link and by headline before
  counting. Each edition is its source's own pick, shown newest first. A
  failed fetch keeps the last good set; a set older than 6h is not served,
  and an empty tab says "No stories right now."
  **A morning paper** (build 19): no cards, no navigation bar, just a page.
  "The World Today" as a black serif masthead, "By Stanley" under it in
  small italic serif the way a paper names its publisher (build 22), then
  the heavy and hairline rules, the dateline ("SUNDAY, 1 NOVEMBER 2026 · PBS
  NEWS HOUR") in small caps, then the lead story across the full width (title-size bold serif,
  byline, summary), a rule, and the rest in columns (two on a phone, three on
  the Duo's inner display) split where the page is about half full, with
  hairline rules between stories and between columns. Nearby is a section
  under an italic "Near Bloomington" between rules. New York (the system
  serif) throughout, the only serif in Stanley; bylines in small caps.
  The page is the floor with paper grain, and a strip of floor sits under
  the status bar so the paper slides beneath the clock.
  **Reading in place** (build 15; build 18 for the two styles): a story with
  a summary (PBS, the BBC) shows the headline, outlet and time, the summary
  beneath, and a small italic "Read full article ↗"; the whole story opens
  `SFSafariViewController`. A headline-only story (Google's local feed) is
  the bold headline, the source line and "Read more ↗", with no empty space
  where a summary would be.
  Safari is presented by UIKit over whatever is on top (`StoryReader`): as a
  SwiftUI sheet, its Close forced a second dismissal that closed what was
  beneath it too. A notice boxed in a rule, under the masthead, asks once
  for location ("News from near you", Allow location / Not now) before the
  system sheet; "Not now" puts it away for good. The page names its outlet
  in the dateline and counts nothing. No likes, saves, shares, comments or
  notifications. News never
  appears in Today, Held, Returned, the export or any memory surface. It
  loads when the tab appears and on pull, never on a timer, and the pull
  runs as a separate `Task` because SwiftUI cancels a `.refreshable` task the
  moment the state it refreshes changes. The national stories don't wait for
  a location fix; if the fix finds the phone in another country, the
  national edition reloads once. The test suite turns news off by default,
  and an autouse guard fails any test that tries to reach a feed.
- **Safety/privacy** — bidirectional block (enforced on the feed, direct photo
  access, member profiles, **and the Held/Rested archive** — a blocked person's
  photos are hidden, never deleted; unblocking restores the thread intact),
  report (24h takedown), account deletion
  with cascading blob purge, signed URLs, a biometric app lock (off by default;
  named for the phone's own biometric since build 29, `Biometrics.kind` from
  `LAContext.biometryType`: Face ID with the faceid symbol, Touch ID with
  touchid on the Duo, no row at all without one unless the lock is already
  on, so it can still be turned off; the lock screen's Unlock says which, and
  the usage description is generic),
  memories export (zip). **In the app since build 18** (`SafetyViews.swift`;
  before, no build had ever called the server's report, block, photo delete
  or untag): every print has a quiet "…" at the end of its caption line
  (always drawn now), and its long-press menu and the stories sheet's
  toolbar carry the same rows: **Report Photo** on anyone else's, **Delete
  Photo** on yours, **Remove Me from This Photo** when you're tagged. A
  story's long-press menu has **Report Story** (not on your own). Reporting
  is one tap on a reason (seven since the production audit, which added "It
  sexualizes or endangers a child", plus Something else with your own
  words); the
  sheet says it goes to the person who runs Stanley, not the poster, and is
  read within a day, then offers to block them. A long press opens the menu
  without holding the photo (checked). **Block** sits at the foot of every
  member profile, behind an alert that says neither sees the other's photos
  or stories and they aren't told; **Settings → Privacy & Security → About
  Your Account → Blocked** (build 22; it was a row of Privacy & Security
  itself, more visible than something so rarely needed) lists the people you
  blocked (`GET /blocks`, faces and names, never who blocked you) with
  Unblock, next to Delete Account. Blocking refreshes Today only after
  its sheet has closed: refreshing under it removed the card that presented
  it and tore the sheet down. Delete's alert says whether it gives the day
  back, from `retake_on_delete` (owner-only, in the photo payload: today's
  photo with the redo unspent), never a guess. A report is logged as a
  WARNING ("A report is waiting for review: <id>"), which `fly logs` shows,
  and a story can only be reported by someone in its photo's circles.
  Account deletion leaves a bare row for
  tombstones and reports to point at, with no name, username, bio, Apple
  `sub`, avatar, time zone or settings, and takes the person's community
  note, notification log and Returned log with it (build 18; username, bio
  and those rows used to survive). Deleting a story detaches any report about
  it (`decay.delete_comments`, pointing the report at the photo instead):
  before, foreign keys refused, and one reported story made its photo's
  deletion, its purge and its author's account deletion fail.
- **One circle's countdown** (build 35, a product decision on 2026-11-06,
  for Ayush's circle going home to India for Thanksgiving). A flag, not a
  feature: `circles.countdown`, a JSON column, null for every circle but the
  one it was set on, returned by `/circles/mine` with the circle on screen.
  Set only by hand with `scripts/set_countdown.py` (`find`, `show`, `set`
  with the `india` preset or a JSON file, `clear`; standard library only, so
  it can be piped to Fly like `integrity_check.py`). Nothing in the app or
  the API creates one. Under Today's dateline the app draws `CountdownRoute`:
  a dotted route sketched edge to edge, a dot at the start, a ring at the
  end, a light SF `airplane` along it by how much of the wait since
  `start_date` has passed, and the phase's words in Noteworthy beneath, all
  in the secondary ink and not tappable. Phases (`Countdown.phase(at:)`,
  the words since build 36): before the day, "16 days for Home", two
  calendar days left "Almost Home", one left "Tomorrow", each over a
  **flip clock** (build 36) counting to the first second of the day in
  `target_tz`; the day itself, plane at the end ("Bags packed, hearts full.
  Let's go home.", no clock: the moment has come); then until `arrives_at`
  ("You're in for an awesome journey!"); then a drawn SF `house` in place of
  the route ("How's home?") until `home_until`, after which nothing is
  drawn. Which words is a matter of calendar days; the number in them is
  the clock's own whole days, so the two never disagree (Nov 6 at 7 PM CST
  is "16 days for Home" over 16 : 05 : 00 : 00, though Nov 23 is 17
  calendar days off). Landing and the end are stored with their own IST
  offsets (Nov 25 02:30 IST, which is Nov 24 15:00 CST, and the start of
  Nov 28 IST). **No emoji in the countdown** (build 36, a product
  decision): the plane and the house are drawn, `set_countdown.py` refuses
  a symbol in the label or a message, and a photo posted on the day itself
  gets a tiny drawn plane after the time in its byline (`PrintByline`'s
  `plane`; it was a ✈️). **The flip clock** (`FlipClock` in
  `CountdownRoute.swift`): Days, Hours, Min, Sec, each two digits on a
  little card of the atmosphere's card color with a hairline round it and
  one across the middle where a flip card splits (black boxed in the
  room's gray in the dark room), colons in the secondary ink between. The
  digits are SF Rounded semibold with even widths, 16pt scaling with
  Dynamic Type; the labels are the hand, bold, 10pt, in capitals beneath.
  Each digit flips on its own as it changes, a 0.3s rotation about its
  middle (`rotation3DEffect` on X with a little `scaleEffect`), the old one
  tipping away as the new one comes up; only a fade under Reduce Motion;
  silent. A `TimelineView` ticks on whole seconds while the clock counts
  and each minute after. VoiceOver reads the words and what's left to the
  minute, not a number every second. **Trip reminders** (build 36): the
  countdown's `reminders`, keyed by calendar days left, a note on certain
  days ("17": "The countdown begins!", then 14, 11 ("Shopping done? 👀", the
  one emoji a reminder may carry; the script allows them there), 8, 5, 3,
  and "1": "Tomorrow. TOMORROW."). On its day only, a `ReminderSlip` sits
  above the route: a scrap of the sticky note's paper (lamplit in the dark)
  torn along the bottom (`TornEdge`, from a seed of its words), as wide as
  its words, under a small strip of `Tape`, 2° to 4° off square, the words
  in the hand at 14pt in the note's ink. It fades in as it settles 8pt
  down onto the page each time the page shows it (just the fade under
  Reduce Motion). The days between have none; nothing to dismiss, nothing
  that notifies. It counts days, never people, so it sits outside "No
  counts"; a countdown would still break the rule for notifications. A
  countdown the app can't decode is dropped and never fails the circle
  (`CircleInfo.init(from:)`), and one written before build 36 (with
  `emoji`, without `reminders`) still reads.

## Open items (not yet built / not yet done)

- **Deploy for real.** Stood up on **Fly** (`server/fly.toml`) — a third path
  beyond the two [`server/DEPLOY.md`](server/DEPLOY.md) documents, and the one
  actually in use. Live at `https://server-earnest-stream-9793.fly.dev`, `GET
  /health` returns `ok`, `STANLEY_SECRET_KEY` and `STANLEY_DATA_DIR`
  (`/data/var`, on the `stanley_data` volume) and `APPLE_BUNDLE_ID`
  (`com.ayushkapileshwar.stanley`) all deployed, `STANLEY_DEV_AUTH=0`. Sign in
  with Apple is configured: `POST /auth/apple` rejects a bad token with 401
  rather than answering 503 `apple_auth_unconfigured`.
- **The India countdown in production.** Set on 2026-11-06 (Fly release
  **v20**) with build 35's `india` preset on Ayush's production circle,
  **Anti mosquito** (`8fa3cca67bba40ec8157dca4fd8193ce`, the only circle
  `find Ayush` names; Ayush is a member, not its creator), and on no other.
  **Not yet: build 36's words and reminders.** The row still holds build
  35's ("17 days until India ✈️", no reminders), and v20's copy of the
  script has the old preset, so it takes a `fly deploy` of the new script
  and then the same `set 8fa3cca67bba40ec8157dca4fd8193ce india` again.
  The script ships in the image, so it runs as it is, no piping:
  `fly ssh console -a server-earnest-stream-9793 -C "/app/.venv/bin/python
  /app/scripts/set_countdown.py /data/var/stanley.db show <id>"` (or
  `set <id> india`, `clear <id>`). Everyone in that circle sees it once
  they're on build 35 (36 for the clock and the slips); older builds
  ignore the field. **Build 36 has to reach them before November 23.**
- **Build 36** (0.2.0) is committed but not archived. Build 35 was
  archived on November 6 at 7:30 PM (Organizer), before the flip clock and
  the reminders; builds 34 and 28 are archived too. Whether any was
  uploaded isn't visible from here. Build 18 added the `aps-environment` entitlement, so the App ID
  needs Push Notifications (automatic signing normally adds it; see DEPLOY.md
  if the archive complains).
- **TestFlight build.** Build 13 (0.2.0) is archived and exported from
  `163ec6d` (it includes the gate sign-out), **not yet uploaded**. An earlier
  build 13 archive from `4a616da` was moved to the Trash. The archive is in Xcode's Organizer (`~/Library/Developer/Xcode/
  Archives/2026-10-30/Stanley 0.2.0 (13).xcarchive`). The App Store Connect
  IPA is at `ios/build/testflight-13/Stanley.ipa` (gitignored), with the
  `ExportOptions.plist` that made it: method `app-store-connect`, destination
  `export`, automatic signing. The paid membership is in place. The
  IPA is signed with the team's cloud-managed Apple Distribution certificate
  and the App Store profile (created 2026-10-29). It carries
  `beta-reports-active`, Sign in with Apple, no `get-task-allow`, the Fly
  `STANLEY_API_BASE`, and symbols. Release compiles out dev sign-in and the
  simulator camera stand-in. `STANLEY_SENTRY_DSN` is empty, so this build
  has no crash reporting. To ship, use Organizer → Distribute App → TestFlight
  & App Store, or Transporter with the IPA.
- **App Store submission** (November 4, build 33): `APP_STORE_METADATA.md`
  holds every field (name, subtitle, promotional text, a 3,030-character
  description, keywords, categories, age rating, URLs, copyright) and the
  screenshot plan. The screenshots are in `ios/AppStoreScreenshots/6.7/`
  (1290 × 2796) and `6.1/` (1179 × 2556, native from an iPhone 15 Pro
  simulator), and the Duo's cover in `duo-outer/` (1398 × 2034; no inner set,
  since the simulator can't unfold): Today, capture, Held, You, World
  and the weekly question, plus an optional seventh, all from
  `seed_screenshots.py`. The Support URL is the server's `/support` page
  (build 34; live after the next `fly deploy`). One decision is open:
  - **Unrestricted Web Access:** answering Yes rates the app **16+** in
    Apple's current table, against the Terms' 13; No keeps it at 13+.

  The World screenshot carries the day-after-midterms headlines.
- **Fly now** (checked read-only on 2026-11-04): release **v18** (November 3,
  20:00 UTC) carries the production audit and build 26's journal (headers,
  hidden docs, refresh, reflections all answer). **Not deployed: the board**
  (`/circles/{id}/notes` is a 404) and the November 4 Terms and Privacy
  wording (`/privacy` says November 3). The volume is **3 GB**, with 32 MB
  used. `/data/pre-build18.db` is still there (due by November 8). The
  paragraph below about v15 is history.
- **Fly before** (checked read-only on 2026-11-03): release **v15**
  (2026-11-02 04:54 UTC) runs the server as of `de71bc9`, the last server
  change before the production audit: `/terms` and `/privacy` are
  byte-identical to `legal.py` then, and `REPORT_WEBHOOK_URL` is set among
  the secrets. The paragraphs below about v11 are history. **Not yet
  deployed: everything from the production audit** (rate limits, headers,
  the word filter, paging, refresh, moderation tool, the November 3 privacy
  wording), the reading layout for `/terms` and `/privacy`, and **build 26's
  journal** (four new tables and `reports.response_id`, made by `create_all`
  and `ensure_schema` on the first start; until then build 26's app shows no
  question slip, no Sunday card and no book, quietly), and **the board**
  (`circle_notes`, `reports.note_id`, the old note moved across; against
  today's server the app shows its one note and writes it through the old
  path). The volume is **1 GB** (26 MB used): about ten days of a
  30-person circle's photos, so extend it before the pilot
  (`PRODUCTION_CHECKLIST.md`, step 1). The integrity check passed on the
  live database.
- **Fly deploys.** Release **v11** (2026-11-01 16:27 UTC) runs the server as
  of `fd6a50b`, build 18: everything above, including multiple circles,
  push, `/terms` and `/privacy`. Before it, v10 was a build 16-or-earlier
  server (`/terms` 404, `GET /circles` 405). On v11's first startup
  `ensure_schema` rebuilt the photos table, making the day's slot per
  circle (`_rebuild_photos`). Afterwards it was checked on the machine:
  the slot per circle, `push_tokens`, `users.digest_enabled`, integrity
  ok, no foreign-key problems, 4 photos and 3 users intact. The snapshot
  taken just before is `/data/pre-build18.db` on the volume and
  `server/var/fly-backups/pre-build18-20261101.db` here (gitignored). The
  app's own INFO lines (news, APNs) don't appear in `fly logs` under
  uvicorn's logging, so check state on the machine (`fly ssh console`)
  rather than by a missing log line. **Not yet deployed:** the full Terms
  and Privacy Policy, the deletion fixes, and what the app's Report, Block
  and Delete need (`GET /blocks`, `retake_on_delete`, the report log line
  and scope, the ntfy alert), and build 19's member profile fields and
  `moments_shared`; against v11 the Blocked list fails quietly, Delete's
  alert leaves out the day, member profiles show only name and words, and
  the You tab has no moments line. Mentions need no server change. Delete the pre-build-18
  snapshot (both copies) by 2026-11-08, or the policy's "gone from our
  backups within seven days" stops being true.
- **Report alerts need the topic on Fly.** Each report is a WARNING line in
  `fly logs` and, with `REPORT_WEBHOOK_URL` set, one POST of "A report is
  waiting for review" to an ntfy.sh topic the operator's phone subscribes to
  (`alerts.py`, build 18; DEPLOY.md, "Report alerts"). The line is fixed: no
  reporter, photo or reason, so ntfy receives no one's data and the Privacy
  Policy has nothing to add. It's sent as a background task after the commit
  and the response; a failure is logged without the URL (the topic name is
  the secret) and never touches the report. Set on Fly by v15 (`fly secrets
  list`); whether a real report reaches the operator's phone hasn't been
  seen yet. Not yet seen on
  a device: Remove Me from This Photo (no dev photo tags the dev account;
  the server path is tested).
- **Live SIWA verification.** The Apple flow is tested against a mocked signing key
  (faithful to the verify path); it has not been run end-to-end on a real device.
- **APNs.** Configured on Fly (v11): `APNS_KEY` (the `.p8`, key ID
  `YBN4J996KV`, kept at `~/Documents/AuthKey_YBN4J996KV.p8`),
  `APNS_KEY_ID`, `APNS_TEAM_ID` (`6P882KH9CZ`); the topic falls back to
  `APPLE_BUNDLE_ID`. Checked from the machine with a made-up device token:
  Apple answers `400 BadDeviceToken` over HTTP/2 in **both production and
  sandbox**, so the key is accepted for TestFlight and for Xcode builds
  alike (a bad key would get `403 InvalidProviderToken`). Not yet delivered
  to a real phone.
- **Off-box backups.** Written, not yet scheduled: `server/scripts/
  pull_backup.sh` copies the newest snapshot to this Mac and keeps six days
  (DEPLOY.md, "Backups", for the launchd install). Fly's own daily volume
  snapshots (five days) are a second layer already running.
- **From the production audit, by hand** (`PRODUCTION_CHECKLIST.md`):
  extend the volume, `fly deploy`, a Sentry DSN (no build has ever reported a
  crash), an uptime monitor on `/health`, the App Store Connect privacy and
  age-rating forms (answers written: 13+), telling the pilot about the
  Privacy Policy change before a DSN build ships (§10 promises an in-app
  notice; none exists), and the CSAM launch items (hash matching,
  SensitiveContentAnalysis). There's no lasting ban: an ended account can
  sign in with Apple again as a new one.
- **Seen in the audit's screenshots, not fixed:** on a 6.1" phone the
  capture sheet's subtitle is cut after one line. (The glass tab bar losing
  its ink over photos, seen here and in build 28, is fixed in build 31.) The World screenshot carries PBS's real
  election-day headlines.
- **QA audit** (November 4, 2026, build 30; `docs/qa-2026-11-04/QA_AUDIT.md`
  with screenshots): fixed the app rotating (the portrait-only key was a
  build setting that never reached Stanley's own Info.plist; it's in the plist
  now), the empty Today's camera falling behind the tab bar (it's inside the
  sheet now), the username check's low-contrast orange and green, and the
  circle never reloading after launch (now on Today's pull and tab tap,
  Settings, and coming to the front, with the Settings circle picker that had
  been documented but missing). What it left open, build 31 fixed: the
  circle gate restyled as the journal's first page, the empty Today short
  enough to clear the tab bar, the capture sheet's photo fitted so nothing
  starts under its footer, and the tab bar on a floor of its own
  (screenshots in `docs/qa-2026-11-04/build31/`).
- **HCI audit** (November 4, 2026, build 32; `docs/hci-audit.md`, screenshots
  in `docs/hci-audit/`): a heuristic evaluation, Nielsen's ten plus IA,
  gestures, emotional design and accessibility; 19 findings, 14 fixed.
  Fixed:
  - errors no longer close sheets (above);
  - the capture sheet can't be swiped away after the shutter, and Not now
    asks before discarding;
  - the note editor waits for the server and opens with the keyboard up,
    and it and the journal entry sheet hold against a swipe while edited;
  - small capitals (`SmallCaps`) and the World tab's small type follow
    Dynamic Type;
  - light mode's `.secondary` is the system gray at 75% (4.6 to 4.9:1 on
    every mood's paper, from 3.2), set inside each tab by `darkRoomInk()`
    with a single ink above the tab bar so the selected tab keeps its
    accent;
  - photos are described to VoiceOver ("Photo by Theo, fading") with Like
    and Hold actions;
  - About Stanley has "How it works", and onboarding's second page says to
    tap the bookmark;
  - Held's long-press menu offers Rest on a phone too;
  - "too_soon" and "circle_full" say what to do.
  Open:
  - the note editor, report sheet, profile editor and place picker are
    still system forms;
  - Today's first photo starts low under the board and the question.
  Fixed in build 33: inviting someone was two levels into Settings, and
  Spring's and Warm's accents were 2.5:1.
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
  circle gates, and the app lock. Welcome and the spinner used to leave a
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
- **The World Today's terms.** Google's feed says it is for "a personal feed
  reader for personal, non-commercial use". PBS's and the BBC's feed terms
  haven't been checked. All three are acceptable for a closed pilot as a
  judgement call, and need revisiting before any wider release. Google's
  local feeds for towns outside the US use a guessed `hl=en-XX` region
  and are unverified past London.
- **Phase 2 / deferred by design:** on-device Returned selection model; CSAM
  hash-matching + NCMEC path (required before any *open* release, §15); R2 actually
  switched on; Android, video, DMs (permanent non-goals for the pilot).
  Multiple circles per user was one too, until build 17.

## Tests

**424 passing** (`cd server && .venv/bin/python -m pytest`). Strong coverage of the
hard logic: physics (Hypothesis property tests across DST/timezones), full decay
lifecycle at exact boundaries, A1/A2, deletion cascades, block bidirectionality,
likes-no-count, Returned priority/dismiss/rest/tombstone, the circle's board
(a note each, newest first, edits in place, only your own to change or take
down, gone at the end of its author's day with or without the sweep, blocks
both ways, leaving takes yours, no counts, 200 characters, reporting with a
copy of its words, and the old single note moved across), shared
moments, mosaic windows, tags, milestones, auth hardening + SIWA, FK enforcement,
capture-race/orphan-blob safety, backups, nameless-vs-departed naming,
`new_account` on the first sign-in only (dev and Apple), push (both notices
off until asked for, tokens registered, refused, moved between accounts and
removed on sign-out and deletion, delivery only after commit, a failed
delivery never failing the sweep, dead tokens dropped, the exact APNs
request and signed provider token, logging only without a key), renaming a
circle (organizer only), the Terms and Privacy pages (public, plain, the
same words as the app's, every numbered section present), account deletion
(nothing of the person left, a reported story stopping neither its photo's
deletion, its purge nor its author's account deletion), the app's safety
controls (your own blocks listed and never who blocked you, the owner alone
told whether deleting gives the day back, no reporting a story you couldn't
have read), report alerts (one fixed line after the commit, nothing without a
URL or for a refused report, a failing webhook never costing the report, the
URL never logged, and an autouse guard failing any test that would reach
ntfy), multiple circles
(the day, the gap and the redo per circle, the per-circle UNIQUE, Today and
capture follow the header and default to the first circle, a circle you're
not in refused rather than swapped, five and no more, gestures across your
circles, Held naming each circle, profiles and blocks across a shared
circle, one digest a day however many circles, and the build 16 database
rebuilt with its rows and references intact), the
World Today (PBS for the US and the unlocated, BBC elsewhere, a town's Google
feed and what isn't a town, one upserted row per edition, last-good-set on
failure, stale silence, fetch-when-due on request, the town cap and
forgetting, keyed by town not person, summaries kept or dropped per feed,
normalization, no key sent, a hostile or oversized feed refused), capture filters (the name kept, an
unknown one dropped without refusing the photo, purged on delete, exported),
commit-before-response (capture commits before the background original
store; every route's session is function-scoped), and the production audit
(`test_production.py`: rate limits per address and per person, Fly-Client-IP
trusted only on Fly, security headers everywhere, no CORS, docs hidden, a
bare 500, `/health` failing with the database, token refresh, control and
bidi characters dropped, blank stories refused, oversized fields refused,
bad time zones never kept, files judged by their bytes, decompression
bombs, the word filter on every field a circle reads and never on reports,
ordinary words passing, Today's pages adding up to the whole feed with
moments unsplit, a failing digest not undoing the sweep, an unknown zone not
stopping digests, the disk warning, VACUUM, each hot query's index, event
lines without anyone's words, Held's faces, the moderation tool, and 240
concurrent requests on a file database), and the journal (`test_journaling.py`:
an entry only its writer can reach, never in the feed beyond the owner's
flag, bounded, cleaned and filtered, fading with the photo unless its owner
held it, gone with a delete, a purge or a let-go; a reflection filed under
its writer's week, Sunday after midnight included, one a week, paged,
private, never fading, with only the writer's own surviving photos; the
same question for the whole circle, forty weeks without a repeat, answers
sealed to the second and then open to everyone, closed once open, nothing
counted, blocks both ways, the circle journal from the week you joined,
reporting an answer only once it's readable, account deletion and export,
the writing rate limit, no notification, and the older database's report
column).
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
- Notifications policy: `notifications.py`; APNs: `apns.py`; report alerts (ntfy): `alerts.py`; Terms and Privacy copy: `legal.py`
- Writing things down (build 26): the weeks and the forty questions
  `journal.py`; routes `routes/journal.py`
- The production audit: rate limits `ratelimit.py`; text cleaning `text.py`;
  word filter `wordfilter.py` + `blocklist.txt`; the operator's moderation
  tool `moderation.py` (`python -m stanley.moderation`)
- Auth: `auth.py` (JWT), `apple.py` (SIWA verify)
- Storage + signed URLs: `storage.py`; image pipeline: `images.py`; backups: `backup.py`
- Routes (`server/stanley/routes/`): `auth_routes.py`, `circles.py`, `photos.py`,
  `feed.py`, `me.py`, `journal.py`, `memories.py`, `safety.py`, `blobs.py`, `news.py`
- Tests: `server/tests/`; deploy notes: `server/DEPLOY.md`; seed/dev tools:
  `server/scripts/seed_demo.py`, `server/scripts/dev_timetravel.py`;
  App Store screenshots `server/scripts/seed_screenshots.py` + `scenes.py`
  (output in `ios/AppStoreScreenshots/`); ops `server/scripts/
  integrity_check.py`, `pull_backup.sh` + `com.stanley.pull-backup.plist`,
  `set_countdown.py` (the one circle's countdown)
- Production status of every audit item: `PRODUCTION_CHECKLIST.md` (repo root)

**iOS** (`ios/Stanley/`)
- App entry / root / tabs / flash / atmosphere tint: `StanleyApp.swift`
- State + API calls: `AppState.swift`; HTTP client: `APIClient.swift`; models: `Models.swift`
- Screens: `WelcomeView.swift` (sign-in), `TodayFeedView.swift` (the journal,
  circle switcher, day marks, prints, moments, mosaic card, returned card),
  `NoteBoard.swift` (build 27: the circle's board, a sticky note, the note
  editor, every note in a sheet, the tape), `CaptureView.swift` (prompt, who-was-there, the framed
  preview + filter pills), `Framing.swift` (move and scale, the crop
  arithmetic both crops share), `PhotoFilters.swift` (the four
  looks, `FilterRenderer`), `Places.swift` (place picker, favorites,
  `PlaceBook`), `LibraryPhoto.swift` (a library photo read upright, small,
  with its own location), `SetupView.swift` (a new account's four steps),
  `Whereabouts.swift` (location permission, one fix, names
  from Apple's geocoder), `WorldTodayView.swift` (the World tab, stories
  that open in place, Safari),
  `SafetyViews.swift` (photo and story menus, report sheet, Block,
  Blocked), `Mentions.swift` (@mentions: parsing, tones, `StoryComposer`,
  `MentionBar`), `Paper.swift` (the paper grain, `.paperPage()`),
  `Journal.swift` (the journal's look: masthead, rules, small capitals,
  prints, paper inserts; `DarkRoom`, the dark mode's colors and rules),
  `Countdown.swift` + `CountdownRoute.swift` (build 35: one circle's
  countdown, its phases and the route under Today's dateline; build 36:
  the flip clock and the day's reminder slip),
  `MemoriesView.swift` (Held + Rested), `ProfileView.swift` (You +
  milestones), `Writing.swift` (build 26: the journal entry slip and sheet,
  the question slip, answers and circle journal, the Sunday card, the
  reflection sheet and pages), `SettingsView.swift` (the five groups, invite code, circle
  name, the Quiet switches), `AboutView.swift` (About Stanley, About Your
  Account), `Legal.swift` (Terms and Privacy, from `legal.py`), `Push.swift`
  (permission, the APNs token, `AppDelegate`), `CircleGateView.swift`
- Components: `UIComponents.swift` (avatars, face cluster, faces sheet, share,
  `WideButton`), `Haptics.swift` (the five gestures' haptics, the shutter),
  `TabTaps.swift` (a tap on the current tab: to the top, or refresh),
  `SignedImage.swift` (every photo and face behind a signed
  link, renewing it when it runs out; `PhotoMemory`), `AvatarPicker.swift` (choose, Move and Scale, upload), `Atmosphere.swift` (also `ChoicePill`), `Prompts.swift`, `AppLock.swift`,
  `Keychain.swift`, `Trail.swift` (the crash report's fixed-word trail),
  `Acknowledgements.swift` (open-source notices)
- Project gen: `ios/project.yml` (run `xcodegen generate` after adding files)
- App icon: since build 23 a bookmark, the hold's own mark, sketched as one
  thin pen line in dark brown ink (#3B2F25) on the journal's cream
  (#F6F0E4): an outline, never a fill, a little off true as a hand draws,
  with a lighter crease across the top. It was a white sun on amber. The
  design lives in Figma ("Stanley App Icon",
  https://www.figma.com/design/mRCswvhBMwH2dmIWqRCzjO, the frame "App Icon
  / 1024", one editable vector per pen stroke); its 1x PNG export is kept
  at `ios/Design/AppIcon-1024.png`, and `ios/Tools/make_app_icon.py --from
  ios/Design/AppIcon-1024.png` cuts every size from it into the asset
  catalog (run with the server's venv, which has Pillow). Without `--from`
  the script draws the same bookmark itself, with a seeded wobble, so the
  icon can be regenerated with no Figma at all.

## Working with this repo

- Run the server (dev): `cd server && STANLEY_DEV_AUTH=1 STANLEY_SECRET_KEY=dev .venv/bin/python -m uvicorn --factory stanley.main:create_app`
- `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (xcode-select points at CommandLineTools on this machine).
- After changing the physics constants, the decay timeline, or any locked rule,
  re-read this file's "Locked design rules" — those changes are product decisions.
