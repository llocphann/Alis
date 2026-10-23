#!/usr/bin/env python3
"""Private greeter Image failover; no SDDM login, theme install or user data."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import struct
import tempfile
import subprocess
import zlib
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-greeter-wallpaper-") as name:
    folder = Path(name)
    theme = ROOT / "dots/sddm/pixel"
    # Execute only the installer's permission helper against a private copy.
    installed = folder / "installed"
    shutil.copytree(theme, installed)
    for path in installed.rglob("*"):
        path.chmod(0o700 if path.is_dir() else 0o600)
    stamp = installed / "assets/.alis-background-source.json"
    stamp.write_text("synthetic private metadata")
    stamp.chmod(0o600)
    installer = (ROOT / "scripts/sddm/install-pixel-sddm.sh").read_text()
    function = re.search(r"^ensure_greeter_permissions\(\) \{.*?^\}", installer, re.M | re.S).group()
    command = "set -e\nTHEME_DIR=" + shlex.quote(str(installed)) + "\nTHEME_SRC=" + shlex.quote(str(theme))
    command += "\nelevate() { return 99; }\n" + function + "\nensure_greeter_permissions\n"
    subprocess.run(["bash"], input=command, text=True, check=True, timeout=10)
    for path in [installed / "Main.qml", installed / "GreeterWallpaper.qml",
                 installed / "theme.conf", installed / "assets/default-background.svg"]:
        assert path.stat().st_mode & 0o777 == 0o644, path.name
    assert (installed / "assets").stat().st_mode & 0o777 == 0o755
    assert stamp.stat().st_mode & 0o777 == 0o600, "installer exposed private metadata"

    (folder / "GreeterWallpaper.qml").symlink_to(theme / "GreeterWallpaper.qml")
    (folder / "assets").symlink_to(theme / "assets", target_is_directory=True)
    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", zlib.crc32(kind + value) & 0xffffffff)
    image = folder / "synthetic.png"
    image.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))
                      + chunk(b"IDAT", zlib.compress((b"\0" + b"\x40\x80\xc0" * 2) * 2)) + chunk(b"IEND", b""))
    qml = r'''
import QtQuick
import QtTest
import Quickshell
ShellRoot {
 id: root
 property int frames: 0
 FloatingWindow {
  id: window; visible:true; implicitWidth:400;implicitHeight:240;color:"#111820"
  GreeterWallpaper {
   id: wallpaper;anchors.fill:parent;asynchronous:true
   fillMode:Image.PreserveAspectCrop
  }
 }
 TestCase {
  id:test;optional:true;when:false
  function check(value,message) { if(!value)throw new Error(message) }
  function ready(stage) {
   tryCompare(wallpaper,"status",Image.Ready,4000)
   check(wallpaper.status===Image.Ready,"image not ready at "+stage)
   const before=root.frames
   check(wallpaper.grabToImage(image=>root.frames++),"frame refused at "+stage)
   tryVerify(()=>root.frames>before,2000)
   check(root.frames>before,"image never rendered at "+stage)
  }
  function runChecks() { try {
   ready("no configured image")
   check(wallpaper.showingFallback,"empty configuration did not use bundled image")
   wallpaper.configuredSource="VALID_IMAGE";ready("configured wallpaper")
   check(!wallpaper.showingFallback,"valid wallpaper was replaced")
   wallpaper.configuredFallback="VALID_IMAGE"
   wallpaper.configuredSource="file:///nonexistent/alis-fixture-missing.png"
   ready("custom fallback");check(wallpaper.fallbackStage===1,"custom fallback ignored")
   wallpaper.configuredFallback=wallpaper.configuredSource
   ready("legacy duplicate missing path")
   check(wallpaper.fallbackStage===2,"duplicate path prevented bundled recovery")
   wallpaper.configuredFallback="file:///nonexistent/alis-fixture-fallback.png"
   ready("missing custom fallback")
   check(wallpaper.fallbackStage===2,"missing custom fallback prevented recovery")
   wallpaper.configuredSource="VALID_IMAGE";ready("source repaired")
   check(!wallpaper.showingFallback,"repaired source did not recover")
   wallpaper.configuredSource="";wallpaper.configuredFallback=""
   ready("settings cleared")
   check(wallpaper.fallbackStage===2,"cleared settings retained an obsolete image")
   console.info("SDDM_WALLPAPER_RUNTIME_PASS",root.frames,"rendered states")
  }catch(error){console.error("SDDM_WALLPAPER_RUNTIME_FAIL",error.message,error.stack)}Qt.quit() }
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
'''.replace("VALID_IMAGE", image.as_uri())
    (folder / "shell.qml").write_text(qml)
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: greeter Image test needs a private Niri surface")
        result = run_qs(folder, env, timeout=60)
        if os.environ.get("ALIS_GREETER_FIXTURE_LOG"):
            Path(os.environ["ALIS_GREETER_FIXTURE_LOG"]).write_text(result.stdout)
        if result.returncode or "SDDM_WALLPAPER_RUNTIME_PASS" not in result.stdout or any(
            token in result.stdout for token in ["SDDM_WALLPAPER_RUNTIME_FAIL", "ReferenceError:",
                                                "TypeError:", "Binding loop", "Failed to load configuration"]
        ):
            print(result.stdout)
            raise SystemExit(1)
        print("SDDM_WALLPAPER_RUNTIME_PASS private installer permissions, 7 rendered Image states; real greeter/cold boot UNRUN")
