pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Calm, cohesive Alis loading surface used for deferred popups (Dashboard,
// Settings, Nexus, Local Music, Overview, etc.) and slow Settings tab switches.
// Uses stepped solid tonal layers, a round-capped fluid orbital arc, and a
// gliding pill track; pauses all animations automatically when hidden.
Item {
    id: root
    objectName: "alisLoadingScreen"

    property bool loading: true
    property string title: ""
    property string subtitle: Translation.tr("Loading")
    property string icon: "waves"
    property color accentColor: Appearance.colors.colPrimary
    property bool fillSurface: true
    property real backdropOpacity: 0.90
    property real surfaceRadius: 0

    readonly property bool activeAnimation: root.loading
        && root.visible
        && root.opacity > 0.001
        && (root.Window.window?.visible ?? true)
        && Appearance.animationsEnabled
    readonly property color colBase: Appearance.colors.colLayer0Base
    readonly property real tonalDir: root.colBase.hslLightness > 0.86 ? -1.0 : 1.0
    readonly property color medallionFill: ColorUtils.tonalStep(
        Appearance.colors.colLayer1Base, root.tonalDir * 0.022, 1.06)
    readonly property color trackFill: ColorUtils.tonalStep(
        Appearance.colors.colLayer1Base, root.tonalDir * 0.044, 1.05)

    visible: root.loading

    Rectangle {
        id: backdrop
        anchors.fill: parent
        visible: root.fillSurface
        radius: root.surfaceRadius
        color: Qt.alpha(root.colBase, root.backdropOpacity)
    }

    Column {
        id: centerColumn
        anchors.centerIn: parent
        spacing: 10 * Appearance.fontSizeScale

        Item {
            id: orbitalEmblem
            anchors.horizontalCenter: parent.horizontalCenter
            width: 60 * Appearance.fontSizeScale
            height: width

            // Faint orbital track ring
            Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 2
                    strokeColor: Qt.alpha(root.accentColor, 0.16)
                    fillColor: "transparent"
                    PathAngleArc {
                        centerX: orbitalEmblem.width * 0.5
                        centerY: orbitalEmblem.height * 0.5
                        radiusX: orbitalEmblem.width * 0.5 - 2
                        radiusY: orbitalEmblem.height * 0.5 - 2
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }

            // Smoothly sweeping fluid orbital arc (replaces the retired spinning gear)
            Item {
                id: arcSpinner
                anchors.fill: parent
                property real arcSweep: 88

                RotationAnimation on rotation {
                    running: root.activeAnimation
                    from: 0
                    to: 360
                    duration: 1250
                    loops: Animation.Infinite
                    easing.type: Easing.Linear
                }

                SequentialAnimation on arcSweep {
                    running: root.activeAnimation
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 56
                        to: 126
                        duration: 820
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: 126
                        to: 56
                        duration: 820
                        easing.type: Easing.InOutSine
                    }
                }

                Shape {
                    anchors.fill: parent
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 2.5
                        strokeColor: root.accentColor
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: arcSpinner.width * 0.5
                            centerY: arcSpinner.height * 0.5
                            radiusX: arcSpinner.width * 0.5 - 2
                            radiusY: arcSpinner.height * 0.5 - 2
                            startAngle: -90
                            sweepAngle: arcSpinner.arcSweep
                        }
                    }
                }
            }

            // Stepped solid tonal medallion
            Rectangle {
                id: medallion
                anchors.centerIn: parent
                width: 44 * Appearance.fontSizeScale
                height: width
                radius: width * 0.5
                color: root.medallionFill
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.28)

                MaterialSymbol {
                    id: centerGlyph
                    anchors.centerIn: parent
                    text: root.icon.length > 0 ? root.icon : "waves"
                    iconSize: 20 * Appearance.fontSizeScale
                    color: root.accentColor
                    opacity: 0.94

                    SequentialAnimation on opacity {
                        running: root.activeAnimation
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0.72
                            to: 1.0
                            duration: 780
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            from: 1.0
                            to: 0.72
                            duration: 780
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.title.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }

        // Indeterminate smooth gliding pill track
        Rectangle {
            id: progressTrack
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96 * Appearance.fontSizeScale
            height: 3
            radius: height * 0.5
            color: root.trackFill
            clip: true

            Rectangle {
                id: progressPill
                height: parent.height
                width: Math.round(parent.width * 0.38)
                radius: height * 0.5
                color: root.accentColor
                property real slideNorm: 0.31
                x: (progressTrack.width + width) * slideNorm - width

                SequentialAnimation on slideNorm {
                    running: root.activeAnimation
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 0.0
                        to: 1.0
                        duration: 1120
                        easing.type: Easing.InOutCubic
                    }
                    PauseAnimation { duration: 120 }
                }
            }
        }

        StyledText {
            visible: root.subtitle.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.subtitle
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
