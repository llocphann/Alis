# Round-at-zero contact qualification

Source 4848d5ae462846db623a49e502b9515fe468a557 has focused exact-clone evidence for per-edge 0px/checkbox gating: physical-contact policy 302472 checks, Region cohorts 448448 checks, 19 exact disabled/nonzero RGBA pairs with 8 moving contacts, and editor persistence. These checks do not resolve the subsequent owner report about global Curvature, shadow or surplus screen-corner geometry.

The immutable full validator of that source finished with FAIL (exit 1). See canonical-4848d5ae4/receipt.json and unmodified raw logs for the full counts and failures. Its result belongs only to that SHA; focused PASS is not canonical PASS or owner acceptance.

The follow-up is saved as an UNQUALIFIED binary patch against 4848d5ae462846db623a49e502b9515fe468a557. Runtime was restored to the committed source before checkpoint; the patch is not promoted. It stops 0px paint insets expanding to full-width module-height strips while retaining Wayland reservations/local backing, uses global Surface Curvature for physical contact, removes detached fixed corner fields, and computes finite unified SDF distances for shadows.

Pure policy passed 315562 contact checks and 28009 zero-corner checks; the original failed assertion log is retained. Native/GPU tests of the follow-up were NOT_STARTED because the older immutable canonical was running, then the 5-hour remaining limit reached 2 percent. Next proof: apply the patch on a fresh synchronized base, rebuild QSB, run Region/hover, four-edge GPU and editor/save/restart tests serially, inspect actual captures, then commit only if qualified. Multi-output and owner desktop appearance remain open.
