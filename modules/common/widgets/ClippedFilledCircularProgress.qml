import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property int implicitSize: 18
    property int lineWidth: 2
    property real value: 0
    property color colPrimary: Appearance.colors.colOnSecondaryContainer
    property color colSecondary: ColorUtils.transparentize(colPrimary, 0.5)
    property real gapAngle: 360 / 18
    property bool fill: true
    property int fillOverflow: 2
    property bool enableAnimation: true
    property int animationDuration: 800
    property var easingType: Easing.OutCubic
    property bool accountForLightBleeding: true
    default property Item textMask: Item {
        width: implicitSize
        height: implicitSize
        StyledText {
            anchors.centerIn: parent
            text: Math.round(root.value * 100)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
        }
    }

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    readonly property real _rawDegree: Math.max(0, Math.min(360, value * 360))
    // Quantize compact progress arcs (<= 32px) to 0.5° steps (~0.08px arc length)
    // so sub-pixel periodic position ticks do not trigger 48-frame 60 FPS
    // CurveRenderer + OpacityMask FBO repaints when the arc has not visibly moved.
    property real degree: (root.implicitSize <= 32 && _rawDegree > 0 && _rawDegree < 360)
        ? (Math.round(_rawDegree * 2) / 2)
        : _rawDegree
    property real centerX: root.width / 2
    property real centerY: root.height / 2
    property real arcRadius: root.implicitSize / 2 - root.lineWidth / 2 - (0.5 * root.accountForLightBleeding)
    property real startAngle: -90

    Behavior on degree {
        enabled: root.visible && (root.Window.window?.visible ?? true)
            && root.enableAnimation
        NumberAnimation {
            duration: root.animationDuration
            easing.type: root.easingType
        }

    }

    Rectangle {
        id: contentItem
        anchors.fill: parent
        radius: implicitSize / 2
        color: root.colSecondary
        visible: false
        layer.enabled: true
        layer.smooth: true

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                id: primaryPath
                pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting
                strokeColor: root.colPrimary
                strokeWidth: root.lineWidth
                capStyle: ShapePath.RoundCap
                fillColor: root.colPrimary

                startX: root.centerX
                startY: root.centerY

                PathAngleArc {
                    moveToStart: false
                    centerX: root.centerX
                    centerY: root.centerY
                    radiusX: root.arcRadius
                    radiusY: root.arcRadius
                    startAngle: root.startAngle
                    sweepAngle: root.degree
                }
                PathLine {
                    x: primaryPath.startX
                    y: primaryPath.startY
                }
            }
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: contentItem
        invert: true
        maskSource: root.textMask
    }
}
