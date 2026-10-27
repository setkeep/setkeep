# General SETKEEP advertising consent integration — 2026-10-27

The approved startup candidate is integrated on the distribution branch after `e6cefe1`. Existing banner lifecycle cancellation, interstitial load generations, foreground reload, the 55-minute expiry, saved-workout ordering and once-per-local-day display policy are preserved. This is a test-ad integration, not activation of production ads.

## Behavior and scope

- Each cold process requests a UMP update after onboarding, the 16+ confirmation and existing legal acceptance, before the login gate. Concurrent callers share the update/form. A completed session can be remounted without another update or awaiting a Future from an earlier async zone.
- Update/form failure blocks ad requests for that process even if the SDK reports valid prior permission. Unknown/required status also blocks ads. Successful completed choices, including refusal, still require UMP's `canRequestAds`; refusal is not equated with permission for all purposes. Requests retain `nonPersonalizedAds: true`.
- Noninteractive consent operations have a 10-second bound. Interactive forms remain serialized until the native form closes. Failure leaves workout records, login and settings accessible.
- A Japanese/English privacy-settings entry appears only when UMP requires it. Privacy changes invalidate visible/preloaded ads and pending loads. Errors block ads; a successful privacy retry can recover a privacy-options error, but not a failed startup update/form in that process.
- Both after-load and before-display checks reject stale consent revisions. Preloaded interstitials expire at 55 minutes, including when display is attempted without a separate preload call. Foreground return reloads using the existing generation guard.
- No history, favorites, templates, gym data, account service behavior, purchased media, TRAINER code or native project settings is changed. All 240 media files, including 216 purchased files and the Smith annotation fix, remain byte-identical to `e6cefe1`.

## Candidate changes deliberately withheld

The candidate proposed terms/privacy versions 1.2 → 1.3, replacing the beta test-ad wording with production non-personalized-ad wording, and adding a privacy choices/settings paragraph. Those legal text/version changes are not applied. Current legal text and both 1.2 versions are unchanged, so existing acceptance is retained.

The candidate's production-test mode, reserved production IDs and native App ID switching helper are also not applied. `ads_config.dart`, Android manifest and iOS Info.plist remain unchanged. Only the existing official Google sample App IDs and test banner/interstitial IDs are enabled; unknown/off/production modes remain blocked. No website, AdMob/UMP console, store declaration or contract was edited.

## Verification

- Final `flutter analyze --no-pub`: no issues.
- Final general-app `flutter test --no-pub --concurrency=2 --reporter expanded`: **732 passed, 0 failed**.
- Focused recheck of consent, privacy UI, account registration/login and the legacy media assertion: **71 passed**.
- `git diff --check`: clean.
- Media, native configuration, legal versions/text and test-only ad configuration preservation checks: passed.

The first full run found 39 startup timeouts caused by reusing a completed Future across widget-test async zones. The explicit completed-session state fixes this without rerunning UMP; a two-zone regression is included. One pre-existing migration test also expected the legacy weighted-back-extension ID to have no guide, despite the previously approved merge. Only that test expectation is corrected to require the exact canonical guide; no exercise/catalog/media implementation is changed.

Behavior tests cover age/legal → UMP → login, both startup paths, cached permission on error, timeout/late callbacks, completed refusal, session reuse, privacy change/retry, duplicate actions, Japanese/English entry/error text, saved-data retention, banner disposal, interstitial expiry, generation invalidation, background/resume and display frequency. The full-suite total includes these tests; focused-run counts must not be added to it.

Build and artifact verification are recorded separately in this task's `ads-integration-20261027` directory: exact source commit, explicit test-ad mode, native sample App IDs, all 240 asset hashes, existing Android signing-certificate match, and iOS Runner/Watch/Widget bundle identities. iOS validation uses a provisional local number without signing, Archive, IPA or upload; it does not establish App Store Connect numbering or distribution readiness.

Native UMP forms, consent-region behavior and actual ad display on Galaxy/iPhone have not been retested in this change. The official sample App IDs may return an unconfigured-form error; the required behavior is then to block ads while preserving app access. Device installation, TestFlight distribution, main merge and production-ad activation are separate, unperformed steps.

Reference: [Google's Flutter UMP integration documentation](https://developers.google.com/admob/flutter/privacy). The session-wide failure block is the user's stricter requirement, rather than fallback to prior cached eligibility.
