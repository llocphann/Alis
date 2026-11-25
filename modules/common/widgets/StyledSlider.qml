pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

/**
 * Material 3 slider. See https://m3.material.io/components/sliders/overview
 * It doesn't exactly match the spec because it does not make sense to have stuff on a computer that fucking huge.
 * Should be at 3/4 scale...
 */
 
Slider {
    id: root

    // Settings search integration (optional)
    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1
    property string settingsSearchLabel: ""
    property string settingsSearchDescription: ""
    property list<string> settingsSearchKeywords: []

    property list<real> stopIndicatorValues: [1]
    enum Configuration {
        Wavy = 4,
        XS = 12,
        S = 18,
        M = 30,
        L = 42,
        XL = 72
    }

    property var configuration: StyledSlider.Configuration.S
    readonly property bool abyssStyle: Config.options?.panelFamily === "abyss"

    property real handleDefaultWidth: abyssStyle ? 12 : 3
    property real handlePressedWidth: abyssStyle ? 14 : 1.5
    property color highlightColor: Appearance.colors.colPrimary
    property color trackColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.18) : Appearance.colors.colSecondaryContainer
    property color handleColor: Appearance.colors.colPrimary
    property color dotColor: Appearance.colors.colOnSecondaryContainer
    property color dotColorHighlighted: Appearance.colors.colOnPrimary
    property real unsharpenRadius: Appearance.rounding.unsharpen
    property string sliderLayoutId: ""
    property bool _inSettingsPage: false
    readonly property real customLength: 0
    readonly property real customThickness: 0
    readonly property bool hasCustomSliderLayout: false

    orientation: Qt.Horizontal
    readonly property bool isVertical: root.orientation === Qt.Vertical

    property real trackWidth: abyssStyle ? 5 : configuration
    readonly property real effectiveTrackWidth: root.trackWidth
    property real trackRadius: abyssStyle ? 2.5 : effectiveTrackWidth >= StyledSlider.Configuration.XL ? 21
        : effectiveTrackWidth >= StyledSlider.Configuration.L ? 12
        : effectiveTrackWidth >= StyledSlider.Configuration.M ? 9
        : effectiveTrackWidth >= StyledSlider.Configuration.S ? 6
        : Math.max(2, effectiveTrackWidth / 2)
    property real handleHeight: abyssStyle ? handleWidth : (configuration === StyledSlider.Configuration.Wavy) ? 24 : Math.max(33, effectiveTrackWidth + 9)
    property real handleWidth: root.pressed ? handlePressedWidth : handleDefaultWidth
    property real handleMargins: abyssStyle ? 8 : 4
    property real trackDotSize: 3
    property string tooltipContent: `${Math.round(value * 100)}%`
    property bool scrollable: false
    property bool _userInteracting: false
    property real liveValue: NaN
    signal seekCommitted(real value)

    Binding {
        target: root
        property: "value"
        value: root.liveValue
        when: !root.pressed && !root._userInteracting && !Number.isNaN(root.liveValue)
        restoreMode: Binding.RestoreBindingOrValue
    }
    property bool wavy: configuration === StyledSlider.Configuration.Wavy
    property bool animateWave: true
    property real waveAmplitudeMultiplier: wavy ? 0.5 : 0
    property real waveFrequency: 6
    readonly property bool usesWaveTrack: !abyssStyle && (wavy || configuration === StyledSlider.Configuration.Wavy)

    implicitWidth: root.isVertical
        ? Math.max(36, root.effectiveTrackWidth + 16, root.handleHeight + 8)
        : Math.round(190 * Appearance.fontSizeScale)
    implicitHeight: root.isVertical
        ? 132
        : (abyssStyle
            ? 32
            : Math.max((background?.implicitHeight ?? 0) + topPadding + bottomPadding, (handle?.implicitHeight ?? 0) + topPadding + bottomPadding))
    opacity: enabled ? 1 : .4

    Behavior on waveAmplitudeMultiplier {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    leftPadding: root.isVertical ? 0 : handleMargins
    rightPadding: root.isVertical ? 0 : handleMargins
    topPadding: root.isVertical ? handleMargins : 0
    bottomPadding: root.isVertical ? handleMargins : 0
    property real effectiveDraggingWidth: Math.max(0, width - leftPadding - rightPadding)
    property real effectiveDraggingHeight: Math.max(0, height - topPadding - bottomPadding)

    Layout.fillWidth: !root._inSettingsPage && !root.isVertical && root.customLength <= 0
    Layout.preferredWidth: root.isVertical
        ? root.implicitWidth
        : (root.customLength > 0
            ? root.customLength
            : (root._inSettingsPage ? Math.round(190 * Appearance.fontSizeScale) : -1))
    Layout.maximumWidth: root.isVertical
        ? root.implicitWidth
        : (root.customLength > 0
            ? root.customLength
            : (root._inSettingsPage ? Math.round(220 * Appearance.fontSizeScale) : -1))
    Layout.minimumWidth: root.isVertical
        ? root.implicitWidth
        : (root.customLength > 0 ? Math.min(root.customLength, 72) : (root._inSettingsPage ? 72 : -1))
    Layout.preferredHeight: root.isVertical ? root.implicitHeight : -1
    Layout.minimumHeight: root.isVertical ? root.implicitHeight : -1
    from: 0
    to: 1

    function _findSettingsContext() {
        var page = null;
        var card = null;
        var sectionTitle = "";
        var groupTitle = "";
        var siblingText = "";
        var indexInParent = 0;
        var pathParts = [];
        if (root.parent && root.parent.children) {
            for (var i = 0; i < root.parent.children.length; i++) {
                var ch = root.parent.children[i];
                if (ch === root) {
                    indexInParent = i;
                } else if (!siblingText && ch && ch.text && typeof ch.text === "string") {
                    var candidateText = ch.text.trim();
                    if (candidateText.length > 0 && !/^[-+]?\d+(\.\d+)?\s*(%|px|ms|s|x|dp|pt|deg|°|k|hz|db|fps)?$/i.test(candidateText)) {
                        siblingText = candidateText;
                    }
                }
            }
        }
        var node = root;
        var p = root.parent;
        while (p) {
            if (!card && p.children && p.children.length > 1) {
                for (var ci = 0; ci < p.children.length; ci++) {
                    if (p.children[ci] === node) {
                        pathParts.unshift(ci);
                        break;
                    }
                }
            }
            if (!card && p.hasOwnProperty("moduleId") && p.hasOwnProperty("bentoColumn")) {
                card = p;
            }
            if (!page && p.hasOwnProperty("settingsPageIndex")) {
                page = p;
            }
            if (p.hasOwnProperty("title")) {
                if (!sectionTitle && p.hasOwnProperty("icon")) {
                    sectionTitle = p.title;
                } else if (!groupTitle && !p.hasOwnProperty("icon")) {
                    groupTitle = p.title;
                }
            }
            node = p;
            p = p.parent;
        }
        return {
            page: page,
            card: card,
            sectionTitle: sectionTitle,
            groupTitle: groupTitle,
            siblingText: siblingText,
            indexInParent: indexInParent,
            pathKey: pathParts.length > 0 ? pathParts.join("-") : String(indexInParent)
        };
    }

    function focusFromSettingsSearch() {
        var p = root.parent;
        while (p) {
            if (p.hasOwnProperty("expanded") && p.hasOwnProperty("collapsible")) {
                p.expanded = true;
                break;
            }
            p = p.parent;
        }
        root.forceActiveFocus();
    }

    Component.onCompleted: {
        var ctx = _findSettingsContext();
        var page = ctx.page;
        var pageIndex = page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1;
        root._inSettingsPage = (page !== null);

        var rawLabel = root.settingsSearchLabel || root.Accessible.name || ctx.siblingText || ctx.groupTitle || ctx.sectionTitle || ("slider-" + ctx.indexInParent);
        if (root._inSettingsPage && !root.sliderLayoutId) {
            var slugPart = String(ctx.sectionTitle + "-" + ctx.groupTitle + "-" + rawLabel + "-" + ctx.pathKey)
                .toLowerCase()
                .replace(/[^a-z0-9]+/g, "-")
                .replace(/^-+|-+$/g, "");
            root.sliderLayoutId = "p" + pageIndex + ":slider:" + (slugPart || ("s-" + ctx.indexInParent));
        }

        if (!enableSettingsSearch)
            return;
        if (typeof SettingsSearchRegistry === "undefined")
            return;
        if (pageIndex < 0)
            return;

        var sectionTitle = ctx.sectionTitle;
        var label = root.settingsSearchLabel || ctx.groupTitle || sectionTitle;

        settingsSearchOptionId = SettingsSearchRegistry.registerOption({
            control: root,
            pageIndex: pageIndex,
            pageName: page && page.settingsPageName ? page.settingsPageName : "",
            section: sectionTitle,
            label: label,
            description: root.settingsSearchDescription || "",
            keywords: root.settingsSearchKeywords || []
        });
    }

    Component.onDestruction: {
        if (typeof SettingsSearchRegistry !== "undefined") {
            SettingsSearchRegistry.unregisterControl(root);
        }
    }

    Timer {
        id: _userInteractingReset
        interval: 250
        repeat: false
        onTriggered: root._userInteracting = false
    }

    onPressedChanged: {
        if (pressed) {
            _userInteractingReset.stop()
            root._userInteracting = true
        } else {
            _userInteractingReset.restart()
            root.seekCommitted(root.value)
            root.moved()
        }
    }

    Behavior on handleMargins {
        animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    component TrackDot: Rectangle {
        required property real value
        property real normalizedValue: {
            const span = (root?.to ?? 1) - (root?.from ?? 0)
            return span !== 0 ? (value - (root?.from ?? 0)) / span : 0
        }
        x: (root?.isVertical ?? false)
            ? ((parent?.width ?? 0) - width) / 2
            : ((root?.handleMargins ?? 0) + (normalizedValue * (root?.effectiveDraggingWidth ?? 0)) - ((root?.trackDotSize ?? 0) / 2))
        y: (root?.isVertical ?? false)
            ? ((root?.handleMargins ?? 0) + ((1 - normalizedValue) * (root?.effectiveDraggingHeight ?? 0)) - ((root?.trackDotSize ?? 0) / 2))
            : (((parent?.height ?? 0) - height) / 2)
        width: root?.trackDotSize ?? 4
        height: root?.trackDotSize ?? 4
        radius: Math.min(width, height) / 2
        color: normalizedValue > (root?.position ?? 0) ? (root?.dotColor ?? "transparent") : (root?.dotColorHighlighted ?? "transparent")

        Behavior on color {
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => mouse.accepted = false
        cursorShape: root.pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor 

        onWheel: (event) => {
            if (!root.scrollable) {
                event.accepted = false
                return
            }

            root._userInteracting = true
            _userInteractingReset.restart()

            const step = root.stepSize > 0 ? root.stepSize : 0.02
            if (event.angleDelta.y > 0) {
                root.value = Math.min(root.value + step, root.to)
            } else {
                root.value = Math.max(root.value - step, root.from)
            }
            root.seekCommitted(root.value)
            root.moved()
        }
    }

    background: Item {
        x: root.isVertical
            ? Math.round((parent.width - width) / 2)
            : (root.abyssStyle ? root.leftPadding : 0)
        y: root.isVertical
            ? (root.abyssStyle ? root.topPadding : 0)
            : Math.round((parent.height - height) / 2)
        width: root.isVertical
            ? root.effectiveTrackWidth
            : (root.abyssStyle ? root.availableWidth : parent.width)
        height: root.isVertical
            ? (root.abyssStyle ? root.availableHeight : parent.height)
            : root.effectiveTrackWidth
        implicitWidth: root.isVertical ? root.effectiveTrackWidth : 120
        implicitHeight: root.isVertical ? 120 : root.effectiveTrackWidth

        // Horizontal active fill (left)
        Loader {
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
            }
            width: Math.max(0, root.visualPosition * root.effectiveDraggingWidth - (root.abyssStyle ? 0 : handle.implicitWidth / 2))
            height: root.effectiveTrackWidth
            active: !root.isVertical && !root.usesWaveTrack
            sourceComponent: Rectangle {
                color: root.highlightColor
                topLeftRadius: root.trackRadius
                bottomLeftRadius: root.trackRadius
                topRightRadius: root.abyssStyle ? root.trackRadius : root.unsharpenRadius
                bottomRightRadius: root.abyssStyle ? root.trackRadius : root.unsharpenRadius
            }
        }

        Loader {
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
            }
            width: Math.max(0, root.visualPosition * root.effectiveDraggingWidth - handle.implicitWidth / 2)
            height: root.effectiveTrackWidth * (1 + 2 * Math.max(0.5, Math.abs(root.waveAmplitudeMultiplier)))
            active: !root.isVertical && root.usesWaveTrack
            sourceComponent: WavyLine {
                anchors.fill: parent
                frequency: root.waveFrequency
                fullLength: root.width
                color: root.highlightColor
                lineWidth: root.effectiveTrackWidth
                amplitudeMultiplier: root.waveAmplitudeMultiplier
                animate: root.animateWave && root.wavy
            }
        }

        // Horizontal inactive fill (right)
        Rectangle {
            visible: !root.isVertical
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right
            }
            width: Math.max(0, (1 - root.visualPosition) * root.effectiveDraggingWidth - (root.abyssStyle ? 0 : handle.implicitWidth / 2))
            height: root.effectiveTrackWidth
            color: root.trackColor
            topRightRadius: root.trackRadius
            bottomRightRadius: root.trackRadius
            topLeftRadius: root.abyssStyle ? root.trackRadius : root.unsharpenRadius
            bottomLeftRadius: root.abyssStyle ? root.trackRadius : root.unsharpenRadius
        }

        // Vertical active fill (bottom)
        Rectangle {
            visible: root.isVertical
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
            }
            width: root.effectiveTrackWidth
            height: Math.max(0, root.position * root.effectiveDraggingHeight - (root.abyssStyle ? 0 : handle.implicitHeight / 2))
            color: root.highlightColor
            bottomLeftRadius: root.trackRadius
            bottomRightRadius: root.trackRadius
            topLeftRadius: root.abyssStyle ? root.trackRadius : root.unsharpenRadius
            topRightRadius: root.abyssStyle ? root.trackRadius : root.unsharpenRadius
        }

        // Vertical inactive fill (top)
        Rectangle {
            visible: root.isVertical
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            width: root.effectiveTrackWidth
            height: Math.max(0, (1 - root.position) * root.effectiveDraggingHeight - (root.abyssStyle ? 0 : handle.implicitHeight / 2))
            color: root.trackColor
            topLeftRadius: root.trackRadius
            topRightRadius: root.trackRadius
            bottomLeftRadius: root.abyssStyle ? root.trackRadius : root.unsharpenRadius
            bottomRightRadius: root.abyssStyle ? root.trackRadius : root.unsharpenRadius
        }

        // Stop indicators
        Repeater {
            model: root.abyssStyle ? [] : root.stopIndicatorValues
            TrackDot {
                required property real modelData
                value: modelData
            }
        }
    }

    handle: Rectangle {
        id: handle

        implicitWidth: root.isVertical ? root.handleHeight : root.handleWidth
        implicitHeight: root.isVertical ? root.handleWidth : root.handleHeight
        x: root.isVertical
            ? Math.round((root.width - implicitWidth) / 2)
            : (root.handleMargins + (root.visualPosition * root.effectiveDraggingWidth) - (implicitWidth / 2))
        y: root.isVertical
            ? (root.topPadding + (root.visualPosition * root.effectiveDraggingHeight) - (implicitHeight / 2))
            : Math.round((root.height - implicitHeight) / 2)
        radius: Math.min(width, height) / 2
        color: root.handleColor
        border.width: root.abyssStyle ? 1 : 0
        border.color: Qt.alpha(Appearance.colors.colOnSurface,.25)

        Behavior on implicitWidth {
            enabled: Appearance.animationsEnabled
            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on implicitHeight {
            enabled: Appearance.animationsEnabled
            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        StyledToolTip {
            useParentHover: false
            externalHoverState: root.pressed
            externalPressedState: false
            extraVisibleCondition: root.pressed
            text: root.tooltipContent
            font {
                family: Appearance.font.family.numbers
                variableAxes: Appearance.font.variableAxes.numbers
                features: { "tnum": 1 }
            }
        }
    }
}
