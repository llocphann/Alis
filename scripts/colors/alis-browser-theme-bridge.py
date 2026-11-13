#!/usr/bin/env python3
"""
alis-browser-theme-bridge.py — Event-driven loopback SSE bridge (127.0.0.1:43821)
for instant zero-restart theme updates in Zen Browser & Firefox (Native & Flatpak).

Security & resource guarantees:
  - Binds strictly to 127.0.0.1 (loopback only, never exposed on LAN).
  - Single-instance enforced via non-blocking flock.
  - Pure asyncio event-driven push (0% CPU when idle, no file polling loops).
"""

from __future__ import annotations

import argparse
import asyncio
import fcntl
import html
import json
import os
import signal
import sys
from pathlib import Path

DEFAULT_PORT = 43821


class ThemeBridge:
    def __init__(self, gen_dir: Path) -> None:
        self.gen_dir = gen_dir
        self.theme_file = gen_dir / "browser-live-theme.json"
        self.xpi_file = gen_dir / "alis-browser-theme.xpi"
        self.clients: set[asyncio.StreamWriter] = set()

    def read_payload_compact(self) -> str:
        if not self.theme_file.is_file():
            return json.dumps({"enabled": True, "gecko_theme": None})
        try:
            data = json.loads(self.theme_file.read_text(encoding="utf-8"))
            return json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        except Exception:
            return json.dumps({"enabled": True, "gecko_theme": None})

    async def broadcast(self) -> int:
        payload = self.read_payload_compact()
        frame = f"data: {payload}\n\n".encode("utf-8")
        stale: list[asyncio.StreamWriter] = []
        sent = 0
        for writer in list(self.clients):
            try:
                writer.write(frame)
                await writer.drain()
                sent += 1
            except Exception:
                stale.append(writer)
        for w in stale:
            self.clients.discard(w)
            try:
                w.close()
            except Exception:
                pass
        return sent

    def build_install_html(self) -> bytes:
        raw = self.read_payload_compact()
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {}
        pal = parsed.get("palette") or {}
        bg = pal.get("bg", "#141318")
        surface = pal.get("surface_elev", "#211f26")
        fg = pal.get("fg", "#e6e1e9")
        sub = pal.get("subtext", "#cac4d0")
        primary = pal.get("primary", "#82d9df")
        on_primary = pal.get("on_primary", "#10252a")
        border = pal.get("border", "#49454f")

        page = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Alis Live Browser Theme</title>
  <style>
    :root {{
      --bg: {html.escape(bg)};
      --surface: {html.escape(surface)};
      --fg: {html.escape(fg)};
      --sub: {html.escape(sub)};
      --primary: {html.escape(primary)};
      --on-primary: {html.escape(on_primary)};
      --border: {html.escape(border)};
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0; min-height: 100vh; display: grid; place-items: center;
      font-family: system-ui, -apple-system, sans-serif;
      background: var(--bg); color: var(--fg); padding: 24px;
      transition: background 180ms ease, color 180ms ease;
    }}
    .card {{
      max-width: 520px; width: 100%; background: var(--surface);
      border: 1px solid var(--border); border-radius: 20px; padding: 28px;
      box-shadow: 0 18px 48px rgba(0,0,0,0.28);
    }}
    h1 {{ margin: 0 0 8px; font-size: 22px; }}
    p {{ margin: 0 0 18px; color: var(--sub); line-height: 1.55; font-size: 14.5px; }}
    .btn {{
      display: inline-flex; align-items: center; gap: 8px;
      background: var(--primary); color: var(--on-primary);
      font-weight: 600; font-size: 15px; text-decoration: none;
      padding: 12px 20px; border-radius: 12px;
    }}
    .meta {{
      margin-top: 20px; padding-top: 16px; border-top: 1px solid var(--border);
      font-size: 13px; color: var(--sub); display: flex; justify-content: space-between;
    }}
    .dot {{
      display: inline-block; width: 9px; height: 9px; border-radius: 50%;
      background: var(--primary); margin-right: 6px;
    }}
  </style>
</head>
<body>
  <div class="card">
    <h1>Alis Live Browser Theme</h1>
    <p>
      Click below once in <strong>Zen Browser</strong> (or Firefox / LibreWolf / Floorp) to install the
      lightweight Alis theme bridge. Wallpaper &amp; Dark/Light color changes will then apply
      <strong>instantly without restarting</strong>.
    </p>
    <a class="btn" href="/alis-browser-theme.xpi">Install Alis Live Theme (.xpi)</a>
    <div class="meta">
      <span><span class="dot"></span>Loopback SSE Bridge Active</span>
      <span id="seed">Accent: {html.escape(primary)}</span>
    </div>
  </div>
  <script>
    const es = new EventSource("/events");
    es.onmessage = (ev) => {{
      try {{
        const d = JSON.parse(ev.data);
        const p = d.palette || {{}};
        if (p.bg) document.documentElement.style.setProperty("--bg", p.bg);
        if (p.surface_elev) document.documentElement.style.setProperty("--surface", p.surface_elev);
        if (p.fg) document.documentElement.style.setProperty("--fg", p.fg);
        if (p.subtext) document.documentElement.style.setProperty("--sub", p.subtext);
        if (p.primary) {{
          document.documentElement.style.setProperty("--primary", p.primary);
          document.getElementById("seed").textContent = "Accent: " + p.primary;
        }}
        if (p.on_primary) document.documentElement.style.setProperty("--on-primary", p.on_primary);
        if (p.border) document.documentElement.style.setProperty("--border", p.border);
      }} catch (_) {{}}
    }};
  </script>
</body>
</html>
"""
        return page.encode("utf-8")

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            request_line = await asyncio.wait_for(reader.readline(), timeout=5.0)
            if not request_line:
                writer.close()
                return
            parts = request_line.decode("utf-8", errors="replace").strip().split()
            if len(parts) < 2:
                writer.close()
                return
            method, raw_path = parts[0].upper(), parts[1]
            path = raw_path.split("?", 1)[0]

            content_length = 0
            while True:
                hdr = await asyncio.wait_for(reader.readline(), timeout=5.0)
                if not hdr or hdr in (b"\r\n", b"\n"):
                    break
                hline = hdr.decode("utf-8", errors="replace")
                if hline.lower().startswith("content-length:"):
                    try:
                        content_length = max(0, min(65536, int(hline.split(":", 1)[1].strip())))
                    except ValueError:
                        content_length = 0
            if content_length > 0:
                await asyncio.wait_for(reader.readexactly(content_length), timeout=5.0)

            if method == "OPTIONS":
                await self._send_response(writer, 204, "No Content", "text/plain", b"")
                return

            if method == "GET" and path == "/health":
                body = json.dumps({"ok": True, "clients": len(self.clients)}).encode("utf-8")
                await self._send_response(writer, 200, "OK", "application/json; charset=utf-8", body)
                return

            if method == "GET" and path == "/theme":
                body = self.read_payload_compact().encode("utf-8")
                await self._send_response(writer, 200, "OK", "application/json; charset=utf-8", body)
                return

            if method == "POST" and path == "/notify":
                delivered = await self.broadcast()
                body = json.dumps({"ok": True, "clients": delivered}).encode("utf-8")
                await self._send_response(writer, 200, "OK", "application/json; charset=utf-8", body)
                return

            if method == "GET" and path == "/alis-browser-theme.xpi":
                if not self.xpi_file.is_file():
                    await self._send_response(writer, 404, "Not Found", "text/plain; charset=utf-8", b"XPI not built yet")
                    return
                xpi_bytes = self.xpi_file.read_bytes()
                await self._send_response(
                    writer,
                    200,
                    "OK",
                    "application/x-xpinstall",
                    xpi_bytes,
                    extra_headers=["Content-Disposition: inline; filename=\"alis-browser-theme.xpi\""],
                )
                return

            if method == "GET" and path in ("/", "/install"):
                body = self.build_install_html()
                await self._send_response(writer, 200, "OK", "text/html; charset=utf-8", body)
                return

            if method == "GET" and path == "/events":
                headers = (
                    "HTTP/1.1 200 OK\r\n"
                    "Content-Type: text/event-stream; charset=utf-8\r\n"
                    "Cache-Control: no-cache, no-store\r\n"
                    "Connection: keep-alive\r\n"
                    "Access-Control-Allow-Origin: *\r\n"
                    "\r\n"
                ).encode("utf-8")
                writer.write(headers)
                initial = f"data: {self.read_payload_compact()}\n\n".encode("utf-8")
                writer.write(initial)
                await writer.drain()

                self.clients.add(writer)
                try:
                    while True:
                        try:
                            chunk = await asyncio.wait_for(reader.read(64), timeout=45.0)
                            if not chunk:
                                break
                        except asyncio.TimeoutError:
                            writer.write(b": keepalive\n\n")
                            await writer.drain()
                finally:
                    self.clients.discard(writer)
                return

            await self._send_response(writer, 404, "Not Found", "text/plain; charset=utf-8", b"Not Found")
        except Exception:
            pass
        finally:
            self.clients.discard(writer)
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def _send_response(
        self,
        writer: asyncio.StreamWriter,
        status: int,
        reason: str,
        content_type: str,
        body: bytes,
        extra_headers: list[str] | None = None,
    ) -> None:
        lines = [
            f"HTTP/1.1 {status} {reason}",
            f"Content-Type: {content_type}",
            f"Content-Length: {len(body)}",
            "Cache-Control: no-store",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
        ]
        if extra_headers:
            lines.extend(extra_headers)
        raw_head = ("\r\n".join(lines) + "\r\n\r\n").encode("utf-8")
        writer.write(raw_head + body)
        await writer.drain()


async def run_server(gen_dir: Path, host: str, port: int, port_file: Path | None) -> None:
    bridge = ThemeBridge(gen_dir)
    server = await asyncio.start_server(bridge.handle_client, host=host, port=port)
    actual_port = server.sockets[0].getsockname()[1]
    if port_file is not None:
        port_file.write_text(f"{actual_port}\n", encoding="utf-8")

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:
            pass

    async with server:
        await stop_event.wait()


def main() -> int:
    parser = argparse.ArgumentParser(description="Alis loopback SSE bridge for live browser theming")
    parser.add_argument("--state-dir", default="", help="Override quickshell state directory")
    parser.add_argument("--host", default="127.0.0.1", help="Bind address (must be loopback)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Loopback TCP port")
    parser.add_argument("--port-file", default="", help="Optional file to record bound port")
    parser.add_argument("--no-lock", action="store_true", help="Skip singleton flock (isolated tests)")
    args = parser.parse_args()

    if args.host not in ("127.0.0.1", "::1", "localhost"):
        print("Refusing to bind browser theme bridge to non-loopback address", file=sys.stderr)
        return 2

    xdg_state = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    state_dir = Path(args.state_dir).resolve() if args.state_dir else (Path(xdg_state) / "quickshell")
    gen_dir = state_dir / "user" / "generated"
    gen_dir.mkdir(parents=True, exist_ok=True)

    lock_fh = None
    if not args.no_lock:
        lock_path = gen_dir / "browser-theme-bridge.lock"
        lock_fh = lock_path.open("w", encoding="utf-8")
        try:
            fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            # Another bridge instance is already running
            return 0
        lock_fh.write(f"{os.getpid()}\n")
        lock_fh.flush()

    port_file = Path(args.port_file).resolve() if args.port_file else None
    try:
        asyncio.run(run_server(gen_dir, args.host, args.port, port_file))
    except OSError:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
