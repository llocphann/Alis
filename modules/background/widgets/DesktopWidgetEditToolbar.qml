pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.abyss.looks
import "DesktopWidgetEditorPlacement.js" as Placement

// Bottom-connected 2-tier Abyss customization dock for Desktop Widgets Edit Mode.
// When hosted in AbyssPerimeter, widgetEditorBody paints the unified liquid Screen Edge
// silhouette; in standalone/Waffle fallback, AbyssCustomizationDock paints a bottom-anchored panel.
Item {
    id: editControlsBar

    required property var windowContext
    required property var safeBounds
    required property var manager
    required property Item fallbackParent
    property var obstacles: []
    property var abyssHost: null
    property Item abyssRightHost: null

    readonly property string outputName: windowContext?.screenName ?? ""
    readonly property bool abyssMode: (Config.options?.panelFamily ?? "abyss") === "abyss"
    readonly property bool hosted: abyssMode && abyssHost !== null
    readonly property bool managerShown: Boolean(manager?.shown)
    readonly property real desiredRightDockWidth: manager?.desiredDockWidth ?? Math.round(284 * Appearance.fontSizeScale)
    readonly property real desiredRightDockHeight: manager?.desiredDockHeight ?? Math.round(520 * Appearance.fontSizeScale)
    property string newCustomWidgetName: ""
    readonly property real hostPadding: hosted ? Number(abyssHost?.padding ?? 6) : 0
    readonly property real desiredDepth: Math.round(dock.implicitHeight + hostPadding * 2)
    readonly property real desiredDockWidth: Math.min(2400, Math.max(680, Math.ceil(dock.implicitWidth)))
    readonly property real desiredDockHeight: Math.round(dock.implicitHeight + 6)

    Binding {
        target: editControlsBar.manager
        property: "externalDockParent"
        value: editControlsBar.hosted ? editControlsBar.abyssRightHost : null
        when: editControlsBar.manager !== null && editControlsBar.manager.externalDockParent !== undefined
        restoreMode: Binding.RestoreBindingOrValue
    }
    readonly property var placement: Placement.choose(
        hosted ? abyssHost.editorWorkArea : {
            left: safeBounds.safeLeft,
            top: safeBounds.safeTop,
            right: safeBounds.safeRight,
            bottom: safeBounds.safeBottom
        },
        obstacles,
        GlobalStates.selectedDesktopWidget,
        desiredDepth
    )
    readonly property bool vertical: hosted && ["left", "right"].includes(placement.edge)
    readonly property real railExtent: vertical ? height : width
    readonly property bool compactHeader: width < 840
    readonly property bool ultraCompactHeader: width < 560
    readonly property bool iconOnlyHeader: width < 460

    property alias activeTab: dock.activeTab
    property alias trayExpanded: dock.trayExpanded
    property alias searchText: dock.searchText

    readonly property string selectedWidgetKey: {
        const sel = String(GlobalStates.selectedDesktopWidget ?? "");
        const prefix = editControlsBar.outputName + "::";
        return sel.startsWith(prefix) ? sel.slice(prefix.length) : "";
    }

    readonly property bool gridSnapEnabled: Boolean(Config.getNestedValue("background.widgets.editGrid.snap", true))
    readonly property int gridSizeValue: Number(Config.getNestedValue("background.widgets.editGrid.size", 32))
    readonly property int dynamicOpacityValue: Number(Config.getNestedValue("background.widgets.dynamicOpacity", 0))

    readonly property var builtinWidgets: [
        { key: "clock", icon: "schedule", label: Translation.tr("Clock"), defaultOn: true, accent: "#7aa2f7", tags: "time analog digital date" },
        { key: "weather", icon: "cloud", label: Translation.tr("Weather"), defaultOn: false, accent: "#64b5f6", tags: "forecast temperature sky rain" },
        { key: "mediaControls", icon: "album", label: Translation.tr("Media"), defaultOn: false, accent: "#b39ddb", tags: "music player audio now playing spotify" },
        { key: "systemMonitor", icon: "monitor_heart", label: Translation.tr("System Monitor"), defaultOn: false, accent: "#4dd0e1", tags: "cpu ram gpu vitals resources" },
        { key: "calendarUpcoming", icon: "event", label: Translation.tr("Upcoming Events"), defaultOn: false, accent: "#ef5350", tags: "calendar agenda schedule month" },
        { key: "notes", icon: "sticky_note_2", label: Translation.tr("Notes"), defaultOn: false, accent: "#ffca28", tags: "memo sticky todo text" },
        { key: "battery", icon: "battery_full", label: Translation.tr("Battery"), defaultOn: false, accent: "#66bb6a", tags: "power charge laptop energy" },
        { key: "visualizer", icon: "graphic_eq", label: Translation.tr("Visualizer"), defaultOn: false, accent: "#ab47bc", tags: "spectrum cava equalizer sound wave" },
        { key: "newsTicker", icon: "newspaper", label: Translation.tr("News Ticker"), defaultOn: false, accent: "#ffa726", tags: "rss headlines feed articles" },
        { key: "worldClock", icon: "public", label: Translation.tr("World Clock"), defaultOn: false, accent: "#29b6f6", tags: "timezone global cities utc" },
        { key: "uptime", icon: "avg_pace", label: Translation.tr("System Uptime"), defaultOn: false, accent: "#26a69a", tags: "boot session duration timer" },
        { key: "userCard", icon: "account_circle", label: Translation.tr("User Card"), defaultOn: false, accent: "#7e57c2", tags: "profile avatar host whoami" },
        { key: "customImage", icon: "add_photo_alternate", label: Translation.tr("Custom Image"), defaultOn: false, accent: "#ec407a", tags: "picture photo sticker frame" },
        { key: "imageConverter", icon: "transform", label: Translation.tr("Image Converter"), defaultOn: false, accent: "#5c6bc0", tags: "png jpg webp format convert" },
        { key: "japaneseTypography", icon: "translate", label: Translation.tr("Japanese Typography"), defaultOn: false, accent: "#ff7043", tags: "kana kanji vertical quote" }
    ]

    function isWidgetEnabled(layoutKey: string, defaultOn: bool): bool {
        void Config.revision;
        if (layoutKey.startsWith("custom.")) {
            const baseDefault = Boolean(Config.getNestedValue("background.widgets." + layoutKey + ".enable", defaultOn));
            return DesktopWidgetLayout.enabled(editControlsBar.outputName, layoutKey, baseDefault);
        }
        if (typeof editControlsBar.windowContext?._widgetEnabled === "function") {
            const baseDefault = Boolean(Config.getNestedValue("background.widgets." + layoutKey + ".enable", defaultOn));
            return Boolean(editControlsBar.windowContext._widgetEnabled(layoutKey, baseDefault));
        }
        const fallback = Boolean(Config.getNestedValue("background.widgets." + layoutKey + ".enable", defaultOn));
        return DesktopWidgetLayout.enabled(editControlsBar.outputName, layoutKey, fallback);
    }

    function toggleWidget(layoutKey: string, defaultOn: bool): void {
        const currentlyOn = editControlsBar.isWidgetEnabled(layoutKey, defaultOn);
        const nextState = !currentlyOn;
        DesktopWidgetLayout.setGloballyEnabled(layoutKey, nextState);
        const instanceKey = editControlsBar.outputName + "::" + layoutKey;
        if (nextState) {
            GlobalStates.selectDesktopWidget(instanceKey);
        } else if (GlobalStates.selectedDesktopWidget === instanceKey) {
            GlobalStates.clearDesktopWidgetSelection();
        }
    }

    function matchesSearch(title: string, extraTags: string): bool {
        const q = dock.searchText.trim().toLowerCase();
        if (q.length === 0)
            return true;
        return String(title ?? "").toLowerCase().includes(q)
            || String(extraTags ?? "").toLowerCase().includes(q);
    }

    function shouldShowWidgetInGallery(enabled: bool, title: string, extraTags: string): bool {
        if (dock.activeTab === "active" && !enabled)
            return false;
        return editControlsBar.matchesSearch(title, extraTags);
    }

    readonly property int visibleGalleryCount: {
        void Config.revision;
        let count = 0;
        for (let i = 0; i < editControlsBar.builtinWidgets.length; ++i) {
            const w = editControlsBar.builtinWidgets[i];
            const enabled = editControlsBar.isWidgetEnabled(w.key, w.defaultOn);
            if (editControlsBar.shouldShowWidgetInGallery(enabled, w.label, w.key + " " + w.tags))
                count++;
        }
        const customs = CustomWidgets.ready ? CustomWidgets.widgets : [];
        for (let j = 0; j < customs.length; ++j) {
            const cw = customs[j];
            const enabled = editControlsBar.isWidgetEnabled("custom." + cw.id, false);
            if (editControlsBar.shouldShowWidgetInGallery(enabled, cw.name, cw.id + " custom"))
                count++;
        }
        return count;
    }

    readonly property int activeWidgetCount: {
        void Config.revision;
        let count = 0;
        for (let i = 0; i < editControlsBar.builtinWidgets.length; ++i) {
            const w = editControlsBar.builtinWidgets[i];
            if (editControlsBar.isWidgetEnabled(w.key, w.defaultOn))
                count++;
        }
        if (CustomWidgets.ready) {
            for (let j = 0; j < CustomWidgets.widgets.length; ++j) {
                const cw = CustomWidgets.widgets[j];
                if (editControlsBar.isWidgetEnabled("custom." + cw.id, false))
                    count++;
            }
        }
        return count;
    }

    readonly property int customWidgetCount: CustomWidgets.ready ? CustomWidgets.widgets.length : 0

    readonly property bool exampleWidgetInstalled: {
        if (!CustomWidgets.ready)
            return false;
        for (let i = 0; i < CustomWidgets.widgets.length; ++i) {
            if (CustomWidgets.widgets[i].id === "example-widget")
                return true;
        }
        return false;
    }

    readonly property bool outputHasPositionOverrides: {
        void Config.revision;
        const record = DesktopWidgetLayout.outputRecord(editControlsBar.outputName);
        const widgets = record?.widgets;
        if (!widgets || typeof widgets !== "object")
            return false;
        for (const key of Object.keys(widgets)) {
            const entry = widgets[key];
            if (entry && (entry.x !== undefined || entry.y !== undefined || entry.placementStrategy !== undefined))
                return true;
        }
        return false;
    }

    function resetOutputPositions(): void {
        const record = DesktopWidgetLayout.outputRecord(editControlsBar.outputName);
        const widgets = record?.widgets;
        if (!widgets || typeof widgets !== "object")
            return;
        for (const key of Object.keys(widgets))
            DesktopWidgetLayout.clearValues(editControlsBar.outputName, key, ["x", "y", "placementStrategy"]);
    }

    function resetSelectedWidgetPosition(): void {
        if (editControlsBar.selectedWidgetKey.length === 0)
            return;
        DesktopWidgetLayout.clearValues(
            editControlsBar.outputName,
            editControlsBar.selectedWidgetKey,
            ["x", "y", "placementStrategy"]
        );
    }

    function cycleGridSize(): void {
        const sizes = [16, 32, 48, 64];
        const idx = sizes.indexOf(editControlsBar.gridSizeValue);
        const next = sizes[(idx + 1) % sizes.length];
        Config.setNestedValue("background.widgets.editGrid.size", next);
    }

    function toggleWidgetScreen(screenName: string): void {
        const current = Config.getNestedValue("background.widgets.screenList", []) ?? [];
        const list = Array.isArray(current) ? current.slice() : [];
        const idx = list.indexOf(screenName);
        if (idx === -1)
            list.push(screenName);
        else
            list.splice(idx, 1);
        Config.setNestedValue("background.widgets.screenList", list);
    }

    property string registeredOutput: ""
    function registerOutput(): void {
        if (registeredOutput === outputName)
            return;
        GlobalStates.unregisterDesktopWidgetEditor(registeredOutput, editControlsBar);
        registeredOutput = outputName;
        GlobalStates.registerDesktopWidgetEditor(registeredOutput, editControlsBar);
    }
    onOutputNameChanged: registerOutput()
    Component.onCompleted: registerOutput()
    Component.onDestruction: GlobalStates.unregisterDesktopWidgetEditor(registeredOutput, editControlsBar)

    parent: hosted ? abyssHost.contentParent : fallbackParent
    width: hosted
        ? abyssHost.targetRecord.content.width
        : Math.max(0, Math.min(Math.round(safeBounds.safeWidth * 0.80), Math.min(1080, Math.max(320, dock.implicitWidth))))
    height: hosted ? abyssHost.targetRecord.content.height : dock.implicitHeight
    x: hosted ? 0 : Math.round(safeBounds.safeLeft + (safeBounds.safeWidth - width) / 2)
    y: hosted ? 0 : Math.round(Math.max(safeBounds.safeTop, safeBounds.safeBottom - height))
    visible: hosted ? abyssHost.visualResident : GlobalStates.widgetEditMode
    enabled: GlobalStates.widgetEditMode

    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.AllButtons
    }

    // ── Reusable Pill Chip for Grid & Custom Trays ──
    component TrayActionChip: Rectangle {
        id: chip
        property string icon: ""
        property string label: ""
        property bool activeState: false
        property bool accentStyle: false
        property string tooltipText: ""
        signal clicked()

        implicitHeight: 32
        implicitWidth: chipRow.implicitWidth + 22
        height: 32
        radius: 16
        opacity: chip.enabled ? 1.0 : 0.38
        scale: chipMouse.pressed && chip.enabled ? 0.96 : 1.0
        color: chip.accentStyle
            ? (chipMouse.containsMouse && chip.enabled
                ? CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.24)
                : CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16))
            : (chip.activeState
                ? CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.18)
                : (chipMouse.containsMouse && chip.enabled
                    ? Appearance.colors.colLayer2Hover
                    : Qt.alpha(Appearance.colors.colLayer2, 0.65)))
        border.width: 1
        border.color: (chip.activeState || chip.accentStyle)
            ? Qt.alpha(Appearance.colors.colPrimary, 0.48)
            : Qt.alpha(Appearance.colors.colOutlineVariant, 0.28)

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                visible: chip.icon.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                iconSize: 16
                color: (chip.activeState || chip.accentStyle)
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer1
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: (chip.activeState || chip.accentStyle) ? Font.DemiBold : Font.Medium
                color: (chip.activeState || chip.accentStyle)
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer1
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            enabled: chip.enabled
            hoverEnabled: true
            cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.clicked()
        }

        StyledToolTip {
            position: "top"
            extraVisibleCondition: chipMouse.containsMouse && chip.tooltipText.length > 0
            text: chip.tooltipText
        }
    }

    // ── Single-branch Bespoke Miniature Widget Previews (inspired by iNiR v3.0.0 shelf cards) ──
    component WidgetMiniPreview: Loader {
        id: previewLoader
        required property string kind
        anchors.fill: parent
        sourceComponent: {
            switch (previewLoader.kind) {
            case "clock": return clockPreviewComp;
            case "weather": return weatherPreviewComp;
            case "mediaControls": return mediaPreviewComp;
            case "systemMonitor": return monitorPreviewComp;
            case "calendarUpcoming": return calendarPreviewComp;
            case "notes": return notesPreviewComp;
            case "battery": return batteryPreviewComp;
            case "visualizer": return visualizerPreviewComp;
            case "newsTicker": return newsPreviewComp;
            case "worldClock": return worldClockPreviewComp;
            case "uptime": return uptimePreviewComp;
            case "userCard": return userCardPreviewComp;
            case "customImage": return customImagePreviewComp;
            case "imageConverter": return converterPreviewComp;
            case "japaneseTypography": return typographyPreviewComp;
            default: return null;
            }
        }
    }

    Component {
        id: clockPreviewComp
        Item {
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 4
                spacing: 8

                Rectangle {
                    width: 38
                    height: 38
                    radius: 19
                    color: Qt.alpha(Appearance.colors.colLayer1, 0.55)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOnLayer1, 0.22)

                    Repeater {
                        model: 12
                        Rectangle {
                            required property int index
                            readonly property real ang: index * Math.PI / 6
                            width: index % 3 === 0 ? 2.5 : 1.5
                            height: width
                            radius: width / 2
                            x: 19 + Math.sin(ang) * 14.5 - width / 2
                            y: 19 - Math.cos(ang) * 14.5 - height / 2
                            color: Qt.alpha(Appearance.colors.colOnLayer1, index % 3 === 0 ? 0.65 : 0.28)
                        }
                    }

                    Rectangle {
                        x: 18.2
                        y: 10
                        width: 1.8
                        height: 9.5
                        radius: 0.9
                        color: Appearance.colors.colOnLayer1
                        transformOrigin: Item.Bottom
                        rotation: -58
                    }

                    Rectangle {
                        x: 18.3
                        y: 6.5
                        width: 1.5
                        height: 13
                        radius: 0.75
                        color: Appearance.colors.colPrimary
                        transformOrigin: Item.Bottom
                        rotation: 62
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 3.5
                        height: 3.5
                        radius: 1.75
                        color: Appearance.colors.colPrimary
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Row {
                        spacing: 3
                        StyledText {
                            text: "30"
                            font.pixelSize: 13
                            font.family: Appearance.font.family.numbers
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 1
                            text: "OCT"
                            font.pixelSize: 8
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Row {
                        spacing: 2.5
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                width: index === 3 ? 6 : 4
                                height: 4
                                radius: 2
                                color: index === 3
                                    ? Appearance.colors.colPrimary
                                    : Qt.alpha(Appearance.colors.colSubtext, 0.35)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: weatherPreviewComp
        Rectangle {
            radius: 8
            color: Qt.alpha("#64b5f6", 0.12)
            border.width: 1
            border.color: Qt.alpha("#64b5f6", 0.22)

            Row {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 5
                anchors.leftMargin: 7
                spacing: 4

                StyledText {
                    text: "21°"
                    font.pixelSize: 13
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "partly_cloudy_day"
                    iconSize: 13
                    color: "#90caf9"
                }
            }

            Canvas {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                height: 20
                onPaint: {
                    if (width <= 0 || height <= 0)
                        return;
                    const ctx = getContext("2d");
                    if (!ctx)
                        return;
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = "#f4b942";
                    ctx.lineWidth = 1.6;
                    ctx.beginPath();
                    ctx.moveTo(2, height * 0.72);
                    ctx.bezierCurveTo(width * 0.32, height * 0.18, width * 0.64, height * 0.24, width - 6, height * 0.58);
                    ctx.stroke();

                    ctx.fillStyle = "#64b5f6";
                    ctx.beginPath();
                    ctx.arc(width * 0.72, height * 0.42, 2.4, 0, Math.PI * 2);
                    ctx.fill();
                }
                Component.onCompleted: if (available) requestPaint()
                onWidthChanged: if (available) requestPaint()
            }
        }
    }

    Component {
        id: mediaPreviewComp
        Rectangle {
            radius: 8
            color: Qt.alpha("#b39ddb", 0.12)
            border.width: 1
            border.color: Qt.alpha("#b39ddb", 0.22)

            Row {
                id: mediaInnerRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 6
                anchors.rightMargin: 22
                spacing: 7

                Rectangle {
                    width: 34
                    height: 34
                    radius: 7
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha("#7e57c2", 0.65) }
                        GradientStop { position: 1.0; color: Qt.alpha("#283593", 0.75) }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: 16
                        color: "#ede7f6"
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(20, mediaInnerRow.width - 41)
                    spacing: 4

                    Rectangle {
                        width: Math.min(parent.width, 42)
                        height: 4.5
                        radius: 2.2
                        color: Qt.alpha(Appearance.colors.colOnLayer1, 0.72)
                    }
                    Rectangle {
                        width: Math.min(parent.width, 26)
                        height: 3.5
                        radius: 1.7
                        color: Qt.alpha(Appearance.colors.colSubtext, 0.45)
                    }
                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Qt.alpha(Appearance.colors.colOnLayer1, 0.16)
                        Rectangle {
                            width: parent.width * 0.58
                            height: parent.height
                            radius: 1.5
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }

    Component {
        id: monitorPreviewComp
        Rectangle {
            radius: 8
            color: Qt.alpha("#4dd0e1", 0.10)
            border.width: 1
            border.color: Qt.alpha("#4dd0e1", 0.22)

            StyledText {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 5
                anchors.leftMargin: 7
                text: "30%"
                font.pixelSize: 12
                font.family: Appearance.font.family.numbers
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            Column {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: 7
                anchors.rightMargin: 7
                spacing: 4

                Rectangle {
                    width: 28
                    height: 3.5
                    radius: 1.7
                    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.16)
                    Rectangle { width: 18; height: parent.height; radius: 1.7; color: "#4dd0e1" }
                }
                Rectangle {
                    width: 28
                    height: 3.5
                    radius: 1.7
                    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.16)
                    Rectangle { width: 11; height: parent.height; radius: 1.7; color: Appearance.colors.colPrimary }
                }
            }

            Canvas {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 6
                anchors.bottomMargin: 5
                width: 58
                height: 22
                onPaint: {
                    if (width <= 0 || height <= 0)
                        return;
                    const ctx = getContext("2d");
                    if (!ctx)
                        return;
                    ctx.clearRect(0, 0, width, height);
                    ctx.beginPath();
                    ctx.moveTo(0, height);
                    ctx.lineTo(0, height * 0.35);
                    ctx.lineTo(width * 0.35, height * 0.52);
                    ctx.lineTo(width * 0.68, height * 0.28);
                    ctx.lineTo(width, height * 0.76);
                    ctx.lineTo(width, height);
                    ctx.closePath();
                    ctx.fillStyle = "rgba(77, 208, 225, 0.22)";
                    ctx.fill();

                    ctx.beginPath();
                    ctx.moveTo(0, height * 0.35);
                    ctx.lineTo(width * 0.35, height * 0.52);
                    ctx.lineTo(width * 0.68, height * 0.28);
                    ctx.lineTo(width, height * 0.76);
                    ctx.strokeStyle = "#4dd0e1";
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }
                Component.onCompleted: if (available) requestPaint()
            }
        }
    }

    Component {
        id: calendarPreviewComp
        Rectangle {
            radius: 8
            color: Qt.alpha("#ef5350", 0.10)
            border.width: 1
            border.color: Qt.alpha("#ef5350", 0.22)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                spacing: 9

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Rectangle {
                        width: 14
                        height: 3.5
                        radius: 1.7
                        color: "#ef5350"
                    }
                    StyledText {
                        text: "30"
                        font.pixelSize: 14
                        font.family: Appearance.font.family.numbers
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                Grid {
                    anchors.verticalCenter: parent.verticalCenter
                    columns: 5
                    spacing: 3.5
                    Repeater {
                        model: 15
                        Rectangle {
                            required property int index
                            width: 4.5
                            height: 4.5
                            radius: 2.25
                            color: index === 8
                                ? Appearance.colors.colPrimary
                                : Qt.alpha(Appearance.colors.colOnLayer1, index < 2 ? 0.15 : 0.36)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: notesPreviewComp
        Item {
            Rectangle {
                anchors.centerIn: parent
                width: 34
                height: 38
                radius: 7
                color: "#f2be38"

                Column {
                    anchors.centerIn: parent
                    spacing: 4.5
                    Rectangle { width: 20; height: 2.6; radius: 1.3; color: "#2b2108" }
                    Rectangle { width: 20; height: 2.6; radius: 1.3; color: "#2b2108" }
                    Rectangle { width: 13; height: 2.6; radius: 1.3; color: "#2b2108" }
                }
            }
        }
    }

    Component {
        id: batteryPreviewComp
        Item {
            Column {
                anchors.centerIn: parent
                spacing: 1.5

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 8
                    height: 3
                    radius: 1.5
                    color: Qt.alpha("#66bb6a", 0.72)
                }

                Rectangle {
                    width: 22
                    height: 34
                    radius: 5
                    color: Qt.alpha("#66bb6a", 0.22)
                    border.width: 1.5
                    border.color: "#66bb6a"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 3
                        height: 22
                        radius: 3
                        color: "#57c95d"
                    }
                }
            }
        }
    }

    Component {
        id: visualizerPreviewComp
        Item {
            Row {
                id: eqRow
                anchors.centerIn: parent
                height: 38
                spacing: 4

                Repeater {
                    model: [0.32, 0.62, 0.88, 0.52, 0.96, 0.72, 0.84, 0.45, 0.28]
                    Rectangle {
                        required property real modelData
                        required property int index
                        width: 4.5
                        height: Math.round(8 + modelData * 28)
                        y: Math.round((38 - height) / 2)
                        radius: 2.25
                        color: index % 2 === 0
                            ? Appearance.colors.colPrimary
                            : Qt.alpha("#ab47bc", 0.88)
                    }
                }
            }
        }
    }

    Component {
        id: newsPreviewComp
        Rectangle {
            radius: 8
            color: Qt.alpha("#ffa726", 0.10)
            border.width: 1
            border.color: Qt.alpha("#ffa726", 0.22)

            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 22
                spacing: 5

                Rectangle {
                    width: 26
                    height: 11
                    radius: 5.5
                    color: Qt.alpha("#ffa726", 0.28)
                    StyledText {
                        anchors.centerIn: parent
                        text: "RSS"
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        color: "#ffb74d"
                    }
                }
                Rectangle { width: parent.width; height: 4; radius: 2; color: Qt.alpha(Appearance.colors.colOnLayer1, 0.65) }
                Rectangle { width: parent.width * 0.68; height: 3.5; radius: 1.75; color: Qt.alpha(Appearance.colors.colSubtext, 0.42) }
            }
        }
    }

    Component {
        id: worldClockPreviewComp
        Item {
            Column {
                id: wcCol
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 7
                anchors.rightMargin: 22
                spacing: 5

                Repeater {
                    model: [
                        { city: "TYO", time: "09:41", bright: true },
                        { city: "LON", time: "01:41", bright: false }
                    ]
                    Rectangle {
                        required property var modelData
                        width: Math.max(0, wcCol.width)
                        height: 18
                        radius: 6
                        color: Qt.alpha("#29b6f6", modelData.bright ? 0.18 : 0.08)
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            spacing: 6
                            StyledText {
                                text: modelData.city
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                                color: "#4fc3f7"
                            }
                            StyledText {
                                text: modelData.time
                                font.pixelSize: 9
                                font.family: Appearance.font.family.numbers
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: uptimePreviewComp
        Item {
            Column {
                anchors.centerIn: parent
                spacing: 6

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "14d 06h"
                    font.pixelSize: 12
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.DemiBold
                    color: "#4db6ac"
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2.5
                    Repeater {
                        model: 8
                        Rectangle {
                            required property int index
                            width: 6
                            height: 6
                            radius: 2
                            color: index < 6 ? "#26a69a" : Qt.alpha("#26a69a", 0.25)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: userCardPreviewComp
        Item {
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                spacing: 8

                Rectangle {
                    width: 30
                    height: 30
                    radius: 15
                    color: Qt.alpha("#7e57c2", 0.28)
                    border.width: 1
                    border.color: Qt.alpha("#9575cd", 0.5)
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "person"
                        iconSize: 17
                        color: "#b39ddb"
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: 8
                        height: 8
                        radius: 4
                        color: "#66bb6a"
                        border.width: 1.5
                        border.color: Appearance.colors.colLayer2
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Rectangle { width: 38; height: 4.5; radius: 2.25; color: Qt.alpha(Appearance.colors.colOnLayer1, 0.7) }
                    Rectangle { width: 26; height: 3.5; radius: 1.75; color: Qt.alpha("#9575cd", 0.65) }
                }
            }
        }
    }

    Component {
        id: customImagePreviewComp
        Item {
            Rectangle {
                anchors.centerIn: parent
                width: 58
                height: 40
                radius: 7
                color: Qt.alpha("#ec407a", 0.14)
                border.width: 1
                border.color: Qt.alpha("#ec407a", 0.36)
                clip: true

                Rectangle {
                    x: 11
                    y: 8
                    width: 8
                    height: 8
                    radius: 4
                    color: "#ffca28"
                }

                Rectangle {
                    x: 6
                    y: 23
                    width: 28
                    height: 28
                    radius: 4
                    rotation: 45
                    color: Qt.alpha("#ec407a", 0.45)
                }

                Rectangle {
                    x: 24
                    y: 19
                    width: 32
                    height: 32
                    radius: 4
                    rotation: 45
                    color: Qt.alpha("#ab47bc", 0.55)
                }
            }
        }
    }

    Component {
        id: converterPreviewComp
        Item {
            Row {
                anchors.centerIn: parent
                spacing: 5

                Rectangle {
                    width: 28
                    height: 24
                    radius: 5
                    color: Qt.alpha("#5c6bc0", 0.24)
                    border.width: 1
                    border.color: Qt.alpha("#5c6bc0", 0.45)
                    StyledText {
                        anchors.centerIn: parent
                        text: "PNG"
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        color: "#9fa8da"
                    }
                }

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "arrow_forward"
                    iconSize: 13
                    color: Appearance.colors.colSubtext
                }

                Rectangle {
                    width: 32
                    height: 24
                    radius: 5
                    color: Qt.alpha(Appearance.colors.colPrimary, 0.24)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.52)
                    StyledText {
                        anchors.centerIn: parent
                        text: "WEBP"
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

    Component {
        id: typographyPreviewComp
        Item {
            Row {
                anchors.centerIn: parent
                spacing: 7

                Rectangle {
                    width: 28
                    height: 34
                    radius: 6
                    color: Qt.alpha("#ff7043", 0.20)
                    border.width: 1
                    border.color: Qt.alpha("#ff7043", 0.42)
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "translate"
                        iconSize: 16
                        color: "#ff8a65"
                    }
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3.5
                    Rectangle { width: 2.5; height: 28; radius: 1.25; color: Qt.alpha(Appearance.colors.colOnLayer1, 0.65) }
                    Rectangle { width: 2.5; height: 20; radius: 1.25; color: Qt.alpha(Appearance.colors.colSubtext, 0.45) }
                    Rectangle { width: 2.5; height: 24; radius: 1.25; color: "#ff7043" }
                }
            }
        }
    }

    // ── Main 2-Tier Abyss Customization Dock ──
    AbyssCustomizationDock {
        id: dock
        anchors.fill: parent
        embeddedSurface: editControlsBar.hosted
        verticalPadding: editControlsBar.hosted ? 2 : 7
        horizontalPadding: editControlsBar.hosted ? 10 : 14
        trayHeight: editControlsBar.hosted ? 105 : 107
        contentPreferredWidth: dock.activeTab === "grid"
            ? Math.ceil(gridTrayRow.implicitWidth + 12)
            : (dock.activeTab === "power"
                ? Math.ceil(powerTrayRow.implicitWidth + 12)
                : (dock.activeTab === "custom"
                    ? Math.ceil(customTrayRow.implicitWidth + 12)
                    : Math.ceil(tileGalleryRow.implicitWidth + 12)))

        showUndo: false
        showRedo: false
        showCancel: false
        autoSwitchTab: false

        activeTab: "widgets"
        tabs: [
            {
                key: "widgets",
                label: editControlsBar.iconOnlyHeader ? "" : Translation.tr("Widgets"),
                icon: (editControlsBar.iconOnlyHeader || !editControlsBar.ultraCompactHeader) ? "widgets" : "",
                objectName: "widgetDockTabWidgets",
                tooltipText: Translation.tr("Browse all desktop widgets")
            },
            {
                key: "active",
                label: editControlsBar.iconOnlyHeader ? "" : Translation.tr("Active"),
                icon: (editControlsBar.iconOnlyHeader || !editControlsBar.ultraCompactHeader) ? "visibility" : "",
                badge: editControlsBar.compactHeader || editControlsBar.activeWidgetCount === 0
                    ? "" : String(editControlsBar.activeWidgetCount),
                objectName: "widgetDockTabActive",
                tooltipText: Translation.tr("Show currently active widgets on this display")
            },
            {
                key: "grid",
                label: editControlsBar.iconOnlyHeader ? "" : (editControlsBar.compactHeader ? Translation.tr("Grid") : Translation.tr("Grid & Style")),
                icon: (editControlsBar.iconOnlyHeader || !editControlsBar.ultraCompactHeader) ? "grid_on" : "",
                objectName: "widgetDockTabGrid",
                tooltipText: Translation.tr("Configure widget style, grid snap, cell size and positions")
            },
            {
                key: "power",
                label: editControlsBar.iconOnlyHeader ? "" : (editControlsBar.compactHeader ? Translation.tr("Power") : Translation.tr("Power & Displays")),
                icon: (editControlsBar.iconOnlyHeader || !editControlsBar.ultraCompactHeader) ? "bolt" : "",
                objectName: "widgetDockTabPower",
                tooltipText: Translation.tr("Configure widget displays and power-saving rules")
            },
            {
                key: "custom",
                label: editControlsBar.iconOnlyHeader ? "" : Translation.tr("Custom"),
                icon: (editControlsBar.iconOnlyHeader || !editControlsBar.ultraCompactHeader) ? "dashboard_customize" : "",
                badge: editControlsBar.compactHeader || editControlsBar.customWidgetCount === 0
                    ? "" : String(editControlsBar.customWidgetCount),
                objectName: "widgetDockTabCustom",
                tooltipText: Translation.tr("Create and manage custom widgets")
            }
        ]

        showSearch: editControlsBar.width >= 640 && (dock.activeTab === "widgets" || dock.activeTab === "active" || dock.activeTab === "custom")
        searchPlaceholder: Translation.tr("Search widgets...")
        searchObjectName: "widgetDockSearchInput"

        doneLabel: Translation.tr("Done")
        doneObjectName: "widgetDockDoneButton"

        onTabClicked: key => {
            if (dock.activeTab === key) {
                dock.trayExpanded = !dock.trayExpanded;
            } else {
                dock.activeTab = key;
                dock.trayExpanded = true;
            }
        }

        onDoneClicked: {
            editControlsBar.manager.shown = false;
            GlobalStates.setWidgetEditMode(false);
        }

        leadingControls: [
            RippleButton {
                id: collapseTrayBtn
                objectName: "widgetDockCollapseButton"
                visible: editControlsBar.width >= 480
                width: 30
                height: 30
                buttonRadius: Appearance.rounding.full
                colBackground: Qt.alpha(Appearance.colors.colLayer2, 0.55)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                downAction: () => {
                    dock.trayExpanded = !dock.trayExpanded;
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: dock.trayExpanded ? "keyboard_arrow_down" : "keyboard_arrow_up"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: dock.trayExpanded
                        ? Translation.tr("Collapse customization tray")
                        : Translation.tr("Expand customization tray")
                }
            }
        ]

        trailingControls: [
            // Snap quick-action toggle
            RippleButton {
                id: gridSnapBtn
                objectName: "widgetDockSnapButton"
                visible: editControlsBar.width >= 440
                width: 30
                height: 30
                buttonRadius: Appearance.rounding.full
                toggled: editControlsBar.gridSnapEnabled
                colBackground: Qt.alpha(Appearance.colors.colLayer2, 0.55)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.18)
                colBackgroundToggledHover: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.26)
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                downAction: () => {
                    Config.setNestedValue("background.widgets.editGrid.snap", !editControlsBar.gridSnapEnabled);
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "grid_3x3"
                    iconSize: 17
                    color: gridSnapBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Snap to grid") }
            },

            // Grid size cycle badge (16 / 32 / 48 / 64)
            RippleButton {
                id: gridSizeBtn
                objectName: "widgetDockGridSizeButton"
                visible: editControlsBar.width >= 520
                readonly property bool isCustomSize: editControlsBar.gridSizeValue !== 32
                padding: 0
                leftPadding: 0
                rightPadding: 0
                topPadding: 0
                bottomPadding: 0
                implicitWidth: Math.max(48, Math.ceil(gridSizeBtnRow.implicitWidth) + 16)
                width: implicitWidth
                implicitHeight: 30
                height: 30
                buttonRadius: Appearance.rounding.full
                colBackground: isCustomSize
                    ? CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
                    : Qt.alpha(Appearance.colors.colLayer2, 0.55)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                downAction: () => editControlsBar.cycleGridSize()
                contentItem: Item {
                    implicitWidth: gridSizeBtnRow.implicitWidth
                    implicitHeight: gridSizeBtnRow.implicitHeight
                    Row {
                        id: gridSizeBtnRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "grid_4x4"
                            iconSize: 14
                            verticalAlignment: Text.AlignVCenter
                            color: gridSizeBtn.isCustomSize ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(editControlsBar.gridSizeValue)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.numbers
                            font.weight: Font.DemiBold
                            verticalAlignment: Text.AlignVCenter
                            color: gridSizeBtn.isCustomSize ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Grid size: %1px — click to cycle").arg(editControlsBar.gridSizeValue)
                }
            }
        ]

        // ── Tier 2A: Widgets & Active Horizontal Tile Gallery ──
        Flickable {
            id: rail
            objectName: "desktopWidgetEditorRail"
            visible: dock.activeTab === "widgets" || dock.activeTab === "active"
            anchors.fill: parent
            contentWidth: Math.max(width, tileGalleryRow.implicitWidth + 8)
            contentHeight: height
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

            function scrollBy(delta: real): void {
                const maxX = Math.max(0, contentWidth - width);
                contentX = Math.max(0, Math.min(maxX, contentX + delta));
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const px = event.pixelDelta.x;
                    const py = event.pixelDelta.y;
                    if (px !== 0 || py !== 0) {
                        const pDelta = Math.abs(px) > Math.abs(py) ? -px : -py;
                        rail.scrollBy(pDelta);
                    } else {
                        const ax = event.angleDelta.x;
                        const ay = event.angleDelta.y;
                        const aDelta = Math.abs(ax) > Math.abs(ay) ? -ax : -ay;
                        rail.scrollBy(aDelta === 0 ? 0 : (aDelta / 120) * 168);
                    }
                    event.accepted = true;
                }
            }

            Row {
                id: tileGalleryRow
                x: 4
                height: rail.height
                spacing: 10

                Repeater {
                    model: editControlsBar.builtinWidgets
                    delegate: AbyssCustomizationTile {
                        id: builtinTile
                        required property var modelData
                        readonly property bool widgetEnabled: editControlsBar.isWidgetEnabled(modelData.key, modelData.defaultOn)
                        visible: editControlsBar.shouldShowWidgetInGallery(widgetEnabled, modelData.label, modelData.key + " " + modelData.tags)
                        y: Math.round((tileGalleryRow.height - height) / 2)
                        tileId: modelData.key
                        title: modelData.label
                        icon: modelData.icon
                        accentColor: modelData.accent
                        active: widgetEnabled
                        selected: editControlsBar.selectedWidgetKey === modelData.key
                        tileWidth: 132
                        previewHeight: 68
                        tooltipText: widgetEnabled
                            ? Translation.tr("%1 — active (click to hide)").arg(modelData.label)
                            : Translation.tr("Add %1 to desktop").arg(modelData.label)
                        onClicked: editControlsBar.toggleWidget(modelData.key, modelData.defaultOn)

                        WidgetMiniPreview {
                            kind: builtinTile.modelData.key
                        }
                    }
                }

                Repeater {
                    model: CustomWidgets.ready ? CustomWidgets.widgets : []
                    delegate: AbyssCustomizationTile {
                        id: customGalleryTile
                        required property var modelData
                        readonly property string layoutKey: "custom." + modelData.id
                        readonly property bool widgetEnabled: editControlsBar.isWidgetEnabled(layoutKey, false)
                        visible: editControlsBar.shouldShowWidgetInGallery(widgetEnabled, modelData.name, modelData.id + " custom")
                        y: Math.round((tileGalleryRow.height - height) / 2)
                        tileId: layoutKey
                        title: modelData.name || modelData.id
                        icon: modelData.icon || "extension"
                        active: widgetEnabled
                        selected: editControlsBar.selectedWidgetKey === layoutKey
                        tileWidth: 132
                        previewHeight: 68
                        tooltipText: widgetEnabled
                            ? Translation.tr("%1 — active (click to hide)").arg(modelData.name || modelData.id)
                            : Translation.tr("Add %1 to desktop").arg(modelData.name || modelData.id)
                        onClicked: editControlsBar.toggleWidget(layoutKey, false)
                    }
                }
            }

            // Empty state for Search or Empty Active filter
            Row {
                visible: editControlsBar.visibleGalleryCount === 0
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dock.searchText.trim().length > 0 ? "search_off" : "widgets"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dock.searchText.trim().length > 0
                        ? Translation.tr("No widgets match \"%1\"").arg(dock.searchText.trim())
                        : Translation.tr("No active widgets on this display — switch to Widgets to add some")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── Tier 2B: Grid & Snap Controls ──
        Flickable {
            id: gridTrayFlickable
            visible: dock.activeTab === "grid"
            anchors.fill: parent
            contentWidth: Math.max(width, gridTrayRow.implicitWidth + 8)
            contentHeight: height
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const ax = event.angleDelta.x;
                    const ay = event.angleDelta.y;
                    const d = Math.abs(ax) > Math.abs(ay) ? -ax : -ay;
                    const maxX = Math.max(0, gridTrayFlickable.contentWidth - gridTrayFlickable.width);
                    gridTrayFlickable.contentX = Math.max(0, Math.min(maxX, gridTrayFlickable.contentX + (d / 120) * 140));
                    event.accepted = true;
                }
            }

            Row {
                id: gridTrayRow
                x: 4
                height: gridTrayFlickable.height
                spacing: 12

                // Group 0: Widget Style (Panel vs Island)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: styleGroupCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: styleGroupCol
                        anchors.centerIn: parent
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Widget Style")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            spacing: 6
                            TrayActionChip {
                                objectName: "widgetDockStylePanelChip"
                                icon: "view_quilt"
                                label: Translation.tr("Panel")
                                activeState: {
                                    void Config.revision;
                                    return String(Config.getNestedValue("background.widgets.style", "panel")) === "panel";
                                }
                                tooltipText: Translation.tr("Use standard panel surface styling for widgets")
                                onClicked: Config.setNestedValue("background.widgets.style", "panel")
                            }
                            TrayActionChip {
                                objectName: "widgetDockStyleIslandChip"
                                icon: "islands"
                                label: Translation.tr("Island")
                                activeState: {
                                    void Config.revision;
                                    return String(Config.getNestedValue("background.widgets.style", "panel")) === "island";
                                }
                                tooltipText: Translation.tr("Use frosted island styling for widgets")
                                onClicked: Config.setNestedValue("background.widgets.style", "island")
                            }
                        }
                    }
                }

                // Group 1: Snap & Guides
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: snapGroupCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: snapGroupCol
                        anchors.centerIn: parent
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Snap & Guides")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            spacing: 6
                            TrayActionChip {
                                icon: editControlsBar.gridSnapEnabled ? "grid_on" : "grid_off"
                                label: editControlsBar.gridSnapEnabled
                                    ? Translation.tr("Snap On")
                                    : Translation.tr("Freeform")
                                activeState: editControlsBar.gridSnapEnabled
                                tooltipText: Translation.tr("Toggle magnetic grid snapping and alignment lattice")
                                onClicked: Config.setNestedValue("background.widgets.editGrid.snap", !editControlsBar.gridSnapEnabled)
                            }
                        }
                    }
                }

                // Group 2: Grid Cell Size Presets (16 / 32 / 48 / 64px)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: sizeGroupCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: sizeGroupCol
                        anchors.centerIn: parent
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Grid Cell Size & Guide Style")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            spacing: 6
                            Repeater {
                                model: [
                                    { size: 16, label: Translation.tr("16px Fine"), tip: Translation.tr("Fine 16px grid with guide lines") },
                                    { size: 32, label: Translation.tr("32px Dots"), tip: Translation.tr("Default 32px dot lattice") },
                                    { size: 48, label: Translation.tr("48px Wide"), tip: Translation.tr("Wide 48px grid with guide lines") },
                                    { size: 64, label: Translation.tr("64px Block"), tip: Translation.tr("Coarse 64px block grid with guide lines") }
                                ]
                                TrayActionChip {
                                    required property var modelData
                                    label: modelData.label
                                    activeState: editControlsBar.gridSizeValue === modelData.size
                                    tooltipText: modelData.tip
                                    onClicked: Config.setNestedValue("background.widgets.editGrid.size", modelData.size)
                                }
                            }
                        }
                    }
                }

                // Group 3: Fade With Windows
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: fadeGroupCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: fadeGroupCol
                        anchors.centerIn: parent
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Window Fade")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            spacing: 6
                            Repeater {
                                model: [
                                    { val: 0, label: Translation.tr("Always Full") },
                                    { val: 30, label: Translation.tr("Soft 30%") },
                                    { val: 60, label: Translation.tr("Dim 60%") }
                                ]
                                TrayActionChip {
                                    required property var modelData
                                    label: modelData.label
                                    activeState: editControlsBar.dynamicOpacityValue === modelData.val
                                    tooltipText: Translation.tr("Dim desktop widgets when workspace windows are open")
                                    onClicked: Config.setNestedValue("background.widgets.dynamicOpacity", modelData.val)
                                }
                            }
                        }
                    }
                }

                // Group 4: Reset Positions
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: resetGroupCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: resetGroupCol
                        anchors.centerIn: parent
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Positions")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            spacing: 6
                            TrayActionChip {
                                objectName: "widgetDockResetSelectedButton"
                                icon: "my_location"
                                label: Translation.tr("Reset Selected")
                                enabled: editControlsBar.selectedWidgetKey.length > 0
                                tooltipText: Translation.tr("Reset the selected widget back to its default position")
                                onClicked: editControlsBar.resetSelectedWidgetPosition()
                            }
                            TrayActionChip {
                                objectName: "widgetDockResetPositionsButton"
                                icon: "restart_alt"
                                label: Translation.tr("Reset Display")
                                enabled: editControlsBar.outputHasPositionOverrides
                                tooltipText: Translation.tr("Reset all widget positions on this display")
                                onClicked: editControlsBar.resetOutputPositions()
                            }
                        }
                    }
                }
            }
        }

        // ── Tier 2B2: Power & Displays ──
        Flickable {
            id: powerTrayFlickable
            visible: dock.activeTab === "power"
            anchors.fill: parent
            contentWidth: Math.max(width, powerTrayRow.implicitWidth + 8)
            contentHeight: height
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const ax = event.angleDelta.x;
                    const ay = event.angleDelta.y;
                    const d = Math.abs(ax) > Math.abs(ay) ? -ax : -ay;
                    const maxX = Math.max(0, powerTrayFlickable.contentWidth - powerTrayFlickable.width);
                    powerTrayFlickable.contentX = Math.max(0, Math.min(maxX, powerTrayFlickable.contentX + (d / 120) * 140));
                    event.accepted = true;
                }
            }

            Row {
                id: powerTrayRow
                x: 4
                height: powerTrayFlickable.height
                spacing: 12

                // Displays Card
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: displaysGroupCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: displaysGroupCol
                        anchors.centerIn: parent
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Displays")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            spacing: 6
                            TrayActionChip {
                                objectName: "widgetDockAllDisplaysChip"
                                icon: "monitor"
                                label: Translation.tr("All monitors")
                                activeState: {
                                    void Config.revision;
                                    const list = Config.getNestedValue("background.widgets.screenList", []);
                                    return !Array.isArray(list) || list.length === 0;
                                }
                                tooltipText: Translation.tr("Show widgets on all connected displays")
                                onClicked: Config.setNestedValue("background.widgets.screenList", [])
                            }
                            Repeater {
                                model: Quickshell.screens
                                delegate: TrayActionChip {
                                    required property var modelData
                                    readonly property string scrName: String(modelData?.name ?? "")
                                    icon: "desktop_windows"
                                    label: scrName
                                    activeState: {
                                        void Config.revision;
                                        const list = Config.getNestedValue("background.widgets.screenList", []);
                                        return Array.isArray(list) && list.indexOf(scrName) !== -1;
                                    }
                                    tooltipText: Translation.tr("Toggle widgets on %1").arg(scrName)
                                    onClicked: editControlsBar.toggleWidgetScreen(scrName)
                                }
                            }
                        }
                    }
                }

                // Power Saving Card
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: powerGroupCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: powerGroupCol
                        anchors.centerIn: parent
                        spacing: 8

                        Row {
                            spacing: 8
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Power Saving")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colSubtext
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18
                                width: statusBadgeText.implicitWidth + 12
                                radius: 9
                                color: WidgetPowerManager.widgetsActive
                                    ? CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.18)
                                    : CF.ColorUtils.applyAlpha(Appearance.colors.colError, 0.18)
                                StyledText {
                                    id: statusBadgeText
                                    anchors.centerIn: parent
                                    text: WidgetPowerManager.widgetsActive ? Translation.tr("Active") : Translation.tr("Paused")
                                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                    font.weight: Font.DemiBold
                                    color: WidgetPowerManager.widgetsActive ? Appearance.colors.colPrimary : Appearance.colors.colError
                                }
                            }
                        }

                        Row {
                            spacing: 6
                            TrayActionChip {
                                objectName: "widgetDockPowerEnableChip"
                                icon: "bolt"
                                label: Translation.tr("Enable")
                                activeState: {
                                    void Config.revision;
                                    return Boolean(Config.getNestedValue("background.widgets.powerSaving.enable", false));
                                }
                                tooltipText: Translation.tr("Automatically pause widget updates to save battery")
                                onClicked: Config.setNestedValue("background.widgets.powerSaving.enable",
                                    !Boolean(Config.getNestedValue("background.widgets.powerSaving.enable", false)))
                            }
                            TrayActionChip {
                                icon: "sports_esports"
                                label: Translation.tr("Game Mode")
                                activeState: {
                                    void Config.revision;
                                    return Boolean(Config.getNestedValue("background.widgets.powerSaving.pauseOnGameMode", true));
                                }
                                tooltipText: Translation.tr("Pause widgets during Game Mode")
                                onClicked: Config.setNestedValue("background.widgets.powerSaving.pauseOnGameMode",
                                    !Boolean(Config.getNestedValue("background.widgets.powerSaving.pauseOnGameMode", true)))
                            }
                            TrayActionChip {
                                icon: "fullscreen"
                                label: Translation.tr("Fullscreen")
                                activeState: {
                                    void Config.revision;
                                    return Boolean(Config.getNestedValue("background.widgets.powerSaving.pauseOnFullscreen", true));
                                }
                                tooltipText: Translation.tr("Pause widgets when a window is fullscreen")
                                onClicked: Config.setNestedValue("background.widgets.powerSaving.pauseOnFullscreen",
                                    !Boolean(Config.getNestedValue("background.widgets.powerSaving.pauseOnFullscreen", true)))
                            }
                            TrayActionChip {
                                icon: "web_asset"
                                label: Translation.tr("Windows Open")
                                activeState: {
                                    void Config.revision;
                                    return Boolean(Config.getNestedValue("background.widgets.powerSaving.pauseWhenWindowsPresent", false));
                                }
                                tooltipText: Translation.tr("Pause widgets when windows cover the desktop")
                                onClicked: Config.setNestedValue("background.widgets.powerSaving.pauseWhenWindowsPresent",
                                    !Boolean(Config.getNestedValue("background.widgets.powerSaving.pauseWhenWindowsPresent", false)))
                            }
                            TrayActionChip {
                                icon: "pause_circle"
                                label: Translation.tr("Paused Badge")
                                activeState: {
                                    void Config.revision;
                                    return Boolean(Config.getNestedValue("background.widgets.powerSaving.showPausedEffect", true));
                                }
                                tooltipText: Translation.tr("Show subtle dim indicator when widgets are paused")
                                onClicked: Config.setNestedValue("background.widgets.powerSaving.showPausedEffect",
                                    !Boolean(Config.getNestedValue("background.widgets.powerSaving.showPausedEffect", true)))
                            }
                        }
                    }
                }
            }
        }

        // ── Tier 2C: Custom Widgets & Manager Strip ──
        Flickable {
            id: customTrayFlickable
            visible: dock.activeTab === "custom"
            anchors.fill: parent
            contentWidth: Math.max(width, customTrayRow.implicitWidth + 8)
            contentHeight: height
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const ax = event.angleDelta.x;
                    const ay = event.angleDelta.y;
                    const d = Math.abs(ax) > Math.abs(ay) ? -ax : -ay;
                    const maxX = Math.max(0, customTrayFlickable.contentWidth - customTrayFlickable.width);
                    customTrayFlickable.contentX = Math.max(0, Math.min(maxX, customTrayFlickable.contentX + (d / 120) * 150));
                    event.accepted = true;
                }
            }

            Row {
                id: customTrayRow
                x: 4
                height: customTrayFlickable.height
                spacing: 12

                // Management Actions Card
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: customActionsCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: customActionsCol
                        anchors.centerIn: parent
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Custom QML Widgets")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            spacing: 6

                            TrayActionChip {
                                visible: !DesktopEditStage.stageEnabled || !editControlsBar.abyssMode
                                icon: "tune"
                                label: Boolean(editControlsBar.manager?.shown)
                                    ? Translation.tr("Hide Inspector")
                                    : Translation.tr("Open Inspector")
                                activeState: Boolean(editControlsBar.manager?.shown)
                                accentStyle: !Boolean(editControlsBar.manager?.shown)
                                tooltipText: Translation.tr("Open floating Widget Manager for per-widget settings")
                                onClicked: editControlsBar.manager.shown = !editControlsBar.manager.shown
                            }

                            TrayActionChip {
                                icon: "refresh"
                                label: Translation.tr("Reload")
                                tooltipText: Translation.tr("Rescan ~/.config/alis/widgets/ for custom QML widgets")
                                onClicked: CustomWidgets.reload()
                            }

                            TrayActionChip {
                                icon: "folder_open"
                                label: Translation.tr("Folder")
                                tooltipText: Translation.tr("Open ~/.config/alis/widgets/ directory")
                                onClicked: CustomWidgets.openWidgetDir("")
                            }

                            TrayActionChip {
                                visible: !editControlsBar.exampleWidgetInstalled
                                icon: "download"
                                label: Translation.tr("Install Example")
                                accentStyle: true
                                tooltipText: Translation.tr("Install starter custom widget into ~/.config/alis/widgets/")
                                onClicked: {
                                    CustomWidgets.installExample();
                                    CustomWidgets.reload();
                                }
                            }
                        }
                    }
                }

                // Create Custom Widget Card
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: customCreateCol.implicitWidth + 24
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(editControlsBar.abyssMode ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Column {
                        id: customCreateCol
                        anchors.centerIn: parent
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Create Custom Widget")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            spacing: 6

                            MaterialTextField {
                                id: customWidgetNameField
                                objectName: "widgetDockCustomCreateInput"
                                width: Math.round(140 * Appearance.fontSizeScale)
                                height: 32
                                enableSettingsSearch: false
                                placeholderText: Translation.tr("Widget name...")
                                text: editControlsBar.newCustomWidgetName
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                onTextChanged: {
                                    if (editControlsBar.newCustomWidgetName !== text)
                                        editControlsBar.newCustomWidgetName = text;
                                }
                                onAccepted: {
                                    const name = editControlsBar.newCustomWidgetName.trim();
                                    if (name.length > 0) {
                                        CustomWidgets.create(name);
                                        CustomWidgets.reload();
                                        editControlsBar.newCustomWidgetName = "";
                                    }
                                }
                            }

                            TrayActionChip {
                                objectName: "widgetDockCustomCreateButton"
                                icon: "add"
                                label: Translation.tr("Create")
                                accentStyle: true
                                enabled: editControlsBar.newCustomWidgetName.trim().length > 0
                                tooltipText: Translation.tr("Create editable custom QML widget template")
                                onClicked: {
                                    const name = editControlsBar.newCustomWidgetName.trim();
                                    if (name.length > 0) {
                                        CustomWidgets.create(name);
                                        CustomWidgets.reload();
                                        editControlsBar.newCustomWidgetName = "";
                                    }
                                }
                            }
                        }
                    }
                }

                // Installed Custom Widget Tiles
                Repeater {
                    model: CustomWidgets.ready ? CustomWidgets.widgets : []
                    delegate: AbyssCustomizationTile {
                        id: customTabTile
                        required property var modelData
                        readonly property string layoutKey: "custom." + modelData.id
                        readonly property bool widgetEnabled: editControlsBar.isWidgetEnabled(layoutKey, false)
                        visible: editControlsBar.matchesSearch(modelData.name, modelData.id + " custom")
                        y: Math.round((customTrayRow.height - height) / 2)
                        tileId: layoutKey
                        title: modelData.name || modelData.id
                        icon: modelData.icon || "extension"
                        active: widgetEnabled
                        selected: editControlsBar.selectedWidgetKey === layoutKey
                        tileWidth: 132
                        previewHeight: 68
                        tooltipText: widgetEnabled
                            ? Translation.tr("%1 — active (click to hide)").arg(modelData.name || modelData.id)
                            : Translation.tr("Add %1 to desktop").arg(modelData.name || modelData.id)
                        onClicked: editControlsBar.toggleWidget(layoutKey, false)
                    }
                }

                // Hint card when no custom widgets exist yet
                Rectangle {
                    visible: editControlsBar.customWidgetCount === 0
                    anchors.verticalCenter: parent.verticalCenter
                    height: 82
                    width: emptyCustomCol.implicitWidth + 28
                    radius: Math.min(14, Appearance.rounding.normal)
                    color: Qt.alpha(Appearance.colors.colLayer2, 0.36)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.18)

                    Column {
                        id: emptyCustomCol
                        anchors.centerIn: parent
                        spacing: 4

                        StyledText {
                            text: Translation.tr("No custom widgets installed yet")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: "~/.config/alis/widgets/"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
