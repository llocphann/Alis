#!/usr/bin/env python3
"""Regression contract for the freeform Dashboard canvas and adaptive modules."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

def require(text: str, token: str, source: str) -> None:
    if token not in text:
        raise AssertionError(f"{source} missing Dashboard freeform token: {token!r}")

def forbid(text: str, token: str, source: str) -> None:
    if token in text:
        raise AssertionError(f"{source} contains retired Dashboard token: {token!r}")

def main() -> None:
    content = read("modules/dashboard/DashboardContent.qml")
    canvas = read("modules/dashboard/DashboardCanvas.qml")
    grid = read("modules/dashboard/DashboardEditGrid.qml")
    guides = read("modules/dashboard/DashboardAlignmentGuides.qml")
    header = read("modules/dashboard/DashboardHeader.qml")
    toolbar = read("modules/dashboard/DashboardEditToolbar.qml")
    standalone = read("modules/dashboard/Dashboard.qml")
    overview = read("modules/overview/OverviewDashboard.qml")
    overview_shell = read("modules/overview/Overview.qml")
    abyss_toolbar_host = read("modules/abyss/AbyssDashboardEditPopup.qml")
    abyss_content = read("modules/abyss/content/AbyssDashboardContent.qml")
    abyss_perimeter = read("modules/abyss/AbyssPerimeter.qml")
    abyss_controller = read("modules/abyss/AbyssSurfaceController.qml")
    system = read("modules/dashboard/DashSystem.qml")
    calendar_widget = read("modules/sidebarRight/calendar/CalendarWidget.qml")
    weather = read("modules/dashboard/DashWeather.qml")
    orbital = read("modules/bar/weather/OrbitalWeather.qml")
    calendar = read("modules/dashboard/DashCalendar.qml")
    month = read("modules/common/widgets/ObsidianMonthCalendar.qml")
    media = read("modules/dashboard/DashMedia.qml")
    welcome = read("modules/dashboard/DashWelcome.qml")
    todo = read("modules/dashboard/DashTodo.qml")
    dash_card = read("modules/dashboard/DashCard.qml")
    config = read("modules/common/Config.qml")
    defaults = read("defaults/config.json")
    settings = read("modules/settings/DashboardConfig.qml")

    require(content, "DashboardCanvas {", "DashboardContent.qml")
    require(canvas, "import qs.modules.common.functions", "DashboardCanvas.qml")
    forbid(canvas, "id: editToolbar", "DashboardCanvas.qml")
    forbid(canvas, "showStandaloneEditButton", "DashboardCanvas.qml")
    forbid(content, "component WidgetColumn:", "DashboardContent.qml")
    forbid(content, "dashboard.layout.", "DashboardContent.qml")

    for token in (
        'color: root.embeddedSurface ? "transparent" : Appearance.colors.colLayer0',
        'radius: root.embeddedSurface ? 0 : Appearance.rounding.large',
        "border.width: 0",
    ):
        require(content, token, "DashboardContent.qml")
    for token in (
        "ColorQuantizer {",
        "AdaptedMaterialScheme {",
        "ZzzPanelBackdrop {",
        "ZzzPlate {",
        "id: blurredWallpaper",
        "useWallpaperBackdrop",
        "wallpaperDominantColor",
    ):
        forbid(content, token, "DashboardContent.qml")

    for token in (
        'Config.options?.dashboard?.canvas?.widgets',
        'property bool editMode: false',
        'function beginMove(',
        'function beginResize(',
        'function updateInteraction(',
        'function finishInteraction(',
        'function _snapshotVisibleRects(',
        'function _resolveLayout(',
        'function _resolveNeighbour(',
        'function _resolveFeasibleLayout(',
        'localResizeOnly',
        'const directlyAffected = ({})',
        '&& root._rectsOverlap(',
        'state.kind === "resize"',
        'function _layoutHasOverlap(',
        'function _persistPreviewLayout(',
        'function _smartAlignMove(',
        'function _smartAlignResize(',
        'property var _smartGuides: []',
        'property var _smartSnapAxes: ({ x: false, y: false })',
        'readonly property real smartGuideThreshold:',
        'DashboardAlignmentGuides {',
        'A restored widget must join the same collision contract as drag/resize.',
        'const resolved = root._resolveNeighbour(',
        'base, id, obstacles, true)',
        'case "system": return { width: 260, height: 180 }',
        'baselineRects: root._snapshotVisibleRects()',
        'root._applyPreviewRects(resolved)',
        'A dragged module is temporarily lifted out of the packed layout.',
        'Drop is the insertion point: resolve neighbours exactly',
        'function _snapRectForCommit(',
        'Pointer tracking ends before the final target is published.',
        'readonly property bool animateGeometry:',
        'readonly property real collisionGap: Math.max(8,',
        'enabled: root.editMode',
        'enabled: !root.editMode',
        'DashboardEditGrid {',
        'Config.options?.dashboard?.canvas?.gridSize',
        'Config.options?.dashboard?.canvas?.gridStyle',
        'Config.options?.dashboard?.canvas?.snap',
        'Config.options?.dashboard?.canvas?.autoAdjustSize',
        'readonly property bool autoAdjustSizeEnabled:',
        'state.kind === "resize"',
        '&& root.autoAdjustSizeEnabled',
        'allowResize',
    ):
        require(canvas, token, "DashboardCanvas.qml")

    for edge in ("n", "s", "e", "w", "nw", "ne", "sw", "se"):
        require(canvas, f'edge: "{edge}"', "DashboardCanvas.qml")

    for token in (
        "model: root._allIds",
        "root._entryFor(id).visible !== false",
        "root._entryFor(id).visible === false",
        "active: cardWrap.visible",
        "prevents Repeater/model churn",
    ):
        require(canvas, token, "DashboardCanvas.qml")
    forbid(canvas,
        "root.geometryFor(id).visible !== false",
        "DashboardCanvas visibility model")
    forbid(canvas,
        "model: root.visibleIds",
        "DashboardCanvas repeater model")

    move_start = canvas.index('if (state.kind === "move") {')
    move_end = canvas.index('const edge = String(state.edge ?? "")', move_start)
    move_block = canvas[move_start:move_end]
    require(move_block,
        "root._smartAlignMove(state.id, {",
        "DashboardCanvas move block")
    require(move_block,
        "root._setPreview(state.id, guided)",
        "DashboardCanvas move block")
    forbid(move_block, "root._resolveFeasibleLayout(", "DashboardCanvas move block")
    forbid(move_block, "root._snap(", "DashboardCanvas move block")
    # Drag/drop may move neighbours but must never resize them; size adaptation
    # is exclusive to resize interactions and controlled by autoAdjustSize.
    resolve_start = canvas.index("function _candidateInRegion(")
    resolve_end = canvas.index("function _applyPreviewRects(", resolve_start)
    resolve_block = canvas[resolve_start:resolve_end]
    require(resolve_block, "allowResize", "DashboardCanvas collision resolver")
    require(resolve_block,
        "const width = allowResize", "DashboardCanvas collision resolver")
    require(resolve_block,
        "const heights = allowResize ?", "DashboardCanvas collision resolver")

    finish_start = canvas.index("function finishInteraction(commit)")
    finish_end = canvas.index("function _cycleGridSize()", finish_start)
    finish_block = canvas[finish_start:finish_end]
    require(finish_block, "root._resolveFeasibleLayout(", "DashboardCanvas drop block")
    require(finish_block, "root._persistPreviewLayout()", "DashboardCanvas drop block")
    require(finish_block, "root._snapRectForCommit(", "DashboardCanvas drop block")
    require(finish_block,
        "root._smartSnapAxes.x, root._smartSnapAxes.y",
        "DashboardCanvas smart-guide commit block")
    require(finish_block,
        'const allowResize = state.kind === "resize"',
        "DashboardCanvas drop block")
    require(finish_block,
        "&& root.autoAdjustSizeEnabled",
        "DashboardCanvas drop block")
    require(finish_block, "root._interaction = null", "DashboardCanvas drop block")
    require(finish_block, "Qt.callLater(() => {", "DashboardCanvas drop block")

    for token in (
        'property string gridStyle: "dots"',
        'gridStyle === "lines"',
        'gridStyle === "cross"',
    ):
        require(grid, token, "DashboardEditGrid.qml")

    for token in (
        'kind === "vertical"',
        'kind === "horizontal"',
        'kind === "diagonal"',
        'kind === "spacingH"',
        'kind === "spacingV"',
        'String(Math.max(0, Math.round(Number(value ?? 0)))) + " px"',
        "root.arrowHead(ctx",
    ):
        require(guides, token, "DashboardAlignmentGuides.qml")

    require(header, 'root.editMode ? "done" : "edit"', "DashboardHeader.qml")
    require(header, "onClicked: root.editModeRequested()", "DashboardHeader.qml")

    for token in (
        "required property var canvasController",
        "visible: root.editing",
        "bottomLeftRadius: root.abyssMode ? radius : 0",
        "bottomRightRadius: root.abyssMode ? radius : 0",
        'Translation.tr("Edit widgets")',
        "id: editActions",
        "horizontalAlignment: Text.AlignHCenter",
        "focusPolicy: Qt.StrongFocus",
        "root.canvasController.toggleAutoAdjustSize()",
        "border.width: tool.visualFocus ? 2 : (tool.toggled ? 1 : 0)",
        "id: toolbarRow",
        "id: editActions",
        "id: availableModulesViewport",
        "id: availableModulesRow",
        "readonly property real toolbarRowNaturalWidth:",
        "root.availableModulesNaturalWidth",
        "Layout.preferredWidth: root.availableModulesNaturalWidth",
        "flickableDirection: Flickable.HorizontalFlick",
        "interactive: contentWidth > width",
        "implicitWidth: Math.ceil(Math.max(",
        "toolbarTitle.implicitWidth",
        "root.toolbarRowNaturalWidth",
        "readonly property real horizontalPadding: root.abyssMode",
    ):
        require(toolbar, token, "DashboardEditToolbar.qml")
    forbid(toolbar, "Flow {", "DashboardEditToolbar.qml")

    # Edit toolbar is above the Abyss body and must register a native region:
    # painting the buttons alone is insufficient with a masked PanelWindow.
    for token in (
        'import Quickshell',
        'readonly property rect toolbarInputBounds: root.enabled',
        'readonly property Region toolbarInputRegion: Region {',
        'nativeInputRegion: root.toolbarInputRegion',
        'inputBounds: root.toolbarInputBounds',
        'onActivated: root.canvasController.cancelEditMode()',
    ):
        require(abyss_toolbar_host, token, "AbyssDashboardEditPopup.qml")
    require(abyss_controller, 'participants[key]?.nativeInputRegion',
            "AbyssSurfaceController.qml")
    require(abyss_perimeter,
            'Region { regions: window.presented && field.ready ? liquid.nativeInputRegions : [] }',
            "AbyssPerimeter.qml")

    # Escape #1 must use exactly the Cancel/discard branch before outer close;
    # the next Escape is handled by the pre-existing window dismissal.
    edit_esc = content.split('function handleEscape(): bool {', 1)[1].split(
        'function openPlannerEventEditor', 1)[0]
    assert edit_esc.index('if (dashboardCanvas.editMode) {') < edit_esc.index(
        'if (dashboardHeader.cancelPageDrag()) return true')
    require(edit_esc, 'dashboardCanvas.cancelEditMode()', "DashboardContent.qml")
    for txt, name in (
        (standalone, "Dashboard.qml"),
        (overview, "OverviewDashboard.qml"),
        (abyss_toolbar_host, "AbyssDashboardEditPopup.qml"),
    ):
        require(txt, 'sequences: ["Escape"]', name)
        require(txt, 'context: Qt.WindowShortcut', name)
    require(overview_shell,
            'dashboardPanel.item?.handleEscape()', "Overview.qml")
    require(abyss_content, 'return content.handleEscape()', "AbyssDashboardContent.qml")
    require(abyss_perimeter, 'dashboardBody.contentItem.item.handleEscape()',
            "AbyssPerimeter.qml")

    # Icon/button centering and the occasional ninth button must not overflow
    # an eighth-column-only layout.
    for token in (
        "readonly property int visibleActionCount:",
        "Math.min(root.visibleActionCount,",
        "Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter",
        "implicitWidth: tool.implicitWidth",
        "implicitHeight: tool.implicitHeight",
        "horizontalAlignment: Text.AlignHCenter",
        "verticalAlignment: Text.AlignVCenter",
    ):
        require(toolbar, token, "DashboardEditToolbar.qml")

    # The adaptive GridLayout is assigned the toolbar's width; feeding its
    # implicit width back into that same width creates a sizing cycle.
    forbid(toolbar, "editActions.implicitWidth", "Dashboard toolbar width dependency")
    for source, text in (
        ("Dashboard.qml", standalone),
        ("OverviewDashboard.qml", overview),
    ):
        require(text, "DashboardEditToolbar {", source)
    require(overview,
        "x: Math.round(dashContainer.x", "OverviewDashboard.qml")
    require(overview,
        "y: root.embeddedSurface ? 0 : Math.round(dashContainer.y - height + 1)", "OverviewDashboard.qml")
    require(overview,
        "dashboardEditToolbar.implicitWidth", "OverviewDashboard.qml")
    require(standalone,
        "x: Math.round((parent.width - width) / 2)", "Dashboard.qml")
    require(standalone,
        "standaloneEditToolbar.implicitWidth", "Dashboard.qml")
    require(standalone, "y: 0", "Dashboard.qml")
    forbid(overview, "width: Math.min(440,", "OverviewDashboard.qml")
    forbid(standalone, "width: Math.min(440,", "Dashboard.qml")

    require(welcome,
        "layer.enabled: root.visible && status === Image.Ready",
        "DashWelcome.qml")
    forbid(welcome,
        "GlobalStates.dashboardOpen || GlobalStates.overviewOpen",
        "DashWelcome avatar mask lifecycle")
    require(todo, "Layout.minimumHeight: root.veryShallowLayout", "DashTodo.qml")
    require(todo, "? 8 : (root.shallowLayout ? 56 : 72)", "DashTodo.qml")

    require(canvas, "cursorShape: root.editMode", "DashboardCanvas.qml")
    require(canvas, ": Qt.ArrowCursor", "DashboardCanvas.qml")
    require(canvas, "width: corner ? 8 : (horizontal ? 24 : 6)", "DashboardCanvas.qml")
    require(canvas, "height: corner ? 8 : (vertical ? 24 : 6)", "DashboardCanvas.qml")
    require(canvas, "anchors.margins: -4", "DashboardCanvas.qml")

    for token in (
        "Behavior on x {",
        "Behavior on y {",
        "Behavior on width {",
        "Behavior on height {",
        "Appearance.animation.elementMoveFast.duration",
        "Appearance.animation.elementResize.duration",
        "&& cardWrap.animateGeometry",
    ):
        require(canvas, token, "DashboardCanvas.qml")

    # System monitor is intentionally card-based now: compact utilization
    # tiles with history sparklines, secondary thermal/storage chips, and one
    # integrated ThinkFan panel. Keep the freeform contract focused on its
    # adaptive primitives rather than the retired three vertical meters.
    for token in (
        "component MetricTile: Rectangle",
        "component StatusChip: Rectangle",
        "columns: 3",
        "history: ResourceUsage.cpuUsageHistory",
        "history: ResourceUsage.memoryUsageHistory",
        "history: ResourceUsage.gpuUsageHistory",
        "Graph {",
        "ThinkFanService.refresh()",
        "ThinkFanService.applyProfile(",
        'text: Translation.tr("Fan control")',
        'Translation.tr("RPM:")',
        "ThinkFanService.fanRpm",
        "ThinkFanService.fanLevel",
        "StyledSwitch {",
    ):
        require(system, token, "DashSystem.qml")
    forbid(system, "component VerticalBar:", "DashSystem.qml")
    require(calendar_widget,
        "anchors.verticalCenter: root.dashboardAdaptive",
        "CalendarWidget.qml")
    require(month,
        "? Math.max(root.implicitWidth, root.width)",
        "ObsidianMonthCalendar.qml")

    for token in (
        "radius: Appearance.rounding.small",
        "readonly property color sidebarRaisedSurface: Config.options?.panelFamily === \"abyss\" ? AbyssStyle.contentLayer : Appearance.colors.colLayer1",
        "root.sidebarRaisedSurface",
        "border.width: 0",
        'border.color: "transparent"',
    ):
        require(dash_card, token, "DashCard.qml")
    for token in (
        "AngelPartialBorder {",
        "ZzzGraphicPlate {",
        "gradient: Gradient {",
    ):
        forbid(dash_card, token, "DashCard.qml")

    require(weather, "OrbitalWeather {", "DashWeather.qml")
    for token in (
        "function hourFromLabel(label): real",
        "function arcAngle(",
        "function orbitAngleForHour(",
    ):
        require(orbital, token, "OrbitalWeather.qml")

    require(calendar, "dashboardAdaptive: true", "DashCalendar.qml")
    for token in (
        "property bool autoWeekNumbers: false",
        "readonly property bool effectiveWeekNumbers:",
        "function isoWeekNumber(value): int",
        'text: Translation.tr("WK")',
    ):
        require(month, token, "ObsidianMonthCalendar.qml")

    require(media, "import qs.modules.mediaControls", "DashMedia.qml")
    require(media, "EqualizerPanel {", "DashMedia.qml")
    require(media, "active: root.showEqualizer && root.presentationActive && root.visible", "DashMedia.qml")
    require(canvas, "presentationActive: root.presentationActive", "DashboardCanvas.qml")

    for token in (
        "property JsonObject canvas: JsonObject {",
        "property int gridSize: 24",
        "property bool snap: true",
        "property bool autoAdjustSize: true",
        'property string gridStyle: "dots"',
        "property list<var> widgets:",
    ):
        require(config, token, "Config.qml")

    require(defaults, '"autoAdjustSize": true', "defaults/config.json")

    for token in (
        'title: Translation.tr("Canvas & grid")',
        'Config.setNestedValue("dashboard.canvas.snap", checked)',
        'Config.setNestedValue(\n                        "dashboard.canvas.autoAdjustSize", checked)',
        'Config.setNestedValue("dashboard.canvas.gridStyle", value)',
        'Config.setNestedValue("dashboard.canvas.gridSize", value)',
    ):
        require(settings, token, "DashboardConfig.qml")

    print("Dashboard freeform canvas contract: OK")

if __name__ == "__main__":
    main()
