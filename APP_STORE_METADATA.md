# Stanley: App Store metadata

What to paste into App Store Connect for the first submission, field by field,
with each limit checked. Written November 4, 2026, for build 33 (0.2.0).
Two answers in the brief clash with Apple's current rules; they're marked
**⚠️ Decide** below, with what each choice does.

## App information

| Field | Value | Length |
|---|---|---|
| Name | `Stanley - One Day, One Photo` | 28 / 30 |
| Subtitle | `A journal for your circle` | 25 / 30 |
| Primary category | Photo & Video | |
| Secondary category | Social Networking | |
| Copyright | `2026 Ayush Kapileshwar` | |
| Privacy Policy URL | `https://server-earnest-stream-9793.fly.dev/privacy` | |
| Support URL | `https://server-earnest-stream-9793.fly.dev/support` (live after the next `fly deploy`) | |

**Privacy Policy URL.** It answers today, but it serves the policy as of the
last deploy (Fly release v15, the November 1 wording). The November 4 policy
(the journal, the board) goes live only with `fly deploy`. Deploy before you
submit, so the URL matches what the app says.

**Support URL.** Apple's help for this field asks for "the entire URL,
including the protocol", leading to "actual contact information... so that
users can reach you". A `mailto:` link isn't a web page, so the server now
has a `/support` page (build 34), set like the Terms:
- "Stanley Support";
- "For questions, feedback, or issues, contact:" and the address, linked;
- "We'll get back to you within 48 hours.";
- links to the Terms and the Policy.

It's in the repo but **not on Fly until `fly deploy`**; until then the URL
is a 404, so deploy before entering it.

## Version information

**Promotional text** (126 / 170). It can be changed at any time without a new
build:

> One photo a day. Everything fades in six days unless someone keeps it. A quiet photo journal for the people you actually know.

**Keywords** (69 / 100):

```
photo,journal,circle,friends,memories,daily,decay,private,group,diary
```

App Store search already indexes the name and subtitle, so `photo`,
`journal` and `circle` spend 21 characters on words that are already
counted. An alternative with the same intent, if you want the room (91 / 100):

```
friends,memories,daily,decay,private,group,diary,polaroid,film,dorm,roommates,keepsake,fade
```

**Description** (3030 / 4000):

```
Stanley is a photo journal for a small circle: your floor, your house, your team, the people you actually know. You post one photo a day. It fades over six days. If someone in your circle reaches for it and keeps it, it stays.

That's most of it. The rest is what Stanley leaves out.

ONE PHOTO A DAY
Each day you get one photo in each circle you're in, taken with the camera or chosen from your library. Frame it, add a look if you want one (Mono, Grain, Dusk or Clean), say where it was and who was there, and post it. Then it's today's. Delete it the same day and you get one more try.

EVERYTHING FADES
Today is your circle's journal, newest first, and nothing else decides the order. Photos grow quieter as the days pass and are gone after six, unless someone keeps them. Keeping is the heart of Stanley: tap the bookmark on a photo and it lives on in your Held album at full light. The person who posted it sees the faces of who kept it. Nobody sees a number.

WHAT YOU REMEMBER
Under each photo, write what you remember. Mention a friend with @. Double-tap a photo to like it; only the person who posted it sees who did, and the likes fade with the photo.

THE BOARD
At the top of Today, everyone in the circle can pin one sticky note a day: plans for tonight, a lost scarf, quiet hours before a midterm. Only you can change yours, and it clears at the end of your day.

A QUESTION EACH WEEK
Every week your circle gets one question. You answer it privately, and nobody can read anyone's answer until the week's end. Then everyone's open at once, and they're kept in the circle's journal.

YOUR OWN PAGES
Add a private journal entry to your own photo. On Sunday evening, Stanley asks how your week was. What you write for yourself is read by no one else, ever.

THE WORLD TODAY
A morning paper, kept apart from your circle: the day's headlines laid out like a front page, with stories from near you if you share your location. Read a story in place, or open it in full. No likes, no shares, no comments.

WHAT STANLEY DOESN'T DO
No followers. No public profiles. No like counts, no view counts, no streaks. No algorithm choosing what you see, and no ads. Two notifications exist, and both stay off until you turn them on. Up to five circles, each one mutual by invite code, and each one made for the people you'd actually call.

PRIVATE BY DESIGN
Every photo is stripped of its location data. A place you add is only the words you choose. If you delete a photo, it's gone everywhere, even from the albums of friends who kept it; they're left with a quiet note that a memory was here. Stanley doesn't sell your data or use your photos to train anything. You can export your memories, or delete your account, whenever you like.

WHO IT'S FOR
People who miss when photos were for each other. A dorm floor, roommates, a running group, a family spread across time zones. Anyone who'd rather have six days of something real than a feed that never ends.

One day, one photo. The moments that last are the ones someone reached for.
```

Every claim in it is something the app does, checked against CLAUDE.md:

- **One a day, one redo:** one photo a day in each circle, and deleting today's
  photo gives the day back once.
- **Fading and keeping:** a photo fades over six days unless held. Only the
  poster sees who held it, as faces, never a count.
- **Likes:** owner-only, and they fade with the photo.
- **The board:** one note per person a day, only its author can change it, and
  it clears at the end of their day.
- **The weekly question:** answers are sealed until the week's end.
- **Private writing:** journal entries and reflections are read by no one else.
- **Notifications:** two, both off by default.
- **Location:** GPS is stripped from every photo.
- **Deletion:** a deleted photo leaves a tombstone in friends' albums.
- **Data:** export and account deletion exist.

The description names no news outlet. If you'd like them credited, "from PBS
NewsHour, or the BBC outside the US" fits in the World paragraph.

## Age rating

App Store Connect → the app → App Information → Age Rating. Answers as briefed,
with the questions the brief didn't list taken from `PRODUCTION_CHECKLIST.md`:

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use | None |
| Simulated Gambling | None |
| Horror/Fear Themes | None |
| Mature/Suggestive Themes | None |
| Graphic sexual content, guns or weapons, medical or wellness topics | None / No |
| Gambling, contests, loot boxes | No |
| Parental controls · Age assurance | No · No |
| Messaging and chat | No (stories are comments on a photo within a circle; there are no direct messages) |
| Advertising | No |
| User Generated Content | **Yes** |
| Social media (a feed of other people's posts) | **Yes** |
| Unrestricted Web Access | **Yes** (as briefed) **⚠️ Decide**, see below |

**⚠️ Decide: Unrestricted Web Access.** Apple defines it as "Users can navigate
to any webpage within the app or freely browse the web. May include: embedded
browser functionality or browser app." In Apple's current base table it
**sets the rating to 16+**. User-generated content is 4+; social media is 13+.
So:

- **Yes (as briefed): Stanley is rated 16+.** The Terms say 13 is the minimum
  age, so the store would say 16 while the Terms say 13. Pick one: raise the
  Terms to 16 (and the in-app copy, `legal.py` and `Legal.swift` together), or
  accept that the store is stricter than the Terms. A dorm-floor pilot is
  unaffected; a 13 to 15 year old couldn't download it where ratings are
  enforced.
- **No: Stanley is rated 13+**, from social media. This is
  `PRODUCTION_CHECKLIST.md`'s answer. The World tab opens a publisher's article
  in Safari's in-app viewer, which has no address bar, and Stanley offers no
  way to go to an address of your own. A reader can still follow links on the
  publisher's page, so a reviewer could call it a Yes.
- If you answer No and review disagrees, the fix the checklist names is to
  open articles in Safari itself, outside the app. Then the answer is a clean
  No.

Either way, in Australia social media alone maps to 16+, per Apple's
regional table.

## Screenshots

`ios/AppStoreScreenshots/`, JPEG, light mode, status bar at 9:41 with full
bars:

| Folder | Size | Taken on | App Store Connect slot |
|---|---|---|---|
| `6.7/` | 1290 × 2796 | iPhone 17 Pro Max simulator (1320 × 2868), scaled | **6.9" display** (required; 1290 × 2796 is accepted there) |
| `6.1/` | 1179 × 2556 | iPhone 17 simulator (1206 × 2622), scaled | 6.3" display (optional; App Store Connect scales the 6.9" set if absent) |

Each set, in upload order:

1. `01-today.jpg`: Today, with the circle's board (Maya's note first, four
   more to swipe), this week's question answered and sealed until Friday at
   7 PM, and the first of today's prints.
2. `02-capture.jpg`: the capture sheet. A sunset field with Grain on, the
   place filled in from the phone ("Indiana University"), a caption, and
   Jonah and Ines tagged.
3. `03-held.jpg`: Held, the album. "Kept from Ines Moreau", a rooftop print
   held since October, and Jonah Reyes's page beginning.
4. `04-you.jpg`: the You tab. Maya's bookplate, the circle's faces with
   **Invite** at the end, and a milestone.
5. `05-world.jpg`: The World Today, PBS NewsHour's edition. **⚠️ Read the
   caveat below.**
6. `06-weekly-question.jpg`: the circle journal. Last week's question ("If
   you could give this week a color, what would it be?") with everyone's
   answers open, names in their own colors.
7. `07-stories-optional.jpg`: an extra, if you want a seventh. Movie night
   with stories and who was there, then a shared moment at Griffy Lake.

How they were made:

- **Seeding.** `server/scripts/seed_screenshots.py` seeds the circle. As of
  this build it also adds last week's and this week's question, and Maya's own
  note. "Third Floor" is eight people with three days of photos, stories, a
  shared moment, notes and a Held album.
- **Photos.** Every photo is drawn in code (`server/scripts/scenes.py`):
  nobody's real photos, and no stock licence.
- **The camera.** The capture shot uses the simulator's camera stand-in, a
  drawn `golden_field` saved as `SampleCapture.jpg`.

Caveats:

- **World shows real headlines from the day after the 2026 midterms:**
  "Democrats win control of U.S. House, in major rebuke to Trump" and similar.
  A store page carrying partisan-sounding headlines from a real outlet may put
  people off, and PBS's feed terms haven't been checked for this use. Options:
  - retake on a quieter news day (seed, run the server with news on, and
    shoot the World tab alone);
  - leave World out and upload six without it (01 to 04, 06, 07);
  - keep it.

  I didn't invent headlines: a fake front page under a real outlet's name
  isn't something to publish.
- **Today shows one photo, not three or four.** Prints are full width, so the
  first screen holds the board, the question and the top of the first photo;
  `07` is the one with more photos in it. A screen with three or four photos
  would need smaller prints than the app draws.
- **The drawn photos read as illustration up close,** as noted in the
  production audit.
- The older set in `ios/AppStore/Screenshots/` (from the production audit, with Settings in
  place of the question) is removed; it's in git history if you want it.
