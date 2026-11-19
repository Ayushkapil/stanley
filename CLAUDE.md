# Stanley — One Day, One Photo

## What it is

Stanley is a small-circle photo app built on two structural laws: each person may
post **exactly one photo per day** in each circle they're in, and every photo **decays out of existence
within six days unless someone deliberately keeps (anchors) it**. The only social
gestures are *holding* (a private act of keeping, never counted),
*story-comments* (co-remembering), since build 26 the circle's *question
of the week* (answered privately, read together) and, since build 42, a
monthly *letter to the circle* (unsigned, opened together). Beside the circle, since build 45,
each person has a private **journal kept as a book** (their own pages, what they've held, letters opened,
weekly reflections; since build 54 the Journal tab opens to its covers, one journal to a page, yours and then one
for each circle, each over a photo you kept), which nobody else ever sees
unless they choose to share a page: since build 51 a page can be put in the circle's **shared journal**, read there as
facing pages, two people's pages from the same day, and since build 52 shared with **one person** in the circle instead.
Also since build 52 a person may fill one of **five unlabelled dots** for their day, kept for them alone; since
build 65 each month is an **answer sheet**, a row a day, and only today's row takes a mark (since build 72 on a
screen of its own in the Journal tab, in no journal: there are several books and one set of days). The product's identity lives as much in what it
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
- **Notifications are almost nothing.** Six exist (the sixth, **Written
  to You**, at the end of this rule: build 57's Journal Entries as
  narrowed in build 59), and all but that one are **off until
  the person turns them on** in Settings → Quiet (Written to You is on
  until turned off, build 60; iOS's own permission still has to be
  given): the owner's single
  LAST_LIGHT notice for their own photo, at most one evening digest a day
  ("Something new from your circle today.", when someone else in one of
  their circles posted), since build 37 **Circle Posts** ("Ruby shared a
  moment", each time someone else in the circle a photo went to posts it),
  and since build 39 **two reminders a person sets for themselves** (a
  product decision, 2026-11-11; §10 N6 in `notifications.py`): "Leave a
  note for your circle today" and "Your circle is waiting for today's
  moment". Each goes at one of four hours of the person's own day that
  they pick (9, 14, 18 or 21; note defaults to 9, photo to 18), at most
  once a day, and only while it's still true (no note of theirs on any
  board today; no photo of theirs in any circle today). They are the
  first notices that ask for something, which every earlier round
  refused: they exist because the person asked for them, go only to that
  person, and say nothing about what anyone else did.
  No notification may carry a count, deadline, countdown or image, and only
  Circle Posts carries a name: the poster's, to their own circle, and
  nothing else about the photo. **Build 37's notice is a product decision**
  (2026-11-07, asked for twice; it's §10 N5 in `notifications.py`): until
  then no round had added a notification and none carried a name. It never
  goes to the poster, across a block either way, or twice for one person's
  day in one circle (a retake after the redo is quiet), and it's handed to
  Apple only after the post's response, so posting never waits on a push.
  **Written to You, build 59, a product decision that narrows build
  57's** (the brief of 2026-11-14, "Reverse one locked rule, narrowly";
  §10 N7 in `notifications.py`). **It supersedes both the Phase 2
  shared-journal brief's "no notification when someone shares" (build
  51) and build 57's notice for every page in a circle's journal; it is
  not a contradiction of either, it replaces them.** The rule now:
  - **Whole-circle shared journal pages never notify anyone.** The
    circle's journal is ambient: you go to it, it doesn't pull you.
    (Build 57 sent "{name} wrote in {circle}" to the circle; that's
    gone, and a test says nobody hears of such a page.)
  - **A page shared with one person notifies that person only**:
    "{name} wrote you a page".
  - **A sealed letter to a person notifies its recipient**: "{name}
    sent you a letter", when it's sealed (its day may be a year off;
    the envelope says when). Letters to the circle are unsigned and
    never notify: a notice would have to say, or would give away, who
    wrote one.
  - **A private page notifies nobody**, the writer included.
  - **Counts are still never shown**, in a notification or anywhere
    else: the words are a name and what they did, nothing of the page
    or the letter, no number, no "new" with a count.
  It's one switch, "Written to You" in Settings → Quiet, and **since
  build 60 it is on until the person turns it off** (a product
  decision, Ayush, 2026-11-14: iOS's permission prompt is already an
  opt-in, and a second, off-by-default switch would be found by almost
  nobody). `users.written_to_you`: null is never chosen, which is on;
  a new column, so everyone already here got the default once (build
  57's `journal_posts_enabled`, off for everyone, is no longer read;
  the API field keeps that name). **When iOS is asked** (build 61): at the
  first moment the value is concrete, never on launch or on opening a
  tab, behind a soft sheet of Stanley's first (`AskToNotify`, below). Never to
  the writer, across a block neither way, nothing for a rewrite in
  place or a page made private. **A page is quiet while the recipient
  has muted the circle it's in** ("Mute Pages Written to You" in
  Settings → Circle, or the journal's cover; `memberships.
  journal_muted`). **A letter answers to no circle's mute** (build 60:
  it's from a person, not a circle); only the switch quiets it. **At
  most one an hour from each sender to each recipient**, pages and
  letters together: a second inside the hour is skipped, never stacked
  or summed. A tap opens the page or the letter. It carries a name, as
  Circle Posts does.
  Likes, holds, stories, mentions and notes still notify nobody. Build 18
  made them real pushes (APNs, `apns.py`) and, because of that, made the
  digest opt-in (it had gone to everyone back when it was only logged). A
  brief asking for "3 new moments today" was kept to words: the count would
  break this rule.
- **The subject wins on deletion.** Owner delete purges the image everywhere;
  anchorers keep an honest tombstone ("a memory was here") plus their own comment
  text only. **One lag, from build 40's widget** (it follows from the brief:
  a widget that shows the circle's photos and makes no network calls can't
  hear about a delete): a small copy on a friend's phone can stay in their
  Home Screen widget until they next open Stanley, a day at most
  (`WidgetSnapshot.photosKeep`). Both documents say so. It was not asked
  about as a product decision; shorten the constant, or leave other
  people's photos out of the widget, if a day is too long.
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
  filter covers all three. **The pages of the journal** (build 45, from
  the brief of 2026-11-14) are the same kind of thing: a page a day in the
  person's own words and ink, and the name they give the journal, are in
  no payload anyone else is sent, and every route about one answers 404 to
  anyone but its writer. A page never fades; one a day, the day being the
  writer's own, and writing again replaces it. **The word filter is not on
  pages or the journal's name**: it's for what a circle reads, and a
  private diary that refused its writer's account of their day would
  protect nobody (hold notes are the same). Not asked about as a product
  decision; put `refuse_objectionable` back in `routes/journal.py` if it
  should be otherwise. Nothing about the book counts anything (no streak,
  no "pages written"); a page's number is its place in the book.
  **One way out, the writer's own** (build 51, a product decision: the
  brief of 2026-11-14, "Phase 2"): a page its writer shares with a circle
  is read by that circle, in its shared journal. Until they do, and again
  once they take it back, everything above holds: a page that isn't
  shared is in no payload anyone else is sent.
- **The shared journal is a book, not a feed** (build 51, from the same
  brief). A shared page is still the day's one page and still in its
  writer's own book; it's in one circle's shared journal at a time. Each
  day there is facing pages: who faces whom is a pure function of the
  day, the circle and who wrote (`journal.pairings`), the same for every
  member. **One heart per reader per page**, left or taken back at the
  foot of the page: the writer is shown who, as faces, never a number,
  and nobody else is shown anything (the photo payload's A2, again). **No
  comments**, **no notification when someone leaves a heart**, and
  **none when a page lands in the circle's book** (build 59, superseding
  build 57's notice; the notifications rule, above), and
  **a shared page never fades**. The word filter is on shared pages (a
  circle reads them) and still not on private ones. Leaving a circle, or
  being removed, takes your pages out of its book and leaves them in
  yours. A shared page can be reported like a photo; the operator's
  takedown puts it back to private, it doesn't delete someone's journal.
  A member reads the book **from the day they joined**, as with the
  circle's questions; not in the brief, and not asked about.
  **A page for one person** (build 52, a product decision: the brief of
  2026-11-14, "Redesign the Journal tab", part 2): a page can be shared
  with one member of the circle on screen instead of all of it
  (`journal_pages.recipient_id`). Its writer and that person read it,
  nobody else; it's a page of its own in their two books, never paired;
  only the recipient can leave the heart, and the writer sees it as a
  face. The word filter is on it (someone else reads it). It goes back
  to its writer's alone if either leaves the circle or the recipient's
  account is deleted. No replies. Since build 59 it notifies the one
  person it's for, if they asked (the notifications rule, above; until
  then it notified nobody, then, in build 57, them alone too, with the
  circle's name). **This edges toward
  the DMs that are a permanent non-goal for the pilot** (open items): it
  is a page, not a conversation, and nothing answers it but a heart; the
  brief asked for it, and the line should be held there.
- **A journal's cover never says anything about anyone's keeps** (build
  54, a product decision on 2026-11-14). The brief asked for each
  journal's cover to be its most-kept photo; that ranks photos by keeps
  and would let a circle see which was kept most, so a cover is **the
  reader's own newest keep** in that journal (anywhere, for their own
  book), worked out on the server for each reader (`sharing.cover`,
  `cover_photo_id` and a signed `cover_url` on `GET /circles` and `GET
  /me/journal`). With nothing kept, the journal's newest photo still in
  its public life (build 56: the circle's for its journal, your own for
  yours), never a faded one. Nothing reads or ranks anyone else's keeps,
  and no keep is counted. A photo its poster deleted, or one across a
  block, isn't a cover. **Asked for again in build 56's brief and kept
  this way**, said to Ayush. **Asked a third time in build 76's brief
  ("Use most kept photo") and kept again, by Ayush's own answer
  (2026-11-16)**, which also changed whose a circle's cover is: since
  build 76 **a circle's journal's cover is the circle's newest photo still
  in its public life, the same for everyone in it** (but across a block),
  and no longer the reader's own keep; your own book's is still your own
  newest keep, **or a photo you chose from your library** (build 76, yours
  alone; shared journals have no chosen photo, also Ayush's answer). The
  opened cover's menu says "Use Automatic Photo", not "most kept".
- **The mark on your day is yours alone and never counts anything**
  (build 52, a product decision, the same brief, part 4; **reshaped in
  build 65**, the answer-sheet brief of 2026-11-15). Five bubbles, no
  labels, no numbers, no "1 = bad", in the app or anywhere it's
  described; a tap fills one. **It's the day's, kept in `day_moods`
  alone** (one a day per person; `GET /moods`, `PUT /moods/{day}`):
  since build 65 no photo carries it, its owner's own included, and
  `photos.score` is cleared and unused. **Only today takes a mark, and
  today is the person's own** (the zone the phone sends; 400
  `not_today` for any other day): a missed day stays empty for good,
  nothing fills one in after, and a day to come can't be marked. It can
  be set from the month's answer sheet or under that day's photo, and
  changed or taken back while the day lasts. It's in no payload to
  anyone else, nor in any circle or shared response (tests walk the
  JSON), never notifies, never fades, **stays when a photo from that day
  is deleted or purged** (build 52 took it with a deleted photo; build
  65 made it the day's, not asked about separately), and goes when its
  owner clears it that day or deletes the account. It's a private mark,
  not a count of anything anyone did, so the "No counts" rule stands as
  it was; nothing may ever total, average, streak, trend, compare or
  describe it, and nothing nudges toward a missed day ("the pattern is
  the insight": the sheet's foot shades each day's square by its mark in
  five neutral steps of one ink, and nothing joins or reads them).
- **The board's notes are everyone's own and the day's alone** (build 27).
  One note per person per circle per day, changed or taken down only by its
  author, gone at the end of their day (deleted, not archived). No replies,
  no reactions, no notification and no count of how many there are.
- **A letter to the circle is unsigned, to the circle** (build 42, from
  the brief of 2026-11-13). One a month each, sealed until the month
  is over, then read together for seven days and deleted. A letter leaves
  the server as its id and its words and nothing else: no author, name,
  face, tone, time written or flag saying whose it is, in any payload to
  any phone (`routes/circle_letters.py`; a test walks the JSON). The
  server keeps `author_id` so the writer can change or delete theirs and
  so a reported letter can be acted on, and the operator can see it; both
  documents say so. Three things follow, and none may be "fixed" without
  breaking the anonymity: **blocks don't hide a letter** (block someone,
  see which letter goes); **a letter already opened stays when its writer
  leaves or is removed** (the organizer could remove people to find out);
  and **a month opens at one moment for the whole circle**, the last
  local midnight among its members, not each reader's own (a letter
  arriving late, or changing after others had read it, would say where it
  came from). Those three follow from the brief's "no indication of who
  wrote what" but weren't each asked about as product decisions. Nothing
  says who has written or how many, there are no
  replies or reactions, and nothing notifies.
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
- **Blobs:** in production, **Cloudflare R2** since November 19, 2026
  (`R2BlobStore`, `BLOB_BACKEND=r2` in `fly.toml`; the endpoint, bucket
  `stanley-photos` and keys are Fly secrets; private bucket, no versioning,
  presigned 15-minute links). Local disk (`BlobStore`, HMAC-signed `/blobs`
  links) is the default in dev and tests. No public URLs ever, on either.
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
  story, (build 26) an answer or (build 42) a letter down, with evidence preserved for a photo,
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
  words), so it's November 4. Build 37's Circle Posts changed both (three
  notices, not two; the notice carries your name to your circle), so both
  are November 7. Build 39's reminders made them November 11, and build
  40's widget (small copies of photos kept on the phone; a deleted photo
  lingering in a widget for up to a day) November 12. Build 42's letters
  (unsigned to the circle, not to the server; a block hides none) made
  both November 13. Build 45's journal (its pages, kept for their writer
  alone; the Journal widget's few lines on the phone) made both November
  14.

## Reference docs (read on demand, not loaded every session)

This file holds only what every session needs. The detail lives in files that
are read when the task touches them. Read them on purpose, by section; don't
load them whole into the main thread. Have a subagent search them and return
only the relevant entries.

- [`docs/reference/FEATURES.md`](docs/reference/FEATURES.md): every
  implemented feature, build by build (design language, journal, letters, the
  answer sheet, widget, notifications, safety…). Grep by feature name or
  `build NN`. **Before changing a feature, read its entry.**
- [`docs/reference/OPEN_ITEMS.md`](docs/reference/OPEN_ITEMS.md): what is not
  built or not done yet (deploy, App Store, pilot follow-ups).
- [`docs/reference/TESTS.md`](docs/reference/TESTS.md): what the test suite
  covers, by area.
- `docs/<feature>-buildNN/`: screenshots and notes for individual builds.

**Per-build notes go in `docs/reference/FEATURES.md` (and open items in
`OPEN_ITEMS.md`), never in this file.** Add to this file only when a locked
rule, the architecture, or the repo's way of working changes.

## Tests

`cd server && .venv/bin/python -m pytest -q` (774 passing as of build 79).
Physics uses Hypothesis property tests across DST/timezones; invariants A1/A2,
decay boundaries, deletion cascades and "no counts" are all guarded. Coverage by
area is in `docs/reference/TESTS.md`. iOS: build for the simulator with
`xcodebuild` (see Key file locations).

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
- Build 52: a page for one person (`recipient_id` in `routes/journal.py`
  and `sharing.py`), the mark on a day (`PUT /photos/{id}/score` in
  `routes/photos.py`, `GET /me/moods` in `routes/me.py`, `DayMood` in
  `models.py`, kept through purge in `decay.scrub`); tests in
  `tests/test_journal_build52.py`
- The shared journal (build 51): `sharing.py` (taking pages out of a
  circle's book, who may read one), `journal.pairings` (who faces whom),
  routes in `routes/journal.py` ("The shared journal"), `PageHeart` in
  `models.py`
- Letters to the circle (build 42): the months and when they open
  `circle_letters.py`; routes `routes/circle_letters.py`; opening and
  clearing in the sweep `decay.open_letters`, `decay.clear_letters`
- The journal as a book (build 45): the limits and the day in
  `journal.py` (`PAGE_MAX`, `INKS`, `local_day`); routes in
  `routes/journal.py` ("a page a day"); `JournalPage` in `models.py`
- The production audit: rate limits `ratelimit.py`; text cleaning `text.py`;
  word filter `wordfilter.py` + `blocklist.txt`; the operator's moderation
  tool `moderation.py` (`python -m stanley.moderation`)
- Auth: `auth.py` (JWT), `apple.py` (SIWA verify)
- Storage + signed URLs: `storage.py`; image pipeline: `images.py`; backups: `backup.py`
- Routes (`server/stanley/routes/`): `auth_routes.py`, `circles.py`, `photos.py`,
  `feed.py`, `me.py`, `journal.py`, `circle_letters.py`, `memories.py`, `safety.py`, `blobs.py`, `news.py`
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
  preview), `Framing.swift` (move and scale, the crop
  arithmetic both crops share), `PhotoRender.swift` (upright, preview and crop,
  `PhotoRenderer`; the four filters were here until build 44), `Places.swift` (place picker, favorites,
  `PlaceBook`), `LibraryPhoto.swift` (a library photo read upright, small,
  with its own location), `SetupView.swift` (a new account's four steps),
  `Whereabouts.swift` (location permission, one fix, names
  from Apple's geocoder), `WorldTodayView.swift` (the World tab, stories
  that open in place, Safari),
  `SafetyViews.swift` (photo and story menus, report sheet, Block,
  Blocked), `Mentions.swift` (@mentions: parsing, tones, `StoryComposer`,
  `MentionBar`), `Paper.swift` (`PaperGrainView`, the grain where paper is still drawn),
  `Journal.swift` (build 44: the three surfaces `card`, `creamPaper` and
  `glass`, the photo cut `asPrint`, and before that the journal's look: masthead, rules, small capitals,
  prints, paper inserts; `DarkRoom`, the dark mode's colors and rules),
  `Shared/Countdown.swift` + `CountdownRoute.swift` (build 35: one circle's
  countdown, its phases and the route under Today's dateline; build 36:
  the flip clock and the day's reminder slip; build 74: the flight path,
  the journey card, `CountdownClock`; its rules in `CountdownJourney.swift`),
  `WidgetFeed.swift` (build
  40: what the app leaves for its widget, and the Debug gallery),
  `MemoriesView.swift` (the Journal tab, which is `BookView`; and the Letters sheet's page), `ProfileView.swift` (You +
  milestones), `Writing.swift` (build 26: the journal entry slip and sheet,
  the question slip, answers and circle journal, the Sunday card, the
  reflection sheet and pages), `CircleLetters.swift` (build 42: the
  envelope, Today's two letter cards, the writing sheet, the opened letters
  and their slips), `SettingsView.swift` (the six groups, invite code, circle
  name, the Quiet switches), `AboutView.swift` (About Stanley, About Your
  Account), `Legal.swift` (Terms and Privacy, from `legal.py`), `Push.swift`
  (permission, the APNs token, `AppDelegate`), `CircleGateView.swift`
- Components: `UIComponents.swift` (avatars, face cluster, faces sheet, share,
  `WideButton`), `Haptics.swift` (the five gestures' haptics, the shutter),
  `TabTaps.swift` (a tap on the current tab: to the top, or refresh),
  `SignedImage.swift` (every photo and face behind a signed
  link, renewing it when it runs out; `PhotoMemory`), `AvatarPicker.swift` (choose, Move and Scale, upload), `Atmosphere.swift` (the flat floor, `Look`: Light, Dark, Rain), `Prompts.swift` (the capture's daily whisper; the day it turns by is `LocalDay.swift`, build 64), `AppLock.swift`,
  `Keychain.swift`, `Trail.swift` (the crash report's fixed-word trail),
  `Acknowledgements.swift` (open-source notices)
- The widget (build 40): `ios/StanleyWidgets/StanleyWidgets.swift` (the
  bundle, the timeline, the entry view), and `ios/Shared/`, compiled into
  the app and the extension both (`WidgetSnapshot.swift` and `WidgetStore`,
  `WidgetViews.swift`, and the look the two share: `Countdown.swift`,
  `AtmospherePalette.swift`, `PaperGrain.swift`, `Hand.swift`,
  `JournalColors.swift`, `NotePaper.swift`)
- The journal's pages (builds 45 and 46): `MemoriesView.swift` (the
  tab, and `LettersPage` for the Letters sheet), `Book.swift` (the page's
  size, the kinds of page, `Paginator`, `BookBuilder`, `JournalName`),
  `BookPages.swift` (each page drawn: `BookSheet`, `PageHeading`,
  `InkText`, the blank page's cursor, the tap on today's page, the
  long-press menu, the shared journal's `SpreadView` and its two pages,
  the small pages of the grid), `BookView.swift` (the
  tab: `PageTurner` and `TurnerHost`, `BookEdge` with the ribbon,
  `BookBar` with the marks for Letters and Prompts at the page's foot,
  `BookSwitch` with "Mine", "Ours" and the "+", `BookFoot`, the grid),
  `BookWriting.swift` (`PageWriting`, the ruled text view, the inks and
  the pen in hand, `PageLanding`, build 63's `PromptLine`),
  `WritingPrompts.swift` (build 63: the suggestions and their turn), `JournalCovers.swift` (build 54: the
  cover pager, the slab), `JournalChrome.swift` (build 54: the glass
  circles, the top bar, the "+", the band under the tab bar; build 52's
  `BookCovers.swift` is deleted), `Moods.swift` (build 52: the five
  dots, `MarkSheetScreen` with the month's form and the deck's
  `DaysCard`),
  and in `ios/Shared/` `JournalInk.swift` (`Ink`, `BookPaper`, `BookHand`)
  and `JournalWidget.swift` (the Journal widget's snapshot and views);
  its feed is in `WidgetFeed.swift`, its widget in `StanleyWidgets.swift`
- Project gen: `ios/project.yml` (two targets, `Stanley` and
  `StanleyWidgets`; run `xcodegen generate` after adding files)
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
  (or start `stanley-server` from `.claude/launch.json`).
- `xcode-select` points at Xcode.app, so `xcodebuild` no longer needs `DEVELOPER_DIR`.
  Rerun `xcodegen generate` in `ios/` after adding or removing files.
- After changing the physics constants, the decay timeline, or any locked rule,
  re-read this file's "Locked design rules": those changes are product decisions.
- Another Claude session may be working in this checkout. If `git status` shows
  changes you didn't make, work in a worktree on a `claude/<name>` branch.
- Long, noisy work (the full pytest run, xcodebuild, simulator screenshot loops,
  searches across `docs/reference/`) goes to a subagent (`runner`, `scout`) that
  returns only the result, so the main thread stays short.
