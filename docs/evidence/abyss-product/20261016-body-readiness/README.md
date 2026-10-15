# Content-ready BodyHost reveal

This private Niri/Quickshell functional comparison exercises actual Dashboard and
Overview content through `AbyssBodyHost`, its availability animation and the shared
GPU field. It uses no image readback and does not measure frame-time improvement or
qualify the owner's installed desktop.

Both runs use baseline `eca4a41de023083eee86647a0d2fd1abecdfc22e`. The candidate
overlays only `modules/abyss/AbyssBodyHost.qml`, changing the availability target
from `presented` to `presented && ready`. Receipts identify the exact source and
fixture hashes; this is an explicitly recorded overlay, not a committed-SHA PASS.

The unchanged fixture fails on baseline with
`EMPTY_PLATE_BEFORE_CONTENT_READY`: semantic open starts the empty shared-field
plate while the deferred content loader is still unavailable. The harness exits
1 although the native process exits 0. Candidate harness and native exits are 0.

Candidate covers 16 Dashboard/Overview × four edges × normal/reduced-motion cases:
delayed readiness, cancelled deferred open without resurrection, cold and expired
reopen, warm reuse, close/reversal, stable full-size content and immediate input
release. It records 16,650 assertions and 447 intermediate window swaps during
normal openings; reduced-motion openings record no intermediate progress. These
counts establish exercised behavior, not a performance gain.

`*-result.json` contains the semantic result without the high-volume trace. The
compressed native logs retain that original trace, warnings and semantic result.
Only isolated fixture state is used; no owner configuration is included.

Reproduce the regression on a selected checkout with:

```sh
ALIS_BODY_REVEAL_EVIDENCE_DIR=/tmp/alis-body-ready-evidence \
  python3 scripts/test-abyss-body-reveal-readiness-runtime.py
```

Exact committed-SHA maintainer validation and owner smoothness acceptance are
separate gates recorded in the owning GitHub Issue.
