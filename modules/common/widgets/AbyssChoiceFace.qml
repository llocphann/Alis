import QtQuick
import QtQuick.Shapes
import qs.modules.common
import "../../abyss/looks/AbyssWave.js" as Wave

// Presses start a finite vector pulse; resting controls have no timer or texture capture.
Item {
    id: root
    property color fillColor: Appearance.colors.colPrimary
    property real phase: 1
    property real origin: .5
    readonly property bool motionAllowed: visible && Appearance.animationsEnabled && (Config.options?.abyss?.waves?.enabled ?? false)
    readonly property real strength: Wave.bodyStrength(Config.options?.abyss?.waves)
    readonly property real amplitude: Math.min(4,height*.12)*Math.min(1,Wave.parameters(Config.options?.abyss?.waves).amplitude/2)*Math.min(1,strength)
    readonly property bool pulseRunning: pulse.running
    readonly property real corner: Math.max(0, Math.min(width/2-1,height/2-2))
    readonly property real inset: 2
    function lift(position): real {
        const rest=motionAllowed && strength>0 ? Math.min(.7,amplitude*.3)*Math.sin(position*Math.PI*2) : 0
        return rest+(motionAllowed ? amplitude*Math.sin(phase*Math.PI*4-Math.abs(position-origin)*5)*(1-phase) : 0)
    }
    function swell(position): void {
        if(!motionAllowed || strength<=0) return
        origin=Math.max(0,Math.min(1,position));pulse.restart()
    }
    onMotionAllowedChanged: if(!motionAllowed) { pulse.stop();phase=1 }
    NumberAnimation { id:pulse;target:root;property:"phase";from:0;to:1;duration:Math.round(520-200*Wave.parameters(Config.options?.abyss?.waves).speed) }
    Shape {
        anchors.fill:parent;preferredRendererType:Shape.CurveRenderer
        visible: root.width > 4 && root.height > 4
        ShapePath {
            strokeWidth:-1;fillColor:root.fillColor;startX:root.corner;startY:root.inset
            PathCubic { x:root.width-root.corner;y:root.inset;control1X:root.width*.34;control1Y:root.inset+root.lift(.34);control2X:root.width*.66;control2Y:root.inset+root.lift(.66) }
            PathCubic { x:root.width-root.inset;y:root.height/2;control1X:root.width-root.inset;control1Y:root.inset;control2X:root.width-root.inset;control2Y:root.height*.25 }
            PathCubic { x:root.width-root.corner;y:root.height-root.inset;control1X:root.width-root.inset;control1Y:root.height*.75;control2X:root.width-root.inset;control2Y:root.height-root.inset }
            PathCubic { x:root.corner;y:root.height-root.inset;control1X:root.width*.66;control1Y:root.height-root.inset-root.lift(.66);control2X:root.width*.34;control2Y:root.height-root.inset-root.lift(.34) }
            PathCubic { x:root.inset;y:root.height/2;control1X:root.inset;control1Y:root.height-root.inset;control2X:root.inset;control2Y:root.height*.75 }
            PathCubic { x:root.corner;y:root.inset;control1X:root.inset;control1Y:root.height*.25;control2X:root.inset;control2Y:root.inset }
        }
    }
}
