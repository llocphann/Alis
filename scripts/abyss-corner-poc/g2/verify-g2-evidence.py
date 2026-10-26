#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import math
import re
import sys
from pathlib import Path

EDGES = ("top", "bottom", "left", "right")
SOURCES = (0.02, 0.50, 0.98)
PROGRESSES = (1.00, 0.55)
FIELDS = ("edge", "source_t", "progress", "png", "detail_png", "metadata_json", "log")


def fail(message: str) -> None:
    raise SystemExit(f"G2 evidence verification failed: {message}")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"cannot parse {path}: {exc}")


def artifact(evidence: Path, raw: str) -> Path:
    path = Path(raw)
    return path if path.is_absolute() else evidence / path.name


def close(actual: object, expected: float, label: str, eps: float = 0.02) -> None:
    try:
        value = float(actual)
    except (TypeError, ValueError):
        fail(f"{label} is not numeric: {actual!r}")
    if not math.isclose(value, expected, rel_tol=0.0, abs_tol=eps):
        fail(f"{label}={value} expected {expected}")


def expected_join(source: float) -> tuple[list[str], bool, bool]:
    if math.isclose(source, 0.02, abs_tol=0.001):
        return ["owner", "frame-start"], True, False
    if math.isclose(source, 0.98, abs_tol=0.001):
        return ["owner", "frame-end"], False, True
    return ["owner"], False, False


def parse_run(path: Path) -> dict[str, str]:
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            result[k] = v
    return result


def rect(data: dict, prefix: str) -> tuple[float, float, float, float]:
    return tuple(float(data[f"{prefix}{suffix}"])
                 for suffix in ("X", "Y", "Width", "Height"))


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: verify-g2-evidence.py <evidence-directory>")
    evidence = Path(sys.argv[1]).expanduser().resolve()
    if not evidence.is_dir():
        fail(f"not a directory: {evidence}")

    run_path = evidence / "g2-run.txt"
    session_path = evidence / "session.json"
    manifest_path = evidence / "manifest.tsv"
    for path in (run_path, session_path, manifest_path):
        if not path.is_file():
            fail(f"missing {path.name}")

    run = parse_run(run_path)
    for key in ("repo_head", "g2_tree_sha", "shader_blob_sha", "qsb_blob_sha", "contract_blob_sha"):
        if not re.fullmatch(r"[0-9a-f]{40}", run.get(key, "")):
            fail(f"g2-run.txt: invalid {key}")
    if run.get("progresses") != "1.00,0.55":
        fail("g2-run.txt: progress pair mismatch")
    if run.get("source_scope_clean") != "true" or run.get("evidence_dir_was_empty") != "true":
        fail("g2-run.txt: provenance flags are not true")

    session = load_json(session_path)
    if session.get("composition") != "top-owner/overlay-popup":
        fail("session.json: wrong composition contract")
    if session.get("detailCropCoordinates") != "compositor-layout-logical":
        fail("session.json: wrong crop coordinate space")
    if session.get("devicePixelRatioAppliedToCrop") is not False:
        fail("session.json: DPR must not be applied to grim -g geometry")
    requested_output = str(run.get("requested_output", ""))
    if str(session.get("requestedOutput") or "") != requested_output:
        fail("session.json: requested output mismatch")

    with manifest_path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if tuple(reader.fieldnames or ()) != FIELDS:
            fail(f"manifest.tsv: unexpected header {reader.fieldnames!r}")
        rows = list(reader)
    if len(rows) != 24:
        fail(f"manifest.tsv: expected 24 rows, got {len(rows)}")

    expected = {(e, s, p) for e in EDGES for s in SOURCES for p in PROGRESSES}
    seen = set()
    outputs = set()

    for row in rows:
        edge = row["edge"]
        if edge not in EDGES:
            fail(f"unknown edge {edge!r}")
        try:
            source = float(row["source_t"])
            progress = float(row["progress"])
        except ValueError:
            fail(f"invalid numeric case {row!r}")

        source_key = min(SOURCES, key=lambda v: abs(v - source))
        progress_key = min(PROGRESSES, key=lambda v: abs(v - progress))
        key = (edge, source_key, progress_key)
        if not math.isclose(source, source_key, abs_tol=0.001) \
                or not math.isclose(progress, progress_key, abs_tol=0.001):
            fail(f"unexpected case {edge}/{source}/{progress}")
        if key in seen:
            fail(f"duplicate case {key}")
        seen.add(key)

        for field in ("png", "detail_png", "metadata_json", "log"):
            path = artifact(evidence, row[field])
            if not path.is_file():
                fail(f"missing {field} for {key}: {path}")

        data = load_json(artifact(evidence, row["metadata_json"]))
        if data.get("edge") != edge:
            fail(f"{key}: metadata edge mismatch")
        close(data.get("sourceT"), source, f"{key}: sourceT")
        close(data.get("progress"), progress, f"{key}: progress")
        if data.get("ownerLayer") != "top" or data.get("popupLayer") != "overlay":
            fail(f"{key}: layer split mismatch")
        if data.get("inputPolicy") != "visible-body-only":
            fail(f"{key}: input policy mismatch")
        if data.get("keyboardFocus") != "none":
            fail(f"{key}: keyboard focus was captured")
        if data.get("shaderCompiled") is not True:
            fail(f"{key}: Abyss shader was not compiled: {data.get('shaderLog')!r}")
        if data.get("shaderLog") not in ("", None):
            fail(f"{key}: Abyss shader log is not empty: {data.get('shaderLog')!r}")
        if data.get("geometryStable") is not True:
            fail(f"{key}: geometry not stable")
        if int(data.get("readinessStableTicks", 0)) < 3:
            fail(f"{key}: insufficient readiness stability")
        if data.get("paintRespectsOwnerSeam") is not True:
            fail(f"{key}: Overlay paint crosses primary owner seam")
        if data.get("paintRespectsTangentOwners") is not True:
            fail(f"{key}: Overlay paint crosses tangent Screen Edge owner")
        if data.get("shadowIsolation") != "texture-source-rect":
            fail(f"{key}: shadow is not texture-isolated")
        if data.get("shadowRespectsOwnerSeam") is not True:
            fail(f"{key}: shadow texture crosses primary owner seam")
        if data.get("shadowRespectsTangentOwners") is not True:
            fail(f"{key}: shadow texture crosses tangent Screen Edge owner")

        joins, at_start, at_end = expected_join(source)
        if data.get("joins") != joins:
            fail(f"{key}: joins={data.get('joins')!r}, expected {joins!r}")
        if data.get("atTangentStart") is not at_start or data.get("atTangentEnd") is not at_end:
            fail(f"{key}: tangent flags mismatch")

        W = float(data["outputWidth"])
        H = float(data["outputHeight"])
        seam = float(data["attachmentBoundary"])
        paint = rect(data, "paint")
        inp = rect(data, "input")
        shadow_rect = rect(data, "shadow")
        px, py, pw, ph = rect(data, "popup")
        area_ratio = (paint[2] * paint[3]) / max(1.0, W * H)
        if area_ratio >= 0.30:
            fail(f"{key}: paint viewport is not local ({area_ratio:.3f} of output)")

        eps = 0.02
        if edge == "top":
            if paint[1] < seam - eps or inp[1] < seam - eps \
                    or shadow_rect[1] < seam - eps:
                fail(f"{key}: top owner interior is paint/input/shadow reachable")
        elif edge == "bottom":
            if paint[1] + paint[3] > seam + eps \
                    or inp[1] + inp[3] > seam + eps \
                    or shadow_rect[1] + shadow_rect[3] > seam + eps:
                fail(f"{key}: bottom owner interior is paint/input/shadow reachable")
        elif edge == "left":
            if paint[0] < seam - eps or inp[0] < seam - eps \
                    or shadow_rect[0] < seam - eps:
                fail(f"{key}: left owner interior is paint/input/shadow reachable")
        else:
            if paint[0] + paint[2] > seam + eps \
                    or inp[0] + inp[2] > seam + eps \
                    or shadow_rect[0] + shadow_rect[2] > seam + eps:
                fail(f"{key}: right owner interior is paint/input/shadow reachable")

        frame = float(data["frameThickness"])
        if at_start:
            if edge in ("top", "bottom"):
                if paint[0] < frame - eps or inp[0] < frame - eps \
                        or shadow_rect[0] < frame - eps:
                    fail(f"{key}: start Screen Edge strip is paint/input/shadow reachable")
            else:
                if paint[1] < frame - eps or inp[1] < frame - eps \
                        or shadow_rect[1] < frame - eps:
                    fail(f"{key}: start Screen Edge strip is paint/input/shadow reachable")
        if at_end:
            if edge in ("top", "bottom"):
                if paint[0] + paint[2] > W - frame + eps \
                        or inp[0] + inp[2] > W - frame + eps \
                        or shadow_rect[0] + shadow_rect[2] > W - frame + eps:
                    fail(f"{key}: end Screen Edge strip is paint/input/shadow reachable")
            else:
                if paint[1] + paint[3] > H - frame + eps \
                        or inp[1] + inp[3] > H - frame + eps \
                        or shadow_rect[1] + shadow_rect[3] > H - frame + eps:
                    fail(f"{key}: end Screen Edge strip is paint/input/shadow reachable")

        resting_x = float(data["restingPopupX"])
        resting_y = float(data["restingPopupY"])
        cross = ph if edge in ("top", "bottom") else pw
        expected_offset = (1.0 - progress) * cross
        close(data.get("animationOffset"), expected_offset, f"{key}: animationOffset")
        if edge == "top":
            close(py, resting_y - expected_offset, f"{key}: top slide")
        elif edge == "bottom":
            close(py, resting_y + expected_offset, f"{key}: bottom slide")
        elif edge == "left":
            close(px, resting_x - expected_offset, f"{key}: left slide")
        else:
            close(px, resting_x + expected_offset, f"{key}: right slide")

        shadow = {name: bool(data[f"shadow{name.title()}"])
                  for name in ("top", "bottom", "left", "right")}
        if shadow[edge]:
            fail(f"{key}: attached-side shadow is enabled")
        if at_start:
            tangent_side = "left" if edge in ("top", "bottom") else "top"
            if shadow[tangent_side]:
                fail(f"{key}: start tangent-edge shadow is enabled")
        if at_end:
            tangent_side = "right" if edge in ("top", "bottom") else "bottom"
            if shadow[tangent_side]:
                fail(f"{key}: end tangent-edge shadow is enabled")

        output = str(data.get("output") or "")
        if not output:
            fail(f"{key}: empty output")
        outputs.add(output)

    if seen != expected:
        fail(f"missing cases: {sorted(expected - seen)}")
    if len(outputs) != 1:
        fail(f"cases span outputs: {sorted(outputs)}")
    if requested_output and outputs != {requested_output}:
        fail(f"rendered output {outputs} != requested {requested_output!r}")

    print(f"G2 evidence structure: PASS ({next(iter(outputs))})")
    for progress in ("1p00", "0p55"):
        sheet = evidence / f"detail-sheet-progress-{progress}.png"
        if not sheet.is_file():
            print(f"warning: {sheet.name} absent; inspect individual detail captures",
                  file=sys.stderr)
    print("Visual split-composition is NOT auto-approved; inspect both detail sheets.")


if __name__ == "__main__":
    main()
