#!/usr/bin/env python3
"""Summarize qualified diagnostic intervals without calling idle gaps stutter."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("evidence", type=Path)
args = parser.parse_args()
report = []
for lane in sorted(args.evidence.glob("[0-9][0-9]-*")):
    if not (lane / "result.json").exists():
        report.append({"lane": lane.name, "status": "No QML result; inspect raw/external receipt"})
        continue
    data = json.loads((lane / "result.json").read_text())
    cases = list(data["results"])
    if data.get("current") and (not cases or data["current"] != cases[-1]):
        cases.append(data["current"])
    summary = {"lane": lane.name, "error": data["error"], "completed": data["completed"], "cases": []}
    for case in cases:
        beats = case.get("heartbeats", [])
        active = []
        endpoints = []
        for before, after in zip(case["swaps"], case["swaps"][1:]):
            if before["phase"] != after["phase"]:
                continue
            gap = {"from_ms": before["ms"], "to_ms": after["ms"], "dt": after["ms"]-before["ms"],
                   "phase": after["phase"], "before_p": before["p"], "after_p": after["p"]}
            if any(0 < entry["p"] < 1 for entry in (before, after)):
                active.append(gap)
            else:
                endpoints.append(gap)
        captures = []
        for capture in case["captures"]:
            requested = capture["request"]["ms"]
            delivered = capture["ms"]
            during = [beat for beat in beats if requested <= beat["ms"] <= delivered]
            captures.append({"requested_ms": requested, "delivered_ms": delivered,
                "latency_ms": delivered-requested, "kind": capture.get("kind", "grabToImage"),
                "heartbeat_count": len(during), "heartbeat_max_gap_ms": max((b["dt"] for b in during), default=None),
                "request_phase": capture["request"]["phase"], "delivery_phase": capture["phase"]})
        summary["cases"].append({"case": case["case"], "heartbeat_max_gap_ms": max((b["dt"] for b in beats), default=None),
            "active_progress_intervals": sorted(active, key=lambda g:g["dt"], reverse=True)[:10],
            "endpoint_only_intervals_not_motion_misses": sorted(endpoints, key=lambda g:g["dt"], reverse=True)[:5],
            "slowest_callbacks_or_control_acks": sorted(captures, key=lambda c:c["latency_ms"], reverse=True)[:10]})
    report.append(summary)
output = args.evidence / "qualified-summary.json"
output.write_text(json.dumps({"scope":"Diagnostic only. Instrumentation and compositor scheduling remain confounders; no owner/FPS acceptance.","lanes":report}, indent=2) + "\n")
print(output)
