import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property list<real> points: []
    property real maxVisualizerValue: 1000
    property int smoothing: 2
    property bool live: true
    readonly property var _cavaPalette: CavaTheme.visualizerColors
    property color colorLow: root._cavaPalette.length > 0
        ? root._cavaPalette[0] : Appearance.colors.colSecondaryContainer
    property color colorMed: root._cavaPalette.length > 0
        ? root._cavaPalette[Math.floor(root._cavaPalette.length / 2)]
        : Appearance.colors.colPrimary
    property color colorHigh: root._cavaPalette.length > 0
        ? root._cavaPalette[root._cavaPalette.length - 1]
        : Appearance.colors.colPrimary
    property int barCount: 50
    property real barSpacing: 2
    property real barMinHeight: 2
    property real barRadius: 3

    readonly property var _targetNormalized: {
        const count = Math.max(1, root.barCount)
        const out = new Array(count)
        const pts = root.points
        const len = pts ? pts.length : 0
        if (!root.visible || !root.live || len === 0) {
            out.fill(0)
            return out
        }
        const maxVal = Math.max(1, root.maxVisualizerValue)
        for (let idx = 0; idx < count; ++idx) {
            const start = Math.floor(idx * len / count)
            const end = Math.min(len, Math.max(start + 1, Math.ceil((idx + 1) * len / count)))
            let sum = 0
            let cnt = 0
            for (let i = start; i < end; ++i) {
                sum += pts[i] || 0
                cnt++
            }
            const barValue = cnt > 0 ? sum / cnt : 0
            out[idx] = Math.min(1, barValue / maxVal)
        }
        return out
    }

    Row {
        id: barsRow
        anchors.fill: parent
        spacing: root.barSpacing

        Repeater {
            id: barsRepeater
            model: root.visible ? root.barCount : 0

            Item {
                id: barWrapper
                required property int index
                width: (root.width - (root.barCount - 1) * root.barSpacing) / root.barCount
                height: root.height

                readonly property real normalizedValue: index < root._targetNormalized.length ? (root._targetNormalized[index] ?? 0) : 0
                readonly property real barHeight: Math.max(root.barMinHeight, normalizedValue * (root.height / 2 - 2))
                readonly property color barColor: normalizedValue > 0.7 ? root.colorHigh
                                       : normalizedValue > 0.35 ? root.colorMed
                                       : root.colorLow

                Column {
                    anchors.centerIn: parent
                    spacing: 1

                    // Top bar (grows upward)
                    Rectangle {
                        width: barWrapper.width
                        height: barWrapper.barHeight
                        radius: root.barRadius
                        color: barWrapper.barColor
                        opacity: 0.9

                        Behavior on height {
                            enabled: Appearance.animationsEnabled && root.visible
                            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                        }
                        Behavior on color {
                            enabled: Appearance.animationsEnabled && root.visible
                            ColorAnimation { duration: 100 }
                        }
                    }

                    // Bottom bar (grows downward, mirror)
                    Rectangle {
                        width: barWrapper.width
                        height: barWrapper.barHeight
                        radius: root.barRadius
                        color: barWrapper.barColor
                        opacity: 0.9

                        Behavior on height {
                            enabled: Appearance.animationsEnabled && root.visible
                            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                        }
                        Behavior on color {
                            enabled: Appearance.animationsEnabled && root.visible
                            ColorAnimation { duration: 100 }
                        }
                    }
                }
            }
        }
    }
}
