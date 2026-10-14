import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: root
    property bool borderless: Config.options?.bar?.borderless ?? false
    property bool vertical: false
    property bool compactRequested: false
    property bool pinnedExpanded: false
    // Abyss owns the connected Utilities popup; other families keep the shared
    // Quick Actions implementation without gaining a new popup route.
    property bool showUtilitiesLauncher: false
    signal utilitiesRequested()
    signal utilitiesHoverChanged(bool hovered)
    readonly property color neutralIconColor: Appearance.colors.colOnLayer2
    readonly property color dangerIconColor: Appearance.colors.colError
    readonly property bool hasUrgentState: RecorderStatus.isRecording
        || Privacy.micActive
        || (Audio?.micBeingAccessed ?? false)
        || (Persistent.states.screenCast.active ?? false)
    readonly property bool inlineExpanded: !root.compactRequested
        || inlineHover.hovered || root.pinnedExpanded
    readonly property real expandedMainAxisLength: root.vertical
        ? controlsLayout.implicitHeight : controlsLayout.implicitWidth
    readonly property real compactMainAxisLength: root.vertical
        ? compactTrigger.implicitHeight : compactTrigger.implicitWidth
    readonly property var defaultUtilityOrder: [
        "screenSnip","screenRecord","colorPicker","notepad","keyboard",
        "keyboardLayout","mic","screenCast","darkMode","performance","utilities"
    ]
    readonly property var utilityOrder: {
        const configured = Config.options?.bar?.utilButtons?.order ?? []
        const result = []
        for (const id of configured) {
            if (root.defaultUtilityOrder.includes(id) && !result.includes(id))
                result.push(id)
        }
        for (const id of root.defaultUtilityOrder)
            if (!result.includes(id)) result.push(id)
        return result
    }
    function utilityActive(id): bool {
        switch (id) {
        case "screenSnip": return Config.options?.bar?.utilButtons?.showScreenSnip ?? true
        case "screenRecord": return Config.options?.bar?.utilButtons?.showScreenRecord ?? false
        case "colorPicker": return Config.options?.bar?.utilButtons?.showColorPicker ?? false
        case "notepad": return Config.options?.bar?.utilButtons?.showNotepad ?? true
        case "keyboard": return Config.options?.bar?.utilButtons?.showKeyboardToggle ?? true
        case "keyboardLayout": return (Config.options?.bar?.utilButtons?.showKeyboardLayoutSwitch ?? false)
            && CompositorService.isNiri && NiriService.hasMultipleKeyboardLayouts
        case "mic": return (Config.options?.bar?.utilButtons?.showMicToggle ?? false)
            || Privacy.micActive || (Audio?.micBeingAccessed ?? false)
        case "screenCast": return (Config.options?.bar?.utilButtons?.showScreenCast ?? false)
            && CompositorService.isNiri
        case "darkMode": return Config.options?.bar?.utilButtons?.showDarkModeToggle ?? true
        case "performance": return Config.options?.bar?.utilButtons?.showPerformanceProfileToggle ?? false
        case "utilities": return root.showUtilitiesLauncher
        default: return false
        }
    }
    readonly property int visibleUtilityCount:
        root.utilityOrder.filter(id => root.utilityActive(id)).length
    function utilityIndex(id): int {
        return Math.max(0,root.utilityOrder.filter(
            candidate => root.utilityActive(candidate)).indexOf(id))
    }

    // Compact Utilities stays inside the Bar. Revealer animates the main axis
    // in-place instead of opening a popup/native surface.
    implicitWidth: inlineLayout.implicitWidth
    implicitHeight: inlineLayout.implicitHeight

    onCompactRequestedChanged: {
        if (!compactRequested)
            pinnedExpanded = false
    }

    HoverHandler {
        id: inlineHover
    }

    GridLayout {
        id: inlineLayout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        columnSpacing: root.vertical ? 0 : 4 * Appearance.sizes.barModuleScale
        rowSpacing: root.vertical ? 4 * Appearance.sizes.barModuleScale : 0

        CircleUtilButton {
            id: compactTrigger
            visible: root.compactRequested && root.expandedMainAxisLength > 0
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Accessible.name: root.pinnedExpanded
                ? Translation.tr("Collapse utility buttons")
                : Translation.tr("Expand utility buttons")
            onClicked: root.pinnedExpanded = !root.pinnedExpanded

            Item {
                anchors.fill: parent

                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    fill: root.inlineExpanded ? 1 : 0
                    text: "settings"
                    iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                    color: root.hasUrgentState
                        ? root.dangerIconColor : root.neutralIconColor
                }

                Rectangle {
                    visible: root.hasUrgentState
                    width: 6 * Appearance.sizes.barModuleScale
                    height: 6 * Appearance.sizes.barModuleScale
                    radius: 3 * Appearance.sizes.barModuleScale
                    color: root.dangerIconColor
                    anchors {
                        top: parent.top
                        right: parent.right
                    }
                }
            }
        }

        Revealer {
            id: controlsRevealer
            vertical: root.vertical
            reveal: root.inlineExpanded
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

            GridLayout {
                id: controlsLayout

                columns: root.vertical ? 1 : Math.max(1, root.visibleUtilityCount)
                columnSpacing: root.vertical ? 0 : 4 * Appearance.sizes.barModuleScale
                rowSpacing: root.vertical ? 4 * Appearance.sizes.barModuleScale : 0

        Loader {
            active: root.utilityActive("screenSnip")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("screenSnip") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("screenSnip")
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: Translation.tr("Take screenshot")
                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "screenshot"])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1
                    text: "screenshot_region"
                    iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                    color: root.neutralIconColor
                }
            }
        }

        Loader {
            active: root.utilityActive("screenRecord")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("screenRecord") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("screenRecord")
            sourceComponent: Item {
                id: recordButtonWrapper
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: screenRecordButton.implicitWidth
                implicitHeight: screenRecordButton.implicitHeight

                property bool isRecording: RecorderStatus.isRecording

                CircleUtilButton {
                    id: screenRecordButton
                    anchors.fill: parent
                    Accessible.name: recordButtonWrapper.isRecording
                        ? Translation.tr("Stop screen recording")
                        : Translation.tr("Start screen recording")

                    onClicked: {
                        const args = [Directories.recordScriptPath]
                        if (recordButtonWrapper.isRecording)
                            args.push("--stop")
                        else
                            args.push("--fullscreen", "--sound")
                        Quickshell.execDetached(args)
                        RecorderStatus.scheduleQuickCheck()
                    }

                    Item {
                        anchors.fill: parent

                        MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Qt.AlignHCenter
                            fill: 1
                            text: "videocam"
                            iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                            color: recordButtonWrapper.isRecording
                                ? root.dangerIconColor
                                : root.neutralIconColor
                        }

                        // Pulsating indicator dot when recording
                        Rectangle {
                            scale: recordButtonWrapper.isRecording ? 1 : 0
                            visible: scale > 0
                            width: 6 * Appearance.sizes.barModuleScale
                            height: 6 * Appearance.sizes.barModuleScale
                            radius: 3 * Appearance.sizes.barModuleScale
                            color: root.dangerIconColor
                            anchors {
                                top: parent.top
                                right: parent.right
                            }

                            Behavior on scale {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }

                            SequentialAnimation on opacity {
                                running: recordButtonWrapper.isRecording && root.visible
                                    && (root.QsWindow.window?.visible ?? true)
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: Appearance.animation.elementMove.duration * 2 }
                                NumberAnimation { to: 1.0; duration: Appearance.animation.elementMove.duration * 2 }
                            }
                        }
                    }
                }
            }
        }

        Loader {
            active: root.utilityActive("colorPicker")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("colorPicker") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("colorPicker")
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: Translation.tr("Pick color")
                onClicked: ShellExec.execDetachedArgs(["/usr/bin/hyprpicker", "-a"], "Pick color")
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1
                    text: "colorize"
                    iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                    color: root.neutralIconColor
                }
            }
        }

        Loader {
            active: root.utilityActive("notepad")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("notepad") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("notepad")
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: Translation.tr("Open notepad")
                onClicked: {
                    GlobalStates.sidebarRightRequestedWidget = "notepad"
                    GlobalStates.openSidebarRight(root.QsWindow.window?.screen?.name ?? "")
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: "edit_note"
                    iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                    color: root.neutralIconColor
                }
            }
        }

        Loader {
            active: root.utilityActive("keyboard")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("keyboard") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("keyboard")
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: Translation.tr("Toggle on-screen keyboard")
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: "keyboard"
                    iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                    color: root.neutralIconColor
                }
            }
        }

        // Keyboard layout switch (Niri only)
        Loader {
            active: root.utilityActive("keyboardLayout")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("keyboardLayout") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("keyboardLayout")
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: Translation.tr("Switch keyboard layout")
                onClicked: NiriService.switchLayout()
                Item {
                    anchors.fill: parent
                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Qt.AlignHCenter
                        fill: 0
                        text: "language"
                        iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                        color: root.neutralIconColor
                    }
                }
            }
        }

        Loader {
            readonly property bool micInUse: Privacy.micActive || (Audio?.micBeingAccessed ?? false)
            active: root.utilityActive("mic")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("mic") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("mic")
            sourceComponent: CircleUtilButton {
                id: micButton
                Layout.alignment: Qt.AlignVCenter

                readonly property bool isMuted: Audio.micMuted
                readonly property bool isInUse: (Privacy.micActive || (Audio?.micBeingAccessed ?? false))

                Accessible.name: micButton.isMuted
                    ? Translation.tr("Unmute microphone")
                    : Translation.tr("Mute microphone")
                onClicked: Audio.toggleMicMute()

                Item {
                    anchors.fill: parent

                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Qt.AlignHCenter
                        fill: micButton.isInUse ? 1 : 0
                        animateFill: true
                        text: micButton.isMuted ? "mic_off" : "mic"
                        iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                        color: micButton.isInUse && !micButton.isMuted
                            ? root.dangerIconColor
                            : root.neutralIconColor
                    }

                    Rectangle {
                        scale: micButton.isInUse && !micButton.isMuted ? 1 : 0
                        visible: scale > 0
                        width: 6 * Appearance.sizes.barModuleScale
                        height: 6 * Appearance.sizes.barModuleScale
                        radius: 3 * Appearance.sizes.barModuleScale
                        color: root.dangerIconColor
                        anchors { top: parent.top; right: parent.right }

                        Behavior on scale {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        SequentialAnimation on opacity {
                            running: micButton.isInUse && !micButton.isMuted && root.visible
                                && (root.QsWindow.window?.visible ?? true)
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: Appearance.animation.elementMove.duration * 2 }
                            NumberAnimation { to: 1.0; duration: Appearance.animation.elementMove.duration * 2 }
                        }
                    }
                }
            }
        }

        // Screen casting toggle (PR #29 by levpr1c)
        // Toggles Niri dynamic casting to configured output
        Loader {
            active: root.utilityActive("screenCast")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("screenCast") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("screenCast")
            sourceComponent: CircleUtilButton {
                id: screenCastButton
                Layout.alignment: Qt.AlignVCenter

                readonly property bool isCasting: Persistent.states.screenCast.active

                Accessible.name: screenCastButton.isCasting
                    ? Translation.tr("Stop screen casting")
                    : Translation.tr("Start screen casting")
                onClicked: {
                    const output = Config.options?.bar?.utilButtons?.screenCastOutput ?? "HDMI-A-1"

                    if (isCasting) {
                        Quickshell.execDetached(["niri", "msg", "action", "clear-dynamic-cast-target"])
                        Persistent.states.screenCast.active = false
                    } else {
                        Quickshell.execDetached(["niri", "msg", "action", "set-dynamic-cast-monitor", output])
                        Persistent.states.screenCast.active = true
                    }
                }

                Item {
                    anchors.fill: parent

                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Qt.AlignHCenter
                        fill: screenCastButton.isCasting ? 1 : 0
                        animateFill: true
                        text: "cast"
                        iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                        color: screenCastButton.isCasting
                            ? root.dangerIconColor
                            : root.neutralIconColor
                    }

                    Rectangle {
                        scale: screenCastButton.isCasting ? 1 : 0
                        visible: scale > 0
                        width: 6 * Appearance.sizes.barModuleScale
                        height: 6 * Appearance.sizes.barModuleScale
                        radius: 3 * Appearance.sizes.barModuleScale
                        color: root.dangerIconColor
                        anchors {
                            top: parent.top
                            right: parent.right
                        }

                        Behavior on scale {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        SequentialAnimation on opacity {
                            running: screenCastButton.isCasting && root.visible
                                && (root.QsWindow.window?.visible ?? true)
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.4; duration: Appearance.animation.elementMove.duration * 2 }
                            NumberAnimation { to: 1.0; duration: Appearance.animation.elementMove.duration * 2 }
                        }
                    }
                }
            }
        }

        Loader {
            active: root.utilityActive("darkMode")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("darkMode") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("darkMode")
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: Appearance.m3colors.darkmode
                    ? Translation.tr("Switch to light mode")
                    : Translation.tr("Switch to dark mode")
                onClicked: event => {
                    MaterialThemeLoader.setDarkMode(!Appearance.m3colors.darkmode)
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
                    iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                    color: root.neutralIconColor
                }
            }
        }

        Loader {
            active: root.utilityActive("performance")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("performance") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("performance")
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: Translation.tr("Change power profile")
                onClicked: event => {
                    if (PowerProfiles.hasPerformanceProfile) {
                        switch(PowerProfiles.profile) {
                            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced
                            break;
                            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance
                            break;
                            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver
                            break;
                        }
                    } else {
                        PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                    }
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: switch(PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: return "energy_savings_leaf"
                        case PowerProfile.Balanced: return "settings_slow_motion"
                        case PowerProfile.Performance: return "local_fire_department"
                    }
                    iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                    color: root.neutralIconColor
                }
            }
        }

        Loader {
            active: root.utilityActive("utilities")
            visible: active
            Layout.row: root.vertical ? root.utilityIndex("utilities") : 0
            Layout.column: root.vertical ? 0 : root.utilityIndex("utilities")
            sourceComponent: CircleUtilButton {
                id: utilitiesButton
                Layout.alignment: Qt.AlignVCenter
                Accessible.name: Translation.tr("Open utilities")
                onClicked: root.utilitiesRequested()
                Component.onDestruction: root.utilitiesHoverChanged(false)
                // RippleButton already exposes buttonHovered from its internal
                // MouseArea. Reuse that signal instead of inserting a
                // PointerHandler into CircleUtilButton's Item-only default property.
                onButtonHoveredChanged: root.utilitiesHoverChanged(buttonHovered)
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: "tune"
                    iconSize: Math.round(Appearance.font.pixelSize.large * Appearance.sizes.barModuleScale)
                    color: root.neutralIconColor
                }
            }
        }
            }
        }
    }
}
