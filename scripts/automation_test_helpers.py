"""Deterministic transport fixtures; never access real profiles/Desktop."""
from contextlib import contextmanager
import os
from pathlib import Path
import sys
import tempfile
import threading
import uuid
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.manager import control, daemon, model, store


@contextmanager
def environment():
    with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {
            "XDG_CONFIG_HOME":tmp+"/config", "XDG_STATE_HOME":tmp+"/state"}):
        store.change(lambda c,s: c["profiles"][0].update(enabled=False))
        with patch.object(control, "_ensure_runtime_services"), patch.object(control, "_await_dispatch"), \
             patch.object(control.time, "time", return_value=100):
            yield


def profile(name="Workflow"):
    pid=control.create_profile(name)["profile_id"]
    control.set_profile(pid,"enabled","true")
    control.set_profile(pid,"requires_github","false")
    control.set_profile(pid,"prompt",'"Observe, diagnose, test and recover"')
    control.profile_action("start",pid)
    return pid


class Transport:
    def __init__(self):
        self.calls=[]; self.messages={}; self.replies={}; self.down=False
        self.uncertain=False; self.barrier=None; self.active=0; self.peak=0; self.lock=threading.Lock()
    def __call__(self, op, **data):
        with self.lock: self.calls.append((op,data))
        if self.down: raise RuntimeError("Desktop unavailable")
        if op=="project": return {"project_id":"project-"+data["name"]}
        if op=="preflight":return {"ready":True}
        if op=="submit":
            with self.lock:
                self.active+=1;self.peak=max(self.peak,self.active)
            if self.barrier: self.barrier.wait(timeout=5)
            chat=data.get("conversation_id") or str(uuid.uuid4())
            self.messages[data["user_message_id"]]=chat
            with self.lock:self.active-=1
            if self.uncertain: raise RuntimeError("lost acknowledgment after send")
            return {"dispatched":True,"conversation_id":chat}
        if op=="poll":
            p=data["pending"]; chat=self.messages.get(p["user_message_id"],p.get("conversation_id"))
            reply=self.replies.get(p["user_message_id"])
            if reply: return {"completed":True,"conversation_id":chat,"response":{
                "message_id":str(uuid.uuid5(uuid.NAMESPACE_URL,p["user_message_id"])),"text":reply}}
            return {"completed":False,"submitted":bool(chat),"conversation_id":chat}
        if op=="cursor":
            for uid, chat in reversed(list(self.messages.items())):
                if chat==data["conversation_id"] and uid in self.replies:
                    return {"current_node":str(uuid.uuid5(uuid.NAMESPACE_URL,uid))}
            raise RuntimeError("no completed response")
        raise AssertionError(op)
    def pending(self,pid):return store.read_snapshot()[1]["profiles"][pid]["pending"]
    def reply(self,pid,text="HADALIS_LOOP:CONTINUE"):
        self.replies[self.pending(pid)["user_message_id"]]=text
    def count(self,op):return sum(c[0]==op for c in self.calls)
