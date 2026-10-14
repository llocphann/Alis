The owned Abyss perimeter skips only a provably transparent central region. Existing geometry, ordered smooth union, Waves, physical contacts, materials, opacity, blur, refraction, shadow, derivatives near visible pixels and immersion remain unchanged. No quality reduction, lower cadence, new offscreen image buffer or user setting is introduced. Arbitrary public field callers opt out by default; unknown active wave encodings, unsupported coordinates and render scales below 0.5 retain the original calculation. Immersion never culls the workspace mask.

The vertex stage computes the clearance from the existing packed uniforms. Each new primitive is at least L away; the accumulated distance stays at least L-k because smooth union is monotone and fuse(L-k,L)=L-k. The guard reserves the complete encoded wave range, water displacement, shadow support, numerical error and adjacent derivative quads. This avoids a second JS geometry traversal or reactive cache.

Runtime source: `bab43ab375dd312cb804629ca51e29964801687f`. Reference: frozen `8c4ebd2700e41fddf04bbbe28af0c2b1e768a39c`. `7e6392f6e` only corrects the proof comment; rebuilding its vertex package is byte-identical. The actual product, not just a prototype, passed 456 strict whole-RGBA pairs at dark/light 1x/1.5x, including full/immersion passes and 24 mutations per matrix on the same living candidate QObject. Readiness, nonempty output, package freshness and pixel equality are asserted. Another 114 strict pairs passed at 0.5x (570 product pairs in total), exercising the minimum admitted render scale. A separate ordered-fold oracle passed 90 pairs; native shader cold/cache/error/software lifecycle and actual wave texture/rest/hidden/reduced-motion checks passed. The earlier smoke FAIL used a nonexistent fixture config key and remains in the raw evidence.

The actual source benchmark uses 16 alternating before/after pairs, 2560x1440 offscreen native OpenGL, animated records and positive rendered alpha. Per-process DRM clients are deduplicated; GPU time is divided by its own presented frames. These are isolated-field measurements, not whole-desktop CPU/GPU/RAM or FPS savings.

| Records / wave profile | GPU ms/frame before | After | Reduction |
|---|---:|---:|---:|
| 4 / inactive | 2.278 | 1.421 | 37.6% |
| 16 / inactive | 3.292 | 1.703 | 48.3% |
| 40 / inactive | 5.855 | 2.440 | 58.3% |
| 16 / active encoded waves | 4.036 | 3.009 | 25.4% |

CPU is not claimed as a gain: actual-source medians vary from -0.003 to +0.023 ms/frame, and the earlier prototype has different small changes. Actual-source PSS medians increased by 2.7-5.3 MiB. Preserve these measurements rather than claiming all resources fell. The earlier QML bounds candidate is HELD for a clear CPU regression; owner-snapshot/fround variants were not promoted. Their raw results and failed initial launch/context/process-detection attempts are retained.

`manifest.json`, compressed raw drivers/logs/receipts and `measurements.json` preserve the tested scope and provenance. The full PNG hash catalog is compressed losslessly; representative original captures are published and all original readbacks remain in the local evidence directory recorded by the manifest. Incidental Weather lines, where present, are omitted from published text and original byte hashes are recorded.

Prior full canonical 8c4ebd270 finished with a FAIL log summary (388 PASS, 55 FAIL, 1 numbered SKIP). Its OS exit was not captured independently. No current-source full canonical, installed-service migration, owner visual/input or multi-output acceptance is implied by these focused results. Companion G0 was not replayed.
