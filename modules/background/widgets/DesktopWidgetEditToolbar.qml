pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import "DesktopWidgetEditorPlacement.js" as Placement

// Reparent the original controls into the existing Abyss field host. Their
// creation context, manager and widget callbacks remain owned by Background.
Item {
    id: editControlsBar
    required property var windowContext
    required property var safeBounds
    required property var manager
    required property Item fallbackParent
    property var obstacles: []
    property var abyssHost: null
    readonly property string outputName: windowContext?.screenName ?? ""
    readonly property bool abyssMode: (Config.options?.panelFamily ?? "abyss") === "abyss"
    readonly property bool hosted: abyssMode && abyssHost !== null
    readonly property var placement: Placement.choose(
        hosted ? abyssHost.editorWorkArea : {
            left:safeBounds.safeLeft, top:safeBounds.safeTop,
            right:safeBounds.safeRight, bottom:safeBounds.safeBottom},
        obstacles, GlobalStates.selectedDesktopWidget)
    readonly property bool vertical: hosted && ["left","right"].includes(placement.edge)
    readonly property real railExtent: vertical ? height : width
    property string registeredOutput: ""
    function registerOutput(): void {
        if (registeredOutput === outputName) return
        GlobalStates.unregisterDesktopWidgetEditor(registeredOutput,editControlsBar)
        registeredOutput = outputName
        GlobalStates.registerDesktopWidgetEditor(registeredOutput,editControlsBar)
    }
    onOutputNameChanged: registerOutput()
    Component.onCompleted: registerOutput()
    Component.onDestruction: GlobalStates.unregisterDesktopWidgetEditor(registeredOutput,editControlsBar)

    parent: hosted ? abyssHost.contentParent : fallbackParent
    x: hosted ? 0 : Math.round(safeBounds.safeLeft+(safeBounds.safeWidth-width)/2)
    y: hosted ? 0 : Math.round(Math.max(safeBounds.safeTop,safeBounds.safeBottom-height-12))
    width: hosted ? abyssHost.targetRecord.content.width : Math.min(safeBounds.safeWidth,editBarRow.implicitWidth+24)
    height: hosted ? abyssHost.targetRecord.content.height : 52
    visible: hosted ? abyssHost.visualResident : GlobalStates.widgetEditMode
    enabled: GlobalStates.widgetEditMode

    Toolbar {
        visible: !editControlsBar.hosted
        anchors.fill: parent
        padding: 6
        spacing: 4
        screenX: editControlsBar.x
        screenY: editControlsBar.y
    }
    MouseArea { anchors.fill:parent; z:-1; acceptedButtons:Qt.AllButtons }
    Flickable {
        id: rail
        objectName: "desktopWidgetEditorRail"
        contentWidth: Math.max(width,editBarRow.implicitWidth+16)
        contentHeight: 52
        clip: true
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        width: editControlsBar.railExtent
        height: 52
        x: editControlsBar.vertical ? editControlsBar.width : 0
        y: editControlsBar.vertical ? 0 : (editControlsBar.height-height)/2
        transform: Rotation { origin.x:0;origin.y:0;angle:editControlsBar.vertical ? 90 : 0 }
        Row {
            id: editBarRow
            anchors.centerIn: parent
            spacing: 4

            // Grid snap toggle
            RippleButton {
                id: gridSnapBtn
                width: 36; height: 36
                buttonRadius: Appearance.rounding.full
                toggled: Config.getNestedValue("background.widgets.editGrid.snap", true)
                colBackground: "transparent"
                colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.08)
                colBackgroundToggled: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
                colBackgroundToggledHover: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.24)
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                downAction: () => {
                    const current = Config.getNestedValue("background.widgets.editGrid.snap", true);
                    Config.setNestedValue("background.widgets.editGrid.snap", !current);
                }
                contentItem: MaterialSymbol {
                    rotation: editControlsBar.vertical ? -90 : 0
                    anchors.centerIn: parent
                    text: "grid_3x3"
                    iconSize: 20
                    color: gridSnapBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                }
                StyledToolTip { text: Translation.tr("Snap to grid") }
            }

            // Grid size cycle
            RippleButton {
                id: gridSizeBtn
                readonly property int _gridSize: Config.getNestedValue("background.widgets.editGrid.size", 32)
                readonly property bool _isCustom: _gridSize !== 32
                width: editControlsBar.vertical ? 36 : gridSizeBtnRow.implicitWidth + 12; height: 36
                buttonRadius: Appearance.rounding.full
                colBackground: _isCustom ? CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.10) : "transparent"
                colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.08)
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                downAction: () => {
                    const sizes = [16, 32, 48, 64];
                    const current = gridSizeBtn._gridSize;
                    const idx = sizes.indexOf(current);
                    const next = sizes[(idx + 1) % sizes.length];
                    Config.setNestedValue("background.widgets.editGrid.size", next);
                }
                contentItem: Row {
                    id: gridSizeBtnRow
                    rotation: editControlsBar.vertical ? -90 : 0
                    anchors.centerIn: parent
                    spacing: 2
                    MaterialSymbol {
                        text: "grid_4x4"
                        iconSize: 14
                        color: gridSizeBtn._isCustom ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        text: gridSizeBtn._gridSize + ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        font.weight: Font.Medium
                        color: gridSizeBtn._isCustom ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                StyledToolTip { text: Translation.tr("Grid size: %1px — click to cycle").arg(gridSizeBtn._gridSize) }
            }

            // Separator
            Rectangle {
                width: 1; height: 24
                anchors.verticalCenter: parent.verticalCenter
                color: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
            }

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                rotation: editControlsBar.vertical ? -90 : 0
                text: "widgets"
                iconSize: 16
                color: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.62)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !editControlsBar.vertical && (editControlsBar.hosted ? editControlsBar.width >= 760 : safeBounds.safeWidth >= 900)
                text: Translation.tr("Widgets")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.72)
            }

            RippleButton {
                width: 26; height: 36
                enabled: widgetToggleRail.contentX > 1
                opacity: enabled ? 1 : 0.28
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.08)
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                releaseAction: () => widgetToggleRail.scrollBy(-144)
                cancelAction: () => {}
                contentItem: MaterialSymbol {
                    rotation: editControlsBar.vertical ? -90 : 0
                    anchors.centerIn: parent
                    text: editControlsBar.vertical ? "expand_less" : "chevron_left"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip { text: Translation.tr("Previous widgets") }
            }

            Flickable {
                id: widgetToggleRail
                width: Math.max(72, Math.min(420,
                    (editControlsBar.hosted
                    ? editControlsBar.railExtent - (editControlsBar.vertical ? 300 : editControlsBar.width >= 860 ? 485 : editControlsBar.width >= 760 ? 395 : 340)
                    : safeBounds.safeWidth - 530),
                    widgetToggleRow.implicitWidth))
                height: 36
                contentWidth: widgetToggleRow.implicitWidth
                contentHeight: height
                clip: true
                interactive: contentWidth > width
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick

                function scrollBy(delta: real): void {
                    const maxX = Math.max(0, contentWidth - width)
                    contentX = Math.max(0, Math.min(maxX, contentX + delta))
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const horizontal = event.angleDelta.x
                        const vertical = event.angleDelta.y
                        const delta = Math.abs(horizontal) > Math.abs(vertical)
                            ? -horizontal : -vertical
                        widgetToggleRail.scrollBy(delta === 0 ? 0
                            : (delta > 0 ? 120 : -120))
                        event.accepted = true
                    }
                }

                Row {
                    id: widgetToggleRow
                    spacing: 2

                    Repeater {
                model: [
                    { key: "weather", icon: "cloud", label: "Weather", defaultOn: false },
                    { key: "customImage", icon: "add_photo_alternate", label: "Custom Image", defaultOn: false },
                    { key: "imageConverter", icon: "transform", label: "Image Converter", defaultOn: false },
                    { key: "clock", icon: "schedule", label: "Clock", defaultOn: true },
                    { key: "mediaControls", icon: "album", label: "Media", defaultOn: false },
                    { key: "japaneseTypography", icon: "translate", label: "Japanese Typography", defaultOn: false },
                    { key: "visualizer", icon: "graphic_eq", label: "Visualizer", defaultOn: false },
                    { key: "systemMonitor", icon: "monitor_heart", label: "System Monitor", defaultOn: false },
                    { key: "battery", icon: "battery_full", label: "Battery", defaultOn: false },
                    { key: "notes", icon: "sticky_note_2", label: "Notes", defaultOn: false },
                    { key: "calendarUpcoming", icon: "event", label: "Upcoming Events", defaultOn: false },
                    { key: "uptime", icon: "avg_pace", label: "System Uptime", defaultOn: false },
                    { key: "newsTicker", icon: "newspaper", label: "News Ticker", defaultOn: false },
                    { key: "worldClock", icon: "public", label: "World Clock", defaultOn: false },
                    { key: "userCard", icon: "account_circle", label: "User Card", defaultOn: false }
                ]
                RippleButton {
                    id: quickWidgetButton
                    required property var modelData
                    // Repeater delegates can outlive their window's QML context during teardown.
                    readonly property bool widgetEnabled: windowContext?._widgetEnabled(modelData.key, modelData.defaultOn) ?? false
                    width: 36; height: 36
                    buttonRadius: Appearance.rounding.full
                    toggled: widgetEnabled
                    colBackground: "transparent"
                    colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.08)
                    colBackgroundToggled: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
                    colBackgroundToggledHover: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.24)
                    colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                    releaseAction: () => DesktopWidgetLayout.setGloballyEnabled(
                        quickWidgetButton.modelData.key,
                        !quickWidgetButton.widgetEnabled)
                    cancelAction: () => {}
                    contentItem: MaterialSymbol {
                    rotation: editControlsBar.vertical ? -90 : 0
                        anchors.centerIn: parent
                        text: quickWidgetButton.modelData.icon
                        iconSize: 18
                        color: quickWidgetButton.toggled ? Appearance.colors.colPrimary : CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.5)
                    }
                    StyledToolTip { text: quickWidgetButton.modelData.label }
                }
            }

            // Custom widget toggles
            Repeater {
                model: CustomWidgets.ready ? CustomWidgets.widgets : []
                RippleButton {
                    id: customWidgetButton
                    required property var modelData
                    readonly property bool widgetEnabled: DesktopWidgetLayout.enabled(
                        windowContext.screenName, "custom." + modelData.id,
                        Config.getNestedValue("background.widgets.custom." + modelData.id + ".enable", false))
                    width: 36; height: 36
                    buttonRadius: Appearance.rounding.full
                    toggled: widgetEnabled
                    colBackground: "transparent"
                    colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.08)
                    colBackgroundToggled: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
                    colBackgroundToggledHover: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.24)
                    colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                    releaseAction: () => DesktopWidgetLayout.setGloballyEnabled(
                        "custom." + customWidgetButton.modelData.id,
                        !customWidgetButton.widgetEnabled)
                    cancelAction: () => {}
                    contentItem: MaterialSymbol {
                    rotation: editControlsBar.vertical ? -90 : 0
                        anchors.centerIn: parent
                        text: customWidgetButton.modelData.icon || "widgets"
                        iconSize: 18
                        color: customWidgetButton.toggled ? Appearance.colors.colPrimary : CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.5)
                    }
                    StyledToolTip { text: customWidgetButton.modelData.name }
                }
            }
                }
            }

            RippleButton {
                width: 26; height: 36
                enabled: widgetToggleRail.contentX
                    < Math.max(0, widgetToggleRail.contentWidth - widgetToggleRail.width) - 1
                opacity: enabled ? 1 : 0.28
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.08)
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                releaseAction: () => widgetToggleRail.scrollBy(144)
                cancelAction: () => {}
                contentItem: MaterialSymbol {
                    rotation: editControlsBar.vertical ? -90 : 0
                    anchors.centerIn: parent
                    text: editControlsBar.vertical ? "expand_more" : "chevron_right"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip { text: Translation.tr("More widgets") }
            }

            // Separator
            Rectangle {
                width: 1; height: 24
                anchors.verticalCenter: parent.verticalCenter
                color: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
            }

            // Toggle the richer widget manager. Keep a visible
            // label here: this is the primary navigation path,
            // not an ambiguous add button.
            RippleButton {
                id: manageWidgetsButton
                width: editControlsBar.vertical ? 36 : manageWidgetsContent.implicitWidth + 16
                height: 36
                buttonRadius: Appearance.rounding.full
                toggled: manager.shown
                colBackground: "transparent"
                colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.08)
                colBackgroundToggled: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
                colBackgroundToggledHover: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.24)
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                releaseAction: () => { manager.shown = !manager.shown }
                cancelAction: () => {}
                contentItem: Row {
                    id: manageWidgetsContent
                    rotation: editControlsBar.vertical ? -90 : 0
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: "tune"
                        iconSize: 17
                        color: manageWidgetsButton.toggled
                            ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        visible: !editControlsBar.vertical && (editControlsBar.hosted ? editControlsBar.width >= 860 : safeBounds.safeWidth >= 1000)
                        text: Translation.tr("Manage widgets")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: manageWidgetsButton.toggled
                            ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                StyledToolTip { text: Translation.tr("Search, filter, lock and configure widgets") }
            }

            // Open full settings
            RippleButton {
                width: 36; height: 36
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.08)
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                downAction: () => {
                    if (Config.options?.settingsUi?.overlayMode !== false) {
                        GlobalStates.settingsOverlayRequestedPage = 14
                        GlobalStates.settingsOverlayOpen = true
                    } else {
                        Quickshell.execDetached(["/usr/bin/env", "QS_SETTINGS_PAGE=14", Quickshell.shellPath("scripts/alis"), "settings-window"])
                    }
                }
                contentItem: MaterialSymbol {
                    rotation: editControlsBar.vertical ? -90 : 0
                    anchors.centerIn: parent
                    text: "settings"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip { text: Translation.tr("Widget settings") }
            }

            // Separator
            Rectangle {
                width: 1; height: 24
                anchors.verticalCenter: parent.verticalCenter
                color: CF.ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
            }

            // Exit edit mode
            RippleButton {
                width: 36; height: 36
                buttonRadius: Appearance.rounding.full
                colBackground: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12)
                colBackgroundHover: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.20)
                colRipple: CF.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.24)
                downAction: () => { manager.shown = false; GlobalStates.setWidgetEditMode(false) }
                contentItem: MaterialSymbol {
                    rotation: editControlsBar.vertical ? -90 : 0
                    anchors.centerIn: parent
                    text: "check"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }
                StyledToolTip { text: Translation.tr("Done editing") }
            }
        }
    }
}
