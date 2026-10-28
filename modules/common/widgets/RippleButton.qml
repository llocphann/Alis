pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls

/**
 * A button with ripple effect similar to in Material Design.
 */
Button {
    id: root
    hoverEnabled: true
    padding: 0
    property bool toggled
    property bool buttonHovered: buttonMouseArea.containsMouse
    property string buttonText
    Accessible.name: root.buttonText.length > 0 ? root.buttonText : root.text
    property bool pointingHandCursor: true
    readonly property bool abyssStyle: Config.options?.panelFamily === "abyss"
    property real buttonRadius: abyssStyle ? Math.min(18,height/2) : Appearance?.rounding?.small ?? 4
    property real buttonRadiusPressed: buttonRadius
    property real buttonEffectiveRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    property int rippleDuration: 1200
    property bool rippleEnabled: !abyssStyle
    property bool stateTransitionsEnabled: true
    property bool pressScaleEnabled: true
    // Retained as a compatibility knob for callers that still assign it. The
    // Material-only v1.0 renderer has no alternate organic face to activate.
    property bool cookieMorphing: false
    property var downAction // When left clicking (down)
    property var releaseAction // When left clicking (release)
    property var cancelAction // When the press is canceled before release
    property var moveAction // When mouse moves while pressed (for drag support)
    property var altAction // When right clicking
    property var middleClickAction // When middle clicking
    property bool suppressClickOnRelease: false
    property Item dragTarget: null
    property int pointerDragThreshold: 10
    readonly property bool pointerDragActive: buttonMouseArea.drag.active

    property color colBackground: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.14) : "transparent"
    property color colBackgroundHover: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.24) : Appearance.colLayer1Hover
    property color colBackgroundToggled: Appearance.colors.colPrimary
    property color colBackgroundToggledHover: Appearance.colors.colPrimaryHover
    property color colRipple: Appearance.colLayer1Active
    property color colRippleToggled: Appearance.colors.colPrimaryActive

    opacity: root.enabled ? 1 : 0.4
    property color buttonColor: {
        const hoverColor = root.toggled
            ? root.colBackgroundToggledHover : root.colBackgroundHover
        let targetColor = root.toggled
            ? (root.buttonHovered ? root.colBackgroundToggledHover : root.colBackgroundToggled)
            : (root.buttonHovered ? root.colBackgroundHover : root.colBackground)

        // Qt's literal "transparent" is transparent black. Interpolating from
        // it to a light/tinted hover first travels through black, producing the
        // apparent two-stage hover seen across Settings. Preserve the target
        // hue at alpha zero so only opacity changes on entry.
        if (!root.buttonHovered && targetColor.a === 0 && hoverColor.a > 0)
            targetColor = ColorUtils.applyAlpha(hoverColor, 0)

        return ColorUtils.transparentize(targetColor, root.enabled ? 0 : 1)
    }
    property color rippleColor: root.toggled ? colRippleToggled : colRipple

    Behavior on opacity {
        enabled: Appearance.animationsEnabled && root.stateTransitionsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    Behavior on buttonEffectiveRadius {
        enabled: Appearance.animationsEnabled && root.stateTransitionsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
    }

    function startRipple(x, y) {
        const stateY = buttonBackground.y;
        rippleAnim.x = x;
        rippleAnim.y = y - stateY;

        const dist = (ox,oy) => ox*ox + oy*oy
        const stateEndY = stateY + buttonBackground.height
        rippleAnim.radius = Math.sqrt(Math.max(dist(0, stateY), dist(0, stateEndY), dist(width, stateY), dist(width, stateEndY)))

        rippleFadeAnim.complete();
        rippleAnim.restart();
    }

    component RippleAnim: NumberAnimation {
        duration: rippleDuration
        easing.type: Appearance?.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance?.animationCurves.standardDecel
    }

    MouseArea {
        id: buttonMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        drag.target: root.dragTarget
        drag.axis: Drag.XAndYAxis
        drag.smoothed: false
        drag.threshold: root.pointerDragThreshold
        onPressed: (event) => {
            if(event.button === Qt.RightButton) {
                if (root.altAction) root.altAction(event);
                return;
            }
            if(event.button === Qt.MiddleButton) {
                if (root.middleClickAction) root.middleClickAction();
                return;
            }
            root.suppressClickOnRelease = false
            root.down = true
            if (root.downAction) root.downAction(event);
            if (!root.rippleEnabled) return;
            const {x,y} = event
            // Guard against tear-down race: when a parent Loader / popover is destroying
            // this RippleButton mid-click, the function table can be torn down before
            // the MouseArea callback finishes. Qt 6.11+ warns; pre-6.11 silently no-op'd.
            if (typeof root.startRipple === "function") root.startRipple(x, y)
        }
        onPositionChanged: (event) => {
            if (root.moveAction) root.moveAction(event);
        }
        onReleased: (event) => {
            root.down = false
            if (event.button != Qt.LeftButton) return;
            const suppressClick = root.suppressClickOnRelease || root.pointerDragActive
            root.suppressClickOnRelease = false
            if (root.releaseAction) root.releaseAction();
            if (!suppressClick)
                root.click() // Because the MouseArea already consumed the event
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
        onCanceled: (event) => {
            root.down = false
            root.suppressClickOnRelease = false
            if (root.cancelAction) root.cancelAction(event)
            else if (root.releaseAction) root.releaseAction();
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
    }

    RippleAnim {
        id: rippleFadeAnim
        duration: rippleDuration * 2
        target: ripple
        property: "opacity"
        to: 0
    }

    SequentialAnimation {
        id: rippleAnim

        property real x
        property real y
        property real radius

        PropertyAction {
            target: ripple
            property: "x"
            value: rippleAnim.x
        }
        PropertyAction {
            target: ripple
            property: "y"
            value: rippleAnim.y
        }
        PropertyAction {
            target: ripple
            property: "opacity"
            value: 1
        }
        ParallelAnimation {
            RippleAnim {
                target: ripple
                properties: "rippleWidth,rippleHeight"
                from: 0
                to: rippleAnim.radius * 2
            }
        }
    }

    background: Rectangle {
        id: buttonBackground
        implicitHeight: 30

        color: root.buttonColor
        radius: root.buttonEffectiveRadius
        border.width: root.visualFocus ? 1 : 0
        border.color: root.visualFocus ? Appearance.colors.colPrimary : "transparent"
        Behavior on border.color {
            enabled: Appearance.animationsEnabled && root.stateTransitionsEnabled
            animation: ColorAnimation { duration: Appearance.animation.stateChange.duration; easing.type: Appearance.animation.stateChange.type; easing.bezierCurve: Appearance.animation.stateChange.bezierCurve }
        }
        Behavior on color {
            enabled: Appearance.animationsEnabled && root.stateTransitionsEnabled
            animation: ColorAnimation { duration: Appearance.animation.stateChange.duration; easing.type: Appearance.animation.stateChange.type; easing.bezierCurve: Appearance.animation.stateChange.bezierCurve }
        }
        readonly property real _pressScale: {
            const w = Math.max(width, 1);
            const h = Math.max(height, 1);
            const inset = 2;
            return Math.max(0.94, Math.min(0.995,
                1 - inset / Math.max(w, h)));
        }
        scale: root.down && root.enabled && root.pressScaleEnabled ? _pressScale : 1
        Behavior on scale {
            enabled: Appearance.animationsEnabled && root.stateTransitionsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }


        layer.enabled: ripple.opacity > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: buttonBackground.width
                height: buttonBackground.height
                radius: root.buttonEffectiveRadius
                color: "white"
            }
        }

        Item {
            id: ripple
            width: ripple.rippleWidth
            height: ripple.rippleHeight
            opacity: 0
            visible: width > 0 && height > 0

            property real rippleWidth: 0
            property real rippleHeight: 0

            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            RadialGradient {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.rippleColor }
                    GradientStop { position: 0.3; color: root.rippleColor }
                    GradientStop { position: 0.5; color: Qt.rgba(root.rippleColor.r, root.rippleColor.g, root.rippleColor.b, 0) }
                }
            }

            transform: Translate {
                x: -ripple.width / 2
                y: -ripple.height / 2
            }
        }
    }

    contentItem: StyledText {
        text: root.buttonText
        color: Appearance.colors.colOnLayer0
    }
}
