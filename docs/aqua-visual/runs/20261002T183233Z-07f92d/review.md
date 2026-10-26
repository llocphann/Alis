# Real nested shader visual review — base-neck anchor experiment

Actual current-source synthetic Niri-in-Niri images, **opened and compared directly**:

- [Baseline: wide bright base strips](../20261002T182524Z-42e677/curated-nested-field-four-edge.png), exact source `42e67777f7e67c9dc58895d006efef2a2c272e5f`; capture `JOB-AQUA-NESTED-FIELD-P1E0042-20261003-30:2` and successful safe publication `JOB-AQUA-NESTED-PUBLISH-P1E0042-20261003-32:0`.
- [Revision 1: flipped side anchors, bottom attached at top](curated-nested-field-four-edge.png), exact source `07f92d1182265fd32eb82e065a92ef500b0f7a59`; five focused regression/capture actions `JOB-AQUA-CRADLE-CAPTURE-P1E0042-20261003-33:0..4` all exit 0 and safe publication `JOB-AQUA-CRADLE-PUBLISH-P1E0042-20261003-35:0` exit 0.

**Actual visual findings:** both images contain the same real `AbyssField.frag.qsb` shader and actual `AbyssCompanion` QML in four isolated 224×224 cells. The first image displays elongated light-blue bar shapes distinct from the field rim, most visibly on left/right. Flipping both side anchors in revision 1 moved the bars to the opposite side of the bodies **without yielding shader continuity**; the bottom bar moved above the inverted body and remains prominent, while top was unchanged. This is a failed visual hypothesis despite clean static/runtime test receipts.

**Next candidate (implemented separately after this review):** return left/right neck anchors to the side positions adjacent to the observed field rim, retain bottom top-anchor, reduce each bar from length 58 to 28 and use `AbyssStyle.surface` instead of accent fill with much dimmer specular border. Inspect a NEW real-shader image before saying this helps. Keep original successful captures, this negative A/B image, and the subsequent revision image as regression evidence; do not delete them.

**Explicit limitations:** fixed synthetic insets, no live modules/popup/native pointer. The authentic four maintainer blueprint reference images and their manifest are still unverified. Neither image establishes a visual resemblance score, live production field union, or maintainer visual acceptance.
