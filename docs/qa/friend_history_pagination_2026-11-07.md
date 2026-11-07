# Complete friend history and daily totals, 2026-11-07

## Scope and reproduction

Base: `46f9208bde99d3310e9a7039d8e676e46c03d643`. Work was isolated on `fix/friend-history-pagination-20261107`; the existing release checkout and build 22 were not changed.

Two regressions were reproduced in Flutter widget tests against the original UI before changing it:

- With 999 newer records and two sessions on the selected day, the bounded feed showed 3 sets instead of the correct 5 sets, 800 kg and 300 seconds.
- With 1000 newer records, the selected old session opened through its exact-ID fallback but disappeared after tapping its calendar day again.

The failing test output is retained separately from passing final results.

## Implementation

`FriendsRepository.history(owner:)` now reads the complete visible history using 1000-row requests ordered by `performed_at DESC, id DESC`. A quoted composite keyset cursor avoids offset skips when earlier rows are deleted. Short server-capped pages continue until an empty page. Owner, UUID, timestamp, strict ordering and duplicate IDs are checked. A failed or malformed page never returns a partial list.

The authenticated viewer is checked across asynchronous reads. Before returning nonempty history, a fresh owner-scoped RLS query rechecks current visibility; revoked sharing discards accumulated records. `FriendActivityPage` uses this complete-history operation and no longer combines a bounded feed with a single selected-record fallback.

The existing bounded feed remains unchanged for friend cards and photo access checks. Original workout IDs, individual likes/comments, stored data, `sharedWorkoutDate`, sharing rules, database schema, media, dependencies and release configuration are unchanged. No production database operation was performed.

Multiple HTTP reads are not one atomic database snapshot. Concurrent individual edits or deletions may require the next refresh; invalid ordering or duplicate responses fail closed rather than producing a misleading total.

## Validation

- New repository tests: 43 cases using the actual SupabaseClient against a loopback HTTP server. Includes 0/999/1000/1001/2001 rows, tied timestamps, microseconds and offsets, smaller server row caps, deletions, failed reads/retry, revoked sharing, account changes, malformed pages, and legacy feed/schema compatibility.
- New widget tests: 12 cases across iOS and Android themes. Includes complete totals, repeated day taps, individual social IDs, month navigation, failure/retry, sharing/account changes and year-end civil dates.
- Focused run: 67 tests passed.
- Standard broad regression: 107 files, 803 tests passed. Retains the established exclusion of 16 output-only preview files; this is not a claim that every preview was executed.
- Additional end-to-end run: 5 tests passed, connecting the real repository and SupabaseClient to the actual friend UI through a loopback-only server. Covers complete totals, same-day retap, failed pages, revocation during paging/final visibility check, and bounded photo checks. Test transport rejects non-loopback destinations.
- Final `flutter analyze --no-pub`: no issues found. `git diff --check`: passed.
- Android ARM64 debug APK: built successfully. All 257 declared assets, including 108 licensed videos and 108 thumbnails, match the source SHA-256 fingerprints.
- iOS device debug app with code signing disabled: built successfully, including the Watch companion target. All 257 declared assets match the same fingerprints. The simulator attempt required a Watch-paired device selection, so this verification used an unsigned device-target build instead.
- The runtime source, dependency files and native project settings remained unchanged across the native builds.

The additional end-to-end harness initially needed corrections to its asynchronous wait, recovery-month selection and synthetic PNG fixture. These failures were not counted as successful runs; final results are in `end-to-end-tests-r3.log`.

## Boundaries and evidence

The native outputs are local validation builds using the repository's unchanged version 1.0.0+7, without production connection or release-signing configuration. They were not installed or distributed. No GitHub push, TestFlight operation, Galaxy operation, or production Supabase test was performed. Actual-device behavior and release distribution remain separate steps.

Local evidence is under `build/history-pagination-qa/` in the isolated checkout: original failing widget tests, focused and broad regression logs, final analysis, end-to-end logs, native build logs, declared asset fingerprints and artifact verification JSON.
