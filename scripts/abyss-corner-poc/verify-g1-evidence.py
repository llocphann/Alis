#!/usr/bin/env python3
"""Structural verifier for a paired Abyss G1 live-evidence directory.

This script validates provenance, case completeness and geometry metadata only.
It does not make the visual morphology acceptance decision.
"""
from __future__ import annotations

import csv
import json
import math
import re
import sys
from pathlib import Path

PROFILES = {
    "diagnostic": {"radius": 48.0, "fuse": 56.0, "weld": 4.0},
    "upstream-relative": {"radius": 30.0, "fuse": 30.0, "weld": 3.0},
}
EDGES = ("top", "bottom", "left", "right")
SOURCES = (0.02, 0.50, 0.98)
MANIFEST_FIELDS = (
    "edge", "source_t", "mode", "profile",
    "png", "detail_png", "metadata_json", "log",
)


def fail(message: str) -> None:
    raise SystemExit(f"G1 evidence verification failed: {message}")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"cannot parse {path}: {exc}")


def artifact_path(evidence_dir: Path, raw: str) -> Path:
    path = Path(raw)
    if path.is_absolute():
        return path
    # All matrix artifacts live directly in the evidence directory. Resolving
    # relative entries by basename also makes later offline review independent
    # of the shell working directory used during capture.
    return evidence_dir / path.name


def close_enough(actual: object, expected: float, label: str) -> None:
    try:
        value = float(actual)
    except (TypeError, ValueError):
        fail(f"{label} is not numeric: {actual!r}")
    if not math.isclose(value, expected, rel_tol=0.0, abs_tol=0.011):
        fail(f"{label}={value} expected {expected}")


def parse_run(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def expected_join(source_t: float) -> tuple[list[str], bool, bool]:
    if math.isclose(source_t, 0.02, abs_tol=0.001):
        return ["owner", "frame-start"], True, False
    if math.isclose(source_t, 0.98, abs_tol=0.001):
        return ["owner", "frame-end"], False, True
    return ["owner"], False, False


def verify_profile(evidence_dir: Path, profile: str, requested_output: str) -> set[str]:
    manifest = evidence_dir / f"manifest-card-owner-{profile}.tsv"
    session = evidence_dir / f"session-card-owner-{profile}.json"
    if not manifest.is_file():
        fail(f"missing {manifest.name}")
    if not session.is_file():
        fail(f"missing {session.name}")

    session_data = load_json(session)
    if session_data.get("mode") != "card-owner":
        fail(f"{session.name}: mode is not card-owner")
    if session_data.get("profile") != profile:
        fail(f"{session.name}: profile mismatch")
    if session_data.get("detailCropCoordinates") != "compositor-layout-logical":
        fail(f"{session.name}: unexpected detail crop coordinate space")
    if session_data.get("devicePixelRatioAppliedToCrop") is not False:
        fail(f"{session.name}: DPR must not be applied to grim -g geometry")
    if str(session_data.get("requestedOutput") or "") != requested_output:
        fail(f"{session.name}: requested output does not match g1-run.txt")

    with manifest.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != MANIFEST_FIELDS:
            fail(f"{manifest.name}: unexpected header {reader.fieldnames!r}")
        rows = list(reader)

    if len(rows) != len(EDGES) * len(SOURCES):
        fail(f"{manifest.name}: expected 12 rows, got {len(rows)}")

    expected_keys = {(edge, source) for edge in EDGES for source in SOURCES}
    seen_keys: set[tuple[str, float]] = set()
    outputs: set[str] = set()
    expected_profile = PROFILES[profile]

    for row in rows:
        edge = row["edge"]
        if edge not in EDGES:
            fail(f"{manifest.name}: unknown edge {edge!r}")
        try:
            source_t = float(row["source_t"])
        except ValueError:
            fail(f"{manifest.name}: invalid source_t {row['source_t']!r}")
        key = min(expected_keys, key=lambda item: abs(item[1] - source_t)
                  if item[0] == edge else 999.0)
        if key[0] != edge or not math.isclose(key[1], source_t, abs_tol=0.001):
            fail(f"{manifest.name}: unexpected case {edge}/{source_t}")
        if key in seen_keys:
            fail(f"{manifest.name}: duplicate case {edge}/{source_t}")
        seen_keys.add(key)

        if row["mode"] != "card-owner" or row["profile"] != profile:
            fail(f"{manifest.name}: mislabeled case {edge}/{source_t}")

        for field in ("png", "detail_png", "metadata_json", "log"):
            path = artifact_path(evidence_dir, row[field])
            if not path.is_file():
                fail(f"{manifest.name}: missing {field} for {edge}/{source_t}: {path}")

        metadata_path = artifact_path(evidence_dir, row["metadata_json"])
        metadata = load_json(metadata_path)
        if metadata.get("mode") != "card-owner":
            fail(f"{metadata_path.name}: mode mismatch")
        if metadata.get("profile") != profile:
            fail(f"{metadata_path.name}: profile mismatch")
        if metadata.get("edge") != edge:
            fail(f"{metadata_path.name}: edge mismatch")
        if metadata.get("geometryStable") is not True:
            fail(f"{metadata_path.name}: readiness geometry was not stable")
        try:
            stable_ticks = int(metadata.get("readinessStableTicks"))
        except (TypeError, ValueError):
            fail(f"{metadata_path.name}: readinessStableTicks is not an integer")
        if stable_ticks < 3:
            fail(f"{metadata_path.name}: readinessStableTicks={stable_ticks} expected >= 3")
        close_enough(metadata.get("outputWidth"), metadata.get("screenWidth"),
                     f"{metadata_path.name}: outputWidth/screenWidth")
        close_enough(metadata.get("outputHeight"), metadata.get("screenHeight"),
                     f"{metadata_path.name}: outputHeight/screenHeight")
        close_enough(metadata.get("sourceT"), source_t, f"{metadata_path.name}: sourceT")
        close_enough(metadata.get("radius"), expected_profile["radius"], f"{metadata_path.name}: radius")
        close_enough(metadata.get("fuse"), expected_profile["fuse"], f"{metadata_path.name}: fuse")
        close_enough(metadata.get("weld"), expected_profile["weld"], f"{metadata_path.name}: weld")

        joins, at_start, at_end = expected_join(source_t)
        if metadata.get("joins") != joins:
            fail(f"{metadata_path.name}: joins={metadata.get('joins')!r} expected {joins!r}")
        if metadata.get("atTangentStart") is not at_start:
            fail(f"{metadata_path.name}: atTangentStart mismatch")
        if metadata.get("atTangentEnd") is not at_end:
            fail(f"{metadata_path.name}: atTangentEnd mismatch")

        output = str(metadata.get("output") or "")
        if not output:
            fail(f"{metadata_path.name}: output is empty")
        outputs.add(output)

    if seen_keys != expected_keys:
        missing = sorted(expected_keys - seen_keys)
        fail(f"{manifest.name}: missing cases {missing}")
    if len(outputs) != 1:
        fail(f"{manifest.name}: cases span multiple outputs {sorted(outputs)}")
    if requested_output and outputs != {requested_output}:
        fail(f"{manifest.name}: rendered output does not match requested output {requested_output!r}")
    return outputs


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: verify-g1-evidence.py <evidence-directory>")
    evidence_dir = Path(sys.argv[1]).expanduser().resolve()
    if not evidence_dir.is_dir():
        fail(f"not a directory: {evidence_dir}")

    run_path = evidence_dir / "g1-run.txt"
    if not run_path.is_file():
        fail("missing g1-run.txt")
    run = parse_run(run_path)
    if run.get("mode") != "card-owner":
        fail("g1-run.txt: mode is not card-owner")
    if run.get("profiles") != "diagnostic,upstream-relative":
        fail("g1-run.txt: profile pair mismatch")
    for key in (
        "repo_head",
        "poc_tree_sha",
        "contract_blob_sha",
        "runtime_exclusions_blob_sha",
    ):
        if not re.fullmatch(r"[0-9a-f]{40}", run.get(key, "")):
            fail(f"g1-run.txt: {key} is not a full Git SHA")
    if run.get("source_scope_clean") != "true":
        fail("g1-run.txt: source scope was not clean")
    if run.get("evidence_dir_was_empty") != "true":
        fail("g1-run.txt: evidence directory was not fresh")

    requested_output = run.get("requested_output", "")
    outputs = set()
    for profile in PROFILES:
        outputs.update(verify_profile(evidence_dir, profile, requested_output))
    if len(outputs) != 1:
        fail(f"paired profiles target different outputs: {sorted(outputs)}")

    print(f"G1 evidence structure: PASS ({next(iter(outputs))})")
    for profile in PROFILES:
        sheet = evidence_dir / f"detail-sheet-card-owner-{profile}.png"
        if not sheet.is_file():
            print(
                f"warning: {sheet.name} is absent; review the 12 individual "
                f"*-{profile}-detail.png captures instead",
                file=sys.stderr,
            )
    print("Visual morphology is NOT auto-approved; inspect the live detail captures.")


if __name__ == "__main__":
    main()
