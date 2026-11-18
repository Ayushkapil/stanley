---
name: stanley-release
description: Ship a Stanley build - tests, optional server deploy to Fly, archive and upload the iOS build to App Store Connect, add it to the TestFlight "Friends" group, and record it in docs. Use only when Ayush asks to deploy, upload, or release a build.
disable-model-invocation: true
argument-hint: "<build number> [server]"
---

# Stanley release

Run each step only as far as Ayush asked (an upload alone, or server + upload).
Delegate the long runs (pytest, archive, export) to the `runner` subagent and
ask for results only.

1. **Preflight.** `git status` is clean on `main` (or the release branch);
   `cd server && .venv/bin/python -m pytest -q` passes. Note the count.
2. **Build number.** Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION`
   only if asked) in `ios/project.yml`, then `xcodegen generate` in `ios/`.
3. **Server (only if this build needs it or Ayush asked).** `fly deploy` from
   `server/`, then check `GET /health` on the Fly app. Record the Fly release
   number (vNN).
4. **Archive + upload.** `xcodebuild archive` into Organizer's folder
   ("Stanley <version> (<build>)"), then `xcodebuild -exportArchive` with the
   `upload` destination and `-allowProvisioningUpdates`. Expect "Upload
   succeeded"; the Sentry.framework missing-dSYM warning is known and harmless.
   `ITSAppUsesNonExemptEncryption` is false in `project.yml` (build 76+), so no
   compliance question should appear. If it does, Ayush answers it.
5. **TestFlight Friends** (pre-approved for every upload). In the built-in
   browser: App Store Connect → TestFlight → iOS Builds → the build → Groups
   "+" → **Friends** → a short "What to Test" note → Submit. Show Ayush the note.
6. **Record it.** Add the build's entry to `docs/reference/OPEN_ITEMS.md` (the
   release list) and the feature notes to `docs/reference/FEATURES.md`. Never in
   CLAUDE.md. Commit only if Ayush asks.
