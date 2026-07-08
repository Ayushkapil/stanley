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
  user-typed location labels (a free-text string like "Dunn Meadow" — never
  device GPS), who-was-there tags, and report text.
- [ ] Emails or Text Messages / Audio / Gameplay / Customer Support — **not collected.**

### Identifiers

- [ ] **User ID — COLLECTED · Linked to identity · Not used for tracking.**
  Stanley issues an opaque account ID (the JWT subject) and stores the SIWA
  `sub` to recognize repeat sign-ins. Required for accounts to exist.
- [ ] Device ID — **not collected** (no IDFA, no IDFV use).

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

Health & Fitness, Financial Info, **Location (precise and coarse — the app
never requests location permission; photo locations are typed labels and EXIF
GPS is stripped)**, Sensitive Info, Contacts, Browsing History, Search
History, Purchases, **Usage Data (no analytics, no product-interaction
telemetry, no advertising data — nothing in the app records taps, views, or
launches)**, Surroundings, Body, Other Data.

---

## Honest footnotes (not label categories, but say them if asked)

- The server stores the device's **IANA timezone string** (e.g.
  `America/New_York`) sent with each capture — it defines "one photo per local
  day". It is not a location under Apple's definitions (no GPS/network
  derivation) and has no label category.
- Push notifications: when APNs is wired, the server stores a **device push
  token**. Tokens exist to deliver the single last-light notice/digest and are
  not an Apple label category by themselves.
- Data deletion: account deletion cascades — photos, blobs, comments, holds
  all purge. Owner-deleted photos purge everywhere immediately.

## Re-derive this label when…

- `.email` is added to SIWA `requestedScopes` → Email becomes Collected.
- Any analytics/telemetry SDK is added → Usage Data changes, and the "no
  counts, no engagement signals" product rules deserve a second look anyway.
- `SentrySDK.setUser` or custom Sentry events/breadcrumbs with user data are
  added → Crash Data flips to **Linked to identity**.
- `tracesSampleRate` becomes non-zero → add Performance Data.
