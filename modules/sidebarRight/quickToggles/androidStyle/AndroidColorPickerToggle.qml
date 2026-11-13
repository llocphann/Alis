import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

AndroidQuickToggleButton {
    id: root

    name: Translation.tr("Color picker")
    statusText: ""
    accessibilityCheckable: false
    toggled: false
    buttonIcon: "colorize"

    mainAction: () => {
        GlobalStates.sidebarRightOpen = false;
        ColorPickerService.start()
    }

    StyledToolTip {
        text: Translation.tr("Color picker")
    }
}
