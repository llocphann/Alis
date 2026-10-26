#!/usr/bin/env python3
"""Real Management UI restores internal Todo when the package is absent."""
import json
from pathlib import Path
import tempfile
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-integration-recovery-") as name:
    private = Path(name)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
        (private / entry).symlink_to(ROOT / entry)
    vault = private / "vault"
    vault.mkdir()
    sentinel = vault / "owner.md"
    sentinel.write_bytes(b"preserve synthetic vault bytes\n")
    config = private / "config/alis"
    config.mkdir(parents=True)
    options = json.loads((ROOT / "defaults/config.json").read_text())
    options["todo"]["backend"] = "obsidian"
    options["todo"]["obsidian"]["vaultPath"] = str(vault)
    options["integrations"]["alisIntergration"]["obsidian"] = True  # Saved selection survives missing package.
    options["integrations"]["obsidian"]["autoTheme"] = False
    (config / "config.json").write_text(json.dumps(options))
    (private / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 FloatingWindow {visible:true;implicitWidth:800;implicitHeight:700
  IntegrationsConfig {id:page;anchors.fill:parent}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function run(){try{
   tryCompare(Config,"ready",true,4000)
   tryCompare(AlisIntergration,"diagnostic","not-installed",4000)
   check(page.primaryTabs.length===1 && page.activePlugin==="management","absent package exposed plugin tabs")
   check(AlisIntergration.session===null && !AlisIntergration.obsidianEnabled,"missing package started workers")
   check(Config.options.integrations.alisIntergration.obsidian===true,"discovery erased the saved plugin choice")
   tryCompare(Todo,"backend","obsidian",2000)
   const before=JSON.stringify(Config.options.todo.obsidian)
   const restore=findChild(page,"integrationRestoreInternalTodos")
   tryVerify(()=>restore!==null && restore.visible && restore.enabled,4000)
   restore.clicked()
   tryCompare(Todo,"backend","internal",2000)
   check(JSON.stringify(Config.options.todo.obsidian)===before,"recovery changed saved source paths")
   check(AlisIntergration.session===null,"recovery activated optional code")
   console.info("INTEGRATION_RECOVERY_RUNTIME_PASS")
  }catch(error){console.error("INTEGRATION_RECOVERY_RUNTIME_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(private) as env:
        if env is None:
            raise SystemExit("SKIP: Management recovery requires private Niri")
        result = run_qs(private, env, timeout=25)
    if result.returncode or "INTEGRATION_RECOVERY_RUNTIME_PASS" not in result.stdout or any(token in result.stdout for token in
        ("INTEGRATION_RECOVERY_RUNTIME_FAIL", "ReferenceError:", "TypeError:", "Unable to assign", "Failed to load configuration")):
        print(result.stdout)
        raise SystemExit(1)
    assert sentinel.read_bytes() == b"preserve synthetic vault bytes\n"
print("INTEGRATION_RECOVERY_RUNTIME_PASS absent package, saved enable flag, Management recovery and preserved vault/source paths")
