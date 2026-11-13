from pathlib import Path
import os, sys, tempfile, json, re
sys.path.insert(0,str(Path(__file__).resolve().parent))
from native_test_session import private_wayland, run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='alis-cloud-labels-') as name:
 p=Path(name);host=Path(os.environ.get('ALIS_COMBO_HOST',str(ROOT)))
 out=Path(os.environ.get('ALIS_COMBO_EVIDENCE_DIR',str(p/'evidence')));out.mkdir(parents=True,exist_ok=True)
 for item in ['modules','services','scripts','defaults','GlobalStates.qml','qmldir','translations','assets']:(p/item).symlink_to(host/item)
 (p/'shell.qml').write_text('''import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import qs.modules.common.widgets
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 QtObject { id: wrapped; property string displayName:"Wrapped QObject cloud" }
 ListModel { id: list; ListElement { displayName:"ListModel cloud" } }
 FloatingWindow { visible:true; implicitWidth:500; implicitHeight:150; StyledComboBox { id:combo; width:460; y:20 } }
 TestCase {
  id:tc; when:false; optional:true
  function runChecks() {
   try {
    const cases=[{model:[{displayName:"Gemini 4 Argon"}],expected:"Gemini 4 Argon"},{model:[{model:{name:"Nested cloud"}}],expected:"Nested cloud"},{model:[{label:"[object V4ReferenceObject]",displayName:"Clean cloud label"}],expected:"Clean cloud label"},{model:[wrapped],expected:"Wrapped QObject cloud"},{model:list,role:"displayName",expected:"ListModel cloud"},{model:["Plain model"],expected:"Plain model"},{model:[],expected:""},{model:null,expected:""}];
    for(let i=0;i<cases.length;i++) {
     const c=cases[i]; combo.textRole=c.role||""; combo.model=c.model; combo.currentIndex=0; wait(70);
     const label=combo.contentItem.children.find(x=>x.text!==undefined);
     const actual=label?label.text:"";
     console.info("CLOUD_LABEL",JSON.stringify({index:i,expected:c.expected,actual:actual,indexValue:combo.currentIndex,displayText:combo.displayText,isArray:Array.isArray(combo.model),modelLength:combo.model?combo.model.length:null,firstResolved:combo._resolveItemDisplayText(combo.model?combo.model[0]:null,combo.textRole,0),status:actual===c.expected?"PASS":"FAIL"}));
     combo.popup.open(); wait(60); combo.popup.close();
    }
    console.info("CLOUD_LABEL_DONE"); Qt.quit();
   }catch(e){console.error("CLOUD_LABEL_ABORT",e.message);Qt.exit(1)}
  }
 }
 Timer {interval:500;running:true;onTriggered:tc.runChecks()}
}''')
 with private_wayland(p) as env:
  if env is None:raise SystemExit('SKIP private compositor unavailable')
  result=run_qs(p,env,timeout=12)
 samples=[json.loads(x) for x in re.findall(r'CLOUD_LABEL (\{[^\n]+\})',result.stdout)]
 receipt={'scope':'Selected source or installed shared StyledComboBox in private native compositor. Covers JavaScript object, nested model, polluted label, QObject and ListModel; no provider/account calls. Host and Companion both import shared host widget. Settings-screen interaction/real provider models not independently proven.','exit':result.returncode,'complete':'CLOUD_LABEL_DONE' in result.stdout,'checks':samples}
 (out/'native.log').write_text(result.stdout);(out/'native.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))

 if result.returncode or not receipt['complete'] or len(samples)!=8 or any(x['status']!='PASS' for x in samples):raise SystemExit(1)
