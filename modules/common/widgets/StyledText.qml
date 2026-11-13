import qs.modules.common
import QtQuick

Text {
    id: root
    property bool animateChange: false
    property real animationDistanceX: 0
    property real animationDistanceY: 6
    property bool marquee: false
    property bool marqueeActive: false
    readonly property bool _marqueeCandidate: root.marquee && root.marqueeActive && root.visible && root.opacity > 0 && (root.Window.window?.visible ?? true) && root.wrapMode === Text.NoWrap && root.maximumLineCount <= 1
    readonly property real _marqueeDistance: (root._marqueeCandidate && root.width > 8 && root.contentWidth > root.width + 1)
        ? Math.ceil(root.contentWidth - root.width) : 0
    readonly property bool _marqueeOverflow: root._marqueeDistance > 0
    property real _marqueeOffset: 0

    leftPadding: root._marqueeOverflow ? -root._marqueeOffset : 0
    rightPadding: root._marqueeOverflow ? root._marqueeOffset : 0
    clip: root.marquee || root._marqueeOverflow

    onElideChanged: {
        if (root.marquee && root.marqueeActive && root.elide !== Text.ElideNone)
            root.elide = Text.ElideNone
    }
    onMarqueeChanged: {
        if (root.marquee && root.marqueeActive && root.elide !== Text.ElideNone)
            root.elide = Text.ElideNone
        else if (root.marquee && !root.marqueeActive && root.elide === Text.ElideNone)
            root.elide = Text.ElideRight
        if (!root.marquee || !root.marqueeActive)
            root._marqueeOffset = 0
    }
    onMarqueeActiveChanged: {
        if (root.marquee && root.marqueeActive && root.elide !== Text.ElideNone) {
            root.elide = Text.ElideNone
        } else if (root.marquee && !root.marqueeActive) {
            if (root.elide === Text.ElideNone)
                root.elide = Text.ElideRight
            root._marqueeOffset = 0
        }
    }
    Component.onCompleted: {
        if (root.marquee && !root.marqueeActive && root.elide === Text.ElideNone)
            root.elide = Text.ElideRight
    }
    on_MarqueeOverflowChanged: {
        if (!root._marqueeOverflow)
            root._marqueeOffset = 0
    }
    onTextChanged: root._marqueeOffset = 0

    SequentialAnimation on _marqueeOffset {
        running: root._marqueeOverflow && (Appearance?.animationsEnabled ?? true)
        loops: Animation.Infinite
        PauseAnimation { duration: 1100 }
        NumberAnimation {
            from: 0
            to: root._marqueeDistance
            duration: Math.max(1200, root._marqueeDistance * 28)
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: 900 }
        NumberAnimation {
            from: root._marqueeDistance
            to: 0
            duration: Math.max(1200, root._marqueeDistance * 28)
            easing.type: Easing.InOutSine
        }
    }

    property real _slideX: 0
    property real _slideY: 0
    Translate {
        id: slideTransform
        x: root._slideX
        y: root._slideY
    }
    transform: root.animateChange ? [slideTransform] : []

    // QtRendering keeps glyph antialiasing inside the scene graph. Native
    // platform text can leave dark subpixel fringes when the texture is later
    // composited over translucent Screen Edge / layer-shell surfaces.
    renderType: Text.QtRendering
    verticalAlignment: Text.AlignVCenter
    property bool shouldUseNumberFont: /^\d+$/.test(root.text)
    property var defaultFont: shouldUseNumberFont ? Appearance.font.family.numbers : Appearance.font.family.main
    
    font {
        hintingPreference: Font.PreferDefaultHinting
        // Tooltip content can bind the font before defaultFont is initialized.
        // Keep a valid family during construction; the live binding still
        // selects the configured text/number font as soon as it is available.
        family: root.defaultFont ?? Appearance.font.family.main ?? "Roboto Flex"
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        variableAxes: shouldUseNumberFont ? ({}) : Appearance.font.variableAxes.main
        letterSpacing: (Appearance?.zzzEverywhere && !root.shouldUseNumberFont)
            ? (Appearance?.zzz.tracking ?? 0)
            : (Appearance?.regaliaEverywhere && !root.shouldUseNumberFont) ? 0.12 : 0
    }
    color: Appearance?.colors.colOnLayer0 ?? "black"
    linkColor: Appearance?.colors.colPrimary

    component Anim: NumberAnimation {
        target: root
        duration: 300 / 2
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    Behavior on text {
        enabled: root.animateChange

        SequentialAnimation {
            alwaysRunToEnd: true

            ParallelAnimation {
                Anim {
                    property: "_slideX"
                    to: -root.animationDistanceX
                    easing.type: Easing.InSine
                }
                Anim {
                    property: "_slideY"
                    to: -root.animationDistanceY
                    easing.type: Easing.InSine
                }
                Anim {
                    property: "opacity"
                    to: 0
                    easing.type: Easing.InSine
                }
            }
            PropertyAction {}
            PropertyAction {
                target: root
                property: "_slideX"
                value: root.animationDistanceX
            }
            PropertyAction {
                target: root
                property: "_slideY"
                value: root.animationDistanceY
            }
            ParallelAnimation {
                Anim {
                    property: "_slideX"
                    to: 0
                    easing.type: Easing.OutSine
                }
                Anim {
                    property: "_slideY"
                    to: 0
                    easing.type: Easing.OutSine
                }
                Anim {
                    property: "opacity"
                    to: 1
                    easing.type: Easing.OutSine
                }
            }
        }
    }
}
