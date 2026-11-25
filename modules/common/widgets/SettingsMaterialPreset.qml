pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.abyss.looks
import qs.modules.waffle.looks as Waffle

QtObject {
    id: root

    readonly property bool waffle: Config.options?.panelFamily === "waffle"
    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    readonly property bool isDarkSurface: Qt.color(Appearance.colors.colLayer0Base).hslLightness < 0.52
    readonly property real tonalDirection: Qt.color(Appearance.colors.colLayer1Base).hslLightness > 0.86 ? -1 : 1
    readonly property real _surfaceAlpha: abyss ? Math.max(0.18, AbyssStyle.contentOpacity) : 1.0
    readonly property string fontFamily: waffle ? Waffle.Looks.font.family.ui : Appearance.font.family.main
    readonly property color textColor: waffle ? Waffle.Looks.colors.fg : Appearance.colors.colOnLayer1
    readonly property color secondaryTextColor: waffle ? Waffle.Looks.colors.subfg : Appearance.colors.colSubtext
    readonly property color windowColor: waffle
        ? (Waffle.Looks.useMaterial ? Appearance.colors.colLayer0
            : Waffle.Looks.applyBackgroundTransparency(Qt.tint(Waffle.Looks.dark ? "#202020" : "#f3f3f3", Qt.alpha(Waffle.Looks.colors.accent, 0.035))))
        : Appearance.colors.colLayer0

    // ── Redesigned Tonal Surface Hierarchy (derived smoothly from theme base) ──
    readonly property color _sidebarSolid: ColorUtils.tonalStep(
        Appearance.colors.colLayer0Base,
        isDarkSurface ? 0.022 : -0.024,
        1.06
    )
    readonly property color sidebarColor: waffle
        ? "transparent"
        : Qt.alpha(_sidebarSolid, abyss ? Math.min(1.0, AbyssStyle.contentOpacity * 0.94) : 1.0)
    readonly property color sidebarBorderColor: waffle
        ? "transparent"
        : Qt.alpha(Appearance.colors.colOutlineVariant, isDarkSurface ? 0.24 : 0.30)

    readonly property color _controlSolid: ColorUtils.tonalStep(
        Appearance.colors.colLayer1Base,
        tonalDirection * 0.026,
        1.08
    )
    readonly property color _controlHoverSolid: ColorUtils.tonalStep(
        Appearance.colors.colLayer1Base,
        tonalDirection * 0.048,
        1.10
    )
    readonly property color _controlActiveSolid: ColorUtils.tonalStep(
        Appearance.colors.colLayer1Base,
        tonalDirection * 0.068,
        1.12
    )
    readonly property color controlSurface: waffle
        ? (Waffle.Looks.useMaterial ? Appearance.colors.colLayer2 : Waffle.Looks.colors.bg2)
        : Qt.alpha(_controlSolid, _surfaceAlpha)
    readonly property color controlSurfaceHover: waffle
        ? (Waffle.Looks.useMaterial ? Appearance.colors.colLayer2Hover : Waffle.Looks.colors.bg2Hover)
        : Qt.alpha(_controlHoverSolid, Math.min(1.0, _surfaceAlpha + 0.06))
    readonly property color controlSurfaceActive: waffle
        ? (Waffle.Looks.useMaterial ? Appearance.colors.colLayer2Active : Waffle.Looks.colors.bg2Active)
        : Qt.alpha(_controlActiveSolid, Math.min(1.0, _surfaceAlpha + 0.10))
    readonly property color controlBorderColor: waffle
        ? cardBorderColor
        : Qt.alpha(Appearance.colors.colOutlineVariant, isDarkSurface ? 0.24 : 0.30)

    readonly property color accentTint: waffle
        ? Qt.alpha(Waffle.Looks.colors.accent, 0.14)
        : Qt.alpha(Appearance.colors.colPrimary, isDarkSurface ? 0.15 : 0.12)
    readonly property color accentTintHover: waffle
        ? Qt.alpha(Waffle.Looks.colors.accent, 0.22)
        : Qt.alpha(Appearance.colors.colPrimary, isDarkSurface ? 0.23 : 0.19)
    readonly property color accentBorder: waffle
        ? Qt.alpha(Waffle.Looks.colors.accent, 0.32)
        : Qt.alpha(Appearance.colors.colPrimary, isDarkSurface ? 0.30 : 0.28)
    readonly property color pillSelectedColor: waffle
        ? navSelectedColor
        : Appearance.colors.colPrimaryContainer
    readonly property color pillSelectedHoverColor: waffle
        ? navSelectedHoverColor
        : Appearance.colors.colPrimaryContainerHover
    readonly property color pillSelectedTextColor: waffle
        ? textColor
        : ColorUtils.ensureReadable(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 5.0)

    readonly property color navSelectedColor: waffle ? Qt.alpha(Waffle.Looks.colors.fg, 0.065) : Appearance.colors.colPrimaryContainer
    readonly property color navHoverColor: waffle ? Qt.alpha(Waffle.Looks.colors.fg, 0.045) : controlSurfaceHover
    readonly property color navSelectedHoverColor: waffle ? Qt.alpha(Waffle.Looks.colors.fg, 0.09) : Appearance.colors.colPrimaryContainerHover
    readonly property color navSelectedTextColor: waffle ? Waffle.Looks.colors.fg : pillSelectedTextColor
    readonly property int navItemRadius: waffle ? 6 : 10
    readonly property int navSidebarWidth: Math.round(226 * Math.min(1.25, Math.max(1.0, Appearance.fontSizeScale)))
    readonly property int waffleRailWidth: 280
    readonly property int compactNavWidth: 62

    function useCompactNav(surfaceWidth: real, editing: bool): bool {
        return !waffle && surfaceWidth > 0 && surfaceWidth < 860
    }
    readonly property int searchRadius: waffle ? 4 : 10
    readonly property color searchColor: waffle ? cardColor : controlSurface
    readonly property color searchBottomLineColor: Waffle.Looks.dark ? "#8a8a8a" : "#868686"

    // ── Page layout (Clean single-column editorial card cadence / Win11 4px card stack) ──
    readonly property int pageSpacing: Math.round((waffle ? 4 : Appearance.regaliaEverywhere ? Appearance.regalia.tileGap : 12) * Appearance.fontSizeScale)
    // Legacy compatibility no-ops
    property real _measuredThemesBentoHeight: 0
    property real _measuredThemesFontScale: -1
    property string _measuredThemesPanelFamily: ""
    readonly property real standardBentoHeight: 0

    // ── Card / Form Plate (SettingsCardSection) ──
    readonly property int cardRadius: waffle ? 8 : Appearance.angelEverywhere ? Appearance.angel.roundingNormal
        : Appearance.regaliaEverywhere ? Appearance.regalia.roundNormal
        : Appearance.zzzEverywhere ? Appearance.zzz.cornerRadius + 1
        : Appearance.alisEverywhere ? Appearance.alis.roundingNormal
        : 14
    readonly property int cardPadding: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.tilePadding
        : abyss ? 14 : 15) * Appearance.fontSizeScale)

    // ── Card header ──
    readonly property int headerRadius: waffle ? 4 : 8
    readonly property int headerPaddingX: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.controlPaddingHorizontal : 4) * Appearance.fontSizeScale)
    readonly property int headerPaddingY: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.controlPaddingVertical : 2) * Appearance.fontSizeScale)

    // ── Group (SettingsGroup — clean borderless flow inside card plate, no double-boxing) ──
    readonly property int groupRadius: waffle ? 4 : 10
    readonly property int groupPadding: Math.round((waffle ? 10 : abyss ? 2 : 4) * Appearance.fontSizeScale)
    readonly property int groupSpacing: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.tileGap : 8) * Appearance.fontSizeScale)

    // ── Colors ──
    readonly property color cardColor: waffle ? (Waffle.Looks.useMaterial ? Appearance.colors.colLayer1 : Waffle.Looks.applyBackgroundTransparency(Waffle.Looks.dark ? "#2b2b2b" : "#fbfbfb")) : abyss ? AbyssStyle.contentLayer : Appearance.angelEverywhere
        ? ColorUtils.transparentize(Appearance.colors.colLayer1Base, Appearance.angel.cardTransparentize * 0.7)
        : Appearance.regaliaEverywhere ? Appearance.regalia.surfacePlate
        : Appearance.zzzEverywhere ? "transparent"
        : Appearance.alisEverywhere ? Appearance.alis.colLayer1
        : Appearance.auroraEverywhere ? ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.85)
        : Appearance.colors.colLayer1
    readonly property color cardBorderColor: waffle
        ? (Waffle.Looks.useMaterial ? Qt.alpha(Appearance.colors.colOutlineVariant, 0.36) : (Waffle.Looks.dark ? "#353535" : "#e5e5e5"))
        : abyss
        ? Qt.alpha(Appearance.colors.colOutlineVariant, isDarkSurface ? 0.26 : 0.32)
        : Appearance.angelEverywhere
        ? Appearance.angel.colCardBorder
        : Appearance.regaliaEverywhere ? "transparent"
        : Appearance.zzzEverywhere ? Appearance.zzz.hairline
        : Appearance.alisEverywhere ? Appearance.alis.colBorder
        : Appearance.auroraEverywhere ? Appearance.aurora.colPopupBorder
        : Qt.alpha(Appearance.colors.colOutlineVariant, isDarkSurface ? 0.28 : 0.34)
    readonly property color plateDividerColor: waffle
        ? (Waffle.Looks.useMaterial ? Qt.alpha(Appearance.colors.colOutlineVariant, 0.24) : (Waffle.Looks.dark ? "#353535" : "#e5e5e5"))
        : Qt.alpha(Appearance.colors.colOutlineVariant, isDarkSurface ? 0.20 : 0.26)

    readonly property color groupColor: "transparent"
    readonly property color groupBorderColor: Qt.alpha(Appearance.colors.colOutlineVariant, isDarkSurface ? 0.22 : 0.28)

    // ── Header hover ──
    readonly property color headerHoverColor: waffle ? Qt.alpha(Waffle.Looks.colors.fg, 0.04) : Appearance.angelEverywhere
        ? Appearance.angel.colGlassCardHover
        : Appearance.regaliaEverywhere ? Appearance.regalia.surfacePlateHover
        : Appearance.zzzEverywhere ? Appearance.zzz.paperAlt
        : Appearance.alisEverywhere ? Appearance.alis.colLayer1Hover
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover
        : Appearance.colors.colLayer1Hover

    // ── Accent bar (left edge on expanded section) ──
    readonly property color accentColor: waffle ? Waffle.Looks.colors.accent : Appearance.angelEverywhere
        ? Appearance.angel.colPrimary
        : Appearance.regaliaEverywhere ? Appearance.regalia.onColor
        : Appearance.zzzEverywhere ? Appearance.zzz.accent
        : Appearance.alisEverywhere ? Appearance.alis.colAccent
        : Appearance.colors.colPrimary

    // ── Section title colors ──
    readonly property color titleExpandedColor: waffle ? Waffle.Looks.colors.fg : Appearance.angelEverywhere
        ? Appearance.angel.colText
        : Appearance.regaliaEverywhere ? Appearance.regalia.onColor
        : Appearance.zzzEverywhere ? Appearance.zzz.onColor
        : Appearance.alisEverywhere ? Appearance.alis.colText
        : Appearance.colors.colOnLayer0
    readonly property color titleCollapsedColor: waffle ? Waffle.Looks.colors.subfg : Appearance.angelEverywhere
        ? Appearance.angel.colTextSecondary
        : Appearance.regaliaEverywhere ? Appearance.regalia.onMuted
        : Appearance.zzzEverywhere ? Appearance.colors.colOnLayer1
        : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary
        : Appearance.colors.colOnSurfaceVariant

    // ── Icon colors ──
    // ZZZ: the card header icon rides a ZzzGlyphBadge plate (sticker when
    // expanded, secondary when collapsed); the INK on that plate must be the
    // corresponding on-plate ink, not a raw accent (which can compute near-
    // black on a low-chroma wallpaper and render as a black glyph).
    readonly property color iconExpandedColor: waffle ? Waffle.Looks.colors.accent : Appearance.angelEverywhere
        ? Appearance.angel.colPrimary
        : Appearance.regaliaEverywhere ? Appearance.regalia.hardwarePrimary
        : Appearance.zzzEverywhere ? Appearance.zzz.onSticker
        : Appearance.alisEverywhere ? Appearance.alis.colAccent
        : Appearance.colors.colPrimary
    readonly property color iconCollapsedColor: waffle ? Waffle.Looks.colors.subfg : Appearance.angelEverywhere
        ? Appearance.angel.colTextMuted
        : Appearance.regaliaEverywhere ? Appearance.regalia.hardwareSecondary
        : Appearance.zzzEverywhere ? Appearance.zzz.onSecondary
        : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary
        : Appearance.colors.colOnSurfaceVariant

    // ── In-page task navigation ──
    // One quiet shared rail; native rectangles need no per-tab texture/blur.
    readonly property real taskTabPadding: 6 * Appearance.fontSizeScale
    readonly property real taskTabHeight: 40 * Appearance.fontSizeScale
    readonly property real taskTabRadius: (waffle ? 4 : 16) * Appearance.fontSizeScale
    readonly property real taskRailRadius: (waffle ? 6 : 22) * Appearance.fontSizeScale
    readonly property color taskRailBase: waffle ? Waffle.Looks.colors.bg0 : Appearance.colors.colLayer2Base
    readonly property color taskRailColor: waffle ? "transparent" : Qt.alpha(taskRailBase, AbyssStyle.contentOpacity * .72)
    readonly property color taskTabSelectedBase: waffle ? Waffle.Looks.colors.bg2Base : ColorUtils.mix(AbyssStyle.accent,
        Appearance.colors.colLayer1Base, .26)
    readonly property color taskTabSelectedColor: waffle ? taskTabSelectedBase : Qt.alpha(taskTabSelectedBase, AbyssStyle.contentOpacity)
    readonly property color taskTabHoverColor: waffle ? navHoverColor : Qt.alpha(AbyssStyle.accent, AbyssStyle.contentOpacity * .16)
    readonly property color taskTabPressedColor: waffle ? navSelectedHoverColor : Qt.alpha(AbyssStyle.accent, AbyssStyle.contentOpacity * .24)
    readonly property color taskTabInk: waffle ? Waffle.Looks.colors.fg : ColorUtils.ensureReadable(Appearance.colors.colOnLayer1, taskRailBase)
    readonly property color taskTabSelectedInk: waffle ? Waffle.Looks.colors.fg : ColorUtils.ensureReadable(Appearance.colors.colOnPrimaryContainer, taskTabSelectedBase)
    readonly property color taskTabFocusColor: waffle ? Waffle.Looks.colors.accent : ColorUtils.ensureReadable(AbyssStyle.accent, taskRailBase, 3)

    // ── Navigation rail ──
    readonly property int navWidth: 180
    readonly property int navItemHeight: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.controlHeight : 34) * Appearance.fontSizeScale)
    readonly property int navCategorySpacing: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.tileGap + Appearance.regalia.controlGap : 10) * Appearance.fontSizeScale)
    readonly property int navItemSpacing: Appearance.regaliaEverywhere ? Appearance.regalia.controlGap : 2

    // One continuous theme-derived gradient across the flat Settings list.
    // No page owns a hard-coded icon color.
    function navigationIconColor(position: int, count: int, selected = false): color {
        if (waffle && !Waffle.Looks.useMaterial)
            return selected ? Waffle.Looks.colors.accent : Waffle.Looks.colors.fg
        const t = count <= 1 ? 0 : Math.max(0, Math.min(1, position / (count - 1)))
        const base = t <= 0.5
            ? ColorUtils.mix(Appearance.colors.colPrimary,
                Appearance.colors.colSecondary, 1 - t * 2)
            : ColorUtils.mix(Appearance.colors.colSecondary,
                Appearance.colors.colTertiary, 2 - t * 2)
        return selected
            ? ColorUtils.mix(base, Appearance.colors.colOnPrimaryContainer, 0.72)
            : ColorUtils.mix(base, Appearance.colors.colOnSurfaceVariant, 0.58)
    }
}
