import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

GroupButton {
    id: root
    Accessible.checkable: true
    Accessible.checked: root.toggled
    property bool abyssTaskNavigation: false
    horizontalPadding: root.abyssTaskNavigation ? 14 * Appearance.fontSizeScale : 11
    verticalPadding: root.abyssTaskNavigation ? 9 * Appearance.fontSizeScale : 6
    baseHeight: Math.max(contentItem.implicitHeight + verticalPadding * 2,
        root.abyssTaskNavigation ? SettingsMaterialPreset.taskTabHeight : 0)
    bounce: false
    property bool useAbyssPillShape: true
    waveFace: !root.abyssTaskNavigation && root.useAbyssPillShape && Config.options?.panelFamily === "abyss"
    property string buttonIcon
    // Opt-in high contrast for compact category tabs on dense Settings pages.
    property bool highContrastSelection: false
    selectionOutlineWidth: root.abyssTaskNavigation && root.visualFocus ? 1
        : root.highContrastSelection && root.toggled ? 2 : 0
    selectionOutlineColor: root.abyssTaskNavigation ? SettingsMaterialPreset.taskTabFocusColor : Appearance.colors.colPrimary
    colBackgroundToggled: root.abyssTaskNavigation ? SettingsMaterialPreset.taskTabSelectedColor : root.highContrastSelection
        ? Appearance.colors.colPrimaryContainer : Appearance.colors.colPrimary
    colBackgroundToggledHover: root.abyssTaskNavigation ? ColorUtils.mix(SettingsMaterialPreset.taskTabSelectedColor,
        SettingsMaterialPreset.taskTabHoverColor, .88) : root.highContrastSelection
        ? Qt.darker(Appearance.colors.colPrimaryContainer, 1.06)
        : Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: root.abyssTaskNavigation ? ColorUtils.mix(SettingsMaterialPreset.taskTabSelectedColor,
        SettingsMaterialPreset.taskTabPressedColor, .8) : root.highContrastSelection
        ? Qt.darker(Appearance.colors.colPrimaryContainer, 1.12)
        : Appearance.colors.colPrimaryActive
    property string buttonPreviewKind: ""
    property real maxTextWidth: 180
    // Opt-in only. Most segmented controls keep their centered label; callers
    // such as the TLP category browser can request a tidy left-aligned list
    // without changing alignment shell-wide.
    property bool leftAlignContent: false
    // Opt-in for Planner: keep the source label mounted and reveal its clipped
    // width left-to-right. Collapse retracts the right edge without dropping text.
    property bool revealActiveLabelOnly: false
    // The group coordinates which label expands, independently of the
    // highlighted selection. Keeps rightward selection swaps deterministic.
    property bool selectedLabelExpanded: root.toggled
    readonly property bool labelExpanded: !root.revealActiveLabelOnly
        || root.selectedLabelExpanded
    clip: root.revealActiveLabelOnly
    property bool leftmost: false
    property bool rightmost: false
    readonly property bool showZzzPreview: false
    leftRadius: root.abyssTaskNavigation ? Math.min(height / 2, SettingsMaterialPreset.taskTabRadius) : ((root.useAbyssPillShape && Config.options?.panelFamily === "abyss") || toggled || leftmost)
        ? (height / 2) : Appearance.rounding.unsharpenmore
    rightRadius: root.abyssTaskNavigation ? Math.min(height / 2, SettingsMaterialPreset.taskTabRadius) : ((root.useAbyssPillShape && Config.options?.panelFamily === "abyss") || toggled || rightmost)
        ? (height / 2) : Appearance.rounding.unsharpenmore
    Behavior on leftRadius {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
    }
    Behavior on rightRadius {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
    }
    colBackground: root.abyssTaskNavigation ? "transparent" : root.useAbyssPillShape && Config.options?.panelFamily === "abyss"
        ? Qt.alpha(Appearance.colors.colPrimary,.1) : Appearance.colors.colSecondaryContainer
    colBackgroundHover: root.abyssTaskNavigation ? SettingsMaterialPreset.taskTabHoverColor : root.useAbyssPillShape && Config.options?.panelFamily === "abyss"
        ? Qt.alpha(Appearance.colors.colPrimary,.18) : Appearance.colors.colSecondaryContainerHover
    colBackgroundActive: root.abyssTaskNavigation ? SettingsMaterialPreset.taskTabPressedColor : root.useAbyssPillShape && Config.options?.panelFamily === "abyss"
        ? Qt.alpha(Appearance.colors.colPrimary,.26) : Appearance.colors.colSecondaryContainerActive

    contentItem: RowLayout {
        // Keep the icon fixed at the leading edge while the clipped text
        // viewport slides open from left to right (and retracts from the right).
        spacing: root.buttonIcon?.length > 0 && root.buttonText?.length > 0
            && root.labelExpanded ? 4 : 0
        clip: root.revealActiveLabelOnly

        Behavior on spacing {
            enabled: Appearance.animationsEnabled && root.enableImplicitWidthAnimation
            NumberAnimation { duration: 160; easing.type: Easing.InOutCubic }
        }

        Item {
            id: iconReveal
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.buttonIcon?.length > 0 ? materialSymbol.implicitWidth : 0
            implicitHeight: materialSymbol.implicitHeight
            opacity: root.buttonIcon?.length > 0 ? 1 : 0
            visible: opacity > 0
            clip: true

            Behavior on implicitWidth {
                enabled: Appearance.animationsEnabled && root.enableImplicitWidthAnimation
                animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
            }
            Behavior on opacity {
                enabled: Appearance.animationsEnabled && root.enableImplicitWidthAnimation
                animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            MaterialSymbol {
                id: materialSymbol
                anchors.centerIn: parent
                text: root.buttonIcon
                iconSize: Appearance.font.pixelSize.normal
                color: root.abyssTaskNavigation
                    ? (root.toggled ? SettingsMaterialPreset.taskTabSelectedInk : SettingsMaterialPreset.taskTabInk)
                    : root.toggled
                    ? (root.highContrastSelection ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnPrimary)
                    : Appearance.colors.colOnSecondaryContainer
            }
        }

        Item {
            Layout.minimumWidth: 0
            implicitWidth: root.buttonText?.length > 0 && root.labelExpanded
                ? Math.min(textItem.implicitWidth, root.maxTextWidth) : 0
            implicitHeight: textMetrics.height // Force height to that of regular text
            // Do not unmount or fade a label during selection changes: fading
            // and visible:opacity>0 could drop the text on rapid toggles.
            visible: root.buttonText?.length > 0
            clip: true

            Behavior on implicitWidth {
                enabled: Appearance.animationsEnabled && root.enableImplicitWidthAnimation
                NumberAnimation { duration: 190; easing.type: Easing.InOutCubic }
            }
            TextMetrics {
                id: textMetrics
                font.family: Appearance.font.family.main
                text: "Abc"
            }

            StyledText {
                id: textItem
                // The glyphs remain at full natural width behind a clipping
                // viewport. Animating the viewport edge reveals left->right
                // and collapses right->left without intermediate ellipses.
                x: 0
                y: 0
                width: root.revealActiveLabelOnly
                    ? Math.min(implicitWidth, root.maxTextWidth) : parent.width
                height: parent.height
                horizontalAlignment: root.revealActiveLabelOnly || root.leftAlignContent
                    ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: root.revealActiveLabelOnly ? Text.ElideNone : Text.ElideRight
                maximumLineCount: 1
                color: root.abyssTaskNavigation
                    ? (root.toggled ? SettingsMaterialPreset.taskTabSelectedInk : SettingsMaterialPreset.taskTabInk)
                    : root.toggled
                    ? (root.highContrastSelection ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnPrimary)
                    : Appearance.colors.colOnSecondaryContainer
                font.weight: root.highContrastSelection && root.toggled
                    ? Font.DemiBold : Font.Normal
                text: root.buttonText
            }
        }

        // With GridLayout-forced equal button widths, this absorbs only the
        // trailing free space and leaves icon + label against the left inset.
        Item {
            visible: root.leftAlignContent
            Layout.fillWidth: root.leftAlignContent
            Layout.preferredWidth: root.leftAlignContent ? 1 : 0
        }
    }
}
