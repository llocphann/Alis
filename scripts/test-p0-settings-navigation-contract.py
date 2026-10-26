#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "modules/settings/SettingsPageRegistry.qml").read_text(encoding="utf-8")
data = (ROOT / "modules/settings/SettingsPageRegistryData.qml").read_text(encoding="utf-8")
bar = (ROOT / "modules/settings/BarConfig.qml").read_text(encoding="utf-8")
quick = (ROOT / "modules/settings/QuickConfig.qml").read_text(encoding="utf-8")
system = (ROOT / "modules/settings/GeneralConfigCore.qml").read_text(encoding="utf-8")

def require(text: str, needle: str, message: str) -> None:
    if needle not in text:
        raise SystemExit(f"FAIL: P0 settings contract: {message}: {needle}")

def forbid(text: str, needle: str, message: str) -> None:
    if needle in text:
        raise SystemExit(f"FAIL: P0 settings contract: {message}: {needle}")

# Quick and Bar are canonical public pages. Retired UI choices are normalized
# at the persistence boundary instead of being instantiated and hidden later.
require(data, 'component: "modules/settings/QuickConfig.qml"',
        "Quick Settings lost its canonical page route")
require(data, 'component: "modules/settings/BarConfig.qml"',
        "Bar Settings lost its canonical page route")
forbid(registry, "QuickConfigHugOnly",
       "Quick Settings restored the retired compatibility facade")
forbid(registry, "BarConfigHugOnly",
       "Bar Settings restored the retired compatibility facade")
require(registry, 'Config.setNestedValue("bar.cornerStyle", 0)',
        "legacy Bar cornerStyle is no longer normalized to Hug")

# Canonical Bar Settings owns the Screen Edge controls required by the v1.0 gate.
# Normalize whitespace so formatting-only line wraps do not invalidate behavior.
bar_contract = re.sub(r"\s+", " ", bar)
for needle in [
    'title: Translation.tr("Screen Edge")',
    'text: Translation.tr("Screen edge width (px)")',
    '"appearance.screenEdge.width", value)',
    'text: Translation.tr("Screen edge shadow")',
    '"appearance.screenEdge.physicalShadow.enabled"',
    '"appearance.screenEdge.physicalShadow.size"',
    '"appearance.screenEdge.physicalShadow.opacity"',
]:
    require(bar_contract, needle, "public Bar Settings lost a Screen Edge control")

# Search must be useful before lazy page materialization and must not advertise
# retired Float/Rectangle corner-style controls that no longer exist in BarConfig.
for needle in [
    'section: Translation.tr("Screen Edge")',
    'label: Translation.tr("Screen edge width (px)")',
    'label: Translation.tr("Screen edge shadow")',
    'description: Translation.tr("Configure Screen Edge and connected surface shadows")',
]:
    require(data, needle, "static Settings search lost Screen Edge discoverability")
forbid(data, 'label: Translation.tr("Corner style")',
       "static search still exposes the retired corner-style selector")
forbid(data, 'description: Translation.tr("Bar corner style: hug, float or rectangle")',
       "static search still describes retired Float/Rectangle Bar surfaces")

# Quick has one job: shortcuts. Bar position and backdrop are owned by
# their dedicated pages; no post-load compatibility wrapper is allowed.
require(quick, 'settingsPageName: Translation.tr("Quick")',
        "Quick Settings lost its canonical page identity")
forbid(quick, 'Translation.tr("Bar style")',
       "Quick Settings still carries a retired style workaround")
forbid(quick, 'settingsTaskSection: "screen"',
       "Quick reintroduced duplicate Bar/backdrop settings")
forbid(quick, 'Config.setNestedValue("bar.vertical"',
       "Quick still writes the canonical Bar position")

# Bar must expose only active Hug controls directly; compatibility fields are
# normalized by SettingsPageRegistry and never materialized as hidden UI.
for retired in [
    'Translation.tr("Corner style")',
    'Translation.tr("Float shadow")',
    'Translation.tr("Show background")',
    'Config.options?.bar?.blurBackground',
    'Config.setNestedValue("bar.blurBackground',
]:
    forbid(bar, retired, "Bar Settings still instantiates a retired control")

# App-specific Fan Control belongs to the installed plugin's tab. Generic
# System power controls and old deep links remain reachable independently.
integrations = (ROOT / "modules/settings/IntegrationsConfig.qml").read_text()
facade = (ROOT / "modules/settings/GeneralConfig.qml").read_text()
require(integrations, 'AlisIntergration.installedPlugins.map', "plugin navigation must derive from discovery")
require(integrations, 'AlisIntergration.pluginEnabled(root.activePlugin)', "plugin settings lost their explicit opt-in gate")
require(facade, 'showIntegrationSettings: false', "System must keep only generic battery controls")
forbid(system, "ThinkfanSettings {", "System restored a duplicate plugin editor")
require(registry, 'const optionalPower = key === "system"', "legacy System plugin links lost their redirect")
require(facade, 'SettingsPageRegistry.navigateToKey("integrations", "Thinkfan")', "System fan links must reach Integrations")
require(data, 'section: "Thinkfan"', "static search lost the installed plugin destination")
require(data, 'keywords: ["fan", "fan control", "thinkfan", "thermal", "cooling", "rpm", "temperature", "system"]', "Fan Control search keywords drifted")

print("PASS: P0 Settings routes, Screen Edge discoverability and Fan Control ownership")
