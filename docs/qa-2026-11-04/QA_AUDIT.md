# QA audit, November 4, 2026 (build 30)

A pass through Stanley as a tester trying to break it, before App Store
submission. It ran on the iPhone 17 Pro simulator (iOS 26.5) and the iPhone Duo
simulator's cover display (iOS 27.1), against a local server on a fresh copy of
the screenshot circle (`seed_screenshots.py`), with a local listener standing in
for the report webhook. Screenshots are in this folder.

## Fixed in this build

1. **The app turned with the phone.** `project.yml` set
   `INFOPLIST_KEY_UISupportedInterfaceOrientations`, a build setting that only
   reaches a *generated* Info.plist; Stanley has its own, so the key never got
   there, and every screen rotated to landscape, which nothing was laid out
   for. The key is now in the plist itself (portrait only); checked by turning
   the simulator: the app stays upright.
2. **The empty Today hid its own camera.** With the note row and the weekly
   question above it (both new since the empty page was designed), the 90pt
   ring and "Take today's photo" fell under the tab bar, half covered
   (`01-empty-today-before.jpg`). The camera is now a row inside the empty
   page's sheet, above the fold (`02-empty-today-after.jpg`).
3. **"That username is taken." and "Available." were hard to read.** The
   system orange and green on the light paper are about 2:1
   (`03-username-taken-before.jpg`). Both are a deeper shade in light mode now
   (dark mode keeps the system's own), in setup and the profile editor.
4. **The circle never caught up after launch.** Someone joining your circle,
   or you joining another on a different phone, didn't show in Settings →
   Members, the mention bar or the circle list until the app was relaunched:
   only reconnecting reloaded it. And CLAUDE.md promised a circle picker in
   Settings once you're in more than one, which didn't exist. The circle now
   reloads on Today's pull and tab tap, when Settings opens and when the app
   returns to the front; Settings → Circle has the picker (checked: switched
   from QA House to Third Floor, and Today followed).

## Found, not fixed

- **The circle gate looks like a system form** (`05-circle-gate.jpg`): a bare
  large title over grouped rows, unlike the journal pages around it. It works;
  it's the first screen a new person meets after setup, so it's worth a design
  pass.
- **The empty Today's sheet still ends under the tab bar** on a 6.3" phone;
  the action is visible and the page scrolls, so it's cosmetic.
- **The glass tab bar over photos** loses the selected tab's ink (light photo
  in dark mode, dark photo in light mode), as already noted in CLAUDE.md. An
  iOS 26 glass effect; not fixed.
- **The capture sheet's "In your words" label** sits partly under the Post
  footer until you scroll the sheet.

## Checked and working

- Fresh install → onboarding (three pages) → dev sign-in → name → username
  (live check: taken, then available) → bio → photo from the library (crop,
  upload) → circle gate → create a circle → empty Today.
- First photo: location asked at the shutter, the place filled in from where
  the phone is ("Indiana University"), each filter rendered differently (Mono,
  Grain, Dusk, Clean; the server kept `clean`), posted with the success
  haptic; the journal slip under it, an entry kept, the book on the print; a
  like and a hold.
- Joining by code (also typed lowercase without the hyphen), switching
  circles, the weekly question and the note row in both circles.
- Through the API, with a second and third person: a block hides their photos,
  notes and profile in both directions, and unblocking brings them back; a
  report returns 201, logs its WARNING line and POSTs exactly once to the
  webhook with the fixed text; a deleted photo leaves everyone's Today at once
  and its holder keeps a tombstone; a deleted account leaves no name,
  username, stories or memberships.
- Offline: stopping the server shows "Offline · it all catches up when you're
  back" under the masthead and keeps the page (`06-offline.jpg`); restarting it
  reloads Today within a few seconds with nothing tapped.
- Light ↔ dark mid-use and an atmosphere change (Auto → Fall) mid-use apply at
  once on every tab (`07-dark-fall-today.jpg`, `08-dark-you.jpg`).
- The Duo's cover: an expired sign-in signs out once, in words; signing in
  lands on Today with the "+", the note row and the question, beside the side
  dock.
- World's empty state ("No stories right now.") with news off.

## Not verified this pass

- **Links after 20 minutes.** Signed links last 15 minutes; renewing them on a
  403 (`SignedImage`, `AppState.linksExpired`) was verified in build 21. Not
  re-run: it needs a page left open for a quarter hour.
- **@mentions in a story.** The simulator's taps land late while a page is
  still scrolling, and the story never reached the field. Mentions are
  client-side and were verified in build 19.
- **The circle-name menu atop Today.** The simulator's synthetic taps don't
  open that menu (it opens from Settings' picker and on a real phone).
- **Pull to refresh and tab-tap-to-top on every tab.** Today's, with its
  haptic, was checked in build 28; Held, You and World use the same code.
- **The inner display of the Duo, and any real device.** Unchanged from
  CLAUDE.md's open items.
