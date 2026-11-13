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
    readonly property var _savedSliderConfig: (root._inSettingsPage && root.sliderLayoutId.length > 0 && SettingsLayoutManager.hasAnySliderCustomizations)
        ? SettingsLayoutManager.getSliderConfig(root.sliderLayoutId)
        : null
    readonly property string _savedOrientation: root._savedSliderConfig?.orientation ?? ""
    property real _previewLength: -1
    property real _previewThickness: -1
    readonly property real customLength: root._previewLength >= 0 ? root._previewLength : (root._savedSliderConfig?.length ?? 0)
    readonly property real customThickness: root._previewThickness >= 0 ? root._previewThickness : (root._savedSliderConfig?.thickness ?? 0)
    readonly property bool hasCustomSliderLayout: root._savedOrientation === "vertical"
        || root.customLength > 0
        || root.customThickness > 0

    orientation: root._savedOrientation === "vertical" ? Qt.Vertical : Qt.Horizontal
    readonly property bool isVertical: root.orientation === Qt.Vertical

    property real trackWidth: abyssStyle ? 4 : configuration
    readonly property real effectiveTrackWidth: root.customThickness > 0
        ? root.customThickness
        : root.trackWidth
    property real trackRadius: abyssStyle && root.customThickness <= 0 ? 2 : effectiveTrackWidth >= StyledSlider.Configuration.XL ? 21
        : effectiveTrackWidth >= StyledSlider.Configuration.L ? 12
        : effectiveTrackWidth >= StyledSlider.Configuration.M ? 9
        : effectiveTrackWidth >= StyledSlider.Configuration.S ? 6
        : Math.max(2, effectiveTrackWidth / 2)
    property real handleHeight: (abyssStyle && root.customThickness <= 0) ? handleWidth : (configuration === StyledSlider.Configuration.Wavy) ? 24 : Math.max(33, effectiveTrackWidth + 9)
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
        ? Math.max(36, root.effectiveTrackWidth + 16, root.handleHeight + 8, (root._inSettingsPage && SettingsLayoutManager.editMode && SettingsLayoutManager.innerEditMode) ? 88 : 36)
        : (root.customLength > 0 ? root.customLength : Math.round(190 * Appearance.fontSizeScale))
    implicitHeight: root.isVertical
        ? (root.customLength > 0 ? root.customLength : 132)
        : (abyssStyle && root.customThickness <= 0
            ? 36
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

    // Interactive Edit Mode overlay for rotating & resizing sliders inside Settings modules
    Loader {
        id: sliderEditOverlayLoader
        anchors.fill: parent
        z: 30
        active: root._inSettingsPage
            && root.sliderLayoutId.length > 0
            && SettingsLayoutManager.editMode
            && SettingsLayoutManager.innerEditMode
        sourceComponent: Item {
            id: sliderEditOverlay

            property real startLength: 0
            property real startThickness: 0

            HoverHandler {
                id: sliderEditHover
            }

            readonly property bool isSliderControlsActive: sliderEditHover.hovered
                || sliderPillHover.hovered
                || sliderResizeDrag.pressed
                || rotateMouse.containsMouse
                || thickMouse.containsMouse
                || resetSliderMouse.containsMouse

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: sliderResizeDrag.pressed
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.14)
                    : (sliderEditOverlay.isSliderControlsActive ? Qt.alpha(Appearance.colors.colPrimary, 0.06) : "transparent")
                border.width: (sliderEditOverlay.isSliderControlsActive || root.hasCustomSliderLayout) ? 1 : 0
                border.color: Qt.alpha(Appearance.colors.colPrimary, sliderResizeDrag.pressed || root.hasCustomSliderLayout ? 0.75 : 0.38)
            }

            // Floating compact toolbar pill on the slider: Rotate (H/V), Thickness cycle, Reset, Size drag handle
            Rectangle {
                id: sliderControlPill
                objectName: "sliderControlPill"
                visible: sliderEditOverlay.isSliderControlsActive
                x: (root.isVertical || parent.width < width) ? 0 : Math.max(0, parent.width - width)
                y: -4
                height: 22
                width: pillRow.implicitWidth + 8
                radius: 11
                color: Appearance.colors.colLayer3
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.55)
                z: 10

                HoverHandler {
                    id: sliderPillHover
                }

                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 2

                    // Rotate Horizontal <-> Vertical
                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: rotateMouse.containsMouse
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.22)
                            : (root.isVertical ? Qt.alpha(Appearance.colors.colPrimary, 0.16) : "transparent")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.isVertical ? "swap_vert" : "swap_horiz"
                            iconSize: 13
                            color: Appearance.colors.colPrimary
                        }

                        MouseArea {
                            id: rotateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsLayoutManager.toggleSliderOrientation(root.sliderLayoutId)
                        }

                        StyledToolTip {
                            extraVisibleCondition: rotateMouse.containsMouse
                            text: root.isVertical
                                ? Translation.tr("Rotate slider to Horizontal")
                                : Translation.tr("Rotate slider to Vertical")
                        }
                    }

                    // Cycle thickness (6 -> 10 -> 16 -> 24 -> 34 -> default)
                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: thickMouse.containsMouse
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.22)
                            : (root.customThickness > 0 ? Qt.alpha(Appearance.colors.colPrimary, 0.16) : "transparent")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "line_weight"
                            iconSize: 12
                            color: Appearance.colors.colOnLayer2
                        }

                        MouseArea {
                            id: thickMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const steps = [0, 6, 10, 16, 24, 34]
                                let nextT = 8
                                for (let i = 0; i < steps.length; i++) {
                                    if (Math.abs(root.customThickness - steps[i]) <= 1) {
                                        nextT = steps[(i + 1) % steps.length]
                                        break
                                    }
                                }
                                SettingsLayoutManager.resizeSlider(root.sliderLayoutId, root.customLength, nextT, "")
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: thickMouse.containsMouse
                            text: Translation.tr("Cycle slider track thickness")
                        }
                    }

                    // Reset slider customization
                    Rectangle {
                        visible: root.hasCustomSliderLayout
                        width: 18
                        height: 18
                        radius: 9
                        color: resetSliderMouse.containsMouse
                            ? Qt.alpha(Appearance.colors.colError, 0.2)
                            : "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "restart_alt"
                            iconSize: 12
                            color: Appearance.colors.colSubtext
                        }

                        MouseArea {
                            id: resetSliderMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SettingsLayoutManager.resetSlider(root.sliderLayoutId)
                        }

                        StyledToolTip {
                            extraVisibleCondition: resetSliderMouse.containsMouse
                            text: Translation.tr("Reset slider orientation and dimensions")
                        }
                    }

                    // Drag handle for resizing slider length (and perpendicular thickness)
                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: sliderResizeDrag.pressed || sliderResizeDrag.containsMouse
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.28)
                            : Qt.alpha(Appearance.colors.colPrimary, 0.12)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "open_in_full"
                            iconSize: 11
                            color: Appearance.colors.colPrimary
                        }

                        MouseArea {
                            id: sliderResizeDrag
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: root.isVertical ? Qt.SizeVerCursor : Qt.SizeHorCursor

                            property real pressSceneX: 0
                            property real pressSceneY: 0
                            property bool resizingSlider: false

                            onPressed: mouse => {
                                const pt = sliderResizeDrag.mapToItem(null, mouse.x, mouse.y)
                                pressSceneX = pt.x
                                pressSceneY = pt.y
                                sliderEditOverlay.startLength = root.customLength > 0
                                    ? root.customLength
                                    : (root.isVertical ? root.height : root.width)
                                sliderEditOverlay.startThickness = root.effectiveTrackWidth
                                resizingSlider = true
                            }

                            onPositionChanged: mouse => {
                                if (!pressed || !resizingSlider)
                                    return
                                const pt = sliderResizeDrag.mapToItem(null, mouse.x, mouse.y)
                                const dx = pt.x - pressSceneX
                                const dy = pt.y - pressSceneY
                                const nextLen = root.isVertical
                                    ? Math.max(56, Math.min(640, Math.round(sliderEditOverlay.startLength + dy)))
                                    : Math.max(56, Math.min(640, Math.round(sliderEditOverlay.startLength + dx)))
                                const perpDelta = root.isVertical ? dx : -dy
                                const nextThick = Math.abs(perpDelta) > 8
                                    ? Math.max(4, Math.min(48, Math.round(sliderEditOverlay.startThickness + perpDelta * 0.4)))
                                    : (root._savedSliderConfig?.thickness ?? 0)
                                root._previewLength = nextLen
                                root._previewThickness = nextThick
                            }

                            onReleased: {
                                const wasResizing = resizingSlider
                                resizingSlider = false
                                if (wasResizing && (root._previewLength >= 0 || root._previewThickness >= 0)) {
                                    const finalLen = root._previewLength >= 0 ? root._previewLength : root.customLength
                                    const finalThick = root._previewThickness >= 0 ? root._previewThickness : root.customThickness
                                    root._previewLength = -1
                                    root._previewThickness = -1
                                    SettingsLayoutManager.resizeSlider(root.sliderLayoutId, finalLen, finalThick, "")
                                } else {
                                    root._previewLength = -1
                                    root._previewThickness = -1
                                }
                            }

                            onCanceled: {
                                resizingSlider = false
                                root._previewLength = -1
                                root._previewThickness = -1
                            }

                            onDoubleClicked: {
                                resizingSlider = false
                                root._previewLength = -1
                                root._previewThickness = -1
                                SettingsLayoutManager.resetSlider(root.sliderLayoutId)
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: sliderResizeDrag.containsMouse && !sliderResizeDrag.pressed
                            text: Translation.tr("Drag to resize slider length and thickness")
                        }
                    }
                }
            }

            // Live dimension badge while dragging or hovered when customized
            Rectangle {
                visible: sliderEditOverlay.isSliderControlsActive && (sliderResizeDrag.pressed || root.hasCustomSliderLayout)
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -4
                height: 16
                width: dimText.implicitWidth + 8
                radius: 8
                color: Appearance.colors.colLayer3
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.45)

                StyledText {
                    id: dimText
                    anchors.centerIn: parent
                    text: `${Math.round(root.isVertical ? root.height : root.width)}×${Math.round(root.effectiveTrackWidth)} ${root.isVertical ? "V" : "H"}`
                    font.pixelSize: 9
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colPrimary
                }
            }
        }
    }
}
