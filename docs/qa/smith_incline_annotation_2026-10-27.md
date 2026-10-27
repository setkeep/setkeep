# Smith incline annotation removal — 2026-10-27

The user accepted the existing grip appearance and requested removal of the upper-left trial annotation. The guide remains available. This change does not improve or certify grip anatomy, contact quality, or the previously rejected grip experiments.

Only the existing SETKEEP-authored v11 MP4 and its thumbnail are replaced. The exercise ID, app mapping, video timing, model, framing, background, and original animation remain unchanged. No purchased media, catalog review flags, or unrelated code is changed. Original labelled media and candidate source files are preserved outside the app assets.

## Evidence

- Both encoder scripts use the same source render sequence, frames 1–102 repeated twice. All 102 render hashes match the recorded source provenance.
- Old and new videos decode to 204 frames, 512 × 512, 30 fps, 6.8 seconds, with matching presentation timestamps.
- Outside the top 64 rows containing the annotation, mean RGB difference is 0.219711 / 255 and the largest per-frame mean is 0.317691 / 255. This is a separate H.264 encode; pixel identity is not claimed.
- Accurate Japanese/English OCR inspected all 204 new frames and detected no text. Sixteen evenly distributed decoded frames and the thumbnail were visually reviewed.
- The thumbnail is extracted at time zero with AVAssetImageGenerator. Outside the annotation region, mean RGB difference from the old thumbnail is 0.000744 / 255.
- Other 238 media files are byte-identical, including all 216 purchased entries.
- Existing tests: `flutter test --no-pub test/exercise_media_test.dart test/approved_six_media_test.dart` — 21 passed. These cover asset mapping/manifest and shared video presentation/lifecycle; they are not new real-device QA.

## Asset identity

- MP4 SHA-256: `a6a7eb9ff812476cf7da0b82db19e9625bf07e333f33488c52c44b6efe1a6e72`
- Thumbnail SHA-256: `81357e4ce7ddb2db3818b6866569f00c7164051452436208e954044bd9441f21`

Local build/bundle verification is recorded separately under the task's `smith-label-removal-20261027` evidence directory. Git storage, build success, device installation, and TestFlight distribution are distinct stages. This note does not claim a new device installation, TestFlight upload, or anatomical quality approval.
