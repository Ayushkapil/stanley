# Stanley — test suite coverage

> Moved out of CLAUDE.md on 2026-11-17.

## Tests

**774 passing** (`cd server && .venv/bin/python -m pytest`). Strong coverage of the
hard logic: physics (Hypothesis property tests across DST/timezones), full decay
lifecycle at exact boundaries, A1/A2, deletion cascades, block bidirectionality,
likes-no-count, Returned priority/dismiss/rest/tombstone, the circle's board
(a note each, newest first, edits in place, only your own to change or take
down, gone at the end of its author's day with or without the sweep, blocks
both ways, leaving takes yours, no counts, 200 characters, reporting with a
copy of its words, and the old single note moved across), shared
moments, mosaic windows, tags, milestones, auth hardening + SIWA, FK enforcement,
capture-race/orphan-blob safety, backups, nameless-vs-departed naming,
`new_account` on the first sign-in only (dev and Apple), Circle Posts
(`test_circle_posts.py`: off until asked for, the name and nothing else, never
the poster, only the circle posted to, blocks both ways, the retake quiet, a
refused post silent, a deleted account deaf, delivered after the response, a
failed push never failing the post), push (both notices
off until asked for, tokens registered, refused, moved between accounts and
removed on sign-out and deletion, delivery only after commit, a failed
delivery never failing the sweep, dead tokens dropped, the exact APNs
request and signed provider token, logging only without a key), renaming a
circle (organizer only), the Terms and Privacy pages (public, plain, the
same words as the app's, every numbered section present), account deletion
(nothing of the person left, a reported story stopping neither its photo's
deletion, its purge nor its author's account deletion), the app's safety
controls (your own blocks listed and never who blocked you, the owner alone
told whether deleting gives the day back, no reporting a story you couldn't
have read), report alerts (one fixed line after the commit, nothing without a
URL or for a refused report, a failing webhook never costing the report, the
URL never logged, and an autouse guard failing any test that would reach
ntfy), multiple circles
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
commit-before-response (capture commits before the background original
store; every route's session is function-scoped), and the production audit
(`test_production.py`: rate limits per address and per person, Fly-Client-IP
trusted only on Fly, security headers everywhere, no CORS, docs hidden, a
bare 500, `/health` failing with the database, token refresh, control and
bidi characters dropped, blank stories refused, oversized fields refused,
bad time zones never kept, files judged by their bytes, decompression
bombs, the word filter on every field a circle reads and never on reports,
ordinary words passing, Today's pages adding up to the whole feed with
moments unsplit, a failing digest not undoing the sweep, an unknown zone not
stopping digests, the disk warning, VACUUM, each hot query's index, event
lines without anyone's words, Held's faces, the moderation tool, and 240
concurrent requests on a file database), and the journal (`test_journaling.py`:
an entry only its writer can reach, never in the feed beyond the owner's
flag, bounded, cleaned and filtered, fading with the photo unless its owner
held it, gone with a delete, a purge or a let-go; a reflection filed under
its writer's week, Sunday after midnight included, one a week, paged,
private, never fading, with only the writer's own surviving photos; the
same question for the whole circle, forty weeks without a repeat, answers
sealed to the second and then open to everyone, closed once open, nothing
counted, blocks both ways, the circle journal from the week you joined,
reporting an answer only once it's readable, account deletion and export,
the writing rate limit, no notification, and the older database's report
column), and letters to the circle (`test_circle_letters.py`: written, read
back and rewritten as one letter a month; what a member is told about the
month the same to the byte whoever else has written; cleaned, bounded and
filtered; sealed to the second and then open to everyone who was there,
whether they wrote or not; nothing in the payload but ids and words, no
name, id or time of anyone's; shown in id order, not the order written;
closed once open, the traveller's late letter refused; the reveal waiting
for the last midnight in the circle; the sweep opening them unasked, stamped
with the moment they opened; joining afterwards reads nothing; a block
hiding no letter; seven days and then deleted, a sealed one never; taking
your own back before and after; leaving taking a sealed letter and leaving
an opened one; account deletion; the export; a report only once readable,
keeping the words and the writer and telling the reporter nothing; the
operator's takedown; no notification; the months, and the older database's
column), and the journal as a book (`test_journal_book.py`: a page written
and read back; one a day, written again in place; the day the writer's own,
the zone remembered and a bad one refused; the book oldest first, a stretch
at a time; three inks and no others; cleaned, its lines kept; a blank page
refused; ten thousand characters kept and one past the guard refused; not
run past the word filter; an edit keeping its day, an ink changed alone, no
edit to blank; a page torn out and the day free again; nobody else reading,
changing or removing one; in nothing anyone else is sent; no sign-in, no
book; no notification; no field that counts; the journal named, renamed,
cleaned and bounded; the writing pace; account deletion; the export; the
older database's column; the day; and, build 50, a page in more than one
ink: each stretch kept where it was written and read back as text, one ink
meaning no stretches, stretches cleaned with only the page's ends trimmed
and same-ink neighbours joined, only the three inks, never blank, never
longer than any page, the day written again in one ink forgetting them, an
edit ink by ink, a change of ink or new words making it one ink, stretches
that don't fit the words let go, the export, and the older database's
column), and the shared journal (`test_shared_journal.py`: a private page
only in its writer's book; a shared one in the circle's and still in its
writer's; private to shared and back; only the writer shares; writing
again leaving a page where it was unless told; inks kept; sharing needing
a circle you're in, and the one on screen; the word filter on shared pages
and rewrites and not on private ones; two writers facing each other and
every member sent the same spreads; an odd one out alone and last, and no
day nobody wrote; pairing as a pure function that gives each writer every
other in turn; days a stretch at a time; reading from the day you joined;
a block hiding a page both ways and changing nobody else's book; a heart
shown to the writer as a face and to nobody else; one each, taken back by
a second tap; none on your own page or a private one; no field that
counts; taking a page back taking its hearts; leaving and being removed;
tearing a shared page out; account deletion; reporting, with the report
keeping how the page began; the operator's takedown leaving the page in
its writer's journal; no notification; no fading; the export; no sign-in,
no book; and the older database's columns).
The filter looks themselves are checked in a macOS harness, not in pytest.
The phone has unit tests since build 61 (`StanleyTests`: when to offer to
ask about notifications, six; since build 63 the suggestion over a new
page, six more; since build 64 the capture's daily prompt turning at
local midnight, four more; and a day written out and read back on the
phone's calendar, four more; since build 65 the answer sheet's rules,
eight more; since build 66 what VoiceOver says and taking a mark back,
five more; since build 69 the title's ink on a journal's field, six more;
since build 70 a crash report leaving with no identifier, one, and the
policy's notice, five; since build 72 the sheet's months, four;
since build 73 the link's words, one; since build 74 the countdown's
flight path, eleven; since build 76 the opened cover's words, four, and the
cover colours' inks, one; since build 77 the offline queue's owner, three, and the heart and
bookmark's rollback, five; since build 79 the photos kept on the phone,
six; eighty in all). `tests/test_entries_build81.py` (build 81) holds the day's entry: a second entry refused, a third photo taken and a fourth refused, adding and removing within the day and both refused the next, the only photo not removable, the first's removal moving the next up, nobody else adding, `editable_today` the owner's alone, an old-shaped response still one photo in `urls`, no count on an entry, hearts and keeps on the entry and not a photo, every photo kept through purge or gone with the entry, the redo untouched by a removal, and the R2 reconcile naming every photo. `tests/test_moods.py` (build 65) holds
the mark on a day: today only, the person's own, in no shared response. `tests/test_local_days.py`
(build 64) holds every day a person lives as theirs in Bloomington, Delhi
and across a clock change. `tests/test_writing_prompts.py` (build 63) holds the
app's suggestions to the circle's questions, word for word.
Untested by nature: real-device SIWA,
live APNs, concurrency under real load.

