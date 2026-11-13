import qs.modules.common
import QtQuick

Item {
    id: root
    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0
    property string text: ""
    property color color: Appearance.colors.colOnSurface
    property int horizontalAlignment: Text.AlignHCenter
    property int verticalAlignment: Text.AlignVCenter
    property alias font: iconText.font
    property alias style: iconText.style
    property alias styleColor: iconText.styleColor
    property bool animateChange: false  // Compatibility with StyledText
    property bool forceNerd: false  // Force Nerd Font rendering (text is already a glyph)
    property bool animateFill: false
    property int textRenderType: Text.NativeRendering
    
    // Use Nerd Font only when explicitly requested.
    readonly property bool useNerd: forceNerd
    readonly property string nerdGlyph: forceNerd ? text : ""
    readonly property bool hasNerdGlyph: useNerd && nerdGlyph !== ""

    // "jp:<char>" renders the raw character in the Japanese UI font instead of
    // a Material Symbols name — lets registry icons be kanji/katakana.
    readonly property bool useJp: text.startsWith("jp:")
    readonly property string jpGlyph: useJp ? text.slice(3) : ""
    
    // Nerd fonts need slightly larger size to match Material Symbols visually
    readonly property real effectiveFontSize: Math.max(1, Math.round((useNerd && hasNerdGlyph) ? iconSize * 1.1 : iconSize))
    readonly property real effectiveSize: (useNerd && hasNerdGlyph) ? iconSize * 1.1 : iconSize
    
    // Use iconSize for consistent sizing regardless of font metrics
    implicitWidth: effectiveSize
    implicitHeight: effectiveSize
    
    readonly property real clampedFill: Math.max(0, Math.min(1, fill))
    readonly property real effectiveFill: Math.round(clampedFill)
    readonly property bool _variableFillIcon: !useJp && !(useNerd && hasNerdGlyph)
    readonly property bool _crossfadeFillActive: animateFill && _variableFillIcon
        && clampedFill > 0.01 && clampedFill < 0.99
    readonly property int _baseDiscreteFill: _crossfadeFillActive ? 0 : (clampedFill >= 0.5 ? 1 : 0)
    // Material Symbols variable font axis range is 20..48; keeping it in-range avoids distorted fill at small icon sizes.
    readonly property real effectiveOpsz: 24
    
    Text {
        id: iconText
        anchors.centerIn: parent
        width: root.effectiveSize
        height: root.effectiveSize
        text: root.useJp ? root.jpGlyph
            : (root.useNerd && root.hasNerdGlyph) ? root.nerdGlyph : root.text
        color: root.color
        opacity: root._crossfadeFillActive ? (1 - root.clampedFill) : 1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        renderType: root.textRenderType
        font {
            hintingPreference: (root.useNerd && root.hasNerdGlyph) ? Font.PreferFullHinting : Font.PreferNoHinting
            family: root.useJp ? "Zen Kaku Gothic New"
                : (root.useNerd && root.hasNerdGlyph)
                ? (Appearance?.font.family.monospace ?? "JetBrainsMono Nerd Font")
                : (Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded")
            pixelSize: root.useJp ? Math.max(1, Math.round(root.iconSize * 0.92)) : root.effectiveFontSize
            weight: root.useJp ? Font.Medium : Font.Normal
            variableAxes: !root._variableFillIcon ? ({}) : ({
                "FILL": root._baseDiscreteFill,
                "opsz": root.effectiveOpsz,
            })
        }
    }

    Loader {
        anchors.centerIn: parent
        width: root.effectiveSize
        height: root.effectiveSize
        active: root._crossfadeFillActive
        sourceComponent: Text {
            text: root.text
            color: root.color
            opacity: root.clampedFill
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            renderType: root.textRenderType
            style: iconText.style
            styleColor: iconText.styleColor
            font {
                hintingPreference: Font.PreferNoHinting
                family: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"
                pixelSize: root.effectiveFontSize
                weight: Font.Normal
                variableAxes: ({
                    "FILL": 1,
                    "opsz": root.effectiveOpsz,
                })
            }
        }
    }

    Behavior on fill {
        enabled: root.animateFill && Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }

    Behavior on color {
        enabled: Appearance.animationsEnabled
        ColorAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }
}
