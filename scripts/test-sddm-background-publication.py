#!/usr/bin/env python3
"""Greeter asset publication uses synthetic files; never writes a live theme."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get("ALIS_TEST_SDDM_SYNC_SOURCE", ROOT / "scripts/sddm/sync-pixel-sddm.py"))
spec = importlib.util.spec_from_file_location("sddm_sync_fixture", SOURCE)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class Publication(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="alis-sddm-publication-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.assets = self.base / "assets"
        self.assets.mkdir(mode=0o700)
        self.source = self.base / "private-wallpaper.png"
        self.source.write_bytes(b"synthetic image, not an owner wallpaper")
        self.source.chmod(0o600)
        self.dest = self.assets / "background.png"
        self.mock_assets = patch.object(sync, "ASSETS_DIR", str(self.assets))
        self.mock_assets.start()
        self.addCleanup(self.mock_assets.stop)

    def mode(self, path):
        return stat.S_IMODE(path.stat().st_mode)

    def publish(self):
        self.assertTrue(sync.update_background(str(self.source)))

    def test_private_source_publishes_readable_copy(self):
        self.publish()
        self.assertEqual(self.dest.read_bytes(), self.source.read_bytes())
        self.assertEqual(self.mode(self.dest), 0o644)
        self.assertEqual(self.mode(self.assets), 0o755)
        self.assertEqual(self.mode(self.source), 0o600)

    def test_unchanged_sync_keeps_inode_and_timestamp(self):
        self.publish()
        before = self.dest.stat()
        with patch.object(sync.shutil, "copy2", side_effect=AssertionError("unchanged image recopied")):
            self.publish()
        after = self.dest.stat()
        self.assertEqual((before.st_ino, before.st_mtime_ns), (after.st_ino, after.st_mtime_ns))

    def test_legacy_private_copy_is_repaired(self):
        self.dest.write_bytes(self.source.read_bytes())
        self.dest.chmod(0o600)
        self.publish()
        self.assertEqual(self.mode(self.dest), 0o644)
        self.assertEqual(self.mode(self.source), 0o600)

    def test_symlink_is_replaced_without_changing_private_target(self):
        private = self.base / "untouched-private-image"
        private.write_bytes(b"private sentinel")
        private.chmod(0o600)
        self.dest.symlink_to(private)
        self.publish()
        self.assertFalse(self.dest.is_symlink())
        self.assertEqual(private.read_bytes(), b"private sentinel")
        self.assertEqual(self.mode(private), 0o600)

    def test_partial_copy_failure_keeps_old_asset(self):
        self.publish()
        old = self.dest.read_bytes()
        inode = self.dest.stat().st_ino
        self.source.write_bytes(b"a different next synthetic image")

        def partial(src, dst):
            Path(dst).write_bytes(b"incomplete")
            raise OSError("injected copy failure")

        with patch.object(sync.shutil, "copy2", side_effect=partial):
            self.assertFalse(sync.update_background(str(self.source)))
        self.assertEqual(self.dest.read_bytes(), old)
        self.assertEqual(self.dest.stat().st_ino, inode)
        self.assertEqual(list(self.assets.glob(".alis-background-*")), [])

    def test_publish_denial_keeps_old_asset(self):
        self.publish()
        old = self.dest.read_bytes()
        self.source.write_bytes(b"a different next synthetic image")
        with patch.object(sync.os, "replace", side_effect=PermissionError("injected denial")):
            self.assertFalse(sync.update_background(str(self.source)))
        self.assertEqual(self.dest.read_bytes(), old)
        self.assertEqual(list(self.assets.glob(".alis-background-*")), [])

    def test_cached_video_repairs_mode_without_decoding_again(self):
        video = self.base / "synthetic.mp4"
        video.write_bytes(b"synthetic video identity")
        info = video.stat()
        stamp = self.assets / ".alis-background-source.json"
        stamp.write_text(json.dumps({"path":str(video.resolve()), "size":info.st_size,
                                     "mtime_ns":info.st_mtime_ns}, sort_keys=True))
        self.dest.write_bytes(b"previously extracted frame")
        self.dest.chmod(0o600)
        with patch.object(sync, "extract_video_frame", side_effect=AssertionError("cached frame decoded again")):
            self.assertTrue(sync.update_background(str(video)))
        self.assertEqual(self.dest.read_bytes(), b"previously extracted frame")
        self.assertEqual(self.mode(self.dest), 0o644)

    def test_missing_source_keeps_existing_image(self):
        self.publish()
        old = self.dest.read_bytes()
        self.assertFalse(sync.update_background(str(self.base / "missing.png")))
        self.assertEqual(self.dest.read_bytes(), old)

    def test_symlinked_asset_directory_is_not_modified(self):
        self.assets.rmdir()
        private = self.base / "private-directory"
        private.mkdir(mode=0o700)
        self.assets.symlink_to(private, target_is_directory=True)
        self.assertFalse(sync.update_background(str(self.source)))
        self.assertEqual(self.mode(private), 0o700)
        self.assertEqual(list(private.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
