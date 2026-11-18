import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks

// TODO: Replace the icon with QMLized svg (with /usr/lib/qt6/bin/svgtoqml) for proper micro-animation
AppButton {
    id: root

    leftInset: (Config.options?.waffles?.bar?.leftAlignApps ?? false) ? 12 : 0
    // Absolute path to the bundled glyph, not the freedesktop name. As a plain
    // name this resolved against the user's icon theme, and any non-Windows set
    // answers "start-here" with its own launcher mark — WhiteSur returns the
    // Apple logo. The Start button is waffle's identity, not a themed app icon.
    iconName: WIcons.pathForName(down ? "start-here-pressed" : "start-here")

    checked: GlobalStates.searchOpen && LauncherSearch.query === ""
    onClicked: {
        GlobalStates.searchOpen = !GlobalStates.searchOpen;
    }

    BarToolTip {
        id: tooltip
        text: Translation.tr("Start")
        barExtraVisibleCondition: root.shouldShowTooltip
    }

    altAction: () => {
        contextMenu.active = true;
    }

    BarMenu {
        id: contextMenu

        model: [
            {
                iconName: "apps",
                text: Translation.tr("Dashboard"),
                action: () => {
                    WaffleNavigation.toggleDashboard()
                }
            },
            {
                iconName: "apps",
                text: Translation.tr("Installed apps"),
                action: () => {
                    WaffleNavigation.openSettings("applications", "")
                }
            },
            {
                iconName: "desktop",
                text: Translation.tr("System"),
                action: () => {
                    WaffleNavigation.openSettings("system", "")
                }
            },
            { type: "separator" },
            {
                iconName: "terminal",
                text: Translation.tr("Terminal"),
                action: () => {
                    AppLauncher.launch("terminal")
                }
            },
            {
                iconName: "pulse",
                text: Translation.tr("Task Manager"),
                action: () => {
                    AppLauncher.launch("taskManager")
                }
            },
            {
                iconName: "settings",
                text: Translation.tr("Settings"),
                action: () => {
                    WaffleNavigation.openSettings()
                }
            },
            {
                iconName: "folder",
                text: Translation.tr("File Explorer"),
                action: () => {
                    AppLauncher.launch("fileManager")
                }
            },
            {
                iconName: "search",
                text: Translation.tr("Search"),
                action: () => {
                    Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "overview", "toggle"]);
                }
            },
        ]
    }
}
