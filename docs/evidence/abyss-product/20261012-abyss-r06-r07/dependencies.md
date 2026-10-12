# ABYSS-R06 dependency inventory — before implementation

Audited at c1371ba08. Default enablement is not mandatory classification.

| IDs | Decision | Actual dependency/mount |
| --- | --- | --- |
| abyssPerimeter | **Mandatory on Abyss only** | Critical host owns the single field, shaped input, body hosts and fullscreen feedback. Turning it off removes every connected surface. |
| abyssBackground | Optional | Separate Background/Backdrop LazyLoaders. External wallpaper renderers remain valid. |
| abyssBar | Optional | Foreground modules/reveal and workspace reservation, within Perimeter. |
| abyssDock | Optional | Dock body/reservation under its module and dock.enable gates. |
| abyssPopup | Optional | Source-owned module content presented in the field; no structural field ownership. |
| abyssSidebarLeft, abyssSidebarRight | Optional | Independently gated body/reveal hosts. |
| abyssNotificationPopup, abyssNotificationCenter | Optional | Notification display/history consumers; field exists without either. |
| abyssOnScreenDisplay | Optional | OSD feedback including fullscreen-only bodies. Host mandatory does not force its consumer on. |
| abyssClipboard, abyssOverview | Optional | Independently gated field content. |
| abyssLock | Optional | Separate shared Lock LazyLoader; security workflow remains user-controlled. |
| abyssPolkit | Optional | Separate shared Polkit LazyLoader; never classify privileged helper as structural. |
| abyssSessionScreen | Optional | Utility body gated by its selected identifier. |
| iiDashboard, iiControlPanel | Optional | Connected content bodies; do not own field. |
| iiCheatsheet, iiOnScreenKeyboard, iiShellUpdate, iiRecordingOsd | Optional | Individually gated field consumers. |
| iiOverlay, iiRegionSelector, iiTilingOverlay | Optional | DemandPanel loaders require ready/deferred/open/identifier. |
| iiWallpaperSelector, iiWallpaperLauncher, iiCoverflowSelector | Optional/compatibility | Selection consumers/old routing IDs, independent of the required field. |
| Companion and Integration optional packages | Optional | Package/client/consent gates unchanged; not in required set. |
| All Waffle IDs | Unchanged | Separate supported family; no forced mandatory set by this change. |

Implementation will enforce only abyssPerimeter, in policy/config and actual
critical loader. All optional off preferences, unknown package IDs, output
profiles and privacy/privileged gates must survive reconciliation and reset.
