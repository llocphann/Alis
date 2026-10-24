#!/usr/bin/env python3
"""Local metadata and prompt admission; only an owned protocol fixture."""
import copy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/ai'))
import local_provider as local

row={'id':'fixture','type':'vlm','compatibility_type':'gguf','arch':'qwen35',
     'quantization':'Q5_K_XL','state':'loaded','max_context_length':4096}
ollama={'details':{'format':'gguf','quantization_level':'Q4_K_M'},
        'model_info':{'general.architecture':'fixture'}}
for endpoint in ('https://example.test/v1','http://127.0.0.1.evil/v1','http://localhost@evil/v1',
                 'http://127.00.0.1/v1','file:///etc/passwd','http://127.0.0.1:0/v1','http://@127.0.0.1/v1'):
    try:local.origin(endpoint)
    except local.LocalProviderError:pass
    else:raise AssertionError('unverified origin accepted')
for patch in ({'type':'cloud'},{'compatibility_type':'proxy'},{'remote_host':'example.test'},
              {'is_remote':True},{'remote_model':False},{'arch':None},{'quantization':None},
              {'max_context_length':True},{'state':'unknown'}):
    try:local.lmstudio_metadata({'data':[{**row,**patch}]},'fixture')
    except local.LocalProviderError:pass
    else:raise AssertionError('remote/malformed metadata accepted')
for patch in ({'remote_model':'cloud'},{'remote_host':'remote.test'},{'details':None},{'model_info':{}}):
    try:local.ollama_metadata({**ollama,**patch},'fixture')
    except local.LocalProviderError:pass
    else:raise AssertionError('Ollama relay accepted')
assert len(local.fingerprint(local.lmstudio_metadata({'data':[row]},'fixture')))==64
assert local.ollama_metadata(ollama,'fixture')['provider']=='ollama'

state={'row':copy.deepcopy(row),'show':copy.deepcopy(ollama),'requests':[],'mode':'ok'}
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def send_json(self,value):
        raw=json.dumps(value).encode();self.send_response(200);self.end_headers();self.wfile.write(raw)
    def do_GET(self):
        if state['mode']=='redirect':
            self.send_response(302);self.send_header('Location','http://127.0.0.1:1/never');self.end_headers();return
        if self.path=='/api/v0/models':return self.send_json({'data':[state['row']]})
        if self.path=='/v1/models':return self.send_json({'data':[{'id':'fixture'}]})
        self.send_error(404)
    def do_POST(self):
        data=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path=='/api/show':return self.send_json(state['show'])
        state['requests'].append((data,dict(self.headers)))
        if state['mode']=='rate-limited':
            self.send_response(429);self.end_headers();self.wfile.write(b'private provider prose');return
        self.send_response(200);self.end_headers()
        self.wfile.write(b'data: {"choices":[{"delta":{"content":"fixture reply"}}]}\n\ndata: [DONE]\n\n')

server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
base='http://127.0.0.1:'+str(server.server_port)
body={'model':'fixture','stream':True,'messages':[{'role':'user','content':'fixture private prompt'}]}
try:
    expected=local.verify('lmstudio',base+'/v1/chat/completions','fixture')['fingerprint']
    env=dict(os.environ,AI_ENDPOINT=base+'/v1/chat/completions',AI_LOCAL_MODEL='fixture',
             AI_LOCAL_PROVIDER='lmstudio',AI_LOCAL_FINGERPRINT=expected,AI_LOCAL_KEY='fixture-key',
             HTTP_PROXY='http://127.0.0.1:1',http_proxy='http://127.0.0.1:1',NO_PROXY='',no_proxy='')
    def call(payload=body,environment=env):
        return subprocess.run([sys.executable,str(ROOT/'scripts/ai/local-provider-session.py')],
            input=json.dumps(payload)+'\n',env=environment,capture_output=True,text=True,timeout=8)
    accepted=call()
    assert accepted.returncode==0 and '__ALIS_HTTP_STATUS__:200' in accepted.stdout
    assert state['requests'][0][0]==body and state['requests'][0][1]['Authorization']=='Bearer fixture-key'
    assert 'fixture-key' not in accepted.stdout+accepted.stderr
    for patch in ({'remote_host':'cloud.test'},{'quantization':'Q8_0'},{'type':'cloud'},{'max_context_length':None}):
        state['row']={**row,**patch};rejected=call()
        assert rejected.returncode==1 and len(state['requests'])==1
        assert 'fixture private prompt' not in rejected.stdout+rejected.stderr
        assert 'fixture-key' not in rejected.stdout+rejected.stderr
    state['row']=copy.deepcopy(row)
    assert call({**body,'model':'cloud-alias'}).returncode==1 and len(state['requests'])==1
    state['mode']='redirect'
    assert call().returncode==1 and len(state['requests'])==1
    state['mode']='ok'
    result=subprocess.run([sys.executable,str(ROOT/'scripts/ai/discover-provider-models.py'),
        '--provider-id','lmstudio','--kind','openai-compatible','--models-url',base+'/v1/models',
        '--chat-endpoint',base+'/v1/chat/completions','--local'],capture_output=True,text=True,timeout=8)
    item=json.loads(result.stdout)['models'][0]
    assert item['local'] and item['localVerified'] and item['localFingerprint']==expected
    state['row']={**row,'type':'cloud'}
    result=subprocess.run(result.args,capture_output=True,text=True,timeout=8)
    item=json.loads(result.stdout)['models'][0]
    assert not item['local'] and not item['localVerified'] and not item['localFingerprint']
    assert len(state['requests'])==1,'catalog verification generated text'
    state['row']=copy.deepcopy(row);state['mode']='rate-limited'
    limited=call()
    assert limited.returncode==1 and '__ALIS_HTTP_STATUS__:429' in limited.stdout
    assert 'private provider prose' not in limited.stdout+limited.stderr
finally:
    server.shutdown();server.server_close()
print('AI_LOCAL_PROVIDER_PASS positiveWeights unknownRelayDeny freshBeforePrompt staleFingerprint modelOverride redirect proxy credentialPrivacy catalog noInference')
