#!/usr/bin/env python3
"""Contract for the compact connected Weather popup and shared orbit."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEATHER_DIR = ROOT / "modules/bar/weather"


def require(source: str, *features: str) -> None:
    for feature in features:
        if feature not in source:
            raise AssertionError(f"Weather popup lost {feature!r}")


def main() -> None:
    source = (WEATHER_DIR / "WeatherPopupContent.qml").read_text()
    wrapper = (WEATHER_DIR / "WeatherPopup.qml").read_text()
    orbital = (WEATHER_DIR / "OrbitalWeather.qml").read_text()
    dashboard = (ROOT / "modules/dashboard/DashWeather.qml").read_text()

    # Merged orientation-aware popup: Orbital and Detailed appear together in one
    # surface (side-by-side on top/bottom edges, vertical Orbital-top / Detailed-bottom on left/right edges).
    require(wrapper, "StyledPopup {", "WeatherPopupContent {",
            "verticalLayout: root._attachmentVertical",
            "compact: (root.presentationWindow?.width ?? 1920)")
    require(source, "property bool verticalLayout: false",
            "readonly property real panelWidth: root.compact ? 344 : 372",
            "readonly property real orbitHeight: root.compact ? 250 : 276",
            "readonly property real orbitalInset: root.compact ? 6 : 8",
            "readonly property real orbitalRightInset: root.orbitalInset",
            "columns: 2",
            "implicitHeight: root.compact ? 36 : 42")

    require(source, "id: weatherViewport", "clip: true",
            "id: timeWeatherPanel", "id: sectionDivider",
            "liquidMode: true", "id: detailPanel",
            "liquidAnimationActive: root.visible",
            "id: primaryMetrics", "id: sunTimeline")
    for removed in ("id: tabIndicator", "WheelHandler {", "property int currentTab:",
                    "Behavior on tabPosition", "id: modeSwitch", "component OrbitArrow:",
                    "selectedHourIndex", "function cycleHour(",
                    "model: (Weather.data?.forecast ?? []).slice("):
        if removed in source:
            raise AssertionError(f"Removed tab/large-popup control remains: {removed}")

    require(orbital, "(Weather.data?.hourly ?? []).slice(0, 8)",
            "function orbitAngleForHour(label, tables): real",
            "readonly property real conceptOrbitAspect:",
            "readonly property real availableLiquidWidth:",
            "readonly property real availableLiquidHeight:",
            "readonly property real liquidOrbitAspect:",
            "Math.min(1.32, availableLiquidAspect)",
            "width * 0.13, root.orbitStageHeight * 0.19",
            "readonly property real orbitRadiusX:",
            "readonly property real orbitRadiusY:",
            "readonly property real orbitStageHeight: Math.max(1, height)",
            "LiquidOrbitalField {", "root.liquidMode")
    for removed in ("id: conceptFooter", "id: aqiPill", "footerHeight"):
        if removed in orbital:
            raise AssertionError(f"Removed footer status remains: {removed}")
    require(dashboard, "import qs.modules.bar.weather", "OrbitalWeather {")

    print("Weather compact popup and shared orbit contract: PASS")


if __name__ == "__main__":
    main()
