#!/usr/bin/env python3
"""The Sidebar Left interior uses the approved Abyss material only on Abyss."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sidebar=(root/"modules/sidebarLeft/SidebarLeftContent.qml").read_text()
weather=(root/"modules/bar/weather/WeatherPopupContent.qml").read_text()
checks=[
 ('import qs.modules.abyss.looks' in sidebar,"shared material dependency"),
 ('property color innerContentSurfaceColor:' in sidebar,"reactive material property"),
 ('Config.options?.panelFamily === "abyss"' in sidebar,"explicit panel family policy"),
 ('ColorUtils.mix(AbyssStyle.contentLayer, AbyssStyle.accent, .88)' in sidebar,
  "same color blend as Weather Details"),
 ('ColorUtils.mix(AbyssStyle.contentLayer, AbyssStyle.accent, .88)' in weather,
  "approved reference still intact"),
 ('objectName: "sidebarLeftInnerSurface"' in sidebar,"native-test identity"),
 ('color: root.innerContentSurfaceColor' in sidebar,"inner plate uses shared material"),
 ('sidebarLeftBackground.cardStyle ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0'
  in sidebar,"original connected outer paint"),
 ('color: root.externalConnectedSurface' in sidebar,"original outer panel semantics"),
 ('border.width: 0 // Screen Edge seam owns the outer boundary' in sidebar,
  "seam remains externally owned"),
 ('clip: true' in sidebar,"content clipping remains"),
 ('color: Appearance.colors.colLayer1\n                border.width: 0' not in sidebar,
  "fixed neutral inner paint retired"),
]
for ok,label in checks:
    assert ok,label
print("SIDEBAR_LEFT_THEME_SOURCE_PASS",len(checks),"contracts")
