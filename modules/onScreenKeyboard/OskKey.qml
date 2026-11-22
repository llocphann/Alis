import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property var keyData
    property string key: keyData.label
    property string type: keyData.keytype
    property var keycode: keyData.keycode
    property string shape: keyData.shape
    readonly property bool physicalPressed: keycode !== undefined
        && keycode !== null
        && PhysicalKeyboardFeedback.pressedKeycodes.includes(Number(keycode))
    readonly property bool showPhysicalPress: physicalPressed && !root.down && !root.toggled
    property bool isShift: Ydotool.shiftKeys.includes(keycode)
    readonly property bool isCaps: root.shape === "caps"
    readonly property bool isSpace: root.shape === "space"
    property bool isBackspace: (key.toLowerCase() == "backspace")
    property bool isEnter: (key.toLowerCase() == "enter" || key.toLowerCase() == "return")
    readonly property bool isModifierKey: root.type === "modkey"
        || root.shape === "fn"
        || root.shape === "tab"
        || root.isCaps
        || root.shape === "shift"
        || root.shape === "control"
        || root.isBackspace
        || root.key.toLowerCase() === "menu"
    readonly property bool hasSecondaryLegend: root.type === "normal"
        && !root.isBackspace
        && !root.isEnter
        && !root.isSpace
        && Boolean(root.keyData?.labelShift)
        && String(root.keyData.labelShift).toLowerCase() !== String(root.keyData.label ?? "").toLowerCase()
    readonly property string primaryText: root.isSpace ? ""
        : root.isShift ? root.keyData.label
        : (root.toggled && root.keyData.labelToggled) ? root.keyData.labelToggled
        : Ydotool.shiftMode == 2 ? (root.keyData.labelCaps || root.keyData.labelShift || root.keyData.label)
        : Ydotool.shiftMode == 1 ? (root.keyData.labelShift || root.keyData.label)
        : root.keyData.label
    property real baseWidth: 46
    property real baseHeight: 44
    property var widthMultiplier: ({
        "normal": 1,
        "fn": 1,
        "tab": 1.55,
        "caps": 1.85,
        "shift": 2.4,
        "control": 1.3
    })
    property var heightMultiplier: ({
        "normal": 1,
        "fn": 0.68,
        "tab": 1,
        "caps": 1,
        "shift": 1,
        "control": 1
    })
    // Dedicated Caps Lock owns shiftMode === 2; Shift keys light up for single-shot shiftMode === 1.
    toggled: isCaps ? (Ydotool.shiftMode === 2) : (isShift ? (Ydotool.shiftMode === 1) : false)

    enabled: shape != "empty"
    // Physical key events are visual-only. Do not call Ydotool here: the real
    // keyboard event is already being delivered to the focused application.
    // Suppress this extra transform while the pointer is down (or a virtual
    // modifier is toggled) so ydotool-generated events do not double-animate.
    scale: (showPhysicalPress || root.down) ? 0.95 : 1
    Behavior on scale {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    // Unified Alis auto-theming: stepped solid tonal surfaces anchored on
    // colLayer1Base (matching DashCard / Control Center across dark & light modes)
    // with distinct modifier vs alphanumeric elevation and crisp active pills.
    readonly property color _baseLayer1: Appearance.colors.colLayer1Base !== undefined
        ? Appearance.colors.colLayer1Base
        : Appearance.colors.colLayer1
    readonly property real _tonalDir: _baseLayer1.hslLightness > 0.86 ? -1.0 : 1.0
    readonly property color _alphaFill: ColorUtils.tonalStep(_baseLayer1, _tonalDir * 0.022, 1.04)
    readonly property color _enterFill: ColorUtils.mix(Appearance.colors.colPrimary, _baseLayer1, 0.20)
    readonly property color _keyRestColor: root.isEnter
        ? _enterFill
        : (root.isModifierKey ? _baseLayer1 : _alphaFill)
    readonly property color _keyHoverColor: root.isEnter
        ? ColorUtils.mix(Appearance.colors.colPrimary, _baseLayer1, 0.30)
        : ColorUtils.tonalStep(_keyRestColor, _tonalDir * 0.028, 1.05)
    readonly property color _keyPressColor: ColorUtils.mix(Appearance.colors.colPrimary, _keyRestColor, 0.28)
    readonly property color _keyInk: root.toggled
        ? Appearance.colors.colOnPrimary
        : root.isEnter
            ? ColorUtils.readableAccentInk(Appearance.colors.colPrimary, _enterFill, 4.5, Appearance.colors.colOnLayer1)
            : root.isModifierKey
                ? ColorUtils.mix(Appearance.colors.colOnLayer1, Appearance.colors.colSubtext, 0.58)
                : Appearance.colors.colOnLayer1

    colBackground: shape === "empty"
        ? ColorUtils.transparentize(Appearance.colors.colLayer1)
        : showPhysicalPress
            ? _keyPressColor
            : _keyRestColor
    colBackgroundHover: shape === "empty"
        ? "transparent"
        : _keyHoverColor
    colBackgroundToggled: Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
    buttonRadius: Appearance.rounding.small
    implicitWidth: baseWidth * widthMultiplier[shape] || baseWidth
    implicitHeight: baseHeight * heightMultiplier[shape] || baseHeight
    Layout.fillWidth: shape == "space" || shape == "expand"

    Connections {
        target: Ydotool
        enabled: isShift
        function onShiftModeChanged() {
            if (Ydotool.shiftMode == 0) {
                capsLockTimer.hasStarted = false;
            }
        }
    }

    Timer {
        id: capsLockTimer
        property bool hasStarted: false
        property bool canCaps: false
        interval: 300
        function startWaiting() {
            hasStarted = true;
            canCaps = true;
            start();
        }
        onTriggered: {
            canCaps = false;
        }
    }

    downAction: () => {
        if (root.isCaps || root.type === "spacer" || root.keycode === undefined || root.keycode === null)
            return;
        Ydotool.press(root.keycode);
        if (isShift && Ydotool.shiftMode == 0) Ydotool.shiftMode = 1;
    }
    releaseAction: () => {
        if (root.isCaps) {
            if (Ydotool.shiftMode === 2) {
                Ydotool.releaseShiftKeys();
            } else {
                if (Ydotool.shiftMode === 0)
                    Ydotool.press(Ydotool.shiftKeys[0]);
                Ydotool.shiftMode = 2;
            }
            return;
        }
        if (root.type === "spacer" || root.keycode === undefined || root.keycode === null)
            return;
        if (root.type == "normal") {
            Ydotool.release(root.keycode);
            if (Ydotool.shiftMode == 1) {
                Ydotool.releaseShiftKeys()
            }
        } else if (isShift) {
            if (Ydotool.shiftMode == 1) {
                if (!capsLockTimer.hasStarted) {
                    capsLockTimer.startWaiting();
                } else {
                    if (capsLockTimer.canCaps) {
                        Ydotool.shiftMode = 2; // Caps lock mode
                    } else {
                        Ydotool.releaseShiftKeys()
                    }
                }
            } else if (Ydotool.shiftMode == 2) {
                Ydotool.releaseShiftKeys();
            }
        } else if (root.type == "modkey") {
            root.toggled = !root.toggled;
            if (!root.toggled) {
                if (isShift) {
                    Ydotool.releaseShiftKeys();
                } else {
                    Ydotool.release(root.keycode);
                }
            }
        }
    }

    contentItem: Item {
        anchors.fill: parent

        // Crisp hairline keycap border that elevates definition cleanly in dark & light themes
        Rectangle {
            anchors.fill: parent
            radius: root.buttonEffectiveRadius
            color: "transparent"
            border.width: (root.shape === "empty" || root.toggled) ? 0 : 1
            border.color: root.showPhysicalPress
                ? Qt.alpha(Appearance.colors.colPrimary, 0.56)
                : root.isEnter
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.36)
                    : Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)
        }

        // Secondary shifted symbol legend (e.g. ! @ # $ % { } :)
        StyledText {
            visible: root.hasSecondaryLegend && Ydotool.shiftMode === 0
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 3
            anchors.rightMargin: 5
            text: root.keyData?.labelShift ?? ""
            font.pixelSize: Math.max(9, Math.round(Appearance.font.pixelSize.smaller * 0.84))
            font.weight: Font.Medium
            color: Qt.alpha(root._keyInk, 0.46)
        }

        // Active modifier / Caps Lock LED indicator
        Rectangle {
            visible: (root.isCaps || root.isShift || root.type === "modkey") && root.toggled
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: 5
            anchors.leftMargin: 6
            width: 4
            height: 4
            radius: 2
            color: Appearance.colors.colOnPrimary
            opacity: 0.9
        }

        // Icon keycaps (Backspace, Enter, Caps Lock)
        MaterialSymbol {
            visible: root.isBackspace || root.isEnter || root.isCaps
            anchors.centerIn: parent
            text: root.isBackspace
                ? "backspace"
                : root.isEnter
                    ? "keyboard_return"
                    : "keyboard_capslock"
            iconSize: 18
            color: root._keyInk
            horizontalAlignment: Text.AlignHCenter
        }

        // Minimalist Space bar indicator pill
        Rectangle {
            visible: root.isSpace
            anchors.centerIn: parent
            width: 36
            height: 3
            radius: 1.5
            color: Qt.alpha(root._keyInk, 0.42)
        }

        // Text keycap legend
        StyledText {
            id: keyText
            visible: !root.isBackspace && !root.isEnter && !root.isCaps && !root.isSpace && root.shape !== "empty"
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 6)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideNone
            font.family: Appearance.font.family.main
            font.weight: (root.isModifierKey || root.primaryText.length > 1) ? Font.Medium : Font.Normal
            font.pixelSize: root.shape === "fn"
                ? Math.max(10, Math.round(Appearance.font.pixelSize.smaller))
                : root.primaryText.length > 1
                    ? Math.max(11, Math.round(Appearance.font.pixelSize.small))
                    : Math.round(Appearance.font.pixelSize.normal + 1)
            color: root._keyInk
            text: root.primaryText
        }
    }
}
