# Shared Settings task tabs

SET-R02 replaces the segmented task tabs with one themed rail and sculpted
selected/hover/focus states. Theme and opacity come from shared Settings/Abyss
tokens. It creates no liquid face, blur layer or texture for individual tabs.
Ordinary value choices and Waffle controls retain their styling.

Actual private Niri checks: **4,642 QML assertions /168 captures across DPR1
and1.25, exit0** ([results](native-results.json), [source hashes](receipt.json)).
Seven navigation models cover dark/light, font scale1/1.25, width240/430/840,
long labels, dynamic models, disabled targets, wrapping, arrow/Home/End/Enter,
Tab/Escape, focus rings, hover reversal, family switches and zero opacity.
Representative images are retained; all capture counts and raw per-process
logs are recorded. A first candidate fails to compile unsupported Keys
Home/End signal handlers; the repair uses Keys.onPressed. That original
failure is retained, rather than concealed by the subsequent passing checks.

Existing actual Overlay/standalone hierarchy, parent/child/Back, search,
legacy routes and optional-package consent fixture also PASS ([log](hierarchy.log)).
The [consumer inventory](inventory.json) covers21 host callers plus the
optional Companion caller. Four actual Settings pages were captured before
and after: compositor, System, Panels and Themes, using the existing private
backend and actual registry routes. [Before](before/themes.png),
[after](after/themes.png), [capture helper](page-capture.py).

Current committed canonical and owner review of every navigation family,
physical keyboard, multiple outputs and installed optional pages remain OPEN.
These private images do not prove owner acceptance or a resource percentage.
