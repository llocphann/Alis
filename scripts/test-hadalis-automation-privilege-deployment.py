#!/usr/bin/env python3
"""No elevation or live shell mutation: test broker receipts and rollback files."""
import json
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from automation.worker import privilege as p, deployment as d
from automation.manager.store import _write, state_dir


def main():
    with tempfile.TemporaryDirectory() as tmp,patch.dict(os.environ,{"XDG_CONFIG_HOME":tmp+"/config","XDG_STATE_HOME":tmp+"/state"}):
        request={"key":"JOB-admin:0","spec":{"operation":"system-service-restart","unit":"test.service","reason":"Recover the observed service failure"}}
        assert p.handle(request)["status"]=="denied"
        policy=Path(tmp)/"config/hadalis/automation-privilege.json"
        _write(policy,{"units":["test.service"],"authentication":"sudo-cache"})
        request["key"]="JOB-admin:1"
        calls=[]
        def execute(argv,**kw):
            calls.append(argv)
            assert argv==["/usr/bin/sudo","-n","--","/usr/bin/timeout","--signal=TERM","--kill-after=2s","20s","/usr/bin/systemctl","restart","test.service","--no-block"]
            assert "password" not in json.dumps(kw,default=str)
            return {"stdout":"","stderr":"","exit_code":0,"timed_out":False,"cancelled":False}
        assert p.handle(request,execute)["status"]=="passed"
        assert p.handle(request,execute)["status"]=="passed" and len(calls)==1
        # Intent without completion is ambiguous; cache retry must not elevate twice.
        import hashlib
        key=hashlib.sha256(request["key"].encode()).hexdigest();path=state_dir()/"privilege"/(key+".json")
        saved=json.loads(path.read_text());saved.pop("result");saved["phase"]="executing";_write(path,saved)
        assert p.handle(request,execute)["status"]=="indeterminate" and len(calls)==1
        for spec in ({"operation":"exec","argv":["rm","/"]}, {**request["spec"],"password":"no"}):
            try:p.validate(spec)
            except ValueError:pass
            else:raise AssertionError("privilege escaped allowlist")
        # Crash after applying a QML file: old source survives in a durable backup.
        target=d.target_for("inir");target.mkdir(parents=True)
        dest=target/"shell.qml";dest.write_text("new broken shell")
        root=state_dir()/"deployments/JOB-rollback-0";backup=root/"backup/shell.qml";backup.parent.mkdir(parents=True);backup.write_text("known good shell")
        receipt={"phase":"watching","runner":None,"family":"inir","target":str(target),
                 "files":[{"name":"shell.qml","applied_sha256":d.digest(dest),"original_sha256":d.digest(backup)}]}
        _write(root/"receipt.json",receipt)
        with patch.object(d,"shell_identity",return_value=None),patch.object(d,"bounded_run",return_value={"exit_code":0}) as run:
            d.recover()
            assert dest.read_text()=="known good shell" and run.call_count==1
            assert json.loads((root/"receipt.json").read_text())["phase"]=="rolled_back"
            d.recover();assert run.call_count==1
        # Preserve a concurrent user deployment rather than clobbering it.
        dest.write_text("concurrent valid shell");receipt["phase"]="applying";_write(root/"receipt.json",receipt)
        with patch.object(d,"shell_identity",return_value={}):d.recover()
        assert dest.read_text()=="concurrent valid shell"
        assert json.loads((root/"receipt.json").read_text())["phase"]=="conflict"
        # Failed validation cannot touch the deployed files.
        source=Path(tmp)/"source";source.mkdir();(source/"shell.qml").write_text("invalid replacement")
        with patch.object(d,"shell_identity",return_value={"pid":1}),patch.object(d,"bounded_run",return_value={"exit_code":1}):
            result=d.deploy({"family":"inir","files":["shell.qml"],"reason":"Validate the proposed shell change"},source,"JOB-red-0")
        assert result["status"]=="failed" and dest.read_text()=="concurrent valid shell"
        for files in (["../shell.qml"],["automation/worker.py"],["/etc/sudoers"]):
            try:d.validate({"family":"inir","files":files,"reason":"Unsafe path should be rejected"})
            except ValueError:pass
            else:raise AssertionError("unsafe deployment admitted")
    print("PASS: administrator allowlist/audit, no credential protocol, durable privilege deduplication, validation refusal and crash/concurrent rollback")


if __name__=="__main__":main()
