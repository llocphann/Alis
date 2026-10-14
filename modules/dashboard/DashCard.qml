import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks

/**
 * Shared Material card surface for Dashboard modules.
 *
 * Dashboard cards use the same Material layer hierarchy as Sidebar surfaces.
 * The Dashboard shell is layer-0; each module sits one level above it on
 * layer-1 so cards read as a subtle raised surface rather than detached tiles.
 */
Rectangle {
    id: root

    property string title: ""
    property string icon: ""
    default property alias content: inner.data

    readonly property bool compact:
        (Config.options?.dashboard?.appearance?.density ?? "comfortable")
            === "compact"
    readonly property real cardOpacity: Math.max(0.3, Math.min(1,
        Config.options?.dashboard?.appearance?.cardOpacity ?? 1))
    readonly property bool showTitle:
        Config.options?.dashboard?.appearance?.showCardTitles ?? true
    readonly property real pad: compact ? 8 : 12

    // Compatibility properties consumed by a few Dashboard content components.
    // They no longer select the card background: Material owns the surface.
    readonly property bool alisEverywhere: Appearance.alisEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere
    readonly property bool zzzEverywhere: Appearance.zzzEverywhere

    readonly property color colText: Appearance.colors.colOnSurface
    readonly property color colSubtext: Appearance.colors.colOnSurfaceVariant
    readonly property color colAccent: Appearance.colors.colPrimary

    Layout.fillWidth: true
    implicitHeight: contentColumn.implicitHeight + root.pad * 2

    radius: Appearance.rounding.small
    readonly property color sidebarRaisedSurface: Config.options?.panelFamily === "abyss" ? AbyssStyle.contentLayer : Appearance.colors.colLayer1
    color: root.cardOpacity >= 0.999
        ? root.sidebarRaisedSurface
        : ColorUtils.applyAlpha(
            root.sidebarRaisedSurface,
            root.cardOpacity * root.sidebarRaisedSurface.a)
    border.width: 0
    border.color: "transparent"
    clip: true

    Behavior on color {
        enabled: Appearance.animationsEnabled
        ColorAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve:
                Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.compact ? 6 : 8

        RowLayout {
            visible: root.title.length > 0 && root.showTitle
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                visible: root.icon.length > 0
                text: root.icon
                iconSize: Appearance.font.pixelSize.larger
                color: root.colAccent
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: root.colText
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            id: inner
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // Non-filling children sit naturally in the center of their card;
            // full-width/full-height widgets keep ownership of their alignment.
            Component.onCompleted: {
                for (let i = 0; i < inner.children.length; i++) {
                    const child = inner.children[i]
                    if (child.Layout
                            && child.Layout.fillWidth !== true
                            && child.Layout.fillHeight !== true
                            && child.Layout.alignment === 0) {
                        child.Layout.alignment =
                            Qt.AlignHCenter | Qt.AlignVCenter
                    }
                }
            }
        }
    }
}
