#!/usr/bin/env python3
"""Bounded owned analyzer metadata probe; never stores PCM or media labels."""
import hashlib,json,os,pathlib,re,subprocess,sys,threading,time
root=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);out.mkdir(mode=0o700,exist_ok=True)
def dump():return json.loads(subprocess.check_output(['pw-dump'],text=True,timeout=5))
def analyzers(objects):
 clients={o['id']:o.get('info',{}).get('props',{}) for o in objects if o.get('type')=='PipeWire:Interface:Client'};result=[]
 for o in objects:
  if o.get('type')!='PipeWire:Interface:Node':continue
  p=o.get('info',{}).get('props',{});c=clients.get(p.get('client.id'),{})
  if c.get('application.process.binary')!='cava' and p.get('application.process.binary')!='cava' and p.get('application.name')!='cava':continue
  result.append({'id':o['id'],'serial':p.get('object.serial'),'client_pid':c.get('application.process.id'),'secure_pid':c.get('pipewire.sec.pid'),'latency_present':'node.latency' in p,'latency':p.get('node.latency'),'passive':p.get('node.passive'),'always_process':p.get('node.always-process'),'state':o.get('info',{}).get('state')})
 return result
objects=dump();physical={o['id'] for o in objects if o.get('type')=='PipeWire:Interface:Node' and o.get('info',{}).get('props',{}).get('media.class')=='Audio/Sink' and o.get('info',{}).get('props',{}).get('device.api')=='alsa'}
if not physical or analyzers(objects):raise SystemExit('STOP: missing physical output or existing native analyzer')
if any(k in os.environ for k in ('PIPEWIRE_PROPS','PIPEWIRE_LATENCY','PIPEWIRE_QUANTUM')):raise SystemExit('STOP: explicit owner override; default-policy probe unavailable')
def snapshot():
 graph=dump();rows=[];iteration=-1
 raw=subprocess.check_output(['pw-top','-b','-n','3'],text=True,timeout=8)
 for line in raw.splitlines():
  if re.match(r'^\s*S\s+ID\s+',line):iteration+=1;continue
  fields=line.split()
  if iteration<1 or len(fields)<10:continue
  try:
   ident=int(fields[1])
   if ident in physical:rows.append({'iteration':iteration,'id':ident,'state':fields[0],'quantum':int(fields[2]),'rate':int(fields[3]),'errors':int(fields[8])})
  except ValueError:pass
 return {'physical_nodes':[{'id':o['id'],'serial':o.get('info',{}).get('props',{}).get('object.serial'),'state':o.get('info',{}).get('state')} for o in graph if o['id'] in physical],'mature_statistics':rows}
cache=pathlib.Path.home()/'.cache/quickshell/cava_config.txt';installed=pathlib.Path.home()/'.config/quickshell/alis'
def identities():
 pid=subprocess.check_output(['systemctl','--user','show','alis.service','--property=MainPID','--value'],text=True).strip()
 hashes={str(p):hashlib.sha256((installed/p).read_bytes()).hexdigest() for p in map(pathlib.Path,['version.json','services/deferred/CavaService.qml','modules/mediaControls/EqualizerPanel.qml','scripts/equalizer-control.sh'])}
 return {'owner_pid':pid,'installed_sha':json.loads((installed/'version.json').read_text())['commit'],'runtime_hashes':hashes,'cache_sha256':hashlib.sha256(cache.read_bytes()).hexdigest() if cache.exists() else None}
before=identities();config=out/'owned.conf'
subprocess.run(['bash',str(root/'scripts/cava/generate_config.sh'),str(config),'30','100','64','true','__alis_music_player__'],stdout=subprocess.DEVNULL,check=True,timeout=8)
report={'scope':'Repository generator and wrapper; owned temporary native CAVA; no global settings, deployment, preset/routing/volume changes or PCM storage','source_sha':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),'physical_ids':sorted(physical),'identity_before':before,'before':snapshot(),'frames':{'complete':0,'nonzero':0,'invalid':0}}
process=None
try:
 process=subprocess.Popen(['bash',str(root/'scripts/cava/run.sh'),'-p',str(config)],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 def drain():
  for line in process.stdout:
   try:
    values=[float(v) for v in line.strip().split(';') if v!='']
    if len(values)!=64:raise ValueError()
    report['frames']['complete']+=1
    if max(values)>0:report['frames']['nonzero']+=1
   except ValueError:report['frames']['invalid']+=1
 thread=threading.Thread(target=drain,daemon=True);thread.start();time.sleep(.6)
 report['owned_pid']=process.pid;report['nodes']=analyzers(dump())
 report['ownership_verified']=len(report['nodes'])==1 and str(report['nodes'][0]['secure_pid'])==str(process.pid)
 report['during']=snapshot()
finally:
 if process:
  process.terminate()
  try:process.wait(timeout=3)
  except subprocess.TimeoutExpired:process.kill();process.wait(timeout=3)
  thread.join(timeout=1);report['child_exit']=process.returncode
 time.sleep(.25)
 report['after']=snapshot();report['remaining_analyzers']=analyzers(dump());report['identity_after']=identities();report['runtime_and_cache_preserved']=before==report['identity_after'];report['listening_acceptance']='NOT OBSERVED'
 (out/'trace.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
assert report['ownership_verified'] and not report['nodes'][0]['latency_present'] and report['nodes'][0]['passive'] is True
assert report['frames']['complete']>10 and report['frames']['invalid']==0
assert report['runtime_and_cache_preserved'] and not report['remaining_analyzers']
