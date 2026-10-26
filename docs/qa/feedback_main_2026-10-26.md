# SETKEEP feedback fixes on main — 2026-10-26

## Scope and provenance

- Base: `30ce8899acb4d48346a3ec8728de537748439634` (`origin/main`).
- Source: PR #2, `bc39ef3a9fa5f96b023290bed2d6424b2b51da2d`.
- PR #2 targets `fix/friends-ux-local-integration`, whose base is 23 commits ahead of main. A separate branch from main applies only the five feedback fixes and their tests.
- Fixes: Android rest deadlines/notification expiry and exact-alarm permission guidance; serialized favorite updates; preferred-place B layout; thumbnail-to-guide navigation preserving workout state; detail mannequin front/back tapping.
- Main's existing workout-completion policy is retained. The source PR's test adjustment for another branch's completion policy is not applied.
- No package, lockfile, signing, video mapping, video, thumbnail, or model changes. The six proposed videos and the 34 background edits remain outside this change.

## Verification on this main candidate

- `flutter analyze --no-pub`: no issues.
- 161 unique unit/widget tests pass across the nine relevant suites: feedback (5), gym integration (11), gym details (11), catalog cleanup (8), widgets (87), existing media (15), home/rest/cloud revision (19), body recording (2), workout layout (3).
- Android ARM64 debug QA build succeeds. Four UI cases pass on the dedicated API 36 QA emulator: favorites after a real process restart, next workout and picker reopening; matching guide with weight `72.5` and deadline retained; native mannequin angle changes from front `0` to back `2`; B layout. Screenshots inspected.
- Android rest-action suite: eight active cases pass, including pause/resume, natural expiry retaining the ready/set action, and idempotent bound-set updates. The ninth host-gated notification boundary case is not executed.
- iOS simulator debug build succeeds. The same four UI cases pass on the dedicated iPhone 17 / iOS 26.5 simulator. Favorites are verified on disk before terminating the QA process, then verified after relaunch, the next workout and picker reopening. Front/back and B-layout screenshots inspected.

## Preparation issues resolved

The first isolated checkout lacked ignored licensed media and the trainer subapp's package configuration. Existing packages were restored offline and 108 original purchased videos plus 108 thumbnails were referenced locally without editing their contents. A test asset manifest created before those references existed was regenerated. The three affected suites then passed (107 tests); the other six suites passed (54 tests). No production code changes were needed for these setup failures.

## Limits and release state

- No physical Galaxy or iPhone installation/QA in this main-integration task.
- Deep-Doze/lock-screen host-gated checks are not rerun on this main candidate. Earlier evidence on the source branch is not counted as a pass here.
- iOS preferences use platform persistence. Restart QA waits for the stored favorites to flush before terminating the QA process; immediate-crash durability is not asserted.
- Exact Android deadline notifications depend on the user granting the existing system's alarms/reminders access. The UI explains delayed delivery when that access is absent.
- No TestFlight upload, tester distribution, or App Store submission. Video quality prerequisites remain outstanding.
- GitHub main is unprotected with no repository rulesets or required status contexts. Zero Actions/check runs is recorded as no CI execution, not CI success.
- The shared primary checkout's HEAD, dirty status and all 37 recorded file hashes are unchanged. The 216 locally referenced purchased-media hashes are unchanged.

Logs and native screenshots are kept in the task workspace under `feedback-main-20261026/`.
