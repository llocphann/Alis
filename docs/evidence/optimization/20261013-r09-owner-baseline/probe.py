from pathlib import Path
import json,os,subprocess,time,hashlib
OUT=Path.cwd()/'.git/maintainer-validation/20261013-r09-owner-counter';CONFIG=Path('/home/llocphann/.config/quickshell/alis')
def ipc(method):
 p=subprocess.run(['qs','-p',str(CONFIG),'ipc','call','abyssHoverProbe',method],capture_output=True,text=True,timeout=3)
 if p.returncode:raise RuntimeError(p.stderr[-200:])
 return json.loads(p.stdout)
def identity():
 apps=json.loads(subprocess.check_output(['qs','list','--all','--json'],text=True));app=next(a for a in apps if a['shell_id']=='alis'and Path(a['config_path']).parent==CONFIG)
 manifest=CONFIG/'version.json';version=json.loads(manifest.read_text())if manifest.exists()else{}
 src={}
 for name in ['modules/abyss/AbyssPerimeter.qml','modules/abyss/looks/AbyssField.qml','modules/abyss/looks/AbyssField.frag.qsb','modules/common/widgets/PopupToolTip.qml']:
  p=CONFIG/name;src[name]=hashlib.sha256(p.read_bytes()).hexdigest()if p.exists()else None
 return {'pid':app['pid'],'launch':app['launch_time'],'version':version,'source_hashes':src}
def safe_state():
 s=ipc('snapshot');out=[]
 for v in s.get('outputs',[]):
  out.append({k:v.get(k)for k in ['output','fieldReady','editorOpen','liquidPopupsOpen','fullscreenCovered','largeFocus','genericPopup','popupSlots']})
 return {'timestampMs':s.get('timestamp'),'outputs':out}
before=identity();PID=before['pid'];proc=Path('/proc')/str(PID)
def stat():
 s=(proc/'stat').read_text();fields=s[s.rindex(')')+2:].split();return {'utime':int(fields[11]),'stime':int(fields[12]),'starttime':int(fields[19]),'rssPages':int(fields[21])}
initial_stat=stat();fds={}
for f in (proc/'fdinfo').iterdir():
 try:s=f.read_text()
 except OSError:continue
 if 'drm-client-id:'not in s:continue
 cid=next(l.split(':',1)[1].strip()for l in s.splitlines()if l.startswith('drm-client-id:'));fds.setdefault(cid,f)
def sample():
 row={'timeNs':time.monotonic_ns(),'timestampMs':round(time.time()*1000),'stat':stat(),'drm':{}}
 for cid,f in fds.items():
  text=f.read_text();row['drm'][cid]={}
  for line in text.splitlines():
   if line.startswith(('drm-engine-','drm-memory-','drm-resident-','amd-evicted-')):
    k,v=line.split(':',1);pieces=v.split();row['drm'][cid][k]={'value':int(pieces[0]),'unit':pieces[1]if len(pieces)>1 else''}
 return row
rows=[];states=[];frames=[];fail=None
try:
 for block in range(5):
  started=ipc('startFrames');assert any(v.get('started')for v in started),started
  begin=time.monotonic();next_state=begin
  while time.monotonic()-begin<6:
   rows.append(sample())
   if time.monotonic()>=next_state:states.append({'block':block,'snapshot':safe_state()});next_state=time.monotonic()+1
   time.sleep(.2)
  frames.append({'block':block,'trace':ipc('stopFrames')})
except Exception as e:fail=str(e)
finally:
 try:last_frames=ipc('stopFrames')
 except Exception as e:last_frames={'error':str(e)}
 after=identity();same=before==after and stat()['starttime']==initial_stat['starttime']
 receipt={'classification':'read-only installed owner desktop diagnostic; intentional owner interactions; instrumentation/IPC overhead; no optimized comparison or percentage gain','before':before,'after':after,'same_source_and_process':same,'clockTicks':os.sysconf('SC_CLK_TCK'),'pageBytes':os.sysconf('SC_PAGE_SIZE'),'rows':rows,'states':states,'frames':frames,'lastFrames':last_frames,'failure':fail}
 (OUT/'result.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('rows',len(rows),'blocks',len(frames),'stable',same,'failure',fail)
 for block in frames:
  print(block['block'],[{k:t[k]for k in ['count','p50','p95','p99','max','panelProgressChangedFrames','popupOpenFrames','heartbeatOver100Ms','heartbeatMaxIntervalMs']}for t in block['trace']])
 if fail or not same:raise SystemExit(1)
