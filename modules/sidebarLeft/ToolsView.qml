pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks
import qs.services
import qs.services.deferred
import "root:"

Item {
    id: root

    // Local state for niri toggles
    property bool _debugTint: false
    property bool _showDamage: false
    property bool _opaqueRegions: false

    readonly property bool abyssMode: Config.options?.panelFamily === "abyss"
    readonly property real edgeOpacity: AbyssStyle.contentOpacity
    readonly property real edgeHighlight: AbyssStyle.highlightStrength
    readonly property real edgeLift: AbyssStyle.blurRadius > 0 ? 0.024 : 0
    readonly property real edgeRadius: Math.max(12, Math.min(26, AbyssStyle.perimeterRadius))
    readonly property color cloudColor: Qt.rgba(
        Math.min(1, AbyssStyle.surfaceDeep.r + edgeLift),
        Math.min(1, AbyssStyle.surfaceDeep.g + edgeLift),
        Math.min(1, AbyssStyle.surfaceDeep.b + edgeLift),
        edgeOpacity
    )
    readonly property color cloudBorderColor: edgeHighlight > 0.01
        ? Qt.alpha(AbyssStyle.specular, Math.max(0.08, 0.55 * edgeHighlight))
        : Qt.alpha(AbyssStyle.textColor, 0.06)

    function edgeSurfaceColor(depthWeight): color {
        const k = Math.max(0, Math.min(1, depthWeight * 0.38 * root.edgeHighlight))
        return Qt.rgba(
            root.cloudColor.r + (AbyssStyle.surfaceRaised.r - root.cloudColor.r) * k,
            root.cloudColor.g + (AbyssStyle.surfaceRaised.g - root.cloudColor.g) * k,
            root.cloudColor.b + (AbyssStyle.surfaceRaised.b - root.cloudColor.b) * k,
            root.edgeOpacity
        )
    }

    // Style tokens
    readonly property color colText: root.abyssMode ? AbyssStyle.textColor
        : Appearance.angelEverywhere ? Appearance.angel.colText
        : Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer1
    readonly property color colTextSecondary: root.abyssMode ? AbyssStyle.textColorMuted
        : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colSubtext
    readonly property color colBg: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.04)
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : Appearance.alisEverywhere ? Appearance.alis.colLayer1
        : Appearance.auroraEverywhere ? "transparent"
        : Appearance.colors.colLayer1
    readonly property color colBgHover: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.09)
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : Appearance.alisEverywhere ? Appearance.alis.colLayer1Hover
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
        : Appearance.colors.colLayer1Hover
    readonly property real radius: root.abyssMode ? 11
        : Appearance.angelEverywhere ? Appearance.angel.roundingSmall
        : Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.verysmall

    Rectangle {
        id: toolsCloudBackground
        visible: root.abyssMode
        anchors.fill: parent
        anchors.margins: 4
        radius: 14
        color: root.cloudColor
        border.width: 1
        border.color: root.cloudBorderColor
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: root.edgeSurfaceColor(1.0) }
            GradientStop { position: 1.0; color: root.edgeSurfaceColor(0.25) }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.edgeRadius * 0.7
            anchors.rightMargin: root.edgeRadius * 0.7
            height: 1.5
            radius: 1
            color: Qt.alpha(AbyssStyle.accent, 0.45)
        }
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        anchors.margins: root.abyssMode ? 12 : 8
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainColumn
            width: flickable.width
            spacing: 12

            // === Power Profiles ===
            CollapsibleSection {
                title: Translation.tr("Power Profile")
                icon: "bolt"
                expanded: true
                enableSettingsSearch: false

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 4
                    spacing: 4

                    PowerProfileButton {
                        profile: PowerProfile.PowerSaver
                        profileIcon: "energy_savings_leaf"
                        label: Translation.tr("Saver")
                    }
                    PowerProfileButton {
                        profile: PowerProfile.Balanced
                        profileIcon: "balance"
                        label: Translation.tr("Balanced")
                    }
                    PowerProfileButton {
                        profile: PowerProfile.Performance
                        profileIcon: "local_fire_department"
                        label: Translation.tr("Performance")
                        enabled: PowerProfiles.hasPerformanceProfile
                    }
                }
            }

            // === Quick Toggles ===
            CollapsibleSection {
                title: Translation.tr("Quick Toggles")
                icon: "toggle_on"
                expanded: true
                enableSettingsSearch: false

                ConfigSwitch {
                    buttonIcon: "dark_mode"
                    text: Translation.tr("Dark mode")
                    autoToggle: false
                    checked: Appearance.m3colors?.darkmode ?? false
                    onToggledByUser: checked => MaterialThemeLoader.setDarkMode(checked)
                }
                ConfigSwitch {
                    buttonIcon: "nightlight"
                    text: Translation.tr("Night light")
                    autoToggle: false
                    checked: Hyprsunset.active ?? false
                    onToggledByUser: checked => Hyprsunset.toggle(checked)
                }
                ConfigSwitch {
                    buttonIcon: "coffee"
                    text: Translation.tr("Idle inhibitor")
                    checked: Idle.inhibit ?? false
                    onCheckedChanged: if (checked !== Idle.inhibit) Idle.toggleInhibit()
                }
                ConfigSwitch {
                    buttonIcon: "do_not_disturb_on"
                    text: Translation.tr("Do not disturb")
                    checked: Notifications.silent ?? false
                    onCheckedChanged: if (checked !== Notifications.silent) Notifications.toggleSilent()
                }
                ConfigSwitch {
                    buttonIcon: "sports_esports"
                    text: Translation.tr("Game mode")
                    checked: GameMode.active
                    onCheckedChanged: if (checked !== GameMode.active) GameMode.toggle()
                }
            }

            // === Capture ===
            CollapsibleSection {
                title: Translation.tr("Capture")
                icon: "screenshot"
                expanded: true
                enableSettingsSearch: false

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 4
                    columnSpacing: 4

                    ActionTile {
                        visible: CompositorService.isNiri
                        tileIcon: "screenshot"
                        label: Translation.tr("Screenshot")
                        onClicked: Quickshell.execDetached(["niri", "msg", "action", "screenshot"])
                    }
                    ActionTile {
                        tileIcon: "screenshot_region"
                        label: Translation.tr("Region")
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "screenshot"])
                    }
                    ActionTile {
                        tileIcon: "videocam"
                        label: Translation.tr("Record")
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "record"])
                    }
                    ActionTile {
                        tileIcon: "text_fields"
                        label: Translation.tr("OCR")
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "region", "ocr"])
                    }
                    ActionTile {
                        visible: CompositorService.isNiri
                        tileIcon: "colorize"
                        label: Translation.tr("Color")
                        onClicked: {
                            GlobalStates.sidebarLeftOpen = false
                            ColorPickerService.start()
                        }
                    }
                    ActionTile {
                        visible: CompositorService.isNiri
                        tileIcon: "screenshot_monitor"
                        label: Translation.tr("Window")
                        onClicked: Quickshell.execDetached(["niri", "msg", "action", "screenshot-window"])
                    }
                }
            }

            // === Quick Launch ===
            CollapsibleSection {
                title: Translation.tr("Quick Launch")
                icon: "rocket_launch"
                expanded: false
                enableSettingsSearch: false

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 4
                    columnSpacing: 4

                    ActionTile {
                        tileIcon: "terminal"
                        label: Translation.tr("Terminal")
                        onClicked: AppLauncher.launch("terminal")
                    }
                    ActionTile {
                        tileIcon: "folder"
                        label: Translation.tr("Files")
                        onClicked: AppLauncher.launch("fileManager")
                    }
                    ActionTile {
                        tileIcon: "settings"
                        label: Translation.tr("Settings")
                        onClicked: ShellExec.execDetachedArgs([Quickshell.shellPath("scripts/alis"), "settings"], "Open Alis settings")
                    }
                    ActionTile {
                        tileIcon: "tune"
                        label: Translation.tr("Audio")
                        onClicked: AppLauncher.launch("volumeMixer")
                    }
                    ActionTile {
                        tileIcon: "language"
                        label: Translation.tr("Browser")
                        onClicked: AppLauncher.launch("browser")
                    }
                    ActionTile {
                        tileIcon: "code"
                        label: Translation.tr("Editor")
                        onClicked: AppLauncher.launch("editor")
                    }
                }
            }

            // === Clipboard ===
            CollapsibleSection {
                title: Translation.tr("Clipboard")
                icon: "content_paste"
                expanded: false
                enableSettingsSearch: false

                ActionButton {
                    btnIcon: "assignment"
                    label: Translation.tr("Open clipboard manager")
                    onClicked: GlobalStates.clipboardOpen = true
                }
                ActionButton {
                    btnIcon: "delete_sweep"
                    label: Translation.tr("Clear clipboard history")
                    onClicked: Cliphist.wipe()
                }
            }

            // === Niri Debug ===
            CollapsibleSection {
                visible: CompositorService.isNiri
                title: Translation.tr("Niri Debug")
                icon: "bug_report"
                expanded: false
                enableSettingsSearch: false

                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Debug tint")
                    checked: root._debugTint
                    onCheckedChanged: {
                        if (root._debugTint !== checked) {
                            root._debugTint = checked
                            Quickshell.execDetached(["niri", "msg", "action", "toggle-debug-tint"])
                        }
                    }
                }
                ConfigSwitch {
                    buttonIcon: "broken_image"
                    text: Translation.tr("Show damage")
                    checked: root._showDamage
                    onCheckedChanged: {
                        if (root._showDamage !== checked) {
                            root._showDamage = checked
                            Quickshell.execDetached(["niri", "msg", "action", "debug-toggle-damage"])
                        }
                    }
                }
                ConfigSwitch {
                    buttonIcon: "select_all"
                    text: Translation.tr("Opaque regions")
                    checked: root._opaqueRegions
                    onCheckedChanged: {
                        if (root._opaqueRegions !== checked) {
                            root._opaqueRegions = checked
                            Quickshell.execDetached(["niri", "msg", "action", "debug-toggle-opaque-regions"])
                        }
                    }
                }
                ActionButton {
                    btnIcon: "refresh"
                    label: Translation.tr("Reload Niri config")
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "load-config-file"])
                }
            }

            // === Shell ===
            CollapsibleSection {
                title: Translation.tr("Shell")
                icon: "deployed_code"
                expanded: false
                enableSettingsSearch: false

                ActionButton {
                    btnIcon: "restart_alt"
                    label: Translation.tr("Restart shell")
                    onClicked: Quickshell.execDetached(["/usr/bin/bash", Quickshell.shellPath("scripts/restart-shell.sh")])
                }
                ActionButton {
                    btnIcon: "lock"
                    label: Translation.tr("Lock screen")
                    onClicked: Session.lock()
                }
                ActionButton {
                    btnIcon: "logout"
                    label: Translation.tr("Session menu")
                    onClicked: GlobalStates.sessionOpen = true
                }
            }

            // === System ===
            CollapsibleSection {
                title: Translation.tr("System")
                icon: "computer"
                expanded: false
                enableSettingsSearch: false

                ActionButton {
                    btnIcon: "system_update"
                    label: Translation.tr("Check for updates")
                    onClicked: ShellExec.execDetachedArgs([Config.options?.apps?.terminal ?? "/usr/bin/kitty", "-e", "fish", "-c", "yay -Syu; read -P 'Press Enter to close...'"], "Check for updates")
                }
                ActionButton {
                    btnIcon: "cleaning_services"
                    label: Translation.tr("Clean package cache")
                    onClicked: ShellExec.execDetachedArgs([Config.options?.apps?.terminal ?? "/usr/bin/kitty", "-e", "fish", "-c", "sudo paccache -rk1; read -P 'Press Enter to close...'"], "Clean package cache")
                }
                ActionButton {
                    btnIcon: "info"
                    label: Translation.tr("System info")
                    onClicked: ShellExec.execDetachedArgs([Config.options?.apps?.terminal ?? "/usr/bin/kitty", "-e", "fish", "-c", "fastfetch; read -P 'Press Enter to close...'"], "Show system info")
                }
            }

            Item { Layout.preferredHeight: 8 }
        }
    }

    // ═══════════════════════════════════════════
    // INLINE COMPONENTS
    // ═══════════════════════════════════════════

    component PowerProfileButton: RippleButton {
        required property int profile
        required property string profileIcon
        required property string label

        Layout.fillWidth: true
        implicitHeight: 56
        buttonRadius: root.radius

        readonly property bool isActive: PowerProfiles.profile === profile

        colBackground: isActive
            ? (root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.22) : Appearance.colors.colPrimary)
            : root.colBg
        colBackgroundHover: isActive
            ? (root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.30) : Appearance.colors.colPrimaryHover)
            : root.colBgHover

        onClicked: PowerProfiles.profile = profile

        contentItem: ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: profileIcon
                iconSize: 20
                fill: isActive ? 1 : 0
                animateFill: true
                color: isActive
                    ? (root.abyssMode ? AbyssStyle.accent : Appearance.colors.colOnPrimary)
                    : root.colText
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: label
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: isActive ? Font.DemiBold : Font.Normal
                color: isActive
                    ? (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnPrimary)
                    : root.colTextSecondary
            }
        }

        StyledToolTip {
            text: label + (isActive ? " (" + Translation.tr("Active") + ")" : "")
        }
    }

    component ActionTile: RippleButton {
        property string tileIcon: ""
        property string label: ""

        Layout.fillWidth: true
        implicitHeight: 56
        buttonRadius: root.radius

        colBackground: root.colBg
        colBackgroundHover: root.colBgHover

        contentItem: ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: tileIcon
                iconSize: 20
                color: root.colText
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.colTextSecondary
                elide: Text.ElideRight
            }
        }
    }

    component ActionButton: RippleButton {
        property string btnIcon: ""
        property string label: ""

        Layout.fillWidth: true
        implicitHeight: 40
        buttonRadius: root.radius

        colBackground: "transparent"
        colBackgroundHover: root.colBgHover

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            MaterialSymbol {
                text: btnIcon
                iconSize: Appearance.font.pixelSize.normal
                color: root.colText
            }
            StyledText {
                text: label
                Layout.fillWidth: true
                color: root.colText
            }
            MaterialSymbol {
                text: "chevron_right"
                iconSize: Appearance.font.pixelSize.small
                color: root.colTextSecondary
            }
        }
    }
}
