import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

GridLayout {
    id: root
    objectName: "settingsBentoGrid"

    property int maxColumns: 2
    property real minTwoColumnWidth: 560

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    columns: width >= minTwoColumnWidth ? maxColumns : 1
    uniformCellWidths: columns > 1
    columnSpacing: SettingsMaterialPreset.pageSpacing
    rowSpacing: SettingsMaterialPreset.pageSpacing
}
