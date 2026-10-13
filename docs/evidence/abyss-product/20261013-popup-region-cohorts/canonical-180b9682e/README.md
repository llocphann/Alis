# Exact-source canonical receipt

The frozen driver validated source `180b9682e803197ce6c1ca1ee81ed6add842f5f0` in a clean clone. It completed with exit 1: **FAIL**, 386 PASS, 21 FAIL, 1 SKIP (407 completed checks). The source tree cleanliness check passed. This is not validation of the later physical-contact curvature prototype.

`canonical.log` retains every result and failure diagnostic; `outer-driver.log` retains the launching process output. `receipt.json` records source identity and SHA-256 of the immutable driver and logs. The earlier scoped hover/cohort passes do not supersede these failures. Several failures involve source assertions or native fixture loading in other components; their root causes and product acceptance remain separate, rather than being silently reclassified as environment failures.
