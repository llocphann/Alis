# Connected static Panel content sizing

Sidebar source: `d01f0d491bd3fcd95552229ba869210476829824`. Extended static panel source: `4d8ea01bb40c7c30a0ec28f3c2d276d5c52da45c`.

Both Sidebars, Settings, Controls and Clipboard now use the existing full-size content Loader contract while the host clips its reveal/retract. Previously Sidebar's Loader followed the clipped dimensions: a native Left reveal at progress.01 reduced a345.8px content width to0px. Sidebar adapters pass that width to their actual control layouts, causing repeated reflow during motion. This change preserves the final target size and existing opacity/motion, surface geometry, masks, semantic input release and unload policy. Genuine target resize/reflow still updates the content.

Clean d01 native PASS280 covers both Sidebar flags through production BodyHost on four Edges, opening/closing/reversals, exact original surface/input/target geometry, retained content identity, genuine size change and destruction. Clean4d8 expands that same diagnostic-pane test to five production flags and PASS700. It does not instantiate every Settings/Controls/Clipboard feature UI or establish CPU/GPU/frame-rate savings. The closed content is still released; no permanent warming, config mutation or render-quality reduction is introduced.

Native body lifecycle at d01 also passes anchor retention, readable reflow, animated eviction, draft/input restoration and close unload in a private no-focus Niri. Relevant surface-motion/Pyramid/placement/input/hover contracts pass at4d8. Full canonical and installed/multi-output/Owner acceptance are separate and not run for the new source.

The actual Sidebar Left theme fixture FAILs its non-Abyss material assertion at the worktree and the unchanged cleanfe80 baseline; both raw logs are retained. That isolated theme fixture does not mount the edited Perimeter. The cause is not established, and it is not recorded as PASS or attributed to these sizing flags. The earlier tooltip fractional pixel failure remains independent.
