pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Text-only activity state; a stable label, with emphasis supplied by motion.
StyledText {
    id: root
    text: Translation.tr("Loading")
    horizontalAlignment: Text.AlignHCenter
    font.pixelSize: Appearance.font.pixelSize.small
    font.weight: Font.DemiBold
    color: Appearance.colors.colSubtext

    SequentialAnimation on opacity {
        running: root.visible && (root.Window.window?.visible ?? true) && Appearance.animationsEnabled
        loops: Animation.Infinite
        NumberAnimation { from: 0.55; to: 1; duration: 780; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.55; duration: 780; easing.type: Easing.InOutSine }
        onRunningChanged: { if (!running) root.opacity = 1 }
    }
    SequentialAnimation on scale {
        running: root.visible && (root.Window.window?.visible ?? true) && Appearance.animationsEnabled
        loops: Animation.Infinite
        NumberAnimation { from: 0.98; to: 1.04; duration: 780; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.04; to: 0.98; duration: 780; easing.type: Easing.InOutSine }
        onRunningChanged: { if (!running) root.scale = 1 }
    }
}
