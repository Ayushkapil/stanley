# Stanley — open items (not yet built / not yet done)

> Moved out of CLAUDE.md on 2026-11-17. Update this file when an item ships or is added.

## Open items (not yet built / not yet done)

- **Deploy for real.** Stood up on **Fly** (`server/fly.toml`) — a third path
  beyond the two [`server/DEPLOY.md`](server/DEPLOY.md) documents, and the one
  actually in use. Live at `https://server-earnest-stream-9793.fly.dev`, `GET
  /health` returns `ok`, `STANLEY_SECRET_KEY` and `STANLEY_DATA_DIR`
  (`/data/var`, on the `stanley_data` volume) and `APPLE_BUNDLE_ID`
  (`com.ayushkapileshwar.stanley`) all deployed, `STANLEY_DEV_AUTH=0`. Sign in
  with Apple is configured: `POST /auth/apple` rejects a bad token with 401
  rather than answering 503 `apple_auth_unconfigured`.
- **The India countdown in production.** Set on 2026-11-06 with the
  `india` preset on Ayush's production circle, **Anti mosquito**
  (`8fa3cca67bba40ec8157dca4fd8193ce`, the only circle `find Ayush` names;
  Ayush is a member, not its creator), and on no other: first build 35's
  words (Fly v20), then build 36's words and reminders once the new script
  was on Fly (release **v21**), the same evening. The script ships in the
  image, so it runs as it is, no piping:
  `fly ssh console -a server-earnest-stream-9793 -C "/app/.venv/bin/python
  /app/scripts/set_countdown.py /data/var/stanley.db show <id>"` (or
  `set <id> india`, `clear <id>`). Everyone in that circle sees it once
  they're on build 35 (36 for the clock and the slips); older builds
  ignore the field. **Build 36 has to reach them before November 23.**
  Build 38's daily notes are in the preset: the script with them is on
  Fly as release **v23** (2026-11-07), and the preset was set again on
  Anti mosquito the same evening, so the circle has them; builds 36 and
  37 show them too, all but the day itself's.
- **Circle Posts on Fly.** Deployed as release **v22** (2026-11-07): the
  column is added on startup, off for everyone, and `/terms` and `/privacy`
  answer with the November 7 wording. Nobody is notified until people on
  build 37 turn it on (older builds never show the switch). The policy's
  promise to say in the app when it changes still has no in-app notice
  behind it. Not yet seen end to end: a real phone receiving "… shared a
  moment".
- **Build 69** (0.2.0): the title's ink from its field (above). Phone
  only; not archived. Carries build 68.
- **Crash reporting is ready to switch on once the Sentry account
  exists** (build 70; Ayush stopped the work there, November 15). Done:
  the scrub and its test, the policy's notice, `PRIVACY_LABEL.md`. Left,
  in order, after the account is made:
  1. From sentry.io: the region (US or EU), the plan (Developer keeps
     errors 30 days, Team 90), an Apple/iOS project, its organization
     and project slugs, the DSN (a public key; fine in the repo), and
     Security & Privacy: *Prevent Storing of IP Addresses*, *Data
     Scrubber*, *Use Default Scrubbers*. An organization auth token for
     symbols, which Ayush saves in `~/.sentryclirc` (`[auth]`,
     `token=…`) or `SENTRY_AUTH_TOKEN`: never in the repo or a chat.
  2. The Privacy Policy: region, retention, no identifier; a new date in
     `legal.py` and `Legal.swift`; a `PolicyNotice.Revision`;
     `PRIVACY_LABEL.md`'s "checked against" line; `fly deploy`.
  3. `STANLEY_SENTRY_DSN` in `ios/project.yml`; `brew install
     getsentry/tools/sentry-cli`; a Release-only post-build phase running
     `sentry-cli debug-files upload --include-sources
     "$DWARF_DSYM_FOLDER_PATH"` with the org and project, skipped with a
     warning when no token is found, so a build never fails for it (and
     covering `Sentry.framework`'s dSYM, which build 68's upload warned
     about: that framework is dynamic).
  4. Prove it: a Release build crashed on purpose, the report read in
     Sentry for a readable stack and nothing identifying.
  5. Tell the pilot: build 70's notice does it in the app.
- **The engineering review** (November 17, 2026): three read-only reviews
  (the phone's speed, its code health, the server), ranked with severity
  and effort, and Ayush's order: (1) the sign-out leak, done in build 77;
  (2) optimistic updates: the heart and bookmark at once, the capture sheet
  closing on upload, a journal page closing on save, cached photos without
  a placeholder flash; (3) photo files deleted only after the database
  commits (D3), then the weekly VACUUM's lock (D2); (4) blobs to R2 (D1),
  its Privacy Policy wording batched with Sentry's; (5) bounding upload
  memory on the 1 GB machine, before November 23. **Not to be done: the
  AppState split (item 15) or any refactor.** **Deferred, known work**:
  independent loads run concurrently and the Journal tab not refetching
  what launch fetched (5); the book's pagination off launch and the main
  thread (6); renewing expired links in parallel and ahead of time, and
  keeping avatars (7); batching the server's per-photo queries in Today,
  Held, the circle list and the shared journal's hearts, and Held's write
  on every read (9); pruning `notification_log` (14); the four orphaned
  views, duplicate date and upload helpers and timing hacks (16); retiring
  code for old builds once `client_builds` shows them gone, after mid
  February 2027 at the earliest (17; the logging is in build 77); faster
  server tests and more phone unit tests (18). Also found: the news fetch
  inside requests, signed links that change every second.
- **Photos moved to Cloudflare R2, November 19, 2026** (step 4, unparked
  by Ayush once the bucket existed). 88 files (82.4 MB) copied, each
  checked by size and a SHA-256 of what R2 hands back, twice (`copy`,
  `verify`), then the switch as Fly release v41 with the November 19
  Privacy Policy (Cloudflare named as a processor, photos in the eastern
  US). After it: `copy`/`verify` 88/88 again, `reconcile` 0 strays, a
  server-signed link loads from R2 (200) and the bare address is refused
  (400). **The volume copies are held 24 hours** (Ayush's change to the
  runbook); a one-time scheduled task (`stanley-r2-reconcile-and-delete-local`,
  November 20, 7:20 Bloomington) runs `reconcile --confirm`, `verify`,
  reads the logs, and only if all are clean `delete-local --confirm`.
- **Build 81** (0.2.0): the day's entry of up to three photos, placed
  like a scrapbook, and the Journal tab first (FEATURES.md). Server
  deployed with it; the build is to be archived and uploaded after Ayush
  has read the report. Not done: the Terms changed (November 19) but the
  app's policy notice is keyed to the Privacy Policy, so no line tells
  people the Terms changed; the Held viewer, mosaic, returned card, widget
  and book pages show an entry's first photo only; the brand line "One
  Day, One Photo" is unchanged.
- **Build 80** (0.2.0): the November 19 policy in the app and its notice
  (one line: photos now stored by Cloudflare), nothing else. Uploaded
  right after the switch, and **added to Friends the same day** (Testing,
  with Pilot Testers), with a What to Test note.
- **Build 79** (0.2.0): photos and faces kept on the phone, the renewal
  at once and ahead of time, loads run together (above). **Its server is
  on Fly as v39** (November 17, `main` as of `1e86d5a`, 774 passing:
  versioned faces at 256px, the November 17 Privacy Policy; `/health` ok,
  `/privacy` with the new words, integrity ok), deployed before the app.
  **Archived and uploaded the same evening**; never added to Friends
  (80, which has everything in it, went instead).
- **Build 78** (0.2.0): the phone's words for `busy` (item 13), and
  everything in 77. **Uploaded November 17, 2026** (after an App Store
  Connect outage turned the first six tries away with a 500) and **added
  to Friends** the same evening (Testing, eight invitations), with a What
  to Test note. Item 13's server change is on Fly as **v38** (healthy;
  it carries the R2 groundwork too, with photos still on the volume).
- **Build 77** (0.2.0): sign-out and the queue, the build logging, step
  2's optimistic updates and their rollback tests (above). **Archived and
  uploaded November 17, 2026**; never added to Friends (78 went instead). Its server parts: the build
  logging on Fly as v36, D3 and D2 as v37 (both November 17, healthy).
- **Build 76** (0.2.0): the opened cover (above). Phone and server.
  **Archived and uploaded on November 16, 2026**, and added to Friends the
  same evening (straight to Testing, no compliance question: the plist
  answers it now), with a What to Test note. **Its server is on Fly as release v35** (November 16, `main`
  as of `74de31e`, after the full suite passed, 736): `/health` ok;
  `POST /me/journal/cover` and `PATCH /me/journal` answer 401 without a
  sign-in; `/privacy` says November 16, 2026 with the cover's words;
  `users.journal_cover_key` exists on the volume; integrity ok. Older
  builds see one change: a circle's cover is now its newest photo for
  everyone, not their own keep in it.
- **Build 75** (0.2.0): days and hours to midnight on the 23rd (above).
  Phone only; v34 on Fly is its server, and the legs set on Anti mosquito
  need nothing new. **Archived and uploaded to App Store Connect on
  November 16, 2026**, as 74 was ("Stanley 0.2.0 (75)" in Organizer's
  folder; "Upload succeeded", then processing; the only warning
  Sentry.framework's missing dSYM). Ayush's friends were on build 55
  in TestFlight then: builds 56 to 74 had gone only to the internal
  group, Pilot Testers (Ayush alone), and 68 and 75 sat at "Missing
  Compliance" (no `ITSAppUsesNonExemptEncryption` in the plist, so each
  build waits on that question). Ayush answered it for 75, and 75 was
  added to the external group **Friends** (seven testers) the same
  afternoon, with a "What to Test" note; it went straight to Testing,
  no review wait, and testers were notified. **From build 76 on**, the
  app's plist says `ITSAppUsesNonExemptEncryption` false (in
  `project.yml`), so builds skip the question; each upload still has to
  be added to Friends in App Store Connect (Ayush said yes to doing that
  with every upload).
- **Build 74** (0.2.0): the India countdown as a flight path (above).
  Phone only; v34 on Fly is its server. **Archived and uploaded to App
  Store Connect on November 16, 2026**, as 73 was ("Stanley 0.2.0 (74)"
  in Organizer's folder, `-exportArchive` to `upload` with
  `-allowProvisioningUpdates`; "Upload succeeded", then processing; the
  only warning Sentry.framework's missing dSYM again). Not yet seen in
  TestFlight. **The legs are on Anti mosquito** (asked for by Ayush,
  November 16): after `fly deploy` (release **v34**, `main` as of
  `eb1077d`, the full suite passing on it, 724; `/health` ok), `set
  8fa3cca67bba40ec8157dca4fd8193ce india` with this build's script, read
  back with the five legs, Dubai's `at` null. Builds before 74 ignore
  `legs` and read the rest as before. The trip leaves on 23 November.
- **Build 73** (0.2.0): the sheet's rows leading to their pages, and the
  sheet scrolling instead of turning the screen (above). Phone only; v33
  on Fly is its server. Carries builds 71 and 72. **Archived and uploaded
  to App Store Connect on November 16, 2026**, as 68 and 70 were
  ("Stanley 0.2.0 (73)" in Organizer's folder, `-exportArchive` to
  `upload` with `-allowProvisioningUpdates`; "Upload succeeded", then
  processing). No Sentry DSN; the only warning was Sentry.framework's
  missing dSYM again. Not yet seen in TestFlight.
- **Build 72** (0.2.0) was never archived on its own: the answer sheet
  standing alone (above). Carries build 71.
- **Build 71** (0.2.0) was never archived on its own: the covers' room
  evenly veiled, no shadows behind words (above).
- **Build 70** (0.2.0): the crash scrub and the policy's notice (above).
  Phone only; v33 on Fly is its server. Carries builds 69 and 68.
  **Archived and uploaded to App Store Connect on November 15, 2026**,
  the same way as 68 ("Stanley 0.2.0 (70)" in Organizer's folder,
  `-exportArchive` to `upload` with `-allowProvisioningUpdates`; "Upload
  succeeded", then processing). No Sentry DSN, so the scrub is inert
  until one is set; the only warning was again Sentry.framework's
  missing dSYM. The pilot sees the policy's notice (November 13 to 15)
  on first opening it. Not yet seen in TestFlight.
- **Build 68** (0.2.0): the page's date as furniture and the covers'
  scrims (above). Phone only; v33 on Fly is its server. Build 68
  carries everything below. **Archived and uploaded to App Store
  Connect on November 15, 2026** (`xcodebuild archive` into Organizer's
  folder, "Stanley 0.2.0 (68)", then `-exportArchive` with destination
  `upload` and `-allowProvisioningUpdates`; "Upload succeeded", then
  processing). The only warning: no dSYM for Sentry.framework, which
  matters only once a Sentry DSN is set. Not yet seen in TestFlight.
  The last build uploaded before it was 40.
- **Build 67** (0.2.0) was never archived on its own: the book to
  VoiceOver and the darker secondary (above).
- **Build 66** (0.2.0) was never archived on its own: the answer sheet
  read by VoiceOver (above).
- **Build 65** (0.2.0) was never archived on its own: the answer sheet
  (above).
- **Build 64** (0.2.0) was never archived on its own: the capture's
  daily prompt turning at local midnight, not UTC (Daily prompt, below),
  and the sweep for the same bug ("Whose day it is", above). **Its server
  must be on Fly before the app reaches anyone**: against v31, the first
  day the letter picker offers is refused as too soon in an American
  evening. The server is safe for older builds (no zone is UTC, as
  before), so the order is deploy, then upload.
  over build 63's Prompts out of
  the Journal tab's toolbar and onto the page being written (above),
  over build 62's covers to
  Apple's iPhone Duo guidance, over build 61's asking to notify
  at the first concrete moment, over
  build 60's Written to You as corrected, over build 58's covers' room, centered peeks and the covers
  on their side, build 57's
  Journal Entries, the capsule and the inks at night, build 56's cover
  screen and build 54's glass chrome with "Mine" and "Ours" in
  an open book's bar (55), and build 52's page for one person, ruled
  paper and the dots.
- **Build 65's server is on Fly** (2026-11-15, asked for in its brief):
  release **v33** runs `main` as of `b37eeb6`, after the full suite
  passed on that code (698). Checked after the deploy: `/health` ok;
  `GET /moods`, `PUT /moods/{day}`, `PUT /photos/{id}/score` and `GET
  /me/moods` answer 401 without a sign-in; `/privacy` says November 15
  and "on that day only"; integrity all clear (the one empty circle
  noted as before). The migration found nothing to move: no account on
  the volume had left a mark (`photos.score` set on none, `day_moods`
  empty). Build 65's app can go out now. Not yet seen: a real phone
  marking a day against it.
- **Build 64's server is on Fly** (2026-11-15, asked for by Ayush):
  release **v32** (history now) runs `main` as of `ac1710d`, after the full suite
  passed on that code (673). Safe for older builds: a letter sent with no
  zone is checked against UTC's today as before, and a note with none
  clears as before. Checked after the deploy: `/health` ok; `POST
  /me/letters/send` and `PUT /circles/{id}/notes/mine` answer 401
  without a sign-in; the running code has the zone-or-UTC letter check
  and the note's zone; integrity all clear. Build 64's app can go out
  now. Not yet seen: a real phone sending a letter or a note with its
  zone.
- **Build 60's server is on Fly** (2026-11-14, asked for in its brief):
  release **v31** (history now) runs `main` as of `63de349`, after the full suite
  passed on that code (649). Checked after the deploy: `/health` ok;
  `/privacy` says Written to You is on until turned off;
  `users.written_to_you` was added and is null (on) for all five
  accounts on the volume; integrity ok, no foreign-key problems.
- **Build 59's server is on Fly** (2026-11-14, asked for in its brief):
  release **v30** (history now) runs `main` as of `bf16e0e`, after the full suite
  passed on that code (647). Checked after the deploy: `/health` ok;
  `POST /me/letters/send` answers 401 without a sign-in; `/privacy` has
  "Written to You" and no longer says a circle hears of a page;
  `notification_log.sender_id` exists on the volume; integrity ok, no
  foreign-key problems. From now on a whole circle's journal notifies
  nobody on the live server, whatever build a phone is on. Not yet
  seen: a real phone receiving "… wrote you a page" or "… sent you a
  letter" from it.
- **Builds 52 to 58's server is on Fly** (2026-11-14, asked for by
  Ayush): release **v29** (history now) runs `main` as of `b4a5fb3`, after the full
  suite passed on that code (644). Checked after the deploy: `/health`
  ok; `GET /me/moods`, `PUT /photos/{id}/score` and `PUT
  /circles/{id}/journal/mute` answer 401 without a sign-in; `/privacy`
  says November 14 with the words for a page for one person, the mark
  on a day and Journal Entries; `journal_pages.recipient_id`,
  `photos.score`, `memberships.journal_muted`,
  `users.journal_posts_enabled` and the `day_moods` table exist on the
  volume; integrity ok, no foreign-key problems. Nothing changes for
  older builds. Not yet seen: a real phone getting a journal notice, a
  cover from `cover_url`, or the dots, against it.
- **Build 51's server is on Fly** (2026-11-14, asked for by Ayush):
  release **v28** runs `main` as of `68aa2f6`, after the full suite
  passed on that code (573). Checked after the deploy: `/health` ok; the
  shared journal's routes answer 401 without a sign-in (`GET
  /circles/{id}/journal`, `PATCH /journal/{id}`, `POST
  /journal/{id}/heart`, `GET /journal/{id}/hearts`); `/privacy` has the
  shared journal's words; `journal_pages.shared` and `circle_id`,
  `reports.page_id` and the `page_hearts` table exist on the volume;
  integrity ok, no foreign-key problems; no page shared yet. Nothing
  changes for older builds. Not yet seen: a real phone on build 51
  sharing a page to it.
- **Build 50's server is on Fly** (2026-11-14): release **v27** runs
  `main` as of `7bc5414`. Checked after the deploy: `/health` ok; the
  journal's routes answer 401 without a sign-in; `journal_pages.inks`
  was added on the volume; integrity ok, no foreign-key problems.
  Nothing changes for older builds. Not yet seen: a real phone keeping a
  page in more than one ink on it.
- The next upload carries builds 41 to 51 (43 and 47 were only bumps; 44 is the
  Quiet Warmth design pass, which also removed the filters and
  rest-a-memory from the app; 45 is the journal as a book, never archived
  on its own). The last build uploaded is 40.
- **Build 45's server is on Fly** (2026-11-14): release **v26** runs
  `main` as of `33ef9aa`. Checked after the deploy: `/health` ok; the five
  `/me/journal` routes answer 401 without a sign-in; `/terms` and
  `/privacy` say November 14 and the policy has the Journal widget's
  paragraph; `journal_pages` and `users.journal_title` exist on the
  volume; integrity ok, no foreign-key problems. Nothing changes for
  older builds. Not yet seen: a real phone writing a page to it.
- **A flaky server test, fixed** (November 13). `test_journaling.py::
  test_nothing_about_the_question_counts_anyone` failed one run in forty:
  it looked for "count" in every string of the payload, and one of the
  forty questions is "What does your week look like if you only count the
  quiet moments?" (picked at random). Nothing to do with the clock, and
  not a bug in the server. It now reads only the payload's field names
  (`names()`), and asks that very question so the case that failed is the
  one tested.
- **Fly now** (2026-11-13): release **v25** runs `main` as of `7a2b2a0`:
  both letters features, build 39's reminders if v24 hadn't already
  brought them, and the November 13 Terms and Privacy. Checked after the
  deploy: `/health` ok; `/terms` and `/privacy` say November 13 and the
  policy has the letters paragraph; the new routes answer 401 without a
  sign-in (`/circles/{id}/letters/mine`, `/reveal`, `/me/letters/sent`,
  `/received`); `circle_letters`, `person_letters` and both `reports`
  columns exist on the volume; `integrity_check.py` is all clear. The
  older "Fly now" and "Fly before" paragraphs below are history.
- **Build 42** (0.2.0) holds **two letters features, built by two
  sessions at once on November 13** and joined on the branch
  `claude/letters-both`, since merged into `main`. Neither is archived.
  Both are on Fly (v25).
  - **Letters to the circle** (above): one unsigned letter a month to the
    whole circle. Built in a worktree on `claude/letters-to-the-circle`.
    New on the server: `circle_letters`, `reports.circle_letter_id`, the
    sweep's two letter passes, and the November 13 Terms and Privacy.
  - **Sealed letters to a person** (commit `78d4ff5`, written by the other
    session straight onto `main`): a letter from one person to another,
    closed until a day the sender picks, written from the You tab and
    kept in the recipient's Held (`routes/letters.py`, `person_letters`,
    `reports.letter_id`, `Letters.swift`, `test_letters.py`). **It has no
    section in this file, and no words in the Terms, the Privacy Policy or
    `PRIVACY_LABEL.md`**: its commit message is all there is. It hasn't
    been looked at on a simulator by the session that wrote this.
  The join kept both whole: where they met (the report sheet's target,
  `AppState.report`, the moderation tool's command) the circle's letters
  took the longer name (`circleLetter`, `circle-letter`) and the sealed
  ones kept `letter`.
- **Build 41** (0.2.0) is committed but not archived: the widget's light
  mode fix, above. Phone only; nothing on the server.
- **Build 40** (0.2.0), the Home Screen widget, was archived on November
  13 at 12:52 PM and uploaded from Organizer (the archive records an
  upload with no errors), so the App Group
  `group.com.ayushkapileshwar.stanley` and the widget's App ID
  `com.ayushkapileshwar.stanley.widgets` are registered. It carries build
  39's polish pass too, and the widget's light mode bug that build 41
  fixes. An `xcodebuild -exportArchive` with the old `ExportOptions.plist`
  may still need `-allowProvisioningUpdates`. Nothing on the server
  changed for it but the two documents' words and date (November 12),
  which go out with the next `fly deploy`.
- **Build 39** (0.2.0) was never archived on its own (build 40 carries
  it): the polish pass below. Its server side (four `users` columns for
  the reminders, off for everyone; the reminder pass in the sweep) is on
  Fly as of v25 at the latest. Build 38 added the bigger
  flip clock and the day itself's note to everything in 37. Build 37
  (Circle Posts) was archived on November 7 at 4:18 PM, build 36 on
  November 6 at 8:21 PM and build 35 at 7:30 PM (Organizer); builds 34
  and 28 are archived too. Whether any was
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
  used. `/data/pre-build18.db` was still there then (deleted November 16). The
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
  the You tab has no moments line. Mentions need no server change. The pre-build-18
  snapshot (both copies) was due by 2026-11-08 and **was deleted on
  2026-11-16**, late: `/data/pre-build18.db` on the volume and
  `server/var/fly-backups/pre-build18-20261101.db` here.
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
- **Off-box backups, running since November 16, 2026.** `server/scripts/
  pull_backup.sh` is installed as the launch agent `com.stanley.pull-backup`
  (DEPLOY.md, "Backups"): daily at 10:00, into `~/Library/Application
  Support/Stanley/backups` (not iCloud-synced; FileVault on), six days
  kept, output in `~/Library/Logs/stanley-pull-backup.log`. Run once by hand
  that day and it fetched `20261117T000717Z.db`, integrity ok. Fixed on the
  way: the integrity check opened the copy in a way that left `-shm` and
  `-wal` files the cleanup never removed; it opens it `immutable` now. The
  installed copy is outside the repo, so after changing the script copy it
  there again. Fly's own daily volume snapshots (five days) are a second
  layer.
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
  now; since build 58 the journals' covers alone may turn, above), the empty Today's camera falling behind the tab bar (it's inside the
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
  cover. **Gone into again for build 51** (November 14, 2026), and still
  no way in: the Duo simulator has two displays, `xcrun simctl io <Duo>
  screenshot --display=1` (the cover, 1398×2034, where the app is) and
  `--display=3` (the inner panel, 2007×2853, always black; it's also what
  a bare `simctl io screenshot` takes); `simctl io <Duo> screenConfig`
  refuses the inner panel's geometry on the cover ("No mode found");
  `screenConfig --display=1 power off` doesn't move the scene and leaves
  the cover black until the simulator is shut down and booted again;
  there is no fold or posture verb in `simctl`, CoreSimulator, Xcode's
  Device Hub or the 27.1 runtime; and Xcode 27.1 ships no Simulator.app
  to click a fold button in. **A device type of one's own doesn't get
  round it either**: the Duo's `capabilities.plist` lists both panels
  (screenID 1 the cover, screenID 3 "LCD-1" the inner one), but a copy
  of the type in `~/Library/Developer/CoreSimulator/Profiles/DeviceTypes`
  with the two swapped can't make a device ("Incompatible device": the
  27.1 runtime is `restrictedToDeviceTypes` Apple's own, by its product
  alias V68), and CoreSimulator keeps an existing device's type in
  memory, so editing the Duo's `device.plist` does nothing without
  restarting the service and every booted simulator with it. Tried and
  put back; nothing of it is left on the machine. Whether the 669×951pt inner panel reports **regular** to an
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

