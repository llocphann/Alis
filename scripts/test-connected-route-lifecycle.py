#!/usr/bin/env python3
"""Regression checks for supported connected-surface presentation lifecycle."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def body(source: str, marker: str) -> str:
    start = source.index("{", source.index(marker))
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start + 1:end - 1]


def weather_actions(source: str) -> None:
    # Execute the actual handlers. Pointer activation must stay with the hover
    # popup, keyboard activation keeps its focus affordance, and right-click
    # refresh retains exactly one explicit notification. No desktop is touched.
    handlers = {
        "primary": body(source, "function activatePrimary("),
        "click": body(source, "onClicked:"),
    }
    program = r'''
const assert=require('node:assert/strict');
const handlers=HANDLERS;
let focus=0,sidebar=0,refresh=0,notify=0;
const root={_pointerFocused:true,forceActiveFocus(){focus++}};
const GlobalStates={openSidebarRight(){sidebar++}};
const Qt={LeftButton:1,RightButton:2,MiddleButton:4};
const Weather={forceRefresh(){refresh++}};
const Quickshell={execDetached(){notify++}};
const Translation={tr:value=>value};
new Function('root','GlobalStates',handlers.primary)(root,GlobalStates);
assert.equal(root._pointerFocused,false);assert.equal(focus,1);assert.equal(sidebar,0);
const click=new Function('mouse','root','GlobalStates','Qt','Weather','Quickshell','Translation',handlers.click);
for(const button of [Qt.LeftButton,Qt.MiddleButton]){
 click({button},root,GlobalStates,Qt,Weather,Quickshell,Translation);
 assert.equal(sidebar,0);assert.equal(refresh,0);assert.equal(notify,0);
}
click({button:Qt.RightButton},root,GlobalStates,Qt,Weather,Quickshell,Translation);
assert.equal(sidebar,0);assert.equal(refresh,1);assert.equal(notify,1);
'''.replace("HANDLERS", json.dumps(handlers))
    subprocess.run(["node", "-e", program], check=True)


def main() -> None:
    popup = read("modules/bar/StyledPopup.qml")
    media = read("modules/bar/Media.qml")
    weather_bar = read("modules/bar/weather/WeatherBar.qml")
    weather_popup = read("modules/bar/weather/WeatherPopup.qml")
    sidebar = read("modules/sidebar/SidebarHost.qml")

    for token in (
        "property bool requestedVisible",
        "property bool _lingerVisible",
        "property real revealProgress",
        "retractTimer",
        "progress: root.revealProgress",
        "mask: connectedMask",
    ):
        check(token in popup,
              f"StyledPopup missing supported connected lifecycle contract: {token}")

    check("root.requestedVisible || root._lingerVisible" in popup,
          "StyledPopup must remain resident through its retract tail")
    check("inputEnabled: root.requestedVisible" in popup,
          "StyledPopup must revoke semantic input when a click popup closes")

    check(media.count("StyledPopup {") >= 1,
          "Media expanded controls must use StyledPopup")
    check("hoverActivates: true" in media
          and "keyboardFocus: root.barMediaPopupVisible" in media,
          "Media popup must open on hover without taking focus until explicitly pinned")
    check("SurfaceRouteController" not in media
          and "qs.modules.perimeter" not in media,
          "Normal Media UX must not depend on retired broad perimeter routing")

    check("StyledPopup {" in weather_popup,
          "Weather hover popup must use the supported StyledPopup shell")
    weather_actions(weather_bar)
    check("SurfaceRouteController" not in weather_bar
          and "SurfaceRouteController" not in weather_popup,
          "Normal Weather UX must not depend on retired broad perimeter routing")

    for token in (
        "ConnectedSurfaceAbyssEdgeSurface {",
        "id: sidebarAbyssSurface",
        "ownerThickness: root.screenEdgeHoverWidth",
        "PerimeterTokens.seamOverlap",
        "Config.options?.appearance?.screenEdge?.width ?? 10",
    ):
        check(token in sidebar,
              f"Sidebar connected route contract missing: {token}")
    check("SidebarEdgeConnectors.qml" not in sidebar,
          "Sidebar lifecycle must not depend on the retired standalone bridge window")

    if failures:
        print("Connected presentation lifecycle regression(s):")
        for failure in failures:
            print(f"  - {failure}")
        raise SystemExit(1)

    print("Connected presentation lifecycle: OK")


if __name__ == "__main__":
    main()
