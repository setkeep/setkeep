# Back extension identity consolidation — 2026-10-26

Weighted back extension is hidden from new exercise choices and canonically resolves to back_extension. The dedicated back_extension_machine remains separate. Japanese/English old weighted names remain searchable through tags; legacy name-only resolution remains unambiguous.

The old catalog ID, stored record IDs/names, weight/reps and asset remain intact. Existing identity compatibility handles favorites, history/PR aggregation and saved menu display. No user-data migration or deletion runs. Historical edits retain each stored ID. Records without IDs and custom IDs remain unchanged.

Validation: 57 unique related cases covered on the release baseline (56 initially passed; one new test's provider expectation was corrected, then all six new cases passed); 53 related cases passed together on the main baseline. The different source baselines retain different media tests; these counts and the six-case rerun must not be added as distinct tests. Static analysis reports no issues on both. Tests cover old/current/machine IDs, zero/additional loads, backup and template round trips, favorites and picker recreation, duplicate selection prevention and editing preservation. The 240 retained video/thumbnail hashes match the prior release manifest. No purchased media or Watch/Widget configuration changes.

Physical Galaxy is not currently visible to ADB; installed source and actual device behavior remain unverified. No installation or device UI operation performed. App Store Connect remains at the existing Chrome failed-login page, without navigation/input/reload. TestFlight current build number is unverified; upload remains blocked.

APK 8 and the earlier provisional IPA 18 came from 877a6e1 before this change. They do not contain this consolidation. Any replacement artifact must have separate source/hash provenance; iOS build 18 remains local validation only until live numbering is confirmed. Main and the Watch-preserving release branch remain intentionally separate baselines.
