# Dashboard horizontal page navigation

Task DASH-R02, Alis dev. Candidate sources are pinned in [receipt](receipt.json); the committed-source canonical result must be recorded separately.

The old exact runtime `b543bb7602eb74901c3c137c89c70c301e12fde4` reproduces vertical page switching (page 0 → 1) with actual Qt mouseWheel input: expected FAIL, exit 1. [Probe patch](baseline-probe.diff), [raw baseline](baseline.log).

The candidate removes vertical page handlers and uses one horizontal gesture policy across body/header. It keeps inner Music scrolling first, one transition per burst, phase/momentum ownership, fast reversal, boundaries and stable IDs/order; dialogs/editing suspend navigation. The new order schema retains disabled/unknown entries rather than rewriting user preferences. Numeric Music=1 remains the public compatibility intent.

Focused results: Node policy 990 checks PASS; actual Dashboard/Music controls PASS; six actual overflow lists (wheel, themed thumb drag, keyboard/end) PASS; LocalMusic presentation-demand and Python/Rust ordered mutation PASS; each script exit 0. [Native](native.log), [scroll](scroll-native.log), [demand](demand.log), [mutation](mutation.log). Pixel/phase owner calls use actual QV4 objects; QtTest mouseWheel dispatch supplies angle deltas. These do not prove physical touchpad/wl_pointer delivery. Private XDG/Niri and fake/private audio backends preserve owner focus, queue and preferences.

Only Dashboard and Music are implemented product pages. Three-page policy permutations do not implement Weekly Planner (DASH-F01) or drag-reorder UI/transactions (DASH-F02). Those, owner gestures/scaling/multi-output and committed canonical qualification remain OPEN. No resource percentage is claimed.
