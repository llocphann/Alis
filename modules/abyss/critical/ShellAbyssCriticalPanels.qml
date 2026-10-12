import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

// URL boundaries keep optional presentation errors out of the family entry.
Item {
    id: root

    readonly property bool abyssBackgroundEnabled:
        Config.ready && (Config.options?.enabledPanels ?? []).includes("abyssBackground")

    // Niri cold-start pointer contract: a perimeter constructed as soon as
    // Config.ready can paint correctly while its initial native input path
    // never delivers hover. The owner reproduced 0/16 hover at startup and
    // recovered by *recreating only this subtree* after deferred readiness,
    // without a family switch (2026-10-09 native evidence).
    //
    // Mount the actual production host once the shell's deferred services
    // and panel surfaces have settled. This avoids a blind startup remount
    // and does not change popup content, its geometry or shaped hitboxes.
    property bool perimeterInitialMountReady: false
    Timer {
        id: perimeterInitialMountTimer
        interval: 150
        repeat: false
        running: Config.ready && GlobalStates.deferredPanelsReady
            && !root.perimeterInitialMountReady
        onTriggered: root.perimeterInitialMountReady = true
    }

    // Native acceptance isolated this exact remedy: refreshing Region.changed,
    // swapping Region identity and hiding/showing PanelWindow all failed;
    // destroying and reconstructing the entire AbyssPerimeter subtree restored
    // hover (16/16 native samples). A delayed *first* construction still failed
    // (0/24), so delay alone is not a remedy.
    //
    // Recreate once, only if the shell booted directly into Abyss on Niri,
    // after all presented output fields have emitted their first frame and
    // remained ready for 600 ms. The automatic cycle shares the same bounded
    // destruction/restoration path as the proven manual remount experiment.
    // This is a native-initialization workaround, not a claim that the internal
    // Quickshell/Niri cause is proven.
    readonly property bool nativeFirstFramesReady:
        perimeterLoader.item?.nativeInputFramesReady ?? false
    property bool coldPerimeterRecreated: false
    Timer {
        id: nativeColdPerimeterRecreate
        interval: 600
        repeat: false
        running: CompositorService.isNiri
            && GlobalStates.abyssColdPerimeterRecreatePending
            && GlobalStates.deferredPanelsReady
            && root.perimeterInitialMountReady
            && root.nativeFirstFramesReady
            && !root.coldPerimeterRecreated
            && !root.diagnosticPerimeterUnmounted
        onTriggered: {
            root.coldPerimeterRecreated = true
            GlobalStates.abyssColdPerimeterRecreatePending = false
            root.diagnosticPerimeterUnmounted = true
            perimeterProbeRestore.restart()
            console.info("[Abyss] Cold Niri perimeter re-created after first native frame")
        }
    }

    // Production-host lifecycle experiment: recreate Perimeter but leave
    // the shell, config and current panelFamily unchanged. Unlike toggling
    // PanelWindow.visible, setting LazyLoader.active=false destroys its QML
    // subtree and the native Wayland window owned by that subtree.
    property bool diagnosticPerimeterUnmounted: false
    Timer {
        id: perimeterProbeRestore
        interval: 450
        repeat: false
        onTriggered: root.diagnosticPerimeterUnmounted = false
    }
    IpcHandler {
        target: "abyssHostProbe"
        function status(): string {
            return JSON.stringify({
                family: Config.options?.panelFamily ?? "",
                perimeterLoaded: perimeterLoader.item !== null,
                perimeterActive: perimeterLoader.active,
                diagnosticUnmounted: root.diagnosticPerimeterUnmounted,
                shellEntryReady: GlobalStates.shellEntryReady,
                deferredPanelsReady: GlobalStates.deferredPanelsReady,
                initialMountReady: root.perimeterInitialMountReady,
                nativeFirstFramesReady: root.nativeFirstFramesReady,
                coldRecreatePending: GlobalStates.abyssColdPerimeterRecreatePending,
                coldRecreated: root.coldPerimeterRecreated
            })
        }
        function remountPerimeter(): string {
            if ((Config.options?.panelFamily ?? "") !== "abyss"
                    || GlobalStates.abyssEditing || GlobalStates.screenLocked
                    || root.diagnosticPerimeterUnmounted)
                return JSON.stringify({skipped:true, reason:"not safe during current state"})
            root.diagnosticPerimeterUnmounted = true
            perimeterProbeRestore.restart()
            return JSON.stringify({
                skipped:false, experiment:"destroy-recreate-AbyssPerimeter",
                restoreAfterMs:450, familyChanged:false
            })
        }
    }

    LazyLoader {
        id: perimeterLoader
        objectName:"abyssPerimeterLoader"
        active: Config.ready
            && root.perimeterInitialMountReady
            && !root.diagnosticPerimeterUnmounted
        source: "../AbyssPerimeter.qml"
    }
    LazyLoader {
        active: root.abyssBackgroundEnabled
        source: "../../background/Background.qml"
    }

    // Stable Material kept a dedicated Background-layer wallpaper surface inside
    // Niri's overview backdrop. Abyss folds iiBackground/iiBackdrop into one public
    // background module, so retain that renderer under the same module gate instead
    // of losing wallpaper when Niri zooms the workspace from a hot corner.
    LazyLoader {
        active: root.abyssBackgroundEnabled
            && (Config.options?.background?.backdrop?.enable ?? false)
        source: "../../background/Backdrop.qml"
    }
}
