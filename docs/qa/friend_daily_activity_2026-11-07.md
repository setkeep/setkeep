# Friend daily activity display, 2026-11-07

## Scope

Remove the numbered workout-selection list and its summary rows from the friend detail page. Show all workouts for the selected calendar day immediately, without modifying stored records or the existing calendar, header, summary-card design, exercise-card design, sets, or sharing permissions.

The single white summary card aggregates the selected day's sets, total volume and recorded duration. Exercise count uses existing exercise identities, so a repeated exercise is counted once. Positive durations are added in seconds and formatted by the existing formatter; missing/zero durations contribute zero. If none is recorded, the duration column remains an em dash. This is a display-only WorkoutRecord, never saved or published.

Exercise cards remain grouped by their original workout so likes, liker avatars and comments stay attached to their original workout IDs. All groups are visible by scrolling; no numbered selector or next/previous controls remain. Comment-notification IDs are passed only for the original notification's workout. Selecting another calendar day refreshes its social data and immediately displays that day's details.

## Validation

- Final flutter analyze --no-pub: No issues found.
- Focused five-file run: 25 tests passed.
- Existing 104-file normal regression scope: 744 tests passed, exit 0. The pre-existing scope excludes 16 output-only preview/visual files, as recorded in feedback-20261106-validation/regression-scope.json.
- New coverage: same-day duplicate-exercise count, sets/volume/duration aggregation, second-workout like targeting, second-workout comment navigation and return, empty day, month change, one-workout day, and missing/zero durations.
- Existing release-feedback tests preserve exercise order, set values and read-only cards at 390px and 320px with 2x text; revoked access and profile refresh checks pass.
- UI capture run: 6 tests passed. Normal and compact friend detail screenshots inspected. Original calendar wrapping/truncation under enlarged text is unchanged; this change does not restyle it.
- git diff --check passed.

Local logs: /Volumes/PS2000W/SETKEEP/friend-day-regression.log, friend-day-focused.log and friend-day-ui.log. UI captures: /Volumes/PS2000W/SETKEEP/friend-day-20261107-ui/.

No production data changes, repository push, Android installation or TestFlight upload were performed by this task. Android build/installation is the next requested validation step.
