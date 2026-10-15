#!/usr/bin/env python3
"""Bounded, read-only PipeWire transition trace. Never records audio or raw tool output."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time

MAX_BYTES = 4 * 1024 * 1024
MAX_INPUT = 2 * 1024 * 1024
MARKERS = {"new-online-clip", "heard-crackle", "ui-open", "ui-close"}
CLASSES = {
    "browser": {"firefox", "chrome", "chromium", "google-chrome", "brave", "zen", "vivaldi", "opera", "librewolf"},
    "local": {"mpd"},
    "cava": {"cava"},
    "dsp": {"easyeffects"},
}
MEDIA = {"Audio/Sink", "Audio/Source", "Stream/Output/Audio", "Stream/Input/Audio", "Audio/Duplex"}
STATES = {"error", "creating", "suspended", "idle", "running"}


class TraceError(Exception):
    pass


def integer(value):
    if isinstance(value, bool):
        return None
    try:
        result = int(value)
        return result if result >= 0 and str(value) == str(result) else None
    except (TypeError, ValueError, OverflowError):
        return None


def latency(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,10}/[0-9]{1,10}", value):
        return None
    numerator, denominator = map(int, value.split("/"))
    return [numerator, denominator] if numerator <= 0xffffffff and 0 < denominator <= 0xffffffff else None


def boolean(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value in {"true", "false", "1", "0"}:
        return value in {"true", "1"}
    return None


class Writer:
    def __init__(self, stream, limit=MAX_BYTES):
        self.stream, self.limit, self.size = stream, limit, 0

    def emit(self, kind, **fields):
        record = {"event": kind, "utc": datetime.now(timezone.utc).isoformat(),
                  "monotonic_ns": time.monotonic_ns(), **fields}
        line = json.dumps(record, separators=(",", ":"), allow_nan=False) + "\n"
        self.size += len(line.encode())
        if self.size > self.limit:
            raise TraceError("output-limit")
        self.stream.write(line)
        self.stream.flush()


class Graph:
    def __init__(self, writer):
        self.writer, self.objects = writer, {}
        self.epochs = {}

    def identities(self):
        return {key: (integer(obj["props"].get("object.serial")), self.epochs.get(key, 0)) for key, obj in self.objects.items()
                if obj["type"] == "Node" and integer(obj["props"].get("object.serial")) is not None}

    def category(self, obj):
        client = self.objects.get(integer(obj["props"].get("client.id")), {})
        return client.get("props", {}).get("category", "other") if client.get("type") == "Client" else "other"

    def update(self, items):
        if not isinstance(items, list) or len(items) > 20000:
            raise TraceError("unsupported-graph-format")
        changed = set()
        for item in items:
            if not isinstance(item, dict):
                raise TraceError("unsupported-graph-format")
            key = integer(item.get("id"))
            if key is None:
                continue
            if "info" in item and item["info"] is None:
                old = self.objects.pop(key, None)
                self.epochs[key] = self.epochs.get(key, 0) + 1
                if old and old["type"] in {"Node", "Link"}:
                    self.writer.emit("removed", id=key, serial=integer(old["props"].get("object.serial")), object_type=old["type"])
                changed.add(key)
                continue
            kind = item.get("type", "")
            if not isinstance(kind, str):
                raise TraceError("unsupported-graph-format")
            kind = kind.removeprefix("PipeWire:Interface:")
            old = self.objects.get(key)
            if kind not in {"Node", "Link", "Client"}:
                kind = old["type"] if old else ""
            if not kind:
                continue
            info = item.get("info", {})
            if not isinstance(info, dict):
                raise TraceError("unsupported-graph-format")
            props = dict(old["props"]) if old else {}
            incoming = info.get("props", {})
            if not isinstance(incoming, dict):
                raise TraceError("unsupported-graph-format")
            # Retain only properties used below. Monitor updates can be partial.
            for name in ("object.serial", "client.id", "node.driver-id"):
                if name in incoming:
                    props[name] = integer(incoming[name])
            for name in ("node.latency", "node.passive", "node.always-process", "node.driver"):
                if name in incoming:
                    props[name] = latency(incoming[name]) if name == "node.latency" else boolean(incoming[name])
            for name, allowed in (("media.class", MEDIA), ("application.process.binary", None)):
                if name not in incoming:
                    continue
                value = incoming[name]
                if not isinstance(value, str):
                    raise TraceError("unsupported-graph-format")
                if allowed is not None:
                    props[name] = value if value in allowed else None
                elif kind == "Client":
                    # Keep only the classification, never the raw binary or private strings.
                    props["category"] = next((label for label, binaries in CLASSES.items() if value in binaries), "other")
            if old and integer(props.get("object.serial")) != integer(old["props"].get("object.serial")):
                self.epochs[key] = self.epochs.get(key, 0) + 1
            obj = {"type": kind, "props": props, "info": dict(old["info"]) if old else {}}
            for name in ("state", "output-node-id", "input-node-id"):
                if name in info:
                    value = info[name]
                    if name == "state":
                        if not isinstance(value, str):
                            raise TraceError("unsupported-graph-format")
                        obj["info"][name] = value if value in STATES else "unknown"
                    else:
                        obj["info"][name] = integer(value)
            self.objects[key] = obj
            changed.add(key)
        if len(self.objects) > 20000 or len(self.epochs) > 20000:
            raise TraceError("graph-object-limit")
        # Clients may occur after their nodes in the same initial dump.
        clients_changed = any(self.objects.get(key, {}).get("type") == "Client" for key in changed)
        for key, obj in self.objects.items():
            if key not in changed and not (clients_changed and obj["type"] == "Node"):
                continue
            serial = integer(obj["props"].get("object.serial"))
            if obj["type"] == "Node":
                media = obj["props"].get("media.class")
                if not isinstance(media, str) or media not in MEDIA:
                    continue
                state = obj["info"].get("state")
                self.writer.emit("node", id=key, serial=serial, state=state if isinstance(state, str) and state in STATES else "unknown",
                                 media_class=media, category=self.category(obj),
                                 requested_latency=obj["props"].get("node.latency"),
                                 passive=obj["props"].get("node.passive"),
                                 always_process=obj["props"].get("node.always-process"),
                                 node_driver=obj["props"].get("node.driver"),
                                 driver_id=obj["props"].get("node.driver-id"))
            elif obj["type"] == "Link":
                self.writer.emit("link", id=key, serial=serial,
                                 output_node=integer(obj["info"].get("output-node-id")),
                                 input_node=integer(obj["info"].get("input-node-id")))


class Top:
    HEADER = ["S", "ID", "QUANT", "RATE", "WAIT", "BUSY", "W/Q", "B/Q", "ERR", "FORMAT", "NAME"]

    def __init__(self, graph, writer):
        self.graph, self.writer = graph, writer
        self.rows, self.identity, self.previous = [], None, {}
        self.frames = 0
        self.mature_samples = 0
        self.rejected_rows = 0
        self.frame_time = {}

    def line(self, line):
        parts = line.split()
        if not parts:
            return
        if parts[:len(self.HEADER)] == self.HEADER:
            self.finish()
            self.identity = self.graph.identities()
            self.frame_time = {"frame_received_utc": datetime.now(timezone.utc).isoformat(),
                               "frame_received_monotonic_ns": time.monotonic_ns()}
            return
        if self.identity is None:
            raise TraceError("unsupported-pw-top-format")
        if len(parts) < 10 or parts[0] not in {"R", "I", "S", "C", "E", "t", "T"}:
            raise TraceError("unsupported-pw-top-format")
        values = [integer(parts[index]) for index in (1, 2, 3, 8)]
        if any(value is None for value in values):
            raise TraceError("unsupported-pw-top-format")
        self.rows.append((parts[0], *values))
        if len(self.rows) > 20000:
            raise TraceError("pw-top-row-limit")

    def finish(self):
        if self.identity is None:
            return
        self.frames += 1
        current = self.graph.identities()
        samples, rejected = [], 0
        for state, key, quantum, rate, errors in self.rows:
            token = self.identity.get(key)
            serial = token[0] if token else None
            if (self.frames == 1 or state != "R" or not quantum or not rate
                    or serial is None or current.get(key) != self.identity.get(key)):
                rejected += 1
                continue
            identity = (key, *token)
            previous = self.previous.get(identity)
            delta = errors - previous if previous is not None and errors >= previous else None
            status = "baseline" if previous is None else "reset" if errors < previous else "delta"
            self.previous[identity] = errors
            samples.append({"id": key, "serial": serial, "quantum": quantum, "rate": rate,
                            "err_total": errors, "err_delta": delta, "counter_status": status})
        # Remove identities that disappeared/reused IDs; never bridge their counters.
        self.previous = {identity: value for identity, value in self.previous.items()
                         if current.get(identity[0]) == identity[1:]}
        self.mature_samples += len(samples)
        self.rejected_rows += rejected
        self.writer.emit("top_frame", index=self.frames, warmup=self.frames == 1,
                         samples=samples, rejected_rows=rejected, **self.frame_time)
        self.rows, self.identity = [], None


def collect(args, writer):
    writer.emit("start", duration_seconds=args.duration,
                collector_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                scope="read-only graph metadata; ERR combines xruns and errors; no PCM or clipping diagnosis")
    selector = selectors.DefaultSelector()
    children, buffers = {}, {}
    graph = Graph(writer)
    top = Top(graph, writer)
    deadline = time.monotonic() + args.duration
    decoder = json.JSONDecoder()
    marker_rejected = False
    try:
        # Refreshes can arrive faster than once per second (including graph
        # changes). Bound both owned tools by our monotonic deadline, not by
        # a guessed number of pw-top refreshes.
        for name, command in (("graph", ["pw-dump", "--monitor", "--no-colors"]),
                              ("top", ["pw-top", "--batch-mode"])):
            child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     stdin=subprocess.DEVNULL, start_new_session=True)
            children[name] = child
            os.set_blocking(child.stdout.fileno(), False)
            selector.register(child.stdout, selectors.EVENT_READ, name)
            buffers[name] = ""
        if args.markers:
            selector.register(sys.stdin, selectors.EVENT_READ, "marker")
            buffers["marker"] = ""
        while time.monotonic() < deadline and selector.get_map():
            for event, _ in selector.select(min(args.interval, max(0, deadline-time.monotonic()))):
                name = event.data
                data = os.read(event.fd, 1024 if name == "marker" else 65536)
                if not data:
                    selector.unregister(event.fileobj)
                    if name != "marker":
                        raise TraceError("tool-ended-early")
                    continue
                buffers[name] += data.decode("utf-8", errors="replace")
                if len(buffers[name].encode()) > (2048 if name == "marker" else MAX_INPUT):
                    raise TraceError("input-limit")
                if name == "graph":
                    while buffers[name].strip():
                        text = buffers[name].lstrip()
                        if not text.startswith("["):
                            raise TraceError("unsupported-graph-format")
                        try:
                            value, end = decoder.raw_decode(text)
                        except json.JSONDecodeError:
                            break
                        graph.update(value)
                        buffers[name] = text[end:]
                else:
                    while "\n" in buffers[name]:
                        line, buffers[name] = buffers[name].split("\n", 1)
                        if name == "top":
                            top.line(line)
                        elif line.strip() in MARKERS:
                            writer.emit("marker", marker=line.strip())
                        elif line.strip() and not marker_rejected:
                            writer.emit("marker_rejected")
                            marker_rejected = True
        # A live stream can be midway through its next packet at our deadline.
        # Keep completed records, explicitly discard that boundary tail and
        # its in-progress top frame, and never reinterpret earlier failed runs.
        graph_tail = len(buffers["graph"].strip().encode())
        top_tail = len(buffers["top"].strip().encode())
        if graph_tail or top_tail:
            writer.emit("deadline_tail_discarded", graph_bytes=graph_tail,
                        top_bytes=top_tail, unfinished_top_rows=len(top.rows))
            top.rows, top.identity = [], None
        else:
            top.finish()
        if top.frames < 2 or not top.mature_samples:
            raise TraceError("insufficient-mature-frames")
        writer.emit("complete", frames=top.frames, accepted_samples=top.mature_samples,
                    rejected_rows=top.rejected_rows, acceptance="collection-only")
    finally:
        selector.close()
        for child in children.values():
            if child.poll() is None:
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        for child in children.values():
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait(timeout=1)
            finally:
                child.stdout.close()


def bounded_float(low, high):
    def parse(raw):
        try:
            value = float(raw)
        except ValueError:
            raise argparse.ArgumentTypeError(f"must be between {low} and {high}") from None
        if not math.isfinite(value) or not low <= value <= high:
            raise argparse.ArgumentTypeError(f"must be between {low} and {high}")
        return value
    return parse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new private JSONL file; existing paths are refused")
    parser.add_argument("--duration", type=bounded_float(1, 60), default=45)
    parser.add_argument("--interval", type=bounded_float(.05, 1), default=.25, help="maximum event-loop wait, not pw-top sampling rate")
    parser.add_argument("--markers", action="store_true", help="read fixed markers from stdin; other text is discarded")
    args = parser.parse_args()
    try:
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as stream:
            writer = Writer(stream)
            try:
                collect(args, writer)
            except (TraceError, OSError, ValueError, KeyboardInterrupt) as error:
                # Raw tool errors and arguments can contain private metadata.
                try:
                    writer.emit("incomplete", reason=str(error) if isinstance(error, TraceError) else "tool-or-interruption")
                except TraceError:
                    pass
                print("Trace incomplete; tool/format/bounds failure. Retain as incomplete evidence.", file=sys.stderr)
                return 1
    except OSError:
        print("Cannot create a new private output file.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
