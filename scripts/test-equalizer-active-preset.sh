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

printf 'PASS: EQ DSP updates the live Equalizer without reloading Convolver -> EQ -> Limiter\n'
