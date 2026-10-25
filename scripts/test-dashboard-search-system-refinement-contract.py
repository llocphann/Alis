#!/usr/bin/env python3
"""Regression contract for Dashboard search crossfade and System monitor layout."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(source: str, token: str, message: str) -> None:
    if token not in source:
        raise SystemExit(message)


def forbid(source: str, token: str, message: str) -> None:
    if token in source:
        raise SystemExit(message)


search_bar = read("modules/overview/SearchBar.qml")
overview = read("modules/overview/OverviewDashboard.qml")
search = read("modules/overview/SearchWidget.qml")
system = read("modules/dashboard/DashSystem.qml")

forbid(search_bar, "id: songRecButton",
       "SongRec toolbar button must remain retired (MUSIC-R01).")
forbid(search_bar, "SongRec",
       "SearchBar must not reference retired SongRec singleton (MUSIC-R01).")
forbid(search_bar, "MaterialShape {",
       "SearchBar must not restore the stray custom MaterialShape geometry.")
forbid(search_bar, "RotationAnimation on rotation",
       "SearchBar must not create a transformed custom icon scene node.")
require(search_bar, 'colBackground: "transparent"',
        "SearchBar toolbar buttons must keep transparent shared chrome.")

require(overview, "opacity: root.dashboardOpacity",
        "Dashboard content must consume the smoothed crossfade progress.")
forbid(overview,
       "transform: Translate { y: (1 - root.dashboardProgress) * dashboardViewport.height }",
       "Dashboard/Search transition must not use the old vertical slide.")
require(overview, "resultsOpacity: root.searchResultsOpacity",
        "Search results must consume the smoothed crossfade progress.")
require(search, "property real resultsOpacity: 1",
        "SearchWidget must expose the embedded result-layer opacity.")
require(search, "opacity: root.resultsOpacity",
        "Search results must consume the shared crossfade progress.")

for token in (
    "component MetricTile: Rectangle",
    "component StatusChip: Rectangle",
    "history: ResourceUsage.cpuUsageHistory",
    "history: ResourceUsage.memoryUsageHistory",
    "history: ResourceUsage.gpuUsageHistory",
    "Graph {",
    'label: Translation.tr("Disk")',
    "id: fanPanel",
    'text: Translation.tr("Fan control")',
    "ThinkFanService.fanRpm",
    "ThinkFanService.fanLevel",
    "StyledSwitch {",
):
    require(system, token, f"Dashboard System monitor refinement missing: {token}")
forbid(system, "component VerticalBar:",
       "Dashboard System monitor must not regress to the old three vertical meters.")

print("Dashboard search crossfade + System monitor refinement contract: OK")
