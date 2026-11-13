pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Material 3 button with expressive bounciness. 
 * See https://m3.material.io/components/button-groups/overview
 */
Button {
    id: root
    property bool toggled
    // Optional outline for high-contrast selections; existing buttons stay unchanged.
    property int selectionOutlineWidth: 0
    property color selectionOutlineColor: "transparent"
    property string buttonText
    Accessible.name: root.buttonText.length > 0 ? root.buttonText : root.text
    property real buttonRadius: Appearance?.rounding?.small ?? 8
    property real buttonRadiusPressed: Appearance?.rounding?.small ?? 6
    property var downAction // When left clicking (down)
    property var releaseAction // When left clicking (release)
    property var altAction // When right clicking
    property bool altActionEnabled: true
    property var middleClickAction // When middle clicking
    property bool bounce: true
    property bool waveFace: false
    readonly property Item waveFaceItem: waveLoader.item
    // Cookie Shapes: an organic face costs a Canvas, and a segmented group needs
    // its members to share one continuous silhouette. Standalone semantic
    // controls opt in; grouped ones stay rectangular on purpose.
    property bool cookieMorphing: false
    property real baseWidth: contentItem.implicitWidth + horizontalPadding * 2
    property real baseHeight: contentItem.implicitHeight + verticalPadding * 2
    property bool enableImplicitWidthAnimation: true
    property bool enableImplicitHeightAnimation: true
    property real clickedWidth: baseWidth + (isAtSide ? 10 : 20)
    property real clickedHeight: baseHeight
    property var parentGroup: root.parent
    property int indexInParent: {
        if (!parentGroup?.children) return -1
        let visibleIndex = 0
        for (let i = 0; i < parentGroup.children.length; ++i) {
            const child = parentGroup.children[i]
            if (!child.visible) continue
            if (child === root) return visibleIndex
            visibleIndex += 1
        }
        return -1
    }
    property int visibleChildrenCount: {
        if (!parentGroup?.children) return 0
        let count = 0
        for (let i = 0; i < parentGroup.children.length; ++i) {
            if (parentGroup.children[i].visible) count += 1
        }
        return count
    }
    property int clickIndex: parentGroup?.clickIndex ?? -1
    property bool isAtSide: indexInParent === 0 || indexInParent === (visibleChildrenCount - 1)

    Layout.fillWidth: clickIndex >= 0 && (clickIndex - 1 <= indexInParent && indexInParent <= clickIndex + 1)
    Layout.fillHeight: clickIndex >= 0 && (clickIndex - 1 <= indexInParent && indexInParent <= clickIndex + 1)
    implicitWidth: (root.down && bounce) ? clickedWidth : baseWidth
    implicitHeight: (root.down && bounce) ? clickedHeight : baseHeight

    property color colBackground: ColorUtils.transparentize(colBackgroundHover, 1) || "transparent"
    property color colBackgroundHover: Appearance.colors.colLayer1Hover
    property color colBackgroundActive: Appearance.colors.colLayer1Active
    property color colBackgroundToggled: Appearance.colors.colPrimary
    property color colBackgroundToggledHover: Appearance.colors.colPrimaryHover
    property color colBackgroundToggledActive: Appearance.colors.colPrimaryActive

    property real radius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    property real leftRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    property real rightRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    property color color: root.enabled ? (root.toggled ? 
        (root.down ? colBackgroundToggledActive : 
            root.hovered ? colBackgroundToggledHover : 
            colBackgroundToggled) :
        (root.down ? colBackgroundActive : 
            root.hovered ? colBackgroundHover : 
            colBackground)) : colBackground

    onDownChanged: {
        if (root.down && root.waveFaceItem) root.waveFaceItem.swell(buttonMouseArea.mouseX/Math.max(1,width))
        if (root.parent.clickIndex === undefined)
            return
        if (root.down)
            root.parent.clickIndex = root.indexInParent
        else if (root.parent.clickIndex === root.indexInParent)
            root.parent.clickIndex = -1
    }

    Behavior on implicitWidth {
        enabled: root.enableImplicitWidthAnimation
        animation: NumberAnimation { duration: Appearance.animation.clickBounce.duration; easing.type: Appearance.animation.clickBounce.type; easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve }
    }

    Behavior on implicitHeight {
        enabled: root.enableImplicitHeightAnimation
        animation: NumberAnimation { duration: Appearance.animation.clickBounce.duration; easing.type: Appearance.animation.clickBounce.type; easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve }
    }

    Behavior on leftRadius {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }
    Behavior on rightRadius {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    // TapHandler for right-click (altAction) - works better with Button control
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (root.altActionEnabled && root.altAction) root.altAction();
        }
    }

    // TapHandler for middle-click
    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: {
            if (root.middleClickAction) root.middleClickAction();
        }
    }

    // TapHandler for long-press (also triggers altAction)
    TapHandler {
        acceptedButtons: Qt.LeftButton
        longPressThreshold: 0.5
        onLongPressed: {
            if (root.altActionEnabled && root.altAction) root.altAction();
        }
    }

    // MouseArea only for cursor shape and left-click handling
    property alias mouseArea: buttonMouseArea
    MouseArea {
        id: buttonMouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onPressed: (event) => { 
            root.down = true
            if (root.downAction) root.downAction();
        }
        onReleased: (event) => {
            root.down = false
            if (root.releaseAction) root.releaseAction();
        }
        onClicked: (event) => {
            root.clicked()
        }
        onCanceled: (event) => {
            root.down = false
        }
    }


    background: Rectangle {
        id: buttonBackground
        topLeftRadius: root.leftRadius
        topRightRadius: root.rightRadius
        bottomLeftRadius: root.leftRadius
        bottomRightRadius: root.rightRadius
        implicitHeight: 50

        color: root.waveFace ? "transparent" : root.color
        Loader {
            id:waveLoader;anchors.fill:parent;active:root.waveFace
            sourceComponent:AbyssChoiceFace { fillColor:root.color }
        }
        border.width: root.selectionOutlineWidth
        border.color: root.selectionOutlineColor
        Behavior on color {
            enabled: Appearance.animationsEnabled
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

    }

    contentItem: StyledText {
        text: root.buttonText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: Appearance.colors.colOnLayer0
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }
}
