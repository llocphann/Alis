#!/usr/bin/env python3
"""Evidence-driven generic workflow, isolated malformed config and failed turns."""
import json
from unittest.mock import patch
from automation_test_helpers import environment,profile,Transport,daemon,control,store


def main():
    with environment():
        pid=profile();t=Transport()
        with patch.object(daemon,"native_command",side_effect=t):
            daemon.tick(100);t.reply(pid,"HADALIS_LOOP:WAIT_RESULT JOB-evidence");daemon.tick(102)
            evidence={"job":"JOB-evidence","profile_id":pid,"status":"failed","job_commit":"b"*40,
                "actions":[{"kind":"diagnostics","evidence_id":"JOB-evidence:0","source_sha":"b"*40,"observed_at_unix":102,
                            "stdout":"PRIVATE_PASSWORD=do-not-share","safe_observations":[{"check":"journal","exit_code":0,"error_codes":["qml_import"]}]}]}
            with patch.object(daemon,"job_result",return_value=evidence):daemon.tick(104)
            daemon.tick(106)
            prompt=[data["prompt"] for op,data in t.calls if op=="submit"][-1]
            assert "qml_import" in prompt and "JOB-evidence:0" in prompt and "do-not-share" not in prompt
            t.reply(pid,'HADALIS_DIAGNOSIS:{"conclusion":"The import is missing","evidence_ids":["JOB-evidence:0"]}\nHADALIS_CHECKPOINT:{"phase":"fix","next":"validate","evidence_ids":["JOB-evidence:0"]}\nHADALIS_LOOP:CONTINUE')
            daemon.tick(108);assert store.read_snapshot()[1]["profiles"][pid]["checkpoint"]["phase"]=="fix"
            daemon.tick(110)
            t.reply(pid,'HADALIS_DIAGNOSIS:{"conclusion":"Unproven cause","evidence_ids":["invented"]}\nHADALIS_LOOP:CONTINUE')
            daemon.tick(112);item=store.read_snapshot()[1]["profiles"][pid]
            assert item["status"]=="evidence_required" and item["pending"] is None and item["desired"]=="paused"
            count=t.count("submit");daemon.tick(114);assert t.count("submit")==count
    with environment():
        good=profile("Good");bad=profile("Malformed");t=Transport()
        original=store.read_snapshot()[0]
        for p in original["profiles"]:
            if p["id"]==bad:p["mode"]="bad-mode"
        store._write(store.config_path(),original)
        store.change_state(lambda c,s:s["profiles"][bad].update(pending={"prepared_at_unix":80,"response_action_count":3}))
        with patch.object(daemon,"native_command",side_effect=t):daemon.tick(100)
        assert store.read_snapshot()[1]["profiles"][good]["pending"]
        assert store.read_snapshot()[1]["profiles"][bad]["pending"]["response_action_count"]==3
        assert json.loads(store.config_path().read_text())["profiles"][-1]["mode"]=="bad-mode", "quarantine must preserve raw config"
    with environment():
        pid=profile();t=Transport()
        with patch.object(daemon,"native_command",side_effect=t):daemon.tick(100)
        original=t.pending(pid)
        def native(op,**data):
            if op=="poll":return {"completed":False,"submitted":True,"terminal_failed":True,"conversation_id":original["conversation_id"]}
            return t(op,**data)
        with patch.object(daemon,"native_command",side_effect=native):
            daemon.tick(102);item=store.read_snapshot()[1]["profiles"][pid]
            assert item["pending"] is None and item["request"]=="recovery"
            daemon.tick(132)
            assert t.pending(pid)["user_message_id"]!=original["user_message_id"]
            assert t.pending(pid)["conversation_id"]!=original["conversation_id"]
            assert t.count("submit")==2
            assert "new recovery step" in [d["prompt"] for op,d in t.calls if op=="submit"][-1]
    with environment():
        a,b=profile("Superseded"),profile("Independent");t=Transport()
        with patch.object(daemon,"native_command",side_effect=t):daemon.tick(100)
        original=t.pending(a).copy()
        def native(op,**data):
            if op=="poll" and data["pending"]["user_message_id"]==original["user_message_id"]:
                return {"completed":False,"submitted":True,"superseded":True,
                    "successor_user_message_id":"human-turn","conversation_id":original["conversation_id"]}
            return t(op,**data)
        t.reply(b)
        with patch.object(daemon,"native_command",side_effect=native):
            daemon.tick(162);state=store.read_snapshot()[1]
            assert state["profiles"][a]["desired"]=="paused" and state["profiles"][a]["status"]=="session_changed"
            assert state["profiles"][a]["pending"]["user_message_id"]==original["user_message_id"]
            assert state["profiles"][b]["iterations"]==1
            daemon.tick(164);assert t.count("submit")==3 and t.count("resume")==0
            control.profile_action("stop",a);daemon.tick(222)
            assert store.read_snapshot()[1]["profiles"][a]["desired"]=="stopped"
            assert t.count("resume")==0 and t.count("submit")==3
    print("PASS: generic evidence/checkpoints, quarantine, failure recovery and isolated superseded turns without prompt replay or stream reattachment")


if __name__=="__main__":main()
