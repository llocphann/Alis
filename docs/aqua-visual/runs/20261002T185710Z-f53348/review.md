# Visual review — actual Bar Clock module, field and Aqua on both side edges

I directly opened the [strictly cropped 512×512 synthetic contact sheet](curated-real-bar-left-right.png) and compared it with the earlier [four-edge field-only experiment](../20261002T183805Z-a5de67/curated-nested-field-four-edge.png).

## What was observed

- The screenshot was produced from **real production** `AbyssBar.qml` / `AbyssBarModule.qml` with one real Clock module, `AbyssLayout.js`, `AquaSurfacePlacement.js`, actual compiled `AbyssField.frag.qsb` and `AbyssCompanion.qml` in an owned Niri-in-Niri session. Left and right were rendered sequentially in separate private Qt windows, never captured from the host compositor.
- Both left and right droplets appear closer to the *actual Bar-derived* inner field rim than in the old field-only fixture with hard-coded 66px insets. Faces stay upright and share the same material/character identity.
- A **very small rectangular rim** is still visible outside the outer side of both Aqua bodies. It is consistent with the distinct QML cradle outline and is NOT established as a single continuous shader/SDF union. The top area that contained the real Clock control was entirely redacted before publication.

## Reproducibility and limits

- Source/job `f53348cbdb270ba2b2ed1a4d4951b0afa33c938a`, `JOB-AQUA-REAL-BAR-P1E0042-20261003-41:0..2` (3/3 exit 0, Unix1790967412–7430). Curator `JOB-AQUA-REAL-BAR-CURATE-P1E0042-20261003-42:0..1` (2/2 exit 0, Unix1790967665–7668); safe publication `JOB-AQUA-REAL-BAR-PUBLISH-P1E0042-20261003-43:0` exit0 Unix1790967720. [Minimal provenance](curated-provenance.json) contains source SHA/digest/redaction policy.
- The private configuration has deliberately only one synthetic-positioned **real** Clock module per side and local module expansion, so these images are closer to the production layout but not an untouched full production `AbyssPerimeter` user setup or native pointer/popup. Desktop screenshots, verbose logs and unredacted images were not published.
- The four authentic original maintainer reference drawings and manifest are still unavailable. No claim of reference similarity or Visual PASS.

**Next evidence-driven candidate:** test `border.width: 0` on only the small QML cradle to remove its bright rectangular outline. Retain this image as the baseline, then render the same two-side real-Bar fixture at the new source SHA, strictly sanitize, open and compare. If the neck is still perceptibly detached, inspect field SDF geometry instead of iterating cosmetic offsets blindly.
