# Office application theming

The optional Office target uses the existing Alis app palette and color refresh
pipeline. In Settings → Color generation, ONLYOFFICE and LibreOffice have
independent switches, both off by default. Close the selected application,
enable its switch or refresh colors, then open it yourself. Alis never starts,
closes or restarts either suite. An open application or LibreOffice profile lock
defers the change; close it and refresh again. There is no background retry.

## Supported interfaces

| Application | Inspected installation | Adapter surface | Scope |
| --- | --- | --- | --- |
| ONLYOFFICE Desktop Editors | `onlyoffice-bin 9.4.0-1` | User `UITheme` preference and `uithemes/alis-auto.json` | Light/dark base and supported surface, text, border and accent tokens; unspecified tokens retain the suite defaults. |
| LibreOffice | `libreoffice-fresh 26.8.1-2` | User XCU registry, `AlisAuto` color scheme and Appearance properties | 28 UI color roles, current scheme, light/dark mode and custom theme enable flag. Existing explicit document/font/visibility overrides are inherited into the new scheme. |

Native Linux package detection uses package metadata, never an application's
`--version` command. The initial capability range is ONLYOFFICE 9.4.x and
LibreOffice 26.8.x, with a required installed LibreOffice schema check. Missing
packages and unrecognized versions/layouts are skipped with a diagnostic.
AppImage, Flatpak, custom-profile and other packaging are not inferred from an
application name or silently written to the native profile.

ONLYOFFICE's [theme format](https://api.onlyoffice.com/docs/desktop-editors/usage-api/customizing-themes/)
defines a JSON theme. Its pinned [desktop source](https://github.com/ONLYOFFICE/desktop-apps/tree/3ad4e294ae5e25902ccc56088a760ad21a9d123a/win-linux/src)
(`cthemes.cpp`, `defines.h`, `prop/utils.cpp`) also defines the Linux user theme
directory and the QSettings selector. This is tag `v9.4.0.131`; package version
metadata alone does not establish the installed binary's complete build tag.
The adapter uses `$XDG_DATA_HOME/onlyoffice/desktopeditors/uithemes` and
`$XDG_CONFIG_HOME/onlyoffice/DesktopEditors.conf`. It does not write `/opt`,
inject browser JavaScript or use an undocumented command-line theme flag.

### Editor workspace canvas and document safety

ONLYOFFICE has **two distinct color systems**: Home/Settings CSS and the
document editor's canvas. An earlier adapter themed `background-normal` and
`background-action-panel` but omitted the documented `canvas-background`
role; consequently the area around the document still used the built-in gray
color even when the toolbar and settings followed Alis. The adapter now sets
`canvas-background` and `canvas-ruler-background` to the Owner-requested
`#114161` when the Alis app palette is dark, instead of either suite's gray.
A light palette uses the generated Alis background as the canvas. Page borders,
scroll thumbs and spreadsheet header colors are contrast-checked against that
canvas. This is an explicit Office dark workspace preference, **not** a
document page color.

The adapter **intentionally does not set** `canvas-content-background` (paper,
slide or spreadsheet cell surface) or document font/content colors. This
preserves the editor's document-theme and printing semantics; light paper may
appear against a dark Alis workspace and that is intentional.

LibreOffice's supported `AppBackground` UI color role serves the analogous
workspace outside the document. Per Owner request, the adapter now sets
`AppBackground` to **exactly `#114161`** rather than deriving it from the
generic Alis palette, while keeping explicit `DocColor`, `FontColor` and
document visibility preferences user-owned. The override remains active even
when other LibreOffice UI colors are generated from a light Alis palette; this
is intentional until the Owner requests a different per-mode color. LibreOffice 26.8 may render some
toolkit/toolbar regions with platform or module-specific colors; do not claim
full pixel-level palette parity. If the user has selected a Writer application
background bitmap, that can obscure the plain application-background color:
the adapter preserves the user's bitmap preference.

To verify on the installed desktop, close both office apps (the adapter
defers changes while they run), refresh Alis colors and reopen. In ONLYOFFICE
inspect the area **outside** a Writer document, the ruler and the unchanged
document page; repeat for spreadsheets and presentations. In LibreOffice
inspect the application background around a Writer document and the
Appearance > Application background color, plus menus and buttons. Repeat
with dark and light Alis palettes and confirm restore on disabling each
integration. These are Owner visual checks, not covered by synthetic tests.

**Important runtime limitation:** both Office suites must be *fully closed*
before color refresh, as this adapter deliberately defers writes while either
suite is running. If the ONLYOFFICE surround is still the default gray,
do not infer that the editor consumed the new JSON merely because the Alis
generated-file test passes. Inspect the selected `UITheme` in
`DesktopEditors.conf`, the `canvas-background` inside the generated
`alis-auto.json`, and the actual editor's selected theme after reopening.
The Desktop Editors shell loads local themes at startup and the embedded
editor has a separate theme consumer. A synthetic profile receipt alone
cannot prove the running editor uses it; no hot-patching of the user's
documents or third-party binaries is attempted.

LibreOffice documents its [Appearance options](https://help.libreoffice.org/latest/en-US/text/shared/optionen/01012000.html)
and [configuration/theme architecture](https://github.com/LibreOffice/core/blob/master/vcl/README.themes.md).
The installed `share/registry/main.xcd` is authoritative for available properties;
the source guide's historical light/dark property example differs from this
installation's single `Color` property. The adapter uses
`$XDG_CONFIG_HOME/libreoffice/4/user/registrymodifications.xcu`, matching
`Office.Common/Appearance` and `Office.UI/ColorScheme`. It preserves other schemes,
document content and unrelated property bytes. Native platform decorations and
toolkit-rendered controls may retain toolkit styling; full pixel parity is not
claimed. Settings changes take effect on a later application launch.

## Preservation and recovery

The adapter rejects malformed/ambiguous configuration, symlink or hardlink
targets and unowned files/schemes that collide with its names. Per-app locks
serialize refreshes. Settings edits use a final comparison before an atomic
replace; all unrelated INI/XML bytes remain in place. Existing user edits to
managed fields block a later refresh rather than silently taking them over.

Disabling a switch restores each owned selector/property only while it still
matches Alis's last applied value. User changes are retained. An unchanged
generated ONLYOFFICE theme is removed; an edited copy remains. LibreOffice
inherits explicit non-UI overrides only on first enable, leaves later edits to
those inherited properties alone, and removes only still-owned properties on
disable. The previous scheme remains intact throughout.

Private write-ahead receipts live in
`$XDG_STATE_HOME/quickshell/user/generated/office`, mode 0700 with 0600 files.
An unfinished receipt can contain before/after preference file bytes; keep it
private. Recovery accepts only the recorded old/new contents. If another edit
conflicts with an interrupted write, the receipt and current preferences remain
untouched for review. Do not delete a receipt to force a retry. No error log
includes preference contents or those recovery payloads.

Diagnostics are appended to the existing `theming_modules.log`. The Office
target runs even with both switches off so it can perform ownership-aware
restore. One suite failing does not prevent the other adapter from running.
No office package is an Alis dependency and no system configuration is changed.

## Validation boundaries

`python3 scripts/test-office-auto-theme.py` uses private synthetic profiles for
palette mapping, preservation, disable, interrupted writes, concurrent edits,
independent adapters and failure handling. It is part of the maintainer validator.
`python3 scripts/test-office-qsettings.py` checks the INI boundary against native
Qt 5 in an isolated HOME; it starts only a settings probe, not an office suite.
Package metadata and schema checks do not establish visible application behavior.
Actual installed-app light/dark/color appearance, controls and Owner acceptance
remain separate gates. Do not report them as passed from a generated file.
