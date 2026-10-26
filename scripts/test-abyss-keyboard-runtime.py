#!/usr/bin/env python3
"""Actual connected keyboard; fake input backend cannot touch the owner keyboard."""
import json,os,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='alis-abyss-keyboard-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(folder/entry).symlink_to(ROOT/entry)
 binary=folder/'bin';binary.mkdir();stub=binary/'ydotool'
 stub.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$OSK_LOG"\n');stub.chmod(0o700)
 (folder/'shell.qml').write_text(r"""
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
ShellRoot {
 id:root
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssPerimeter {id:perimeter}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function key(item,label){if(item.keyData?.label===label)return item;for(const child of item.children ?? []){const found=key(child,label);if(found)return found}return null}
  function runChecks(){try {
   tryCompare(Config,"ready",true,4000)
   GlobalStates.deferredPanelsReady=true
   GlobalStates.oskOpen=true
   const name="abyssOutputHost_"+Quickshell.screens[0].name
   tryVerify(()=>perimeter.outputHosts.length>0,8000)
   const win=perimeter.outputHosts[0]
   tryVerify(()=>findChild(win.contentItem,"oskPin")!==null,8000)
   const pin=findChild(win.contentItem,"oskPin"),content=pin.parent.parent.parent.parent
   const participant=content.participant
   check(participant?.identity==="keyboard" && participant.ready,"keyboard did not join the shared field")
   const a=key(content,"a")
   check(a && a.abyss,"keycaps did not use Abyss palette")
   // A 99% reveal can still leave several pixels of valid entrance motion.
   // Measure the fitted body only once its presentation has actually ended.
   tryCompare(participant,"progress",1,3000)
   const keys=findChild(content,"abyssKeyboardKeys")
   check(keys!==null,"actual key layout missing")
   const keyRect=keys.mapToItem(content,0,0,keys.width,keys.height)
   check(Math.abs(content.height-keyRect.height)<1 && Math.abs(participant.depth-content.height-2*participant.padding)<1,"keyboard body kept unused vertical space")
   check(Math.abs(participant.span-content.implicitWidth*participant.fitScale-2*participant.padding)<1,"keyboard frame did not fit its natural content")
   mousePress(a);wait(30);mouseRelease(a);wait(120)
   mouseClick(pin);check(content.pinned,"Pin did not lock position")
   mouseClick(pin);check(!content.pinned,"Pin could not release")
   const handle=findChild(content,"oskDrag")
   mousePress(handle);mouseMove(handle,handle.width/2+75,handle.height/2-90,100);mouseRelease(handle);wait(200)
   const saved=Array.from(Config.options.abyss.positions).find(p=>p.kind==="keyboard" && p.outputName===win.screen.name)
   check(saved && saved.alignment==="custom" && saved.position>=0 && saved.position<=1,"drag did not save a bounded output position")
   const count=Array.from(Config.options.abyss.positions).length
   mouseClick(findChild(content,"oskClose"));wait(600)
   check(!GlobalStates.oskOpen,"Close did not dismiss keyboard")
   GlobalStates.oskOpen=true
   tryVerify(()=>findChild(win.contentItem,"oskPin")!==null,5000)
   check(Array.from(Config.options.abyss.positions).length===count,"reopen duplicated position preferences")
   GlobalStates.oskOpen=false;wait(600)
   console.info("ABYSS_KEYBOARD_PASS shared-field key-down-up Pin drag output-save close reopen")
  }catch(e){console.error("ABYSS_KEYBOARD_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
""")
 with private_wayland(folder) as env:
  if env is None:print('SKIP: connected keyboard requires private Niri');raise SystemExit(0)
  config=folder/'config/illogical-impulse';config.mkdir(parents=True,exist_ok=True)
  value=json.loads((ROOT/'defaults/config.json').read_text());value['panelFamily']='abyss';value['enabledPanels']=['iiOnScreenKeyboard'];value['abyss']['companion']['enabled']=False;(config/'config.json').write_text(json.dumps(value))
  env.update(PATH=str(binary)+os.pathsep+env['PATH'],OSK_LOG=str(folder/'input.log'),QSG_RHI_BACKEND='opengl')
  result=run_qs(folder,env,timeout=40);output=result.stdout
  if result.returncode or 'ABYSS_KEYBOARD_PASS' not in output or any(e in output for e in ['ABYSS_KEYBOARD_FAIL','ReferenceError:','TypeError:','Unable to assign','Binding loop','Failed to load configuration']):print(output);raise SystemExit(1)
  lines=(folder/'input.log').read_text().splitlines()
  assert any(line.endswith('30:1') for line in lines) and any(line.endswith('30:0') for line in lines),'typing transport lost press/release: '+repr(lines)
  assert any('248:0' in line for line in lines),'Close did not release held modifiers'
  print('ABYSS_KEYBOARD_PASS shared-field key-down-up Pin drag output-save close reopen modifier-release (isolated fake input backend)')
