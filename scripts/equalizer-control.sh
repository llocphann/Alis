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

    apply|ensure)
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

        topology_stamp="$state_root/topology_sync.json"
        rm -f "$state_candidate"
        if python3 - "$sock" "$state_candidate" "$topology_stamp" "$backend" "$preset" "$@" <<'PY'
import copy
import json
import math
import os
import pathlib
import socket
import sys
import tempfile
import time

socket_path = sys.argv[1]
state_path = pathlib.Path(sys.argv[2])
topology_stamp_path = pathlib.Path(sys.argv[3])
backend = sys.argv[4]
preset_label = sys.argv[5]
raw_gains = sys.argv[6:]

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

POST_EQ_PREFIXES = {
    "autogain",
    "loudness",
    "compressor",
    "multiband_compressor",
    "gate",
    "multiband_gate",
    "deesser",
    "maximizer",
    "limiter",
    "level_meter",
}

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

def reload_preset_pipeline(preset_name: str, target_prefix: str) -> None:
    # Pipeline topology reload only runs when a dedicated Equalizer stage had to
    # be injected or moved relative to speaker-tuning Convolver / Limiter stages.
    send(f"load_preset:output:{preset_name}")
    deadline = time.monotonic() + 1.5
    while True:
        probe = request(f"get_property:{target_prefix}:numBands")
        if probe and not probe.startswith("error_"):
            return
        if time.monotonic() >= deadline:
            return
        time.sleep(0.05)

try:
    client.connect(socket_path)

    active_preset = request("get_last_loaded_preset:output")
    if active_preset and (
        active_preset in {".", ".."} or "/" in active_preset or "\\" in active_preset
    ):
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
        output_dirs = [
            app_root / "data/easyeffects/output",
            app_root / "config/easyeffects/output",
        ]
        autoload_dirs = [
            app_root / "data/easyeffects/autoload/output",
            app_root / "config/easyeffects/autoload/output",
        ]
        rc_path = app_root / "config/easyeffects/db/easyeffectsrc"
    else:
        data_home = xdg_home("XDG_DATA_HOME", home / ".local/share")
        config_home = xdg_home("XDG_CONFIG_HOME", home / ".config")
        output_dirs = [
            data_home / "easyeffects/output",
            config_home / "easyeffects/output",
        ]
        autoload_dirs = [
            data_home / "easyeffects/autoload/output",
            config_home / "easyeffects/autoload/output",
        ]
        rc_path = config_home / "easyeffects/db/easyeffectsrc"

    def is_safe_preset_name(name: str) -> bool:
        return (
            bool(name)
            and name not in {".", ".."}
            and "/" not in name
            and "\\" not in name
        )

    def preset_candidates(name: str):
        return [directory / f"{name}.json" for directory in output_dirs]

    def parse_preset_document(path: pathlib.Path, strict: bool):
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            if strict:
                print(f"active EasyEffects preset is invalid JSON: {error}", file=sys.stderr)
                raise SystemExit(66)
            return None
        if not isinstance(doc, dict):
            if strict:
                print("active EasyEffects preset has no output pipeline", file=sys.stderr)
                raise SystemExit(66)
            return None
        out = doc.get("output")
        if not isinstance(out, dict):
            if strict:
                print("active EasyEffects preset has no output pipeline", file=sys.stderr)
                raise SystemExit(66)
            return None
        ord_list = out.get("plugins_order")
        if not isinstance(ord_list, list) or not all(isinstance(item, str) for item in ord_list):
            if strict:
                print("active EasyEffects preset has an invalid plugins_order", file=sys.stderr)
                raise SystemExit(66)
            return None
        return doc, out, ord_list

    def read_stream_outputs_info() -> tuple[str, list[str] | None, str]:
        if not rc_path.is_file():
            return "", None, ""
        try:
            stat = rc_path.stat()
            lines = rc_path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return "", None, ""
        in_stream_outputs = False
        output_device = ""
        live_plugins = None
        raw_plugins = ""
        for raw_line in lines:
            line = raw_line.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            if line.startswith("[") and line.endswith("]"):
                group = line[1:-1].split("][", 1)[0].strip()
                in_stream_outputs = group == "StreamOutputs"
                continue
            if in_stream_outputs and "=" in line:
                key, _, value = line.partition("=")
                key_name = key.split("[", 1)[0].strip()
                cleaned = value.strip()
                if (
                    len(cleaned) >= 2
                    and cleaned[0] == cleaned[-1]
                    and cleaned[0] in {'"', "'"}
                ):
                    cleaned = cleaned[1:-1]
                if key_name == "outputDevice":
                    output_device = cleaned
                elif key_name == "plugins":
                    raw_plugins = cleaned
                    live_plugins = [
                        item.strip()
                        for item in cleaned.split(",")
                        if item.strip()
                    ]
        rc_sig = f"{stat.st_mtime_ns}:{raw_plugins}" if live_plugins is not None else ""
        return output_device, live_plugins, rc_sig

    stream_output_device, live_plugins, rc_sig = read_stream_outputs_info()

    def resolve_autoload_preset():
        if stream_output_device:
            for autoload_dir in autoload_dirs:
                if not autoload_dir.is_dir():
                    continue
                for autoload_file in sorted(autoload_dir.glob("*.json")):
                    try:
                        entry = json.loads(autoload_file.read_text(encoding="utf-8"))
                    except (OSError, json.JSONDecodeError):
                        continue
                    if not isinstance(entry, dict) or entry.get("device") != stream_output_device:
                        continue
                    preset_name = str(entry.get("preset-name") or "").strip()
                    if not is_safe_preset_name(preset_name):
                        continue
                    candidate_path = next(
                        (p for p in preset_candidates(preset_name) if p.is_file()),
                        None,
                    )
                    if candidate_path is None:
                        continue
                    parsed = parse_preset_document(candidate_path, strict=False)
                    if parsed is not None and len(parsed[2]) > 0:
                        return candidate_path, parsed[0], parsed[1], parsed[2]

        kernel_raw = request("get_property:output:convolver:0:kernelName")
        if kernel_raw and not kernel_raw.startswith("error_"):
            kernel_stem = pathlib.Path(kernel_raw).stem
            matches = []
            seen_stems = set()
            for directory in output_dirs:
                if not directory.is_dir():
                    continue
                for candidate_path in sorted(directory.glob("*.json")):
                    stem = candidate_path.stem
                    if stem in seen_stems:
                        continue
                    if (
                        kernel_raw == stem
                        or kernel_raw.startswith(stem + "-")
                        or kernel_stem == stem
                        or kernel_stem.startswith(stem + "-")
                    ):
                        seen_stems.add(stem)
                        exact = 0 if (kernel_raw == stem or kernel_stem == stem) else 1
                        matches.append(((exact, -len(stem), stem), candidate_path))
            matches.sort(key=lambda item: item[0])
            for _, candidate_path in matches:
                parsed = parse_preset_document(candidate_path, strict=False)
                if parsed is not None and len(parsed[2]) > 0:
                    return candidate_path, parsed[0], parsed[1], parsed[2]
        return None

    def is_dolby_doc(doc: dict, name: str) -> bool:
        gen = str(doc.get("_generator", "")).strip().lower()
        return gen.startswith("dolby_to_easyeffects.py") or name.lower().startswith("dolby-")

    def is_speaker_tuning_doc(doc: dict, name: str) -> bool:
        gen = str(doc.get("_generator", "")).strip().lower()
        return is_dolby_doc(doc, name) or "speaker" in gen or "autoeq" in gen

    def is_protected_calibration_eq(doc: dict, preset_stem: str, out_dict: dict, ord_list: list[str], key: str) -> bool:
        stage = out_dict.get(key)
        if not isinstance(stage, dict):
            return False
        if doc.get("_alis_dsp_eq_key") == key:
            return False
        if is_dolby_doc(doc, preset_stem) and key in {"equalizer#0", "equalizer#1"}:
            return True
        if len(ord_list) > 1:
            if stage.get("split-channels") is True:
                return True
            for channel in ("left", "right"):
                bands = stage.get(channel)
                if isinstance(bands, dict):
                    for band in bands.values():
                        if isinstance(band, dict) and band.get("type", "Bell") != "Bell":
                            return True
        return False

    def is_equalizer_key(item: str) -> bool:
        return item == "equalizer" or item.startswith("equalizer#")

    def parse_eq_instance_id(key: str) -> str:
        if key == "equalizer":
            return "0"
        return key.partition("#")[2]

    def build_graphic_equalizer_stage(band_gains: list[float]) -> dict:
        left = {}
        right = {}
        for idx, (frequency, gain) in enumerate(zip(frequencies, band_gains)):
            band_obj = {
                "frequency": float(frequency),
                "gain": float(gain),
                "mode": "RLC (BT)",
                "mute": False,
                "q": 1.0,
                "slope": "x1",
                "solo": False,
                "type": "Bell",
                "width": 4.0,
            }
            left[f"band{idx}"] = dict(band_obj)
            right[f"band{idx}"] = dict(band_obj)
        return {
            "balance": 0.0,
            "bypass": False,
            "input-gain": 0.0,
            "left": left,
            "mode": "IIR",
            "num-bands": 32,
            "output-gain": 0.0,
            "pitch-left": 0.0,
            "pitch-right": 0.0,
            "right": right,
            "split-channels": False,
        }

    def apply_eq_fields_to_stage(equalizer_dict: dict, eq_stage_key: str) -> None:
        modern_schema = "#" in eq_stage_key
        for channel in ("left", "right"):
            channel_bands = equalizer_dict.get(channel)
            if not isinstance(channel_bands, dict):
                channel_bands = {}
                equalizer_dict[channel] = channel_bands

            template = {
                "mode": "RLC (BT)" if modern_schema else "Bell",
                "mute": False,
                "q": 1.0,
                "solo": False,
                "width": 4.0 if modern_schema else 1.0,
                "slope": "x1",
            }
            if modern_schema:
                template["type"] = "Bell"
            first_band = next(
                (band for band in channel_bands.values() if isinstance(band, dict)),
                None,
            )
            if first_band is not None:
                candidate = copy.deepcopy(first_band)
                candidate["slope"] = "x1"
                if modern_schema or "type" in candidate:
                    candidate["type"] = "Bell"
                template = candidate

            for index, (frequency, gain) in enumerate(zip(frequencies, backend_gains)):
                band_key = f"band{index}"
                existing = channel_bands.get(band_key)
                band = copy.deepcopy(existing if isinstance(existing, dict) else template)
                band["slope"] = "x1"
                if modern_schema or "type" in band:
                    band["type"] = "Bell"
                band["frequency"] = frequency
                band["gain"] = gain
                channel_bands[band_key] = band

        equalizer_dict["bypass"] = False
        equalizer_dict["num-bands"] = 32
        equalizer_dict["split-channels"] = False

    def compute_eq_bounds(order_without_eq: list[str], protected_keys: set[str]) -> tuple[int, int]:
        # Place tonal shaping EQ after linear speaker correction (convolver &
        # calibration PEQs) and before dynamic excursion limiters / compressors.
        min_idx = 0
        for idx, item in enumerate(order_without_eq):
            if item.split("#", 1)[0] == "convolver" or item in protected_keys:
                min_idx = idx + 1
        max_idx = len(order_without_eq)
        for idx in range(min_idx, len(order_without_eq)):
            if order_without_eq[idx].split("#", 1)[0] in POST_EQ_PREFIXES:
                max_idx = idx
                break
        return min_idx, max_idx

    def provision_preset_eq(doc: dict, preset_stem: str, out_dict: dict, ord_list: list[str], preferred_key: str | None = None):
        protected_keys = {
            item
            for item in ord_list
            if is_equalizer_key(item)
            and is_protected_calibration_eq(doc, preset_stem, out_dict, ord_list, item)
        }
        chosen_key = next(
            (
                item
                for item in ord_list
                if is_equalizer_key(item) and item not in protected_keys
            ),
            None,
        )
        topology_changed = False
        if chosen_key is None:
            if preferred_key and preferred_key not in protected_keys and preferred_key not in out_dict:
                chosen_key = preferred_key
            else:
                used_ids = set()
                for k in list(out_dict.keys()) + list(ord_list):
                    if is_equalizer_key(k):
                        raw_id = parse_eq_instance_id(k)
                        if raw_id.isdigit():
                            used_ids.add(int(raw_id))
                next_id = 0
                while next_id in used_ids:
                    next_id += 1
                chosen_key = f"equalizer#{next_id}"
            out_dict[chosen_key] = build_graphic_equalizer_stage(backend_gains)
            topology_changed = True

        if not isinstance(out_dict.get(chosen_key), dict):
            print("active EasyEffects preset has malformed Equalizer data", file=sys.stderr)
            raise SystemExit(66)

        order_without_eq = [item for item in ord_list if item != chosen_key]
        min_idx, max_idx = compute_eq_bounds(order_without_eq, protected_keys)
        if chosen_key not in ord_list:
            order_without_eq.insert(max_idx, chosen_key)
            ord_list[:] = order_without_eq
            topology_changed = True
        elif protected_keys:
            cur_idx = ord_list.index(chosen_key)
            if cur_idx < min_idx or cur_idx > max_idx:
                order_without_eq.insert(max_idx, chosen_key)
                ord_list[:] = order_without_eq
                topology_changed = True

        if protected_keys:
            doc["_alis_dsp_eq_key"] = chosen_key

        return chosen_key, protected_keys, topology_changed

    preset_path = None
    document = {}
    output = {}
    order = []

    if active_preset:
        preset_path = next(
            (path for path in preset_candidates(active_preset) if path.is_file()),
            None,
        )
        if preset_path is None:
            print(
                f'active EasyEffects preset "{active_preset}" is not a writable local preset',
                file=sys.stderr,
            )
            raise SystemExit(66)
        document, output, order = parse_preset_document(preset_path, strict=True)

    if not order:
        resolved = resolve_autoload_preset()
        if resolved is not None:
            preset_path, document, output, order = resolved
        elif preset_path is not None and preset_path.stem.lower() == "nothing":
            alis_eq_path = preset_path.parent / "Alis-EQ.json"
            parsed_alis = parse_preset_document(alis_eq_path, strict=False) if alis_eq_path.is_file() else None
            if parsed_alis is not None and len(parsed_alis[2]) > 0:
                preset_path = alis_eq_path
                document, output, order = parsed_alis
            else:
                preset_path = alis_eq_path
                document = {
                    "_generator": "alis-equalizer",
                    "_alis_dsp_eq_key": "equalizer#0",
                    "output": {
                        "blocklist": [],
                        "plugins_order": ["equalizer#0"],
                        "equalizer#0": build_graphic_equalizer_stage(backend_gains),
                    },
                }
                output = document["output"]
                order = output["plugins_order"]
        elif not active_preset:
            print("EasyEffects has no active output preset", file=sys.stderr)
            raise SystemExit(66)

    if preset_path is None:
        print("EasyEffects has no active output preset", file=sys.stderr)
        raise SystemExit(66)

    target_preset_name = preset_path.stem
    eq_key, protected_eq_keys, preset_topology_changed = provision_preset_eq(
        document, target_preset_name, output, order
    )

    equalizer = output.get(eq_key)
    instance_id = parse_eq_instance_id(eq_key)
    if not instance_id.isdigit():
        print("active EasyEffects preset has an invalid Equalizer instance id", file=sys.stderr)
        raise SystemExit(66)

    plugin_prefix = f"output:equalizer:{instance_id}"

    def is_live_pipeline_valid() -> bool:
        if target_preset_name != active_preset:
            # e.g. Nothing autoload fallback mismatch; only reload if plugin missing
            # in live pipeline when speaker preset was NOT loaded. Wait: if active_preset
            # was "Alis-EQ" newly created from Nothing, force load.
            if active_preset.lower() == "nothing" and target_preset_name == "Alis-EQ":
                return False
        probe = request(f"get_property:{plugin_prefix}:numBands")
        if not probe or probe.startswith("error_"):
            return False
        if live_plugins is not None:
            if eq_key not in live_plugins:
                return False
            if protected_eq_keys:
                eq_live_idx = live_plugins.index(eq_key)
                order_without_eq = [item for item in order if item != eq_key]
                min_idx, max_idx = compute_eq_bounds(order_without_eq, protected_eq_keys)
                pre_stages = {
                    item
                    for idx, item in enumerate(order_without_eq)
                    if idx < min_idx
                }
                post_stages = {
                    item
                    for idx, item in enumerate(order_without_eq)
                    if idx >= max_idx
                }
                order_invalid = any(
                    (s in live_plugins and live_plugins.index(s) > eq_live_idx)
                    for s in pre_stages
                ) or any(
                    (s in live_plugins and live_plugins.index(s) < eq_live_idx)
                    for s in post_stages
                )
                if order_invalid:
                    already_synced_sig = ""
                    if topology_stamp_path.is_file():
                        try:
                            stamp = json.loads(topology_stamp_path.read_text(encoding="utf-8"))
                            if isinstance(stamp, dict) and stamp.get("preset") == target_preset_name:
                                already_synced_sig = str(stamp.get("rc_sig") or "")
                        except (OSError, json.JSONDecodeError):
                            pass
                    if not rc_sig or already_synced_sig != rc_sig:
                        return False
        return True

    def sync_sibling_speaker_presets() -> None:
        if not is_speaker_tuning_doc(document, target_preset_name):
            return
        parent_dir = preset_path.parent
        for sibling_path in sorted(parent_dir.glob("*.json")):
            if sibling_path == preset_path:
                continue
            parsed = parse_preset_document(sibling_path, strict=False)
            if parsed is None:
                continue
            sib_doc, sib_out, sib_order = parsed
            if not sib_order:
                continue
            if not is_speaker_tuning_doc(sib_doc, sibling_path.stem):
                continue
            before_text = sibling_path.read_text(encoding="utf-8")
            sib_eq_key, _, _ = provision_preset_eq(
                sib_doc, sibling_path.stem, sib_out, sib_order, preferred_key=eq_key
            )
            sib_eq = sib_out.get(sib_eq_key)
            if not isinstance(sib_eq, dict):
                continue
            apply_eq_fields_to_stage(sib_eq, sib_eq_key)
            after_text = json.dumps(sib_doc, indent=4) + "\n"
            if after_text != before_text:
                atomic_text_write(sibling_path, after_text)

    def write_preset_document(path: pathlib.Path, doc_obj: dict) -> None:
        atomic_text_write(path, json.dumps(doc_obj, indent=4) + "\n")

    def reload_topology_if_needed() -> bool:
        if not (preset_topology_changed or not is_live_pipeline_valid()):
            return False
        apply_eq_fields_to_stage(equalizer, eq_key)
        write_preset_document(preset_path, document)
        sync_sibling_speaker_presets()
        reload_preset_pipeline(target_preset_name, plugin_prefix)
        if rc_sig:
            atomic_text_write(
                topology_stamp_path,
                json.dumps({"preset": target_preset_name, "rc_sig": rc_sig}) + "\n",
            )
        return True

    needs_topology_reload = reload_topology_if_needed()

    require_property(f"get_property:{plugin_prefix}:numBands")
    require_property(f"get_property:{plugin_prefix}:left:band0Gain")
    require_property(f"get_property:{plugin_prefix}:right:band0Gain")
    band0_type_probe = request(f"get_property:{plugin_prefix}:left:band0Type")
    supports_band_type = band0_type_probe.isdigit()

    # Change only the active Equalizer database. When the topology already matches
    # (the normal steady-state case), no preset reload occurs, so Convolver,
    # Limiter, and unsaved live state remain untouched with zero audio glitch.
    send(f"set_property:{plugin_prefix}:bypass:false")
    send(f"set_property:{plugin_prefix}:numBands:32")
    send(f"set_property:{plugin_prefix}:splitChannels:false")
    for index, (frequency, gain) in enumerate(zip(frequencies, backend_gains)):
        for channel in ("left", "right"):
            if supports_band_type:
                send(f"set_property:{plugin_prefix}:{channel}:band{index}Type:1")
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

    # Persist only Equalizer fields into the selected preset (plus sibling
    # speaker-tuning profiles so preset switches keep the user's EQ curve).
    apply_eq_fields_to_stage(equalizer, eq_key)
    atomic_text_write(preset_path, json.dumps(document, indent=4) + "\n")
    if not needs_topology_reload:
        sync_sibling_speaker_presets()

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
