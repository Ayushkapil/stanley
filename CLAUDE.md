# Stanley — One Day, One Photo

## What it is

Stanley is a small-circle photo app built on two structural laws: each person may
post **exactly one photo per day** in each circle they're in, and every photo **decays out of existence
within six days unless someone deliberately keeps (anchors) it**. The only social
gestures are *holding* (a private act of keeping, never counted) and
*story-comments* (co-remembering). The product's identity lives as much in what it
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

## Implemented and working

Backend and iOS unless noted. All guarded by the test suite where testable.

- **Capture** — one-a-day, 12h gap, EXIF-stripped, claim-slot-then-upload (no
  orphan blobs), caption ≤2000. The shot opens a preview with the filter pills
  under it, then Post; nothing uploads until Post. Today's photo is taken from
  a **floating camera button** (`CaptureButton`): a 56pt solid disc of the
  accent with the camera in the palette's ink (on Auto, black on warm white
  in dark mode, cream on charcoal in light; it was a gray-looking disc pilot
  users called outdated, and Liquid Glass turned Auto's white gray again, so
  it's solid). On a standard iPhone it floats bottom right above the tab bar.
  On the Duo's cover, where iOS 27 stands the tab bar on its side as a dock,
  it sits in the dock's column just above it (build 16; it had been beside
  the dock). `SideDockReader` finds the dock by shape, not by a private class
  name: UIKit gives a side tab bar the whole 69pt strip, and the visible dock
  is a glass view inside the tab container (48×262pt on the Duo). Not found,
  or a bottom tab bar, means the bottom-right camera. `HomeView` draws the
  Duo camera, over the tab bar, because inside Today, over that strip, it
  never saw a tap. It stays put while Today scrolls. It's dimmed, not
  hidden, while a queued capture holds the day. It hides while the keyboard
  is up: a safe-area inset rides above the keyboard and would sit on the
  story field's Add button. The sheet (build 15) is laid out like composing
  a memory: before the photo, an empty rounded frame holding the day's
  prompt (tapping it opens the camera) and the rule in a line beneath;
  after it, the photo with 20pt corners. Both are `PhotoShape` (3:4, the
  camera's own 4:3 held upright; build 17), as wide as the sheet allows and
  no taller than 55% of the screen, so the place and the pills show on the
  Duo's cover. **The frame is the crop** (build 17): a photo of another
  shape (most library photos) fills it and drags to choose what's in it,
  and any photo pinches in closer (`Framing.swift`, the same arithmetic as
  the avatar crop). "Drag to frame it" shows until it's moved, and thirds
  while it moves. On Post the look goes on at full size and then exactly
  the frame is cut from it (`FilterRenderer.jpeg(_:_:crop:)`), so what's
  posted is what was framed; a camera shot left as it came posts the
  camera's own JPEG untouched. With more than one circle the sheet says whose
  day it is ("for Climbing Club"). **Where it was** sits right under the photo (build 16; on the card
  below the pills it was out of sight on the Duo's cover), then the filter
  pills, then the caption card, then who-was-there. The foot of the sheet
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
- **Today feed** — reverse-chronological, ambient fade rendered client-side from
  `decay_progress` (smoothstep, dark-mode-aware floor). Since build 17 it's a
  **shared journal, not a card feed** (pilot users said it was "just
  Instagram"). The circle's name is the page's title (`CircleSwitcher`). The
  community note is a sticky note on the first page. Each day has a mark,
  "Today", "Yesterday", then the weekday, with the date (`JournalDay`,
  `DayMark`). Each photo is a **print**: the photo is the whole card,
  `PhotoShape` 3:4, filled and clipped, never letterboxed, with 14pt corners
  alike all round and no frame or header bar. It lies up to 0.9° off square,
  decided by its id (`PrintTilt`). The poster's first name and the time are
  written in Noteworthy (`Font.hand`) on a soft dark capsule in its
  bottom-left corner; a tap opens their profile. The bookmark and the heart
  sit in its bottom-right corner. Caption, place, who was there, the first
  story and "What do you remember?" sit beneath with no chrome. A shared
  moment is a run of prints under its place, written by hand. The mosaic and
  Returned keep their cards; they're artifacts, not entries. On an ordinary
  iPhone the tab bar folds to the current tab while Today scrolls down
  (`tabBarMinimizeBehavior(.onScrollDown)`, iOS 26+; not on the Duo's side
  dock, which the camera is placed against).
- **Decay engine** — server-authoritative state machine, idempotent sweep,
  append-only audit log, 7-day tombstone, purge with blob deletion.
- **Held (anchoring)** — press-and-hold to keep (bookmark), owner-only "held by"
  faces, full-saturation archive, tombstones, "Held" tab + per-friend threads.
  Held gathers every circle a person is in; each memory carries its
  `circle_name`, shown as a small tag (`CircleTag`) once there's more than
  one circle to tell apart.
- **Likes** — double-tap heart, owner-only faces, decays with the photo. The
  heart bottom-right of each photo (the bookmark beside it, on the photo too,
  since build 17) is *your own* state only (filled if you
  liked it), never a signal to anyone else and never a number. Since build 12
  it is also a button, because real users reached for it, and a tap does what
  a double-tap does.
- **Gesture icon size** — the heart and the bookmark share one size,
  `GestureIcon`: a 22pt glyph (about 24pt tall, roughly 40% up from build 11)
  inside a 44pt target, through `@ScaledMetric` so it follows Dynamic Type.
  It applies on Today's prints, shared-moment prints, the story sheet, and
  Returned's "Keep this". Each marker's whole 44pt square takes a tap.
- **Story-comments** — flat, chronological, part of the artifact. Today shows
  the first one on the card; the rest sit behind "More stories" (never "2
  more" — a tally is still a count) which opens the photo with the thread.
  Every story line is `StoryLine.text`: the name **bold** in the primary
  color, two spaces, the words in the secondary color, so two people's lines
  never run together. The empty field asks "What do you remember?"
  (`StoryLine.prompt`; it used to say "Add to the story…", which read like
  Instagram Stories).
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
  one on screen is remembered per account; leaving it brings up another, or
  the gate if none is left. A sixth is `too_many_circles`, said in words.
- **Profiles** — display name, username, multi-line bio, avatar (soft-square,
  crop), member profiles (A2-safe: name + words + face only). The You tab's
  circle, under "Your circle" and its name, is a scrolling row of small cards
  (`CircleCards`, build 17): face or initial, name, a quiet "organizer" mark
  on whoever started it, on the atmosphere's card surface. Each opens that
  person's profile. **Setup**
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
- **Community note** — one shared line atop Today, last-writer-wins, clears at end
  of the setter's local day. Not a chat. Drawn as a sticky note (build 17):
  yellow paper, a strip of tape, a slight tilt, the words in a hand; a lamplit
  yellow in dark mode. Empty, it's a slip asking for a note.
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
  (#F8F6F1) and white cards in light mode, true black and a #1A1A1A card in
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
  "terrible" and "artificial". Ambient only; never affects function.
- **Errors in Stanley's voice** — no status code, server `detail` string or
  system description ever reaches the screen. `APIError` maps every server
  code and bare status to a sentence; `AppState.words(for:)` covers the rest
  (unreachable, undecodable, Apple sign-in). A failed upload says the day is
  still open, which is true: the server rolls the whole request back. No
  signal never fails at all — it queues. A sign-in the server turns down
  (a bare 401 on a request that carried a token: expired, secret rotated,
  account gone) signs out **automatically**. `APIClient.onTokenRejected`
  hands `AppState` the token that was refused, and the app signs out only if
  that's still the token it holds, so a late answer can't undo a fresh
  sign-in. It says why once (`APIError.signedOut`), and every other failure
  from the same cause stays quiet. It used to say "Sign out in Settings",
  which the name and circle gates can't reach.
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
  **Reading in place** (build 15): a card shows the headline, outlet and
  time; a tap opens it where it is, with the full headline, the summary, and
  a small "Read full article ↗" that opens `SFSafariViewController`. Several
  can be open at once. A local story opens to its headline and the link.
  Safari is presented by UIKit over whatever is on top (`StoryReader`): as a
  SwiftUI sheet, its Close forced a second dismissal that closed what was
  beneath it too. A quiet card at the top asks once for location ("News from
  near you", Allow location / Not now) before the system sheet; "Not now"
  puts it away for good. Subtitles use the real count ("12 stories from PBS
  News Hour, refreshed every half hour"), the edition's size, not a tally of
  anyone. No likes, saves, shares, comments or notifications. News never
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
- **Build 17** (0.2.0) is committed but not archived; the archive below is
  build 13's.
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
- **Fly deploys.** Release v7 (2026-10-30 21:43 UTC) runs the server as of
  `0f07d54`: filters, commit-before-response, `UNNAMED`, the digest wording,
  and the NewsAPI version of the World Today, which never fetched because
  `NEWS_API_KEY` was never set. The news changes of builds 14 and 15 need
  `fly deploy` from `server/`. No secret. On startup `ensure_schema` drops
  `news_cache` and `create_all` adds `news_editions`; PBS then fills within
  seconds (`news refreshed: 12 stories for national:us` in the logs). Fly's
  outbound HTTPS to news.google.com was checked from the machine (200);
  pbs.org and feeds.bbci.co.uk were checked from this Mac only. Build 15's
  app also calls `/news/nearby`, which v7 doesn't have: against v7 the World
  tab shows nothing at all, so deploy before testers get build 15. Build
  16's server change is one field, `new_account` on sign-in; without it a
  new account that Apple gave a name skips setup and goes straight to the
  circle gate, as before. **Build 17's server** is multiple circles, and on
  first startup `ensure_schema` **rebuilds the photos table** to make the
  day's slot per circle (`_rebuild_photos`: SQLite's documented rebuild in
  one transaction, foreign keys checked before it commits; on failure
  nothing changes and the slot stays per person). Run on the dev database
  with real data (18 photos, 6 holds, nothing dangling) and in tests. Take a
  manual backup of the Fly volume's `stanley.db` before that deploy. Build
  17's app against an older server still works with one circle: `GET
  /circles` 404s and it falls back to `/circles/mine`.
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

**270 passing** (`cd server && .venv/bin/python -m pytest`). Strong coverage of the
hard logic: physics (Hypothesis property tests across DST/timezones), full decay
lifecycle at exact boundaries, A1/A2, deletion cascades, block bidirectionality,
likes-no-count, Returned priority/dismiss/rest/tombstone, community note, shared
moments, mosaic windows, tags, milestones, auth hardening + SIWA, FK enforcement,
capture-race/orphan-blob safety, backups, nameless-vs-departed naming,
`new_account` on the first sign-in only (dev and Apple), multiple circles
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
- Screens: `WelcomeView.swift` (sign-in), `TodayFeedView.swift` (the journal,
  circle switcher, day marks, prints, moments, mosaic card, returned card,
  sticky note), `CaptureView.swift` (prompt, who-was-there, the framed
  preview + filter pills), `Framing.swift` (move and scale, the crop
  arithmetic both crops share), `PhotoFilters.swift` (the four
  looks, `FilterRenderer`), `Places.swift` (place picker, favorites,
  `PlaceBook`), `LibraryPhoto.swift` (a library photo read upright, small,
  with its own location), `SetupView.swift` (a new account's four steps),
  `Whereabouts.swift` (location permission, one fix, names
  from Apple's geocoder), `WorldTodayView.swift` (the World tab, stories
  that open in place, Safari),
  `MemoriesView.swift` (Held + Rested), `ProfileView.swift` (You +
  milestones), `SettingsView.swift`, `AboutView.swift`, `CircleGateView.swift`
- Components: `UIComponents.swift` (avatars, face cluster, faces sheet, share,
  `WideButton`), `AvatarPicker.swift` (choose, Move and Scale, upload), `Atmosphere.swift` (also `ChoicePill`), `Prompts.swift`, `AppLock.swift`,
  `Keychain.swift`
- Project gen: `ios/project.yml` (run `xcodegen generate` after adding files)

## Working with this repo

- Run the server (dev): `cd server && STANLEY_DEV_AUTH=1 STANLEY_SECRET_KEY=dev .venv/bin/python -m uvicorn --factory stanley.main:create_app`
- `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (xcode-select points at CommandLineTools on this machine).
- After changing the physics constants, the decay timeline, or any locked rule,
  re-read this file's "Locked design rules" — those changes are product decisions.
