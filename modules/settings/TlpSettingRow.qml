import QtQuick
import QtQuick.Layouts
import qs.services

// Compatibility input contract; application-specific editors live in AlisIntergration.
Item {
    id: root
    required property var definition
    property string groupDescription: ""
    property bool compactProfileRows: false
    property bool singleSettingGroup: false
    Layout.fillWidth: true
    implicitHeight: content.item?.implicitHeight ?? 0
    Loader {
        id: content
        width: parent.width
        active: AlisIntergration.tlpEnabled
        function loadSettings(): void {
            if (!active) { source = ""; return }
            const path = Qt.resolvedUrl(AlisIntergration.settingsSource("tlpRow"))
            if (String(source) === String(path)) return
            setSource(path, {
                definition: Qt.binding(() => root.definition),
                compactProfileRows: Qt.binding(() => root.compactProfileRows),
                singleSettingGroup: Qt.binding(() => root.singleSettingGroup),
                groupDescription: Qt.binding(() => root.groupDescription)
            })
        }
        onActiveChanged: loadSettings()
        Component.onCompleted: loadSettings()
    }
}
