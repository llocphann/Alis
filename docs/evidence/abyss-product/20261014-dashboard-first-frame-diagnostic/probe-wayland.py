from pathlib import Path
import tempfile,sys,json,subprocess
root=Path.cwd();source=Path('/tmp/alis-ready-exact-537e791e4');sys.path.insert(0,str(source/'scripts'))
from native_test_session import private_wayland,run_qs
out=root/'.git/maintainer-validation/20261014-dashboard-first-frame'
with tempfile.TemporaryDirectory(prefix='alis-dashboard-first-frame-')as name:
 f=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations']:(f/entry).symlink_to(source/entry)
 v=f/'variants';v.mkdir()
 q=(source/'modules/dashboard/Dashboard.qml').read_text().replace('import qs.services','import qs.services\nimport qs.modules.dashboard')
 q=q.replace('id: root\n','id: root\n    property alias qaPanel: panelRoot\n    property alias qaContent: contentLoader\n',1)
 (v/'DiagnosticDashboard.qml').write_text(q)
 (f/'shell.qml').write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.modules.common
import "variants"
ShellRoot {
 id:root;property var frames:[];property bool collect:false;property var events:[]
 Component.onCompleted:Quickshell.watchFiles=false
 DiagnosticDashboard {id:dash}
 Connections {
  target:dash.qaContent.Window.window
  function onFrameSwapped(){if(root.collect)root.frames.push({time:Date.now(),offset:dash.qaContent.panelTranslateY,presented:dash._presentedOpen,content:dash._contentPresented})}
 }
 TestCase {
  id:test;when:false;optional:true
  function run(){try{
   tryCompare(Config,"ready",true,5000);GlobalStates.deferredPanelsReady=true;wait(300)
   // A bounded synthetic render delay exercises the existing first-entry
   // guarantee without changing the owner window or motion parameters.
   root.collect=true;GlobalStates.dashboardOpen=true;dash.qaPanel.updatesEnabled=false
   wait(500)
   root.events.push({stage:"delayed-paint",time:Date.now(),offset:dash.qaContent.panelTranslateY,presented:dash._presentedOpen,frames:root.frames.length})
   dash.qaPanel.updatesEnabled=true;wait(700)
   root.collect=false;GlobalStates.dashboardOpen=false
   console.info("DASH_FIRST_FRAME_DIAGNOSTIC",JSON.stringify({events:root.events,frames:root.frames}))
  }catch(e){console.error("DASH_FIRST_FRAME_DIAGNOSTIC_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:150;running:true;onTriggered:test.run()}
}
''')
 with private_wayland(f)as env:
  assert env
  cfg=f/'config/illogical-impulse';cfg.mkdir();(cfg/'config.json').write_text((source/'defaults/config.json').read_text())
  result=run_qs(f,env,35);(out/'native-wayland.log').write_text(result.stdout)
 for line in result.stdout.splitlines():
  if 'DASH_FIRST_FRAME_DIAGNOSTIC 'in line:
   payload=json.loads(line.split('DASH_FIRST_FRAME_DIAGNOSTIC ',1)[1]);(out/'result.json').write_text(json.dumps({'source_sha':'537e791e492d4cef5a49bdc2d742a59ef688ef38','scope':'actual standalone Dashboard with private no-focus Wayland/config and synthetic500ms render suppression; no owner/compositor/performance claim',**payload},indent=2)+'\n');print(payload)
 print('native exit',result.returncode)
