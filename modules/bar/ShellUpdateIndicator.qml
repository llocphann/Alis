import qs
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Compact Alis shell update indicator for the bar.
 * Shows when a new version is available in the git repo, and handles live update progress.
 */
MouseArea {
    id: root
    // A pointer click can retain activeFocus after hover ends. Keep popup
    // keyboard focus affordance without treating pointer focus as hover.
    property bool _pointerFocused: false
    onPressed: root._pointerFocused = true
    onActiveFocusChanged: {
        if (!root.activeFocus)
            root._pointerFocused = false
    }
    property bool vertical: false
    property real contentRotation: 0
    property bool editPreview: GlobalStates.abyssEditing
        && (Config.options?.panelFamily ?? "abyss") === "abyss"
        && (GlobalStates.abyssEditorTargetOutput === ""
            || !root.QsWindow.window?.screen?.name
            || GlobalStates.abyssEditorTargetOutput === root.QsWindow.window.screen.name)

    readonly property bool liveContentAvailable: ShellUpdates.showUpdate || ShellUpdates.isUpdating
    readonly property bool showEditPreview: editPreview && !liveContentAvailable
    readonly property bool contentAvailable: liveContentAvailable || showEditPreview
    readonly property real _targetImplicitWidth: root.contentAvailable
        ? (root.vertical ? 34 * Appearance.sizes.barModuleScale : pill.width) : 0
    property real _animatedImplicitWidth: _targetImplicitWidth
    Behavior on _animatedImplicitWidth {
        // No lingering empty slot while the update status disappears.
        // Edit-mode sample preview snaps immediately so naturalSpan is ready on frame 0.
        enabled: Appearance.animationsEnabled && root.contentAvailable && !root.showEditPreview
        animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
    }
    visible: root.contentAvailable
    implicitWidth: root.contentAvailable
        ? (root.showEditPreview ? _targetImplicitWidth : _animatedImplicitWidth) : 0
    implicitHeight: root.vertical
        ? (root.contentAvailable ? 34 * Appearance.sizes.barModuleScale : 0)
        : Appearance.sizes.barHeight

    hoverEnabled: !root.showEditPreview
    cursorShape: (root.showEditPreview || ShellUpdates.isUpdating) ? Qt.ArrowCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    activeFocusOnTab: root.visible && !ShellUpdates.isUpdating && !root.showEditPreview

    Accessible.role: Accessible.Button
    Accessible.name: ShellUpdates.isUpdating
        ? Translation.tr("Updating Alis") : Translation.tr("Alis update available")
    Accessible.focusable: root.visible && !ShellUpdates.isUpdating && !root.showEditPreview

    readonly property color accentColor: Appearance.colors.colPrimary

    function activatePrimary(): void {
        if (root.showEditPreview)
            return
        if (!ShellUpdates.isUpdating)
            ShellUpdates.openOverlay()
    }

    Keys.onPressed: event => {
        if (root.showEditPreview || ShellUpdates.isUpdating || event.isAutoRepeat
                || (event.key !== Qt.Key_Return
                    && event.key !== Qt.Key_Enter
                    && event.key !== Qt.Key_Space))
            return
        root.activatePrimary()
        event.accepted = true
    }

    onClicked: (mouse) => {
        if (root.showEditPreview || ShellUpdates.isUpdating) return;

        if (mouse.button === Qt.RightButton) {
            ShellUpdates.dismiss()
        } else {
            root.activatePrimary()
        }
    }

    // Background pill
    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: root.vertical ? 30 * Appearance.sizes.barModuleScale : contentRow.implicitWidth + 16 * Appearance.sizes.barModuleScale
        height: root.vertical ? 30 * Appearance.sizes.barModuleScale : contentRow.implicitHeight + 8 * Appearance.sizes.barModuleScale
        radius: height / 2
        scale: (!ShellUpdates.isUpdating && root.pressed) ? 0.93 : ((!ShellUpdates.isUpdating && root.containsMouse) ? 1.03 : 1.0)
        color: {
            if (ShellUpdates.isUpdating)
                return ColorUtils.transparentize(Appearance.colors.colPrimary, 0.92)
            if (root.pressed)
                return Appearance.colors.colLayer1Active
            if (root.containsMouse)
                return Appearance.colors.colLayer1Hover
            return ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
        }

        border.width: 0
        border.color: "transparent"

        Behavior on color {
            enabled: Appearance.animationsEnabled
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

    KeyboardFocusRing {
        anchors.fill: pill
        focusVisible: root.activeFocus
        radius: pill.radius
    }

    RowLayout {
        id: contentRow
        anchors.centerIn: pill
        spacing: 5 * Appearance.sizes.barModuleScale
        layoutDirection: root.contentRotation < 0 ? Qt.RightToLeft : Qt.LeftToRight

        MaterialSymbol {
            id: updateIcon
            text: ShellUpdates.isUpdating ? "settings" : "upgrade"
            iconSize: Math.round(Appearance.font.pixelSize.normal * Appearance.sizes.barModuleScale)
            rotation: -root.contentRotation
            color: root.accentColor
            Layout.alignment: Qt.AlignVCenter

            RotationAnimation on rotation {
                loops: Animation.Infinite
                running: ShellUpdates.isUpdating && root.visible
                    && (root.Window.window?.visible ?? true)
                from: -root.contentRotation
                to: 360 - root.contentRotation
                duration: 1200
            }

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: !ShellUpdates.isUpdating && !root.showEditPreview && root.containsMouse
                    && root.visible && (root.Window.window?.visible ?? true)
                NumberAnimation { to: 0.5; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        Item {
            readonly property bool verticalContent: Math.abs(root.contentRotation) === 90
            visible: !root.vertical && updateBadgeText.text !== ""
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: verticalContent ? updateBadgeText.implicitHeight : updateBadgeText.implicitWidth
            implicitHeight: verticalContent ? updateBadgeText.implicitWidth : updateBadgeText.implicitHeight

            StyledText {
                id: updateBadgeText
                objectName: "shellUpdateBadgeText"
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (ShellUpdates.isUpdating) {
                        if (ShellUpdates.updateStep > 0 && ShellUpdates.updateTotalSteps > 0) {
                            return ShellUpdates.updateStep + "/" + ShellUpdates.updateTotalSteps
                        }
                        return "" // Just spinner if no steps known
                    }
                    if (root.showEditPreview)
                        return "3"
                    return ShellUpdates.commitsBehind > 0
                        ? ShellUpdates.commitsBehind.toString()
                        : "!"
                }
                font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * Appearance.sizes.barModuleScale)
                font.weight: Font.DemiBold
                rotation: -root.contentRotation
                color: root.accentColor
            }
        }
    }

    // Hover popup — follows BatteryPopup / ResourcesPopup pattern
    StyledPopup {
        id: updatePopup
        hoverTarget: root
        hoverActivates: !root.showEditPreview
        alternativeVisibleCondition: root.activeFocus && !root._pointerFocused

        // Wrapper caps implicitWidth so StyledPopup doesn't grow unbounded
        // (monospace hashes + branch names exceed the visual area otherwise)
        Item {
            readonly property real minW: 220
            readonly property real maxW: 280
            anchors.centerIn: parent
            width: Math.min(Math.max(columnContent.implicitWidth, minW), maxW)
            height: columnContent.implicitHeight
            implicitWidth: width
            implicitHeight: height
            clip: true

            ColumnLayout {
                id: columnContent
                width: parent.width
                spacing: 6

                // Header row
                Row {
                    spacing: 5

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !ShellUpdates.isUpdating
                        text: "deployed_code_update"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !ShellUpdates.isUpdating
                        text: Translation.tr("Alis Update")
                        font {
                            weight: Font.Medium
                            pixelSize: Appearance.font.pixelSize.normal
                        }
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    LoadingText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: ShellUpdates.isUpdating
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                // Update progress
                RowLayout {
                    visible: ShellUpdates.isUpdating
                    spacing: 5
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    MaterialSymbol {
                        text: "info"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: ShellUpdates.updateStepMessage.length > 0 ? Translation.tr(ShellUpdates.updateStepMessage) : Translation.tr("Processing...")
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: ShellUpdates.updateStep > 0 && ShellUpdates.updateTotalSteps > 0
                        text: Translation.tr("Step") + " " + ShellUpdates.updateStep + "/" + ShellUpdates.updateTotalSteps
                        color: Appearance.colors.colOnSurfaceVariant
                        font.weight: Font.DemiBold
                    }
                }

                // Commits behind
                RowLayout {
                    visible: !ShellUpdates.isUpdating
                    spacing: 5
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    MaterialSymbol {
                        text: "download"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: Translation.tr("Behind:")
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: ShellUpdates.commitsBehind > 0
                            ? (ShellUpdates.commitsBehind + " " + Translation.tr("commit(s)"))
                            : Translation.tr("Update available")
                        color: ShellUpdates.commitsBehind > 10
                            ? (Appearance.m3colors?.m3error ?? Appearance.colors.colOnSurfaceVariant)
                            : Appearance.colors.colOnSurfaceVariant
                        font.weight: Font.Medium
                    }
                }

                // Version row
                RowLayout {
                    visible: !ShellUpdates.isUpdating && ShellUpdates.localVersion.length > 0 && ShellUpdates.remoteVersion.length > 0 && ShellUpdates.remoteVersion !== ShellUpdates.localVersion
                    spacing: 5
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    MaterialSymbol {
                        text: "tag"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: Translation.tr("Version:")
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideMiddle
                        text: "v" + ShellUpdates.localVersion + "  →  v" + ShellUpdates.remoteVersion
                        font {
                            family: Appearance.font.family.monospace
                            weight: Font.Medium
                        }
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                // Commit comparison row
                RowLayout {
                    visible: !ShellUpdates.isUpdating
                    spacing: 5
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    MaterialSymbol {
                        text: "commit"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: Translation.tr("Commit:")
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideMiddle
                        text: (ShellUpdates.localCommit || "\u2014") +
                            (ShellUpdates.remoteCommit.length > 0 ? ("  →  " + ShellUpdates.remoteCommit) : "")
                        font {
                            family: Appearance.font.family.monospace
                            weight: Font.Medium
                        }
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                // Branch row
                RowLayout {
                    visible: !ShellUpdates.isUpdating && ShellUpdates.currentBranch.length > 0
                    spacing: 5
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    MaterialSymbol {
                        text: "account_tree"
                        iconSize: Appearance.font.pixelSize.large
                        color: ShellUpdates.isNonMainBranch
                            ? Appearance.colors.colTertiary
                            : Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: Translation.tr("Branch:")
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideMiddle
                        text: ShellUpdates.currentBranch
                        font.family: Appearance.font.family.monospace
                        color: ShellUpdates.isNonMainBranch
                            ? Appearance.colors.colTertiary
                            : Appearance.colors.colOnSurfaceVariant
                    }
                }

                // Non-main branch hint
                StyledText {
                    visible: ShellUpdates.isNonMainBranch && !ShellUpdates.isUpdating
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Translation.tr("You are on a non-release branch. Updates track this branch.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colTertiary
                    wrapMode: Text.WordWrap
                    opacity: 0.85
                }

                // Error display
                RowLayout {
                    spacing: 5
                    visible: !ShellUpdates.isUpdating && ShellUpdates.lastError.length > 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    MaterialSymbol {
                        text: "error"
                        color: Appearance.m3colors?.m3error ?? Appearance.colors.colOnSurfaceVariant
                        iconSize: Appearance.font.pixelSize.large
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: ShellUpdates.lastError
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.m3colors?.m3error ?? Appearance.colors.colOnSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }

                // Separator
                Rectangle {
                    visible: !ShellUpdates.isUpdating
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2
                    color: Appearance.colors.colLayer0Border
                    opacity: 0.5
                }

                // Hint
                StyledText {
                    visible: !ShellUpdates.isUpdating
                    text: Translation.tr("Click for details · Right-click to dismiss")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.6
                }
            }
        }
    }
}
