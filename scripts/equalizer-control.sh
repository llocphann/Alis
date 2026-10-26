#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/alis"
state_file="$state_root/equalizer_state.json"
state_candidate="$state_root/equalizer_state.next.json"

mkdir -p "$state_root"

emit_default_state() {
    printf '%s\n' '{"gains":[0,0,0,0,0,0,0,0,0,0],"preset":"Flat"}'
}

case "$cmd" in
    get)
        if [[ -s "$state_file" ]]; then
            cat "$state_file"
        else
            emit_default_state
        fi
        ;;

    apply)
        backend="${2:-}"
        preset="${3:-Custom}"
        shift 3 || true

        if [[ "$backend" != "native" && "$backend" != "flatpak" ]]; then
            printf 'invalid backend\n' >&2
            exit 64
        fi
        if [[ "$#" -ne 10 ]]; then
            printf 'expected ten band gains\n' >&2
            exit 64
        fi
        if [[ "$preset" == *:* || "$preset" == *$'\n'* || "$preset" == *$'\r'* ]]; then
            printf 'invalid preset label\n' >&2
            exit 64
        fi

        sock="${XDG_RUNTIME_DIR:-}/EasyEffectsServer"
        [[ -n "${XDG_RUNTIME_DIR:-}" && -S "$sock" ]] || exit 65
        command -v python3 >/dev/null 2>&1 || exit 127

        rm -f "$state_candidate"
        if python3 - "$sock" "$state_candidate" "$backend" "$preset" "$@" <<'PY'
import copy
import json
import math
import os
import pathlib
import socket
import sys
import tempfile

socket_path = sys.argv[1]
state_path = pathlib.Path(sys.argv[2])
backend = sys.argv[3]
preset_label = sys.argv[4]
raw_gains = sys.argv[5:]

if len(raw_gains) != 10:
    raise SystemExit(64)

gains = []
for raw in raw_gains:
    value = float(raw)
    if not math.isfinite(value):
        raise SystemExit(64)
    gains.append(max(-12.0, min(12.0, value)))

slider_map = {
    0: 0,
    1: 3,
    2: 6,
    3: 9,
    4: 12,
    5: 15,
    6: 18,
    7: 21,
    8: 24,
    9: 27,
}
frequencies = [
    31, 40, 50, 63, 80, 100, 125, 160,
    200, 250, 315, 400, 500, 630, 800, 1000,
    1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300,
    8000, 10000, 12500, 16000, 20000, 22000, 24000, 24000,
]
gain_by_backend_index = {
    backend_index: gains[dsp_index]
    for dsp_index, backend_index in slider_map.items()
}
backend_gains = [gain_by_backend_index.get(index, 0.0) for index in range(32)]

def atomic_text_write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(3.0)

def send(command: str) -> None:
    client.sendall((command + "\n").encode("utf-8"))

def read_line() -> str:
    response = bytearray()
    while b"\n" not in response and len(response) < 4096:
        chunk = client.recv(4096)
        if not chunk:
            break
        response.extend(chunk)
    return response.partition(b"\n")[0].decode("utf-8", errors="strict").strip()

def request(command: str) -> str:
    send(command)
    return read_line()

def require_property(command: str) -> str:
    value = request(command)
    if not value or value.startswith("error_"):
        print(
            "EasyEffects live Equalizer property API is unavailable: "
            f"{command} -> {value or '<empty>'}",
            file=sys.stderr,
        )
        raise SystemExit(67)
    return value

try:
    client.connect(socket_path)

    active_preset = request("get_last_loaded_preset:output")
    if not active_preset:
        print("EasyEffects has no active output preset", file=sys.stderr)
        raise SystemExit(66)
    if active_preset in {".", ".."} or "/" in active_preset or "\\" in active_preset:
        print("EasyEffects returned an unsafe active preset name", file=sys.stderr)
        raise SystemExit(66)

    home = pathlib.Path.home()

    def xdg_home(name: str, fallback: pathlib.Path) -> pathlib.Path:
        raw = os.environ.get(name, "")
        if raw:
            path = pathlib.Path(raw)
            if path.is_absolute():
                return path
        return fallback

    if backend == "flatpak":
        app_root = home / ".var/app/com.github.wwmm.easyeffects"
        preset_candidates = [
            app_root / "data/easyeffects/output" / f"{active_preset}.json",
            app_root / "config/easyeffects/output" / f"{active_preset}.json",
        ]
    else:
        data_home = xdg_home("XDG_DATA_HOME", home / ".local/share")
        config_home = xdg_home("XDG_CONFIG_HOME", home / ".config")
        preset_candidates = [
            data_home / "easyeffects/output" / f"{active_preset}.json",
            config_home / "easyeffects/output" / f"{active_preset}.json",
        ]

    preset_path = next((path for path in preset_candidates if path.is_file()), None)
    if preset_path is None:
        print(
            f'active EasyEffects preset "{active_preset}" is not a writable local preset',
            file=sys.stderr,
        )
        raise SystemExit(66)

    original_text = preset_path.read_text(encoding="utf-8")
    try:
        document = json.loads(original_text)
    except json.JSONDecodeError as error:
        print(f"active EasyEffects preset is invalid JSON: {error}", file=sys.stderr)
        raise SystemExit(66)

    output = document.get("output")
    if not isinstance(output, dict):
        print("active EasyEffects preset has no output pipeline", file=sys.stderr)
        raise SystemExit(66)

    order = output.get("plugins_order")
    if not isinstance(order, list) or not all(isinstance(item, str) for item in order):
        print("active EasyEffects preset has an invalid plugins_order", file=sys.stderr)
        raise SystemExit(66)

    eq_key = next(
        (item for item in order if item == "equalizer" or item.startswith("equalizer#")),
        None,
    )
    if eq_key is None:
        print(
            "active EasyEffects preset does not contain an Equalizer in plugins_order",
            file=sys.stderr,
        )
        raise SystemExit(66)

    equalizer = output.get(eq_key)
    if not isinstance(equalizer, dict):
        print("active EasyEffects preset has malformed Equalizer data", file=sys.stderr)
        raise SystemExit(66)

    if eq_key == "equalizer":
        instance_id = "0"
    else:
        instance_id = eq_key.partition("#")[2]
        if not instance_id.isdigit():
            print("active EasyEffects preset has an invalid Equalizer instance id", file=sys.stderr)
            raise SystemExit(66)

    plugin_prefix = f"output:equalizer:{instance_id}"
    require_property(f"get_property:{plugin_prefix}:numBands")
    require_property(f"get_property:{plugin_prefix}:left:band0Gain")
    require_property(f"get_property:{plugin_prefix}:right:band0Gain")

    # Change only the active Equalizer database. No preset reload occurs, so
    # Convolver/Limiter and any unsaved live pipeline state remain untouched.
    send(f"set_property:{plugin_prefix}:bypass:false")
    send(f"set_property:{plugin_prefix}:numBands:32")
    send(f"set_property:{plugin_prefix}:splitChannels:false")
    for index, (frequency, gain) in enumerate(zip(frequencies, backend_gains)):
        for channel in ("left", "right"):
            send(f"set_property:{plugin_prefix}:{channel}:band{index}Frequency:{frequency}")
            send(f"set_property:{plugin_prefix}:{channel}:band{index}Gain:{gain}")

    try:
        if int(float(require_property(f"get_property:{plugin_prefix}:numBands"))) != 32:
            raise ValueError("numBands")
        split_value = require_property(f"get_property:{plugin_prefix}:splitChannels").lower()
        if split_value not in {"false", "0"}:
            raise ValueError("splitChannels")
        for channel in ("left", "right"):
            live_gain = float(require_property(f"get_property:{plugin_prefix}:{channel}:band27Gain"))
            live_frequency = float(require_property(f"get_property:{plugin_prefix}:{channel}:band27Frequency"))
            if not math.isclose(live_gain, backend_gains[27], abs_tol=1e-6):
                raise ValueError(f"{channel} band27 gain")
            if not math.isclose(live_frequency, frequencies[27], abs_tol=1e-6):
                raise ValueError(f"{channel} band27 frequency")
    except (TypeError, ValueError):
        print("EasyEffects did not accept the live Equalizer update", file=sys.stderr)
        raise SystemExit(67)

    # Persist only Equalizer fields into the selected preset. The rest of the
    # preset document and plugins_order remain unchanged in value.
    modern_schema = "#" in eq_key
    for channel in ("left", "right"):
        channel_bands = equalizer.get(channel)
        if not isinstance(channel_bands, dict):
            channel_bands = {}
            equalizer[channel] = channel_bands

        template = next((band for band in channel_bands.values() if isinstance(band, dict)), None)
        if template is None:
            template = {
                "mode": "RLC (BT)" if modern_schema else "Bell",
                "mute": False,
                "q": 1.0,
                "solo": False,
                "width": 1.0,
                "slope": "x1",
            }
            if modern_schema:
                template["type"] = "Bell"

        for index, (frequency, gain) in enumerate(zip(frequencies, backend_gains)):
            band_key = f"band{index}"
            existing = channel_bands.get(band_key)
            band = copy.deepcopy(existing if isinstance(existing, dict) else template)
            band["frequency"] = frequency
            band["gain"] = gain
            channel_bands[band_key] = band

    equalizer["bypass"] = False
    equalizer["num-bands"] = 32
    equalizer["split-channels"] = False

    atomic_text_write(preset_path, json.dumps(document, indent=4) + "\n")

    state = {"gains": gains, "preset": preset_label}
    atomic_text_write(state_path, json.dumps(state, indent=4) + "\n")
finally:
    client.close()
PY
        then
            mv -f "$state_candidate" "$state_file"
        else
            status=$?
            rm -f "$state_candidate"
            exit "$status"
        fi
        ;;

    *)
        printf 'usage: %s {get|apply backend preset gain...}\n' "$0" >&2
        exit 64
        ;;
esac
