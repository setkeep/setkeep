# Android rest duration and equipment refresh — 2026-10-27

## Report and changes

Galaxy APK 1.0.0 (9), source 4b9662f, was reported to show a large 11:07:51 next to the set-completion action. The source explicitly replaced the remaining duration with HH:mm:ss(deadline) when exact-alarm permission was unavailable. The compact layout omitted the explanatory label present in the expanded layout. This is a source-confirmed defect consistent with the report; current Galaxy permission state and the original screenshot pixels were not available in this follow-up. Formal Library materialization failed with download failed, including a fresh transfer.

The notification now uses a SystemUI countdown independently of exact-alarm permission, with a wall-clock deadline for notification metadata and an elapsedRealtime base for RemoteViews. Paused notifications use the saved remaining duration; finished notifications retain 00:00. Alarm scheduling, sound, completion claims, timeout cancellation and workout records are unchanged. No promoted-notification/Now Bar eligibility was added. OEM rendering remains physical-device QA.

The equipment report concerns kanekin-fitness-gym:matsudo. A read-only request using the APK's existing public configuration returned 41 machines, including community-training:cable_crossover and community-training:dual_pulley, both present and available, source admin. The complete response parsed successfully through GymStoreDetail and both machines rendered and were searchable in GymStoreEquipmentPage. The older equipment withdrawal commit 8a00508 is an ancestor of the release candidate; its client filter does not exclude this store.

A separate reproducible stale-page defect was found: after a failed initial network request, returning to the still-open equipment page did not fetch fresh data. The page now refreshes on app resume, retains current rows on failure, and prevents older in-flight responses from replacing a newer response. Forced refresh avoids an unnecessary cache read. No server adoption, master registration, database mutation or user-record deletion was performed. The exact cause on the user's Galaxy remains unconfirmed until the new build is tested there.

## Validation and limits

Final release-tree analysis: no issues. Related unit/widget tests: 32/32. Separate current-public-API rendering probe: 1/1. Native cases: 2/2 with exact alarms denied and 2/2 allowed (4 total; teardown is not counted as a test). The API<26 guard added to debug timeout diagnostics uses the same branch on the tested API36 device.

- Regression covers both machine IDs through parsing/cache, offline-to-online resume, and out-of-order response protection.
- Native QA checks compact/expanded/heads-up duration, elapsed base, notification when, countdown flags, pause/resume, extension, expiry and cancellation, in exact-alarm denied and allowed modes.
- Dedicated AOSP Android 16 QA only; Galaxy was not operated or reinstalled.
- A forced screen-off/deep-Doze observation with permission denied completed the same timer 2 ms after its deadline, persisted remainingSeconds=0, removed the ongoing countdown, and posted the completion notification. The VM service disconnected; host observations plus the app log independently confirmed resume reconciliation. This is not a claim that the whole interrupted driver run passed.
- The user's APK9 sound test passed according to their report. No new physical sound result is claimed.
- Xcode and TestFlight remained on hold. No media, purchased assets, credentials or permanent permissions changed.

Local evidence: timer-display-20261027 in the requesting task workspace. Final commit, test totals and APK hash are recorded in its final report after verification.

Reference: [Android Notification.Builder documentation](https://developer.android.com/reference/android/app/Notification.Builder) describes countdown metadata and notification timeout as separate concerns.

