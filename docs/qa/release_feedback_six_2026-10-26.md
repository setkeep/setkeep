# Feedback and approved guides: release composition, 2026-10-26

The normal dirty checkout remained on the older local integration source. Its APK generated at 21:48 UTC was version 1.0.0 (7), lacked the B-place and new rest/guide markers in its debug kernel, and bundled none of the six newly approved guides. Its SHA-256 is `e8527622568dd2dbfe8ceb8c536f457e7de04b61cbae93e2ec5e5ecba196a029`. This is a likely explanation of the owner's missing-place and missing-mannequin reports, not proof of which binary is currently installed: the Galaxy disconnected before its post-install state could be read.

## Preserved release baseline

- The last confirmed distributed iOS build is 1.0.0 (17). Its archived bundle and the retained build 18 candidate both include the main app, RestTimerWidget, and Watch companion.
- The existing build 18 source snapshot has the same Watch/widget source, Xcode project, startup UI and ad code as the distributed build 17 source. These existing features are retained. The separate newer AdMob candidate was not applied.
- The six old original guides in that source snapshot exactly match the APK read from the Galaxy before the owner's manual install. Their bytes remain unchanged.
- This release branch starts from the already tested feedback branch `bc39ef3a9fa5f96b023290bed2d6424b2b51da2d`, reconciles the retained source snapshot, and adds the six guides from `4711d1438615f5f559da943ae835c391645277dd`. It is deliberately separate from main; do not merge its older local feature history wholesale into main.
- Runtime differences against the retained source snapshot are exactly the five-feedback implementation files and the exercise media catalog. Purchased mappings (109 / 108 unique clips) and all 216 licensed video/thumbnail files remain unchanged. All 12 original guides have exact source hashes, with 121 total media identities.

## Validation

- Flutter analysis: no issues.
- Full application suite: 675 passed, 3 failed. The failures were stale fixtures for the B layout and for the newly approved original guides. Only those tests changed after this run.
- Rerun of all three affected files plus feedback and approved-guide tests: 30 passed, 0 failed. No unresolved test failures remain. This is not a claim that the initial full invocation passed.
- Earlier isolated native runs verified the five feedback cases and six-guide routes/playback on the dedicated Android emulator and iOS simulator. Those runs are not physical Galaxy proof and were not repeated on this composed binary.
- Fresh normal-entry Android arm64 profile build: 1.0.0 (8). Its signed APK contains the expected B-place, rest-permission and workout-guide markers. All 240 declared video/thumbnail files match their source hashes. Existing debug/profile signer matches both the previously read Galaxy package and the owner's 21:48 local APK.
- No device installation, automatic phone UI operation, data deletion, or permission grant occurred in this continuation.

## Requirement-to-device status

| Requirement | Main / composed source | Built APK (8) | Current Galaxy |
| --- | --- | --- | --- |
| Lock-screen rest deadline/notification/nonnegative recovery | Implemented, prior tests recorded | Included | Unverified after owner install |
| Favorites across picker/restart/next workout | Implemented, regression tested | Included | Unverified after owner install |
| B layout: preferred place above compact others | RegisteredGymsPage, opened from My Page → 利用場所 | Included | Owner reports missing; unresolved |
| Thumbnail guide and return preserving inputs/timer | Picker and workout routes implemented | Included | Unverified after owner install |
| Detail mannequin front/back tap | Detail no longer disables tap-to-flip; shared behavior retained | Included | Owner reports missing; unresolved |
| Six approved new guides | All six exact approved versions; purchased priority | All six hashes verified | Unverified after owner install |

The separate in-workout TrainingPlacePicker remains a distinct route. The owner has been asked which location screen was inspected; no unrequested route redesign was inferred. Current physical installation must be verified after USB reconnection before marking any row reflected on the device.

## Distribution state

App Store Connect still redirects to `authResult=FAILED` and the sign-in widget stays blank/loading. Reload and normal Apps navigation did not recover the session. No password, credential, account privilege or contract was changed. Live build numbers, processing status and tester groups remain unverified. No new iOS archive, upload, tester assignment or beta review was submitted. TestFlight is held while the owner-reported physical mismatch is unresolved and Apple sign-in needs recovery. Purchased-background edits remain on hold and no licensed content was changed.

Android APK SHA-256: `10e492a50c58e0db6bbd68b647565b155a7704d69e9d06f9570c2e3864a45833`
