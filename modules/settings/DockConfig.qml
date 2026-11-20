import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../dashboard/DashboardCustomTabPolicy.js" as TabPolicy

ContentPage {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    property var pinnedDragInfo: null
    property int pinnedDropIndex: -1
    readonly property bool pinnedDragging: pinnedDragInfo !== null
    property bool addApplicationsOpen: false

    function commitPinnedDrop(): void {
        if (!root.pinnedDragInfo || root.pinnedDropIndex < 0) {
            root.pinnedDragInfo = null;
            root.pinnedDropIndex = -1;
            return;
        }
        const values = [...(Config.options?.dock?.pinnedApps ?? [])];
        const fromIndex = root.pinnedDragInfo.index;
        const toIndex = root.pinnedDropIndex;
        if (fromIndex >= 0 && fromIndex < values.length
                && toIndex >= 0 && toIndex < values.length
                && fromIndex !== toIndex) {
            const moved = values.splice(fromIndex, 1)[0];
            values.splice(toIndex, 0, moved);
            Config.setNestedValue("dock.pinnedApps", values);
        }
        root.pinnedDragInfo = null;
        root.pinnedDropIndex = -1;
    }

    function pinnedAppLabel(appId: string): string {
        return AppSearch.lookupDesktopEntry(appId)?.name ?? appId;
    }

    function pinnedAppIcon(appId: string): string {
        const entry = AppSearch.lookupDesktopEntry(appId);
        const icon = entry?.icon || AppSearch.guessIcon(appId);
        const resolved = IconThemeService.smartIconName(icon, appId);
        if (resolved.startsWith("/") || resolved.startsWith("file://"))
            return resolved.startsWith("file://") ? resolved : `file://${resolved}`;
        return Quickshell.iconPath(resolved, "application-x-executable");
    }

    function isPinnedVisible(appId: string): bool {
        const lowerId = String(appId ?? "").toLowerCase();
        const hidden = Config.options?.dock?.hiddenPinnedApps ?? [];
        return !hidden.some(id => String(id ?? "").toLowerCase() === lowerId);
    }

    function togglePinnedVisibility(appId: string): void {
        const lowerId = String(appId ?? "").toLowerCase();
        if (!lowerId) return;
        const hidden = [...(Config.options?.dock?.hiddenPinnedApps ?? [])];
        const index = hidden.findIndex(id => String(id ?? "").toLowerCase() === lowerId);
        if (index >= 0) hidden.splice(index, 1);
        else hidden.push(lowerId);
        Config.setNestedValue("dock.hiddenPinnedApps", hidden);
    }

    function removePinnedApp(appId: string): void {
        const lowerId = String(appId ?? "").toLowerCase();
        if (!lowerId) return;
        const pinned = [...(Config.options?.dock?.pinnedApps ?? [])]
            .filter(id => String(id ?? "").toLowerCase() !== lowerId);
        const hidden = [...(Config.options?.dock?.hiddenPinnedApps ?? [])]
            .filter(id => String(id ?? "").toLowerCase() !== lowerId);
        Config.setNestedValues({
            "dock.pinnedApps": pinned,
            "dock.hiddenPinnedApps": hidden
        });
    }

    function addPinnedApp(appId: string): void {
        const id = String(appId ?? "").trim();
        if (!id) return;
        const lowerId = id.toLowerCase();
        const pinned = [...(Config.options?.dock?.pinnedApps ?? [])];
        if (!pinned.some(existing => String(existing ?? "").toLowerCase() === lowerId))
            pinned.push(id);
        const hidden = [...(Config.options?.dock?.hiddenPinnedApps ?? [])]
            .filter(existing => String(existing ?? "").toLowerCase() !== lowerId);
        Config.setNestedValues({
            "dock.pinnedApps": pinned,
            "dock.hiddenPinnedApps": hidden
        });
    }

    function filteredAddApps(): var {
        const query = pinnedAppSearchField.text.toLowerCase().trim();
        const pinned = new Set((Config.options?.dock?.pinnedApps ?? [])
            .map(id => String(id ?? "").toLowerCase()));
        const result = [];
        for (const app of (AppSearch.list ?? [])) {
            const id = String(app?.id ?? "").trim();
            if (!id || pinned.has(id.toLowerCase())) continue;
            const haystack = [
                app?.name ?? "",
                app?.genericName ?? "",
                app?.comment ?? "",
                id
            ].join(" ").toLowerCase();
            if (query && !haystack.includes(query)) continue;
            result.push(app);
        }
        result.sort((a, b) => String(a?.name ?? a?.id ?? "")
            .localeCompare(String(b?.name ?? b?.id ?? "")));
        return result;
    }

    settingsPageIndex: embedded ? 2 : 22
    settingsPageName: Translation.tr("Dock & Dashboard")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
    readonly property var tabChoices: {
        const choices = [
            { displayName: Translation.tr("Dashboard"), icon: "dashboard", value: "dashboard" },
            { displayName: Translation.tr("Weekly Planner"), icon: "calendar_month", value: "weeklyPlanner" }
        ];
        if (Config.options?.dashboard?.music?.enable ?? true)
            choices.splice(1, 0, { displayName: Translation.tr("Music"), icon: "library_music", value: "music" });
        if (Config.options?.dashboard?.spacedRepetition?.enable ?? true)
            choices.push({ displayName: Translation.tr("Spaced Repetition"), icon: "school", value: "spacedRepetition" }); // contract: value:"spacedRepetition"
        if (AlisIntergration.exercisesTrackerEnabled)
            choices.push({ displayName: Translation.tr("Exercises Tracker"), icon: "fitness_center", value: "exercisesTracker" }); // contract: value:"exercisesTracker"
        for (const tab of TabPolicy.tabs(Config.options?.dashboard?.customTabs))
            choices.push({ displayName: tab.name, icon: "tab", value: tab.id });
        return choices;
    }

    SettingsTaskNavigator {
        visible: !root.embedded
        showTabBar: false
        showIntro: false
        icon: "call_to_action"
        title: Translation.tr("Dock & Dashboard")
        description: Translation.tr("Dock behavior, window indicators, dashboard hub and local music.")
        summary: Translation.tr("Dock & Indicators · Pinned apps · Dashboard · Local Music")
    }

    SettingsCardSection {
        visible: !root.isIiActive
        expanded: true
        icon: "info"
        title: Translation.tr("Not Active")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Dock & Dashboard settings apply to Abyss and Material panel styles.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
    }

    SettingsCardSection {
        id: dockIndicatorsCard
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: root.isIiActive
        expanded: true
        icon: "call_to_action"
        title: Translation.tr("Dock & Indicators")

        SettingsGroup {
            GridLayout {
                id: dockPrimaryToggles
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 340 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.dock.enable
                    onCheckedChanged: Config.setNestedValue("dock.enable", checked)
                    StyledToolTip { text: Translation.tr("Show the application dock") }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "dashboard"
                    text: Translation.tr("Show Dashboard icon")
                    checked: Config.options?.dock?.showDashboardButton ?? true
                    onCheckedChanged: Config.setNestedValue("dock.showDashboardButton", checked)
                    StyledToolTip {
                        text: Translation.tr("Show the Dashboard / Overview launcher button in the Dock")
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "colors"
                    text: Translation.tr("Tint app icons")
                    checked: Config.options.dock.monochromeIcons
                    onCheckedChanged: Config.setNestedValue("dock.monochromeIcons", checked)
                    StyledToolTip {
                        text: Translation.tr("Apply accent color tint to dock app icons")
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "splitscreen"
                    text: Translation.tr("Separate pinned from running")
                    checked: Config.options?.dock?.separatePinnedFromRunning ?? true
                    onCheckedChanged: Config.setNestedValue("dock.separatePinnedFromRunning", checked)
                    StyledToolTip {
                        text: Translation.tr("Show pinned-only apps on the left, running apps on the right with a separator")
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "notifications"
                    text: Translation.tr("Notification badges")
                    checked: Config.options?.dock?.notificationBadge ?? true
                    onCheckedChanged: Config.setNestedValue("dock.notificationBadge", checked)
                    StyledToolTip {
                        text: Translation.tr("Show the number of pending notifications on each app icon")
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "my_location"
                    text: Translation.tr("Highlight focused window")
                    checked: Config.options.dock.smartIndicator !== false
                    onCheckedChanged: Config.setNestedValue("dock.smartIndicator", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "more_horiz"
                    text: Translation.tr("Dots for inactive apps")
                    checked: Config.options.dock.showAllWindowDots !== false
                    onCheckedChanged: Config.setNestedValue("dock.showAllWindowDots", checked)
                }
            }

            SettingsDivider {}

            GridLayout {
                id: dockSecondaryToggles
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 340 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "minimize"
                    text: Translation.tr("Click focused to minimize")
                    checked: Config.options?.dock?.minimizeUnfocused ?? false
                    onCheckedChanged: Config.setNestedValue("dock.minimizeUnfocused", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "crop_square"
                    text: Translation.tr("Card dock frame")
                    checked: Config.options?.dock?.cardStyle ?? false
                    onCheckedChanged: Config.setNestedValue("dock.cardStyle", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "widgets"
                    visible: Config.options?.panelFamily !== "abyss"
                    text: Translation.tr("Show dock background")
                    checked: Config.options.dock.showBackground
                    onCheckedChanged: Config.setNestedValue("dock.showBackground", checked)
                    StyledToolTip {
                        text: Translation.tr("Show a background behind the dock")
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "blur_on"
                    visible: Config.options?.panelFamily !== "abyss"
                    text: Translation.tr("Blur dock glass")
                    checked: Config.options?.dock?.enableBlurGlass ?? true
                    onCheckedChanged: Config.setNestedValue("dock.enableBlurGlass", checked)
                }
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 720 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 18
                rowSpacing: 12

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Dock position")

                    ConfigSelectionArray {
                        currentValue: Config.options?.dock?.position ?? "bottom"
                        onSelected: newValue => Config.setNestedValue("dock.position", newValue)
                        options: [
                            { displayName: Translation.tr("Left"), icon: "arrow_back", value: "left" },
                            { displayName: Translation.tr("Top"), icon: "arrow_upward", value: "top" },
                            { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: "bottom" },
                            { displayName: Translation.tr("Right"), icon: "arrow_forward", value: "right" }
                        ]
                    }

                    ConfigRow {
                        uniform: true
                        ConfigSpinBox {
                            icon: "height"
                            text: Translation.tr("Dock height (px)")
                            value: Config.options.dock.height ?? 60
                            from: 40
                            to: 100
                            stepSize: 5
                            onValueChanged: Config.setNestedValue("dock.height", value)
                        }

                        ConfigSpinBox {
                            icon: "aspect_ratio"
                            text: Translation.tr("Icon size (px)")
                            value: Config.options.dock.iconSize ?? 35
                            from: 20
                            to: 60
                            stepSize: 5
                            onValueChanged: Config.setNestedValue("dock.iconSize", value)
                        }
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Reveal behavior")
                    tooltip: Translation.tr("Hover reveals the Dock at the edge; Empty workspace shows it on an empty desktop.")

                    ConfigSelectionArray {
                        currentValue: Config.options?.dock?.hoverToReveal ?? true
                        onSelected: newValue => Config.setNestedValue("dock.hoverToReveal", newValue)
                        options: [
                            { displayName: Translation.tr("Hover"), icon: "highlight_mouse_cursor", value: true },
                            { displayName: Translation.tr("Empty workspace"), icon: "desktop_windows", value: false }
                        ]
                    }

                    ConfigRow {
                        id: revealModeToggles
                        uniform: true

                        SettingsSwitch {
                            buttonIcon: "desktop_windows"
                            text: Translation.tr("Show on desktop")
                            enabled: !(Config.options?.dock?.hoverToReveal ?? true)
                            checked: Config.options?.dock?.showOnDesktop ?? true
                            onCheckedChanged: Config.setNestedValue("dock.showOnDesktop", checked)
                            StyledToolTip {
                                text: Translation.tr("Show dock when no window is focused (Empty workspace mode only)")
                            }
                        }

                        SettingsSwitch {
                            buttonIcon: "keep"
                            text: Translation.tr("Pinned on startup")
                            enabled: !(Config.options?.dock?.hoverToReveal ?? true)
                            checked: Config.options.dock.pinnedOnStartup
                            onCheckedChanged: Config.setNestedValue("dock.pinnedOnStartup", checked)
                            StyledToolTip {
                                text: Translation.tr("Keep dock visible at all times (Empty workspace mode only)")
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true

                        ConfigSpinBox {
                            icon: "vertical_align_bottom"
                            text: Translation.tr("Reveal edge (px)")
                            value: Config.options?.dock?.hoverRegionHeight ?? 2
                            from: 1
                            to: 16
                            stepSize: 1
                            onValueChanged: Config.setNestedValue("dock.hoverRegionHeight", value)
                        }

                        ConfigSpinBox {
                            icon: "filter_5"
                            text: Translation.tr("Max window dots")
                            value: Config.options?.dock?.maxIndicatorDots ?? 5
                            from: 1
                            to: 10
                            stepSize: 1
                            onValueChanged: Config.setNestedValue("dock.maxIndicatorDots", value)
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: pinnedAppsCard
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: root.isIiActive
        expanded: true
        icon: "keep"
        title: Translation.tr("Pinned apps")

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Drag to reorder · eye hides · minus removes.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: (Config.options?.dock?.pinnedApps?.length ?? 0) === 0
                text: "Nothing pinned yet. Add applications below or right-click any Dock icon."
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: Config.options?.dock?.pinnedApps ?? []

                    delegate: Item {
                        id: pinnedSlot
                        required property var modelData
                        required property int index
                        readonly property string appId: String(modelData ?? "")
                        Layout.fillWidth: true
                        implicitHeight: 44
                        clip: false

                        DropArea {
                            anchors.fill: parent
                            keys: ["alis-dock-pinned-app"]
                            enabled: root.pinnedDragging
                            onEntered: drag => {
                                if (drag.source && drag.source.appId !== pinnedSlot.appId)
                                    root.pinnedDropIndex = pinnedSlot.index;
                            }
                        }

                        Rectangle {
                            id: pinnedRow
                            property string appId: pinnedSlot.appId
                            width: pinnedSlot.width
                            height: 44
                            x: 0
                            y: 0
                            z: pinnedHandle.drag.active ? 100 : 1
                            radius: Appearance.rounding.small
                            color: pinnedHandle.containsMouse || pinnedHandle.drag.active
                                ? Appearance.colors.colLayer1Hover
                                : Appearance.colors.colLayer1
                            border.width: root.pinnedDragging
                                && root.pinnedDropIndex === pinnedSlot.index ? 1 : 0
                            border.color: Appearance.colors.colPrimary
                            opacity: root.isPinnedVisible(pinnedSlot.appId) ? 1 : 0.62

                            Drag.active: pinnedHandle.drag.active
                            Drag.source: pinnedRow
                            Drag.keys: ["alis-dock-pinned-app"]
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 8

                                Item {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "drag_indicator"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colSubtext
                                    }

                                    MouseArea {
                                        id: pinnedHandle
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: drag.active
                                            ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        drag.target: pinnedRow
                                        drag.axis: Drag.YAxis
                                        drag.minimumY: -pinnedSlot.index * 48
                                        drag.maximumY: ((Config.options?.dock?.pinnedApps?.length ?? 0)
                                            - pinnedSlot.index - 1) * 48
                                        onPressed: {
                                            root.pinnedDragInfo = {
                                                id: pinnedSlot.appId,
                                                index: pinnedSlot.index
                                            };
                                            root.pinnedDropIndex = pinnedSlot.index;
                                        }
                                        onReleased: {
                                            pinnedRow.Drag.drop();
                                            root.commitPinnedDrop();
                                            pinnedRow.y = 0;
                                        }
                                        onCanceled: {
                                            root.pinnedDragInfo = null;
                                            root.pinnedDropIndex = -1;
                                            pinnedRow.y = 0;
                                        }
                                    }
                                }

                                IconImage {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    source: root.pinnedAppIcon(pinnedSlot.appId)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.pinnedAppLabel(pinnedSlot.appId)
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: pinnedSlot.appId
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        elide: Text.ElideRight
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    buttonRadius: Appearance.rounding.full
                                    Accessible.name: root.isPinnedVisible(pinnedSlot.appId)
                                        ? Translation.tr("Hide from Dock")
                                        : Translation.tr("Show in Dock")
                                    onClicked: root.togglePinnedVisibility(pinnedSlot.appId)
                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: root.isPinnedVisible(pinnedSlot.appId)
                                                ? "visibility" : "visibility_off"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: root.isPinnedVisible(pinnedSlot.appId)
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colSubtext
                                        }
                                    }
                                    StyledToolTip {
                                        text: root.isPinnedVisible(pinnedSlot.appId)
                                            ? Translation.tr("Hide from Dock")
                                            : Translation.tr("Show in Dock")
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    buttonRadius: Appearance.rounding.full
                                    Accessible.name: Translation.tr("Remove from Dock")
                                    onClicked: root.removePinnedApp(pinnedSlot.appId)
                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "remove_circle"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                    StyledToolTip { text: Translation.tr("Remove from Dock") }
                                }
                            }
                        }
                    }
                }
            }

            SettingsDivider {}

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 8
                Layout.rightMargin: 6
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Translation.tr("Add applications")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                }

                RippleButton {
                    id: addApplicationsToggle
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    Accessible.name: root.addApplicationsOpen
                        ? Translation.tr("Close application picker")
                        : Translation.tr("Add applications")
                    onClicked: {
                        root.addApplicationsOpen = !root.addApplicationsOpen;
                        if (root.addApplicationsOpen)
                            Qt.callLater(() => pinnedAppSearchField.forceActiveFocus());
                        else
                            pinnedAppSearchField.text = "";
                    }

                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.addApplicationsOpen ? "close" : "add"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.addApplicationsOpen
                                ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colPrimary
                        }
                    }

                    StyledToolTip {
                        text: root.addApplicationsOpen
                            ? Translation.tr("Close application picker")
                            : Translation.tr("Add applications")
                    }
                }
            }

            Item {
                id: addApplicationsPanel
                Layout.fillWidth: true
                implicitHeight: root.addApplicationsOpen
                    ? addApplicationsContent.implicitHeight : 0
                opacity: root.addApplicationsOpen ? 1 : 0
                clip: true
                enabled: root.addApplicationsOpen

                Behavior on implicitHeight {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                ColumnLayout {
                    id: addApplicationsContent
                    width: parent.width
                    spacing: 4

                    MaterialTextField {
                        id: pinnedAppSearchField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        placeholderText: Translation.tr("Search applications...")
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    ListView {
                        id: pinnedAppSearchList
                        Layout.fillWidth: true
                        implicitHeight: Math.min(200, Math.max(48, contentHeight))
                        clip: true
                        model: root.addApplicationsOpen ? root.filteredAddApps() : []
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: 2

                        PagePlaceholder {
                            shown: pinnedAppSearchList.count === 0
                            icon: "search_off"
                            title: Translation.tr("No matching apps")
                            description: Translation.tr("Try a different search term.")
                            anchors.fill: parent
                        }

                        delegate: Item {
                            id: addAppDelegate
                            required property var modelData
                            required property int index
                            width: pinnedAppSearchList.width
                            height: 42

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.small
                                color: addAppHover.hovered
                                    ? Appearance.colors.colLayer1Hover : "transparent"
                            }
                            HoverHandler { id: addAppHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 8

                                Item {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26

                                    Image {
                                        id: addAppIcon
                                        anchors.fill: parent
                                        source: AppSearch.getIconSource(
                                            addAppDelegate.modelData?.icon ?? "",
                                            addAppDelegate.modelData?.name ?? "")
                                        sourceSize.width: 52
                                        sourceSize.height: 52
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: addAppIcon.status !== Image.Ready
                                        text: "apps"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: addAppDelegate.modelData?.name
                                            ?? addAppDelegate.modelData?.id ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(addAppDelegate.modelData?.id ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    buttonRadius: Appearance.rounding.full
                                    Accessible.name: Translation.tr("Add to Dock")
                                    onClicked: root.addPinnedApp(
                                        String(addAppDelegate.modelData?.id ?? ""))
                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "add_circle"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colPrimary
                                        }
                                    }
                                    StyledToolTip { text: Translation.tr("Add to Dock") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        id: dashboardCard
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: root.isIiActive
        expanded: true
        icon: "space_dashboard"
        title: Translation.tr("Dashboard")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Default tab after inactivity")
                ConfigSelectionArray {
                    currentValue: root.tabChoices.some(item =>
                        item.value === (Config.options?.dashboard?.defaultTabId ?? "dashboard"))
                        ? (Config.options?.dashboard?.defaultTabId || "dashboard") : "dashboard"
                    options: root.tabChoices
                    onSelected: id => Config.setNestedValue("dashboard.defaultTabId", id)
                }
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 340 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    text: Translation.tr("Return after (min)")
                    value: Config.options?.dashboard?.inactiveMinutes ?? 0
                    from: 0
                    to: 240
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("dashboard.inactiveMinutes", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    text: Translation.tr("Card opacity (%)")
                    value: Math.round((Config.options?.dashboard?.appearance?.cardOpacity ?? 1) * 100)
                    from: 30
                    to: 100
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("dashboard.appearance.cardOpacity", value / 100)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    text: Translation.tr("% width")
                    value: Math.round((Config.options?.dashboard?.widthRatio ?? 0.72) * 100)
                    from: 40
                    to: 90
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("dashboard.widthRatio", value / 100)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    text: Translation.tr("% height")
                    value: Math.round((Config.options?.dashboard?.heightRatio ?? 0.72) * 100)
                    from: 45
                    to: 90
                    stepSize: 2
                    onValueChanged: Config.setNestedValue("dashboard.heightRatio", value / 100)
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true
                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Welcome subtitle")
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Custom phrase (optional)")
                        text: Config.options?.dashboard?.subtitle ?? ""
                        onTextChanged: {
                            Qt.callLater(() => {
                                Config.setNestedValue("dashboard.subtitle", text);
                            });
                        }
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("GitHub username")
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("e.g. octocat")
                        text: Config.options?.dashboard?.github?.username ?? ""
                        onTextChanged: {
                            Qt.callLater(() => {
                                Config.setNestedValue("dashboard.github.username", text);
                            });
                        }
                    }
                }
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 340 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "web_asset"
                    text: Translation.tr("Show header")
                    checked: Config.options?.dashboard?.showHeader ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.showHeader", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Power buttons")
                    checked: Config.options?.dashboard?.showPowerButtons ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.showPowerButtons", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "title"
                    text: Translation.tr("Show card titles")
                    checked: Config.options?.dashboard?.appearance?.showCardTitles ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.appearance.showCardTitles", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "bolt"
                    text: Translation.tr("Keep loaded")
                    checked: Config.options?.dashboard?.keepLoaded ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.keepLoaded", checked)
                    StyledToolTip {
                        text: Translation.tr("Keep Dashboard ready in memory for instant opening")
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "school"
                    text: Translation.tr("Spaced Repetition tab")
                    checked: Config.options?.dashboard?.spacedRepetition?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.spacedRepetition.enable", checked)
                }

                SettingsSwitch {
                    objectName: "dockExercisesTrackerTabSwitch"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "fitness_center"
                    text: Translation.tr("Exercises Tracker tab")
                    enabled: AlisIntergration.available
                    checked: AlisIntergration.exercisesTrackerEnabled
                    onToggledByUser: nextChecked => {
                        AlisIntergration.setExercisesTrackerEnabled(nextChecked)
                        checked = Qt.binding(() => AlisIntergration.exercisesTrackerEnabled)
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "compress"
                    text: Translation.tr("Compact card density")
                    checked: (Config.options?.dashboard?.appearance?.density ?? "comfortable") === "compact"
                    onCheckedChanged: Config.setNestedValue("dashboard.appearance.density", checked ? "compact" : "comfortable")
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "event_available"
                    text: Translation.tr("Weekend reviews")
                    checked: Config.options?.dashboard?.spacedRepetition?.weekendsEnabled ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.spacedRepetition.weekendsEnabled", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "auto_fix_high"
                    text: Translation.tr("Auto-generate cloze")
                    checked: Config.options?.dashboard?.spacedRepetition?.autoCloze ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.spacedRepetition.autoCloze", checked)
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "add_task"
                    text: Translation.tr("Daily new cards")
                    value: Config.options?.dashboard?.spacedRepetition?.dailyNewLimit ?? 20
                    from: 1
                    to: 200
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.dailyNewLimit", value)
                }

                ConfigSpinBox {
                    icon: "fact_check"
                    text: Translation.tr("Daily review cap")
                    value: Config.options?.dashboard?.spacedRepetition?.dailyReviewLimit ?? 100
                    from: 10
                    to: 500
                    stepSize: 10
                    onValueChanged: Config.setNestedValue("dashboard.spacedRepetition.dailyReviewLimit", value)
                }
            }
        }
    }

    SettingsCardSection {
        id: localMusicCard
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: root.isIiActive
        expanded: true
        icon: "library_music"
        title: Translation.tr("Local Music (MPD)")

        DashboardMusicSettings {
            Layout.fillWidth: true
        }

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("MPD host")
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: "127.0.0.1"
                    text: Config.options?.sidebar?.music?.mpdHost ?? "127.0.0.1"
                    onEditingFinished: {
                        const nextHost = text.trim() || "127.0.0.1";
                        Config.setNestedValue("sidebar.music.mpdHost", nextHost);
                    }
                }
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 340 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "library_music"
                    text: Translation.tr("Dashboard music tab")
                    checked: Config.options?.dashboard?.music?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.music.enable", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "queue_music"
                    text: Translation.tr("Sidebar MPD player")
                    checked: Config.options?.sidebar?.music?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("sidebar.music.enable", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Music scrollbars")
                    checked: Config.options?.dashboard?.music?.showScrollbars ?? false
                    onCheckedChanged: Config.setNestedValue("dashboard.music.showScrollbars", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "filter_alt"
                    text: Translation.tr("Filter duplicate players")
                    checked: Config.options?.media?.filterDuplicatePlayers ?? true
                    onCheckedChanged: Config.setNestedValue("media.filterDuplicatePlayers", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "album"
                    text: Translation.tr("Sidebar media card")
                    checked: Config.options?.sidebar?.widgets?.media ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.widgets.media", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "featured_play_list"
                    text: Translation.tr("Desktop media widget")
                    checked: Config.options?.background?.widgets?.mediaControls?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("background.widgets.mediaControls.enable", checked)
                }
            }
        }
    }

    SettingsCardSection {
        id: dashboardCanvasCard
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        visible: root.isIiActive
        expanded: true
        icon: "grid_view"
        title: Translation.tr("Canvas & Media Popups")

        SettingsGroup {
            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 680 * Appearance.fontSizeScale ? 2 : 1
                uniformCellWidths: columns > 1
                columnSpacing: 16
                rowSpacing: 10

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Canvas grid style")
                    ConfigSelectionArray {
                        currentValue: Config.options?.dashboard?.canvas?.gridStyle ?? "dots"
                        onSelected: val => Config.setNestedValue("dashboard.canvas.gridStyle", val)
                        options: [
                            { displayName: Translation.tr("Dots"), icon: "grain", value: "dots" },
                            { displayName: Translation.tr("Lines"), icon: "grid_4x4", value: "lines" },
                            { displayName: Translation.tr("Hidden"), icon: "visibility_off", value: "none" }
                        ]
                    }
                }

                ContentSubsection {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Media popup placement")
                    ConfigSelectionArray {
                        currentValue: Config.options?.media?.popupMode ?? "dock"
                        onSelected: val => Config.setNestedValue("media.popupMode", val)
                        options: [
                            { displayName: Translation.tr("Dock"), icon: "call_to_action", value: "dock" },
                            { displayName: Translation.tr("Bar"), icon: "web_asset", value: "bar" }
                        ]
                    }
                }
            }

            SettingsDivider {}

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 340 ? 2 : 1
                uniformCellWidths: columns === 2
                columnSpacing: Appearance.sizes.spacingSmall
                rowSpacing: Appearance.sizes.spacingSmall

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "grid_goldenratio"
                    text: Translation.tr("Snap cards to grid")
                    checked: Config.options?.dashboard?.canvas?.snap ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.canvas.snap", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "fit_screen"
                    text: Translation.tr("Auto-fit canvas")
                    checked: Config.options?.dashboard?.canvas?.autoAdjustSize ?? true
                    onCheckedChanged: Config.setNestedValue("dashboard.canvas.autoAdjustSize", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    buttonIcon: "music_video"
                    text: Translation.tr("Media track OSD")
                    checked: Config.options?.osd?.mediaEnabled ?? true
                    onCheckedChanged: Config.setNestedValue("osd.mediaEnabled", checked)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    icon: "grid_on"
                    text: Translation.tr("Grid size (px)")
                    value: Config.options?.dashboard?.canvas?.gridSize ?? 24
                    from: 12
                    to: 48
                    stepSize: 4
                    onValueChanged: Config.setNestedValue("dashboard.canvas.gridSize", value)
                }
            }
        }
    }
}
