# Unified profile editor QA — 2026-10-05

The pencil and avatar now open the same profile editor. The editor shows a photo preview, photo change/removal, and the existing optional 40-character display name. Photo edits remain drafts until Save; Cancel/Back discard unsaved drafts. Gallery cancellation preserves the current draft.

Name and photo changes use one profile-row update. Storage path, owner checks, visibility, and photo preprocessing remain unchanged. If a profile update response fails, the repository checks the actual row before deleting a candidate photo; a confirmed committed update is accepted. Local preference failure after cloud success retains a receipt so retry avoids resending the photo. Busy states block duplicate Save, Cancel and Back. Loading a cloud profile checks that the same account is still active.

Validation: 108 tests passed across profile dialog, synthetic UI preview, main widget regressions, friends UX, and schema compatibility; 3 local HTTP repository tests passed for atomic update, lost response after commit, and rejected update preserving previous photo. Full flutter analyze passed. No backend, real user photo, native build, upload, install, or push performed.

Visual inspection: synthetic current UI before and after at /tmp/setkeep_profile_edit_qa/before.png and integrated.png. The after preview shows photo and name together, with readable Japanese text and accessible actions at 390×844; a 320×640 keyboard-inset test passed. Original Library reference materialization failed with download failed; parent had inspected original pixels and authorized local synthetic UI verification. No fallback transfer used.

Known practical limit: a failed server response plus failed state confirmation can leave an unused private candidate object; retain it rather than risk deleting a committed avatar. Existing data and publication scope are untouched.
