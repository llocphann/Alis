#!/usr/bin/env python3
"""Small stdlib-only MPD client for Alis LocalMusic.

MPD owns the library, saved playlists and playback queue. Alis uses this
helper only for database/queue operations that MPRIS does not expose; transport
controls are routed through mpd-mpris whenever that MPRIS player is available.
"""
from __future__ import annotations

import hashlib
import json
import os
import socket
import sys
from pathlib import Path
from typing import Any

ART_NAMES = ("cover", "folder", "front", "album", "artwork")
ART_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".avif")
ART_CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "alis" / "music-covers"


class MpdError(RuntimeError):
    pass


def _quote(value: Any) -> str:
    text = str(value)
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _load_json_list_argument(value: str) -> list[Any]:
    """Load a JSON list from argv or from @/path to avoid exec argv limits."""
    source = str(value)
    if source.startswith("@"):
        source = Path(source[1:]).read_text(encoding="utf-8")
    payload = json.loads(source)
    if not isinstance(payload, list):
        raise MpdError("invalid_list_payload")
    return payload


class MpdClient:
    def __init__(self, host: str, port: int, timeout: float = 2.0) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: socket.socket | None = None
        self.stream = None

    def __enter__(self) -> "MpdClient":
        if self.host.startswith("/"):
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(self.timeout)
            sock.connect(self.host)
        else:
            sock = socket.create_connection((self.host, self.port), self.timeout)
        self.sock = sock
        self.stream = sock.makefile("rwb", buffering=0)
        greeting = self.stream.readline().decode("utf-8", errors="replace").strip()
        if not greeting.startswith("OK MPD "):
            raise MpdError("invalid_greeting")
        return self

    def __exit__(self, *_exc: Any) -> None:
        try:
            if self.stream is not None:
                self.stream.close()
        finally:
            if self.sock is not None:
                self.sock.close()

    def command(self, name: str, *args: Any) -> list[str]:
        if self.stream is None:
            raise MpdError("not_connected")
        line = name
        if args:
            line += " " + " ".join(_quote(arg) for arg in args)
        self.stream.write((line + "\n").encode("utf-8"))
        result: list[str] = []
        while True:
            raw = self.stream.readline()
            if not raw:
                raise MpdError("connection_closed")
            text = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            if text == "OK":
                return result
            if text.startswith("ACK "):
                raise MpdError(text)
            result.append(text)

    def binary(self, name: str, uri: str) -> tuple[bytes, str] | None:
        """Read MPD albumart/readpicture binary chunks without a second backend."""
        if self.stream is None:
            raise MpdError("not_connected")

        data = bytearray()
        mime = ""
        offset = 0

        def read_exact(size: int) -> bytes:
            chunks = bytearray()
            while len(chunks) < size:
                chunk = self.stream.read(size - len(chunks))
                if not chunk:
                    raise MpdError("connection_closed")
                chunks.extend(chunk)
            return bytes(chunks)

        while True:
            line = f"{name} {_quote(uri)} {_quote(offset)}\n"
            self.stream.write(line.encode("utf-8"))
            total_size: int | None = None
            chunk_size = 0

            while True:
                raw = self.stream.readline()
                if not raw:
                    raise MpdError("connection_closed")
                if raw.startswith(b"ACK "):
                    if offset == 0:
                        return None
                    raise MpdError(raw.decode("utf-8", errors="replace").strip())

                text = raw.decode("utf-8", errors="replace").rstrip("\r\n")
                if text == "OK":
                    break
                if ": " not in text:
                    continue
                key, value = text.split(": ", 1)
                lower = key.lower()
                if lower == "size":
                    try:
                        total_size = int(value)
                    except ValueError:
                        total_size = None
                elif lower == "type":
                    mime = value.strip()
                elif lower == "binary":
                    try:
                        chunk_size = max(0, int(value))
                    except ValueError as exc:
                        raise MpdError("invalid_binary_size") from exc
                    if chunk_size > 0:
                        data.extend(read_exact(chunk_size))
                        terminator = read_exact(1)
                        if terminator != b"\n":
                            raise MpdError("invalid_binary_terminator")

            if chunk_size <= 0 or total_size is None or len(data) >= total_size:
                break
            offset = len(data)

        if not data:
            return None
        return bytes(data), mime


def _pairs(lines: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in lines:
        if ": " not in line:
            continue
        key, value = line.split(": ", 1)
        result[key.lower()] = value
    return result


def _records(lines: list[str], marker: str = "file") -> list[dict[str, Any]]:
    marker = marker.lower()
    records: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for line in lines:
        if ": " not in line:
            continue
        key, value = line.split(": ", 1)
        lower = key.lower()
        if lower == marker:
            if current is not None:
                records.append(current)
            current = {marker: value}
            continue
        if current is None:
            continue
        previous = current.get(lower)
        if previous is None:
            current[lower] = value
        elif isinstance(previous, list):
            previous.append(value)
        else:
            current[lower] = [previous, value]
    if current is not None:
        records.append(current)
    return records


def _first(record: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = record.get(key.lower())
        if isinstance(value, list):
            value = value[0] if value else ""
        text = str(value or "").strip()
        if text:
            return text
    return ""


def _number(value: Any, fallback: float = 0.0) -> float:
    try:
        return float(str(value).split(":", 1)[0])
    except (TypeError, ValueError):
        return fallback


def _int_prefix(value: Any) -> int:
    try:
        return int(str(value or "0").split("/", 1)[0])
    except ValueError:
        return 0


def _local_path(uri: str, music_root: str) -> str:
    if "://" in uri:
        return uri
    candidate = Path(os.path.expanduser(uri))
    if candidate.is_absolute():
        return str(candidate)
    if music_root:
        return str((Path(os.path.expanduser(music_root)) / candidate).resolve())
    return uri


def _folder_art(path_text: str) -> str:
    if not path_text or "://" in path_text:
        return ""
    path = Path(path_text)
    directory = path.parent
    try:
        entries = {entry.name.lower(): entry for entry in directory.iterdir() if entry.is_file()}
    except OSError:
        return ""
    for base in ART_NAMES:
        for ext in ART_EXTENSIONS:
            candidate = entries.get(base + ext)
            if candidate is not None:
                try:
                    return candidate.resolve().as_uri()
                except ValueError:
                    return str(candidate.resolve())
    return ""


def _art_cache_key(track: dict[str, Any]) -> str:
    album_artist = str(track.get("albumArtist") or track.get("artist") or "").strip()
    album = str(track.get("album") or "").strip()
    folder = str(track.get("folder") or "").strip()
    uri = str(track.get("uri") or "").strip()
    if album:
        identity = ("album", album_artist, album, folder)
    else:
        identity = ("folder", folder or str(Path(uri).parent))
    payload = "\x1f".join(identity).encode("utf-8", errors="replace")
    return hashlib.sha256(payload).hexdigest()


def _cached_art(track: dict[str, Any]) -> str:
    key = _art_cache_key(track)
    try:
        matches = sorted(ART_CACHE_DIR.glob(key + ".*"))
    except OSError:
        return ""
    for candidate in matches:
        if not candidate.is_file() or candidate.stat().st_size <= 0:
            continue
        try:
            return candidate.resolve().as_uri()
        except ValueError:
            return str(candidate.resolve())
    return ""


def _art_extension(data: bytes, mime: str) -> str:
    value = mime.lower().strip()
    if "png" in value or data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if "webp" in value or (len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP"):
        return ".webp"
    if "gif" in value or data.startswith((b"GIF87a", b"GIF89a")):
        return ".gif"
    return ".jpg"


def _write_cached_art(track: dict[str, Any], data: bytes, mime: str) -> str:
    if not data:
        return ""
    ART_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    key = _art_cache_key(track)
    target = ART_CACHE_DIR / (key + _art_extension(data, mime))
    temp = target.with_suffix(target.suffix + ".tmp")
    temp.write_bytes(data)
    os.replace(temp, target)
    try:
        return target.resolve().as_uri()
    except ValueError:
        return str(target.resolve())


def _fetch_mpd_art(client: MpdClient, uri: str) -> tuple[bytes, str] | None:
    if not uri:
        return None
    for command in ("albumart", "readpicture"):
        try:
            payload = client.binary(command, uri)
        except (MpdError, OSError):
            payload = None
        if payload is not None and payload[0]:
            return payload
    return None


def _populate_library_art(client: MpdClient, tracks: list[dict[str, Any]]) -> None:
    """Resolve one MPD cover per album/folder group and cache it for the UI."""
    groups: dict[str, list[dict[str, Any]]] = {}
    for track in tracks:
        if track.get("art"):
            continue
        cached = _cached_art(track)
        if cached:
            track["art"] = cached
            continue
        groups.setdefault(_art_cache_key(track), []).append(track)

    for group in groups.values():
        representative = group[0]
        payload = _fetch_mpd_art(client, str(representative.get("uri") or ""))
        if payload is None:
            continue
        try:
            art_url = _write_cached_art(representative, payload[0], payload[1])
        except OSError:
            continue
        if not art_url:
            continue
        for track in group:
            track["art"] = art_url


def _track(record: dict[str, Any], music_root: str) -> dict[str, Any]:
    uri = _first(record, "file")
    path = _local_path(uri, music_root)
    title = _first(record, "title") or Path(uri).stem.replace("_", " ").strip()
    artist = _first(record, "artist", "albumartist")
    album = _first(record, "album")
    duration = _number(_first(record, "duration", "time"))
    folder = str(Path(uri).parent)
    if folder == ".":
        folder = ""
    track = {
        "uri": uri,
        "path": path,
        "title": title,
        "artist": artist,
        "album": album,
        "albumArtist": _first(record, "albumartist"),
        "duration": round(duration, 3),
        "track": _int_prefix(_first(record, "track")),
        "disc": _int_prefix(_first(record, "disc")),
        "genre": _first(record, "genre"),
        "date": _first(record, "date"),
        "folder": folder,
        "art": "",
        "queueId": _int_prefix(_first(record, "id")),
        "queuePos": _int_prefix(_first(record, "pos")),
    }
    track["art"] = _folder_art(path) or _cached_art(track)
    return track


def _music_root(client: MpdClient, override: str) -> str:
    if override:
        return os.path.expanduser(override)
    try:
        config = _pairs(client.command("config"))
    except MpdError:
        return ""
    return os.path.expanduser(config.get("music_directory", ""))


def _status_payload(client: MpdClient, music_root: str) -> dict[str, Any]:
    status = _pairs(client.command("status"))
    if status.get("consume") == "1":
        try:
            client.command("consume", 0)
            status["consume"] = "0"
        except MpdError:
            pass
    current_records = _records(client.command("currentsong"))
    queue_records = _records(client.command("playlistinfo"))
    current = _track(current_records[0], music_root) if current_records else None
    queue = [_track(record, music_root) for record in queue_records]
    return {
        "connected": True,
        "status": status,
        "current": current,
        "queue": queue,
    }


def snapshot(client: MpdClient, override_root: str, include_folders: bool = True) -> dict[str, Any]:
    music_root = _music_root(client, override_root)
    library_records = _records(client.command("listallinfo"))
    tracks = [_track(record, music_root) for record in library_records]
    tracks.sort(
        key=lambda item: (
            str(item["artist"]).casefold(),
            str(item["album"]).casefold(),
            int(item["disc"] or 0),
            int(item["track"] or 0),
            str(item["title"]).casefold(),
            str(item["uri"]).casefold(),
        )
    )
    _populate_library_art(client, tracks)

    playlist_names = [
        value
        for key, value in (
            line.split(": ", 1)
            for line in client.command("listplaylists")
            if ": " in line
        )
        if key.lower() == "playlist"
    ]
    playlists: list[dict[str, Any]] = []
    for name in playlist_names:
        try:
            items = [_track(record, music_root) for record in _records(client.command("listplaylistinfo", name))]
        except MpdError:
            continue
        playlists.append(
            {
                "id": "mpd:" + name,
                "name": name,
                "kind": "playlist",
                "tracks": items,
            }
        )
    playlists.sort(key=lambda item: str(item["name"]).casefold())

    # The internal shell route does not consume the duplicate folder tree.
    if include_folders:
        folders_map: dict[str, list[dict[str, Any]]] = {}
        for item in tracks:
            folder = str(item.get("folder", ""))
            if folder:
                folders_map.setdefault(folder, []).append(item)
        folders = [
            {
                "id": "folder:" + folder,
                "name": Path(folder).name or folder,
                "subtitle": folder,
                "kind": "folder",
                "tracks": values,
            }
            for folder, values in sorted(folders_map.items(), key=lambda pair: pair[0].casefold())
            if len(values) >= 2
        ]

    payload = _status_payload(client, music_root)
    payload.update(
        {
            "musicRoot": music_root,
            "tracks": tracks,
            "playlists": playlists,
        }
    )
    if include_folders:
        payload["folders"] = folders
    return payload


def replace_queue(client: MpdClient, uris: list[str], index: int) -> None:
    if not uris:
        raise MpdError("empty_queue")
    client.command("clear")
    for uri in uris:
        client.command("add", uri)
    client.command("play", max(0, min(index, len(uris) - 1)))


def enqueue_track(client: MpdClient, uri: str, play_now: bool) -> None:
    if not uri:
        raise MpdError("empty_uri")
    response = _pairs(client.command("addid", uri))
    song_id = response.get("id", "")
    if play_now:
        if song_id:
            client.command("playid", song_id)
        else:
            status = _pairs(client.command("status"))
            queue_length = int(status.get("playlistlength", "1") or "1")
            client.command("play", max(0, queue_length - 1))


def enqueue_many(client: MpdClient, uris: list[str]) -> None:
    for uri in uris:
        value = str(uri).strip()
        if value:
            client.command("add", value)


def _playlist_names(client: MpdClient) -> list[str]:
    names: list[str] = []
    for line in client.command("listplaylists"):
        if ": " not in line:
            continue
        key, value = line.split(": ", 1)
        if key.lower() == "playlist" and value.strip():
            names.append(value.strip())
    return names


def mutate_playlist(
    client: MpdClient,
    name: str,
    uris: list[str],
    create_only: bool,
) -> None:
    playlist_name = str(name).strip()
    if not playlist_name or "\n" in playlist_name or "\r" in playlist_name:
        raise MpdError("invalid_playlist_name")

    valid_uris = list(dict.fromkeys(str(uri).strip() for uri in uris if str(uri).strip()))
    if not valid_uris:
        raise MpdError("empty_playlist_selection")

    if create_only:
        folded = playlist_name.casefold()
        if any(existing.casefold() == folded for existing in _playlist_names(client)):
            raise MpdError("playlist_exists")

    # MPD creates the stored playlist on the first playlistadd when needed.
    for uri in valid_uris:
        client.command("playlistadd", playlist_name, uri)


ALLOWED_COMMANDS = {
    "next",
    "previous",
    "stop",
    "play",
    "pause",
    "seekcur",
    "setvol",
    "random",
    "repeat",
    "single",
    "consume",
    "update",
    "delete",
    "deleteid",
    "clear",
}


def main() -> int:
    if len(sys.argv) < 4:
        return 2
    mode = sys.argv[1]
    host = sys.argv[2]
    try:
        port = int(sys.argv[3])
    except ValueError:
        return 2

    try:
        with MpdClient(host, port) as client:
            if mode == "snapshot":
                root = sys.argv[4] if len(sys.argv) > 4 else ""
                include_folders = not (len(sys.argv) > 5 and sys.argv[5] == "--lean")
                print(json.dumps(snapshot(client, root, include_folders), ensure_ascii=False, separators=(",", ":")))
                return 0
            if mode == "status":
                root = sys.argv[4] if len(sys.argv) > 4 else ""
                music_root = _music_root(client, root)
                payload = _status_payload(client, music_root)
                payload["musicRoot"] = music_root
                print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
                return 0
            if mode == "queue" and len(sys.argv) > 5:
                index = int(sys.argv[4])
                uris = _load_json_list_argument(sys.argv[5])
                replace_queue(client, [str(uri) for uri in uris], index)
                print('{"ok":true}')
                return 0
            if mode == "enqueue" and len(sys.argv) > 6:
                override_root = sys.argv[4]
                play_now = sys.argv[5] == "1"
                uri = sys.argv[6]
                enqueue_track(client, uri, play_now)
                music_root = _music_root(client, override_root)
                payload = _status_payload(client, music_root)
                payload["musicRoot"] = music_root
                print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
                return 0
            if mode == "enqueue-many" and len(sys.argv) > 5:
                override_root = sys.argv[4]
                uris = _load_json_list_argument(sys.argv[5])
                enqueue_many(client, [str(uri) for uri in uris])
                music_root = _music_root(client, override_root)
                payload = _status_payload(client, music_root)
                payload["musicRoot"] = music_root
                print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
                return 0
            if mode in ("playlist-create", "playlist-add") and len(sys.argv) > 5:
                name = sys.argv[4]
                uris = _load_json_list_argument(sys.argv[5])
                mutate_playlist(
                    client,
                    name,
                    [str(uri) for uri in uris],
                    create_only=mode == "playlist-create",
                )
                print('{"ok":true}')
                return 0
            if mode == "command" and len(sys.argv) > 5:
                name = sys.argv[4]
                if name not in ALLOWED_COMMANDS:
                    return 2
                args = json.loads(sys.argv[5])
                if not isinstance(args, list):
                    return 2
                if name == "repeat" and len(args) >= 2:
                    client.command("repeat", args[0])
                    lines = client.command("single", args[1])
                    print(json.dumps({"ok": True, "lines": lines}, ensure_ascii=False, separators=(",", ":")))
                    return 0
                lines = client.command(name, *args)
                print(json.dumps({"ok": True, "lines": lines}, ensure_ascii=False, separators=(",", ":")))
                return 0
    except (OSError, MpdError, json.JSONDecodeError, ValueError) as exc:
        print(json.dumps({"connected": False, "error": str(exc)}, ensure_ascii=False, separators=(",", ":")))
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
