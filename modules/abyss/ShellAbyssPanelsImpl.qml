import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

// Critical and specialist workflows deliberately retain their shared renderer.
// Native perimeter content is composed by the critical Abyss host.
Item {
    component DemandPanel: LazyLoader {
        required property string identifier
        required property string targetSource
        property bool open: false
        readonly property bool shouldLoad: Config.ready && GlobalStates.deferredPanelsReady && open
            && (Config.options?.enabledPanels ?? []).includes(identifier)
        loading: shouldLoad
        active: shouldLoad
        source: Qt.resolvedUrl(targetSource)
    }
    // AbyssPolkit is rendered natively inside AbyssPerimeter as a Screen-Edge
    // attached AbyssBodyHost when "abyssPolkit" is enabled, so no separate
    // fullscreen Polkit window is mounted here.
    DemandPanel { identifier: "iiRegionSelector"; open: GlobalStates.regionSelectorOpen || GlobalStates.annotationEditorOpen; targetSource: "../regionSelector/RegionSelector.qml" }
    DemandPanel { identifier: "iiTilingOverlay"; open: GlobalStates.tilingOverlayPickerOpen || GlobalStates.tilingOverlayOsdOpen; targetSource: "../tilingOverlay/TilingOverlay.qml" }
}
