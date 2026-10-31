# App Store Privacy Nutrition Label — Stanley

Fill the App Store Connect form (App Privacy section) directly from this
checklist. Every answer below is derived from what the code actually does as of
this commit — if you add an SDK, an analytics call, a SIWA scope, or attach a
user to Sentry, re-derive this document first.

**Two builds, two labels.** The label depends on one build-time value:
`STANLEY_SENTRY_DSN` in Info.plist. Empty → the Sentry SDK never starts and
Stanley collects **no diagnostics at all**. Set (TestFlight/release) → add
Crash Data as described below. Everything else is identical.

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
  server, tied to the account. Server-side ingest strips **all EXIF except the
  capture timestamp — GPS is removed** before the image ever touches disk.
  Photos are visible only to the user's one circle (≤30 people), served via
  short-TTL signed URLs, and are deleted by decay physics unless held.
- [ ] **Other User Content — COLLECTED · Linked to identity · Not used for tracking.**
  Captions, story-comments, bio, username, hold notes, the community note,
  location labels (a free-text string like "Dunn Meadow", typed, or offered
  from where the phone is and kept by the person; never coordinates),
  who-was-there tags, and report text.
- [ ] Emails or Text Messages / Audio / Gameplay / Customer Support — **not collected.**

### Identifiers

- [ ] **User ID — COLLECTED · Linked to identity · Not used for tracking.**
  Stanley issues an opaque account ID (the JWT subject) and stores the SIWA
  `sub` to recognize repeat sign-ins. Required for accounts to exist.
- [ ] Device ID — **not collected** (no IDFA, no IDFV use).

### Location

- [ ] **Precise Location — NOT COLLECTED.**
  With "while using" permission (asked after the shutter, or from the World
  tab's invitation), the phone takes one fix and turns it into names with
  Apple's geocoder (`Whereabouts.swift`). The coordinates go to Apple, as
  platform geocoding, and never to Stanley's server. What can reach the
  server is a place *name* the person keeps on a photo, which is Other User
  Content above. Photos still have EXIF GPS stripped at ingest.
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
  - `sendDefaultPii` is left at its default (`false`) — no IP address is
    attached client-side.
  - **Action required in the Sentry project settings:** enable
    *Security & Privacy → Prevent Storing of IP Addresses*, so the ingest
    server discards the connection IP too. Do this before shipping the DSN.
- [ ] Performance Data / Other Diagnostic Data — **not collected.**

### Everything else — Not Collected

Health & Fitness, Financial Info, Sensitive Info, Contacts, Browsing History, Search
History, Purchases, **Usage Data (no analytics, no product-interaction
telemetry, no advertising data — nothing in the app records taps, views, or
launches)**, Surroundings, Body, Other Data.

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

- `.email` is added to SIWA `requestedScopes` → Email becomes Collected.
- Any analytics/telemetry SDK is added → Usage Data changes, and the "no
  counts, no engagement signals" product rules deserve a second look anyway.
- `SentrySDK.setUser` or custom Sentry events/breadcrumbs with user data are
  added → Crash Data flips to **Linked to identity**.
- `tracesSampleRate` becomes non-zero → add Performance Data.
