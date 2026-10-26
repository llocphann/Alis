pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

FocusScope {
    id: root
    property string outputName: ""
    property bool confirmClear: false
    focus: true
    signal closeRequested()
    readonly property var rows: {
        const query = search.text.toLowerCase()
        const pins = Cliphist.pinned.map(text => ({pin:true, value:text, preview:Cliphist.pinPreview(text)}))
        const history = Cliphist.entries.map(entry => ({pin:false, value:entry, preview:String(entry).slice(String(entry).indexOf("\t")+1)}))
        return pins.concat(history).filter(row => row.preview.toLowerCase().includes(query))
    }
    function copyRow(row): void {
        if (!row) return
        if (row.pin) Quickshell.clipboardText = row.value
        else Cliphist.copy(row.value)
        closeRequested()
    }
    function togglePinRow(row): void {
        if (!row) return
        if (row.pin) {
            Cliphist.unpin(row.value)
        } else if (Cliphist.isPinnable(row.value)) {
            const pinnedText = Cliphist.pinnedTextFor(row.value)
            if (pinnedText.length) Cliphist.unpin(pinnedText)
            else Cliphist.pinEntry(row.value)
        }
    }
    function moveSelection(delta: int): void {
        if (root.rows.length <= 0) return
        list.currentIndex = Math.max(0, Math.min(root.rows.length - 1, list.currentIndex + delta))
        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    }
    Component.onCompleted: { Cliphist.refresh(); Qt.callLater(() => root.forceActiveFocus()) }
    Connections {
        target: GlobalStates
        function onClipboardOpenChanged(): void {
            if (GlobalStates.clipboardOpen) {
                Cliphist.refresh()
                Qt.callLater(() => root.forceActiveFocus())
            }
        }
    }
    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            search.forceActiveFocus()
            search.selectAll()
            event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
            root.togglePinRow(root.rows[list.currentIndex])
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (search.activeFocus && search.text.length > 0) {
                root.forceActiveFocus()
            } else {
                root.closeRequested()
            }
            event.accepted = true
        } else if (!search.activeFocus && !(event.modifiers & Qt.ControlModifier)) {
            if (event.key === Qt.Key_J || event.key === Qt.Key_L || event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                root.moveSelection(1)
                event.accepted = true
            } else if (event.key === Qt.Key_K || event.key === Qt.Key_H || event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                root.moveSelection(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.copyRow(root.rows[list.currentIndex])
                event.accepted = true
            }
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: AbyssStyle.sectionSpacing/2
        RowLayout {
            AbyssLabel { text: "Clipboard"; font.bold: true; Layout.fillWidth: true }
            AbyssButton {
                objectName: "abyssClipboardClear"
                glyph: root.confirmClear ? "check" : "delete_sweep"
                description: root.confirmClear ? "Confirm clear" : "Clear history"
                enabled: Cliphist.entries.length > 0
                onClicked: { if (root.confirmClear) { Cliphist.wipe(); root.confirmClear = false } else root.confirmClear = true }
            }
            AbyssButton { glyph: "close"; description: "Close clipboard"; onClicked: root.closeRequested() }
        }
        AbyssSearchField {
            id: search
            Layout.fillWidth: true
            placeholderText: "Search history and pins (Ctrl+F)"
            onTextChanged: { list.currentIndex = 0; root.confirmClear = false }
            onAccepted: root.copyRow(root.rows[list.currentIndex])
            Keys.onDownPressed: root.moveSelection(1)
            Keys.onUpPressed: root.moveSelection(-1)
            Keys.onEscapePressed: {
                if (search.text.length > 0) {
                    search.text = ""
                }
                root.forceActiveFocus()
            }
            Keys.onPressed: event => {
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
                    root.togglePinRow(root.rows[list.currentIndex])
                    event.accepted = true
                }
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            model: root.rows
            currentIndex: 0
            spacing: 4
            delegate: RowLayout {
                id: row
                required property var modelData
                required property int index
                width: list.width
                readonly property bool imageEntry: !modelData.pin && Cliphist.entryIsImage(modelData.value)
                Rectangle {
                    visible: row.imageEntry
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? abyssClipboardImageItem.implicitHeight + 12 : 0
                    radius: 12
                    color: row.index === list.currentIndex
                        ? Qt.alpha(AbyssStyle.accent, 0.16)
                        : Qt.alpha(AbyssStyle.surfaceRaised, 0.45)
                    border.width: row.index === list.currentIndex ? 1 : 0
                    border.color: AbyssStyle.accent
                    CliphistImage {
                        id: abyssClipboardImageItem
                        objectName: "abyssClipboardImage"
                        visible: row.imageEntry
                        anchors.centerIn: parent
                        width: visible ? Math.min(220, implicitWidth) : 0
                        height: visible ? implicitHeight : 0
                        maxWidth: 220; maxHeight: 112
                        entry: row.imageEntry ? row.modelData.value : ""
                    }
                    TapHandler { onTapped: { list.currentIndex = row.index; root.copyRow(row.modelData) } }
                }
                AbyssButton {
                    visible: !row.imageEntry
                    Layout.fillWidth: true
                    text: row.modelData.preview
                    glyph: row.modelData.pin ? "keep" : "content_paste"
                    checked: row.index === list.currentIndex
                    onClicked: root.copyRow(row.modelData)
                }
                AbyssButton {
                    glyph: row.modelData.pin ? "keep_off" : "keep"
                    description: row.modelData.pin ? "Unpin" : "Pin text"
                    enabled: row.modelData.pin || Cliphist.isPinnable(row.modelData.value)
                    onClicked: root.togglePinRow(row.modelData)
                }
                AbyssButton { visible: !row.modelData.pin; glyph: "delete"; description: "Delete entry"; onClicked: Cliphist.deleteEntry(row.modelData.value) }
            }
        }
        AbyssLabel { visible: root.rows.length === 0; text: "No matching clipboard entries"; color: Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : "#1a1a1a" }
    }
}
