# Stanley — Production checklist

The production readiness audit of November 3, 2026: build 24 (0.2.0), and
the server as of the commit that added this file. Every item says where it
stands:

- ✅ **Good**: already right; checked, nothing changed.
- 🔧 **Fixed**: changed in this audit, with tests (server suite: 359 passing then; 394 on November 4).
- ⚠️ **By hand**: needs someone with the accounts (Fly, Apple, Sentry, an
  uptime monitor). Exact steps are below.

Fly was checked read-only on November 3: release v15 runs the same server
code as `main` before this audit, the full Terms and Privacy Policy are live
(byte-identical to `legal.py` then), `REPORT_WEBHOOK_URL` is set, the volume
is 1 GB with 26 MB used, and the integrity check found nothing wrong. None of
the fixes below are on Fly until the next `fly deploy`.

### Re-checked November 4, 2026 (build 33, before App Store submission)

Every item was checked again, read-only, against Fly, this Mac and the repo:

- **Fly runs release v18**, deployed November 3 at 20:00 UTC. It carries the
  production audit and build 26's journal:
  - HSTS and CSP headers are on `/health`;
  - `/openapi.json` is a 404;
  - `/auth/refresh` and `/me/reflections` exist.
- **v18 doesn't carry build 27's board.** `/circles/{id}/notes` is a 404, and
  `/privacy` still says November 3, not the November 4 wording.
- **The volume is 3 GB**, with 32 MB used (step 1, done).
- **The pre-build-18 snapshot is still on the volume and on this Mac**
  (step 8, due in four days).
- **Not set up yet:** no Sentry DSN, and no off-Fly backup job.
- **Archives:** build 28 is the newest; nothing from builds 29 to 33 is
  archived.
- **Server suite: 394 passing** (395 with the `/support` page, build 34).

Status marks below are updated where they changed. The App Store fields
themselves (description, keywords, age rating, screenshots) are in
`APP_STORE_METADATA.md`.

---

## Do these by hand, in this order

1. ✅ **Done (3 GB, seen November 4; 32 MB used).** About a month of a
   30-person circle at ~3 MB a photo; extend again as it fills (the daily
   `event=disk_low` warning fires at three quarters).
   **Grow the volume before anyone posts in earnest.** At about 3 MB a photo,
   a 30-person circle fills 1 GB in roughly ten days and every post after
   that fails (DEPLOY.md, "Disk").

   ```bash
   fly volumes extend vol_v8eygoljqj2j02kv --size 10 --app server-earnest-stream-9793
   ```

2. ⚠️ **Partly done.** v18 (November 3, 20:00 UTC) has the production audit
   and the journal. **Deploy once more** for the board (build 27) and the
   November 4 Terms and Privacy Policy: until then the app falls back to the
   old single note, and the store's Privacy Policy URL serves the November 3
   wording. Deploy before submitting, so the URL says what the app says.
   **Deploy the server.** It works with every build in people's hands, and
   the other way round: an older app never asks for pages and gets
   everything, as before; the app built from this commit, against today's
   server, gets everything in one page and quietly skips the token refresh
   (a 404 it ignores).

   ```bash
   cd server && fly deploy
   ```

   The same deploy carries build 26's journal: its first start creates four
   tables (`journal_entries`, `weekly_reflections`, `circle_prompts`,
   `prompt_responses`) and adds `reports.response_id` (`ensure_schema`).
   Against today's server, build 26's app quietly shows no question slip, no
   Sunday card and no book on a print.

   And the circle's board (a note each): the first start creates
   `circle_notes`, moves the one live community note onto it as its author's
   note, drops `community_notes`, and adds `reports.note_id`. Builds already
   installed keep working: their `PUT /note` writes the caller's own note,
   and they show the newest note on the board. The Privacy Policy's date
   moves to November 4 with it, so tell the pilot about both changes at once.

   Then check: `curl -sI https://server-earnest-stream-9793.fly.dev/health`
   shows `strict-transport-security` and `content-security-policy`;
   `/openapi.json` is a 404; `fly logs` shows `INFO stanley: backup: wrote …`
   and, after the first sign-up, `event=signup`; and the integrity check
   passes (DEPLOY.md, "Integrity check").

3. ⚠️ **Not done** (`STANLEY_SENTRY_DSN` is still empty in `ios/project.yml`).
   **Turn on crash reporting** (Sentry; no build has had a DSN yet, so no
   crash has ever been reported from anyone's phone):
   1. sentry.io → Projects → Create Project → platform **Apple / iOS** →
      name it `stanley-ios`.
   2. Project Settings → **Security & Privacy**: turn on *Prevent Storing of
      IP Addresses*, *Data Scrubber* and *Use Default Scrubbers*.
   3. Symbols, so crashes come back readable: after each archive, upload its
      dSYMs (`sentry-cli debug-files upload <archive>.xcarchive/dSYMs`, with
      a Sentry auth token in `SENTRY_AUTH_TOKEN`), or add Sentry's upload
      build phase to the target.
   4. Project Settings → Client Keys → copy the **DSN** into `ios/project.yml`
      (`STANLEY_SENTRY_DSN: "https://…"`; a DSN is a public client key, fine
      to commit), then `xcodegen generate`, bump the build, archive, upload.
   5. Alerts → Create Alert → *Issues* → "A new issue is created" → email.
   6. Prove it works once: run a Release build with the DSN on a phone from
      Xcode, pause in the debugger, `expr SentrySDK.crash()`, continue,
      reopen the app (reports go on the next launch), and find the issue in
      Sentry with its trail ("opened Today", …) and no user attached.
   7. Before that build reaches anyone, tell the pilot the Privacy Policy
      changed (see 7).

4. ⚠️ **Not done** (no `com.stanley.pull-backup` in `~/Library/LaunchAgents`).
   **Schedule the off-Fly backup** on this Mac (DEPLOY.md, "Backups", layer 3):

   ```bash
   server/scripts/pull_backup.sh --dry-run
   mkdir -p ~/Library/Application\ Support/Stanley
   cp server/scripts/pull_backup.sh ~/Library/Application\ Support/Stanley/
   sed "s#HOMEDIR#$HOME#g" server/scripts/com.stanley.pull-backup.plist > ~/Library/LaunchAgents/com.stanley.pull-backup.plist
   launchctl load ~/Library/LaunchAgents/com.stanley.pull-backup.plist
   ```

5. ⚠️ **Unknown from here** (an outside monitor can't be seen from the repo).
   **Watch `/health` from outside** (free): uptimerobot.com → Add New Monitor
   → type **HTTP(s)** → name `Stanley` → URL
   `https://server-earnest-stream-9793.fly.dev/health` → interval 5 minutes →
   alert contact: your email, and the UptimeRobot app for pushes → Create.
   Better Stack's free plan does the same at 3-minute checks. `/health` is a
   503 when the database can't be read, so a down database alerts too.

6. ⚠️ **App Store Connect forms.** Everything to paste is in
   `APP_STORE_METADATA.md`.
   - **Support URL:** `https://server-earnest-stream-9793.fly.dev/support`.
     The page exists from build 34 but is a 404 on Fly until the next deploy
     (step 2).
   - One field still needs a decision:
   - **Unrestricted Web Access:** Yes rates the app **16+** in Apple's
     current table; No keeps it at 13+. See "Age rating" below.
   - App Privacy: the click-by-click answers are at the end of
     `PRIVACY_LABEL.md` (Name, Photos, Other User Content, User ID, Device ID,
     Coarse Location, Product Interaction, Crash Data). Privacy Policy URL:
     `https://server-earnest-stream-9793.fly.dev/privacy`.
   - Age rating: the answers are under "App Store requirements" below; the
     result is **13+**, or **16+** with Unrestricted Web Access answered Yes.
   - Screenshots: upload `ios/AppStoreScreenshots/6.7/` to the **6.9"
     display** slot (1290 × 2796 is accepted there) and, optionally,
     `ios/AppStoreScreenshots/6.1/` to the 6.3" slot. Read the caveats under
     "Screenshots" first.

7. ⚠️ **Not done.** Now covers the November 4 wording too (the board).
   **Tell the pilot about the Privacy Policy change** before a build with a
   Sentry DSN ships. The policy now says a crash report carries a short trail
   of what the app did ("opened Held", "posted a photo"), and its section 10
   promises material changes are told "in the app before it takes effect".
   No in-app notice exists yet: either add a one-time note to that build, or
   decide the pilot's group chat is enough and accept that it isn't "in the
   app". The policy's effective date moved to November 3, 2026; the Terms
   didn't change.

   **Build 26 adds to this** (the journal): the policy now also describes
   private journal entries, weekly reflections and answers to the circle's
   question of the week (what's kept, who reads it, for how long, and that
   answers open to the whole circle on Saturday at midnight UTC), and the
   Terms count them as Content, so the Terms are dated November 3 as well.
   That's collecting something new, so section 10's promise applies to build
   26 whether or not it has a Sentry DSN: tell the pilot before it ships.

8. ⚠️ **Not done, due November 8.** Both copies were still there on November 4
   (`/data/pre-build18.db` on the volume, 196 KB, and the copy here).
   **Delete the pre-build-18 snapshot by November 8** (both copies), or the
   policy's "gone from our backups within seven days" stops being true:

   ```bash
   fly ssh console --app server-earnest-stream-9793 -C "rm /data/pre-build18.db"
   rm server/var/fly-backups/pre-build18-20261101.db
   ```

9. **Before any open release:** the CSAM launch items below, and a lawyer's
   read of the Terms and Privacy Policy (not done).

10. ⚠️ **Archive and upload build 33.** The newest archive is build 28
    (November 4, 01:42); builds 29 to 33 (the "+", the biometric lock, the QA
    and HCI fixes, Invite, the accent contrast) exist only as commits. Archive
    from `main` in Xcode → Product → Archive, then Organizer → Distribute App →
    TestFlight & App Store. Build 18 added Push Notifications; automatic
    signing adds it to the App ID.

---

## Security

- 🔧 **Rate limiting** (`stanley/ratelimit.py`, in memory, right for one
  process). Sign-in: 10 a minute per IP address (on Fly, the `Fly-Client-IP`
  the proxy sets; off Fly that header is ignored so nobody can forge an
  address). Photo posts: **10** an hour per person, not the 5 suggested:
  five circles with a photo and a redo each is ten honest posts, and a limit
  must never cost someone their day. Avatars 10/hour, stories 30/hour,
  reports 20/hour (so nobody can flood the operator's phone with ntfy
  alerts). Over the limit is a 429 with `slow_down` and `Retry-After`, said
  in words by the app; a queued photo just waits. Every number is an env var
  (DEPLOY.md), so a pilot kickoff where a whole floor signs in from one dorm
  network can raise the sign-in limit for an evening.
- 🔧 **Input validation.** Every free-text field now goes through
  `stanley/text.py`: control characters dropped (newlines kept where a field
  is multi-line), the bidirectional override characters that let a name
  display backwards dropped, Unicode normalized (NFC), blank-only text
  refused or treated as absent. New caps: the Apple identity token (8 KB),
  invite codes, ids in reports and blocks, the username check's query, push
  tokens, Today's cursor and page size, and "who was there" tags (cut at the
  circle cap; past 1,000 form fields the framework refuses the request with
  a 400). Existing caps kept: captions 2,000, stories 2,000, bios 1,000, names
  80, circle names 80, places 120, notes 200 (the board, build 27; it was
  90), journal entries 1,000, reflections 500, answers 300 (build 26).
- 🔧 **Found and fixed: one malformed time zone could stop decay for
  everyone.** `GET /feed/returned?tz=…` stored any string as the person's
  time zone. The evening digest then failed on it every pass, and since the
  digest ran in the same transaction as the decay sweep, nothing would have
  faded or purged for anyone. Now time zones are checked before they're
  kept (`bad_timezone`), the digest reads an unknown zone as UTC, and the
  sweep commits before the digest runs.
- 🔧 **Photo validation by content, not name.** The first bytes decide
  (`images.sniff`): JPEG, PNG or HEIF only. GIF, BMP, TIFF, WebP, PSD, EPS and
  the rest are refused before any decoder sees them (EPS goes through
  Ghostscript in Pillow, a known attack surface). A photo over 50 megapixels
  is refused from its header: a 12,000 × 12,000 "decompression bomb" used to
  be decoded into 432 MB of memory on a 1 GB machine. Every failure is a 400
  `bad_image`, the day untouched.
- ✅🔧 **Token expiry.** Tokens already lasted 30 days and were refused after.
  New: `POST /auth/refresh` trades a working token for a fresh one, and the
  app asks once a day when it opens or comes to the front, so nobody who
  uses Stanley monthly is signed out by the calendar. An expired token can't
  be refreshed. There's still no way to revoke one token (only rotating
  `STANLEY_SECRET_KEY`, which signs everyone out).
- ✅ **CORS: none, deliberately.** Stanley has no web app, so no browser on
  another site may read its answers. No CORS middleware means browsers
  refuse cross-origin reads; a test checks that no response ever carries
  `Access-Control-Allow-Origin`.
- 🔧 **Security headers on every response** (a plain ASGI middleware in
  `main.py`): `Strict-Transport-Security` (one year), `X-Content-Type-Options:
  nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, a
  `Content-Security-Policy` that allows only inline styles (for `/terms` and
  `/privacy`) and same-origin images, `Permissions-Policy`, and
  `Cross-Origin-Opener-Policy`. Fly already forces HTTPS.
- 🔧 **API docs hidden in production.** `/docs`, `/redoc` and
  `/openapi.json` exist only with dev sign-in on.
- ✅ **SQL injection.** Every query goes through SQLAlchemy with bound
  parameters. The only SQL built from strings is startup DDL from constant
  table names in `db.py`. A test already posts injection payloads and finds
  them stored as text.
- ✅ **EXIF and GPS.** The server keeps only the capture time (an
  allowlist, so GPS can't slip through) on every photo path, and strips
  everything from avatars. On the phone, library photos and avatars are
  re-encoded from pixels, so their metadata never leaves; camera photos are
  stripped by the server. Tests cover both.
- ✅ **Signed links expire.** 15 minutes, an HMAC over the path and the
  expiry, compared in constant time; tampering or an old link is a 403
  (tested). R2's presigned URLs, if switched on, use the same 15 minutes.
- 🔧 **Found and fixed: double taps were 500s.** The concurrency test caught
  holding the same photo twice at once failing with a constraint error. Like,
  hold, block, rest, push-token registration and milestones are now single
  `INSERT … ON CONFLICT` statements; a double join is a 409, not a 500.

## Performance

- ✅ **Photo sizes.** Three already exist: a 320px thumbnail (the mosaic,
  profile prints, Held's small prints, Returned), a 1080px copy (Today and
  Held's big prints) and the full-size original, which is never served. Not
  done: serving 400px in Today. Today shows a photo the full width of the
  screen (1,290 pixels on a Pro Max), and a 400px image would look soft;
  1080 is the size the capture filters are matched against. A 1080 copy is
  about 260 KB.
- 🔧 **Indexes.** Thirteen added where a hot query read the whole table:
  memberships by person (nearly every request), blocks by the blocked
  (every photo), holds by person, the decay sweep's overdue photos, the
  day's redo count, the purge queue, the digest's "already sent today", and
  the account-deletion lookups. Added to the models and created on existing
  databases at startup; a test reads `EXPLAIN QUERY PLAN` for each.
- 🔧 **Today in pages.** `GET /feed/today?limit=20` returns twenty entries
  and a `next_cursor`; the app asks for the next page as the end comes into
  view, and a refresh (after a like, a hold, a story) asks for everything
  already showing in one request, so the page never folds back to twenty
  under someone's thumb. Order is unchanged (time, nothing else); shared
  moments are grouped before the page is cut, so one is never split; only
  the page's photos are serialized. Without `limit` it's everything, so older
  builds keep working. Checked on the simulator: 33 entries, first page of
  20, the rest fetched at the bottom.
- 🔧 **Less work per photo.** Who's blocked is read once per page instead of
  three times per photo.
- ✅ **Image caching on the phone.** Photos are kept in memory by blob path
  (`PhotoMemory`, an `NSCache` capped at 120 MB that empties under memory
  pressure), so renewed links never re-download a photo. Deliberately not on
  disk: a deleted photo shouldn't outlive its deletion in a cache.
- ✅🔧 **Background work.** The sweep's queries now use indexes; the digest
  asks "did anyone post?" with a single-row query instead of loading every
  id. News: one fetch per edition per 30 minutes, cached by edition, on its
  own loop with a timeout.
- 🔧 **Database upkeep.** After the daily backup: `PRAGMA optimize`, and
  `VACUUM` plus a WAL checkpoint on Sundays (`backup.maintain_database`).
- 🔧 **Connections.** SQLAlchemy's default pool (15) was smaller than
  FastAPI's thread pool (40), so a burst queued for connections; it's now
  10 + 30 overflow. WAL lets readers run alongside the one writer, and
  `busy_timeout` makes writers wait their turn instead of failing.

## Reliability

- ✅🔧 **No stack traces reach clients.** FastAPI never sent them (debug is
  off). Now an unexpected error is a JSON 500 with `server_error`, which
  the app turns into words, and one `event=server_error route=<template>`
  line in the log beside uvicorn's traceback.
- 🔧⚠️ **Backups.** Three layers, documented in DEPLOY.md: daily snapshots
  on the volume (now pruned by age as well as count, so a server that was
  down for days can't keep a snapshot past the policy's seven days), Fly's
  daily volume snapshots (5 days), and `scripts/pull_backup.sh` for a copy
  off Fly (⚠️ schedule it, step 4).
- 🔧 **`/health` reads the database.** It answers 503 `{"status":
  "unavailable"}` when a read fails. Still one indexed read, cheap enough for
  the app's 8-second offline polling and an uptime monitor.
- ✅🔧 **Optional services fail quietly.** Sentry is DSN-gated and
  asynchronous, so the app never waits on it. News keeps the last good set
  and goes silent after 6 hours. APNs and ntfy failures are logged and never
  retried into a second notice. The app treats no answer as offline, not
  broken. Fixed: a failing digest no longer undoes the decay sweep (above).
- ✅ **Memory.** The app's long-lived classes break their cycles (`[weak
  self]` in `AppState`'s handlers and retry loop; CoreLocation's delegate
  is weak by design; coordinators hold structs). On the simulator, after
  every tab, 33 entries of scrolling, the capture and place sheets and
  Acknowledgements, `leaks` found two objects (1 KB), both a CoreGraphics
  path inside Apple's frameworks, none of Stanley's.
- ⚠️ **Crash-free rate: unknown.** No build has had a Sentry DSN, so no
  crash has ever been reported. Step 3 above.
- 🔧⚠️ **Disk.** A daily `event=disk_low` warning when the volume is over
  three quarters full; ⚠️ the volume itself needs growing (step 1).
- 🔧 **Found in the screenshots: Held never showed faces.** The album heads
  each friend's page with their photo, but the server never signed the link,
  so it was always initials. Fixed and tested.
- 🔧 **Found in the screenshots: red buttons had gone black.** Build 24's
  root ink (the dark room) outranked `role: .destructive`, so Leave Circle,
  Reset Code, Delete Account and Block lost their red in both modes. They're
  red again (`destructiveInk()`); alerts and menus were never affected.
- 🔧 **Seen in the audit, fixed in build 31:** the tab bar now sits on the
  atmosphere's floor (`SolidTabBar`), so the selected tab no longer vanishes
  into iOS 26's glass over a photo. The capture sheet's subtitle wraps
  instead of being cut, and the photo sizes itself so nothing starts under
  the footer (seen whole on the iPhone 17 in the November 4 screenshots).

## App Store requirements

- ✅🔧 **User-generated content (Guideline 1.2).** Report (24-hour review,
  an ntfy alert per report) and block were there. New:
  - A **word filter** (`stanley/wordfilter.py`): slurs aimed at race,
    ethnicity, religion, sexuality, gender identity or disability, and a few
    harassment phrases ("kill yourself"), matched as whole words after
    undoing the usual dodges (case, accents, "n1gg3r", "f.a.g", letters
    spaced out or stretched, two words run together). Applied to stories,
    the board's notes, journal entries, reflections, answers, captions, places, names, usernames, bios and circle
    names, refused before anything is stored, said in words by the app. This
    goes past the comments and notes asked for: a caption or a name is read
    by the whole circle too. Never applied to reports (they may need to
    quote) or hold notes (private). Profanity is left alone. The list is
    stored as salted hashes so the repo doesn't print slurs; add a word with
    `.venv/bin/python -m stanley.wordfilter hash <word>`. "Scunthorpe",
    "Niger", "spicy", "spick-and-span" and "chink in the armor" pass (tested).
  - A **moderation tool** for the operator (`python -m stanley.moderation`):
    list open reports, show one with a 15-minute link to the photo, take a
    photo, story or (build 26) answer to the circle's question down (it
    resolves the reports about it), preserve
    evidence first, close a report, end an account. The Terms promised
    removal, but until now there was no way to do it short of editing the
    database. Run it on Fly with `fly ssh console -C "/app/.venv/bin/python
    -m stanley.moderation list"`.
  - A seventh report reason, "It sexualizes or endangers a child".
- ⚠️ **CSAM.** The plan:
  - *Pilot (now):* circles are invite-only, up to 100 people who know each
    other, with nothing public, no search and no discovery. Detection is by
    report: an ntfy alert for each, read within 24 hours, child-safety
    reports first. On anything that may be CSAM: don't download, screenshot
    or forward it; run `python -m stanley.moderation photo <id> --preserve
    /data/evidence` (copies the files and what's known about the poster to
    the encrypted volume, then removes it everywhere); report it to NCMEC's
    CyberTipline (report.cybertip.org), as US law requires of a provider
    with actual knowledge (18 U.S.C. 2258A); keep the preserved copy, access
    restricted, for one year (the REPORT Act's period), then delete it; end
    the account (`moderation account <user id>`). Stanley keeps no email,
    phone or IP address to give.
  - *Before an open release:* hash matching at upload, before a photo is
    stored: Microsoft PhotoDNA (free to qualifying services, by
    application), Thorn's Safer, or Cloudflare's CSAM Scanning Tool (free,
    but it only sees images served through a Cloudflare-proxied domain, so
    it fits only once photos move to R2 behind a custom domain). A match is
    refused, preserved and reported. Also Apple's SensitiveContentAnalysis
    framework, to blur photos for anyone whose phone has Sensitive Content
    Warning or Communication Safety on (entitlement
    `com.apple.developer.sensitivecontentanalysis.client`), and Apple's
    Declared Age Range API to keep under-13s out.
- 🔧⚠️ **Privacy nutrition label.** `PRIVACY_LABEL.md` re-checked against the
  code and updated for the one new thing, the crash report's trail (Product
  Interaction, not linked, App Functionality, only in a build with a DSN).
  The click-by-click App Store Connect answers are at its end. ⚠️ Fill in the
  form.
- ⚠️ **Age rating** (App Store Connect → the app → App Information → Age
  Rating; Apple's questionnaire as revised in 2025, plus the social media
  questions added in July 2026, which this audit knows from press coverage:
  check the exact wording in the form):
  - Parental controls: No. Age assurance: No.
  - Profanity or crude humor, horror or fear themes, alcohol/tobacco/drugs,
    mature or suggestive themes, sexual content or nudity, graphic sexual
    content: **None**.
  - Cartoon, realistic or graphic violence, guns or weapons: **None**. (The
    World Today's headlines can mention conflict, but as text news; if a
    reviewer disagrees, "Infrequent/Mild Realistic Violence" still rates
    13+.)
  - Medical or treatment information, health or wellness topics: None / No.
  - Simulated gambling: None. Gambling, contests, loot boxes: No.
  - **Unrestricted web access: No (this audit) / Yes (the submission brief,
    November 4). ⚠️ Decide.** A news story opens its publisher's page in
    Safari's in-app viewer, with no address bar; Stanley offers no way to
    browse to an address, though a reader can follow the publisher's own
    links. Apple's definition is "Users can navigate to any webpage within
    the app or freely browse the web. May include: embedded browser
    functionality or browser app." In Apple's current base table that
    capability is **16+** (checked November 4 in App Store Connect Help,
    "Age ratings values and definitions"). Yes makes Stanley 16+, three
    years above the Terms' minimum of 13. If you answer No and a reviewer
    insists, the fallback is to open articles in Safari itself.
  - **User-generated content: Yes.** Messaging and chat: No (no direct
    messages; stories are comments on a photo within a circle). Advertising:
    No.
  - **Social media feed (July 2026): Yes.** Today surfaces circle members'
    photos in a feed, which sets a 13+ floor. "Disabled for users under 13":
    No; the Terms already require 13.
  - Result: **13+**, which matches the Terms, with web access No; **16+**
    with Yes. In Australia, social media alone maps to 16+.
- 🔧⚠️ **Screenshots** (retaken November 4, build 33).
  `ios/AppStoreScreenshots/6.7/` (1290 × 2796, from the iPhone 17 Pro Max
  simulator) and `6.1/` (1179 × 2556, native from an iPhone 15 Pro simulator,
  retaken for build 34), plus `duo-outer/` (1398 × 2034, the Duo's cover;
  no store slot confirmed, and no inner-display set), JPEG,
  light mode, status bar at 9:41.
  - **The set:** six each in the order the brief asked for: Today (the board
    and the week's question), the capture sheet (Grain, a place, a caption,
    two tagged), Held, You (the faces and Invite), World, and the weekly
    question's answers in the circle journal. Plus an optional seventh,
    stories and a shared moment.
  - **How it was made:** seeded by `server/scripts/seed_screenshots.py`,
    which now also writes the circle's questions and Maya's own note. Photos
    are drawn in code (`server/scripts/scenes.py`). The older set in
    `ios/AppStore/Screenshots/` is removed (it's in git history).
  - **Caveats:** in `APP_STORE_METADATA.md`. The main one: **World shows
    PBS's real headlines from the day after the 2026 midterms**, which read
    as partisan on a store page. Retake on a quieter day, or leave World
    out.
  - **To retake:**
    1. Seed into a scratch folder and run the dev server on it, with news
       on.
    2. Sign in as "Maya Chen" in a Debug build.
    3. Drop a `SampleCapture.jpg` in the app's Documents (the simulator's
       camera stand-in).
    4. Grant location before opening the capture sheet (`simctl privacy …
       grant location-always`), and set Bloomington (`simctl location … set
       39.1682,-86.5230`).
    5. Fix the status bar with `simctl status_bar … override --time 9:41`.

## Monitoring and observability

- 🔧 **Logging.** The app's own INFO lines never reached `fly logs`
  (uvicorn configures only its own loggers); now they do. Structured event
  lines, with opaque ids and never a name or anything written:
  `event=signup`, `photo_posted`, `photo_deleted`, `circle_created`,
  `circle_joined`, `account_deleted`, `report_filed`, `block`,
  `words_refused`, `rate_limited`, `server_error`, `disk_low`,
  `health_failed`, `photo_taken_down`, `story_taken_down`,
  `account_terminated`. A test checks that the private words never appear.
- 🔧⚠️ **Sentry.** The app had no DSN anywhere, and Sentry is iOS-only (the
  server has none; its errors go to the log, above). New: a crash trail of
  fixed words (`Trail.swift`: tabs opened, photo posted or queued, held,
  liked, story added, note left, circle switched/started/joined/left,
  reported, blocked, signed in or out, offline and back, links renewed, more
  of Today loaded). Sentry's automatic trail is off, because it records
  every request's URL, and a URL can carry a username. ⚠️ Steps 3 and 7.
- ⚠️ **Uptime monitoring.** Step 5 (UptimeRobot or Better Stack, free).
- ✅ **Server metrics.** Fly has them: dashboard → the app → Metrics (CPU,
  memory, network, HTTP status and latency; a hosted Grafana at
  fly-metrics.net), `fly status`, `fly machine status`, and `df -h /data` over
  `fly ssh console` for the volume. Documented in DEPLOY.md, "Monitoring".

## Data integrity

- ✅ **Foreign keys on.** A per-connection PRAGMA listener sets
  `foreign_keys=ON` on every connection the app opens, with WAL and
  `busy_timeout`; an existing test proves an orphan insert is refused.
- ✅🔧 **Orphans: none**, locally and on Fly. New
  `server/scripts/integrity_check.py` (read-only) checks SQLite's own
  integrity, foreign keys, twenty kinds of orphan or leftover, and blob files
  against rows. On Fly on November 3: all clear (one circle everyone has
  left, which isn't a fault: its code still works).
- ✅ **Account deletion cascades** to photos (and holders' copies), stories,
  likes, holds, tags, rests, blocks, memberships, push tokens, the note,
  notification and Returned logs, milestones and the avatar, leaving a bare
  row with nothing about the person; covered by the existing tests, and the
  Fly check found no deleted account with anything left.
- 🔧 **Concurrency.** A new test runs 240 requests through 40 threads against
  a file database like Fly's, readers and writers mixed, the same person
  repeating the same action. It found the double-tap 500s (fixed, above);
  now every request succeeds.

## Legal and compliance

- ✅🔧 **Terms and Privacy Policy.** The full versions (18 and 11 sections)
  were live on Fly, identical to the repo. The policy changed in this audit
  (the crash trail; effective November 3, 2026), in `legal.py` and the app's
  `Legal.swift` together (a test keeps them identical). ⚠️ Deploy, and see
  step 7.
- ✅🔧 **Deletion.** Account deletion is immediate (the policy says "right
  away"; the app's alert says "within a day"), and backups are gone within
  seven days. Fixed: snapshots are now pruned by age, so the seven days hold
  even after downtime. Fly's volume snapshots last five days. ⚠️ The
  pre-build-18 snapshot must go by November 8 (step 8).
- ✅ **Location is asked in context.** Never at launch: after the shutter
  the first time a photo could take a place (seen on the simulator), from
  the place picker's Here, or from the World tab's invitation. Notifications
  are asked when someone turns one on; Photos (add-only) when a stranded
  photo is saved.
- 🔧 **Open-source licences.** Settings → About → Acknowledgements shows the
  Sentry Cocoa SDK's MIT notice, the only third-party code compiled into the
  app. The fonts are Apple's. Server libraries run on Stanley's machine and
  aren't distributed, so they need no notice (FastAPI, Starlette, Pydantic,
  SQLAlchemy, PyJWT, httpx: MIT or BSD; Pillow: MIT-CMU; uvicorn: BSD;
  cryptography: Apache 2.0/BSD).
