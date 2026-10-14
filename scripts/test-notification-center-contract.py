#!/usr/bin/env python3
"""Regression contract for the standalone Material Notification Center."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORNERS = ROOT / "modules" / "screenCorners" / "ScreenCorners.qml"
SCREEN_EDGES = ROOT / "modules" / "screenCorners" / "ScreenEdges.qml"
POPUP = ROOT / "modules" / "notificationCenter" / "NotificationCenterPopup.qml"
CONTENT = ROOT / "modules" / "notificationCenter" / "NotificationCenterContent.qml"
QMLDIR = ROOT / "modules" / "notificationCenter" / "qmldir"
GLOBAL = ROOT / "GlobalStates.qml"
NOTIFICATIONS = ROOT / "services" / "Notifications.qml"
LIST = ROOT / "modules" / "common" / "widgets" / "NotificationListView.qml"
ITEM = ROOT / "modules" / "common" / "widgets" / "NotificationItem.qml"
RIGHT = ROOT / "modules" / "sidebarRight" / "SidebarRightContent.qml"
COMPACT = ROOT / "modules" / "sidebarRight" / "CompactSidebarRightContent.qml"
LAYOUT_EDITOR = ROOT / "modules" / "common" / "widgets" / "SidebarLayoutEditor.qml"
PERSISTENT = ROOT / "modules" / "common" / "Persistent.qml"
OVERLAY = ROOT / "modules" / "ii" / "overlay" / "notifications" / "Notifications.qml"
CONFIG = ROOT / "modules" / "common" / "Config.qml"
DEFAULTS = ROOT / "defaults" / "config.json"
TRANSLATIONS = ROOT / "translations" / "en_US.json"
INTERFACE = ROOT / "modules" / "settings" / "InterfaceConfig.qml"
MONITORS = ROOT / "modules" / "settings" / "MonitorVisibilityConfig.qml"
REGISTRY = ROOT / "modules" / "settings" / "SettingsPageRegistryData.qml"
SHELL = ROOT / "shell.qml"
IPC = ROOT / "scripts" / "lib" / "ipc-registry.sh"
LAUNCHER = ROOT / "scripts" / "alis"
DEV_NAV = ROOT / "services" / "DevNavigation.qml"
CONFIG_DOC = ROOT / "docs" / "CONFIG_SYSTEM.md"
SIDEBAR_PREVIEW = ROOT / "modules" / "common" / "widgets" / "SidebarHeightPreview.qml"
SIDEBAR_HOST = ROOT / "modules" / "sidebar" / "SidebarHost.qml"
SHELL_LAYOUT = ROOT / "services" / "ShellLayoutController.qml"


def fail(message: str) -> None:
    raise SystemExit("FAIL: " + message)


def require(source: str, token: str, message: str) -> None:
    if token not in source:
        fail(message + " (" + token + ")")


def forbid(source: str, token: str, message: str) -> None:
    if token in source:
        fail(message + " (" + token + ")")


corners = CORNERS.read_text(encoding="utf-8")
screen_edges = SCREEN_EDGES.read_text(encoding="utf-8")
popup = POPUP.read_text(encoding="utf-8")
content = CONTENT.read_text(encoding="utf-8")
qmldir = QMLDIR.read_text(encoding="utf-8")
global_states = GLOBAL.read_text(encoding="utf-8")
notifications = NOTIFICATIONS.read_text(encoding="utf-8")
list_view = LIST.read_text(encoding="utf-8")
item = ITEM.read_text(encoding="utf-8")
right = RIGHT.read_text(encoding="utf-8")
compact = COMPACT.read_text(encoding="utf-8")
layout_editor = LAYOUT_EDITOR.read_text(encoding="utf-8")
persistent = PERSISTENT.read_text(encoding="utf-8")
overlay = OVERLAY.read_text(encoding="utf-8")
config = CONFIG.read_text(encoding="utf-8")
defaults = json.loads(DEFAULTS.read_text(encoding="utf-8"))
translations = json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
interface = INTERFACE.read_text(encoding="utf-8")
monitors = MONITORS.read_text(encoding="utf-8")
registry = REGISTRY.read_text(encoding="utf-8")
shell = SHELL.read_text(encoding="utf-8")
ipc = IPC.read_text(encoding="utf-8")
launcher = LAUNCHER.read_text(encoding="utf-8")
dev_nav = DEV_NAV.read_text(encoding="utf-8")
config_doc = CONFIG_DOC.read_text(encoding="utf-8")
sidebar_preview = SIDEBAR_PREVIEW.read_text(encoding="utf-8")
sidebar_host = SIDEBAR_HOST.read_text(encoding="utf-8")
shell_layout = SHELL_LAYOUT.read_text(encoding="utf-8")

# The physical Screen Edge renderer stays the sole owner of screen rounding.
forbid(screen_edges, "notificationCenter",
       "Notification Center must not modify physical ScreenEdges geometry")
forbid(screen_edges, "NotificationCenter",
       "Notification Center must not add physical corner paint")

for token in (
    "NotificationCenterContent 1.0 NotificationCenterContent.qml",
    "NotificationCenterPopup 1.0 NotificationCenterPopup.qml",
):
    require(qmldir, token, "notificationCenter module export missing")

# History and transient toast data are independent from presentation mode.
for token in (
    'property string dataMode: popup ? "transient" : "history"',
    "property bool popupPresentation: popup",
    'root.dataMode === "transient"',
    "popup: root.popupPresentation",
):
    require(list_view, token, "NotificationListView data/presentation split missing")

for token in (
    'dataMode: "history"',
    "popupPresentation: root.popupPresentation",
    "filterQuery: searchField.text",
    "signal externalNavigationRequested()",
    "onNotificationActionInvoked:",
):
    require(content, token, "shared history content contract missing")

# A single ScreenCorners owner arbitrates bottom-right input. Native Niri
# Overview wins, followed by Notification Center and the sidebar trigger.
for token in (
    "readonly property bool shouldShowNotificationCenterCorner:",
    "cornerPanelWindow.isBottomRight",
    "!cornerPanelWindow.niriOverviewOwnsCorner",
    "id: notificationCenterCornerLoader",
    "id: notificationCenterDwellTimer",
    "Config.options?.notificationCenter?.hoverDelayMs ?? 220",
    "Config.options?.notificationCenter?.cornerSize ?? 14",
    "NotificationCenterPopup {",
    "&& !notificationCenterHostNeeded",
    "function reconcileNotificationCenterFullscreenPolicy(): void",
    "onNotificationCenterExplicitForOutputChanged:",
    "onNotificationCenterAllowedInFullscreenChanged:",
):
    require(corners, token, "bottom-right corner ownership contract missing")

notif_pos = corners.index("readonly property bool shouldShowNotificationCenterCorner:")
sidebar_pos = corners.index("readonly property bool shouldShowSidebarCornerOpen:")
if notif_pos >= sidebar_pos:
    fail("Notification Center priority must resolve before legacy sidebar corner-open")

# The popup reuses the canonical connected surface implementation, which owns
# the immutable SurfaceMotion slide contract. Hover and explicit opens are
# separate leases, with drag and transfer grace holding the surface resident.
for token in (
    "Bar.StyledPopup {",
    "required property string outputName",
    "GlobalStates.notificationCenterExplicitOpen",
    "property bool entryBridgeHeld: false",
    "property bool exitGraceHeld: false",
    "Config.options?.notificationCenter?.closeGraceMs ?? 280",
    "(contentLoader.item?.dragActive ?? false)",
    "popupPresentation: true",
    "onExternalNavigationRequested: root.dismissAndDisarm()",
):
    require(popup, token, "Notification Center popup lifecycle contract missing")

if popup.count("Config.options?.notificationCenter?.closeGraceMs ?? 280") < 2:
    fail("Notification Center transfer grace must control both entry and exit")
forbid(popup, "interval: 260",
       "Notification Center entry bridge still bypasses the public grace setting")

# Global state is authoritative and opening the old Right Sidebar must no longer
# mark history read or suppress transient toasts.
for token in (
    "property bool notificationCenterExplicitOpen: false",
    'property string notificationCenterTargetOutput: ""',
    'property string notificationCenterHoverOutput: ""',
    "readonly property bool notificationCenterOpen:",
    "function openNotificationCenter(outputName): bool",
    "function closeNotificationCenter(): void",
    "function setNotificationCenterHoverOutput(outputName, open): void",
    "function onScreensChanged(): void",
    "const hoverOutput = root.notificationCenterHoverOutput",
    "const connected = Quickshell.screens.map(",
    "if (hoverOutput && !connected.includes(hoverOutput))",
    'root.notificationCenterHoverOutput = ""',
    "Config.options?.notificationCenter?.markReadOnOpen ?? true",
):
    require(global_states, token, "GlobalStates Notification Center routing missing")

sidebar_handler = re.search(
    r"onSidebarRightOpenChanged:\s*\{([\s\S]*?)\n\s*\}",
    global_states,
)
if not sidebar_handler:
    fail("GlobalStates sidebarRight handler missing")
forbid(sidebar_handler.group(1), "Notifications.",
       "opening Right Sidebar must not mutate notification state")

read_handler_start = global_states.index("onNotificationCenterOpenChanged:")
read_handler_end = global_states.index("onScreenLockedChanged:", read_handler_start)
read_handler = global_states[read_handler_start:read_handler_end]
for token in (
    "Qt.callLater(() => {",
    "if (!root.notificationCenterOpen",
    "Notifications.timeoutAll()",
    "Notifications.markAllRead()",
):
    require(read_handler, token,
            "Notification Center read-state settlement contract missing")

surface_match = re.search(
    r"readonly property bool notificationSurfaceOpen:([\s\S]*?)\n\s*readonly property bool notificationPolicyActive",
    notifications,
)
if not surface_match:
    fail("Notifications.notificationSurfaceOpen contract missing")
surface = surface_match.group(1)
require(surface, "GlobalStates?.notificationCenterOpen",
        "Material center must suppress duplicate transient toasts")
require(surface, "GlobalStates?.waffleNotificationCenterOpen",
        "Waffle center must remain a notification surface")
forbid(surface, "sidebarRightOpen",
       "Right Sidebar must not suppress transient toasts after extraction")

# Normal and compact right sidebars contain no history section. Compact state is
# persisted by stable id so removing the old index 1 cannot silently select the
# next widget on existing installs.
for source, name in ((right, "normal Right Sidebar"), (compact, "compact Right Sidebar")):
    forbid(source, 'id: "notifications"', name + " still declares notification section")
    forbid(source, 'case "notifications"', name + " still routes notification section")
forbid(compact, "notificationsSectionComponent",
       "compact Right Sidebar still owns notification history renderer")
forbid(compact, "component EmptyNotificationsPlaceholder:",
       "compact Right Sidebar still carries retired notification-history UI")
require(persistent, 'property string sectionId: ""',
        "compact sidebar stable section persistence missing")
for token in (
    "property bool compactSectionRestored: false",
    "function restoreActiveSection(): void",
    "const savedId = String(state?.sectionId ?? \"\")",
    "idx = legacy <= 1 ? 0 : legacy - 1",
):
    require(compact, token, "compact sidebar index migration missing")
forbid(layout_editor, 'notifications: { icon: "notifications"',
       "layout editor still exposes retired notification section")
forbid(layout_editor, "sectionWeights.notifications",
       "layout editor still exposes retired notification/widget balance")
for source, name in (
    (sidebar_preview, "sidebar height preview"),
    (shell_layout, "shell layout diagnostics"),
):
    forbid(
        source,
        "collapseEmptyNotifications",
        name + " still derives geometry from retired notification history",
    )
forbid(
    sidebar_host,
    "notifsCollapsed",
    "sidebar host still probes retired notification-collapse state",
)
require(
    config_doc,
    "Notification history itself lives in the standalone bottom-right Notification Center.",
    "config docs must not describe notification history as a Right Sidebar section",
)

# Shared overlay history uses the same canonical content rather than copying a
# third renderer.
require(overlay, "NotificationCenterContent {",
        "ii overlay must reuse canonical Notification Center content")
forbid(overlay, "OpacityMask",
       "ii overlay notification history must not restore FBO masking")

schema_match = re.search(
    r"property JsonObject notificationCenter: JsonObject \{([\s\S]*?)\n\s*\}",
    config,
)
if not schema_match:
    fail("Config schema does not expose notificationCenter")
schema = schema_match.group(1)
for token in (
    "property bool enable: true",
    "property bool hoverEnable: true",
    "property int hoverDelayMs: 220",
    "property int closeGraceMs: 280",
    "property int cornerSize: 14",
    "property int popupWidth: 420",
    "property int popupHeight: 560",
    "property bool markReadOnOpen: true",
    "property bool allowInFullscreen: false",
    "property list<string> screenList: []",
):
    require(schema, token, "Notification Center Config default missing")

expected = {
    "enable": True,
    "hoverEnable": True,
    "hoverDelayMs": 220,
    "closeGraceMs": 280,
    "cornerSize": 14,
    "popupWidth": 420,
    "popupHeight": 560,
    "markReadOnOpen": True,
    "allowInFullscreen": False,
    "screenList": [],
}
if defaults.get("notificationCenter") != expected:
    fail("defaults/config.json notificationCenter defaults drifted")

for token in (
    'Config.setNestedValue("notificationCenter.enable", checked)',
    'Config.setNestedValue("notificationCenter.hoverEnable", checked)',
    'Config.setNestedValue("notificationCenter.hoverDelayMs", value)',
    'Config.setNestedValue("notificationCenter.closeGraceMs", value)',
    'Config.setNestedValue("notificationCenter.cornerSize", value)',
    'Config.setNestedValue("notificationCenter.popupWidth", value)',
    'Config.setNestedValue("notificationCenter.popupHeight", value)',
    'Config.setNestedValue("notificationCenter.markReadOnOpen", checked)',
    'Config.setNestedValue("notificationCenter.allowInFullscreen", checked)',
    'GlobalStates.toggleNotificationCenter("")',
):
    require(interface, token, "Notification Center Settings control missing")

notification_settings_start = interface.index('settingsTaskSection: "notifications"')
notification_settings_end = interface.index(
    "SettingsCardSection {", notification_settings_start + 1
)
notification_settings = interface[notification_settings_start:notification_settings_end]
require(
    notification_settings,
    'Config.setNestedValue("notificationCenter.closeGraceMs", value)',
    "Notification Center close grace must live in the Notifications settings card",
)

quick_notes_start = interface.index('title: Translation.tr("Bottom-left Quick Notes")')
quick_notes_end = interface.index("SettingsCardSection {", quick_notes_start)
quick_notes_settings = interface[quick_notes_start:quick_notes_end]
forbid(
    quick_notes_settings,
    "notificationCenter.closeGraceMs",
    "Quick Notes settings must not mutate Notification Center close grace",
)
require(monitors, 'path: "notificationCenter.screenList"',
        "Monitor Visibility must expose a dedicated Notification Center screen list")
require(registry, 'label: Translation.tr("Notification center")',
        "Settings search registry must index Notification Center")

for key in (
    "Notification center",
    "Bottom-right notification history surface",
    "Open on bottom-right hover",
    "Close grace (ms)",
    "Mark read when opened",
    "Allow over fullscreen apps",
    "Preview notification center",
    "No matching notifications",
):
    if translations.get(key) != key:
        fail("Notification Center English catalog entry missing: " + key)

# External links/actions retract only the owning center/overlay. Shared cards no
# longer hard-code Right Sidebar state.
forbid(item, "GlobalStates.sidebarRightOpen = false",
       "shared notification item still hard-codes Right Sidebar close semantics")
require(item, "signal notificationActionInvoked()",
        "notification actions must publish navigation semantics")

# Explicit/manual routing is available to CLI and developer tooling.
require(shell, 'target: "notificationCenter"',
        "shell IPC target for Notification Center missing")
for token in (
    '[notificationCenter]="toggle close open status"',
    "[notification-center]=notificationCenter",
):
    require(ipc, token, "IPC registry Notification Center entry missing")
require(dev_nav, '{ id: "notification-center", family: "ii"',
        "DevNavigation must open the standalone Material center")
forbid(dev_nav, 'id: "sidebar-right/notifications"',
       "DevNavigation still points notification history at Right Sidebar")
require(launcher,
        'modules/common/widgets/Notification*.qml)\n                    select_prefix "notification-center"; select_prefix "dashboard" ;;',
        "shared notification-card changes must audit current history surfaces")
require(launcher, 'modules/notificationCenter/*) select_prefix "notification-center" ;;',
        "standalone Notification Center changes must select its acceptance view")
require(launcher,
        'modules/sidebarRight/notifications/*)\n                    select_prefix "notification-center"; select_prefix "dashboard" ;;',
        "changed notification modules must audit the standalone center")
require(launcher,
        'services/Notifications.qml)\n                    select_prefix "notification-center"; select_prefix "waffle/notification-center"; select_prefix "dashboard" ;;',
        "Notifications service changes must audit current notification surfaces")
forbid(launcher, 'select_prefix "sidebar-right/notifications"',
       "developer audit routing still targets the retired sidebar notification view")

print("PASS: standalone Material Notification Center contract")
