pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.abyss.looks

QtObject {
    id: root

    // ── Page layout ──
    readonly property int pageSpacing: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.tileGap : 12) * Appearance.fontSizeScale)

    // ── Card (SettingsCardSection) ──
    readonly property int cardRadius: Appearance.angelEverywhere ? Appearance.angel.roundingNormal
        : Appearance.regaliaEverywhere ? Appearance.regalia.roundNormal
        : Appearance.zzzEverywhere ? Appearance.zzz.cornerRadius + 1
        : Appearance.alisEverywhere ? Appearance.alis.roundingNormal
        : Appearance.rounding.normal
    readonly property int cardPadding: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.tilePadding : 14) * Appearance.fontSizeScale)

    // ── Card header ──
    readonly property int headerRadius: Appearance.angelEverywhere ? Appearance.angel.roundingSmall
        : Appearance.regaliaEverywhere ? Appearance.regalia.controlRadius
        : Appearance.zzzEverywhere ? Appearance.zzz.cornerRadius
        : Appearance.alisEverywhere ? Appearance.alis.roundingSmall
        : Appearance.rounding.small
    readonly property int headerPaddingX: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.controlPaddingHorizontal : 12) * Appearance.fontSizeScale)
    readonly property int headerPaddingY: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.controlPaddingVertical : 7) * Appearance.fontSizeScale)

    // ── Group (SettingsGroup) ──
    readonly property int groupRadius: Appearance.angelEverywhere ? Appearance.angel.roundingSmall
        : Appearance.regaliaEverywhere ? Appearance.regalia.roundSmall
        : Appearance.zzzEverywhere ? Appearance.zzz.cornerRadius
        : Appearance.alisEverywhere ? Appearance.alis.roundingSmall
        : Appearance.rounding.small
    readonly property int groupPadding: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.tilePadding : 12) * Appearance.fontSizeScale)
    readonly property int groupSpacing: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.tileGap : 7) * Appearance.fontSizeScale)

    // ── Colors ──
    // In angel/aurora, cards are more transparent to let the content area's
    // GlassBackground blur show through (like Overlay widgets do).
    readonly property color cardColor: Config.options?.panelFamily === "abyss" ? AbyssStyle.contentLayer : Appearance.angelEverywhere
        ? ColorUtils.transparentize(Appearance.colors.colLayer1Base, Appearance.angel.cardTransparentize * 0.7)
        // bg3 (not tile): the content field sits at bg2 now, so cards must lift a
        // clear step above it instead of matching it — depth by layer, not stroke.
        // ZZZ: transparent so the card complements the window/console ground
        // (dark or light) instead of stacking another dark plate. Definition comes
        // from the diagonal pattern + accent bar, not a filled surface + line.
        : Appearance.regaliaEverywhere ? Appearance.regalia.surfacePlate
        : Appearance.zzzEverywhere ? "transparent"
        : Appearance.alisEverywhere ? Appearance.alis.colLayer1
        : Appearance.auroraEverywhere ? ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.85)
        : Appearance.colors.colLayer1
    readonly property color cardBorderColor: Appearance.angelEverywhere
        ? Appearance.angel.colCardBorder
        : Appearance.regaliaEverywhere ? "transparent"
        : Appearance.zzzEverywhere ? Appearance.zzz.hairline
        : Appearance.alisEverywhere ? Appearance.alis.colBorder
        : Appearance.auroraEverywhere ? Appearance.aurora.colPopupBorder
        : Appearance.colors.colLayer0Border

    readonly property color groupColor: Config.options?.panelFamily === "abyss" ? Qt.alpha(Appearance.colors.colLayer2Base,AbyssStyle.contentOpacity*.55) : Appearance.angelEverywhere
        ? ColorUtils.transparentize(Appearance.colors.colLayer2Base, Appearance.angel.popupTransparentize * 0.6)
        : Appearance.regaliaEverywhere ? "transparent"
        : Appearance.zzzEverywhere ? "transparent"
        : Appearance.alisEverywhere ? ColorUtils.transparentize(Appearance.alis.colLayer2, 0.45)
        : Appearance.auroraEverywhere ? ColorUtils.transparentize(Appearance.colors.colLayer2Base, 0.88)
        : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.4)
    readonly property color groupBorderColor: Appearance.angelEverywhere
        ? Appearance.angel.colBorderSubtle
        : Appearance.regaliaEverywhere ? "transparent"
        : Appearance.zzzEverywhere ? Appearance.zzz.hairlineStrong
        : Appearance.alisEverywhere ? Appearance.alis.colBorderSubtle
        : Appearance.auroraEverywhere ? Appearance.aurora.colPopupBorder
        : Appearance.colors.colLayer0Border

    // ── Header hover ──
    readonly property color headerHoverColor: Appearance.angelEverywhere
        ? Appearance.angel.colGlassCardHover
        : Appearance.regaliaEverywhere ? Appearance.regalia.surfacePlateHover
        : Appearance.zzzEverywhere ? Appearance.zzz.paperAlt
        : Appearance.alisEverywhere ? Appearance.alis.colLayer1Hover
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover
        : Appearance.colors.colLayer1Hover

    // ── Accent bar (left edge on expanded section) ──
    readonly property color accentColor: Appearance.angelEverywhere
        ? Appearance.angel.colPrimary
        : Appearance.regaliaEverywhere ? Appearance.regalia.onColor
        : Appearance.zzzEverywhere ? Appearance.zzz.accent
        : Appearance.alisEverywhere ? Appearance.alis.colAccent
        : Appearance.colors.colPrimary

    // ── Section title colors ──
    readonly property color titleExpandedColor: Appearance.angelEverywhere
        ? Appearance.angel.colText
        : Appearance.regaliaEverywhere ? Appearance.regalia.onColor
        : Appearance.zzzEverywhere ? Appearance.zzz.onColor
        : Appearance.alisEverywhere ? Appearance.alis.colText
        : Appearance.colors.colOnSecondaryContainer
    readonly property color titleCollapsedColor: Appearance.angelEverywhere
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
    readonly property color iconExpandedColor: Appearance.angelEverywhere
        ? Appearance.angel.colPrimary
        : Appearance.regaliaEverywhere ? Appearance.regalia.hardwarePrimary
        : Appearance.zzzEverywhere ? Appearance.zzz.onSticker
        : Appearance.alisEverywhere ? Appearance.alis.colAccent
        : Appearance.colors.colPrimary
    readonly property color iconCollapsedColor: Appearance.angelEverywhere
        ? Appearance.angel.colTextMuted
        : Appearance.regaliaEverywhere ? Appearance.regalia.hardwareSecondary
        : Appearance.zzzEverywhere ? Appearance.zzz.onSecondary
        : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary
        : Appearance.colors.colOnSurfaceVariant

    // ── In-page task navigation ──
    // One quiet shared rail; native rectangles need no per-tab texture/blur.
    readonly property real taskTabPadding: 6 * Appearance.fontSizeScale
    readonly property real taskTabHeight: 40 * Appearance.fontSizeScale
    readonly property real taskTabRadius: 16 * Appearance.fontSizeScale
    readonly property real taskRailRadius: 22 * Appearance.fontSizeScale
    readonly property color taskRailBase: Appearance.colors.colLayer2Base
    readonly property color taskRailColor: Qt.alpha(taskRailBase, AbyssStyle.contentOpacity * .72)
    readonly property color taskTabSelectedBase: ColorUtils.mix(AbyssStyle.accent,
        Appearance.colors.colLayer1Base, .26)
    readonly property color taskTabSelectedColor: Qt.alpha(taskTabSelectedBase, AbyssStyle.contentOpacity)
    readonly property color taskTabHoverColor: Qt.alpha(AbyssStyle.accent, AbyssStyle.contentOpacity * .16)
    readonly property color taskTabPressedColor: Qt.alpha(AbyssStyle.accent, AbyssStyle.contentOpacity * .24)
    readonly property color taskTabInk: ColorUtils.ensureReadable(Appearance.colors.colOnLayer1, taskRailBase)
    readonly property color taskTabSelectedInk: ColorUtils.ensureReadable(Appearance.colors.colOnPrimaryContainer, taskTabSelectedBase)
    readonly property color taskTabFocusColor: ColorUtils.ensureReadable(AbyssStyle.accent, taskRailBase, 3)

    // ── Navigation rail ──
    readonly property int navWidth: 180
    readonly property int navItemHeight: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.controlHeight : 34) * Appearance.fontSizeScale)
    readonly property int navCategorySpacing: Math.round((Appearance.regaliaEverywhere ? Appearance.regalia.tileGap + Appearance.regalia.controlGap : 10) * Appearance.fontSizeScale)
    readonly property int navItemSpacing: Appearance.regaliaEverywhere ? Appearance.regalia.controlGap : 2

    // One continuous theme-derived gradient across the flat Settings list.
    // No page owns a hard-coded icon color.
    function navigationIconColor(position: int, count: int, selected = false): color {
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
