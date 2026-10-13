import qs.modules.bar.weather
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE

Item {
    id: root

    layer.enabled: Appearance.shouldDesaturate("bar") && root.visible
    layer.effect: ShellDesaturationEffect {}

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property alias backgroundItem: barBackground
    property bool nativeBlurAllowed: true

    property Item barContextMenuSource: null
    property rect barContextMenuRect: Qt.rect(0, 0, 1, 1)

    function openBarContextMenu(clickX, clickY, mouseArea) {
        root.barContextMenuSource = mouseArea
        root.barContextMenuRect = Qt.rect(clickX, clickY, 1, 1)
        barContextMenu.requestOpen()
    }

    BarContextMenu {
        id: barContextMenu
        anchorItem: root.barContextMenuSource ?? root
        anchorRect: root.barContextMenuRect
        anchorHovered: root.barContextMenuSource?.hovered ?? false
        closeOnHoverLost: true

        model: [
            {
                iconName: "browse_activity",
                monochromeIcon: true,
                text: Translation.tr("Mission Center"),
                action: () => {
                    Session.launchTaskManager()
                },
            },
            { type: "separator" },
            {
                iconName: "settings",
                monochromeIcon: true,
                text: Translation.tr("Settings"),
                action: () => {
                    Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings"])
                },
            },
        ]
    }

    readonly property bool taskbarEnabled: Config.options?.bar?.modules?.taskbar ?? false
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width)
        ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0

    // Adaptive horizontal packing. Physical-edge inset is independent from
    // module/zone/pivot spacing, and each half reacts to its own pressure.
    readonly property real edgeInset: Math.max(4, Appearance.rounding.screenRounding)
    readonly property real moduleGap: Math.max(2,
        Math.round(4 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))
    readonly property real zoneGapNominal: Math.max(root.moduleGap + 2,
        Math.round(8 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))
    readonly property real zoneGapMinimum: Math.max(2,
        Math.round(4 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))
    readonly property real pivotGapNominal: Math.max(root.moduleGap + 1,
        Math.round(6 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))
    readonly property real pivotGapMinimum: Math.max(2,
        Math.round(3 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))

    readonly property bool _leftEdgeHasContent: leftSectionRowLayout.implicitWidth > 1
    readonly property bool _rightEdgeHasContent: rightSectionRowLayout.implicitWidth > 1
    readonly property bool _leftCenterHasContent: !leftCenterGroup.empty
    readonly property bool _rightCenterHasContent: !rightCenterGroupPill.empty
    readonly property bool _pivotHasContent: !middleCenterGroup.empty
    readonly property bool _leftZoneGapNeeded: root._leftEdgeHasContent
        && (root._leftCenterHasContent || root._pivotHasContent)
    readonly property bool _rightZoneGapNeeded: root._rightEdgeHasContent
        && (root._rightCenterHasContent || root._pivotHasContent)
    readonly property bool _leftPivotGapNeeded:
        root._leftCenterHasContent && root._pivotHasContent
    readonly property bool _rightPivotGapNeeded:
        root._rightCenterHasContent && root._pivotHasContent
    readonly property real _halfWidth: Math.max(0, root.width / 2)
    readonly property real _pivotHalfWidth: root._pivotHasContent
        ? middleCenterGroup.contentWidth / 2 : 0

    readonly property real leftNaturalNeed:
        (root._leftEdgeHasContent
            ? root.edgeInset + leftSectionRowLayout.implicitWidth : 0)
        + (root._leftZoneGapNeeded ? root.zoneGapNominal : 0)
        + (root._leftCenterHasContent ? leftCenterGroup.contentWidth : 0)
        + (root._leftPivotGapNeeded ? root.pivotGapNominal : 0)
        + root._pivotHalfWidth
    readonly property real rightNaturalNeed:
        (root._rightEdgeHasContent
            ? root.edgeInset + rightSectionRowLayout.implicitWidth : 0)
        + (root._rightZoneGapNeeded ? root.zoneGapNominal : 0)
        + (root._rightCenterHasContent ? rightCenterGroupPill.contentWidth : 0)
        + (root._rightPivotGapNeeded ? root.pivotGapNominal : 0)
        + root._pivotHalfWidth
    readonly property real leftPressure:
        Math.max(0, root.leftNaturalNeed - root._halfWidth)
    readonly property real rightPressure:
        Math.max(0, root.rightNaturalNeed - root._halfWidth)

    readonly property real leftGapCompressionCapacity:
        (root._leftZoneGapNeeded
            ? root.zoneGapNominal - root.zoneGapMinimum : 0)
        + (root._leftPivotGapNeeded
            ? root.pivotGapNominal - root.pivotGapMinimum : 0)
    readonly property real rightGapCompressionCapacity:
        (root._rightZoneGapNeeded
            ? root.zoneGapNominal - root.zoneGapMinimum : 0)
        + (root._rightPivotGapNeeded
            ? root.pivotGapNominal - root.pivotGapMinimum : 0)
    readonly property real leftGapCompression: root.leftGapCompressionCapacity > 0
        ? Math.min(1, root.leftPressure / root.leftGapCompressionCapacity) : 0
    readonly property real rightGapCompression: root.rightGapCompressionCapacity > 0
        ? Math.min(1, root.rightPressure / root.rightGapCompressionCapacity) : 0

    readonly property real leftZoneGap: root._leftZoneGapNeeded
        ? root.zoneGapNominal
            - (root.zoneGapNominal - root.zoneGapMinimum) * root.leftGapCompression
        : 0
    readonly property real rightZoneGap: root._rightZoneGapNeeded
        ? root.zoneGapNominal
            - (root.zoneGapNominal - root.zoneGapMinimum) * root.rightGapCompression
        : 0
    readonly property real leftPivotGap: root._leftPivotGapNeeded
        ? root.pivotGapNominal
            - (root.pivotGapNominal - root.pivotGapMinimum) * root.leftGapCompression
        : 0
    readonly property real rightPivotGap: root._rightPivotGapNeeded
        ? root.pivotGapNominal
            - (root.pivotGapNominal - root.pivotGapMinimum) * root.rightGapCompression
        : 0

    readonly property real leftCenterMaxWidth: Math.max(0,
        root._halfWidth - root._pivotHalfWidth
        - (root._leftEdgeHasContent
            ? root.edgeInset + leftSectionRowLayout.implicitWidth : 0)
        - root.leftZoneGap - root.leftPivotGap)
    readonly property real rightCenterMaxWidth: Math.max(0,
        root._halfWidth - root._pivotHalfWidth
        - (root._rightEdgeHasContent
            ? root.edgeInset + rightSectionRowLayout.implicitWidth : 0)
        - root.rightZoneGap - root.rightPivotGap)

    function _pillWidth(cw, maxWidth) {
        const own = Math.max(0, Number(cw) || 0)
        return own <= 0 ? 0 : Math.min(own, Math.max(0, maxWidth))
    }

    function _zoneContains(ids, id) {
        return Array.isArray(ids) && ids.indexOf(id) >= 0
    }
    readonly property real _utilityWeightLeft:
        root._zoneContains(root._leftIds, "utilButtons")
            || root._zoneContains(root._centerLeftIds, "utilButtons") ? 1
        : root._zoneContains(root._centerIds, "utilButtons") ? 0.5 : 0
    readonly property real _utilityWeightRight:
        root._zoneContains(root._rightIds, "utilButtons")
            || root._zoneContains(root._centerRightIds, "utilButtons") ? 1
        : root._zoneContains(root._centerIds, "utilButtons") ? 0.5 : 0
    readonly property bool _utilityPackingEnabled:
        root._moduleVisible("utilButtons")
        && (Config.options?.bar?.verbose ?? true)
        && (root._utilityWeightLeft > 0 || root._utilityWeightRight > 0)
    property bool horizontalUtilitiesCompact: false
    readonly property real utilityExpansionDelta: Math.max(0,
        utilButtonsMeasure.expandedMainAxisLength
            - utilButtonsMeasure.compactMainAxisLength)
    readonly property real leftExpandedPressure: root.leftPressure
        + (root.horizontalUtilitiesCompact
            ? root.utilityExpansionDelta * root._utilityWeightLeft : 0)
    readonly property real rightExpandedPressure: root.rightPressure
        + (root.horizontalUtilitiesCompact
            ? root.utilityExpansionDelta * root._utilityWeightRight : 0)

    function _scheduleUtilityPacking(): void {
        utilityPackingTimer.restart()
    }

    function _reconcileUtilityPacking(): void {
        if (!root._utilityPackingEnabled) {
            if (root.horizontalUtilitiesCompact)
                root.horizontalUtilitiesCompact = false
            return
        }

        const leftNeedsCompact = root._utilityWeightLeft > 0
            && root.leftExpandedPressure > root.leftGapCompressionCapacity + 0.5
        const rightNeedsCompact = root._utilityWeightRight > 0
            && root.rightExpandedPressure > root.rightGapCompressionCapacity + 0.5
        const needsCompact = leftNeedsCompact || rightNeedsCompact

        if (!root.horizontalUtilitiesCompact) {
            if (needsCompact)
                root.horizontalUtilitiesCompact = true
            return
        }

        const leftRelaxed = root._utilityWeightLeft <= 0
            || root.leftExpandedPressure
                <= Math.max(0, root.leftGapCompressionCapacity - 3)
        const rightRelaxed = root._utilityWeightRight <= 0
            || root.rightExpandedPressure
                <= Math.max(0, root.rightGapCompressionCapacity - 3)
        if (!needsCompact && leftRelaxed && rightRelaxed)
            root.horizontalUtilitiesCompact = false
    }

    onWidthChanged: root._scheduleUtilityPacking()
    onLeftPressureChanged: root._scheduleUtilityPacking()
    onRightPressureChanged: root._scheduleUtilityPacking()
    onUtilityExpansionDeltaChanged: root._scheduleUtilityPacking()

    Timer {
        id: utilityPackingTimer
        interval: 16
        repeat: false
        onTriggered: root._reconcileUtilityPacking()
    }

    // Hidden natural-size probe mirrors the real utility enable matrix but
    // never accepts input and never participates in layout.
    UtilButtons {
        id: utilButtonsMeasure
        visible: false
        enabled: false
        vertical: false
        compactRequested: false
    }

    readonly property bool cardStyleEverywhere: false
    readonly property string surfaceDialect: Appearance.surfaceDialectFor("")
    readonly property bool zzzEverywhere: root.surfaceDialect === "zzz"
    readonly property color separatorColor: root.zzzEverywhere
        ? Appearance.zzz.hairlineStrong : Appearance.colors.colOutlineVariant

    readonly property string wallpaperUrl: {
        const _dep1 = WallpaperListener.multiMonitorEnabled
        const _dep2 = WallpaperListener.effectivePerMonitor
        const _dep3 = Wallpapers.effectiveWallpaperUrl
        return WallpaperListener.wallpaperUrlForScreen(root.screen)
    }

    readonly property bool _useGlobalQuantizer: root.wallpaperUrl === Wallpapers.effectiveWallpaperUrl
    ColorQuantizer {
        id: wallpaperColorQuantizer
        source: root.auroraEverywhere
            ? (root._useGlobalQuantizer ? "" : root.wallpaperUrl)
            : ""
        depth: 0
        rescaleSize: 10
    }

    readonly property color wallpaperDominantColor: root._useGlobalQuantizer
        ? Appearance.wallpaperDominantColor
        : (wallpaperColorQuantizer?.colors?.[0] ?? Appearance.colors.colPrimary)
    AdaptedMaterialScheme {
        id: _localBlendedColors
        color: ColorUtils.mix(root.wallpaperDominantColor,
            Appearance.colors.colPrimaryContainer, 0.8)
            || Appearance.colors.colSecondaryContainer
    }
    readonly property QtObject blendedColors: root._useGlobalQuantizer
        ? Appearance.wallpaperBlendedColors : _localBlendedColors

    readonly property bool alisEverywhere: root.surfaceDialect === "alis"
    readonly property bool angelEverywhere: root.surfaceDialect === "angel"
    readonly property bool regaliaEverywhere: root.surfaceDialect === "regalia"
    readonly property bool auroraEverywhere: root.surfaceDialect === "aurora" || root.angelEverywhere

    readonly property string nativeBlurTopology: Appearance.blurTopology.unsupported
    readonly property bool nativeBlurGeometryExact:
        Appearance.blurTopologyExact(root.nativeBlurTopology)
    readonly property bool nativeBlurActive: Appearance.useCompositorBlur(
            "bar", root.nativeBlurTopology)
        && root.nativeBlurAllowed
        && !Appearance.gameModeMinimal
    readonly property bool zzzDetachedRounded: false

    readonly property string leftAction: Config.options?.bar?.leftScrollAction ?? "brightness"
    readonly property string rightAction: Config.options?.bar?.rightScrollAction ?? "volume"
    readonly property bool barSpectrumAudioPlaying: MprisController.isPlaying || YtMusic.isPlaying
    readonly property bool barSpectrumOutputEnabled:
        (Config.options?.bar?.visualizer?.multiMonitorMode ?? "primary") === "all"
        || Quickshell.screens.length <= 1
        || String(root.screen?.name ?? "") === String(GlobalStates.primaryScreen?.name ?? "")
    readonly property bool barSpectrumConfigured:
        (Config.options?.bar?.visualizer?.enable ?? false)
        && root.barSpectrumOutputEnabled
        && !Appearance.gameModeMinimal
        && root.visible
        && (root.QsWindow.window?.visible ?? false)
    readonly property bool barSpectrumProcessWanted: root.barSpectrumConfigured
        && root.barSpectrumAudioPlaying
    readonly property bool barSpectrumVisible: root.barSpectrumConfigured
        && barCavaProcess.audioSignalActive
    readonly property real barSpectrumFillRatio: Math.max(0.1,
        Math.min(1, Config.options?.bar?.visualizer?.height ?? 0.6))
    readonly property real barSpectrumOpacity: Math.max(0,
        Math.min(1, Config.options?.bar?.visualizer?.opacity ?? 0.35))
    readonly property string barSpectrumType: Config.options?.bar?.visualizer?.type ?? "bars"
    readonly property string barSpectrumBarsOrigin: Config.options?.bar?.visualizer?.barsOrigin ?? "bottom"
    readonly property real barSpectrumDensity: Math.max(4,
        Config.options?.bar?.visualizer?.density ?? 12)
    readonly property real barSpectrumGap: Math.max(0,
        Config.options?.bar?.visualizer?.gap ?? 2)
    readonly property int barSpectrumSmoothing: Math.max(0,
        Config.options?.bar?.visualizer?.smoothing ?? 2)
    readonly property string barSpectrumWaveMode: Config.options?.bar?.visualizer?.waveMode ?? "fill"
    readonly property real barSpectrumLineWidth: Math.max(1,
        Config.options?.bar?.visualizer?.lineWidth ?? 2)
    readonly property real barSpectrumEdgeInset: Math.max(0,
        Config.options?.bar?.visualizer?.edgeInset ?? 0)
    readonly property real barSpectrumEdgeSoftness: Math.max(0,
        Math.min(1, (Config.options?.bar?.visualizer?.edgeSoftness ?? 28) / 100))
    readonly property string barSpectrumFrequencyProfile:
        Config.options?.bar?.visualizer?.frequencyProfile ?? "flat"
    readonly property real barSpectrumAccentStrength: Math.max(0,
        Math.min(1, (Config.options?.bar?.visualizer?.accentStrength ?? 70) / 100))
    // Keep the continuous wave's CAVA payload aligned with its bounded scene
    // resolution. Bars stay density-derived because they are discrete columns.
    readonly property int barSpectrumWaveSampleCap: 72
    readonly property color barSpectrumColor: root.alisEverywhere ? Appearance.alis.colPrimary
        : root.zzzEverywhere ? Appearance.zzz.accent
        : root.regaliaEverywhere ? Appearance.regalia.hardwarePrimary
        : (root.blendedColors?.colPrimary ?? Appearance.colors.colPrimary)

    CavaProcess {
        id: barCavaProcess
        active: root.barSpectrumProcessWanted
        sampleCount: {
            const densityCount = Math.max(50,
                Math.round(Math.max(1, root.width) / root.barSpectrumDensity))
            return root.barSpectrumType === "wave"
                ? Math.min(root.barSpectrumWaveSampleCap, densityCount)
                : densityCount
        }
    }

    function performScrollAction(action: string, isUp: bool): void {
        if (action === "brightness") {
            const step = 0.05;
            root.brightnessMonitor.setBrightness(
                root.brightnessMonitor.brightness + (isUp ? step : -step));
        } else if (action === "volume") {
            if (isUp) Audio.incrementVolume();
            else Audio.decrementVolume();
        } else if (action === "workspace") {
            let up = isUp;
            if (Config.options?.bar?.workspaces?.invertScroll ?? false) up = !up;
            if (CompositorService.isNiri) {
                if (up) NiriService.focusWorkspaceUp();
                else NiriService.focusWorkspaceDown();
            } else if (CompositorService.isHyprland) {
                Hyprland.dispatch(up ? "workspace r-1" : "workspace r+1");
            }
        }
    }

    function closeOSD(action: string): void {
        if (action === "brightness") GlobalStates.osdBrightnessOpen = false;
        else if (action === "volume") GlobalStates.osdVolumeOpen = false;
    }

    function getScrollIcon(action: string): string {
        if (action === "brightness") return "light_mode";
        if (action === "volume") return "volume_up";
        if (action === "workspace") return "workspaces";
        return "";
    }

    function getScrollTooltip(action: string): string {
        if (action === "brightness") return Translation.tr("Scroll to change brightness");
        if (action === "volume") return Translation.tr("Scroll to change volume");
        if (action === "workspace") return Translation.tr("Scroll to switch workspaces");
        return "";
    }

    component EdgeZoneCell: Item {
        id: cell
        required property string modelData
        property string zone: "left"
        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: root._fillWidth(modelData, zone)
        Layout.fillHeight: root._fillHeight(modelData)
        implicitWidth: cellLoader.implicitWidth
        implicitHeight: cellLoader.implicitHeight
        visible: root._moduleShown(cell.modelData, cell.zone)
        Loader {
            id: cellLoader
            anchors.fill: parent
            active: root._moduleShown(cell.modelData, cell.zone)
            sourceComponent: root._allComponents[cell.modelData] ?? null
            onLoaded: if (cell.modelData === "activeWindow" && item)
                item.fillSlot = Qt.binding(() => root._fillSlot(cell.zone))
        }
    }

    component VerticalBarSeparator: Rectangle {
        Layout.topMargin: Appearance.sizes.baseBarHeight / 3
        Layout.bottomMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillHeight: true
        implicitWidth: 1
        color: root.zzzEverywhere ? Appearance.zzz.hairlineStrong
            : root.alisEverywhere ? Appearance.alis.colBorderSubtle
            : root.separatorColor
        Behavior on implicitWidth {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    readonly property bool _layoutMigrated: Config.options?.bar?.layout?.migrated === true
    readonly property real _spacerMinimumWidth: Math.max(0,
        Config.options?.bar?.layout?.spacerWidth ?? 0) * Appearance.fontSizeScale * Appearance.sizes.barModuleScale
    function _zone(name, fallback) {
        const a = Config.options?.bar?.layout?.[name]
        return (root._layoutMigrated && a && a.length >= 0) ? a : fallback
    }
    readonly property var _leftIds: root._zone("left",
        ["leftSidebarButton", "distroIcon", "activeWindow"])
    readonly property var _centerLeftIds: root._zone("centerLeft",
        ["resources", "media"])
    readonly property var _centerIds: root._zone("center", ["workspaces"])
    readonly property var _centerRightIds: root._zone("centerRight",
        ["clock", "utilButtons", "battery"])
    readonly property var _rightIds: root._zone("right",
        ["rightSidebarButton", "tray", "timer", "shellUpdate", "spacer", "weather"])

    function _moduleVisible(id) {
        return Config.options?.bar?.modules?.[id] ?? true
    }

    function _moduleShown(id, zone) {
        if (id === "spacer")
            return root._fillWidth(id, zone) || root._spacerMinimumWidth > 0;
        if (id === "tray")
            return root._moduleVisible("sysTray") && root.useShortenedForm === 0;
        if (!root._moduleVisible(id)) return false;
        if (id === "activeWindow")
            return root.taskbarEnabled || root.useShortenedForm === 0;
        if (id === "media") return root.useShortenedForm < 2;
        if (id === "utilButtons")
            return Config.options?.bar?.verbose ?? true;
        if (id === "battery") return root.useShortenedForm < 2 && Battery.available;
        if (id === "weather") return Config.options?.bar?.weather?.enable ?? false;
        return true;
    }

    readonly property var _allComponents: ({
        "leftSidebarButton": leftSidebarButtonComponent,
        "distroIcon": distroIconComponent,
        "activeWindow": activeWindowComponent,
        "resources": resourcesModuleComponent,
        "media": mediaModuleComponent,
        "workspaces": workspacesModuleComponent,
        "clock": clockModuleComponent,
        "utilButtons": utilButtonsModuleComponent,
        "battery": batteryModuleComponent,
        "rightSidebarButton": rightSidebarButtonComponent,
        "tray": trayComponent,
        "timer": timerComponent,
        "shellUpdate": shellUpdateComponent,
        "weather": weatherComponent,
        "spacer": spacerComponent,
    })

    readonly property var _edgeZones: ["left", "right"]
    function _fillSlot(zone) { return root._edgeZones.indexOf(zone) !== -1 }

    readonly property string _spacerMode: Config.options?.bar?.layout?.spacerMode ?? "auto"
    function _fillWidth(id, zone) {
        if (id === "spacer") {
            if (root._spacerMode === "fixed") return false
            if (root._spacerMode === "fill") return true
            return root._fillSlot(zone)
        }
        if (id === "activeWindow") return root._fillSlot(zone)
        if (id === "resources") return root.useShortenedForm === 2
        return false
    }
    function _fillHeight(id) {
        if (id === "activeWindow") return true
        return id === "spacer" || id === "tray" || id === "workspaces"
    }

    Component {
        id: resourcesModuleComponent
        Resources {
            visible: root._moduleVisible("resources")
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: root.useShortenedForm === 2
            alwaysShowAllResources: root.useShortenedForm === 2
        }
    }
    Component {
        id: mediaModuleComponent
        Media {
            visible: root._moduleVisible("media") && root.useShortenedForm < 2
        }
    }
    Component {
        id: workspacesModuleComponent
        Workspaces {
            visible: root._moduleVisible("workspaces")
            Layout.fillHeight: true
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onPressed: event => {
                    if (event.button === Qt.RightButton)
                        GlobalStates.toggleOverview(root.screen?.name ?? "");
                }
            }
        }
    }
    Component {
        id: clockModuleComponent
        ClockWidget {
            visible: root._moduleVisible("clock")
            showDate: ((Config.options?.bar?.verbose ?? true) && root.useShortenedForm < 2)
        }
    }
    Component {
        id: utilButtonsModuleComponent
        UtilButtons {
            visible: root._moduleVisible("utilButtons")
                && (Config.options?.bar?.verbose ?? true)
            compactRequested: root.horizontalUtilitiesCompact
            Layout.alignment: Qt.AlignVCenter
        }
    }
    Component {
        id: batteryModuleComponent
        BatteryIndicator {
            visible: root._moduleVisible("battery")
                && (root.useShortenedForm < 2 && Battery.available)
            Layout.alignment: Qt.AlignVCenter
        }
    }

    Component {
        id: leftSidebarButtonComponent
        LeftSidebarButton {
            visible: root._moduleVisible("leftSidebarButton")
            Layout.alignment: Qt.AlignVCenter
            buttonPadding: 5 * Appearance.sizes.barModuleScale
            colBackground: buttonHovered
                ? (root.auroraEverywhere
                    ? Appearance.aurora.colSubSurfaceHover
                    : Appearance.colors.colLayer1Hover)
                : "transparent"
        }
    }

    Component {
        id: distroIconComponent
        DistroIcon {
            visible: root._moduleVisible("distroIcon")
            Layout.alignment: Qt.AlignVCenter
        }
    }

    Component {
        id: activeWindowComponent
        Item {
            id: awWrapper
            property bool fillSlot: true
            implicitWidth: fillSlot ? 0 : Math.min(_awItem.contentImplicitWidth, _awItem.maxContentWidth)
            implicitHeight: Appearance.sizes.baseBarHeight
            clip: true
            Behavior on implicitWidth {
                enabled: !awWrapper.fillSlot && Appearance.animationsEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementResize.duration
                    easing.type: Appearance.animation.elementResize.type
                    easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                }
            }
            ActiveWindow {
                id: _awItem
                anchors.fill: parent
                visible: root._moduleVisible("activeWindow")
                    && root.useShortenedForm === 0 && !root.taskbarEnabled
            }
            Loader {
                id: _tbLoader
                anchors.fill: parent
                active: root.taskbarEnabled
                visible: active
                sourceComponent: BarTaskbar {
                    parentWindow: root.QsWindow.window
                    slotSize: _tbLoader.height
                }
            }
        }
    }

    // The physical Screen Edge's single inverted frame owns the inward
    // shadow, including this Bar's corners. No local duplicate renderer.

    Rectangle {
        id: barBackground
        readonly property bool auroraEverywhere:
            root.surfaceDialect === "aurora" || root.angelEverywhere
        readonly property bool gameModeMinimal: Appearance.gameModeMinimal
        readonly property int cornerStyle: 0
        readonly property bool zzzGlassActive: root.zzzEverywhere
            && Appearance.effectsEnabled
            && (Config.options?.appearance?.zzz?.glass ?? true)
        readonly property bool floatingStyle: false

        anchors {
            fill: parent
            margins: 0
        }
        readonly property real barMargin: 0
        readonly property bool isBottom: Config.options?.bar?.bottom ?? false
        readonly property QtObject blendedColors: root.blendedColors

        // Hug background is structural connected chrome. Fullscreen/GameMode
        // may disable expensive effects, but it must never hide the Bar body.
        // The PanelWindow remains mapped; compositor stacking covers it while a
        // fullscreen client is active and reveals it again without remapping.
        visible: true
        opacity: root.regaliaEverywhere ? 1
            : Math.max(0, Math.min(1, Config.options?.bar?.opacity ?? 1))
        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        color: {
            if (root.zzzEverywhere) {
                const zzzBase = cornerStyle === 3
                    ? Appearance.zzz.chromeAlt : Appearance.zzz.chrome
                return barBackground.zzzGlassActive ? "transparent" : zzzBase
            }
            if (root.regaliaEverywhere) return "transparent"
            if (root.angelEverywhere) {
                const base = blendedColors?.colLayer0 ?? Appearance.colors.colLayer0
                if (root.nativeBlurActive)
                    return ColorUtils.transparentize(
                        base, Appearance.angel.compositorPanelTransparentize)
                return ColorUtils.applyAlpha(base, 1)
            }
            if (root.alisEverywhere) return Appearance.alis.colLayer0
            if (auroraEverywhere) {
                const base = blendedColors?.colLayer0 ?? Appearance.colors.colLayer0
                if (root.nativeBlurActive)
                    return ColorUtils.transparentize(
                        base, Appearance.aurora.compositorOverlayTransparentize)
                return ColorUtils.applyAlpha(base, 1)
            }
            if (root.cardStyleEverywhere || cornerStyle === 3)
                return Appearance.colors.colLayer1
            return Appearance.colors.colLayer0
        }
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        RegaliaPlate {
            anchors.fill: parent
            visible: root.regaliaEverywhere
            fillColor: barBackground.floatingStyle
                ? Appearance.regalia.barSurfaceFloating
                : Appearance.regalia.barSurface
            radius: barBackground.radius
            inset: barBackground.floatingStyle
                ? Appearance.regalia.surfaceInset : Appearance.regalia.controlInset
            elevated: barBackground.floatingStyle
            deepFrame: !barBackground.floatingStyle
            glassEnabled: true
        }

        radius: {
            if (root.zzzEverywhere) return 0
            const customRounding = Config.options?.bar?.customRounding ?? -1
            if (customRounding >= 0) return customRounding
            if (root.regaliaEverywhere)
                return (cornerStyle === 1 || cornerStyle === 3)
                    ? Appearance.regalia.roundLarge : 0
            if (root.angelEverywhere)
                return (cornerStyle === 1 || cornerStyle === 3)
                    ? Appearance.angel.roundingNormal : 0
            if (root.alisEverywhere)
                return (cornerStyle === 1 || cornerStyle === 3)
                    ? Appearance.alis.roundingNormal : 0
            if (floatingStyle)
                return cornerStyle === 3
                    ? Appearance.rounding.normal : Appearance.rounding.windowRounding
            return 0
        }

        readonly property real zzzRoundEdge:
            (root.zzzEverywhere && Appearance.zzz.round)
                ? Appearance.zzz.panelRadius : -1
        readonly property bool zzzHugCorners: zzzRoundEdge >= 0 && cornerStyle === 0
        readonly property bool zzzAllCorners: zzzRoundEdge >= 0 && floatingStyle
        topLeftRadius: (zzzAllCorners || zzzHugCorners) ? zzzRoundEdge : radius
        topRightRadius: (zzzAllCorners || zzzHugCorners) ? zzzRoundEdge : radius
        bottomLeftRadius: (zzzAllCorners || zzzHugCorners) ? zzzRoundEdge : radius
        bottomRightRadius: (zzzAllCorners || zzzHugCorners) ? zzzRoundEdge : radius
        Behavior on topLeftRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on topRightRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on bottomLeftRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on bottomRightRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        border.width: {
            if (root.zzzEverywhere) return 1
            if (root.regaliaEverywhere) return 0
            if (root.angelEverywhere) return Appearance.angel.panelBorderWidth
            if (root.alisEverywhere)
                return (cornerStyle === 1 || cornerStyle === 3) ? 1 : 0
            if (auroraEverywhere) return floatingStyle ? 1 : 0
            return floatingStyle ? 1 : 0
        }
        Behavior on border.width {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        border.color: {
            if (root.zzzEverywhere) return Appearance.zzz.hairline
            if (root.regaliaEverywhere) return "transparent"
            if (root.angelEverywhere) return Appearance.angel.colPanelBorder
            if (root.alisEverywhere) return Appearance.alis.colBorder
            if (auroraEverywhere) return Appearance.aurora.colTooltipBorder
            return Appearance.colors.colLayer0Border
        }
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        clip: true

        ZzzGlassWash {
            anchors.fill: parent
            maskRadius: barBackground.zzzRoundEdge >= 0
                ? barBackground.zzzRoundEdge : barBackground.radius
            chamfer: 0
            glassEnabled: barBackground.zzzGlassActive
            selfBacked: true
            veilAlpha: Appearance.zzz.dark ? 0.78 : 0.82
            z: -1
        }

        layer.enabled: auroraEverywhere && !root.alisEverywhere
            && !root.zzzEverywhere && !gameModeMinimal
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle {
                width: barBackground.width
                height: barBackground.height
                radius: barBackground.radius
            }
        }

        Image {
            id: blurredWallpaper
            x: -barBackground.barMargin
            y: barBackground.isBottom
                ? -(root.screen?.height ?? 1080) + barBackground.height + barBackground.barMargin
                : -barBackground.barMargin
            width: root.screen?.width ?? 1920
            height: root.screen?.height ?? 1080
            visible: barBackground.auroraEverywhere
                && !root.alisEverywhere && !root.zzzEverywhere
                && !barBackground.gameModeMinimal && !root.nativeBlurActive
            source: visible ? root.wallpaperUrl : ""
            fillMode: Image.PreserveAspectCrop
            cache: true
            sourceSize.width: root.screen?.width ?? 1920
            sourceSize.height: root.screen?.height ?? 1080
            asynchronous: true

            layer.enabled: Appearance.effectsEnabled
                && barBackground.auroraEverywhere
                && !root.alisEverywhere && !root.nativeBlurActive
            layer.effect: MultiEffect {
                source: blurredWallpaper
                anchors.fill: source
                saturation: root.angelEverywhere
                    ? (Appearance.angel.blurSaturation * Appearance.angel.colorStrength)
                    : (Appearance.effectsEnabled ? 0.2 : 0)
                blurEnabled: Appearance.effectsEnabled
                blurMax: 64
                blur: Appearance.effectsEnabled
                    ? (root.angelEverywhere ? Appearance.angel.blurIntensity : 1)
                    : 0
            }

            Rectangle {
                anchors.fill: parent
                color: root.angelEverywhere
                    ? ColorUtils.transparentize(
                        (barBackground.blendedColors?.colLayer0
                            ?? Appearance.colors.colLayer0Base),
                        Appearance.angel.overlayOpacity
                            * Appearance.angel.panelTransparentize)
                    : ColorUtils.transparentize(
                        (barBackground.blendedColors?.colLayer0
                            ?? Appearance.colors.colLayer0Base),
                        Appearance.aurora.overlayTransparentize)
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Appearance.angel.insetGlowHeight
            visible: root.angelEverywhere
            color: Appearance.angel.colInsetGlow
        }

        AngelPartialBorder {
            targetRadius: barBackground.radius
        }

        ZzzTechFrame {
            margin: 6
            showGrid: false
            showCornerMarks: false
            showLabels: false
            showTicks: false
            accentColor: Appearance.zzz.chromeStroke
        }

        BarCavaVisualizer {
            anchors.fill: parent
            active: root.barSpectrumVisible
            points: active ? barCavaProcess.points : []
            normalizationCeiling: active ? barCavaProcess.normalizationCeiling : 100
            visualizerType: root.barSpectrumType
            spectrumOpacity: root.barSpectrumOpacity
            fillRatio: root.barSpectrumFillRatio
            spectrumColor: root.barSpectrumColor
            barsOrigin: root.barSpectrumBarsOrigin
            pixelsPerBar: root.barSpectrumDensity
            barSpacing: root.barSpectrumGap
            smoothing: root.barSpectrumSmoothing
            waveMode: root.barSpectrumWaveMode
            lineWidth: root.barSpectrumLineWidth
            edgeInset: root.barSpectrumEdgeInset
            edgeSoftness: root.barSpectrumEdgeSoftness
            frequencyProfile: root.barSpectrumFrequencyProfile
            accentStrength: root.barSpectrumAccentStrength
            waveStripCap: root.barSpectrumWaveSampleCap
            topLeftRadius: barBackground.topLeftRadius
            topRightRadius: barBackground.topRightRadius
            bottomLeftRadius: barBackground.bottomLeftRadius
            bottomRightRadius: barBackground.bottomRightRadius
        }
    }

    FocusedScrollMouseArea {
        id: barLeftSideMouseArea
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
        }
        width: Math.max(implicitWidth, middleSection.leftPillX)
        implicitWidth: leftSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: root.performScrollAction(root.leftAction, false)
        onScrollUp: root.performScrollAction(root.leftAction, true)
        onMovedAway: root.closeOSD(root.leftAction)
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                ShellLayoutController.toggleSidebarAtSlot("left");
            else if (event.button === Qt.RightButton)
                root.openBarContextMenu(event.x, event.y, barLeftSideMouseArea)
        }

        ScrollHint {
            id: leftScrollHint
            reveal: barLeftSideMouseArea.hovered
                && (Config.options?.bar?.showScrollHints ?? true)
                && root.leftAction !== "none"
            icon: root.getScrollIcon(root.leftAction)
            tooltipText: root.getScrollTooltip(root.leftAction)
            side: "left"
            x: Appearance.rounding.screenRounding
                - implicitWidth - Appearance.sizes.spacingSmall
            anchors.verticalCenter: parent.verticalCenter
            z: 1
        }

        RowLayout {
            id: leftSectionRowLayout
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.edgeInset
            anchors.rightMargin: root.leftZoneGap
            spacing: root.moduleGap

            Repeater {
                model: root._leftIds
                delegate: EdgeZoneCell { zone: "left" }
            }
        }
    }

    Item {
        id: middleSection
        z: root.horizontalUtilitiesCompact ? 2 : 0
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }

        readonly property real leftPillX: leftCenterGroup.width > 0
            ? leftCenterGroup.x : middleCenterGroup.x
        readonly property real rightPillEndX: rightCenterGroup.width > 0
            ? (rightCenterGroup.x + rightCenterGroup.width)
            : (middleCenterGroup.x + middleCenterGroup.width)

        BarGroup {
            id: middleCenterGroup
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            padding: 4 * Appearance.sizes.barModuleScale
            moduleSpacing: root.moduleGap
            visible: !empty

            Repeater {
                model: root._centerIds
                delegate: Loader {
                    required property string modelData
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: root._fillWidth(modelData, "center")
                    Layout.fillHeight: root._fillHeight(modelData)
                    active: root._moduleShown(modelData, "center")
                    visible: active
                    sourceComponent: root._allComponents[modelData] ?? null
                    onLoaded: if (modelData === "activeWindow" && item)
                        item.fillSlot = false
                }
            }
        }

        VerticalBarSeparator {
            id: leftSeparator
            visible: (Config.options?.bar.borderless ?? false)
                && !leftCenterGroup.empty && !middleCenterGroup.empty
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: middleCenterGroup.left
            anchors.rightMargin: root.leftPivotGap / 2
            height: Appearance.sizes.baseBarHeight / 3
        }

        BarGroup {
            id: leftCenterGroup
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: (Config.options?.bar.borderless ?? false)
                ? leftSeparator.left : middleCenterGroup.left
            anchors.rightMargin: (Config.options?.bar.borderless ?? false)
                ? root.leftPivotGap / 2 : root.leftPivotGap
            visible: !empty
            implicitWidth: empty ? 0
                : root._pillWidth(contentWidth, root.leftCenterMaxWidth)
            clipContent: !(root.horizontalUtilitiesCompact
                && root._zoneContains(root._centerLeftIds, "utilButtons"))
            moduleSpacing: root.moduleGap
            contentHorizontalAlignment: Qt.AlignRight

            Repeater {
                model: root._centerLeftIds
                delegate: Loader {
                    required property string modelData
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: root._fillWidth(modelData, "centerLeft")
                    Layout.fillHeight: root._fillHeight(modelData)
                    active: root._moduleShown(modelData, "centerLeft")
                    visible: active
                    sourceComponent: root._allComponents[modelData] ?? null
                    onLoaded: if (modelData === "activeWindow" && item)
                        item.fillSlot = false
                }
            }
        }

        VerticalBarSeparator {
            id: rightSeparator
            visible: (Config.options?.bar.borderless ?? false)
                && !rightCenterGroupPill.empty && !middleCenterGroup.empty
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: middleCenterGroup.right
            anchors.leftMargin: root.rightPivotGap / 2
            height: Appearance.sizes.baseBarHeight / 3
        }

        Item {
            id: rightCenterGroup
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: (Config.options?.bar.borderless ?? false)
                ? rightSeparator.right : middleCenterGroup.right
            anchors.leftMargin: (Config.options?.bar.borderless ?? false)
                ? root.rightPivotGap / 2 : root.rightPivotGap
            visible: !rightCenterGroupPill.empty
            implicitWidth: rightCenterGroupPill.empty ? 0 : rightCenterGroupPill.width
            implicitHeight: rightCenterGroupPill.height
            readonly property real contentWidth: rightCenterGroupPill.contentWidth

            property int _tapSeq: 0
            property bool _confirmFx: false
            Timer {
                id: _tapSeqTimer
                interval: 500
                onTriggered: rightCenterGroup._tapSeq = 0
            }
            Timer {
                id: _fxResetTimer
                interval: 2000
                onTriggered: rightCenterGroup._confirmFx = false
            }

            BarGroup {
                id: rightCenterGroupPill
                anchors.verticalCenter: parent.verticalCenter
                visible: !empty
                implicitWidth: empty ? 0
                    : root._pillWidth(contentWidth, root.rightCenterMaxWidth)
                clipContent: !(root.horizontalUtilitiesCompact
                    && root._zoneContains(root._centerRightIds, "utilButtons"))
                moduleSpacing: root.moduleGap
                contentHorizontalAlignment: Qt.AlignLeft

                Repeater {
                    model: root._centerRightIds
                    delegate: Loader {
                        required property string modelData
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: root._fillWidth(modelData, "centerRight")
                        Layout.fillHeight: root._fillHeight(modelData)
                        active: root._moduleShown(modelData, "centerRight")
                        visible: active
                        sourceComponent: root._allComponents[modelData] ?? null
                        onLoaded: if (modelData === "activeWindow" && item)
                            item.fillSlot = false
                    }
                }
            }

            MouseArea {
                anchors.fill: rightCenterGroupPill
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                z: -1
                onPressed: event => {
                    if (event.button === Qt.RightButton) {
                        GlobalStates.controlPanelOpen = !GlobalStates.controlPanelOpen;
                    } else {
                        ShellLayoutController.toggleSidebarAtSlot("right");
                        rightCenterGroup._tapSeq++;
                        _tapSeqTimer.restart()
                        if (rightCenterGroup._tapSeq >= 3) {
                            rightCenterGroup._confirmFx = true;
                            rightCenterGroup._tapSeq = 0;
                            _fxResetTimer.restart()
                        }
                    }
                }
            }

            Repeater {
                model: rightCenterGroup._confirmFx ? 3 : 0
                Text {
                    property int _delay: index * 120
                    text: "🫃🏻"
                    font.pixelSize: 22
                    x: (rightCenterGroup.width - implicitWidth) / 2 + (index - 1) * 28
                    y: rightCenterGroup.height / 2
                    z: 10
                    scale: 0
                    opacity: 0
                    SequentialAnimation on y {
                        PauseAnimation { duration: _delay }
                        NumberAnimation {
                            to: -20
                            duration: 1200
                            easing.type: Easing.OutCubic
                        }
                    }
                    SequentialAnimation on scale {
                        PauseAnimation { duration: _delay }
                        NumberAnimation {
                            to: 1.3
                            duration: 250
                            easing.type: Easing.OutBack
                        }
                        NumberAnimation { to: 1.0; duration: 200 }
                        PauseAnimation { duration: 500 }
                        NumberAnimation {
                            to: 0
                            duration: 300
                            easing.type: Easing.InBack
                        }
                    }
                    SequentialAnimation on opacity {
                        PauseAnimation { duration: _delay }
                        NumberAnimation { to: 1; duration: 200 }
                        PauseAnimation { duration: 700 }
                        NumberAnimation { to: 0; duration: 350 }
                    }
                }
            }
        }
    }

    FocusedScrollMouseArea {
        id: barRightSideMouseArea
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
        }
        width: Math.max(implicitWidth, root.width - middleSection.rightPillEndX)
        implicitWidth: rightSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: root.performScrollAction(root.rightAction, false)
        onScrollUp: root.performScrollAction(root.rightAction, true)
        onMovedAway: root.closeOSD(root.rightAction)
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                ShellLayoutController.toggleSidebarAtSlot("right");
            } else if (event.button === Qt.RightButton) {
                root.openBarContextMenu(event.x, event.y, barRightSideMouseArea)
            }
        }

        ScrollHint {
            id: rightScrollHint
            reveal: barRightSideMouseArea.hovered
                && (Config.options?.bar?.showScrollHints ?? true)
                && root.rightAction !== "none"
            icon: root.getScrollIcon(root.rightAction)
            tooltipText: root.getScrollTooltip(root.rightAction)
            side: "right"
            x: parent.width - Appearance.rounding.screenRounding
                + Appearance.sizes.spacingSmall
            anchors.verticalCenter: parent.verticalCenter
            z: 1
        }

        RowLayout {
            id: rightSectionRowLayout
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.leftMargin: root.rightZoneGap
            anchors.rightMargin: root.edgeInset
            spacing: root.moduleGap
            layoutDirection: Qt.RightToLeft

            Repeater {
                model: root._rightIds
                delegate: EdgeZoneCell { zone: "right" }
            }
        }
    }

    Component {
        id: timerComponent
        TimerIndicator { Layout.alignment: Qt.AlignVCenter }
    }
    Component {
        id: shellUpdateComponent
        ShellUpdateIndicator { Layout.alignment: Qt.AlignVCenter }
    }
    Component {
        id: spacerComponent
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: root._spacerMinimumWidth
            implicitWidth: root._spacerMinimumWidth
            Behavior on implicitWidth {
                enabled: Appearance.animationsEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementResize.duration
                    easing.type: Appearance.animation.elementResize.type
                    easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                }
            }
        }
    }
    Component {
        id: trayComponent
        SysTray {
            visible: root._moduleVisible("sysTray") && root.useShortenedForm === 0
            Layout.fillWidth: false
            Layout.fillHeight: true
            invertSide: Config.options?.bar?.bottom ?? false
        }
    }
    Component {
        id: weatherComponent
        Loader {
            active: root._moduleVisible("weather")
                && (Config.options?.bar?.weather?.enable ?? false)
            visible: active
            sourceComponent: BarGroup {
                WeatherBar {}
            }
        }
    }
    Component {
        id: rightSidebarButtonComponent
        RippleButton {
            id: rightSidebarButton
            cookieMorphing: true
            visible: root._moduleVisible("rightSidebarButton")
            Accessible.name: Translation.tr("Toggle right sidebar")

            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.fillWidth: false
            implicitWidth: 30 * Appearance.sizes.barModuleScale
            implicitHeight: 30 * Appearance.sizes.barModuleScale

            buttonRadius: Appearance.rounding.full
            colBackground: buttonHovered
                ? Appearance.colors.colLayer1Hover : "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive

            toggled: ShellLayoutController.sidebarOpenAtSlot("right")
            property color colText: toggled
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnLayer0
            onPressed: ShellLayoutController.toggleSidebarAtSlot("right")

            MaterialSymbol {
                anchors.centerIn: parent
                text: "right_panel_open"
                iconSize: Math.round(20 * Appearance.sizes.barModuleScale)
                color: rightSidebarButton.colText
            }
        }
    }
}
