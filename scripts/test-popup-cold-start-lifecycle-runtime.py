#!/usr/bin/env python3
"""Private-Niri cold mount regression: reparent and remount an Abyss popup owner.

This test isolates the source anchor/controller lifecycle while exercising real
Qt pointer events; it does not claim the full production host passed on desktop.
"""
import json
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-popup-cold-mount-") as name:
    folder = Path(name)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets",
                  "scripts", "defaults", "translations"):
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.bar
import qs.modules.abyss
ShellRoot {
    id: root
    property int clicks: 0
    property int frames: 0
    Component.onCompleted: Quickshell.watchFiles = false
    AbyssSurfaceController {
        id: controller
        presentationItem: scene
        outputWidth: scene.width
        outputHeight: scene.height
        presented: true
        edgeInsets: ({left:8,right:8,top:8,bottom:8})
    }
    FloatingWindow {
        id: output
        visible: true
        implicitWidth: 640
        implicitHeight: 360
        color: "#101820"
        Item {
            id: scene
            anchors.fill: parent
            Item { id: detached; x: 20; y: 40; width: 100; height: 55
                MouseArea {
                    id: anchor; width: 80; height: 34; hoverEnabled: true
                    onClicked: root.clicks++
                }
            }
            Item {
                id: mounted; x: 200; y: 300; width: 120; height: 55
                property var liquidController: controller
                property string attachedEdge: "bottom"
                property string kind: "clock"
            }
            AbyssBodyHost {
                id: host
                anchors.fill: parent
                readonly property var entry: controller.popupSlots[0]
                readonly property var current: entry?.popup ?? null
                identity: "coldMountHost"
                controller: controller
                edge: "bottom"
                open: current?.presentationActive ?? false
                externalProgress: current?.revealProgress ?? 0
                embeddedItem: current?.contentItem ?? null
                padding: 14; span: 210; depth: 130; along: 166
                edgeInsets: controller.edgeInsets
                Component.onCompleted: controller.registerPopupHost(0, host)
                Component.onDestruction: controller.unregisterPopupHost(0, host)
                HoverHandler {
                    parent: host.contentParent
                    enabled: host.open
                    onHoveredChanged: if (host.current) host.current._contentHovered=hovered
                }
            }
        }
    }
    StyledPopup {
        id: popup
        hoverTarget: anchor
        Rectangle { implicitWidth: 180; implicitHeight: 95; color: "#334d58" }
    }
    Loader {
        id: retiringPopup
        active: false
        sourceComponent: StyledPopup {
            hoverTarget: anchor
            Rectangle { implicitWidth: 90; implicitHeight: 50; color: "#334d58" }
        }
    }
    TestCase {
        id: test
        when: false
        optional: true
        function check(ok, message) { if(!ok) throw new Error(message) }
        function render() {
            const previous = root.frames
            check(scene.grabToImage(image => root.frames++), "render request failed")
            tryVerify(() => root.frames > previous, 2500)
        }
        function outside() { mouseMove(scene, 580, 25); wait(200); render() }
        function runChecks() {
            try {
                tryCompare(Config, "ready", true, 5000)
                Config.setNestedValue("performance.reduceAnimations", true)
                render()
                check(popup._liquidController === null, "detached cold anchor unexpectedly owns Abyss")
                check(!popup.requestedVisible, "cold popup starts open")
                anchor.parent = mounted
                anchor.x = 5; anchor.y = 4
                tryVerify(() => popup._liquidAnchor === mounted
                    && popup._liquidController === controller && popup._anchorReady, 2000)
                outside()
                mouseMove(anchor, 40, 17); wait(100); render()
                check(popup.requestedVisible && controller.activePopup === popup,
                      "cold parent attachment failed to open popup without click")
                outside()
                check(!popup.requestedVisible && controller.activePopup === null,
                      "cold popup failed to dismiss on pointer exit")
                // Family-switch analogue: owner exists, controller temporarily
                // disappears, then returns without modifying hoverTarget.
                mounted.liquidController = null
                tryVerify(() => popup._liquidController === null, 1500)
                mounted.liquidController = controller
                tryVerify(() => popup._liquidController === controller, 1500)
                mouseMove(anchor, 40, 17); wait(100); render()
                check(popup.requestedVisible && controller.activePopup === popup,
                      "re-mounted owner failed to restore hover")
                outside()
                check(root.clicks === 0, "hover regression used a click")
                // Destroy the actual popup Loader in the same turn that queued
                // cold-resolution and presentation callbacks. The surviving
                // popup must retain its owner and those callbacks must cancel.
                for (let cycle = 0; cycle < 24; cycle++) {
                    retiringPopup.active = true
                    check(retiringPopup.item !== null, "retiring popup did not load")
                    retiringPopup.item.startColdAnchorResolution()
                    retiringPopup.item.refreshAnchorOwnership()
                    retiringPopup.item.alternativeVisibleCondition = true
                    retiringPopup.active = false
                    check(retiringPopup.item === null, "popup Loader retained its item")
                }
                wait(180)
                render()
                check(popup._liquidController === controller && controller.activePopup === null,
                      "retired popup callbacks retained a stale presentation owner")
                console.info("POPUP_COLD_MOUNT_PASS")
            } catch(error) {
                console.error("POPUP_COLD_MOUNT_FAIL", error.message, error.stack)
            }
            Qt.quit()
        }
    }
    Timer { interval: 100; running: true; repeat: false; onTriggered: test.runChecks() }
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: cold popup lifecycle requires private Niri")
        cfg = folder / "config/alis"
        cfg.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        (cfg / "config.json").write_text(json.dumps(data))
        result = run_qs(folder, env, timeout=26)
        errors = ("POPUP_COLD_MOUNT_FAIL", "ReferenceError:", "TypeError:",
                  "Binding loop", "Failed to load configuration")
        if result.returncode or "POPUP_COLD_MOUNT_PASS" not in result.stdout or any(
            token in result.stdout for token in errors
        ):
            print(result.stdout)
            raise SystemExit(1)
        print("PASS: cold mount and controller remount retained hover without clicks")
