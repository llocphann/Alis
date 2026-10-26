#!/usr/bin/env python3
"""Settings must release layer-shell elevation and keyboard focus to Polkit.

Exercise the production layer/focus bindings in real QML and layer-shell windows.
Owner Niri validation with shell-owned/external Polkit agents remains separate.
"""
from pathlib import Path
import re
import tempfile
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
native = (ROOT / "modules/settings/SettingsOverlayNativeHost.qml").read_text()
focus = (ROOT / "modules/settings/SettingsFocus.qml").read_text()
service = (ROOT / "services/AlisIntergration.qml").read_text()
ui = (ROOT / "modules/settings/IntegrationsConfig.qml").read_text()
manager = (ROOT / "scripts/alis-intergration-manager.py").read_text()

bindings = {}
for name, source in (("rail", native), ("focus", focus)):
    layer = re.search(r"WlrLayershell\.layer:\s*([\s\S]*?)\n\s*WlrLayershell\.keyboardFocus:", source)
    assert layer, name + ": missing window elevation binding"
    binding = layer.group(1)
    assert "AlisIntergration.authorizationPending" in binding, name + ": external pkexec not handled"
    assert "PolkitService.active" in binding, name + ": shell Polkit not handled"
    assert "WlrLayer.Bottom" in binding, name + ": must yield to Polkit"
    assert "WlrLayer.Top" not in binding, name + ": cannot elevate Settings above Polkit"
    focus_binding = re.search(r"WlrLayershell\.keyboardFocus:\s*([\s\S]*?)\n\s*color:", source)
    assert focus_binding and "!AlisIntergration.authorizationPending" in focus_binding.group(1), (
        name + ": exclusive keyboard focus remains active during authorization")
    bindings[name] = (binding, focus_binding.group(1))

assert 'authorizationPending = ["helpers-ensure"' in service
assert '["install","remove","rollback","helpers-install","helpers-remove","helpers-ensure"]' in service
assert 'GlobalStates.settingsOverlayOpen = false' in service
assert 'GlobalStates.settingsOverlayOpen = true' in service
assert "root.authorizationPending = false" in service
assert 'privilegedAction(' not in ui
assert 'AlisIntergration.manage("helpers-' not in ui and 'AlisIntergration.manage("gateway-' not in ui
assert './setup integrations' in ui
assert '"helpers-ensure"' in manager
assert 'gateway_call("gateway-status")' in manager
assert 'gateway_call("gateway-install")' in manager
assert 'system_call("helpers-install", package_dir)' in manager

print("ALIS_INTERGRATION_POLKIT_ELEVATION_PASS rail/focus yield to native/external authentication; embedded surface hides and restores")

# Rail uses the complete production native host. Focus reuses the exact window
# bindings without loading unrelated Settings pages/services. Independent expected
# results cover all auth flags, region selection, open state and their reversals.
with tempfile.TemporaryDirectory(prefix="alis-settings-auth-") as name:
    folder = Path(name)
    (folder / "services").mkdir()
    (folder / "qmldir").write_text(
        "module qs\nsingleton GlobalStates 1.0 GlobalStates.qml\n"
        "SettingsOverlayNativeHost 1.0 SettingsOverlayNativeHost.qml\n")
    (folder / "GlobalStates.qml").write_text(
        "pragma Singleton\nimport QtQml\nQtObject {\n"
        " property bool settingsNativeDialogOpen: false\n"
        " property bool regionSelectorOpen: false\n}\n")
    (folder / "services/qmldir").write_text(
        "module qs.services\nsingleton AlisIntergration 1.0 AlisIntergration.qml\n"
        "singleton PolkitService 1.0 PolkitService.qml\n")
    for service_name, flag in (("AlisIntergration", "authorizationPending"),
                               ("PolkitService", "active")):
        (folder / f"services/{service_name}.qml").write_text(
            f"pragma Singleton\nimport QtQml\nQtObject {{ property bool {flag}: false }}\n")
    (folder / "SettingsOverlayNativeHost.qml").write_text(native)
    qml = r'''
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
ShellRoot {
 id: root
 property bool settingsOpen: false
 property int step: 0
 property int cases: 0
 property bool finished: false
 Component.onCompleted: Quickshell.watchFiles = false
 QtObject {
  id: settingsController
  property bool settingsOpen: root.settingsOpen
  property bool _closeAnimRunning: false
 }
 SettingsOverlayNativeHost { id: rail; controller: settingsController }
 PanelWindow {
  id: focusWindow
  visible: root.settingsOpen
  implicitWidth: 320; implicitHeight: 200; color: "#111820"
  WlrLayershell.namespace: "quickshell:test-settings-auth-focus"
  WlrLayershell.layer: __LAYER__
  WlrLayershell.keyboardFocus: __FOCUS__
 }
 function check(value, message) {
  if (!value) throw new Error("Settings auth case " + step + ": " + message)
 }
 Timer {
  interval: 15; running: !root.finished; repeat: true
  onTriggered: {
   try {
    const auth = GlobalStates.settingsNativeDialogOpen
        || AlisIntergration.authorizationPending || PolkitService.active
    const expectedLayer = auth ? WlrLayer.Bottom : WlrLayer.Overlay
    const expectedFocus = root.settingsOpen && !auth && !GlobalStates.regionSelectorOpen
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    for (const window of [rail, focusWindow]) {
     root.check(window.WlrLayershell.layer === expectedLayer, "layer does not yield/restore")
     root.check(window.WlrLayershell.keyboardFocus === expectedFocus, "keyboard not released/restored")
    }
    root.cases++
    if (root.step === 64) {
     root.finished = true
     console.log("ALIS_INTERGRATION_POLKIT_BINDINGS_NATIVE_PASS", JSON.stringify({cases:root.cases,hosts:2}))
     Qt.quit(); return
    }
    // Walk the full flag matrix forward and back, so auth completion/cancel,
    // pending + shell dialog overlap and reopening all restore the prior state.
    const state = root.step < 32 ? root.step : 63-root.step
    GlobalStates.settingsNativeDialogOpen = Boolean(state & 1)
    AlisIntergration.authorizationPending = Boolean(state & 2)
    PolkitService.active = Boolean(state & 4)
    GlobalStates.regionSelectorOpen = Boolean(state & 8)
    root.settingsOpen = Boolean(state & 16)
    root.step++
   } catch (error) {
    root.finished = true; console.error("ALIS_INTERGRATION_POLKIT_BINDINGS_NATIVE_FAIL", String(error)); Qt.quit()
   }
  }
 }
}
'''.replace("__LAYER__", bindings["focus"][0]).replace("__FOCUS__", bindings["focus"][1])
    (folder / "shell.qml").write_text(qml)
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: native Settings authorization bindings (Niri/Wayland unavailable)")
        else:
            result = run_qs(folder, env, timeout=20)
            print(result.stdout)
            assert result.returncode == 0, "native Settings authorization fixture failed"
            assert "ALIS_INTERGRATION_POLKIT_BINDINGS_NATIVE_PASS" in result.stdout
            assert "ALIS_INTERGRATION_POLKIT_BINDINGS_NATIVE_FAIL" not in result.stdout
            assert not re.search(r"(Type .* unavailable|ReferenceError|TypeError|Cannot assign)",
                                 result.stdout)
