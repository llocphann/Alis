#!/usr/bin/env python3
"""Owned GGUF inventory and real Unix-socket supervisor lifecycle fixtures."""
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/ai'))
import local_models
import gguf_runtime

FAKE='''#!/usr/bin/python3
import http.server,json,os,socket,socketserver,subprocess,sys,time
from pathlib import Path
record=Path(os.environ['INIR_TEST_GGUF_RECORD'])
record.write_text(json.dumps({'pid':os.getpid(),'argv':sys.argv[1:]}))
if os.environ.get('INIR_TEST_GGUF_CHILD')=='1':
 child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)'])
 record.with_suffix('.child').write_text(str(child.pid))
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  self.send_response(200);self.end_headers();self.wfile.write(b'{"status":"ok"}')
 def do_POST(self):
  payload=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  record.with_suffix('.payload').write_text(json.dumps(payload))
  if os.environ.get('INIR_TEST_GGUF_CRASH')=='1':os._exit(17)
  time.sleep(float(os.environ.get('INIR_TEST_GGUF_DELAY','0')))
  content=json.dumps({'text':'Splish!','expression':'happy'}) if 'response_format' in payload else 'Tiny fixture reply.'
  self.send_response(200);self.end_headers();self.wfile.write(json.dumps({'choices':[{'message':{'content':content},'finish_reason':'stop'}],'usage':{'completion_tokens':8}}).encode())
class Server(socketserver.UnixStreamServer):
 allow_reuse_address=True
server=Server(sys.argv[sys.argv.index('--host')+1],Handler)
server.serve_forever()
'''

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='wg-');self.root=Path(self.temp.name)
        self.model=self.root/'Model-UD-Q6_K_XL.gguf'
        with self.model.open('wb') as f:f.write(struct.pack('<4sIQQ',b'GGUF',3,1,1));f.truncate(21*1024*1024)
        self.server=self.root/'llama-server';self.server.write_text(FAKE);self.server.chmod(0o700)
        self.record=self.root/'record.json'
        self.env=patch.dict(os.environ,{'XDG_RUNTIME_DIR':str(self.root),'INIR_TEST_GGUF_RECORD':str(self.record),'INIR_GGUF_ROOTS':json.dumps([str(self.root)])})
        self.env.start()
    def tearDown(self):self.env.stop();self.temp.cleanup()
    def assertPidStopped(self,pid):
        until=time.monotonic()+3
        while time.monotonic()<until:
            try:os.kill(pid,0)
            except ProcessLookupError:return
            time.sleep(.03)
        with self.assertRaises(ProcessLookupError):os.kill(pid,0)
    def assertStopped(self):
        self.assertPidStopped(json.loads(self.record.read_text())['pid'])
    def test_inventory_deduplicates_and_excludes_projectors(self):
        (self.root/'Duplicate.gguf').symlink_to(self.model)
        (self.root/'mmproj-F16.gguf').symlink_to(self.model)
        (self.root/'ggml-vocab-fixture.gguf').symlink_to(self.model)
        (self.root/'partial.gguf').write_bytes(b'GGUF')
        found=local_models.inventory()['models']
        self.assertEqual(len(found),1);self.assertEqual(found[0]['size'],21*1024*1024)
        self.assertTrue(found[0]['id'].startswith('gguf:'));self.assertTrue(found[0]['projector'])
        self.assertFalse(found[0]['thinking']);self.assertTrue(local_models.thinking_capable('Qwen3.5-4B-UD-Q5_K_XL'))
        self.assertFalse(local_models.valid_file(self.root/'partial.gguf'))
    def test_supervised_request_is_bounded_and_reaped(self):
        result=gguf_runtime.complete(str(self.model),[{'role':'system','content':'x'*5000}]+
            [{'role':'user','content':'hello'}]*9,server_path=str(self.server))
        self.assertEqual(result['text'],'Tiny fixture reply.');self.assertStopped()
        request=json.loads(self.record.with_suffix('.payload').read_text())
        self.assertEqual(request['max_tokens'],180);self.assertEqual(request['thinking_budget_tokens'],0)
        self.assertFalse(request['chat_template_kwargs']['enable_thinking']);self.assertNotIn('reasoning_effort',request)
        self.assertFalse(request['stream']);self.assertEqual(len(request['messages']),7)
        self.assertEqual(len(request['messages'][0]['content']),3500)
        args=json.loads(self.record.read_text())['argv']
        self.assertIn('--no-webui',args);self.assertEqual(args[args.index('-ngl')+1],'0')
        self.assertEqual(args[args.index('--reasoning')+1],'auto')
        self.assertEqual(args[args.index('-c')+1],'2048')
        self.assertFalse(list(gguf_runtime.private_dir().glob('r-*')))
    def test_bounded_high_thinking_budget(self):
        result=gguf_runtime.complete(str(self.model),[{'role':'user','content':'think'}],
            server_path=str(self.server),thinking_effort='high')
        self.assertEqual(result['text'],'Tiny fixture reply.');self.assertStopped()
        request=json.loads(self.record.with_suffix('.payload').read_text())
        self.assertEqual(request['thinking_budget_tokens'],512);self.assertEqual(request['max_tokens'],832)
        self.assertTrue(request['chat_template_kwargs']['enable_thinking']);self.assertNotIn('reasoning_effort',request)
        with self.assertRaises(gguf_runtime.RuntimeErrorLocal):
            gguf_runtime.complete(str(self.model),[{'role':'user','content':'x'}],
                server_path=str(self.server),thinking_effort='extreme')

    def test_helper_cancel_reaps_model_and_releases_lease(self):
        env=dict(os.environ,INIR_TEST_GGUF_DELAY='10')
        helper=subprocess.Popen([sys.executable,str(ROOT/'scripts/ai/gguf_runtime.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,env=env)
        try:
            helper.stdin.write(json.dumps({'modelPath':str(self.model),'runtimePath':str(self.server),'messages':[{'role':'user','content':'hello'}]})+'\n');helper.stdin.flush()
            until=time.monotonic()+5
            while not self.record.with_suffix('.payload').exists() and time.monotonic()<until:time.sleep(.03)
            self.assertTrue(self.record.with_suffix('.payload').exists())
            helper.send_signal(signal.SIGTERM);helper.communicate(timeout=6);self.assertStopped()
            self.assertFalse(list(gguf_runtime.private_dir().glob('r-*')))
            result=gguf_runtime.complete(str(self.model),[{'role':'user','content':'new'}],server_path=str(self.server))
            self.assertTrue(result['text']);self.assertStopped()
        finally:
            if helper.poll() is None:helper.kill();helper.wait(timeout=3)
    def test_crashed_server_leader_reaps_surviving_process_group(self):
        with patch.dict(os.environ,{'INIR_TEST_GGUF_CHILD':'1','INIR_TEST_GGUF_CRASH':'1'}):
            with self.assertRaises(gguf_runtime.RuntimeErrorLocal):
                gguf_runtime.complete(str(self.model),[{'role':'user','content':'crash'}],server_path=str(self.server))
        child=int(self.record.with_suffix('.child').read_text())
        self.assertStopped();self.assertPidStopped(child)
        self.assertFalse(list(gguf_runtime.private_dir().glob('r-*')))
        result=gguf_runtime.complete(str(self.model),[{'role':'user','content':'recovered'}],server_path=str(self.server))
        self.assertEqual(result['text'],'Tiny fixture reply.');self.assertStopped()

    def test_invalid_model_and_nontext_do_not_spawn(self):
        with self.assertRaises(gguf_runtime.RuntimeErrorLocal):gguf_runtime.complete(str(self.root/'missing'),[],server_path=str(self.server))
        with self.assertRaises(gguf_runtime.RuntimeErrorLocal):gguf_runtime.complete(str(self.model),[{'role':'user','content':[{'type':'image_url'}]}],server_path=str(self.server))
        self.assertFalse(self.record.exists())

if __name__=='__main__':unittest.main()
