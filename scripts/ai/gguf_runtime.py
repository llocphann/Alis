#!/usr/bin/env python3
"""One supervised local llama.cpp request; no persistent model or TCP listener.

Text-only baseline. One private Unix socket, one slot, bounded context/output,
CPU threads, startup/request deadlines, cross-client lock and parent-death
cleanup. Quickshell only sends data to this helper; it never owns a model.
"""
import ctypes
import fcntl
import http.client
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
from local_models import valid_file,runtime

class RuntimeErrorLocal(Exception):pass

EFFORTS={
    'off':{'budget':0,'max_tokens':180},
    'low':{'budget':96,'max_tokens':320},
    'medium':{'budget':256,'max_tokens':512},
    'high':{'budget':512,'max_tokens':832},
}

class UnixHTTP(http.client.HTTPConnection):
    def __init__(self,path,timeout):super().__init__('localhost',timeout=timeout);self.path=str(path)
    def connect(self):
        self.sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout);self.sock.connect(self.path)

def request(path,route,payload=None,timeout=2):
    conn=UnixHTTP(path,timeout)
    try:
        conn.request('GET' if payload is None else 'POST',route,
            None if payload is None else json.dumps(payload).encode(),{'Content-Type':'application/json'})
        response=conn.getresponse();raw=response.read(262145)
        if len(raw)>262144:raise RuntimeErrorLocal('Local reply exceeded the limit')
        if response.status!=200:raise RuntimeErrorLocal('Local model returned HTTP '+str(response.status))
        return json.loads(raw)
    finally:conn.close()

def private_dir():
    base=Path(os.environ.get('XDG_RUNTIME_DIR',tempfile.gettempdir()))
    folder=base/('alis-aqua-'+str(os.getuid()))
    folder.mkdir(mode=0o700,exist_ok=True)
    st=folder.lstat()
    if folder.is_symlink() or st.st_uid!=os.getuid() or st.st_mode&0o077:
        raise RuntimeErrorLocal('Aqua runtime directory is not private')
    return folder

def group_alive(pgid):
    if not pgid:return False
    try:os.killpg(pgid,0);return True
    except ProcessLookupError:return False
    except PermissionError:return True

def stop(process,pgid=None):
    if process is None and not pgid:return
    group=pgid or process.pid
    try:os.killpg(group,signal.SIGTERM)
    except ProcessLookupError:pass
    deadline=time.monotonic()+3
    while group_alive(group) and time.monotonic()<deadline:
        if process is not None and process.poll() is None:
            try:process.wait(timeout=.05)
            except subprocess.TimeoutExpired:pass
        else:time.sleep(.05)
    if group_alive(group):
        try:os.killpg(group,signal.SIGKILL)
        except ProcessLookupError:pass
        deadline=time.monotonic()+3
        while group_alive(group) and time.monotonic()<deadline:time.sleep(.05)
    if process is not None and process.poll() is None:
        try:process.wait(timeout=.2)
        except subprocess.TimeoutExpired:pass
    if group_alive(group):raise RuntimeErrorLocal('Local model process group did not stop')

def complete(model_path,messages,reply_format=None,server_path=None,thinking_effort='off'):
    effort=str(thinking_effort or 'off').lower()
    if effort not in EFFORTS:raise RuntimeErrorLocal('Invalid thinking effort')
    effort_profile=EFFORTS[effort]
    model=Path(model_path).expanduser()
    if not valid_file(model):raise RuntimeErrorLocal('The selected GGUF is missing or incomplete')
    executable=Path(server_path or runtime())
    if executable.name!='llama-server' or not executable.is_file() or not os.access(executable,os.X_OK):
        raise RuntimeErrorLocal('Install llama.cpp or Unsloth to run this local model')
    if not isinstance(messages,list):raise RuntimeErrorLocal('Invalid local messages')
    bounded=[]
    system=[m for m in messages if isinstance(m,dict) and m.get('role')=='system'][:2]
    recent=[m for m in messages if isinstance(m,dict) and m.get('role') in ('user','assistant')][-6:]
    for m in system+recent:
        if not isinstance(m.get('content'),str):raise RuntimeErrorLocal('This local baseline accepts text messages')
        bounded.append({'role':m['role'],'content':m['content'][:3500 if m['role']=='system' else 1200]})
    if not bounded or sum(len(m['content']) for m in bounded)>12000:raise RuntimeErrorLocal('Local conversation is too large')
    folder=private_dir()
    lock_fd=os.open(folder/'model.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
    with os.fdopen(lock_fd,'w') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise RuntimeErrorLocal('The local model is answering another request')
        with tempfile.TemporaryDirectory(prefix='r-',dir=folder) as temp:
            sock=Path(temp)/'api.sock';process=None;process_group=None
            original=signal.getsignal(signal.SIGTERM)
            def cancelled(signum,frame):raise RuntimeErrorLocal('Local request cancelled')
            signal.signal(signal.SIGTERM,cancelled)
            parent=os.getpid()
            def child_setup():
                os.umask(0o077)
                if ctypes.CDLL(None).prctl(1,signal.SIGTERM)!=0 or os.getppid()!=parent:os._exit(1)
            try:
                env={k:v for k,v in os.environ.items() if not k.startswith('LLAMA_ARG_')}
                command=[str(executable),'-m',str(model), '--host',str(sock),'--no-webui','--no-webui-mcp-proxy',
                    '--alias','aqua-local','-c','2048','-np','1','-t',str(min(4,os.cpu_count() or 1)),
                    '-ngl','0','--reasoning','auto','--poll','0','--jinja']
                process=subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,start_new_session=True,preexec_fn=child_setup,env=env)
                process_group=process.pid
                deadline=time.monotonic()+70
                while time.monotonic()<deadline-15:
                    if process.poll() is not None:raise RuntimeErrorLocal('llama.cpp could not load this GGUF')
                    if sock.exists():
                        try:
                            if request(sock,'/health').get('status')=='ok':break
                        except (OSError,ValueError,RuntimeErrorLocal):pass
                    time.sleep(.15)
                else:raise RuntimeErrorLocal('Local model startup timed out')
                payload={'model':'aqua-local','messages':bounded,'stream':False,
                    'max_tokens':effort_profile['max_tokens'],'temperature':.7,
                    'thinking_budget_tokens':effort_profile['budget'],
                    'chat_template_kwargs':{'enable_thinking':effort!='off'}}
                if reply_format is not None:payload['response_format']=reply_format
                result=request(sock,'/v1/chat/completions',payload,timeout=max(1,deadline-time.monotonic()))
                choice=result.get('choices',[{}])[0]
                text=choice.get('message',{}).get('content','')
                if not isinstance(text,str) or not text.strip():raise RuntimeErrorLocal('Local model returned no text')
                return {'text':text[:6000],'usage':result.get('usage',{}),'finishReason':choice.get('finish_reason','')}
            except (OSError,http.client.HTTPException,ValueError,KeyError,IndexError) as exc:raise RuntimeErrorLocal('Local model request failed') from exc
            finally:
                signal.signal(signal.SIGTERM,original)
                stop(process,process_group)

if __name__=='__main__':
    try:
        raw=sys.stdin.buffer.readline(65537)
        if len(raw)>65536:raise RuntimeErrorLocal('Local request exceeded the limit')
        data=json.loads(raw)
        result=complete(data['modelPath'],data['messages'],server_path=data.get('runtimePath'),
            thinking_effort=data.get('thinkingEffort','off'))
        print('data: '+json.dumps({'choices':[{'delta':{'content':result['text']},'finish_reason':'stop'}]}))
        print('data: [DONE]')
    except (RuntimeErrorLocal,ValueError,KeyError,TypeError) as exc:
        print('data: '+json.dumps({'error':{'message':str(exc)[:160]}}))
        print('data: [DONE]')
