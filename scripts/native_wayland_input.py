"""Bounded compositor input for an explicitly distinct private Niri session.

Never fall back to the owner's display. Protocol descriptions retain the
upstream wlroots licenses (swaywm/wlroots/protocol on GitHub).
"""
from contextlib import contextmanager
from pathlib import Path
import os
import select
import shutil
import subprocess


@contextmanager
def native_input(folder, env):
    private = env.get("WAYLAND_DISPLAY", "")
    parent = os.environ.get("WAYLAND_DISPLAY", "")
    runtime = Path(env.get("XDG_RUNTIME_DIR", "/nonexistent"))
    if not private or not parent or private == parent or "/" in private or "/" in parent:
        raise RuntimeError("Distinct explicit private and owner displays required")
    if (runtime/private).samefile(runtime/parent):
        raise RuntimeError("Private input socket aliases the owner's display")
    if any(shutil.which(tool) is None for tool in ("cc", "wayland-scanner", "pkg-config")):
        yield None
        return
    flags = subprocess.run(["pkg-config", "--cflags", "--libs", "wayland-client", "xkbcommon"],
                           capture_output=True, text=True, timeout=5)
    if flags.returncode:
        yield None
        return
    source = Path(__file__).resolve().parent/"fixtures/native-input"
    build = folder/"native-input"
    build.mkdir()
    for name in ("pointer", "keyboard"):
        for mode, suffix in (("client-header", ".h"), ("private-code", ".c")):
            subprocess.run(["wayland-scanner", mode, str(source/(name+".xml")),
                            str(build/(name+suffix))], check=True, timeout=5)
    subprocess.run(["cc", str(source/"client.c"), "-I", str(build),
                    str(build/"pointer.c"), str(build/"keyboard.c"),
                    *flags.stdout.split(), "-o", str(build/"client")], check=True, timeout=15)
    refused = subprocess.run([str(build/"client"), parent, parent],
                             env=env, capture_output=True, timeout=3)
    if refused.returncode != 2:
        raise RuntimeError("Native input owner-display rejection failed")
    process = subprocess.Popen([str(build/"client"), private, parent], env=env,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, bufsize=1)

    class Input:
        def read(self):
            if not select.select([process.stdout], [], [], 3)[0]:
                raise RuntimeError("Private input acknowledgement timed out")
            return process.stdout.readline().strip()

        def command(self, text):
            process.stdin.write(text+"\n")
            process.stdin.flush()
            if self.read() != "ACK":
                raise RuntimeError("Private compositor rejected input")

        def move(self, x, y, width, height):
            self.command(f"M {round(x*64)} {round(y*64)} {round(width*64)} {round(height*64)}")

        def click(self, button=272):
            self.command(f"B {button} 1")
            self.command(f"B {button} 0")

        def escape(self):
            self.command("K 1")
            self.command("K 0")

    driver = Input()
    try:
        first = driver.read()
        if first.startswith("UNAVAILABLE"):
            yield None
        elif first.startswith("READY"):
            yield driver
        else:
            raise RuntimeError("Private virtual input initialization failed")
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
