from pathlib import Path
import os,json,subprocess,time,signal,hashlib
b=Path(__file__).resolve().parent
meta=json.loads((b/'frozen-driver.json').read_text());env=dict(os.environ,HADALIS_VALIDATION_LOG=meta['raw_log'])
assert hashlib.sha256(Path(meta['driver']).read_bytes()).hexdigest()==meta['driver_sha256']
stop=False
proc=None
def terminate(signum,frame):
 global stop
 stop=True
 if proc is None:return
 children={proc.pid}
 for _ in range(10):
  for p in Path('/proc').iterdir():
   if not p.name.isdigit():continue
   try:
    pp=int((p/'stat').read_text().split(') ',1)[1].split()[1])
    if pp in children:children.add(int(p.name))
   except (OSError,ValueError):pass
 for pid in sorted(children,reverse=True):
  try:os.kill(pid,signal.SIGTERM)
  except ProcessLookupError:pass
signal.signal(signal.SIGTERM,terminate);signal.signal(signal.SIGINT,terminate)
start=time.time()
with Path(meta['stdout']).open('wb')as stream:
 proc=subprocess.Popen(['bash',meta['driver'],'--current-repo'],cwd=meta['anchor'],env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
 (b/'running.json').write_text(json.dumps({'supervisor':os.getpid(),'driver_pid':proc.pid,'source':meta['source'],'started_epoch':start},indent=2)+'\n')
 rc=proc.wait()
raw=Path(meta['raw_log']).read_bytes()
receipt={**meta,'status':'STOPPED'if stop else'FINISHED','os_exit_status':rc,'seconds':time.time()-start,'raw_sha256':hashlib.sha256(raw).hexdigest(),'raw_bytes':len(raw)}
(b/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt),flush=True)
