pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "root:modules/background/widgets/japaneseTypography/JapaneseTypographyPresets.js" as JapanesePresets

// Compact per-widget & surface inspector body embedded inside WidgetManagerPanel.
// Deduplicates Scale/Opacity/Dimming/Background/Blur/Border already shown above it.
Column {
    id: root

    required property string outputName
    required property string layoutKey
    required property string widgetKey
    required property bool isCustom
    required property var customManifest
    required property bool supportsAppearance
    required property bool defaultOn
    required property string configPrefix

    width: parent ? parent.width : 200
    spacing: 6

    readonly property var _cfgEntry: {
        void Config.revision;
        return Config.getNestedValue(root.configPrefix, ({})) ?? ({});
    }
    readonly property string _currentPlacement: {
        void Config.revision;
        return String(Config.getNestedValue(root.configPrefix + ".placementStrategy",
            root._cfgEntry?.placementStrategy ?? "free"));
    }
    readonly property var _zoneOptions: [
        { zone: "topLeft", icon: "north_west" },
        { zone: "topCenter", icon: "north" },
        { zone: "topRight", icon: "north_east" },
        { zone: "centerLeft", icon: "west" },
        { zone: "center", icon: "filter_center_focus" },
        { zone: "centerRight", icon: "east" },
        { zone: "bottomLeft", icon: "south_west" },
        { zone: "bottomCenter", icon: "south" },
        { zone: "bottomRight", icon: "south_east" }
    ]
    readonly property var _paletteWidgets: [
        "clock", "weather", "mediaControls", "visualizer",
        "systemMonitor", "battery", "notes", "calendarUpcoming",
        "uptime", "worldClock", "userCard", "newsTicker"
    ]
    readonly property bool _supportsPalette: root._paletteWidgets.indexOf(root.widgetKey) !== -1
    readonly property bool _supportsPlacement: !root.isCustom && [
        "clock", "weather", "customImage", "imageConverter", "mediaControls",
        "visualizer", "systemMonitor", "battery", "notes", "calendarUpcoming",
        "uptime", "worldClock", "userCard", "newsTicker", "japaneseTypography"
    ].indexOf(root.widgetKey) !== -1

    function _cfg(key: string, defVal) {
        void Config.revision;
        const v = Config.getNestedValue(root.configPrefix + "." + key, undefined);
        return v !== undefined ? v : (root._cfgEntry?.[key] ?? defVal);
    }

    function _setCfg(key: string, val): void {
        Config.setNestedValue(root.configPrefix + "." + key, val);
    }

    function _currentPalettePreset(): string {
        const p = String(root._cfg("palette.primary", "primary"));
        const s = String(root._cfg("palette.secondary", "secondary"));
        const t = String(root._cfg("palette.tertiary", "tertiary"));
        if (p === "primary" && s === "primary" && t === "primary") return "primary";
        if (p === "secondary" && s === "secondary" && t === "secondary") return "secondary";
        if (p === "tertiary" && s === "tertiary" && t === "tertiary") return "tertiary";
        if (p === "primary" && s === "secondary" && t === "tertiary") return "balanced";
        return "custom";
    }

    function _applyPalettePreset(preset: string): void {
        let role = "balanced";
        if (preset === "primary" || preset === "secondary" || preset === "tertiary")
            role = preset;
        const updates = {};
        updates[root.configPrefix + ".palette.primary"] = role === "balanced" ? "primary" : role;
        updates[root.configPrefix + ".palette.secondary"] = role === "balanced" ? "secondary" : role;
        updates[root.configPrefix + ".palette.tertiary"] = role === "balanced" ? "tertiary" : role;
        updates[root.configPrefix + ".palette.signal"] = "signal";
        updates[root.configPrefix + ".palette.surface"] = "surface";
        Config.setNestedValues(updates);
    }

    function _roleColor(role: string): color {
        if (role === "secondary") return Appearance.colors.colSecondary;
        if (role === "tertiary") return Appearance.colors.colTertiary;
        return Appearance.colors.colPrimary;
    }

    function _customConfigSpecs(): var {
        if (!root.isCustom || !root.customManifest?.config) return [];
        const cfg = root.customManifest.config;
        const out = [];
        for (const k of Object.keys(cfg))
            out.push({ key: k, spec: cfg[k] ?? ({}) });
        return out;
    }

    function _manifestOptions(opts): var {
        if (!Array.isArray(opts)) return [];
        return opts.map(o => typeof o === "object"
            ? { label: String(o.label ?? o.name ?? o.value ?? ""), value: String(o.value ?? "") }
            : { label: String(o), value: String(o) });
    }

    // ── Compact Inline Controls ──────────────────────────────────────────
    component CompactSectionHeader: StyledText {
        width: parent ? parent.width : 180
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colPrimary
        elide: Text.ElideRight
    }

    component CompactSwitchRow: RowLayout {
        id: swRow
        property string label: ""
        property string icon: ""
        property bool value: false
        signal toggledByUser(bool nextVal)

        width: parent ? parent.width : 180
        spacing: 6

        MaterialSymbol {
            visible: swRow.icon.length > 0
            text: swRow.icon
            iconSize: 15
            color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.54)
        }
        StyledText {
            Layout.fillWidth: true
            text: swRow.label
            color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.78)
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideRight
        }
        StyledSwitch {
            checked: swRow.value
            onClicked: {
                swRow.toggledByUser(!swRow.value);
                checked = Qt.binding(() => swRow.value);
            }
        }
    }

    component CompactSliderRow: Column {
        id: slRow
        property string label: ""
        property string icon: ""
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property real value: 0
        property string suffix: ""
        signal edited(real nextValue)

        width: parent ? parent.width : 180
        spacing: 2

        RowLayout {
            width: parent.width
            spacing: 5
            MaterialSymbol {
                visible: slRow.icon.length > 0
                text: slRow.icon
                iconSize: 14
                color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.5)
            }
            StyledText {
                Layout.fillWidth: true
                text: slRow.label
                color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.74)
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
            }
            StyledText {
                text: Math.round(slRow.value * 100) / 100 + slRow.suffix
                color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.65)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
            }
        }
        StyledSlider {
            width: parent.width
            from: slRow.from
            to: slRow.to
            stepSize: slRow.stepSize
            configuration: StyledSlider.Configuration.XS
            stopIndicatorValues: []
            value: slRow.value
            tooltipContent: Math.round(value * 100) / 100 + slRow.suffix
            onMoved: slRow.edited(Math.round(value * 100) / 100)
        }
    }

    component CompactChipFlow: Column {
        id: chipFlow
        property string label: ""
        property var options: [] // [{ label, value, icon? }]
        property string currentValue: ""
        signal chosen(string value)

        width: parent ? parent.width : 180
        spacing: 4

        StyledText {
            visible: chipFlow.label.length > 0
            width: parent.width
            text: chipFlow.label
            color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.7)
            font.pixelSize: Appearance.font.pixelSize.smallest
            elide: Text.ElideRight
        }
        Flow {
            width: parent.width
            spacing: 4

            Repeater {
                model: chipFlow.options
                delegate: RippleButton {
                    id: optChip
                    required property var modelData
                    readonly property bool active: chipFlow.currentValue === String(modelData.value)
                    padding: 0
                    implicitHeight: 24
                    height: 24
                    width: optRow.implicitWidth + 14
                    buttonRadius: Appearance.rounding.full
                    toggled: active
                    colBackground: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.09)
                    colBackgroundToggled: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.18)
                    colBackgroundToggledHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25)
                    downAction: () => chipFlow.chosen(String(optChip.modelData.value))
                    contentItem: Item {
                        implicitWidth: optRow.implicitWidth
                        implicitHeight: optRow.implicitHeight
                        Row {
                            id: optRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                visible: Boolean(optChip.modelData.icon)
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(optChip.modelData.icon ?? "")
                                iconSize: 13
                                color: optChip.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(optChip.modelData.label ?? optChip.modelData.displayName ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: optChip.active ? Font.DemiBold : Font.Normal
                                color: optChip.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    component CompactTextRow: Column {
        id: txtRow
        property string label: ""
        property string value: ""
        property string placeholder: ""
        signal committed(string nextValue)

        width: parent ? parent.width : 180
        spacing: 3

        StyledText {
            visible: txtRow.label.length > 0
            width: parent.width
            text: txtRow.label
            color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.7)
            font.pixelSize: Appearance.font.pixelSize.smallest
            elide: Text.ElideRight
        }
        MaterialTextField {
            width: parent.width
            enableSettingsSearch: false
            placeholderText: txtRow.placeholder
            text: txtRow.value
            font.pixelSize: Appearance.font.pixelSize.smaller
            onAccepted: txtRow.committed(text)
            onEditingFinished: if (text !== txtRow.value) txtRow.committed(text)
        }
    }

    // ── Divider ──────────────────────────────────────────────────────────
    Rectangle {
        width: parent.width
        height: 1
        color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.06)
    }

    // ── Surface Extras (Border Width, Corner Radius, Palette) ────────────
    CompactSliderRow {
        visible: root.supportsAppearance
        label: Translation.tr("Border width")
        icon: "line_weight"
        from: 1; to: 4; stepSize: 1
        suffix: "px"
        value: Number(root._cfg("borderWidth", 1))
        onEdited: v => root._setCfg("borderWidth", Math.round(v))
    }

    CompactSliderRow {
        visible: root.supportsAppearance
        label: Translation.tr("Corner radius (-1 auto)")
        icon: "rounded_corner"
        from: -1; to: 32; stepSize: 1
        value: Number(root._cfg("cornerRadius", -1))
        onEdited: v => root._setCfg("cornerRadius", Math.round(v))
    }

    Column {
        visible: root._supportsPalette
        width: parent.width
        spacing: 4

        StyledText {
            text: Translation.tr("Palette")
            color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.7)
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
        Flow {
            width: parent.width
            spacing: 4
            Repeater {
                model: [
                    { value: "balanced", label: Translation.tr("Default"), roles: ["primary", "secondary", "tertiary"] },
                    { value: "primary", label: Translation.tr("Primary"), roles: ["primary", "primary", "primary"] },
                    { value: "secondary", label: Translation.tr("Secondary"), roles: ["secondary", "secondary", "secondary"] },
                    { value: "tertiary", label: Translation.tr("Tertiary"), roles: ["tertiary", "tertiary", "tertiary"] }
                ]
                delegate: RippleButton {
                    id: palBtn
                    required property var modelData
                    readonly property bool active: root._currentPalettePreset() === modelData.value
                    padding: 0
                    height: 24
                    width: palRow.implicitWidth + 14
                    buttonRadius: Appearance.rounding.full
                    toggled: active
                    colBackground: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.09)
                    colBackgroundToggled: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.18)
                    colBackgroundToggledHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25)
                    downAction: () => root._applyPalettePreset(palBtn.modelData.value)
                    contentItem: Item {
                        implicitWidth: palRow.implicitWidth
                        implicitHeight: palRow.implicitHeight
                        Row {
                            id: palRow
                            anchors.centerIn: parent
                            spacing: 4
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: -2
                                Repeater {
                                    model: palBtn.modelData.roles
                                    Rectangle {
                                        required property string modelData
                                        width: 8; height: 8; radius: 4
                                        color: root._roleColor(modelData)
                                        border.width: 0.5
                                        border.color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.22)
                                    }
                                }
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: palBtn.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: palBtn.active ? Font.DemiBold : Font.Normal
                                color: palBtn.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Per-Monitor Display & Placement Strategy ─────────────────────────
    CompactSwitchRow {
        visible: root.outputName.length > 0
        label: Translation.tr("Show on %1").arg(root.outputName)
        icon: "monitor"
        value: DesktopWidgetLayout.enabled(root.outputName, root.layoutKey, root.defaultOn)
        onToggledByUser: nextVal => DesktopWidgetLayout.setEnabled(root.outputName, root.layoutKey, nextVal)
    }

    CompactChipFlow {
        visible: root._supportsPlacement
        label: Translation.tr("Placement")
        currentValue: root._currentPlacement
        options: [
            { label: Translation.tr("Free"), icon: "drag_pan", value: "free" },
            { label: Translation.tr("Least"), icon: "category", value: "leastBusy" },
            { label: Translation.tr("Most"), icon: "shapes", value: "mostBusy" },
            { label: Translation.tr("Zone"), icon: "grid_view", value: "zone" }
        ]
        onChosen: v => root._setCfg("placementStrategy", v)
    }

    Flow {
        visible: root._supportsPlacement && [
            "topLeft", "topCenter", "topRight",
            "centerLeft", "center", "centerRight",
            "bottomLeft", "bottomCenter", "bottomRight"
        ].indexOf(root._currentPlacement) >= 0 || root._currentPlacement === "zone"
        width: parent.width
        spacing: 4

        Grid {
            columns: 3
            spacing: 3
            Repeater {
                model: root._zoneOptions
                delegate: RippleButton {
                    id: zoneBtn
                    required property var modelData
                    readonly property bool active: root._currentPlacement === modelData.zone
                    width: 28; height: 28
                    buttonRadius: Appearance.rounding.small
                    toggled: active
                    colBackground: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.09)
                    colBackgroundToggled: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.20)
                    colBackgroundToggledHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.28)
                    downAction: () => root._setCfg("placementStrategy", zoneBtn.modelData.zone)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: zoneBtn.modelData.icon
                        iconSize: 15
                        color: zoneBtn.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }

    // ── Reset Position Action ────────────────────────────────────────────
    RippleButton {
        visible: root.outputName.length > 0 && DesktopWidgetLayout.hasOverrides(root.outputName, root.layoutKey)
        width: parent.width
        height: 26
        buttonRadius: Appearance.rounding.small
        colBackground: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.04)
        colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.09)
        downAction: () => DesktopWidgetLayout.clearWidget(root.outputName, root.layoutKey)
        contentItem: Item {
            implicitWidth: resetRow.implicitWidth
            implicitHeight: resetRow.implicitHeight
            Row {
                id: resetRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "restart_alt"
                    iconSize: 14
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Reset display overrides")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                    color: Appearance.colors.colPrimary
                }
            }
        }
    }

    // ── CLOCK SETTINGS ───────────────────────────────────────────────────
    Loader {
        active: root.widgetKey === "clock"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Clock") }
            CompactChipFlow {
                label: Translation.tr("Style")
                currentValue: String(root._cfg("style", "cookie"))
                options: [
                    { label: Translation.tr("Cookie"), icon: "cookie", value: "cookie" },
                    { label: Translation.tr("Digital"), icon: "timer", value: "digital" },
                    { label: Translation.tr("Android"), icon: "android", value: "androidStacked" }
                ]
                onChosen: v => root._setCfg("style", v)
            }
            CompactChipFlow {
                label: Translation.tr("Time format")
                currentValue: String(root._cfg("timeFormat", "system"))
                options: [
                    { label: Translation.tr("System"), value: "system" },
                    { label: Translation.tr("24h"), value: "24h" },
                    { label: Translation.tr("12h"), value: "12h" }
                ]
                onChosen: v => root._setCfg("timeFormat", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show seconds")
                icon: "timer"
                value: Boolean(root._cfg("showSeconds", false))
                onToggledByUser: v => root._setCfg("showSeconds", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show date")
                icon: "calendar_today"
                value: Boolean(root._cfg("showDate", true))
                onToggledByUser: v => root._setCfg("showDate", v)
            }
            CompactChipFlow {
                visible: Boolean(root._cfg("showDate", true))
                label: Translation.tr("Date style")
                currentValue: String(root._cfg("dateStyle", "long"))
                options: [
                    { label: Translation.tr("Long"), value: "long" },
                    { label: Translation.tr("Minimal"), value: "minimal" },
                    { label: Translation.tr("Weekday"), value: "weekday" },
                    { label: Translation.tr("Numeric"), value: "numeric" }
                ]
                onChosen: v => root._setCfg("dateStyle", v)
            }
            CompactSwitchRow {
                visible: String(root._cfg("style", "cookie")) !== "cookie"
                label: Translation.tr("Text shadow")
                icon: "shadow"
                value: Boolean(root._cfg("showShadow", true))
                onToggledByUser: v => root._setCfg("showShadow", v)
            }
            CompactSliderRow {
                visible: String(root._cfg("style", "cookie")) !== "cookie"
                label: Translation.tr("Time scale")
                from: 0.5; to: 1.5; stepSize: 0.05
                value: Number(root._cfg("timeScale", 1.0))
                onEdited: v => root._setCfg("timeScale", v)
            }
            CompactChipFlow {
                visible: String(root._cfg("style", "cookie")) === "cookie"
                label: Translation.tr("Dial numbers")
                currentValue: String(root._cfg("cookie.dialNumberStyle", "none"))
                options: [
                    { label: Translation.tr("None"), value: "none" },
                    { label: Translation.tr("Dots"), value: "dots" },
                    { label: Translation.tr("Lines"), value: "full" },
                    { label: Translation.tr("123"), value: "numbers" }
                ]
                onChosen: v => root._setCfg("cookie.dialNumberStyle", v)
            }
            CompactSliderRow {
                visible: String(root._cfg("style", "cookie")) === "cookie"
                label: Translation.tr("Cookie sides")
                from: 4; to: 20; stepSize: 1
                value: Number(root._cfg("cookie.sides", 12))
                onEdited: v => root._setCfg("cookie.sides", Math.round(v))
            }
            CompactSliderRow {
                visible: String(root._cfg("style", "cookie")) === "cookie"
                label: Translation.tr("Cookie size")
                from: 120; to: 320; stepSize: 10; suffix: "px"
                value: Number(root._cfg("cookie.size", 200))
                onEdited: v => root._setCfg("cookie.size", Math.round(v))
            }
            CompactSwitchRow {
                visible: String(root._cfg("style", "cookie")) === "cookie"
                label: Translation.tr("Constantly rotate")
                icon: "rotate_right"
                value: Boolean(root._cfg("cookie.constantlyRotate", false))
                onToggledByUser: v => root._setCfg("cookie.constantlyRotate", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show quote")
                icon: "format_quote"
                value: Boolean(root._cfg("quote.enable", false))
                onToggledByUser: v => root._setCfg("quote.enable", v)
            }
            CompactTextRow {
                visible: Boolean(root._cfg("quote.enable", false))
                label: Translation.tr("Quote text")
                value: String(root._cfg("quote.text", ""))
                placeholder: Translation.tr("Custom quote...")
                onCommitted: v => root._setCfg("quote.text", v)
            }
        }
    }

    // ── WEATHER SETTINGS ─────────────────────────────────────────────────
    Loader {
        active: root.widgetKey === "weather"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Weather") }
            CompactChipFlow {
                label: Translation.tr("Style")
                currentValue: String(root._cfg("style", "pill"))
                options: [
                    { label: Translation.tr("Shape"), value: "pill" },
                    { label: Translation.tr("Card"), value: "card" },
                    { label: Translation.tr("Detail"), value: "detail" }
                ]
                onChosen: v => root._setCfg("style", v)
            }
            CompactChipFlow {
                visible: String(root._cfg("style", "pill")) === "pill"
                label: Translation.tr("Shape")
                currentValue: String(root._cfg("shape", "pill"))
                options: [
                    { label: Translation.tr("Pill"), value: "pill" },
                    { label: Translation.tr("Circle"), value: "circle" },
                    { label: Translation.tr("Oval"), value: "oval" },
                    { label: Translation.tr("Cookie"), value: "cookie4" },
                    { label: Translation.tr("Sunny"), value: "sunny" },
                    { label: Translation.tr("Flower"), value: "flower" },
                    { label: Translation.tr("Heart"), value: "heart" }
                ]
                onChosen: v => root._setCfg("shape", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show temperature")
                icon: "thermostat"
                value: Boolean(root._cfg("showTemp", true))
                onToggledByUser: v => root._setCfg("showTemp", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show icon")
                icon: "partly_cloudy_day"
                value: Boolean(root._cfg("showIcon", true))
                onToggledByUser: v => root._setCfg("showIcon", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show condition")
                icon: "short_text"
                value: Boolean(root._cfg("showCondition", false))
                onToggledByUser: v => root._setCfg("showCondition", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show metrics")
                icon: "water_drop"
                value: Boolean(root._cfg("showMetrics", false))
                onToggledByUser: v => root._setCfg("showMetrics", v)
            }
            CompactSliderRow {
                label: Translation.tr("Size")
                from: 100; to: 320; stepSize: 10; suffix: "px"
                value: Number(root._cfg("size", 200))
                onEdited: v => root._setCfg("size", Math.round(v))
            }
        }
    }

    // ── MEDIA CONTROLS SETTINGS ──────────────────────────────────────────
    Loader {
        active: root.widgetKey === "mediaControls"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Media Player") }
            CompactChipFlow {
                label: Translation.tr("Layout")
                currentValue: String(root._cfg("playerPreset", "full"))
                options: [
                    { label: Translation.tr("Full"), value: "full" },
                    { label: Translation.tr("Compact"), value: "compact" },
                    { label: Translation.tr("Minimal"), value: "minimal" },
                    { label: Translation.tr("Art"), value: "albumart" },
                    { label: Translation.tr("Classic"), value: "classic" },
                    { label: Translation.tr("Lyrics"), value: "lyrics" }
                ]
                onChosen: v => root._setCfg("playerPreset", v)
            }
            CompactChipFlow {
                label: Translation.tr("Visualizer")
                currentValue: String(root._cfg("visualizerType", "bars"))
                options: [
                    { label: Translation.tr("Bars"), value: "bars" },
                    { label: Translation.tr("Wave"), value: "wave" },
                    { label: Translation.tr("Circle"), value: "radial" },
                    { label: Translation.tr("None"), value: "none" }
                ]
                onChosen: v => root._setCfg("visualizerType", v)
            }
        }
    }

    // ── VISUALIZER SETTINGS ──────────────────────────────────────────────
    Loader {
        active: root.widgetKey === "visualizer"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Visualizer") }
            CompactChipFlow {
                label: Translation.tr("Mode")
                currentValue: String(root._cfg("vizType", "bars"))
                options: [
                    { label: Translation.tr("Bars"), icon: "equalizer", value: "bars" },
                    { label: Translation.tr("Wave"), icon: "waves", value: "wave" }
                ]
                onChosen: v => root._setCfg("vizType", v)
            }
            CompactChipFlow {
                label: Translation.tr("Colors")
                currentValue: String(root._cfg("paletteMode", "cava"))
                options: [
                    { label: Translation.tr("Cava"), value: "cava" },
                    { label: Translation.tr("Accent"), value: "accent" },
                    { label: Translation.tr("Primary"), value: "primary" }
                ]
                onChosen: v => root._setCfg("paletteMode", v)
            }
            CompactChipFlow {
                visible: String(root._cfg("vizType", "bars")) === "bars"
                label: Translation.tr("Origin")
                currentValue: String(root._cfg("barsOrigin", "bottom"))
                options: [
                    { label: Translation.tr("Bottom"), value: "bottom" },
                    { label: Translation.tr("Top"), value: "top" },
                    { label: Translation.tr("Center"), value: "center" },
                    { label: Translation.tr("Mirror"), value: "mirror" }
                ]
                onChosen: v => root._setCfg("barsOrigin", v)
            }
            CompactChipFlow {
                label: Translation.tr("Frequency")
                currentValue: String(root._cfg("frequencyProfile", "flat"))
                options: [
                    { label: Translation.tr("Flat"), value: "flat" },
                    { label: Translation.tr("Bass"), value: "bass" },
                    { label: Translation.tr("Warm"), value: "warm" },
                    { label: Translation.tr("Vocal"), value: "vocal" },
                    { label: Translation.tr("Treble"), value: "treble" }
                ]
                onChosen: v => root._setCfg("frequencyProfile", v)
            }
            CompactSliderRow {
                label: Translation.tr("Bars")
                from: 8; to: 128; stepSize: 4
                value: Number(root._cfg("barCount", 48))
                onEdited: v => root._setCfg("barCount", Math.round(v))
            }
            CompactSliderRow {
                label: Translation.tr("Smoothing")
                from: 10; to: 100; stepSize: 5; suffix: "%"
                value: Number(root._cfg("smoothing", 60))
                onEdited: v => root._setCfg("smoothing", Math.round(v))
            }
            CompactSliderRow {
                label: Translation.tr("Width")
                from: 100; to: 800; stepSize: 20; suffix: "px"
                value: Number(root._cfg("contentWidth", 360))
                onEdited: v => root._setCfg("contentWidth", Math.round(v))
            }
            CompactSliderRow {
                label: Translation.tr("Height")
                from: 40; to: 400; stepSize: 10; suffix: "px"
                value: Number(root._cfg("contentHeight", 100))
                onEdited: v => root._setCfg("contentHeight", Math.round(v))
            }
        }
    }

    // ── SYSTEM MONITOR SETTINGS ──────────────────────────────────────────
    Loader {
        active: root.widgetKey === "systemMonitor"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("System Monitor") }
            CompactChipFlow {
                label: Translation.tr("Display mode")
                currentValue: String(root._cfg("displayMode", "bars"))
                options: [
                    { label: Translation.tr("Bars"), value: "bars" },
                    { label: Translation.tr("Graph"), value: "graph" },
                    { label: Translation.tr("Ring"), value: "ring" }
                ]
                onChosen: v => root._setCfg("displayMode", v)
            }
            CompactSwitchRow {
                label: Translation.tr("CPU")
                icon: "memory"
                value: Boolean(root._cfg("showCpu", true))
                onToggledByUser: v => root._setCfg("showCpu", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Memory")
                icon: "storage"
                value: Boolean(root._cfg("showMemory", true))
                onToggledByUser: v => root._setCfg("showMemory", v)
            }
            CompactSwitchRow {
                label: Translation.tr("GPU")
                icon: "developer_board"
                value: Boolean(root._cfg("showGpu", false))
                onToggledByUser: v => root._setCfg("showGpu", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Labels")
                icon: "label"
                value: Boolean(root._cfg("showLabels", true))
                onToggledByUser: v => root._setCfg("showLabels", v)
            }
            CompactSliderRow {
                label: Translation.tr("Width")
                from: 160; to: 600; stepSize: 10; suffix: "px"
                value: Number(root._cfg("contentWidth", 320))
                onEdited: v => root._setCfg("contentWidth", Math.round(v))
            }
        }
    }

    // ── BATTERY SETTINGS ─────────────────────────────────────────────────
    Loader {
        active: root.widgetKey === "battery"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Battery") }
            CompactChipFlow {
                label: Translation.tr("Display")
                currentValue: String(root._cfg("displayMode", "ring"))
                options: [
                    { label: Translation.tr("Ring"), icon: "radio_button_checked", value: "ring" },
                    { label: Translation.tr("Bars"), icon: "bar_chart", value: "bars" },
                    { label: Translation.tr("Pill"), icon: "horizontal_rule", value: "pill" }
                ]
                onChosen: v => root._setCfg("displayMode", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show time remaining")
                icon: "schedule"
                value: Boolean(root._cfg("showTime", true))
                onToggledByUser: v => root._setCfg("showTime", v)
            }
            CompactSliderRow {
                visible: String(root._cfg("displayMode", "ring")) === "ring"
                label: Translation.tr("Ring size")
                from: 40; to: 120; stepSize: 4; suffix: "px"
                value: Number(root._cfg("ringSize", 68))
                onEdited: v => root._setCfg("ringSize", Math.round(v))
            }
            CompactSliderRow {
                visible: String(root._cfg("displayMode", "ring")) === "bars"
                label: Translation.tr("Bar count")
                from: 4; to: 48; stepSize: 2
                value: Number(root._cfg("barCount", 20))
                onEdited: v => root._setCfg("barCount", Math.round(v))
            }
        }
    }

    // ── NOTES SETTINGS ───────────────────────────────────────────────────
    Loader {
        active: root.widgetKey === "notes"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Notes") }
            CompactSliderRow {
                label: Translation.tr("Font size")
                from: 10; to: 48; stepSize: 1; suffix: "px"
                value: Number(root._cfg("fontSize", 14))
                onEdited: v => root._setCfg("fontSize", Math.round(v))
            }
            CompactChipFlow {
                label: Translation.tr("Font")
                currentValue: String(root._cfg("fontFamily", "sans"))
                options: [
                    { label: Translation.tr("Sans"), value: "sans" },
                    { label: Translation.tr("Mono"), value: "mono" }
                ]
                onChosen: v => root._setCfg("fontFamily", v)
            }
            CompactChipFlow {
                label: Translation.tr("Align")
                currentValue: String(root._cfg("textAlign", "left"))
                options: [
                    { label: Translation.tr("Left"), icon: "format_align_left", value: "left" },
                    { label: Translation.tr("Center"), icon: "format_align_center", value: "center" },
                    { label: Translation.tr("Right"), icon: "format_align_right", value: "right" }
                ]
                onChosen: v => root._setCfg("textAlign", v)
            }
            CompactSliderRow {
                label: Translation.tr("Width")
                from: 160; to: 720; stepSize: 10; suffix: "px"
                value: Number(root._cfg("contentWidth", 280))
                onEdited: v => root._setCfg("contentWidth", Math.round(v))
            }
            CompactSliderRow {
                label: Translation.tr("Height")
                from: 100; to: 720; stepSize: 10; suffix: "px"
                value: Number(root._cfg("contentHeight", 200))
                onEdited: v => root._setCfg("contentHeight", Math.round(v))
            }
        }
    }

    // ── UPCOMING EVENTS SETTINGS ─────────────────────────────────────────
    Loader {
        active: root.widgetKey === "calendarUpcoming"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Upcoming Events") }
            CompactSliderRow {
                label: Translation.tr("Max events")
                from: 1; to: 12; stepSize: 1
                value: Number(root._cfg("maxEvents", 5))
                onEdited: v => root._setCfg("maxEvents", Math.round(v))
            }
            CompactSwitchRow {
                label: Translation.tr("Show date")
                icon: "calendar_today"
                value: Boolean(root._cfg("showDate", true))
                onToggledByUser: v => root._setCfg("showDate", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show time")
                icon: "schedule"
                value: Boolean(root._cfg("showTime", true))
                onToggledByUser: v => root._setCfg("showTime", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show location")
                icon: "location_on"
                value: Boolean(root._cfg("showLocation", true))
                onToggledByUser: v => root._setCfg("showLocation", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Group by day")
                icon: "view_agenda"
                value: Boolean(root._cfg("groupByDay", false))
                onToggledByUser: v => root._setCfg("groupByDay", v)
            }
        }
    }

    // ── WORLD CLOCK SETTINGS ─────────────────────────────────────────────
    Loader {
        active: root.widgetKey === "worldClock"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("World Clock") }
            Repeater {
                model: WorldClock.timezones ? WorldClock.timezones.length : 0
                delegate: RowLayout {
                    id: tzRow
                    required property int index
                    width: parent.width
                    spacing: 4
                    StyledText {
                        text: "#" + (tzRow.index + 1)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledComboBox {
                        Layout.fillWidth: true
                        model: WorldClock.comboModel
                        textRole: "label"
                        currentIndex: Math.max(0, WorldClock.comboModel.findIndex(o => o.tz === WorldClock.timezones[tzRow.index]))
                        onActivated: idx => WorldClock.setTimezone(tzRow.index, WorldClock.comboModel[idx].tz)
                    }
                }
            }
            CompactSliderRow {
                label: Translation.tr("Width")
                from: 240; to: 700; stepSize: 10; suffix: "px"
                value: Number(root._cfg("contentWidth", 340))
                onEdited: v => root._setCfg("contentWidth", Math.round(v))
            }
        }
    }

    // ── UPTIME / USER CARD / NEWS TICKER SIZE CONTROLS ───────────────────
    Loader {
        active: root.widgetKey === "uptime" || root.widgetKey === "userCard" || root.widgetKey === "newsTicker"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader {
                text: root.widgetKey === "uptime" ? Translation.tr("System Uptime")
                    : (root.widgetKey === "userCard" ? Translation.tr("User Card") : Translation.tr("News Ticker"))
            }
            CompactSliderRow {
                label: Translation.tr("Width")
                from: 180; to: 600; stepSize: 10; suffix: "px"
                value: Number(root._cfg("contentWidth", 320))
                onEdited: v => root._setCfg("contentWidth", Math.round(v))
            }
            CompactSliderRow {
                label: Translation.tr("Height")
                from: 60; to: 320; stepSize: 4; suffix: "px"
                value: Number(root._cfg("contentHeight", 160))
                onEdited: v => root._setCfg("contentHeight", Math.round(v))
            }
        }
    }

    // ── CUSTOM IMAGE SETTINGS ────────────────────────────────────────────
    Loader {
        active: root.widgetKey === "customImage"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Custom Image") }
            CompactChipFlow {
                label: Translation.tr("Source")
                currentValue: String(root._cfg("sourceMode", "file"))
                options: [
                    { label: Translation.tr("File"), icon: "draft", value: "file" },
                    { label: Translation.tr("Folder"), icon: "folder_open", value: "folder" }
                ]
                onChosen: v => root._setCfg("sourceMode", v)
            }
            CompactTextRow {
                visible: String(root._cfg("sourceMode", "file")) === "file"
                label: Translation.tr("File path")
                value: String(root._cfg("path", ""))
                placeholder: "/path/to/image.png"
                onCommitted: v => root._setCfg("path", v.trim())
            }
            CompactTextRow {
                visible: String(root._cfg("sourceMode", "file")) === "folder"
                label: Translation.tr("Folder path")
                value: String(root._cfg("folder", ""))
                placeholder: "~/Pictures"
                onCommitted: v => root._setCfg("folder", v.trim())
            }
            CompactChipFlow {
                label: Translation.tr("Fit")
                currentValue: String(root._cfg("fitMode", "cover"))
                options: [
                    { label: Translation.tr("Crop"), value: "cover" },
                    { label: Translation.tr("Contain"), value: "contain" }
                ]
                onChosen: v => root._setCfg("fitMode", v)
            }
            CompactChipFlow {
                visible: String(root._cfg("sourceMode", "file")) === "folder"
                label: Translation.tr("Order")
                currentValue: String(root._cfg("order", "sequential"))
                options: [
                    { label: Translation.tr("Order"), value: "sequential" },
                    { label: Translation.tr("Random"), value: "random" }
                ]
                onChosen: v => root._setCfg("order", v)
            }
            CompactSliderRow {
                label: Translation.tr("Size")
                from: 80; to: 1200; stepSize: 10; suffix: "px"
                value: Number(root._cfg("size", 240))
                onEdited: v => root._setCfg("size", Math.round(v))
            }
        }
    }

    // ── IMAGE CONVERTER SETTINGS ─────────────────────────────────────────
    Loader {
        active: root.widgetKey === "imageConverter"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Image Converter") }
            CompactChipFlow {
                label: Translation.tr("Default format")
                currentValue: String(root._cfg("selectedFormat", "png"))
                options: [
                    { label: "PNG", value: "png" },
                    { label: "JPG", value: "jpg" },
                    { label: "WEBP", value: "webp" },
                    { label: "AVIF", value: "avif" },
                    { label: "BMP", value: "bmp" },
                    { label: "TIFF", value: "tiff" },
                    { label: "PDF", value: "pdf" }
                ]
                onChosen: v => root._setCfg("selectedFormat", v)
            }
        }
    }

    // ── JAPANESE TYPOGRAPHY SETTINGS ─────────────────────────────────────
    Loader {
        active: root.widgetKey === "japaneseTypography"
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Japanese Typography") }
            CompactChipFlow {
                label: Translation.tr("Composition")
                currentValue: String(root._cfg("composition", "exhibition"))
                options: [
                    { label: Translation.tr("Exhibition"), value: "exhibition" },
                    { label: Translation.tr("Magazine"), value: "magazine" },
                    { label: Translation.tr("Minimal"), value: "minimal" },
                    { label: Translation.tr("Traditional"), value: "traditional" }
                ]
                onChosen: v => Config.setNestedValues(JapanesePresets.composition(root.configPrefix, v))
            }
            CompactChipFlow {
                label: Translation.tr("Palette")
                currentValue: String(root._cfg("palettePreset", "adaptive"))
                options: [
                    { label: Translation.tr("Adaptive"), value: "adaptive" },
                    { label: Translation.tr("Sumi"), value: "sumi" },
                    { label: Translation.tr("Ivory"), value: "ivory" },
                    { label: Translation.tr("Sunset"), value: "sunset" },
                    { label: Translation.tr("Cinema"), value: "cinema" }
                ]
                onChosen: v => Config.setNestedValues(JapanesePresets.palette(root.configPrefix, v))
            }
            CompactChipFlow {
                label: Translation.tr("Font style")
                currentValue: String(root._cfg("fontPreset", "mincho"))
                options: [
                    { label: Translation.tr("Mincho"), value: "mincho" },
                    { label: Translation.tr("Mixed"), value: "mixed" },
                    { label: Translation.tr("Gothic"), value: "gothic" }
                ]
                onChosen: v => Config.setNestedValues(JapanesePresets.font(root.configPrefix, v))
            }
            CompactTextRow {
                label: Translation.tr("Primary text")
                value: String(root._cfg("primaryText", "夏の記憶"))
                onCommitted: v => root._setCfg("primaryText", v)
            }
            CompactTextRow {
                label: Translation.tr("Secondary text")
                value: String(root._cfg("secondaryText", "潮風と、あの子と、終わらない夏"))
                onCommitted: v => root._setCfg("secondaryText", v)
            }
            CompactTextRow {
                label: Translation.tr("Seal text")
                value: String(root._cfg("sealText", "特別展"))
                onCommitted: v => root._setCfg("sealText", v)
            }
            CompactTextRow {
                label: Translation.tr("Footer text")
                value: String(root._cfg("footerText", "PACIFIC DRIVE-IN"))
                onCommitted: v => root._setCfg("footerText", v)
            }
            CompactTextRow {
                label: Translation.tr("Date text")
                value: String(root._cfg("dateText", "7.12 — 8.31"))
                onCommitted: v => root._setCfg("dateText", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show secondary")
                value: Boolean(root._cfg("showSecondary", true))
                onToggledByUser: v => root._setCfg("showSecondary", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show seal")
                value: Boolean(root._cfg("showSeal", true))
                onToggledByUser: v => root._setCfg("showSeal", v)
            }
            CompactSwitchRow {
                label: Translation.tr("Show footer")
                value: Boolean(root._cfg("showFooter", true))
                onToggledByUser: v => root._setCfg("showFooter", v)
            }
        }
    }

    // ── CUSTOM MANIFEST WIDGET SETTINGS ──────────────────────────────────
    Loader {
        active: root.isCustom && root.customManifest !== null
        visible: active
        width: parent.width
        sourceComponent: Column {
            width: parent ? parent.width : 200
            spacing: 6

            CompactSectionHeader { text: Translation.tr("Custom Widget") }
            Repeater {
                model: root._customConfigSpecs()
                delegate: Item {
                    id: cwOpt
                    required property var modelData
                    readonly property string optType: String(modelData.spec?.type ?? "string")
                    width: parent.width
                    height: optCol.implicitHeight
                    Column {
                        id: optCol
                        width: parent.width
                        spacing: 4
                        CompactSwitchRow {
                            visible: cwOpt.optType === "bool" || cwOpt.optType === "boolean"
                            label: String(cwOpt.modelData.spec?.label ?? cwOpt.modelData.key)
                            value: Boolean(CustomWidgets.getConfigValue(root.customManifest.id, cwOpt.modelData.key, cwOpt.modelData.spec?.default ?? false))
                            onToggledByUser: v => CustomWidgets.setConfigValue(root.customManifest.id, cwOpt.modelData.key, v)
                        }
                        CompactSliderRow {
                            visible: cwOpt.optType === "int" || cwOpt.optType === "float" || cwOpt.optType === "number"
                            label: String(cwOpt.modelData.spec?.label ?? cwOpt.modelData.key)
                            from: Number(cwOpt.modelData.spec?.min ?? 0)
                            to: Number(cwOpt.modelData.spec?.max ?? 100)
                            stepSize: Number(cwOpt.modelData.spec?.step ?? 1)
                            value: Number(CustomWidgets.getConfigValue(root.customManifest.id, cwOpt.modelData.key, cwOpt.modelData.spec?.default ?? 0))
                            onEdited: v => CustomWidgets.setConfigValue(root.customManifest.id, cwOpt.modelData.key, v)
                        }
                        CompactChipFlow {
                            visible: cwOpt.optType === "select" || cwOpt.optType === "enum"
                            label: String(cwOpt.modelData.spec?.label ?? cwOpt.modelData.key)
                            currentValue: String(CustomWidgets.getConfigValue(root.customManifest.id, cwOpt.modelData.key, cwOpt.modelData.spec?.default ?? ""))
                            options: root._manifestOptions(cwOpt.modelData.spec?.options)
                            onChosen: v => CustomWidgets.setConfigValue(root.customManifest.id, cwOpt.modelData.key, v)
                        }
                        CompactTextRow {
                            visible: cwOpt.optType === "string" || cwOpt.optType === "text"
                            label: String(cwOpt.modelData.spec?.label ?? cwOpt.modelData.key)
                            value: String(CustomWidgets.getConfigValue(root.customManifest.id, cwOpt.modelData.key, cwOpt.modelData.spec?.default ?? ""))
                            onCommitted: v => CustomWidgets.setConfigValue(root.customManifest.id, cwOpt.modelData.key, v)
                        }
                    }
                }
            }
            RippleButton {
                width: parent.width
                height: 26
                buttonRadius: Appearance.rounding.small
                colBackground: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.04)
                colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.09)
                downAction: () => CustomWidgets.openWidgetDir(root.customManifest.id)
                contentItem: Item {
                    implicitWidth: openDirRow.implicitWidth
                    implicitHeight: openDirRow.implicitHeight
                    Row {
                        id: openDirRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "folder_open"
                            iconSize: 14
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Open widget folder")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }
}
