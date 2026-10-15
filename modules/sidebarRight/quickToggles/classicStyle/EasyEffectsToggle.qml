import qs.modules.common.widgets
import qs.modules.common.functions
import qs
import qs.services
import qs.services.deferred
import QtQuick
import Quickshell.Io
import Quickshell

QuickToggleButton {
    id: root
    accessibleName: Translation.tr("EasyEffects")
    visible: EasyEffects.available
    toggled: EasyEffects.active
    buttonIcon: "instant_mix"

    Component.onCompleted: {
        EasyEffects.fetchActiveState()
    }

    onClicked: {
        EasyEffects.toggle()
    }

    altAction: () => {
        EasyEffects.openSettings()
        GlobalStates.sidebarRightOpen = false
    }

    StyledToolTip {
        text: Translation.tr("EasyEffects | Right-click to configure")
    }
}
