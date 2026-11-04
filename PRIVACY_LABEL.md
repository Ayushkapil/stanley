# App Store Privacy Nutrition Label — Stanley

Fill the App Store Connect form (App Privacy section) directly from this
checklist. Every answer below is derived from what the code actually does as of
this commit — if you add an SDK, an analytics call, a SIWA scope, or attach a
user to Sentry, re-derive this document first.

**Two builds, two labels.** The label depends on one build-time value:
`STANLEY_SENTRY_DSN` in Info.plist. Empty → the Sentry SDK never starts and
Stanley collects **no diagnostics at all**. Set (TestFlight/release) → add
Crash Data, and Product Interaction for the crash report's short trail, as
described below. Everything else is identical.

Checked against the code in the production audit (November 3, 2026): every
answer below still matches. One thing changed: a crash report now carries a
short trail of fixed words (`Trail.swift`), and the Privacy Policy says so
(section 2, effective November 3, 2026).

---

## Top-level questions

- **Do you or your third-party partners collect data from this app?** → **Yes**
  (name, photos, user content, user ID — all required for the product to work).
- **Is any data used to track users across apps/websites owned by other
  companies (ATT)?** → **No.** Nothing is shared with data brokers or ad
  networks; there are no ads, no fingerprinting, no AdSupport linkage.

---

## Data types — what to select

For every type marked **Collected** below, the purposes are **App
Functionality only** — never Analytics, never Advertising, never Product
Personalization, never Other.

### Contact Info

- [ ] **Name — COLLECTED · Linked to identity · Not used for tracking.**
  From Sign in with Apple, **first sign-in only** (`request.requestedScopes =
  [.fullName]`; Apple sends the name once, the server keeps it as
  `display_name`, later sign-ins never resend or overwrite it). User-editable
  afterwards.
- [ ] **Email Address — NOT COLLECTED.**
  ⚠️ Diverges from the working assumption that Stanley receives a SIWA relay
  address: the app requests only `.fullName` — **not `.email`** — and neither
  the client nor the server has any email field, so no address (relay or real)
  ever reaches Stanley. Declare *Not Collected*. If `.email` is ever added to
  `requestedScopes` (e.g. for support contact), flip this to *Collected ·
  Linked* and note that Hide My Email users yield a `@privaterelay.appleid.com`
  proxy, not a real address.
- [ ] Phone Number / Physical Address / Other Contact Info — **not collected.**

### User Content

- [ ] **Photos or Videos — COLLECTED · Linked to identity · Not used for tracking.**
  The daily photo and the optional avatar, uploaded to and stored on Stanley's
  server, tied to the account. The daily photo is taken with the in-app
  camera or, since build 16, chosen with the system photo picker, which
  needs no Photos permission: Stanley sees only the one photo chosen. A
  chosen photo is re-encoded on the phone from its pixels, so its metadata
  (GPS included) is never sent, and an avatar is cropped and re-encoded the
  same way. Server-side ingest strips **all EXIF except the capture
  timestamp — GPS is removed** before the image ever touches disk.
  Each photo is visible only to the one circle it was posted to (a person
  can be in up to five since build 17; each circle's soft cap is 100), served
  via short-TTL signed URLs, and is deleted by decay physics unless held.
  Nothing about this changes a label answer: the photo is still collected,
  linked to the account, and not used for tracking.
- [ ] **Other User Content — COLLECTED · Linked to identity · Not used for tracking.**
  Captions, story-comments, bio, username, hold notes, notes on the circle's board,
  location labels (a free-text string like "Dunn Meadow", typed, or offered
  from where the phone is and kept by the person; never coordinates),
  who-was-there tags, and report text. Since build 26, what a person writes
  down: journal entries on their own photos and weekly reflections (both
  read by no one but their writer), and answers to the circle's question of
  the week (read by the circle once that week's answers open). The same
  answers as before: collected, linked, used for App Functionality, not for
  tracking.
- [ ] Emails or Text Messages / Audio / Gameplay / Customer Support — **not collected.**

### Identifiers

- [ ] **User ID — COLLECTED · Linked to identity · Not used for tracking.**
  Stanley issues an opaque account ID (the JWT subject) and stores the SIWA
  `sub` to recognize repeat sign-ins. Required for accounts to exist.
- [ ] **Device ID — COLLECTED · Linked to identity · Not used for tracking.**
  Since build 18, only for someone who turns on a notice (Settings → Quiet):
  the phone's APNs device token is sent to the server (`POST
  /me/push-token`) and kept with the account (`push_tokens`) so the
  last-light notice and the evening note can reach that phone. Purpose: App
  Functionality. It's removed when they sign out on that phone, when they
  delete the account, and when Apple reports it dead. Apple's guidance on
  whether a push token counts as a Device ID isn't explicit; declaring it is
  the conservative answer, and costs nothing. No IDFA, no IDFV.

### Location

- [ ] **Precise Location — NOT COLLECTED.**
  With "while using" permission (asked after the shutter, or from the World
  tab's invitation), the phone takes one fix and turns it into names with
  Apple's geocoder (`Whereabouts.swift`). A photo chosen from the library is
  named the same way from the location in its own metadata, read on the
  phone (`LibraryPhoto.swift`). The coordinates go to Apple, as platform
  geocoding, and never to Stanley's server. What can reach the server is a
  place *name* the person keeps on a photo, which is Other User Content
  above. Photos still have EXIF GPS stripped at ingest.
- [ ] **Coarse Location — COLLECTED · NOT linked to identity · Not used for
  tracking.**
  With permission, the World tab sends the **town and country**
  ("Bloomington, IN", "US") to fetch local headlines (`GET /news/nearby`),
  in request headers so they never land in an access log. The server uses
  the town to pick a feed and caches that feed under the town's name, never
  against the account that asked; a town nobody asks about is dropped after
  a day. Declared conservatively: the town outlives the request in that
  cache. Without permission nothing is sent and the national edition is the
  US one.

### Diagnostics — depends on the build

- [ ] **Crash Data — dev builds (`STANLEY_SENTRY_DSN` empty): NOT COLLECTED.**
  The SDK is init-gated on the DSN and never starts.
- [ ] **Crash Data — TestFlight/release builds (DSN set): COLLECTED · NOT
  linked to identity · Not used for tracking.**
  "Not linked" holds because of how the SDK is configured in
  `ios/Stanley/StanleyApp.swift`, and stays true only while all of this does:
  - No `SentrySDK.setUser` call anywhere — crash reports carry no account ID,
    name, or username.
  - `enableAutoSessionTracking = false` (sessions are usage data — off).
  - `attachScreenshot = false` and `attachViewHierarchy = false` (a screenshot
    could contain someone's photo — never shipped).
  - `tracesSampleRate = 0` (no performance telemetry → Performance Data stays
    *Not Collected*).
  - `enableAutoBreadcrumbTracking = false`, `enableNetworkBreadcrumbs =
    false` and `enableCaptureFailedRequests = false` (production audit):
    Sentry's own trail would record taps, screens and every request's URL,
    and a URL can carry a username (`/me/username_check?u=`) or a member's
    id. The only trail is Stanley's (`Trail.swift`): up to 30 fixed phrases
    from a closed list ("opened Held", "posted a photo", "added a story"),
    never an id, a name, a caption, a place, a URL or anything typed. It
    stays on the phone and leaves only inside a crash report.
  - `sendDefaultPii` is left at its default (`false`) — no IP address is
    attached client-side.
  - **Action required in the Sentry project settings:** enable
    *Security & Privacy → Prevent Storing of IP Addresses*, so the ingest
    server discards the connection IP too. Do this before shipping the DSN.
- [ ] Performance Data / Other Diagnostic Data — **not collected.**

### Usage Data — depends on the build

- [ ] **Product Interaction — dev builds: NOT COLLECTED. TestFlight/release
  builds (DSN set): COLLECTED · NOT linked to identity · Not used for
  tracking · purpose App Functionality.** The crash trail is a record of
  what the app did ("opened Held", "posted a photo"), which is Apple's
  definition of product interaction even though it only ever travels inside
  a crash report and is used for nothing but fixing the crash. Declaring it
  is the conservative answer, like the push token under Device ID. Purpose:
  App Functionality (Apple lists "minimize app crashes" there), never
  Analytics.
- [ ] Advertising Data / Other Usage Data — **not collected.**

### Everything else — Not Collected

Health & Fitness, Financial Info, Sensitive Info, Contacts, Browsing History, Search
History, Purchases, Surroundings, Body, Other Data. (Usage Data is above: only
the crash trail, only in a build with a DSN; no analytics, no advertising.)

---

## Honest footnotes (not label categories, but say them if asked)

- The server stores the device's **IANA timezone string** (e.g.
  `America/New_York`) sent with each capture — it defines "one photo per local
  day". It is not a location under Apple's definitions (no GPS/network
  derivation) and has no label category.
- Saved places stay on the phone. The capture screen remembers the place
  labels someone used (recent ones, plus up to ten starred favorites) in the
  app's local storage, per account, to offer them again. They are never sent
  anywhere: a place reaches the server only as the label on a photo they post,
  as before. No maps or places service. Account deletion erases them from
  the phone.
- Push notifications: when APNs is wired, the server stores a **device push
  token**. Tokens exist to deliver the single last-light notice/digest and are
  not an Apple label category by themselves.
- Data deletion: account deletion cascades — photos, blobs, comments, holds
  all purge. Owner-deleted photos purge everywhere immediately.

## Re-derive this label when…

- The town for local news is ever stored with the account, logged, or sent
  in a query string → Coarse Location becomes **Linked to identity**.
- Coordinates are ever sent to Stanley's server → add Precise Location.
- A library photo is ever uploaded as its original file rather than
  re-encoded → its GPS reaches the server before ingest strips it; check
  Precise Location again.

- `.email` is added to SIWA `requestedScopes` → Email becomes Collected.
- A notice ever carries a name, a photo or a count, or push is used for
  anything but the two notices → revisit Device ID's purpose, and §10.
- Any analytics/telemetry SDK is added → Usage Data changes, and the "no
  counts, no engagement signals" product rules deserve a second look anyway.
- `SentrySDK.setUser` or custom Sentry events, or a `Trail` step carrying an
  id, a name or anything typed, is added → Crash Data and Product
  Interaction flip to **Linked to identity**. Sentry's automatic
  breadcrumbs are turned back on → re-read what they record (URLs) first.
- `tracesSampleRate` becomes non-zero → add Performance Data.

## App Store Connect, click by click

App Store Connect → the app → **App Privacy** → Get Started (or Edit). For the
TestFlight/release build, which carries a Sentry DSN:

1. **Do you or your third-party partners collect data from this app?** Yes.
2. Select these data types, and nothing else:
   - Contact Info → **Name**
   - User Content → **Photos or Videos**, **Other User Content**
   - Identifiers → **User ID**, **Device ID**
   - Location → **Coarse Location**
   - Usage Data → **Product Interaction**
   - Diagnostics → **Crash Data**
3. For each type, answer:

| Data type | Purposes | Linked to the user's identity? | Used for tracking? |
|---|---|---|---|
| Name | App Functionality | Yes | No |
| Photos or Videos | App Functionality | Yes | No |
| Other User Content | App Functionality | Yes | No |
| User ID | App Functionality | Yes | No |
| Device ID | App Functionality | Yes | No |
| Coarse Location | App Functionality | No | No |
| Product Interaction | App Functionality | No | No |
| Crash Data | App Functionality | No | No |

4. **Privacy Policy URL** (App Information → Privacy Policy URL):
   `https://server-earnest-stream-9793.fly.dev/privacy`. Live since release
   v15 (November 2, 2026); the November 3 wording (the crash trail) reaches it
   with the next `fly deploy`.
5. Publish. The label shows on the product page once the version is
   submitted.

A build without a DSN collects less (no Crash Data, no Product Interaction),
but the App Store shows one label per app, so answer for the build you ship.
