from pathlib import Path
import tempfile,json,subprocess,sys
r=Path.cwd();sys.path.insert(0,str(r/'scripts'))
from native_test_session import private_wayland,run_qs
out=Path('/home/llocphann/Shared_Documents/Obsidian-Vault/10_Projects/Alis/.git/maintainer-validation/20261013-tooltip-construction-lifetime')
with tempfile.TemporaryDirectory(prefix='alis-tooltip-allocation-') as name:
 f=Path(name)
 for entry in ['modules','services','GlobalStates.qml','assets','scripts','defaults','translations']:(f/entry).symlink_to(r/entry)
 entries=[]
 for prefix,sha in [('Before','28bf63b93'),('After','fe80d90b3')]:
  base=prefix+'PopupToolTip';styled=prefix+'StyledToolTip'
  s=subprocess.check_output(['git','show',sha+':modules/common/widgets/PopupToolTip.qml'],text=True)
  s=s.replace('id: contentItem\n','id: contentItem\n            Component.onCompleted:console.info("DEFAULT_CTOR",root.objectName)\n            Component.onDestruction:console.info("DEFAULT_DTOR",root.objectName)\n')
  (f/(base+'.qml')).write_text(s)
  s=subprocess.check_output(['git','show',sha+':modules/common/widgets/StyledToolTip.qml'],text=True).replace('PopupToolTip {',base+' {',1)
  (f/(styled+'.qml')).write_text(s)
  entries.extend([f'{base} 1.0 {base}.qml',f'{styled} 1.0 {styled}.qml'])
 (f/'qmldir').write_text((r/'qmldir').read_text()+'\n'+'\n'.join(entries)+'\n')
 (f/'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
ShellRoot {
 Component.onCompleted:Quickshell.watchFiles=false
 Item {id:owner}
 Component {id:oldStyle;BeforeStyledToolTip {text:"Allocation QA"}}
 Component {id:newStyle;AfterStyledToolTip {text:"Allocation QA"}}
 Component {id:oldPlain;BeforePopupToolTip {text:"Allocation QA"}}
 Component {id:newPlain;AfterPopupToolTip {text:"Allocation QA"}}
 TestCase {
  id:test;when:false;optional:true
  function run(){try{
   tryCompare(Config,"ready",true,5000)
   for(const row of [[oldStyle,"before-styled",30],[newStyle,"after-styled",30],[oldPlain,"before-plain",10],[newPlain,"after-plain",10]]){
    const objects=[];for(let i=0;i<row[2];i++)objects.push(row[0].createObject(owner,{objectName:row[1],extraVisibleCondition:false,alternativeVisibleCondition:false}))
    wait(0);for(const object of objects)object.destroy();wait(0)
   }
   console.info("TOOLTIP_LIFETIME_DONE")
  }catch(e){console.error("TOOLTIP_LIFETIME_FAIL",e.message)}Qt.quit()}
 }
 Timer {running:true;interval:120;onTriggered:test.run()}
}''')
 with private_wayland(f) as env:
  assert env
  cfg=f/'config/illogical-impulse';cfg.mkdir(parents=True,exist_ok=True);(cfg/'config.json').write_text((r/'defaults/config.json').read_text())
  result=run_qs(f,env,15);(out/'native.log').write_text(result.stdout)
  from collections import Counter
  counts={marker:Counter(line.split(marker+' ')[-1]for line in result.stdout.splitlines()if marker+' 'in line)for marker in ['DEFAULT_CTOR','DEFAULT_DTOR']}
  receipt={'before_sha':subprocess.check_output(['git','rev-parse','28bf63b93'],text=True).strip(),'after_sha':subprocess.check_output(['git','rev-parse','fe80d90b3'],text=True).strip(),'copied_source_instrumented':'only default content constructor/destructor logs added','native_exit':result.returncode,'counts':counts}
  (out/'receipt.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt))
  expected={'before-styled':30,'before-plain':10,'after-plain':10}
  assert result.returncode==0 and 'TOOLTIP_LIFETIME_DONE'in result.stdout and all(dict(v)==expected for v in counts.values())
