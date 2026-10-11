# Generic selection padding contract — 2026-10-12

Running frozen canonical `f94de053514954b07635381a318025fc76a3d522` fails its
old literal `horizontalPadding: 11` guard after SET-R02 introduces opt-in task
padding. The generic branch is still 11/6. This fixture-only fix evaluates the
actual padding expressions with task navigation disabled alongside the existing
18 palette/family/shape cases; all original generic expected values remain.

Focused full Material contract PASS, exit 0; raw output is retained. No production
style was changed. This does not upgrade the running old canonical result or the
separate native Settings task-tab/owner acceptance.
