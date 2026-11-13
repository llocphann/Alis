#!/usr/bin/env python3
"""Guard tray focus-grab state and Niri menu output ownership."""

from pathlib import Path
import re
import subprocess
import tempfile

TRAY_PATH = Path("modules/bar/SysTray.qml")
TRAY_ITEM_PATH = Path("modules/bar/SysTrayItem.qml")
TRAY_MENU_PATH = Path("modules/bar/SysTrayMenu.qml")
TRAY_SERVICE_PATH = Path("services/TrayService.qml")
CONTEXT_MENU_PATH = Path("modules/common/widgets/ContextMenu.qml")


DOCK_BUTTON_PATH = Path("modules/dock/DockAppButton.qml")


def _extract_block(source: str, signature: str) -> str:
    start = source.find(signature)
    if start == -1:
        raise ValueError(f"Missing signature in TrayService.qml: {signature}")
    brace_start = source.find("{", start)
    depth = 0
    for idx in range(brace_start, len(source)):
        ch = source[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                block = source[start : idx + 1]
                return re.sub(r"\)\s*:\s*(?:var|string|bool|int)\s*\{", ") {", block)
    raise ValueError(f"Unbalanced braces for: {signature}")


def _run_dedup_behavior_tests(service_text: str, failures: list[str]) -> None:
    prob_match = re.search(
        r"readonly\s+property\s+var\s+problematicApps\s*:\s*(\[.*?\])\s*\n",
        service_text,
        re.DOTALL,
    )
    if not prob_match:
        failures.append("missing problematicApps definition in TrayService.qml")
        return

    fn_signatures = (
        "function getProblematicAppInfo(item)",
        "function isValidItem(item)",
        "function _normalizeTrayMatchKey(value)",
        "function _isGenericTrayId(idKey)",
        "function getItemDedupKey(item)",
        "function _getItemAliasKeys(item)",
        "function _getItemDedupRank(item)",
        "function _canMergeTrayEntries(existing, candidate)",
        "function deduplicateItems(items)",
    )
    extracted_fns: list[str] = []
    for sig in fn_signatures:
        try:
            extracted_fns.append(_extract_block(service_text, sig))
        except ValueError as exc:
            failures.append(str(exc))
            return

    js_harness = (
        "const assert = require('node:assert/strict');\n"
        "const Status = { Passive: 0, Active: 1, NeedsAttention: 2 };\n"
        "const root = { _log: () => {}, _pinnedItems: [] };\n"
        f"const problematicApps = {prob_match.group(1)};\n"
        + "\n\n".join(extracted_fns)
        + """

// 1. Empty / null / invalid inputs
assert.deepEqual(deduplicateItems(null), []);
assert.deepEqual(deduplicateItems(undefined), []);
assert.deepEqual(deduplicateItems([]), []);
assert.deepEqual(deduplicateItems([null, undefined, {}, { id: "" }, { id: "   " }]), []);

// 2. Duplicate SNI watcher registration (watcher handoff with identical properties)
const watcherOld = {
    id: "InputMethodDaemon",
    title: "Input Method",
    tooltipTitle: "Keyboard Layout",
    icon: "input-keyboard",
    status: Status.Active,
    hasMenu: true,
    watcherGen: 1
};
const otherItem = {
    id: "nm-applet",
    title: "Network",
    icon: "network-wireless",
    status: Status.Active,
    hasMenu: true
};
const watcherNew = {
    id: "InputMethodDaemon",
    title: "Input Method",
    tooltipTitle: "Keyboard Layout",
    icon: "input-keyboard",
    status: Status.Active,
    hasMenu: true,
    watcherGen: 2
};
const watcherDedup = deduplicateItems([watcherOld, otherItem, watcherNew]);
assert.equal(watcherDedup.length, 2, "Duplicate watcher registration must collapse to 1 slot");
assert.equal(watcherDedup[0], watcherNew, "Tie-break must prefer fresher registration in original slot");
assert.equal(watcherDedup[1], otherItem, "Subsequent items must preserve relative order");

// 3. Passive vs Active duplicate registrations in both orders
const passiveDup = {
    id: "ime-agent",
    title: "Keyboard Method",
    icon: "input-keyboard",
    status: Status.Passive,
    hasMenu: false
};
const activeDup = {
    id: "ime-agent",
    title: "Keyboard Method",
    icon: "input-keyboard",
    status: Status.Active,
    hasMenu: true
};
assert.deepEqual(deduplicateItems([passiveDup, activeDup]), [activeDup]);
assert.deepEqual(deduplicateItems([activeDup, passiveDup]), [activeDup]);

// 4. Native SNI + XEmbed proxy duplicate for the same tray app (including canonical vs generic ID priority)
const nativeSni = {
    id: "ime-panel",
    title: "Input Method",
    icon: "image://qsimage/1",
    status: Status.Active,
    hasMenu: true
};
const xembedProxyDup = {
    id: "xembedsniproxy_1",
    title: "Input Method",
    icon: "image://qsimage/2",
    status: Status.Active,
    hasMenu: true
};
assert.deepEqual(
    deduplicateItems([nativeSni, xembedProxyDup]),
    [nativeSni],
    "Canonical non-generic SNI ID must outrank generic xembedsniproxy ID even when both are Active"
);
assert.deepEqual(
    deduplicateItems([xembedProxyDup, nativeSni]),
    [nativeSni],
    "Canonical non-generic SNI ID must replace earlier generic xembedsniproxy ID"
);

// 5. Generic wrapper IDs (chrome_status_icon_1) for distinct apps must NOT collide
const electronAppA = {
    id: "chrome_status_icon_1",
    title: "Music Player",
    icon: "music-player",
    status: Status.Active,
    hasMenu: true
};
const electronAppB = {
    id: "chrome_status_icon_1",
    title: "Notes Client",
    icon: "notes-client",
    status: Status.Active,
    hasMenu: true
};
const electronAppADup = {
    id: "chrome_status_icon_1",
    title: "Music Player",
    icon: "music-player",
    status: Status.Active,
    hasMenu: true,
    reconnected: true
};
const genericResult = deduplicateItems([electronAppA, electronAppB, electronAppADup]);
assert.equal(genericResult.length, 2, "Distinct apps with generic wrapper IDs must remain separate");
assert.equal(genericResult[0], electronAppADup);
assert.equal(genericResult[1], electronAppB);

// 6. Problematic apps with varying IDs/titles collapse to one slot and prefer canonical ID
const tgGeneric = {
    id: "chrome_status_icon_1",
    title: "Telegram (2)",
    icon: "telegram",
    status: Status.Active,
    hasMenu: true
};
const tgCanonical = {
    id: "org.telegram.desktop",
    title: "Telegram Desktop",
    icon: "telegram",
    status: Status.Active,
    hasMenu: true
};
assert.deepEqual(deduplicateItems([tgGeneric, tgCanonical]), [tgCanonical]);
assert.deepEqual(deduplicateItems([tgCanonical, tgGeneric]), [tgCanonical]);

// 7. Empty title + tooltipTitle + pixmap icon (image://qsimage/...) across native SNI and generic proxy
const sniWithTooltip = {
    id: "InputMethodDaemon",
    title: "Input Method",
    tooltipTitle: "VietnameseIM",
    icon: "image://qsimage/10",
    status: Status.Active,
    hasMenu: true
};
const proxyTooltipOnly = {
    id: "StatusNotifierItem-2027-1",
    title: "",
    tooltipTitle: "VietnameseIM",
    icon: "image://qsimage/11",
    status: Status.Active,
    hasMenu: false
};
assert.deepEqual(deduplicateItems([sniWithTooltip, proxyTooltipOnly]), [sniWithTooltip]);
assert.deepEqual(deduplicateItems([proxyTooltipOnly, sniWithTooltip]), [sniWithTooltip]);

// 8. Libappindicator _status_icon_<N> transport suffix increments with empty title and pixmap icon
const appInd1 = {
    id: "flameshot_status_icon_1",
    title: "",
    tooltipTitle: "",
    icon: "image://qsimage/20",
    status: Status.Active,
    hasMenu: true
};
const appInd2 = {
    id: "flameshot_status_icon_2",
    title: "",
    tooltipTitle: "",
    icon: "image://qsimage/21",
    status: Status.Active,
    hasMenu: true
};
assert.deepEqual(deduplicateItems([appInd1, appInd2]), [appInd2]);

// 9. Active status must outrank uninitialized (undefined) status
const initializedActive = {
    id: "ime-daemon",
    title: "Input Method",
    icon: "input-keyboard",
    status: Status.Active,
    hasMenu: true
};
const uninitializedDup = {
    id: "ime-daemon",
    title: "Input Method",
    icon: "input-keyboard",
    status: undefined,
    hasMenu: true
};
assert.deepEqual(deduplicateItems([initializedActive, uninitializedDup]), [initializedActive]);
assert.deepEqual(deduplicateItems([uninitializedDup, initializedActive]), [initializedActive]);

// 10. Distinct non-generic tray items from the same multi-icon suite sharing a generic title must NOT collide
const suiteVpn = {
    id: "suite-vpn",
    title: "Security Suite",
    icon: "security-high",
    status: Status.Active,
    hasMenu: true
};
const suiteFirewall = {
    id: "suite-firewall",
    title: "Security Suite",
    icon: "security-medium",
    status: Status.Active,
    hasMenu: true
};
const suiteVpnDup = {
    id: "suite-vpn",
    title: "Security Suite",
    icon: "security-high",
    status: Status.Active,
    hasMenu: true,
    gen: 2
};
const suiteResult = deduplicateItems([suiteVpn, suiteFirewall, suiteVpnDup]);
assert.equal(suiteResult.length, 2, "Distinct non-generic IDs in a multi-icon suite must remain separate");
assert.equal(suiteResult[0], suiteVpnDup);
assert.equal(suiteResult[1], suiteFirewall);

// 11. Reverse-domain ID + short ID for the same application collapse and preserve user-pinned ID
root._pinnedItems = ["keepassxc"];
const rdnItem = {
    id: "org.keepassxc.KeePassXC",
    title: "KeePassXC",
    icon: "keepassxc",
    status: Status.Active,
    hasMenu: true
};
const shortPinnedItem = {
    id: "keepassxc",
    title: "KeePassXC",
    icon: "keepassxc",
    status: Status.Active,
    hasMenu: true
};
assert.deepEqual(deduplicateItems([rdnItem, shortPinnedItem]), [shortPinnedItem]);
assert.deepEqual(deduplicateItems([shortPinnedItem, rdnItem]), [shortPinnedItem]);
"""
    )

    with tempfile.NamedTemporaryFile("w", suffix=".cjs", encoding="utf-8", delete=True) as tmp:
        tmp.write(js_harness)
        tmp.flush()
        proc = subprocess.run(
            ["node", tmp.name],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            failures.append(f"TrayService.deduplicateItems behavioural test failed:\n{proc.stderr.strip()}")


def _run_qs_tray_dedup_runtime_test(failures: list[str]) -> None:
    import json
    import os
    import sys

    root_dir = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root_dir / "scripts"))
    from native_test_session import run_qs

    sni_helper = r'''#!/usr/bin/env python3
import sys
from gi.repository import Gio, GLib

bus_suffix = sys.argv[1]
item_id = sys.argv[2]
item_title = sys.argv[3]
delayed_id = sys.argv[4] if len(sys.argv) > 4 else ""

SNI_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <method name="Activate">
      <arg name="x" type="i" direction="in"/>
      <arg name="y" type="i" direction="in"/>
    </method>
    <signal name="NewTitle"/>
    <signal name="NewStatus">
      <arg name="status" type="s"/>
    </signal>
  </interface>
</node>
"""

state = {
    "Id": item_id,
    "Title": item_title,
    "Status": "Active",
    "Category": "ApplicationStatus",
    "IconName": "input-keyboard",
    "ItemIsMenu": False,
}

node_info = Gio.DBusNodeInfo.new_for_xml(SNI_XML)
iface_info = node_info.interfaces[0]
loop = GLib.MainLoop()
bus_name = f"org.alis.test.sni_{bus_suffix}"

def on_method_call(conn, sender, path, iface, method, params, invocation):
    invocation.return_value(None)

def on_get_property(conn, sender, path, iface, prop):
    val = state.get(prop)
    if isinstance(val, bool):
        return GLib.Variant("b", val)
    if isinstance(val, str):
        return GLib.Variant("s", val)
    return None

def register_with_watcher(conn):
    try:
        conn.call_sync(
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher",
            "RegisterStatusNotifierItem",
            GLib.Variant("(s)", (bus_name,)),
            None,
            Gio.DBusCallFlags.NONE,
            2000,
            None,
        )
    except Exception:
        return True
    if delayed_id:
        def populate_later():
            state["Id"] = delayed_id
            state["Title"] = "Input Method"
            conn.emit_signal(
                None,
                "/StatusNotifierItem",
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                GLib.Variant(
                    "(sa{sv}as)",
                    (
                        "org.kde.StatusNotifierItem",
                        {"Id": GLib.Variant("s", delayed_id), "Title": GLib.Variant("s", "Input Method")},
                        [],
                    ),
                ),
            )
            conn.emit_signal(None, "/StatusNotifierItem", "org.kde.StatusNotifierItem", "NewTitle", None)
            return False
        GLib.timeout_add(150, populate_later)
    return False

def on_bus_acquired(conn, name):
    conn.register_object("/StatusNotifierItem", iface_info, on_method_call, on_get_property, None)

def on_name_acquired(conn, name):
    GLib.timeout_add(50, register_with_watcher, conn)

Gio.bus_own_name(
    Gio.BusType.SESSION,
    bus_name,
    Gio.BusNameOwnerFlags.NONE,
    on_bus_acquired,
    on_name_acquired,
    lambda *_: loop.quit(),
)
loop.run()
'''

    with tempfile.TemporaryDirectory(prefix="alis-tray-dedup-rt-") as name:
        folder = Path(name)
        for entry in [
            "modules",
            "services",
            "GlobalStates.qml",
            "qmldir",
            "assets",
            "scripts",
            "defaults",
            "translations",
        ]:
            (folder / entry).symlink_to(root_dir / entry)

        helper_path = folder / "mock_sni.py"
        helper_path.write_text(sni_helper, encoding="utf-8")
        helper_path.chmod(0o755)

        (folder / "shell.qml").write_text(
            f"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.abyss.bar

ShellRoot {{
    id: root
    property int checks: 0
    Component.onCompleted: Quickshell.watchFiles = false

    QtObject {{
        id: asyncMockA
        property string id: "InputMethodDaemon"
        property string title: "Input Method"
        property string tooltipTitle: "Keyboard"
        property string icon: "input-keyboard"
        property int status: Status.Active
        property bool hasMenu: true
    }}
    QtObject {{
        id: asyncMockB
        property string id: ""
        property string title: ""
        property string tooltipTitle: ""
        property string icon: "input-keyboard"
        property int status: Status.Active
        property bool hasMenu: true
    }}
    property list<var> mockTrayList: [asyncMockA, asyncMockB]
    readonly property list<var> reactiveDedup: TrayService.deduplicateItems(root.mockTrayList)

    Process {{
        id: sniProc1
        command: ["python3", {json.dumps(str(helper_path))}, "1", "InputMethodDaemon", "Input Method"]
    }}
    Process {{
        id: sniProc2
        command: ["python3", {json.dumps(str(helper_path))}, "2", "InputMethodDaemon", "Input Method"]
    }}
    Process {{
        id: sniProc3
        command: ["python3", {json.dumps(str(helper_path))}, "3", "xembedsniproxy_1", "Input Method"]
    }}
    Process {{
        id: sniProc4
        command: ["python3", {json.dumps(str(helper_path))}, "4", "StatusNotifierItem-999-1", "", "InputMethodDaemon"]
    }}

    FloatingWindow {{
        id: win
        visible: true
        implicitWidth: 640
        implicitHeight: 240
        color: "#111820"
        AbyssBarModule {{
            id: trayModule
            kind: "tray"
            outputName: win.screen?.name ?? ""
            attachedEdge: "top"
            width: Math.max(40, naturalSpan)
            height: 32
        }}
    }}

    TestCase {{
        id: test
        when: false
        optional: true
        function check(cond, msg) {{
            root.checks++
            if (!cond)
                throw new Error(msg)
        }}
        function run() {{
            try {{
                tryCompare(Config, "ready", true, 5000)
                tryVerify(() => trayModule.feature !== null, 5000)

                // Part A: Reactive QML property transition on QtObject tray items
                check(root.reactiveDedup.length === 1 && root.reactiveDedup[0] === asyncMockA,
                    "initial reactive dedup with empty-id second item must have length 1")
                asyncMockB.id = "chrome_status_icon_1"
                wait(20)
                check(root.reactiveDedup.length === 2,
                    "generic-id item before title population is temporarily distinct")
                asyncMockB.title = "Input Method"
                wait(20)
                check(root.reactiveDedup.length === 1 && root.reactiveDedup[0] === asyncMockA,
                    "reactive QML binding must collapse duplicate once async title populates and keep canonical ID")

                // Part B: Real D-Bus StatusNotifierItem duplicate registrations in Quickshell SystemTray
                const spanEmpty = trayModule.naturalSpan
                sniProc1.running = true
                tryVerify(() => SystemTray.items.values.length === 1, 5000)
                wait(80)
                const spanSingle = trayModule.naturalSpan
                check(spanSingle > spanEmpty, "single SNI item must increase Abyss tray module naturalSpan")
                check(TrayService.uniqueItems.length === 1, "TrayService.uniqueItems must be 1 for single SNI")
                check(trayModule.feature.deduplicatedItems.length === 1, "SysTray.deduplicatedItems must be 1")
                check(trayModule.feature.pinnedItems.length === 1, "SysTray.pinnedItems must be 1")

                // Spawn duplicate SNI registration (same Id & Title) + XEmbed proxy + delayed-Title SNI duplicate
                sniProc2.running = true
                sniProc3.running = true
                sniProc4.running = true
                tryVerify(() => SystemTray.items.values.length === 4, 5000)
                tryVerify(() => TrayService.uniqueItems.length === 1, 5000)
                wait(80)
                check(TrayService.uniqueItems.length === 1,
                    "4 duplicate SNI/XEmbed/async registrations must collapse to 1 in TrayService.uniqueItems, got " + TrayService.uniqueItems.length)
                check(TrayService.uniqueItems[0].id === "InputMethodDaemon",
                    "canonical non-generic SNI ID must win over xembedsniproxy_1, got " + TrayService.uniqueItems[0].id)
                check(trayModule.feature.deduplicatedItems.length === 1,
                    "SysTray.deduplicatedItems must remain 1 when 4 duplicate SNI items exist")
                check(trayModule.feature.pinnedItems.length === 1,
                    "SysTray.pinnedItems must remain 1 when 4 duplicate SNI items exist")
                check(Math.abs(trayModule.naturalSpan - spanSingle) < 0.5,
                    "Abyss tray naturalSpan must not grow for duplicate SNI items (" + trayModule.naturalSpan + " vs " + spanSingle + ")")

                sniProc1.running = false
                sniProc2.running = false
                sniProc3.running = false
                sniProc4.running = false
                console.info("TRAY_DEDUP_RUNTIME_PASS", root.checks, "raw=4 unique=1 spanSingle=" + spanSingle)
            }} catch (e) {{
                sniProc1.running = false
                sniProc2.running = false
                sniProc3.running = false
                sniProc4.running = false
                console.error("TRAY_DEDUP_RUNTIME_FAIL", e.message, e.stack)
            }}
            Qt.quit()
        }}
    }}
    Timer {{ interval: 100; running: true; onTriggered: test.run() }}
}}
""",
            encoding="utf-8",
        )

        runtime = folder / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        base_env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime))
        for key in [
            "WAYLAND_DISPLAY",
            "NIRI_SOCKET",
            "DISPLAY",
            "HYPRLAND_INSTANCE_SIGNATURE",
            "QS_CONFIG_NAME",
            "QS_CONFIG_PATH",
            "QS_MANIFEST",
        ]:
            base_env.pop(key, None)
        for kind in ["config", "cache", "data", "state"]:
            (folder / kind).mkdir(parents=True, exist_ok=True)
            base_env[f"XDG_{kind.upper()}_HOME"] = str(folder / kind)
        import time
        sock = "wayland-alis-headless-tray"
        kwin = subprocess.Popen(
            ["kwin_wayland", "--virtual", "--socket", sock, "--width", "1280", "--height", "800"],
            env=base_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            for _ in range(80):
                if (runtime / sock).exists():
                    break
                time.sleep(0.05)
            env = dict(
                base_env,
                WAYLAND_DISPLAY=sock,
                QT_QPA_PLATFORM="wayland",
                QT_QUICK_BACKEND="software",
                QSG_RHI_BACKEND="software",
            )
            cfg = folder / "config/alis"
            cfg.mkdir(parents=True, exist_ok=True)
            values = json.loads((root_dir / "defaults/config.json").read_text(encoding="utf-8"))
            values["panelFamily"] = "abyss"
            values["performance"]["reduceAnimations"] = True
            (cfg / "config.json").write_text(json.dumps(values), encoding="utf-8")
            result = run_qs(folder, env, timeout=30)
        finally:
            if kwin.poll() is None:
                os.killpg(kwin.pid, 15)
                try:
                    kwin.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(kwin.pid, 9)
        bad = (
            "TRAY_DEDUP_RUNTIME_FAIL",
            "ReferenceError:",
            "TypeError:",
            "Binding loop",
            "Failed to load configuration",
        )
        if (
            result.returncode != 0
            or "TRAY_DEDUP_RUNTIME_PASS" not in result.stdout
            or any(token in result.stdout for token in bad)
        ):
            failures.append(f"Quickshell tray dedup runtime test failed:\n{result.stdout[-2000:]}")


def main() -> int:
    text = TRAY_PATH.read_text(encoding="utf-8")
    item_text = TRAY_ITEM_PATH.read_text(encoding="utf-8")
    tray_menu_text = TRAY_MENU_PATH.read_text(encoding="utf-8")
    service_text = TRAY_SERVICE_PATH.read_text(encoding="utf-8")
    context_menu_text = CONTEXT_MENU_PATH.read_text(encoding="utf-8")
    dock_button_text = DOCK_BUTTON_PATH.read_text(encoding="utf-8")
    failures: list[str] = []

    required = (
        "overflowPopup.presentationWindow",
        "root.activeMenu = window;",
        "active: (root.trayOverflowOpen && overflowPopup.presentationWindow !== null)",
        ".filter(window => window !== null)",
        "function releaseFocus(window)",
        "if (root.activeMenu === window)",
        "onMenuClosed: (qsWindow) => root.releaseFocus(qsWindow);",
        "return TrayService.isValidItem(item);",
        "readonly property list<var> deduplicatedItems: TrayService.deduplicateItems(SystemTray.items.values)",
        "property list<var> itemsInUserList: root.deduplicatedItems.filter(",
        "property list<var> itemsNotInUserList: root.deduplicatedItems.filter(",
    )
    for needle in required:
        if needle not in text:
            failures.append(f"missing tray focus/dedup contract in SysTray.qml: {needle}")

    if "SystemTray.items.values.filter(" in text:
        failures.append("SysTray.qml must not filter raw SystemTray.items.values directly without deduplication")

    service_required = (
        "function _canMergeTrayEntries(existing, candidate): bool",
        "function deduplicateItems(items): var",
        "readonly property list<var> uniqueItems: deduplicateItems(SystemTray.items.values)",
        "property list<var> itemsInUserList: root.uniqueItems.filter(",
        "property list<var> itemsNotInUserList: root.uniqueItems.filter(",
    )
    for needle in service_required:
        if needle not in service_text:
            failures.append(f"missing tray deduplication contract in TrayService.qml: {needle}")

    if "SystemTray.items.values.filter(" in service_text:
        failures.append("TrayService.qml must not filter raw SystemTray.items.values directly without deduplication")

    if "return TrayService.uniqueItems.find(item => {" not in dock_button_text:
        failures.append("DockAppButton.qml must look up appTrayItem from TrayService.uniqueItems")

    item_required = (
        "signal menuClosed(qsWindow: var)",
        "const window = menu.item;",
        "root.menuClosed(window);",
    )
    for needle in item_required:
        if needle not in item_text:
            failures.append(f"missing tray-item close identity contract: {needle}")

    # Tray menus must use the same source-owned connected surface as other Bar
    # popups. StyledPopup owns the full-output backdrop on the anchor's output.
    tray_connected_required = (
        "StyledPopup {",
        "hoverTarget: root.anchorItem",
        "alternativeVisibleCondition: root.menuRequestedOpen",
        "closeOnOutsideClick: true",
        "keyboardFocus: root.keyboardMode",
        "root.menuOpened(presentationWindow)",
    )
    for needle in tray_connected_required:
        if needle not in tray_menu_text:
            failures.append(f"missing connected tray-menu contract: {needle}")
    if "PopupWindow {" in tray_menu_text or "PanelWindow {" in tray_menu_text:
        failures.append("tray menu must not own a detached PopupWindow/PanelWindow presentation")
    if "anchorItem: root" not in item_text:
        failures.append("tray item must hand its real visual anchor to the connected menu")
    if "anchor {" in item_text[item_text.find("sourceComponent: SysTrayMenu {"):]:
        failures.append("tray item must not recreate compositor popup-anchor geometry")

    # Shared ContextMenu still owns its own PopupWindow for now; its Niri catcher
    # must remain on the same output until it is migrated separately.
    if "screen: popupWindow.screen" not in context_menu_text:
        failures.append("context-menu Niri backdrop must bind screen to the owning popup")

    # QML imperative assignment to a bound property removes that binding. The
    # focus-grab active state must therefore remain derived from popup/menu state.
    if re.search(r"\bfocusGrab\.active\s*=", text):
        failures.append("focusGrab.active must stay declarative; imperative assignment breaks its binding")

    release_match = re.search(
        r"function\s+releaseFocus\s*\(\s*window\s*\)\s*\{(?P<body>.*?)\}",
        text,
        re.DOTALL,
    )
    if not release_match:
        failures.append("releaseFocus(window) must remain identity-aware")
    else:
        body = release_match.group("body")
        if "root.activeMenu === window" not in body or "root.activeMenu = null;" not in body:
            failures.append("releaseFocus(window) must clear only the matching activeMenu")

    if re.search(r"onMenuClosed\s*:\s*root\.releaseFocus\s*\(\s*\)", text):
        failures.append("tray menu close handlers must forward the closing window identity")

    _run_dedup_behavior_tests(service_text, failures)
    _run_qs_tray_dedup_runtime_test(failures)

    if failures:
        print("Tray/menu focus-output contract failures:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("Tray/menu focus-output contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
