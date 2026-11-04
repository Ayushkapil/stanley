# Stanley: a heuristic evaluation

November 4, 2026 · build 31, with fixes in build 32 · one evaluator

## Method

A heuristic evaluation against Nielsen's ten usability heuristics, plus four
lenses the brief asked for: information architecture, gestural vocabulary,
emotional design and accessibility. Each finding is rated:

| Rating | Meaning |
|---|---|
| **Critical** | Blocks use or loses data |
| **Major** | Confusing or frustrating; affects the experience |
| **Minor** | Cosmetic, or nice to have |
| **Note** | An observation; no action needed |

There were three kinds of evidence:

- **Walkthroughs.** Every main flow on the iPhone 17 Pro simulator (iOS 26.5)
  against a local server, in light and dark mode, plus the Duo's cover
  display. Most screens had already been walked in the QA audit and its
  build 31 follow-up (`docs/qa-2026-11-04/`).
- **A code read** of every view, for labels, gestures, confirmations,
  dismissal and copy.
- **Measured contrast:** WCAG 2.1 relative luminance, computed from the
  palette's own values.

Screenshots are in `docs/hci-audit/`.

**Limits.** This is one evaluator, not three to five. VoiceOver wasn't run
live: the simulator has no scriptable screen reader, so the VoiceOver findings
come from reading the code. No real users took part. Nothing was tested on
hardware.

## Summary

19 findings: 1 critical, 7 major, 6 minor, 5 notes. **Build 32 fixes 14 of
them**, including the critical one and six of the seven majors.

| ID | Heuristic | Finding | Severity | Status |
|---|---|---|---|---|
| C1 | 9, 5 | An error raised inside a sheet closed the sheet: a note's words were lost, and a refused post would lose the framed photo | Critical | Fixed |
| M1 | 3, 5 | A swipe down on the capture sheet after the shutter threw away a camera photo that no library holds | Major | Fixed |
| M2 | 9 | The note editor closed before the server answered, so a note that failed lost its words | Major | Fixed |
| M3 | A11y | Small capitals were a fixed 10pt and ignored Dynamic Type | Major | Fixed |
| M4 | A11y | Secondary text on the light paper measured 3.2:1, under AA's 4.5:1 | Major | Fixed |
| M5 | A11y, 1 | VoiceOver said nothing of a photo (whose it is, how far it has faded), and liking or holding had no spoken action | Major | Fixed |
| M6 | 10, 6 | The gestures and parts of the journal were explained nowhere except the empty Held page | Major | Fixed |
| M7 | 2, 4 | The note editor, report sheet, profile editor and place picker are plain system forms inside the journal | Major | Open |
| m1 | 6, 4 | In Held on a phone, resting a memory was only a swipe, with nothing to show it was there | Minor | Fixed |
| m2 | 7 | The note editor opened without the keyboard | Minor | Fixed |
| m3 | 9 | "too_soon" and "circle_full" didn't say what to do | Minor | Fixed |
| m4 | 3 | A swipe down on the journal entry sheet dropped unsaved words | Minor | Fixed |
| m5 | A11y | Spring's and Warm's accents are 2.5:1 on paper, below the 3:1 icons need | Minor | Open |
| m6 | 8 | Today's first screen fills with the board and the question before the first photo | Minor | Open |
| N1 | 1 | Decay is shown only by the fade and the last light's glow | Note | By design |
| N2 | 5 | Posting to the wrong circle is well guarded | Note | — |
| N3 | 3 | Destructive actions are confirmed throughout | Note | — |
| N4 | IA | Five tabs; World sits outside the circle's purpose | Note | — |
| N5 | 7 | Few accelerators; a Home Screen quick action would be the obvious one | Note | Suggestion |

## 1. Visibility of system status

**Good.** Status is said quietly and almost always.

- **Offline is a state, not an alert.** A line under every masthead says
  Stanley is offline, and the app catches up by itself.
- **Posting is visible.** Post holds a spinner. A photo queued with no
  signal gets its own "waiting to upload" card where it will land. The
  success haptic fires only once the photo is really up.
- **Loading.** Empty states wait for the first answer (`todayLoaded`,
  `memoriesLoaded`), so "Nothing here yet" never flashes while photos load.
- **Decay (N1, Note).** Decay is ambient: the photo fades, and in its last
  day it gets a warm edge. There's no countdown, on purpose: the locked
  rules forbid deadlines. A sighted person learns to read it. But until this
  pass a VoiceOver user got none of it (see M5).

**M5 (Major, fixed).** The photo was an unlabeled image. VoiceOver now says
"Photo by Theo", "Photo by Theo, fading" or "Photo by Theo, in its last
light" ("Your photo" for your own). These are words for what the fade
shows, never time left. The photo also offers Like and Hold as VoiceOver
actions, since a double-tap doesn't reach a screen reader's activation and
the long-press menu is hard to find with one.

## 2. Match between system and the real world

The journal metaphor is strong and mostly unbroken. Each page has a masthead
and dateline, photos are prints on paper, people's words are in a hand,
rules stand in for boxes, notes are taped on, and the circle gate is now
the first page of the journal. The vocabulary fits it too: "hold",
"let go", "rest this memory", "a memory was here", "kept from".

**M7 (Major, open).** Four places are still plain iOS forms:

- **The note editor** (`note-editor-system-form.jpg`). This one hurts most:
  you see a sticky note on the board, tap it, and are handed a grouped
  system text field. Every member writes here every day.
- **The report sheet.**
- **The profile editor.**
- **The place picker.**

The fix is visual only: write the note on the note itself (its paper, its
tape, a hand on a ruled line), as the gate did in build 31. That's design
work rather than a defect, so it's left for a design pass.

**Deliberate exceptions (Note).** These are right as they are:

- The Terms and Privacy Policy are set as legal text, on purpose.
- Settings keeps iOS's grouped rows under a journal masthead, which reads as
  "the machinery".

## 3. User control and freedom

- **Exits.** Every sheet has one in its bar: Cancel, Not now, Done or Close.
- **Reversible gestures.** A like and a hold are toggles. A rested memory
  comes back from Rested ("let it return"). Unblock restores a thread
  intact.

**M1 (Major, fixed).** After the shutter, a stray swipe down closed the
capture sheet. That threw away the photo, its words, its place and who was
there. A camera photo isn't in the library, so it was simply gone. Now:

- The sheet can't be swiped away once there's a shot, or while it's posting.
- **Not now** asks first: "Discard this photo? It hasn't been posted.
  Today's photo is still yours to take." (`capture-discard.jpg`)

**m4 (Minor, fixed).** The journal entry sheet now holds against a swipe
while it has unsaved words, as the weekly reflection already did. The note
editor does the same. Cancel still leaves on purpose.

**N3 (Note).** Each serious action has its own alert:

- Delete Photo (which says whether you get the day back)
- Remove Me from This Photo
- Block
- Leave Circle
- Reset Code
- Delete Account
- Take Down Note
- Delete Entry
- Delete Reflection

A deleted photo can't be undone, which is right: the subject wins on
deletion.

## 4. Consistency and standards

- **One gesture, one meaning.** A long press is always the menu: on prints,
  stories, notes, reflections, and on the Duo's Held. A double-tap on a photo
  always likes it. A tap on the current tab always goes to the top. Return
  sends a story, and since build 31 the circle gate's code and name. (In
  the note and the answer, Return starts a new line, as in any multi-line
  field.)
- **Visual language.** One spacing scale (8, 16 and 32pt), one rule, one way
  of writing small capitals, one wide button. Dark mode is a consistent
  "dark room" on every page.

**m1 (Minor, fixed).** Held was the one inconsistency. On the Duo, a long
press rests a memory; on a phone, only a swipe did, with nothing to show it
was there. The phone now has the same long-press menu, and keeps the swipe.

## 5. Error prevention

**N2 (Note).** Posting to the wrong circle is well guarded:

- With more than one circle, the capture sheet says whose day it is ("for
  Quiet House").
- A queued photo carries its circle.
- The server refuses a circle you aren't in, rather than quietly switching.

The day's slot is claimed at the shutter, and a race is a 409, never a double
post. Disabled buttons prevent empty notes, answers and codes. Text is
clamped to each field's limit as it's typed.

**C1 (Critical, fixed).** Found while testing the note editor offline
(`error-closed-sheet-before.jpg`). Errors were shown by an alert attached to
the app's root view, and to show itself that alert closed whatever sheet was
open. A note that couldn't pin vanished with its words. The same path would
have closed the capture sheet and lost the framed photo, its caption and its
tags when the server refuses a post (too soon, or words not allowed). Errors
are now presented by UIKit over whatever is on top, so the sheet and
everything in it stays (`error-over-sheet-after.jpg`).

## 6. Recognition rather than recall

**M6 (Major, fixed).** Most of what Stanley asks of a person is visible:

- The heart and the bookmark sit on every photo.
- "What do you remember?" waits under it.
- The board shows a blank note to fill.
- The question sits in a slip.
- The circle's name carries a chevron that says it opens.

But the shortcuts were learned by accident: a double-tap likes, a long press
opens the menu, the board swipes, a tap on the current tab goes to the top.
How to keep a photo was explained only on the empty Held page, which a person
sees once if at all. So:

- **Onboarding** now says it: "Tap the bookmark on any photo to keep it."
- **About Stanley** has a short "How it works": the "+", the bookmark and the
  press-and-hold, the double-tap and who sees it, the stories and the @, the
  board, the weekly question, the Sunday reflection, and a tap on the
  current tab.

Nothing needs remembering across screens. A member's profile carries their
own photos, and the invite code is one row away in Settings.

## 7. Flexibility and efficiency of use

- **Accelerators:**
  - a double-tap to like
  - a re-tap on a tab (to the top, or refresh at the top)
  - Return to send
  - the long-press menu
  - a library photo instead of the camera
  - favorites and recents for places
- **Duo.** The Duo's inner display gets denser layouts rather than features.

**m2 (Minor, fixed).** The note editor opened without the keyboard, so every
note took a second tap on the field (`note-editor-system-form.jpg`). It now
opens ready to write.

**N5 (Note, suggestion).** The one obvious accelerator missing is a Home
Screen quick action ("Take today's photo"). It's harmless to the rules: it
opens the same sheet, which knows if today is already shared.

## 8. Aesthetic and minimalist design

Stanley earns this one structurally: no counts, no badges, no ranking, and two
notifications, both off. Most elements earn their space.

**m6 (Minor, open).** Today's first screen can fill with the circle's own
furniture before any photo:

- the board (a full-width note and a peek of the next)
- the weekly question (three lines for the longer ones)
- on Sunday or Monday the mosaic, and sometimes a Returned card

Then come the day's photos, which are the point. On the 17 Pro with an
answered question, the first photo begins about two-thirds down. Options,
none tried here:

- fold an answered question to a single "You answered" line
- show the board one note high with no peek
- let the first photo come before the question

## 9. Help users recognize, diagnose and recover from errors

The copy is warm and never technical. No status code, server string or system
description reaches the screen. A failed upload says the day is still open,
and no signal never fails at all: the photo is queued. The best line is
`slot_used`'s "Today's moment is out there. Come back tomorrow."

- **M2 (Major, fixed).** The note editor closed the moment Post was tapped.
  If the note failed, the error came up but the words were gone; a failed
  story's words come back into its field. The editor now waits ("Pinning…")
  and closes only once the note is on the board.
- **m3 (Minor, fixed).** Two messages explained nothing:
  - "too_soon" was "A little too soon — the day needs room to breathe." It
    now says photos in a circle are twelve hours apart and to try again
    later.
  - "circle_full" was "This circle has reached its limit." It now offers the
    way forward: "You could start one of your own."
- **Note.** "That isn't yours to change." (any 403) is the one line with an
  edge to it. It's rare, since the app doesn't offer what you can't do.

## 10. Help and documentation

Onboarding is three pages: one photo a day, everything fades, a small circle.
It's good at the why. Setup then asks four plain questions, and the circle
gate explains itself. Until this pass, the how was missing (M6, fixed above).

**Note.** About Stanley still has no way to reach a person. The Terms and
Privacy Policy carry the contact address. For a closed pilot that's fine.

## Information architecture

Five tabs: **Today · Held · You · World · Settings**. The first three are the
product: the circle now, what you've kept, and yourself.

**N4 (Note).**

- **World** is the odd one out: a morning paper unrelated to the circle. It's
  kept apart on purpose, so news never enters memory surfaces.
- **Settings** as a tab is unusual in iOS but suits five.

**Can a new person find everything in 30 seconds?**

| Want to… | Where | Found by sight? |
|---|---|---|
| Take today's photo | "+" atop Today, or the empty page's camera | Yes |
| Like / keep a photo | Heart and bookmark on the photo | Yes |
| Write a story | "What do you remember?" under a photo | Yes |
| Leave a note | The blank note on the board | Yes |
| Answer the question | The slip under the board | Yes |
| See what's kept | Held tab | Yes |
| Switch circles | Chevron on the circle's name, or Settings → Circle | Mostly: the chevron is small |
| Invite someone | Settings → Invite Code | Takes a moment |
| Find rested memories | The moon in Held's masthead | Not obvious, rarely needed |
| Report or block | "…" on a print; foot of a profile | Yes |

**Recommendation.** Inviting someone is the action that grows the pilot,
and it sits two levels into Settings. A "Invite someone" line in the circle's
name menu, or on an empty board, would put it where people are.

## Gestural vocabulary

| Gesture | Means | Where | Consistent? |
|---|---|---|---|
| Tap | Open / act | Everywhere | Yes |
| Double-tap | Like (unlike if liked) | A photo, only | Yes, with a visible heart button too |
| Long press | The menu | Prints, stories, notes, reflections, Held | Yes (since m1) |
| Press and hold to keep | Hold | Prints, but the menu takes the press first, so it's "long press → Hold" | Yes, documented |
| Horizontal swipe | Next note | The board | Yes, with dots and a peek |
| Swipe left | Rest a memory | Held on a phone | Now also in the menu |
| Pull down | Refresh | Today, Held, You, World | Yes |
| Re-tap a tab | To the top, then refresh | Today, Held, You, World | Yes |

Every gesture has a visible way to do the same thing, or a visible cue: the
board's swipe has its dots and the peek of the next note. Since m1, no action
is reachable only by a hidden gesture.

## Emotional design

- **Warm:**
  - the paper and its grain
  - handwriting for anything a person writes
  - prints that lean a little
  - the dark room for night
  - haptics only for deliberate acts
  - copy that never shouts ("A memory was here", "Still writing this
    part…")
  - the absence of numbers
- **Cold spots:**
  - **System alerts.** UIKit's glass alerts are the coldest moments, and
    they come at the moments that matter: delete, discard, an error. They
    tint with the accent but are otherwise iOS.
  - **The plain forms (M7).**
- **Cold by intent:** the legal pages. That's correct.

## Accessibility

- **M3 (Major, fixed).** The small capitals were a fixed 10pt. They carry
  real information: the date, "Your answer is private until Friday at 7
  PM", section labels, "Only you see this". They were the one text in
  Stanley that never grew. They now scale with Dynamic Type from
  `.caption2`, and wrap cleanly at the largest standard size
  (`dynamic-type-xxxl.jpg`). The World tab's dateline, publisher line and
  bylines, also fixed sizes, scale too. The handwriting (`Font.hand`)
  already scaled.
- **M4 (Major, fixed).** In light mode, `.secondary` text on the paper
  measured 3.2 to 3.3:1 on every mood. AA asks 4.5:1 of small text, and the
  small capitals are all small text. It's now the system's secondary gray
  at 75% instead of 60%, at 4.6 to 4.9:1 on every mood, set once beside the
  dark room's ink. Dark mode was already at 4.6:1 and is unchanged.
  - First try: set at the app's root, the three-level style reached the tab
    bar's symbols and drew the selected tab in ink.
  - Now: it's set inside each tab, with a single ink above the tab bar, so
    the selected tab keeps its accent.
- **M5 (Major, fixed).** Photos are described and have spoken actions (see
  heuristic 1).
- **Labels.** Every icon-only control has a label: the "+", the heart, the
  bookmark, the "…", the faces button, the journal book, the circle
  switcher, the camera rings.
- **m5 (Minor, open).** The accent is used as text and icon color: the "+",
  "Choose from library", the place pin, links. Measured on the paper:

  | Mood | Contrast |
  |---|---|
  | Fall | 5.1:1 |
  | Rain | 4.3:1 |
  | Cool | 4.0:1 |
  | Warm | 2.6:1 |
  | Spring | 2.5:1 |

  Spring and Warm are below even the 3:1 that icons need. Each mood keeps
  an `ink` for labels on an accent fill (5:1), so it's only text and icons
  in the accent itself. Deepening those two accents is a palette decision;
  they were redrawn from palette sources in build 20, so it's left for the
  product.
- **Note.** A disabled wide button's label is about 1.8:1. WCAG exempts
  disabled controls, and the dimness is the signal.
- **Note.** Noteworthy Light is thin at the smaller hand sizes (16pt
  secondary lines). It scales, but a low-vision reader may prefer the
  system font. An "easier to read" option would be the place for it.
- **Not checked:** VoiceOver end to end on a device, Switch Control, Voice
  Control names.

## What changed in build 32

| Finding | Files |
|---|---|
| **C1** Errors said from the top without closing sheets | `StanleyApp.swift` (`Spoken`) |
| **M1** Capture sheet: no swipe away after the shutter, and Not now asks | `CaptureView.swift` |
| **M2, m2** Note editor waits for the server and opens with the keyboard | `NoteBoard.swift` |
| **M3** Small capitals and World's small type follow Dynamic Type | `Journal.swift`, `WorldTodayView.swift` |
| **M4** Light-mode secondary ink deepened to AA | `StanleyApp.swift` (`DarkRoomInk`) |
| **M5** Photos described to VoiceOver, with Like and Hold actions | `TodayFeedView.swift` |
| **M6** "How it works" in About Stanley; onboarding says how to keep | `AboutView.swift`, `OnboardingView.swift` |
| **m1** Held's long-press menu on a phone | `MemoriesView.swift` |
| **m3** Two error messages say what to do | `APIClient.swift` |
| **m4** Journal entry sheet holds against a swipe while edited | `Writing.swift` |

## Open, in order

1. **M7.** Write the note editor on the note itself, then the report sheet,
   the profile editor and the place picker, in the journal's look.
2. **m5.** Deepen Spring's and Warm's accents to at least 3:1 on paper
   (4.5:1 where they're text).
3. **Invite.** Put "Invite someone" where people are: the circle menu, or an
   empty board.
4. **m6.** Let Today's first photo come sooner (fold an answered question).
5. **N5.** A Home Screen quick action for today's photo.
6. **VoiceOver.** A live pass on a device.
