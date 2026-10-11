pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string outputName: ""
    property string kind: ""
    readonly property string indicatorKind:
        root.kind.length > 0 ? root.kind : GlobalStates.abyssOsdKind
    readonly property var output:
        Quickshell.screens.find(s => s.name === outputName) ?? null
    readonly property var activeKinds: {
        // Layout previews and explicit hosts select one indicator independently
        // of live desktop OSD leases. The ordinary shared host leaves kind empty.
        if (root.kind.length > 0)
            return [root.kind]
        if (GlobalStates.abyssOsdKind === "voiceSearch")
            return ["voiceSearch"]
        if (GlobalStates.osdMediaOpen)
            return ["media"]
        const kinds=[]
        if (GlobalStates.osdVolumeOpen) kinds.push("volume")
        if (GlobalStates.osdBrightnessOpen) kinds.push("brightness")
        if (GlobalStates.osdMicOpen) kinds.push("mic")
        if (GlobalStates.osdKeyboardLayoutOpen) kinds.push("keyboardLayout")
        if (kinds.length === 0)
            kinds.push(root.indicatorKind)
        return kinds
    }
    readonly property real desiredWidth:
        Math.max(indicatorRow.implicitWidth,
            message.visible ? message.implicitWidth : 0)
    readonly property real desiredHeight:
        indicatorRow.implicitHeight
            +(message.visible ? message.implicitHeight+spacing : 0)
    implicitWidth: desiredWidth
    implicitHeight: desiredHeight
    spacing: 8

    component IndicatorHost: Loader {
        required property string indicatorKind
        Layout.alignment: Qt.AlignVCenter
        source: "../../onScreenDisplay/indicators/"
            +({volume:"Volume",brightness:"Brightness",mic:"Mic",
                media:"Media",mediaOsd:"Media",keyboardLayout:"KeyboardLayout",
                voiceSearch:"VoiceSearch"}[indicatorKind] ?? "Volume")
            +"Indicator.qml"
        onLoaded: {
            if (item.connectedSurface !== undefined)
                item.connectedSurface = true
            if (indicatorKind === "brightness" && item.screen !== undefined)
                item.screen = Qt.binding(() =>
                    root.output ?? root.QsWindow.window?.screen)
        }
    }

    RowLayout {
        id: indicatorRow
        Layout.alignment: Qt.AlignHCenter
        spacing: 10

        Repeater {
            id: indicators
            model: root.activeKinds
            onItemAdded: (index, item) => { if (index === 0) root.primaryIndicator = item }
            onItemRemoved: (index, item) => { if (root.primaryIndicator === item) root.primaryIndicator = null }
            delegate: IndicatorHost {
                required property var modelData
                indicatorKind: String(modelData ?? "")
            }
        }
    }

    // The first mature indicator is also exposed to host behavior fixtures.
    property var primaryIndicator: null
    readonly property var feature: primaryIndicator?.item ?? null

    StyledText {
        id: message
        Layout.fillWidth: true
        visible: GlobalStates.abyssOsdMessage.length > 0
            && root.activeKinds.includes("volume")
        text: GlobalStates.abyssOsdMessage
        color: Appearance.colors.colError
        wrapMode: Text.WordWrap
    }
}
