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

# Regression 2: dolby_to_easyeffects.py speaker-tuning preset without equalizer#2
# (or with misplaced equalizer#2 before convolver#0 in easyeffectsrc) must
# auto-provision equalizer#2 in the optimal acoustic slot AFTER convolver#0 ->
# equalizer#0 -> equalizer#1 and BEFORE autogain#0 -> multiband_compressor#* ->
# limiter#0, keep all calibration/dynamics stages untouched, sync sibling Dolby-*
# speaker presets while leaving Nothing.json empty, reload once when topology
# changed, and use zero reloads on subsequent steady-state updates.
preset_dolby="$XDG_DATA_HOME/easyeffects/output/Dolby-Balanced.json"
preset_dolby_warm="$XDG_DATA_HOME/easyeffects/output/Dolby-Warm.json"
cat >"$preset_dolby" <<'JSON'
{
    "_generator": "dolby_to_easyeffects.py v2026.10.1-20-g2180c73",
    "output": {
        "blocklist": [],
        "convolver#0": {
            "bypass": false,
            "kernel-name": "Dolby-Balanced-811d6901"
        },
        "plugins_order": [
            "convolver#0",
            "equalizer#0",
            "equalizer#1",
            "autogain#0",
            "multiband_compressor#0",
            "multiband_compressor#1",
            "limiter#0"
        ],
        "equalizer#0": {
            "bypass": false, "mode": "IIR", "num-bands": 4, "split-channels": true,
            "left": {"band0": {"frequency": 150.0, "gain": 0.0, "type": "Hi-pass", "slope": "x2"}, "band1": {"frequency": 830.0, "gain": -10.5, "type": "Bell", "slope": "x1"}},
            "right": {"band0": {"frequency": 150.0, "gain": 0.0, "type": "Hi-pass", "slope": "x2"}, "band1": {"frequency": 830.0, "gain": -10.5, "type": "Bell", "slope": "x1"}}
        },
        "equalizer#1": {
            "bypass": true, "mode": "IIR", "num-bands": 1, "split-channels": false,
            "left": {"band0": {"frequency": 2500.0, "gain": 1.88, "type": "Bell", "slope": "x1"}},
            "right": {"band0": {"frequency": 2500.0, "gain": 1.88, "type": "Bell", "slope": "x1"}}
        },
        "autogain#0": {"bypass": true},
        "multiband_compressor#0": {"bypass": false},
        "multiband_compressor#1": {"bypass": false},
        "limiter#0": {"bypass": false, "threshold": -1.0}
    }
}
JSON

cat >"$preset_dolby_warm" <<'JSON'
{
    "_generator": "dolby_to_easyeffects.py v2026.10.1-20-g2180c73",
    "output": {
        "blocklist": [],
        "convolver#0": {"bypass": false, "kernel-name": "Dolby-Warm-c5b6a03b"},
        "plugins_order": [
            "convolver#0",
            "equalizer#0",
            "equalizer#1",
            "autogain#0",
            "multiband_compressor#0",
            "multiband_compressor#1",
            "limiter#0"
        ],
        "equalizer#0": {
            "bypass": false, "mode": "IIR", "num-bands": 4, "split-channels": true,
            "left": {"band0": {"frequency": 150.0, "gain": 0.0, "type": "Hi-pass", "slope": "x2"}, "band1": {"frequency": 830.0, "gain": -10.5, "type": "Bell", "slope": "x1"}},
            "right": {"band0": {"frequency": 150.0, "gain": 0.0, "type": "Hi-pass", "slope": "x2"}, "band1": {"frequency": 830.0, "gain": -10.5, "type": "Bell", "slope": "x1"}}
        },
        "equalizer#1": {
            "bypass": false, "mode": "IIR", "num-bands": 1, "split-channels": false,
            "left": {"band0": {"frequency": 3200.0, "gain": -1.16, "type": "Bell", "slope": "x1"}},
            "right": {"band0": {"frequency": 3200.0, "gain": -1.16, "type": "Bell", "slope": "x1"}}
        },
        "autogain#0": {"bypass": true},
        "multiband_compressor#0": {"bypass": false},
        "multiband_compressor#1": {"bypass": false},
        "limiter#0": {"bypass": false, "threshold": -1.0}
    }
}
JSON

cat >"$XDG_DATA_HOME/easyeffects/output/Nothing.json" <<'JSON'
{
    "_generator": "dolby_to_easyeffects.py v2026.10.1-20-g2180c73",
    "output": {
        "blocklist": [],
        "plugins_order": []
    }
}
JSON

# Simulate live user state where Equalizer was manually placed at index 0
# (before Convolver) in easyeffectsrc without saving equalizer#2 into JSON.
mkdir -p "$XDG_CONFIG_HOME/easyeffects/db"
cat >"$XDG_CONFIG_HOME/easyeffects/db/easyeffectsrc" <<'INI'
[Presets]
lastLoadedOutputPreset=Dolby-Balanced

[StreamOutputs]
outputDevice=alsa_output.pci-0000_64_00.6.HiFi__Speaker__sink
plugins=equalizer#2,convolver#0,equalizer#0,equalizer#1,autogain#0,multiband_compressor#0,multiband_compressor#1,limiter#0
INI

spawn_dolby_server() {
    local sock="$1" log="$2" initial_eq2="${3:-missing}" rc_update_path="${4:-}"
    rm -f "$sock"
    python3 - "$sock" "$log" "$initial_eq2" "$rc_update_path" <<'PY' &
import pathlib, socket, sys
sock_path, log_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
initial_eq2, rc_update_path = sys.argv[3], sys.argv[4]
props = {}
if initial_eq2 == "ready":
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
            elif cmd.startswith("load_preset:output:"):
                props[("equalizer", "2", None, "numBands")] = "32"
                props[("equalizer", "2", None, "splitChannels")] = "false"
                props[("equalizer", "2", "left", "band0Gain")] = "0"
                props[("equalizer", "2", "right", "band0Gain")] = "0"
                props[("equalizer", "2", "left", "band0Type")] = "1"
                if rc_update_path:
                    pathlib.Path(rc_update_path).write_text(
                        "[Presets]\nlastLoadedOutputPreset=Dolby-Balanced\n\n"
                        "[StreamOutputs]\noutputDevice=alsa_output.pci-0000_64_00.6.HiFi__Speaker__sink\n"
                        "plugins=convolver#0,equalizer#0,equalizer#1,equalizer#2,autogain#0,multiband_compressor#0,multiband_compressor#1,limiter#0\n",
                        encoding="utf-8",
                    )
            elif cmd.startswith("get_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 6 else (parts[2], parts[3], None, parts[4])
                if ("equalizer", "2", None, "numBands") not in props and parts[2] == "equalizer" and parts[3] == "2":
                    conn.sendall(b"error_plugin_not_found\n")
                else:
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

spawn_dolby_server "$XDG_RUNTIME_DIR/EasyEffectsServer" "$tmp/dolby1.log" "missing" "$XDG_CONFIG_HOME/easyeffects/db/easyeffectsrc"
"$helper" apply native Bass 5 7 5 2 1 0 0 0 1 2
wait "$server_pid"
server_pid=""

python3 - "$preset_dolby" "$preset_dolby_warm" "$XDG_DATA_HOME/easyeffects/output/Nothing.json" "$tmp/dolby1.log" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
warm = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
nothing = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
cmds = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8").splitlines()

expected_order = [
    "convolver#0", "equalizer#0", "equalizer#1", "equalizer#2",
    "autogain#0", "multiband_compressor#0", "multiband_compressor#1", "limiter#0",
]
if doc["output"]["plugins_order"] != expected_order:
    raise SystemExit(f"FAIL: suboptimal Dolby-Balanced plugins_order: {doc['output']['plugins_order']}")
if warm["output"]["plugins_order"] != expected_order:
    raise SystemExit(f"FAIL: sibling Dolby-Warm did not receive equalizer#2 at optimal slot: {warm['output']['plugins_order']}")
if nothing["output"]["plugins_order"] != []:
    raise SystemExit("FAIL: Nothing.json pass-through preset was unexpectedly mutated during sibling sync")

eq0 = doc["output"]["equalizer#0"]
eq1 = doc["output"]["equalizer#1"]
eq2 = doc["output"]["equalizer#2"]
if eq0["num-bands"] != 4 or eq0["left"]["band0"]["type"] != "Hi-pass" or eq0["left"]["band1"]["gain"] != -10.5:
    raise SystemExit("FAIL: speaker PEQ equalizer#0 was mutated during equalizer#2 provisioning")
if eq1["num-bands"] != 1 or eq1["left"]["band0"]["gain"] != 1.88:
    raise SystemExit("FAIL: speaker trim equalizer#1 was mutated during equalizer#2 provisioning")
if doc["output"]["limiter#0"]["threshold"] != -1.0 or doc["output"]["convolver#0"]["kernel-name"] != "Dolby-Balanced-811d6901":
    raise SystemExit("FAIL: convolver#0 or limiter#0 was mutated")
if eq2["left"]["band0"]["gain"] != 5.0 or eq2["right"]["band27"]["gain"] != 2.0:
    raise SystemExit("FAIL: provisioned equalizer#2 did not persist Bass curve")
if warm["output"]["equalizer#2"]["left"]["band0"]["gain"] != 5.0 or warm["output"]["equalizer#1"]["left"]["band0"]["gain"] != -1.16:
    raise SystemExit("FAIL: sibling Dolby-Warm equalizer#2 / equalizer#1 mismatch")
if cmds.count("load_preset:output:Dolby-Balanced") != 1:
    raise SystemExit(f"FAIL: expected single one-time topology reload, got cmds={cmds}")
if any(":equalizer:0:" in c or ":equalizer:1:" in c for c in cmds):
    raise SystemExit("FAIL: socket touched speaker calibration equalizer#0/#1")
if "set_property:output:equalizer:2:left:band0Gain:5.0" not in cmds:
    raise SystemExit("FAIL: socket did not update equalizer#2")
PY

# Subsequent update on the already-provisioned & correctly-ordered Dolby pipeline
# must apply live over socket with ZERO load_preset reload.
spawn_dolby_server "$XDG_RUNTIME_DIR/EasyEffectsServer" "$tmp/dolby2.log" "ready"
"$helper" apply native Vocal -2 -1 1 3 5 5 4 2 1 0
wait "$server_pid"
server_pid=""
python3 - "$preset_dolby" "$tmp/dolby2.log" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
eq0 = doc["output"]["equalizer#0"]
eq2 = doc["output"]["equalizer#2"]
if eq0["num-bands"] != 4 or eq0["left"]["band0"]["type"] != "Hi-pass" or eq0["left"]["band1"]["gain"] != -10.5:
    raise SystemExit("FAIL: speaker PEQ equalizer#0 was modified")
if eq2["left"]["band0"]["gain"] != -2.0 or eq2["right"]["band12"]["gain"] != 5.0:
    raise SystemExit("FAIL: user graphic EQ equalizer#2 did not persist Vocal curve")
cmds = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
if any(c.startswith("load_preset:") for c in cmds):
    raise SystemExit(f"FAIL: steady-state Dolby update reloaded the pipeline: {cmds}")
if any(":equalizer:0:" in c or ":equalizer:1:" in c for c in cmds):
    raise SystemExit("FAIL: socket touched equalizer#0/#1 on steady-state Dolby update")
if "set_property:output:equalizer:2:left:band12Gain:5.0" not in cmds:
    raise SystemExit("FAIL: socket did not update equalizer#2")
PY

# Regression 3: EasyEffects 8.x autoload mismatch where get_last_loaded_preset:output
# returns "Nothing" (empty plugins_order: []) while easyeffectsrc outputDevice +
# autoload/output/*.json (or secondary convolver kernelName fallback) maps to Dolby-Balanced.
cat >"$XDG_DATA_HOME/easyeffects/output/Nothing.json" <<'JSON'
{
    "output": {
        "plugins_order": []
    }
}
JSON

python3 - "$preset_dolby" "$XDG_STATE_HOME/alis/equalizer_state.json" <<'PY'
import json, pathlib, sys
preset_path, state_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
doc = json.loads(preset_path.read_text(encoding="utf-8"))
doc["output"]["equalizer#2"] = {
    "bypass": False, "mode": "IIR", "num-bands": 32, "split-channels": False,
    "left": {"band0": {"frequency": 31, "gain": 0.0, "type": "Bell", "slope": "x1"}},
    "right": {"band0": {"frequency": 31, "gain": 0.0, "type": "Bell", "slope": "x1"}}
}
preset_path.write_text(json.dumps(doc, indent=4) + "\n", encoding="utf-8")
state_path.write_text(json.dumps({"gains": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "preset": "Flat"}, indent=4) + "\n", encoding="utf-8")
PY

mkdir -p "$XDG_CONFIG_HOME/easyeffects/db" "$XDG_CONFIG_HOME/easyeffects/autoload/output"
cat >"$XDG_CONFIG_HOME/easyeffects/db/easyeffectsrc" <<'INI'
[Presets]
lastLoadedOutputPreset=Nothing

[StreamOutputs]
outputDevice=alsa_output.pci-0000_c4_00.6.HiFi__Speaker__sink
INI

cat >"$XDG_CONFIG_HOME/easyeffects/autoload/output/alsa_output.pci-0000_c4_00.6.HiFi__Speaker__sink:[Out] Speaker.json" <<'JSON'
{
    "device": "alsa_output.pci-0000_c4_00.6.HiFi__Speaker__sink",
    "device-description": "ThinkPad Speaker",
    "device-profile": "[Out] Speaker",
    "preset-name": "Dolby-Balanced"
}
JSON

spawn_autoload_server() {
    local sock="$1" log="$2" kernel="${3:-error_property_not_found}"
    rm -f "$sock"
    python3 - "$sock" "$log" "$kernel" <<'PY' &
import pathlib, socket, sys
sock_path, log_path, kernel_name = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
props = {
    ("convolver", "0", None, "kernelName"): kernel_name,
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
                conn.sendall(b"Nothing\n")
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

spawn_autoload_server "$XDG_RUNTIME_DIR/EasyEffectsServer" "$tmp/dolby3_autoload.log"
"$helper" apply native Bass 5 7 5 2 1 0 0 0 1 2
wait "$server_pid"
server_pid=""

python3 - "$preset_dolby" "$XDG_DATA_HOME/easyeffects/output/Nothing.json" "$XDG_STATE_HOME/alis/equalizer_state.json" "$tmp/dolby3_autoload.log" <<'PY'
import json, pathlib, sys
dolby = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
nothing = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
state = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
cmds = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8").splitlines()

if nothing.get("output", {}).get("plugins_order") != []:
    raise SystemExit("FAIL: Nothing.json pass-through preset was mutated")
eq0 = dolby["output"]["equalizer#0"]
eq2 = dolby["output"]["equalizer#2"]
if eq0["num-bands"] != 4 or eq0["left"]["band0"]["type"] != "Hi-pass" or eq0["left"]["band1"]["gain"] != -10.5:
    raise SystemExit("FAIL: speaker PEQ equalizer#0 was modified during autoload resolution")
if eq2["left"]["band0"]["gain"] != 5.0 or eq2["left"]["band3"]["gain"] != 7.0 or eq2["right"]["band27"]["gain"] != 2.0:
    raise SystemExit("FAIL: autoloaded Dolby-Balanced equalizer#2 did not persist Bass curve")
if state.get("preset") != "Bass" or state.get("gains") != [5.0, 7.0, 5.0, 2.0, 1.0, 0.0, 0.0, 0.0, 1.0, 2.0]:
    raise SystemExit(f"FAIL: Bass state did not commit: {state}")
if any(c.startswith("load_preset:") or ":equalizer:0:" in c or ":convolver:" in c for c in cmds):
    raise SystemExit(f"FAIL: unexpected socket commands during easyeffectsrc autoload apply: {cmds}")
if "set_property:output:equalizer:2:left:band0Gain:5.0" not in cmds:
    raise SystemExit("FAIL: socket did not update equalizer#2 via autoload resolution")
PY

# Secondary fallback (c): when easyeffectsrc/autoload has no match and plugins_order == [],
# convolver:0:kernelName resolves the matching <stem>.json preset.
rm -rf "$XDG_CONFIG_HOME/easyeffects/db" "$XDG_CONFIG_HOME/easyeffects/autoload"
spawn_autoload_server "$XDG_RUNTIME_DIR/EasyEffectsServer" "$tmp/dolby3_kernel.log" "Dolby-Balanced-48000"
"$helper" apply native Rock 5 4 2 -1 -2 -1 2 4 5 6
wait "$server_pid"
server_pid=""

python3 - "$preset_dolby" "$XDG_STATE_HOME/alis/equalizer_state.json" "$tmp/dolby3_kernel.log" <<'PY'
import json, pathlib, sys
dolby = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
state = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
cmds = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").splitlines()
eq2 = dolby["output"]["equalizer#2"]
if eq2["left"]["band12"]["gain"] != -2.0 or eq2["right"]["band27"]["gain"] != 6.0:
    raise SystemExit("FAIL: convolver kernelName fallback did not persist Rock curve to equalizer#2")
if state.get("preset") != "Rock":
    raise SystemExit(f"FAIL: Rock state did not commit via kernelName fallback: {state}")
if "get_property:output:convolver:0:kernelName" not in cmds:
    raise SystemExit("FAIL: secondary convolver kernelName fallback was not queried")
PY

# Regression 4: Non-Dolby multi-stage speaker-tuning preset with calibration PEQ
# (split-channels: true + Hi-pass) must preserve equalizer#0 untouched and inject
# equalizer#1 between equalizer#0 and multiband_compressor#0.
preset_generic="$XDG_DATA_HOME/easyeffects/output/SpeakerAutoEQ.json"
cat >"$preset_generic" <<'JSON'
{
    "output": {
        "blocklist": [],
        "convolver#0": {"bypass": false, "kernel-name": "thinkpad.irs"},
        "equalizer#0": {
            "bypass": false, "mode": "IIR", "num-bands": 2, "split-channels": true,
            "left": {"band0": {"frequency": 120.0, "gain": 0.0, "type": "Hi-pass", "slope": "x2"}},
            "right": {"band0": {"frequency": 120.0, "gain": 0.0, "type": "Hi-pass", "slope": "x2"}}
        },
        "multiband_compressor#0": {"bypass": false},
        "limiter#0": {"bypass": false, "threshold": -1.0},
        "plugins_order": ["convolver#0", "equalizer#0", "multiband_compressor#0", "limiter#0"]
    }
}
JSON

rm -f "$XDG_RUNTIME_DIR/EasyEffectsServer"
generic_log="$tmp/generic.log"
python3 - "$XDG_RUNTIME_DIR/EasyEffectsServer" "$generic_log" <<'PY' &
import pathlib, socket, sys
sock_path, log_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
props = {}
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
                conn.sendall(b"SpeakerAutoEQ\n")
            elif cmd == "load_preset:output:SpeakerAutoEQ":
                props[("equalizer", "1", None, "numBands")] = "32"
                props[("equalizer", "1", None, "splitChannels")] = "false"
                props[("equalizer", "1", "left", "band0Gain")] = "0"
                props[("equalizer", "1", "right", "band0Gain")] = "0"
                props[("equalizer", "1", "left", "band0Type")] = "1"
            elif cmd.startswith("get_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 6 else (parts[2], parts[3], None, parts[4])
                if ("equalizer", "1", None, "numBands") not in props and parts[2] == "equalizer" and parts[3] == "1":
                    conn.sendall(b"error_plugin_not_found\n")
                else:
                    conn.sendall((props.get(key, "0") + "\n").encode())
            elif cmd.startswith("set_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 7 else (parts[2], parts[3], None, parts[4])
                props[key] = parts[-1]
log_path.write_text("\n".join(cmds) + "\n", encoding="utf-8")
s.close()
PY
server_pid=$!
for _ in $(seq 1 100); do [[ -S "$XDG_RUNTIME_DIR/EasyEffectsServer" ]] && break; sleep 0.01; done
"$helper" apply native Pop 2 4 2 0 1 2 4 2 1 2
wait "$server_pid"
server_pid=""

python3 - "$preset_generic" "$generic_log" <<'PY'
import json, pathlib, sys
doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
cmds = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
expected = ["convolver#0", "equalizer#0", "equalizer#1", "multiband_compressor#0", "limiter#0"]
if doc["output"]["plugins_order"] != expected:
    raise SystemExit(f"FAIL: wrong order for generic speaker tuning preset: {doc['output']['plugins_order']}")
if doc["output"]["equalizer#0"]["left"]["band0"]["type"] != "Hi-pass":
    raise SystemExit("FAIL: generic calibration Hi-pass PEQ was clobbered")
if doc["output"]["equalizer#1"]["left"]["band3"]["gain"] != 4.0:
    raise SystemExit("FAIL: equalizer#1 did not persist Pop curve")
if cmds.count("load_preset:output:SpeakerAutoEQ") != 1:
    raise SystemExit(f"FAIL: expected single reload for SpeakerAutoEQ, got {cmds}")
PY

# Regression 5: Headphones / active Nothing.json with no autoload must keep
# Nothing.json empty and provision/load Alis-EQ.json cleanly.
rm -f "$XDG_RUNTIME_DIR/EasyEffectsServer"
nothing_log="$tmp/nothing.log"
python3 - "$XDG_RUNTIME_DIR/EasyEffectsServer" "$nothing_log" <<'PY' &
import pathlib, socket, sys
sock_path, log_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
props = {}
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
                conn.sendall(b"Nothing\n")
            elif cmd == "load_preset:output:Alis-EQ":
                props[("equalizer", "0", None, "numBands")] = "32"
                props[("equalizer", "0", None, "splitChannels")] = "false"
                props[("equalizer", "0", "left", "band0Gain")] = "0"
                props[("equalizer", "0", "right", "band0Gain")] = "0"
                props[("equalizer", "0", "left", "band0Type")] = "1"
            elif cmd.startswith("get_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 6 else (parts[2], parts[3], None, parts[4])
                if ("equalizer", "0", None, "numBands") not in props and parts[2] == "equalizer" and parts[3] == "0":
                    conn.sendall(b"error_plugin_not_found\n")
                else:
                    conn.sendall((props.get(key, "0") + "\n").encode())
            elif cmd.startswith("set_property:"):
                parts = cmd.split(":")
                key = (parts[2], parts[3], parts[4], parts[5]) if len(parts) == 7 else (parts[2], parts[3], None, parts[4])
                props[key] = parts[-1]
log_path.write_text("\n".join(cmds) + "\n", encoding="utf-8")
s.close()
PY
server_pid=$!
for _ in $(seq 1 100); do [[ -S "$XDG_RUNTIME_DIR/EasyEffectsServer" ]] && break; sleep 0.01; done
"$helper" apply native Jazz 3 3 1 1 1 1 2 1 2 3
wait "$server_pid"
server_pid=""

python3 - "$XDG_DATA_HOME/easyeffects/output/Nothing.json" "$XDG_DATA_HOME/easyeffects/output/Alis-EQ.json" "$nothing_log" <<'PY'
import json, pathlib, sys
nothing = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
alis_eq = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
cmds = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").splitlines()
if nothing["output"]["plugins_order"] != []:
    raise SystemExit("FAIL: Nothing.json was modified")
if alis_eq["output"]["plugins_order"] != ["equalizer#0"] or alis_eq["output"]["equalizer#0"]["left"]["band0"]["gain"] != 3.0:
    raise SystemExit("FAIL: Alis-EQ.json did not persist Jazz curve")
if cmds.count("load_preset:output:Alis-EQ") != 1:
    raise SystemExit(f"FAIL: expected load_preset:output:Alis-EQ once, got {cmds}")
PY

printf 'PASS: EQ DSP updates the live Equalizer without reloading Convolver -> EQ -> Limiter\n'
