import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss
import qs.modules.abyss.looks
import "../looks/AbyssGeometry.js" as Geometry
Item {
    id: root
    Layout.fillWidth: true
    implicitHeight: 96
    property bool expanded: false
    property real progress: expanded ? 1 : 0
    Behavior on progress { NumberAnimation { duration: AbyssStyle.motionNormal } }
    Rectangle {
        anchors.fill: parent
        radius: SettingsMaterialPreset.groupRadius
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        AbyssField {
            id: field;anchors.fill:parent
            edgeInsets: ({left:8,top:10,right:8,bottom:8})
            records: [Geometry.panel(width,height,edgeInsets,"top",width*.32,width*.36,Math.min(64, Math.max(20, height * 0.44)),root.progress,10)]
            waveTexture: waves.texture
        }
        AbyssWaveController {
            id: waves
            parent: field
            outputWidth: field.width;outputHeight:field.height
            presented: root.visible
            wavesEnabled: true
        }
        StyledText {
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance.colors.colOnSurface
            opacity: 0.85
            text: "Click to test wave · " + waves.mode
        }
    }
    TapHandler {
        onTapped: eventPoint => {
            root.expanded=!root.expanded
            waves.impulse("top",eventPoint.position.x,Math.max(100, root.height * 0.8),root.expanded ? 1 : -.7,2,root.expanded ? "open" : "close")
        }
    }
}
