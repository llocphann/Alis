# Calendar fixture scheduling diagnosis

The consumed f94de0535 canonical remains STOPPED with its recorded FAIL.
No replay of that frozen driver or alteration of production sizing was used.
The bounded default render-loop diagnostic inspected the same narrow card
before and after a frame: Remove x248/32 before polish, x196/32 after rendering
at card width240. The old x248 belonged to the preceding292px layout.

`calendar-layout-before` and `calendar-bounds-diagnostic` retain failures.
`calendar-render-default-raw.log` retains the complete original oracle plus
the before/after rendering trace. The separate basic-loop diagnostic is
supporting evidence only; the default-loop trace establishes this cause.

The fixture now requests one bounded actual frame after width/font/theme
changes and before measuring/clicking. Original assertions, pane widths,
font scales, light/dark modes and whole Remove click targets are unchanged.
`rendered-calendar/focused.log` records PASS149 checks/12 captures, including
actual private Event Add/Edit/Remove readbacks and denied-write recovery.
Calendar production sizing is unchanged. The invisible historical-event link
row in the uncommitted Agenda source was present during this focused run.
This is focused native evidence, not a full exact-SHA or owner acceptance.
