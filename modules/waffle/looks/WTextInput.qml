import QtQuick
import QtQuick.Controls

TextInput {
    id: root
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    color: Looks.colors.fg
    readonly property string liveText: preeditText
        ? (text.slice(0, cursorPosition) + preeditText + text.slice(cursorPosition))
        : text

    font {
        hintingPreference: Font.PreferFullHinting
        family: Looks.font.family.ui
        pixelSize: Looks.font.pixelSize.large
        weight: Looks.font.weight.regular
    }

    selectionColor: Looks.colors.selection
}
