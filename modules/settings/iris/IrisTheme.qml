pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.abyss.looks

Singleton {
    id: root

    readonly property bool isAbyss: (Config.options?.panelFamily ?? "abyss") === "abyss"
    readonly property real scale: Appearance.fontSizeScale ?? 1.0

    // Surfaces — derived strictly from Appearance.colors & AbyssStyle (never hardcoded black)
    readonly property color panelBg: Appearance.colors.colLayer0
    readonly property color sidebarBg: root.isAbyss
        ? Qt.alpha(Appearance.colors.colLayer1Base, AbyssStyle.contentOpacity * 0.42)
        : Qt.alpha(Appearance.colors.colLayer1Base, 0.52)
    readonly property color railBg: root.isAbyss
        ? Qt.alpha(Appearance.colors.colLayer1Base, AbyssStyle.contentOpacity * 0.36)
        : Qt.alpha(Appearance.colors.colLayer1Base, 0.44)
    readonly property color plate: root.isAbyss
        ? AbyssStyle.contentLayer
        : Appearance.colors.colLayer1
    readonly property color plateRaised: root.isAbyss
        ? Qt.alpha(Appearance.colors.colLayer2Base, AbyssStyle.contentOpacity * 0.72)
        : Appearance.colors.colLayer2
    readonly property color plateHover: Appearance.colors.colLayer1Hover
    readonly property color platePressed: Appearance.colors.colLayer1Active

    // Hairlines & strokes
    readonly property color hairline: Qt.alpha(Appearance.colors.colOutlineVariant, 0.28)
    readonly property color hairlineStrong: Qt.alpha(Appearance.colors.colOutlineVariant, 0.44)

    // Ink
    readonly property color text: Appearance.colors.colOnLayer0
    readonly property color textSecondary: Appearance.colors.colOnLayer1
    readonly property color textMuted: Appearance.colors.colSubtext
    readonly property color textDim: Qt.alpha(Appearance.colors.colSubtext, 0.74)

    // Accent & refraction washes
    readonly property color accent: root.isAbyss
        ? AbyssStyle.accent
        : Appearance.colors.colPrimary
    readonly property color accentSecondary: Appearance.colors.colSecondary
    readonly property color accentContainer: Appearance.colors.colPrimaryContainer
    readonly property color onAccent: Appearance.colors.colOnPrimary
    readonly property color onAccentContainer: Appearance.colors.colOnPrimaryContainer
    readonly property color accentTint: Qt.alpha(root.accent, 0.14)
    readonly property color accentTintHover: Qt.alpha(root.accent, 0.22)
    readonly property color accentTintStrong: Qt.alpha(root.accent, 0.28)
    readonly property color accentBorder: Qt.alpha(root.accent, 0.38)
    readonly property color heroWashStart: Qt.alpha(root.accent, 0.16)
    readonly property color heroWashMid: Qt.alpha(Appearance.colors.colSecondary, 0.08)
    readonly property color heroWashEnd: Qt.alpha(Appearance.colors.colLayer1Base, 0.0)

    // Radii
    readonly property int radiusSmall: Appearance.rounding.small
    readonly property int radiusCard: Appearance.rounding.normal
    readonly property int radiusLarge: Appearance.rounding.large
    readonly property int radiusPill: Appearance.rounding.full

    // Geometry
    readonly property int railAutoBreakpoint: 1220
    readonly property int pageMaxWidth: Math.round(860 * root.scale)

    function sidebarWidthFor(totalWidth: real): int {
        const clampedScale = Math.min(1.12, Math.max(0.9, root.scale))
        if (totalWidth > 0 && totalWidth < 880)
            return Math.round(188 * clampedScale)
        return Math.round(204 * clampedScale)
    }

    function railWidthFor(totalWidth: real): int {
        const clampedScale = Math.min(1.12, Math.max(0.9, root.scale))
        if (totalWidth > 0 && totalWidth < 1340)
            return Math.round(244 * clampedScale)
        return Math.round(264 * clampedScale)
    }

    // Motion
    readonly property int fastMs: Appearance.animationsEnabled ? 150 : 0
    readonly property int glideMs: Appearance.animationsEnabled ? 220 : 0
}
