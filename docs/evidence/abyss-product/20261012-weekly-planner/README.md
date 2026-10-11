# Weekly Planner focused qualification — 2026-10-12

`DASH-F01` adds the third stable-ID Dashboard page, using Events, read-only
CalendarSync imports and the existing Todo/Quick Notes surfaces. No new backend,
recurrence writes, reminders, vault access or owner preferences are introduced.
The shared Agenda form receives a clicked quarter-hour rather than a default
noon appointment. Cold unloading retains the selected week for the shell session.

Four isolated Node time zones PASS civil week boundaries, overlapping lanes,
multi-day/exclusive all-day slices, daily/monthly/yearly and long recurring
events, source immutability and 23/25-hour days. Rendering is capped at 512 slices
per day/type; extraordinarily long recurrence projections have a visible
"More events" limit instead of unbounded expansion.

Actual private Niri/QV4 grid PASS **30 checks / 9 captures, exit 0**, including
local/imported activation, real slot clicks, keyboard weeks, small allocated
480×410 content, shared Todo/Notes and spring/fall clock changes. PNGs are QSG
captures of this private surface, not owner desktop or multi-output evidence.
The shallow side panel stays bounded and preserves a usable week viewport.

Retained failures: the first DST fixture used unsupported QV4 `flatMap`; the
allocated resize fixture initially checked stale, unrendered Layout geometry.
The final fixture explicitly captures the resized allocation before checking
it; geometry requirements remain intact. Earlier images also exposed the
oversized side pane, corrected with explicit Layout constraints.

The broader Dashboard/Music test separately failed its existing Queue animation
predicate. Bounded diagnostics retain actual geometry: the animation height
remained at its starting value. A private frame-request probe is being used
because an unfocused/occluded nested Wayland parent can withhold frame callbacks;
it does not focus the owner's desktop or relax animation oracles/deadlines.
The framed default-loop probe passed once, then stalled again; it does not prove
a fix of the owner's render loop. The final actual host PASS uses private
`QSG_RENDER_LOOP=basic`, with the original geometry/deadline oracles intact.
The fixture now requests its private frames and specifies that loop explicitly.
No production renderer was changed. Typed Music Settings now toggles both
scrollbar values without its original missing-property warning; the first
Settings probe retained a reference to an unloaded Music item and is also kept.
Final host result and raw log are recorded in the receipt before source commit.

`receipt.json` pins the actual focused source bytes. Full canonical validation
on the final committed SHA, owner visual acceptance, physical touchpad/input,
fractional/multi-output cases and installed persistence remain **OPEN**. The
earlier failed canonical receipts remain unchanged.
