import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls.FluentWinUI3
import QtQuick.Controls

TextField {
    id: root
    
    clip: true
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    color: Looks.colors.fg
    readonly property string liveText: preeditText
        ? (text.slice(0, cursorPosition) + preeditText + text.slice(cursorPosition))
        : text

    palette {
        active: Looks.colors.accent
    }

    font {
        hintingPreference: Font.PreferDefaultHinting
        family: Looks.font.family.ui
        pixelSize: Looks.font.pixelSize.normal
        weight: Looks.font.weight.regular
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
    }

    TextInputContextMenu {
        target: root
    }
}
