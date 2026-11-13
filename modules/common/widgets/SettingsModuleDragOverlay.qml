import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    objectName: "settingsModuleDragOverlay"

    anchors.fill: parent
    z: 999
    visible: SettingsLayoutManager.draggingModule
    enabled: false

    readonly property point localDragPt: root.visible
        ? root.mapFromItem(null, SettingsLayoutManager.dragSceneX, SettingsLayoutManager.dragSceneY)
        : Qt.point(0, 0)
    readonly property var dropHit: SettingsLayoutManager.hoveredDropTarget

    Rectangle {
        id: ghostCard
        x: Math.round(root.localDragPt.x - width * 0.5)
        y: Math.round(root.localDragPt.y - 24)
        width: Math.min(340, Math.max(210, SettingsLayoutManager.dragCardWidth * 0.72))
        height: 64
        radius: SettingsMaterialPreset.cardRadius
        color: Qt.alpha(Appearance.colors.colLayer3, 0.94)
        border.width: 2
        border.color: Appearance.colors.colPrimary

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: SettingsLayoutManager.draggedModuleIcon || "tune"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: SettingsLayoutManager.draggedModuleTitle
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const spec = root.dropHit?.spec;
                    if (!spec)
                        return Translation.tr("Drag onto any Card, Column, Sub-Tab, or Sidebar Tab");
                    if (spec.kind === "subtab")
                        return `${Translation.tr("Drop into Sub-Tab")}: ${spec.label || spec.subTabKey}`;
                    if (spec.kind === "sidebar-page" || spec.kind === "sidebar-custom-tab")
                        return `${Translation.tr("Drop into Sidebar Tab")}: ${spec.label || ""}`;
                    if (spec.kind === "column")
                        return `${Translation.tr("Drop into Column")}: ${spec.label || spec.column}`;
                    if (spec.kind === "card")
                        return `${root.dropHit.insertAfter ? Translation.tr("Place after") : Translation.tr("Place before")}: ${spec.label || spec.moduleId}`;
                    if (spec.kind === "canvas")
                        return Translation.tr("Place on Freeform Canvas");
                    return Translation.tr("Release to place module");
                }
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.dropHit ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }
}
