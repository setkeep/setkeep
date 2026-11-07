# SNS logo quality repair (2026-11-07)

## Cause and implementation

The previous share asset was a 320×174 PNG produced by integer-coordinate nearest-neighbor reduction of a 460×270 raster. Centered placement at 82% width and 3× image export magnified the baked-in stair steps. Text was unaffected.

`assets/brand/setkeep_share_vector.svg` is now the independent outline master. The approved SK mark, four dumbbell plates, custom SETKEEP lettering, relative proportions, spacing and white/teal appearance were reconstructed with explicit lines and cubic curves. Straight edges and letter baselines were regularized; raster highlights and isolated specks were removed. This is a reconstruction based on the approved raster, not a recovered original vector or a claim that lost detail was restored. No substitute font or unrelated 1254px logo variant is used.

`swift tool/render_share_logo.swift` renders that SVG to a transparent 1280×696 PNG with antialiasing. Runtime assets remain ordinary PNGs, with no new Flutter dependency. Both share layouts use high-quality filtering. Existing position, 82% width, 0.24 opacity, date alignment and export scale remain unchanged. The SVG is the reusable source for larger outputs.

## Verification

- Inspected both previously approved SNS design images and the actual shared-image widget's new exports.
- Tested photo and no-photo output at the production 3× scale (1020×1814), including alignment, centered placement, opacity and high-quality filter selection.
- Added raster size, transparency and intermediate-alpha checks; verified the master contains vector paths and no embedded bitmap or replacement text font.
- Related tests cover photo dragging/cropping and recorded set values. General widget regression included.
- Final test log and exported examples are under `/Volumes/PS2000W/SETKEEP/logo-quality-20261107/`. The photo test uses a synthetic two-color image, not a user's photo.
- Related and general widget regression: 108 tests passed on the fixed logo files.
- Normal regression: all 743 tests in the previous 104-file scope passed (excluding the same 16 output-only preview/visual files). This validates the logo commit with the pre-existing friend view, not later parallel friend-view changes.
- Raster reproduction is deterministic (SHA-256 `da47dbb1f4909ab093a42bb4d9a4c41e1523bc8e992d584345e5b84d8fd20648` on two renders). The raster has 10,497 intermediate-alpha pixels.
- Static analysis: no issues. Device Photos save/share and an installed TestFlight binary were not exercised in this change's unit/widget validation.

The earlier test run briefly used an expected record-label change from a parallel task that was subsequently put on hold. Those expectations were restored and the final fixed files were retested; the interrupted mixed-scope run is not a passing result.

## Release boundary

This change does not itself upload TestFlight, alter build numbers, or change production data. Release assembly must use the final committed source, verify signatures and packaged asset, and confirm Apple's processing and group availability separately.
