pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    function _isInternalMicMonitorNode(node): bool {
        if (!node)
            return false
        const props = node.properties ?? ({})
        const rawName = String(node.name ?? "").toLowerCase()
        const nodeName = String(props["node.name"] ?? node.name ?? "").toLowerCase()
        const appName = String(props["application.name"] ?? "").toLowerCase()
        const mediaName = String(props["media.name"] ?? "").toLowerCase()
        return rawName === "alis-mic-meter"
            || rawName === "alis-audio"
            || rawName === "alis-audio-spectrum"
            || nodeName === "alis-mic-meter"
            || nodeName === "alis-audio"
            || nodeName === "alis-audio-spectrum"
            || appName === "alis-mic-meter"
            || appName === "alis-audio"
            || appName === "alis-audio-spectrum"
            || mediaName === "alis mic meter"
            || mediaName === "alis audio analyzer"
    }

    // Mic active: device -> stream link (same as Audio.micBeingAccessed)
    property bool micActive: (Pipewire.links?.values ?? []).some(link =>
        !(link?.source?.isStream ?? true)
            && !(link?.source?.isSink ?? true)
            && (link?.target?.isStream ?? false)
            && !root._isInternalMicMonitorNode(link?.target)
    )

    // Screen sharing not detected here - done directly in UtilButtons/SystemButton
    property bool screenSharing: false
}
