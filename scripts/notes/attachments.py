#!/usr/bin/env python3
"""Persist Quick Notes images byte-for-byte; keep binary clipboard out of QML."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
import time
from urllib.parse import unquote, urlsplit

LIMIT = 32 * 1024 * 1024
MIMES = ("image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp", "image/tiff")


def collect(command, limit=LIMIT, timeout=5):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        output = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + timeout
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise ValueError("Clipboard read timed out")
                data = os.read(process.stdout.fileno(), min(65536, limit + 1 - len(output)))
                if not data:
                    break
                output.extend(data)
                if len(output) > limit:
                    raise ValueError("Clipboard contents exceed 32 MiB")
        if process.wait(timeout=max(.1, deadline - time.monotonic())):
            raise ValueError("Clipboard is unavailable")
        return bytes(output)
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.kill()
            process.wait()


def image_extension(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "webp"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if data.startswith(b"BM"):
        return "bmp"
    if data[:4] in (b"II*\x00", b"MM\x00*"):
        return "tiff"
    raise ValueError("Choose a PNG, JPEG, WebP, GIF, BMP or TIFF image")


def persist(root, data):
    if not data or len(data) > LIMIT:
        raise ValueError("Image is empty or exceeds 32 MiB")
    extension = image_extension(data)
    directory = Path(root).expanduser()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory = directory.resolve(strict=True)
    path = directory / (hashlib.sha256(data).hexdigest() + "." + extension)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        if path.is_symlink() or path.read_bytes() != data:
            raise ValueError("Stored image collision; the original was preserved")
    else:
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
        except OSError:
            path.unlink(missing_ok=True)
            raise
        directory_fd = os.open(directory, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    return {"ok": True, "kind": "image", "url": path.as_uri(),
            "text": "\n![Image](" + path.as_uri() + ")\n"}


def import_image(root, source):
    url = urlsplit(source)
    if url.scheme:
        if url.scheme != "file" or url.netloc not in ("", "localhost"):
            raise ValueError("Choose a local image file")
        source = unquote(url.path)
    path = Path(source).expanduser()
    if not path.is_file() or path.stat().st_size > LIMIT:
        raise ValueError("Image is missing or exceeds 32 MiB")
    with path.open("rb") as stream:
        data = stream.read(LIMIT + 1)
    return persist(root, data)


def _paste_cmd(*args):
    dispatch = Path(__file__).resolve().parents[1] / "native-dispatch"
    if (
        os.environ.get("ALIS_NATIVE_MODE", "auto") != "legacy"
        and dispatch.is_file()
        and os.access(dispatch, os.X_OK)
        and os.environ.get("WAYLAND_DISPLAY")
    ):
        return [str(dispatch), "clipboard", "paste", *args]
    return ["wl-paste", *args]


def _collect_paste(*args, limit=LIMIT):
    primary = _paste_cmd(*args)
    try:
        return collect(primary, limit=limit)
    except (OSError, ValueError, subprocess.SubprocessError):
        if primary[0] != "wl-paste":
            return collect(["wl-paste", *args], limit=limit)
        raise


def paste(root):
    types = _collect_paste("--list-types", limit=8192).decode("utf-8").splitlines()
    for mime in MIMES:
        if mime in types:
            return persist(root, _collect_paste("--no-newline", "--type", mime))
    # Request actual text; never decode an image offer as UTF-8.
    data = _collect_paste("--no-newline", "--type", "text")
    return {"ok": True, "kind": "text", "text": data.decode("utf-8")}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--import-image", default="")
    args = parser.parse_args()
    try:
        result = import_image(args.root, args.import_image) if args.import_image else paste(args.root)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
