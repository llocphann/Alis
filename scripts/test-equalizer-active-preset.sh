#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/scripts/equalizer-control.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/alis-eq-active.XXXXXX")"
server_pid=""

cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf -- "$tmp"
}
trap cleanup EXIT

export HOME="$tmp/home"
export XDG_DATA_HOME="$tmp/data"
export XDG_CONFIG_HOME="$tmp/config"
export XDG_STATE_HOME="$tmp/state"
export XDG_RUNTIME_DIR="$tmp/runtime"

mkdir -p "$HOME" "$XDG_DATA_HOME/easyeffects/output" \
    "$XDG_CONFIG_HOME/easyeffects/output" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"

preset_file="$XDG_DATA_HOME/easyeffects/output/Music.json"
cat >"$preset_file" <<'JSON'
{
    "output": {
        "blocklist": ["keep-me"],
        "convolver#0": {
            "bypass": false,
            "input-gain": -1.0,
            "kernel-name": "room.irs"
        },
        "equalizer#0": {
            "balance": 0.25,
            "bypass": false,
            "input-gain": -1.5,
            "left": {
                "band0": {
                    "frequency": 100.0,
                    "gain": 1.0,
                    "mode": "RLC (BT)",
                    "mute": false,
                    "q": 2.0,
                    "slope": "x1",
                    "solo": false,
                    "type": "Bell",
                    "width": 2.0
                }
            },
            "mode": "IIR",
            "num-bands": 1,
            "output-gain": 2.0,
            "right": {
                "band0": {
                    "frequency": 100.0,
                    "gain": 1.0,
                    "mode": "RLC (BT)",
                    "mute": false,
                    "q": 2.0,
                    "slope": "x1",
                    "solo": false,
                    "type": "Bell",
                    "width": 2.0
                }
            },
            "split-channels": false
        },
        "limiter#0": {
            "bypass": false,
            "ceiling": -1.0,
            "lookahead": 5.0
        },
        "plugins_order": [
            "convolver#0",
            "equalizer#0",
            "limiter#0"
        ]
    }
}
JSON

server_log="$tmp/server.log"
python3 - "$XDG_RUNTIME_DIR/EasyEffectsServer" "$server_log" <<'PY' &
import pathlib
import socket
import sys

socket_path = pathlib.Path(sys.argv[1])
log_path = pathlib.Path(sys.argv[2])

props = {
    ("equalizer", "0", None, "numBands"): "1",
    ("equalizer", "0", None, "splitChannels"): "false",
    ("equalizer", "0", "left", "band0Gain"): "1.0",
    ("equalizer", "0", "right", "band0Gain"): "1.0",
}
commands = []

def parse_set(parts):
    plugin = parts[2]
    instance = parts[3]
    if len(parts) == 7:
        channel = parts[4]
        prop = parts[5]
        value = parts[6]
    else:
        channel = None
        prop = parts[4]
        value = parts[5]
    return plugin, instance, channel, prop, value

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(str(socket_path))
server.listen(1)
conn, _ = server.accept()
with conn:
    pending = b""
    while True:
        chunk = conn.recv(8192)
        if not chunk:
            break
        pending += chunk
        while b"\n" in pending:
            raw, pending = pending.split(b"\n", 1)
            command = raw.decode("utf-8")
            commands.append(command)

            if command == "get_last_loaded_preset:output":
                conn.sendall(b"Music\n")
                continue

            parts = command.split(":")
            if parts[0] == "get_property":
                plugin = parts[2]
                instance = parts[3]
                if len(parts) == 6:
                    channel = parts[4]
                    prop = parts[5]
                else:
                    channel = None
                    prop = parts[4]
                value = props.get((plugin, instance, channel, prop))
                if value is None:
                    if plugin != "equalizer" or instance != "0":
                        value = "error_plugin_not_found"
                    elif prop.startswith("band") and (
                        prop.endswith("Gain") or prop.endswith("Frequency")
                    ):
                        value = "0"
                    else:
                        value = "error_property_not_found"
                conn.sendall((value + "\n").encode("utf-8"))
                continue

            if parts[0] == "set_property":
                plugin, instance, channel, prop, value = parse_set(parts)
                props[(plugin, instance, channel, prop)] = value

log_path.write_text("\n".join(commands) + "\n", encoding="utf-8")
server.close()
PY
server_pid=$!

for _ in $(seq 1 100); do
    [[ -S "$XDG_RUNTIME_DIR/EasyEffectsServer" ]] && break
    sleep 0.01
done
[[ -S "$XDG_RUNTIME_DIR/EasyEffectsServer" ]] || {
    printf 'FAIL: fake EasyEffects server did not start\n' >&2
    exit 1
}

"$helper" apply native Bass 5 7 5 2 1 0 0 0 1 2
wait "$server_pid"
server_pid=""

python3 - "$preset_file" "$XDG_STATE_HOME/alis/equalizer_state.json" "$server_log" <<'PY'
import json
import pathlib
import sys

preset_path = pathlib.Path(sys.argv[1])
state_path = pathlib.Path(sys.argv[2])
log_path = pathlib.Path(sys.argv[3])

preset = json.loads(preset_path.read_text(encoding="utf-8"))
output = preset["output"]

expected_order = ["convolver#0", "equalizer#0", "limiter#0"]
if output["plugins_order"] != expected_order:
    raise SystemExit("FAIL: Convolver -> EQ -> Limiter order changed")
if output["blocklist"] != ["keep-me"]:
    raise SystemExit("FAIL: output blocklist was replaced")
if output["convolver#0"] != {
    "bypass": False,
    "input-gain": -1.0,
    "kernel-name": "room.irs",
}:
    raise SystemExit("FAIL: Convolver was modified")
if output["limiter#0"] != {
    "bypass": False,
    "ceiling": -1.0,
    "lookahead": 5.0,
}:
    raise SystemExit("FAIL: Limiter was modified")

eq = output["equalizer#0"]
if eq["balance"] != 0.25 or eq["input-gain"] != -1.5 or eq["output-gain"] != 2.0:
    raise SystemExit("FAIL: unrelated Equalizer settings were replaced")
if eq["mode"] != "IIR":
    raise SystemExit("FAIL: Equalizer processing mode changed")
if eq["num-bands"] != 32 or eq["split-channels"] is not False:
    raise SystemExit("FAIL: Alis 32-band Equalizer shape was not persisted")

expected = {
    0: 5.0, 3: 7.0, 6: 5.0, 9: 2.0, 12: 1.0,
    15: 0.0, 18: 0.0, 21: 0.0, 24: 1.0, 27: 2.0,
}
for index in range(32):
    left = eq["left"][f"band{index}"]
    right = eq["right"][f"band{index}"]
    target = expected.get(index, 0.0)
    if left["gain"] != target or right["gain"] != target:
        raise SystemExit(f"FAIL: band{index} gain mismatch")
    if left["frequency"] != right["frequency"]:
        raise SystemExit(f"FAIL: band{index} channel frequencies diverged")

state = json.loads(state_path.read_text(encoding="utf-8"))
if state["preset"] != "Bass":
    raise SystemExit("FAIL: Alis preset label did not commit")
if state["gains"] != [5.0, 7.0, 5.0, 2.0, 1.0, 0.0, 0.0, 0.0, 1.0, 2.0]:
    raise SystemExit("FAIL: Alis DSP gains did not commit")

commands = log_path.read_text(encoding="utf-8").splitlines()
if "get_last_loaded_preset:output" not in commands:
    raise SystemExit("FAIL: active preset was not queried")
if any(command.startswith("load_preset:") for command in commands):
    raise SystemExit("FAIL: DSP update reloaded the pipeline")
if any(":convolver:" in command or ":limiter:" in command for command in commands):
    raise SystemExit("FAIL: DSP update touched Convolver or Limiter")
if not any(
    command.startswith("set_property:output:equalizer:0:left:band27Gain:2")
    for command in commands
):
    raise SystemExit("FAIL: live left Equalizer gain was not updated")
if not any(
    command.startswith("set_property:output:equalizer:0:right:band27Gain:2")
    for command in commands
):
    raise SystemExit("FAIL: live right Equalizer gain was not updated")
PY

# Regression 1: A preset whose band0 is Hi-pass/x2 (with daemon reporting band0Type=2)
# must coerce all 32 graphic bands to Bell / x1 and push band{0..31}Type:1 over socket.
preset_hipass="$XDG_DATA_HOME/easyeffects/output/HiPassSeed.json"
cat >"$preset_hipass" <<'JSON'
{
    "output": {
        "plugins_order": ["equalizer#0"],
        "equalizer#0": {
            "bypass": false,
            "mode": "IIR",
            "num-bands": 1,
            "split-channels": true,
            "left": {
                "band0": {"frequency": 150.0, "gain": 0.0, "mode": "RLC (BT)", "mute": false, "q": 0.707, "slope": "x2", "solo": false, "type": "Hi-pass", "width": 4.0}
            },
            "right": {
                "band0": {"frequency": 150.0, "gain": 0.0, "mode": "RLC (BT)", "mute": false, "q": 0.707, "slope": "x2", "solo": false, "type": "Hi-pass", "width": 4.0}
            }
        }
    }
}
JSON

rm -f "$XDG_RUNTIME_DIR/EasyEffectsServer"
hipass_log="$tmp/hipass.log"
python3 - "$XDG_RUNTIME_DIR/EasyEffectsServer" "$hipass_log" <<'PY' &
import pathlib, socket, sys
sock_path, log_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
props = {
    ("equalizer", "0", None, "numBands"): "1",
    ("equalizer", "0", None, "splitChannels"): "true",
    ("equalizer", "0", "left", "band0Gain"): "0.0",
    ("equalizer", "0", "right", "band0Gain"): "0.0",
    ("equalizer", "0", "left", "band0Type"): "2",
}
commands = []
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(str(sock_path))
s.listen(1)
conn, _ = s.accept()
with conn:
    pending = b""
    while True:
        chunk = conn.recv(8192)
        if not chunk:
            break
        pending += chunk
        while b"\n" in pending:
            raw, pending = pending.split(b"\n", 1)
            cmd = raw.decode()
            commands.append(cmd)
            if cmd == "get_last_loaded_preset:output":
                conn.sendall(b"HiPassSeed\n")
            elif cmd.startswith("get_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 6 else (parts[2], parts[3], None, parts[4])
                conn.sendall((props.get(key, "0") + "\n").encode())
            elif cmd.startswith("set_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 7 else (parts[2], parts[3], None, parts[4])
                props[key] = parts[-1]
log_path.write_text("\n".join(commands) + "\n", encoding="utf-8")
s.close()
PY
server_pid=$!
for _ in $(seq 1 100); do [[ -S "$XDG_RUNTIME_DIR/EasyEffectsServer" ]] && break; sleep 0.01; done
"$helper" apply native Flat 0 0 0 0 0 0 0 0 0 0
wait "$server_pid"
server_pid=""
python3 - "$preset_hipass" "$hipass_log" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
eq = doc["output"]["equalizer#0"]
for ch in ("left", "right"):
    for i in range(32):
        b = eq[ch][f"band{i}"]
        if b.get("type") != "Bell" or b.get("slope") != "x1":
            raise SystemExit(f"FAIL: {ch} band{i} coerced incorrectly: {b}")
cmds = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
if "set_property:output:equalizer:0:left:band31Type:1" not in cmds:
    raise SystemExit("FAIL: socket did not reset band31Type to Bell (1)")
PY

# Regression 2: dolby_to_easyeffects.py preset without equalizer#2 must refuse (exit 66)
# and keep equalizer#0 untouched; with equalizer#2 it must update equalizer#2 only.
preset_dolby="$XDG_DATA_HOME/easyeffects/output/Dolby-Balanced.json"
cat >"$preset_dolby" <<'JSON'
{
    "_generator": "dolby_to_easyeffects.py v2026.10.1-20-g2180c73",
    "output": {
        "plugins_order": ["convolver#0", "equalizer#0", "equalizer#1", "limiter#0"],
        "equalizer#0": {
            "bypass": false, "mode": "IIR", "num-bands": 4, "split-channels": true,
            "left": {"band0": {"frequency": 150.0, "gain": 0.0, "type": "Hi-pass", "slope": "x2"}, "band1": {"frequency": 830.0, "gain": -10.5, "type": "Bell", "slope": "x1"}},
            "right": {"band0": {"frequency": 150.0, "gain": 0.0, "type": "Hi-pass", "slope": "x2"}, "band1": {"frequency": 830.0, "gain": -10.5, "type": "Bell", "slope": "x1"}}
        },
        "equalizer#1": {
            "bypass": true, "mode": "IIR", "num-bands": 1, "split-channels": false,
            "left": {"band0": {"frequency": 2500.0, "gain": 1.88, "type": "Bell", "slope": "x1"}},
            "right": {"band0": {"frequency": 2500.0, "gain": 1.88, "type": "Bell", "slope": "x1"}}
        }
    }
}
JSON

spawn_dolby_server() {
    local sock="$1" log="$2"
    rm -f "$sock"
    python3 - "$sock" "$log" <<'PY' &
import pathlib, socket, sys
sock_path, log_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
props = {
    ("equalizer", "2", None, "numBands"): "32",
    ("equalizer", "2", None, "splitChannels"): "false",
    ("equalizer", "2", "left", "band0Gain"): "0",
    ("equalizer", "2", "right", "band0Gain"): "0",
    ("equalizer", "2", "left", "band0Type"): "1",
}
cmds = []
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(str(sock_path))
s.listen(1)
conn, _ = s.accept()
with conn:
    pending = b""
    while True:
        chunk = conn.recv(8192)
        if not chunk:
            break
        pending += chunk
        while b"\n" in pending:
            raw, pending = pending.split(b"\n", 1)
            cmd = raw.decode()
            cmds.append(cmd)
            if cmd == "get_last_loaded_preset:output":
                conn.sendall(b"Dolby-Balanced\n")
            elif cmd.startswith("get_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 6 else (parts[2], parts[3], None, parts[4])
                conn.sendall((props.get(key, "0") + "\n").encode())
            elif cmd.startswith("set_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 7 else (parts[2], parts[3], None, parts[4])
                props[key] = parts[-1]
log_path.write_text("\n".join(cmds) + "\n", encoding="utf-8")
s.close()
PY
    server_pid=$!
    for _ in $(seq 1 100); do [[ -S "$sock" ]] && break; sleep 0.01; done
}

spawn_dolby_server "$XDG_RUNTIME_DIR/EasyEffectsServer" "$tmp/dolby1.log"
set +e
"$helper" apply native Flat 0 0 0 0 0 0 0 0 0 0 >/dev/null 2>"$tmp/dolby1.err"
rc=$?
set -e
wait "$server_pid"
server_pid=""
[[ "$rc" -eq 66 ]] || { printf 'FAIL: expected exit 66 without equalizer#2, got %s\n' "$rc" >&2; exit 1; }
python3 - "$preset_dolby" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
eq0 = doc["output"]["equalizer#0"]
if eq0["num-bands"] != 4 or eq0["left"]["band0"]["type"] != "Hi-pass" or eq0["left"]["band1"]["gain"] != -10.5:
    raise SystemExit("FAIL: equalizer#0 was mutated when equalizer#2 was absent")
doc["output"]["plugins_order"].insert(3, "equalizer#2")
doc["output"]["equalizer#2"] = {
    "bypass": False, "mode": "IIR", "num-bands": 32, "split-channels": False,
    "left": {"band0": {"frequency": 31, "gain": 0.0, "type": "Bell", "slope": "x1"}},
    "right": {"band0": {"frequency": 31, "gain": 0.0, "type": "Bell", "slope": "x1"}}
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(doc, indent=4) + "\n", encoding="utf-8")
PY

spawn_dolby_server "$XDG_RUNTIME_DIR/EasyEffectsServer" "$tmp/dolby2.log"
"$helper" apply native Bass 5 7 5 2 1 0 0 0 1 2
wait "$server_pid"
server_pid=""
python3 - "$preset_dolby" "$tmp/dolby2.log" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
eq0 = doc["output"]["equalizer#0"]
eq2 = doc["output"]["equalizer#2"]
if eq0["num-bands"] != 4 or eq0["left"]["band0"]["type"] != "Hi-pass" or eq0["left"]["band1"]["gain"] != -10.5:
    raise SystemExit("FAIL: speaker PEQ equalizer#0 was modified")
if eq2["left"]["band0"]["gain"] != 5.0 or eq2["right"]["band27"]["gain"] != 2.0:
    raise SystemExit("FAIL: user graphic EQ equalizer#2 did not persist")
cmds = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
if any(":equalizer:0:" in c for c in cmds):
    raise SystemExit("FAIL: socket touched equalizer#0 on Dolby preset")
if "set_property:output:equalizer:2:left:band0Gain:5.0" not in cmds:
    raise SystemExit("FAIL: socket did not update equalizer#2")
PY

printf 'PASS: EQ DSP updates the live Equalizer without reloading Convolver -> EQ -> Limiter\n'
