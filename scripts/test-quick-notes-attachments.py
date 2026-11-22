#!/usr/bin/env python3
"""Synthetic image persistence, clipboard typing and safe failure receipts."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/notes/attachments.py"
spec = importlib.util.spec_from_file_location("attachments", HELPER)
attachments = importlib.util.module_from_spec(spec)
spec.loader.exec_module(attachments)
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwmLDhPwAFFAKA8JVvSQAAAABJRU5ErkJggg==")


class Images(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="notes-images-")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.store = self.folder / "Bản nháp (1)" / "notepad-attachments"

    def test_import_unicode_url_preserves_source_bytes_and_deduplicates(self):
        source = self.folder / "Ảnh có dấu.png"
        source.write_bytes(PNG)
        first = attachments.import_image(self.store, source.as_uri())
        second = attachments.import_image(self.store, source.as_uri())
        self.assertEqual(first, second)
        self.assertIn("%", first["url"])
        self.assertEqual(list(self.store.iterdir())[0].read_bytes(), PNG)
        self.assertEqual(source.read_bytes(), PNG)
        # The Markdown link itself is persisted by the existing note autosave.
        document = {"tabs": [{"id": "note-a", "text": "draft" + first["text"]}]}
        self.assertEqual(json.loads(json.dumps(document))["tabs"][0]["text"], "draft" + first["text"])

    def test_collision_does_not_overwrite_existing_bytes(self):
        self.store.mkdir(parents=True)
        path = self.store / (hashlib.sha256(PNG).hexdigest() + ".png")
        path.write_bytes(b"original")
        with self.assertRaisesRegex(ValueError, "collision"):
            attachments.persist(self.store, PNG)
        self.assertEqual(path.read_bytes(), b"original")

    def test_unsupported_missing_and_oversized_fail_without_assets(self):
        with self.assertRaises(ValueError):
            attachments.persist(self.store, b"text")
        with self.assertRaises(ValueError):
            attachments.import_image(self.store, str(self.folder / "missing.png"))
        with self.assertRaises(ValueError):
            attachments.persist(self.store, PNG + b"x" * attachments.LIMIT)
        self.assertFalse(self.store.exists())

    def clipboard(self, types, contents):
        bindir = self.folder / "bin"
        bindir.mkdir(exist_ok=True)
        source = self.folder / "clipboard.bin"
        source.write_bytes(contents)
        fake = bindir / "wl-paste"
        fake.write_text("#!/usr/bin/python3\nimport sys\nfrom pathlib import Path\n"
                        "if '--list-types' in sys.argv: print(" + repr(types) + ")\n"
                        "else: sys.stdout.buffer.write(Path(" + repr(str(source)) + ").read_bytes())\n")
        fake.chmod(0o755)
        env = dict(
            os.environ,
            PATH=str(bindir) + os.pathsep + os.environ.get("PATH", ""),
            ALIS_NATIVE_MODE="legacy",
        )
        env.pop("WAYLAND_DISPLAY", None)
        result = subprocess.run(["python3", str(HELPER), "--root", str(self.store)],
                                env=env, capture_output=True, text=True, timeout=10)
        return result, json.loads(result.stdout)

    def test_binary_clipboard_never_enters_note_as_text(self):
        result, payload = self.clipboard("text/plain\nimage/png", PNG)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["kind"], "image")
        self.assertIn("![Image](file://", payload["text"])
        self.assertEqual(list(self.store.iterdir())[0].read_bytes(), PNG)

    def test_text_clipboard_preserves_unicode_and_newlines(self):
        text = "Xin chào\nsecond line\n"
        result, payload = self.clipboard("text/plain;charset=utf-8", text.encode())
        self.assertEqual(result.returncode, 0)
        self.assertEqual(payload, {"ok": True, "kind": "text", "text": text})
        self.assertFalse(self.store.exists())

    def test_invalid_image_returns_failure_instead_of_corrupting_note(self):
        result, payload = self.clipboard("image/png", b"not an image")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(payload["ok"])
        self.assertNotIn("text", payload)
        self.assertFalse(self.store.exists())


if __name__ == "__main__":
    unittest.main()
