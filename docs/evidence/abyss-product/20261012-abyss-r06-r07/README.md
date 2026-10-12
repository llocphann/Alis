# ABYSS-R06 + R07 — structural host and shared typography

Implementation complete; Owner chưa verified. Inventory was recorded before
implementation in dependencies.md, based on c1371ba08. Only abyssPerimeter is
mandatory; all other foreground, wallpaper, security and package workflows remain
optional. Required policy, Config load/mutation/family switch and actual critical
loader enforce that host. Its switch is excluded from Abyss Modules. Waffle and
unknown optional package IDs retain their preferences.

Abyss Clock/Date ignore legacy per-clock font/px keys and use shared main-family
and large/small Typography tokens on every Edge. Shared typography scales once;
legacy bar.height no longer duplicates its scale. Explicit module size still
transforms the whole module. Legacy consumers keep their original default
behavior/keys. The four font/px controls are not instantiated on Abyss.

| Evidence | Result |
| --- | --- |
| Mandatory policy/optional preference isolation | PASS 117 |
| Existing family cycle/migration/route contract | PASS |
| Native actual required host/frame readiness, live disable/switch and type/UI | PASS 156 checks, 25 frames/PNG |
| Fresh native process/durable JSON restart | PASS 9 checks |
| Config overlapping writes | PASS four scenarios |
| Config raw write/migration/retry | PASS 12 startup/restart processes |
| Content opacity Config compatibility | PASS 5 cases / 10 processes |
| Translation source parity | PASS 5654 entries |

Typography test uses two fonts × three scales × four Edges on the same resident
Clock, verifies time/date formats, shared token sizes/family, preserves legacy
consumer font/px behavior and saved keys, and inspects actual Abyss Settings
objects for the absent override controls. Actual critical loader mounts and
presents native frames despite old saved-off preferences; optional Polkit/Lock/
Background stay off. Mandatory runtime preferences survive another process.

Parser, QObject lookup and QV4 replaceAll fixture failures are retained, with
full-typography the final result. BarConfig's subsequent indentation-only cleanup
has the same parsed behavior. Private capture focus is used only for image
verification; owner installation/settings, physical pointer, multi-output,
fractional DPI and full exact-SHA canonical are independent remaining gates.
No resource improvement percentage is claimed.
