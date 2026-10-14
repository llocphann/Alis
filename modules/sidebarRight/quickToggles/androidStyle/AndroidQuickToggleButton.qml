import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

GroupButton {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property bool expandedSize
    required property string buttonIcon
    required property string name
    required property var mainAction
    property var altAction: null
    property string statusText: toggled ? Translation.tr("Active") : Translation.tr("Inactive")
    property bool accessibilityCheckable: true

    Accessible.role: Accessible.Button
    Accessible.name: root.name
    Accessible.description: root.statusText
    Accessible.checkable: root.accessibilityCheckable
    Accessible.checked: root.accessibilityCheckable && root.toggled

    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize
    baseWidth: root.baseCellWidth * cellSize + cellSpacing * (cellSize - 1)
    baseHeight: root.baseCellHeight

    property bool editMode: false
    altActionEnabled: !root.editMode
    readonly property color colDarkSurface: Appearance.angelEverywhere
        ? ColorUtils.transparentize(Appearance.angel.colGlassCard, 0.76)
        : Appearance.alisEverywhere ? ColorUtils.transparentize(Appearance.alis.colLayer1, 0.22)
        : Appearance.auroraEverywhere ? ColorUtils.transparentize(
            Appearance.colors.colLayer0Base,
            Math.max(0.12, Appearance.aurora.subSurfaceTransparentize - 0.14)
        )
        : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.24)
    readonly property color colDarkSurfaceHover: Appearance.angelEverywhere
        ? Appearance.angel.colGlassCardHover
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
        : Appearance.auroraEverywhere ? ColorUtils.transparentize(
            Appearance.colors.colLayer1,
            Math.max(0.16, Appearance.aurora.subSurfaceTransparentize - 0.10)
        )
        : ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.20)
    readonly property color colDarkSurfaceActive: Appearance.angelEverywhere
        ? Appearance.angel.colGlassCardActive
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
        : Appearance.auroraEverywhere ? ColorUtils.transparentize(
            Appearance.colors.colLayer1,
            Math.max(0.12, Appearance.aurora.subSurfaceTransparentize - 0.14)
        )
        : ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.18)
    enableImplicitWidthAnimation: !editMode && root.mouseArea.containsMouse
    enableImplicitHeightAnimation: !editMode && root.mouseArea.containsMouse
    Behavior on baseWidth {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve }
    }
    Behavior on baseHeight {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve }
    }
    opacity: 0
    Component.onCompleted: {
        opacity = 1
    }
    Behavior on opacity {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    signal openMenu()

    padding: 6
    horizontalPadding: padding
    verticalPadding: padding

    // ZZZ: the visible surface is the chamfered ZzzPlate below, so the GroupButton's
    // own rounded rect is held transparent.
    colBackground: Appearance.regaliaEverywhere ? Appearance.regalia.controlPlate
        : Appearance.zzzEverywhere ? "transparent"
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2
        : root.colDarkSurface
    colBackgroundHover: Appearance.regaliaEverywhere ? Appearance.regalia.controlPlateHover
        : Appearance.zzzEverywhere ? "transparent"
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
        : root.colDarkSurfaceHover
    colBackgroundToggled: Appearance.regaliaEverywhere ? Appearance.regalia.primaryPlate
        : Appearance.zzzEverywhere ? "transparent"
        : Appearance.angelEverywhere ? ColorUtils.transparentize(Appearance.angel.colPrimary, 0.45)
        : Appearance.alisEverywhere
        ? Appearance.alis.colPrimaryContainer
        : Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.regaliaEverywhere ? Appearance.regalia.primaryPlateHover
        : Appearance.zzzEverywhere ? "transparent"
        : Appearance.angelEverywhere ? ColorUtils.transparentize(Appearance.angel.colPrimaryHover, 0.35)
        : Appearance.alisEverywhere
        ? Appearance.alis.colPrimaryContainerHover
        : Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: Appearance.regaliaEverywhere ? Appearance.regalia.primaryPlateActive
        : Appearance.zzzEverywhere ? "transparent"
        : Appearance.angelEverywhere ? ColorUtils.transparentize(Appearance.angel.colPrimaryActive, 0.30)
        : Appearance.alisEverywhere
        ? Appearance.alis.colPrimaryContainerActive
        : Appearance.colors.colPrimaryActive
    buttonRadius: Appearance.regaliaEverywhere ? Appearance.regalia.controlRadius
        : Appearance.zzzEverywhere ? Appearance.zzz.controlRadius
        : Appearance.angelEverywhere ? Appearance.angel.roundingSmall
        : Appearance.alisEverywhere
        ? Appearance.alis.roundingSmall
        : (toggled ? Appearance.rounding.large : baseHeight / 2)
    buttonRadiusPressed: Appearance.regaliaEverywhere ? Appearance.regalia.controlRadius
        : Appearance.zzzEverywhere ? Appearance.zzz.cornerRadius
        : Appearance.angelEverywhere ? Appearance.angel.roundingSmall
        : Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.normal
    property color colText: Appearance.regaliaEverywhere
        ? (toggled ? Appearance.regalia.primaryPlateInk : Appearance.regalia.onMuted)
        : Appearance.zzzEverywhere
        ? (toggled ? Appearance.zzz.onAccentSoft : Appearance.zzz.inkMuted)
        : Appearance.angelEverywhere
        ? (toggled ? Appearance.angel.colOnPrimary : Appearance.angel.colText)
        : Appearance.alisEverywhere
        ? (toggled ? Appearance.alis.colOnPrimaryContainer : Appearance.alis.colText)
        : Appearance.auroraEverywhere
        ? (toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface)
        : toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
    property color colIcon: Appearance.regaliaEverywhere
        ? (toggled ? Appearance.regalia.primaryPlateInk : Appearance.regalia.onColor)
        : Appearance.zzzEverywhere
        ? (toggled ? Appearance.zzz.onAccentSoft : Appearance.zzz.ink)
        : Appearance.angelEverywhere
        ? (toggled ? Appearance.angel.colOnPrimary : Appearance.angel.colText)
        : Appearance.alisEverywhere
        ? (toggled ? Appearance.alis.colOnPrimaryContainer : Appearance.alis.colText)
        : Appearance.auroraEverywhere
        ? (toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface)
        : toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2

    onClicked: {
        root.mainAction();
    }

    contentItem: Item {
        // ZZZ console key: a real chamfered plate (geometry, not a sticker). The
        // fill carries the active state; a subtle hairline frames it when idle.
        ZzzPlate {
            anchors.fill: parent
            visible: Appearance.zzzEverywhere
            chamfer: root.buttonHovered ? Appearance.zzz.cutCorner : Appearance.zzz.cutCorner * 0.65
            fillColor: root.toggled ? Appearance.zzz.accentSoft
                : root.buttonHovered ? Appearance.zzz.sticker : Appearance.zzz.paperAlt
            strokeColor: root.toggled ? "transparent"
                : root.buttonHovered ? Appearance.zzz.accentSoft : Appearance.zzz.hairline
            strokeWidth: 1
        }

        MaterialSymbol {
            anchors.centerIn: parent
            fill: root.toggled ? 1 : 0
            animateFill: true
            iconSize: 24
            color: root.colIcon
            text: root.buttonIcon
        }
    }

    MouseArea { // Blocking MouseArea for edit interactions
        id: editModeInteraction
        visible: root.editMode
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        property bool longPressHandled: false

        function toggleEnabled() {
            // Identify the entry by type: buttonIndex is positional and goes
            // stale when rows are reused mid-edit, pinning/unpinning the wrong
            // toggle.
            const buttonType = root.buttonData.type;
            const toggleList = [...(Config.options?.sidebar?.quickToggles?.android?.toggles ?? [])];
            const existingIndex = toggleList.findIndex(toggle => toggle && toggle.type === buttonType);
            if (existingIndex === -1) {
                toggleList.push({ type: buttonType, size: 1 });
            } else {
                toggleList.splice(existingIndex, 1);
            }
            Config.setNestedValue("sidebar.quickToggles.android.toggles", toggleList);
        }

        function toggleSize() {
            const buttonType = root.buttonData.type;
            const toggleList = [...(Config.options?.sidebar?.quickToggles?.android?.toggles ?? [])];
            const existingIndex = toggleList.findIndex(toggle => toggle && toggle.type === buttonType);
            if (existingIndex === -1) return;
            const toggle = toggleList[existingIndex];
            const configuredSize = Number(toggle?.size ?? 1);
            const normalizedSize = Number.isFinite(configuredSize) && Math.round(configuredSize) === 2 ? 2 : 1;
            toggleList[existingIndex] = Object.assign({}, toggle, { size: normalizedSize === 1 ? 2 : 1 });
            Config.setNestedValue("sidebar.quickToggles.android.toggles", toggleList);
        }

        function movePositionBy(offset) {
            const buttonType = root.buttonData.type;
            const toggleList = [...(Config.options?.sidebar?.quickToggles?.android?.toggles ?? [])];
            const existingIndex = toggleList.findIndex(toggle => toggle && toggle.type === buttonType);
            if (existingIndex === -1) return;
            const targetIndex = existingIndex + offset;
            if (targetIndex < 0 || targetIndex >= toggleList.length) return;
            const temp = toggleList[existingIndex];
            toggleList[existingIndex] = toggleList[targetIndex];
            toggleList[targetIndex] = temp;
            Config.setNestedValue("sidebar.quickToggles.android.toggles", toggleList);
        }

        onReleased: (event) => {
            if (event.button === Qt.LeftButton && !longPressHandled)
                toggleEnabled();
            longPressHandled = false;
        }
        onPressed: (event) => {
            if (event.button === Qt.LeftButton) longPressHandled = false;
            if (event.button === Qt.RightButton) toggleSize();
        }
        onPressAndHold: (event) => {
            longPressHandled = true;
            toggleSize();
        }
        onWheel: (event) => {
            if (event.angleDelta.y < 0) { // Move to right
                movePositionBy(1);
            } else if (event.angleDelta.y > 0) { // Move to left
                movePositionBy(-1);
            }
            event.accepted = true;
        }
    }
}
