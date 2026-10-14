#!/usr/bin/env python3
"""Secrets remain in keyring/private IPC, scoped to a profile and repository."""
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import uuid
from types import SimpleNamespace
from unittest.mock import patch
from automation_test_helpers import environment, control, store
from automation.manager import credentials


def main():
    canary="fixture-private-token-"+uuid.uuid4().hex
    with environment():
        pid=control.create_profile("Credential test")["profile_id"]
        saved={};calls=[]
        def keyring(argv,**kwargs):
            calls.append((argv,kwargs));profile=argv[argv.index("profile")+1]
            assert canary not in " ".join(argv)
            if argv[1]=="store":saved[profile]=kwargs["input"]
            if argv[1]=="clear":saved.pop(profile,None)
            return SimpleNamespace(returncode=0,stdout=saved.get(profile,"") if argv[1]=="lookup" else "",stderr="")
        with patch.object(credentials.shutil,"which",return_value="/usr/bin/secret-tool"),patch.object(credentials.subprocess,"run",side_effect=keyring):
            assert credentials.save(pid,canary)=={"ok":True,"saved":True}
            assert credentials.has_token(pid)
            assert canary not in json.dumps(credentials.status())
            request="protocol=https\nhost=github.com\npath=llocphann/Hadalis.git\n\n"
            assert credentials.helper(pid,"llocphann/Hadalis","get",request)=="username=x-access-token\npassword="+canary+"\n\n"
            assert not credentials.helper(pid,"llocphann/Hadalis","get",request.replace("github.com","example.com"))
            assert not credentials.helper(pid,"llocphann/Hadalis","get",request.replace("Hadalis","Other"))
            assert not credentials.helper(pid,"llocphann/Hadalis","store",request)
            duplicate=control.create_profile("Copy",pid)["profile_id"]
            assert not credentials.has_token(duplicate)
            argv=["git",*credentials.git_options(pid,"https://github.com/llocphann/Hadalis.git"),"fetch","origin","dev"]
            assert canary not in " ".join(argv) and "credential.helper=" in argv
            assert not credentials.git_options(pid,"https://example.com/llocphann/Hadalis.git")
            for path in store.state_dir().rglob("*.json"):
                assert canary not in path.read_text(),path
            assert stat.S_IMODE((store.state_dir()/"credentials/github.json").stat().st_mode)==0o600
            assert canary not in store.config_path().read_text()
            assert credentials.clear(pid)=={"ok":True,"saved":False}
            assert not credentials.has_token(pid) and pid not in saved
        with patch.object(credentials.shutil,"which",return_value=None):
            try:credentials.save(pid,canary)
            except RuntimeError:pass
            else:raise AssertionError("unavailable keyring must not save plaintext")
        with patch.dict(os.environ,{"GIT_CURL_VERBOSE":"1","GIT_TRACE":"1","GIT_ASKPASS":"echo-secret"}):
            env=credentials.git_env()
            assert "GIT_CURL_VERBOSE" not in env and "GIT_TRACE" not in env and "GIT_ASKPASS" not in env
            assert env["GIT_TERMINAL_PROMPT"]=="0"
        # Exercise Git's real helper protocol without network or real secrets.
        with tempfile.TemporaryDirectory() as tmp:
            executable=Path(tmp)/"secret-tool"
            executable.write_text("#!/usr/bin/env python3\nimport sys\nif sys.argv[1]=='lookup':print("+repr(canary)+")\n")
            executable.chmod(0o700);credentials._mark(pid,True)
            env=credentials.git_env();env["PATH"]=tmp+":"+os.environ["PATH"]
            result=subprocess.run(["git",*credentials.git_options(pid,"https://github.com/llocphann/Hadalis.git"),"credential","fill"],
                input="protocol=https\nhost=github.com\npath=llocphann/Hadalis.git\n\n",capture_output=True,text=True,env=env,timeout=10)
            assert result.returncode==0 and "password="+canary in result.stdout
            assert canary not in result.stderr
        if os.environ.get("HADALIS_TEST_KEYRING_LIVE")=="1":
            # Unique fixture profile, dummy canary, private XDG and cleanup.
            try:
                credentials.save(pid,canary)
                assert canary in credentials.helper(pid,"llocphann/Hadalis","get",request)
                assert canary not in json.dumps(control.status())
            finally:credentials.clear(pid)
            print("PASS: live system keyring save/lookup/clear with a dummy canary")
    print("PASS: keyring-only secret storage, private stdin/helper pipe, repository scope, no config/state/argv leakage or credential duplication")


if __name__=="__main__":main()
