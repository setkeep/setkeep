# Approved six original guides — 2026-10-26

Six completed original videos are added to existing non-purchased exercise IDs. No exercise identity, workout record, purchased mapping, video, or thumbnail is replaced. The purchased catalog retains precedence if a future mapping collides; the regression guard rejects current collisions.

| Exercise ID | Approved version | Duration | Source and bundled SHA-256 |
|---|---|---|---|
| pallof_press | v4 | 7.2 s | `beb301441f498ebf1e1687139a6b55bbd6a8edd79cfde83ffc87a3b0d3d4bb10` |
| bayesian_curl | v3 | 8 s | `9f27d90e87ccfbd5383b616066139e6d4670d470031d48a611039625079942f2` |
| wall_sit | v2 | 16 s | `9c5da156573d5dd3e3fd44485cebee7a40bc7d677b648d44df87b58c16dec560` |
| chest_supported_dumbbell_row | v5 | 7.2 s | `a4e7f60f3f4115a70369c6961d00e99f0642b2de22851c9800e0615b07211536` |
| reverse_lunge | v4 | 16 s | `253f866a966df64d7cf9a6b8b312f17c583b03b1517ea371f72022deeb411e4a` |
| decline_dumbbell_fly | v5 | 8 s | `fa0705873e9e1c9d19287d113edc88011ec112b0fb5bfbf405203e7ab539a0c4` |

All six are 512×512, 60 fps, no audio track. Full AVFoundation decoding succeeded (432/480/960/432/960/480 frames in table order), timestamp checks passed, and sampled OCR found no text. Start/middle/end contact sheets were visually reviewed; the existing October 15 full native Quick Look motion reviews were read and retained. The video bytes were copied unchanged, and thumbnails were extracted from those same files. New production geometry or motion was not authored.

## Validation

- `flutter test --no-pub test/approved_six_media_test.dart test/exercise_media_test.dart test/feedback_20261026_test.dart`: 22 passed.
- `flutter analyze --no-pub`: no issues.
- Dedicated Android API 36 emulator and iPhone 17 / iOS 26.5 simulator: all six traversed category → picker/search → thumbnail → detail → back, initialized their exact asset, played muted through the end, and looped. No controller error or Flutter exception. Native screenshots reviewed individually on each platform.
- Debug QA builds, version 1.0.0 (7), use the integration-test entry point. They are not distribution artifacts. Both built bundles contain the six exact source hashes above.
- Purchased preservation: 109 mappings / 108 unique clips, all 216 staged video/thumbnail files byte-identical to the pre-task baseline. No conflicts/skipped targets.
- The separate primary checkout's HEAD, dirty status, and 37 protected files remain unchanged.

Initial QA attempts failed because a native keyboard restored stale test input and the test used the catalog label 腹筋 instead of UI category 腹. The harness now waits for keyboard attachment, uses `ExerciseTemplate.fromForm`, and resets list position. Subsequent complete runs passed. Only QA code changed for those failures. Android's emulator decoder reports a 60-fps capability warning; playback completes, but this does not establish physical-device frame rate.

## Distribution status and boundaries

The six-file adoption gate is satisfied by the approved source versions and both native QA platforms. The 34 purchased-video background edits remain on hold and are not a dependency for committing these six; they were not attempted or included. They remain an unfinished item for any broader claim that every purchased clip has a unified background.

No Galaxy or iPhone is currently connected. These simulator checks are not physical-device QA. Previous main timer QA still does not establish notification sound/lock-screen behavior on a Galaxy with the proper permissions.

No TestFlight upload, tester-group update or beta-review submission was performed. App Store Connect returned `authResult=FAILED`; its sign-in widget stayed blank/loading after a reload. Current build numbers, processing/review state and tester groups could not be verified. An existing local 1.0.0 (18) candidate contains an embedded Watch app, while this main-derived branch omits the existing friend/Watch feature history. Its deployment status is unknown. Reconcile the actual deployed baseline and preserve existing features before producing/uploading one signed release build; do not upload this QA binary or silently ship a main-based regression. Existing Apple credentials/settings were not changed.

Task evidence is in the local `approved-six-20261026` folder: decoded verification, original playback references, both native logs/screenshots, preservation hashes and bundle checks. Raw native logs and licensed assets are not committed. The integration test can be rerun on the named dedicated QA environments with the existing driver.
