#!/usr/bin/env python3
"""Regression contract for the v1.0 ThinkFan/System Monitor integration."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def main() -> None:
    resources_popup = read("modules/bar/ResourcesPopup.qml")
    dashboard_system = read("modules/dashboard/DashSystem.qml")
    styled_popup = read("modules/bar/StyledPopup.qml")
    config_schema = read("modules/common/Config.qml")
    default_config = read("defaults/config.json")
    thinkfan_service = read("services/ThinkFanService.qml")
    shell_root = read("shell.qml")
    system_settings = read("modules/settings/GeneralConfigCore.qml")
    system_facade = read("modules/settings/GeneralConfig.qml")
    settings_registry = read("modules/settings/SettingsPageRegistryData.qml")
    bar_settings = read("modules/settings/BarConfig.qml")
    bar_config = read("modules/settings/BarConfig.qml")
    source_setup = read("sdata/subcmd-install/2.setups.sh")
    thinkfan_migration = read("sdata/migrations/041-thinkfan-helper-bridge.sh")
    uninstall_lib = read("sdata/lib/uninstall.sh")
    migration_engine = read("sdata/lib/migrations.sh")
    setup_entrypoint = read("setup")
    thinkfan_docs = read("docs/THINKFAN.md")

    for token in (
        "ThinkFanService.refresh()",
        "ThinkFanService.applyProfile(",
        'Translation.tr("Fan")',
        'Translation.tr("RPM:")',
        'Translation.tr("Level:")',
        "thinkFanCanApply",
        "font.pixelSize: Appearance.font.pixelSize.small",
        "thinkFanApplyErrorMessage",
    ):
        check(token in resources_popup,
              f"System Monitor popup must own ThinkFan runtime UI: {token}")

    for token in (
        "ThinkFanService.refresh()",
        "ThinkFanService.applyProfile(",
        'Translation.tr("Fan control")',
        'Translation.tr("RPM:")',
        'Translation.tr("L%1")',
        "ThinkFanService.fanRpm",
        "ThinkFanService.fanLevel",
        "root.thinkFanCanApply",
    ):
        check(token in dashboard_system,
              f"Dashboard System module must reuse ThinkFan runtime state/control: {token}")

    for forbidden in (
        "ThinkFanConnectedSurface",
        "SurfaceRouteController",
        "AnchorPublisher",
        'surface: "thinkfan"',
        "connectAdjacentScreenEdge: true",
    ):
        check(forbidden not in resources_popup,
              f"System Monitor ThinkFan UI must not revive a standalone popup route: {forbidden}")

    for forbidden in (
        'Translation.tr("Free:")',
        'Translation.tr("Service")',
        'Translation.tr("ThinkFan")',
        'Translation.tr("Fan speed")',
        'Translation.tr("Fan level")',
        'Translation.tr("Temperature")',
        'Translation.tr("High")',
        'Translation.tr("Medium")',
        'Translation.tr("Low")',
        "thinkFanStatusMessage",
        "describeThinkFanStatus",
    ):
        check(forbidden not in resources_popup,
              f"System Monitor popup must keep the compact metrics contract: {forbidden}")

    fan_pos = resources_popup.index('Translation.tr("Fan")')
    speed_pos = resources_popup.index('Translation.tr("RPM:")')
    level_pos = resources_popup.index('Translation.tr("Level:")')
    notice_pos = resources_popup.index("NoticeBox {", level_pos)
    check(fan_pos < speed_pos < level_pos < notice_pos,
          "ThinkFan monitor controls/metrics must remain one inline row before error feedback")

    for token in (
        'label: Translation.tr("Thermal")',
        'label: Translation.tr("Load")',
        'label: Translation.tr("CPU:")',
        'value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`',
        'value: `${Math.round(ResourceUsage.gpuUsage * 100)}%`',
        'property string minimumValueSample: ""',
        'property int valueHorizontalAlignment: Text.AlignRight',
        'Layout.minimumWidth: minimumValueText.implicitWidth',
        'horizontalAlignment: resourceItem.valueHorizontalAlignment',
        'minimumValueSample: "99%"',
        'valueHorizontalAlignment: Text.AlignLeft',
        'text: "speed"',
        'text: "tune"',
        "width: thermalColumn.width",
        "width: cpuColumn.width",
    ):
        check(token in resources_popup,
              f"System Monitor compact grid must keep screenshot-aligned metrics: {token}")

    check('label: "CPU"' not in resources_popup,
          "System Monitor third-column heading must be Load, not CPU")
    check('label: Translation.tr("Load:")' not in resources_popup,
          "System Monitor CPU usage metric must be labelled CPU:, not Load:")
    check(resources_popup.count('minimumValueSample: "99.9 GB"') == 2,
          "System Monitor RAM Used/Total cells must reserve stable width across cold-to-warm polls")
    check(resources_popup.count('minimumValueSample: "99°C"') == 2,
          "System Monitor CPU/GPU thermal cells must reserve stable width across cold-to-warm polls")
    check(resources_popup.count('minimumValueSample: "99%"') == 2,
          "System Monitor CPU/GPU load cells must reserve stable width across cold-to-warm polls")

    for token in (
        "property bool connectAdjacentScreenEdge: false",
        "id: directEdgeAttachment",
        "readonly property real _popupScreenMargin: root._screenEdgeThickness",
        "screenMargin: root._popupScreenMargin",
        "connectorLength: 0",
        "ConnectedSurfaceAbyssFrame {",
        "shadowEnabled: root._edgeShadowEnabled",
        "screenEdge?.physicalShadow?.enabled ?? true",
        "Qt.alpha(Appearance.m3colors.m3shadow, root._edgeShadowOpacity)",
    ):
        check(token in styled_popup,
              f"StyledPopup must use direct Caelestia-style edge attachment: {token}")
    for forbidden in (
        "id: adjacentScreenEdgeGeometry",
        "geometry: adjacentScreenEdgeGeometry",
    ):
        check(forbidden not in styled_popup,
              f"StyledPopup must not render a separate adjacent connector stem: {forbidden}")

    for token in (
        "property JsonObject fanControl: JsonObject {",
        "property bool enabled: false",
        "property int powerSaver: 0",
        "property int balanced: 0",
        "property int performance: 0",
    ):
        check(token in config_schema,
              f"Config schema must persist safe per-profile fan levels: {token}")

    for token in (
        '"fanControl": {',
        '"powerSaver": 0',
        '"balanced": 0',
        '"performance": 0',
    ):
        check(token in default_config,
              f"Default config must keep per-profile fan levels on Auto: {token}")



    integrations = read("modules/settings/IntegrationsConfig.qml")
    check('ThinkfanSettings {' not in system_settings, "System duplicated the plugin editor")
    check('AlisIntergration.installedPlugins.map' in integrations, "Integration tabs must use verified discovery")
    check('AlisIntergration.pluginEnabled(root.activePlugin)' in integrations, "Fan editor lost its opt-in gate")
    fan_wrapper=read("modules/settings/ThinkfanSettings.qml")
    check('active: AlisIntergration.thinkfanEnabled && root.visible' in fan_wrapper, "fan settings must be selected and visible")
    check('source: AlisIntergration.settingsSource("thinkfan")' in fan_wrapper, "fan settings lost the optional source")
    check('SettingsPageRegistry.navigateToKey("integrations", "Thinkfan")' in system_facade, "Legacy fan navigation lost its plugin destination")

    for token in (
        "function flushWrites(): void",
        "root._pendingWrite = true",
        "root._writeMirrorToDisk()",
    ):
        check(token in config_schema,
              f"Explicit Config flushes must serialize safely before fan apply: {token}")

    check("property var _thinkFanService: ThinkFanService" in shell_root,
          "Shell root must retain the typed optional fan facade")

    for token in (
        'value.includes("fan")',
        'SettingsPageRegistry.navigateToKey("integrations", "Thinkfan")',
    ):
        check(token in system_facade,
              f"System Settings search must route Fan Control correctly: {token}")

    for token in (
        'section: "Thinkfan"',
        'keywords: ["fan", "fan control", "thinkfan", "thermal", "cooling", "rpm", "temperature", "system"]',
    ):
        check(token in settings_registry,
              f"Settings search index must expose System Fan Control: {token}")

    for forbidden in (
        'settingsTaskSection: "system"',
        'title: Translation.tr("Fan Control")',
        'text: Translation.tr("ThinkFan managed control")',
    ):
        check(forbidden not in bar_settings,
              f"Bar Settings must not own Fan Control anymore: {forbidden}")

    for forbidden in (
        '{ displayName: Translation.tr("System"), icon: "tune", value: "system" }',
        '"fan control": "system"',
    ):
        check(forbidden not in bar_config,
              f"Bar navigation must not expose the removed pseudo-System task: {forbidden}")

    check(not (ROOT / "modules/perimeter").exists(),
          "Retired broad perimeter module must stay absent")
    for path in (
        "modules/perimeter/ThinkFanModule.qml",
        "modules/perimeter/ThinkFanConnectedSurface.qml",
        "modules/perimeter/ThinkFanPopupContent.qml",
    ):
        check(not (ROOT / path).exists(),
              f"Retired standalone ThinkFan surface must stay removed: {path}")




    for forbidden in (
        "systemctl stop thinkfan",
        "systemctl disable thinkfan",
        "systemctl disable --now thinkfan",
        "pacman -R",
        "dnf remove thinkfan",
        "apt remove thinkfan",
        "rm -f /etc/thinkfan",
        "rm -rf /etc/thinkfan",
    ):
        check(forbidden not in thinkfan_migration,
              f"ThinkFan bridge migration must preserve upstream ThinkFan ownership: {forbidden}")


    for forbidden in (
        "systemctl stop thinkfan",
        "systemctl disable thinkfan",
        "systemctl disable --now thinkfan",
        "pacman -R thinkfan",
        "dnf remove thinkfan",
        "apt remove thinkfan",
        "rm -f /etc/thinkfan",
        "rm -rf /etc/thinkfan",
    ):
        check(forbidden not in uninstall_lib,
              f"Repo uninstall must preserve upstream ThinkFan ownership: {forbidden}")

    check("run_migrations_auto" in setup_entrypoint,
          "Repo update path must run required migrations after pulling source changes")
    check('apply_migration "$migration_id" true' in migration_engine,
          "Required migrations must re-apply from real state when a managed artifact is missing/outdated")

    check("AlisIntergration.session?.thinkfan" in thinkfan_service, "fan facade lost its optional owner")
    check("Process {" not in thinkfan_service and "Timer {" not in thinkfan_service, "fan facade retained duplicate polling")
    check("[Alis-Intergration](https://github.com/llocphann/Alis-Intergration)" in thinkfan_docs, "fan documentation must identify the official optional owner")

    if failures:
        print("ThinkFan/System Monitor contract regression(s):")
        for failure in failures:
            print(f"  - {failure}")
        raise SystemExit(1)

    print("ThinkFan/System Monitor contract: OK")


if __name__ == "__main__":
    main()
