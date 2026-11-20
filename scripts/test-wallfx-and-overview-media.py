#!/usr/bin/env python3
"""Verify Pocket-Dots Favourite-only wallfx transition & Overview Video/GIF preview contracts."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    helper = ROOT / "scripts/wallfx/wallfx_helper.py"
    qsb = ROOT / "modules/common/widgets/wallpaperTransitions/wallfx.frag.qsb"
    crossfader = (ROOT / "modules/common/widgets/WallpaperCrossfader.qml").read_text(encoding="utf-8")
    wallpapers_qml = (ROOT / "services/Wallpapers.qml").read_text(encoding="utf-8")
    overview_niri = (ROOT / "modules/overview/OverviewNiriWidget.qml").read_text(encoding="utf-8")
    waffle_thumb = (ROOT / "modules/waffle/taskview/WorkspaceThumbnail.qml").read_text(encoding="utf-8")
    bg_qml = (ROOT / "modules/background/Background.qml").read_text(encoding="utf-8")
    launcher_item = (ROOT / "modules/wallpaperLauncher/WallpaperLauncherItem.qml").read_text(encoding="utf-8")
    launcher_list = (ROOT / "modules/wallpaperLauncher/WallpaperLauncherList.qml").read_text(encoding="utf-8")
    launcher_content = (ROOT / "modules/wallpaperLauncher/WallpaperLauncherContent.qml").read_text(encoding="utf-8")
    bg_config = (ROOT / "modules/settings/BackgroundConfig.qml").read_text(encoding="utf-8")

    assert qsb.is_file() and qsb.stat().st_size > 1000, "wallfx.frag.qsb missing or empty"
    assert "if (!Wallpapers.isFavourite(cleanPending))" in crossfader, "wallfx must gate on Favourite"
    assert 'root._activeShader = "alisMelt"' in crossfader, "non-favourite must fall back to alisMelt"
    assert 'root._activeShader = "wallfx"' in crossfader, "favourite must activate wallfx shader"
    assert 'value: "wallfx"' in bg_config and "Outline (Favourites)" in bg_config
    assert "Bake Favourites" not in bg_config, "manual Bake Favourites button should be removed"
    assert "Install AI Cutout" in bg_config and "visible: !Wallpapers.wallfxAiAvailable" in bg_config
    assert "_bakeSingleFavouriteAsync" not in wallpapers_qml, "detached racy bake helper must be replaced by save-gated sync"
    assert "syncFavouriteWallpapers()" in wallpapers_qml and "pruneWallfxFavourites()" in wallpapers_qml
    assert 'objectName:"wallpaperCardFavourite"' in launcher_item
    assert "favouritesOnly" in launcher_list and 'objectName:"wallpaperFavouritesFilter"' in launcher_content
    assert "Wallpapers.ensureVideoFirstFrame(wallpaperPathRaw)" in overview_niri
    assert "WallpaperListener.isGifPath(wallpaperPathRaw)" in overview_niri
    assert "Wallpapers.ensureVideoFirstFrame(wallpaperPathRaw)" in waffle_thumb
    assert "Wallpapers.getVideoFirstFramePath(wallpaperPathRaw)" in waffle_thumb
    assert 'bgRoot.wallpaperPathRaw.startsWith("/") ? ("file://" + bgRoot.wallpaperPathRaw)' in bg_qml
    assert 'Config.setNestedValue("background.thumbnailPath", resolvedThumbnailPath)' in wallpapers_qml

    with tempfile.TemporaryDirectory(prefix="alis-wallfx-test-") as tmp:
        tmp_path = Path(tmp)
        cache_dir = tmp_path / "cache"
        fav_file = tmp_path / "favourites.json"
        wp_fav = tmp_path / "hero_fav.png"
        wp_nonfav = tmp_path / "plain_nonfav.png"
        mock_mask = tmp_path / "mock_mask.png"

        img = Image.new("RGB", (640, 360), (24, 28, 38))
        draw = ImageDraw.Draw(img)
        draw.ellipse((220, 60, 420, 320), fill=(230, 140, 90))
        img.save(wp_fav)
        img.save(wp_nonfav)

        mask = Image.new("L", (640, 360), 0)
        mdraw = ImageDraw.Draw(mask)
        mdraw.ellipse((220, 60, 420, 320), fill=255)
        mask.save(mock_mask)

        fav_file.write_text(json.dumps({str(wp_fav): True, wp_fav.name: True}), encoding="utf-8")

        base_env = {**os.environ, "XDG_CACHE_HOME": str(cache_dir)}

        # 1. Non-favourite is strictly ineligible for wallfx maps
        r_nonfav = subprocess.run(
            ["/usr/bin/python3", str(helper), "resolve", str(wp_nonfav), "--favourites-file", str(fav_file)],
            env=base_env,
            capture_output=True,
            text=True,
            check=True,
        )
        nonfav_json = json.loads(r_nonfav.stdout.strip())
        assert nonfav_json["eligible"] is False and nonfav_json["reason"] == "not_favourite"

        # 2. Favourite without AI cutout resolves instant contagio spread maps (modeId 0)
        r_spread = subprocess.run(
            ["/usr/bin/python3", str(helper), "resolve", str(wp_fav), "--favourites-file", str(fav_file)],
            env={**base_env, "ALIS_WALLFX_VENV_DIR": str(tmp_path / "no-venv")},
            capture_output=True,
            text=True,
            check=True,
        )
        spread_json = json.loads(r_spread.stdout.strip())
        assert spread_json["eligible"] is True and spread_json["mode"] == "contagio" and spread_json["modeId"] == 0
        assert Path(spread_json["field"]).is_file() and Path(spread_json["line"]).is_file()

        # 3. Favourite with character mask bakes perfil outline maps (modeId 1)
        bake_env = {**base_env, "ALIS_WALLFX_MOCK_MASK": str(mock_mask)}
        r_bake = subprocess.run(
            ["/usr/bin/python3", str(helper), "bake", str(wp_fav)],
            env=bake_env,
            capture_output=True,
            text=True,
            check=True,
        )
        bake_json = json.loads(r_bake.stdout.strip())
        assert bake_json["ok"] is True and len(bake_json["paths"]) == 2
        assert Path(bake_json["paths"][0]).is_file() and Path(bake_json["paths"][1]).is_file()

        # 4. Subsequent resolve returns cached perfil (modeId 1) immediately
        r_perfil = subprocess.run(
            ["/usr/bin/python3", str(helper), "resolve", str(wp_fav), "--favourites-file", str(fav_file)],
            env=base_env,
            capture_output=True,
            text=True,
            check=True,
        )
        perfil_json = json.loads(r_perfil.stdout.strip())
        assert perfil_json["eligible"] is True and perfil_json["mode"] == "perfil" and perfil_json["modeId"] == 1
        assert perfil_json["sdRange"] == 16.0 and perfil_json["lineW"] == 2.2

        # 5. sync-favourites fast path when already baked
        r_sync_fast = subprocess.run(
            ["/usr/bin/python3", str(helper), "sync-favourites", str(fav_file), str(tmp_path)],
            env=bake_env,
            capture_output=True,
            text=True,
            check=True,
        )
        sync_fast_json = json.loads(r_sync_fast.stdout.strip())
        assert sync_fast_json["bakedNow"] == 0 and sync_fast_json["perfilReady"] == 1 and sync_fast_json["perfilCached"] == 1

        # 6. Unfavourite cleans up cached outline artifacts via prune
        fav_file.write_text(json.dumps({}), encoding="utf-8")
        r_prune = subprocess.run(
            ["/usr/bin/python3", str(helper), "prune", str(fav_file), str(tmp_path)],
            env=base_env,
            capture_output=True,
            text=True,
            check=True,
        )
        prune_json = json.loads(r_prune.stdout.strip())
        assert prune_json["pruned"] >= 1 and prune_json["perfilCached"] == 0
        assert not Path(perfil_json["field"]).exists() and not Path(perfil_json["line"]).exists()

        # 7. Adding favourite back + auto-sync bakes cleanly, and legacy basename-only entry is resolved & preserved
        wp_legacy = tmp_path / "legacy_hero.png"
        img.save(wp_legacy)
        fav_file.write_text(json.dumps({str(wp_fav): True, wp_fav.name: True, wp_legacy.name: True}), encoding="utf-8")
        r_sync_auto = subprocess.run(
            ["/usr/bin/python3", str(helper), "sync-favourites", str(fav_file), str(tmp_path)],
            env=bake_env,
            capture_output=True,
            text=True,
            check=True,
        )
        sync_auto_json = json.loads(r_sync_auto.stdout.strip())
        assert sync_auto_json["bakedNow"] == 2 and sync_auto_json["perfilReady"] == 2 and sync_auto_json["perfilCached"] == 2

        # Pruning without wallpapers_root must still preserve legacy basename-only favourite via meta img basename
        r_prune_keep = subprocess.run(
            ["/usr/bin/python3", str(helper), "prune", str(fav_file)],
            env=base_env,
            capture_output=True,
            text=True,
            check=True,
        )
        prune_keep_json = json.loads(r_prune_keep.stdout.strip())
        assert prune_keep_json["pruned"] == 0 and prune_keep_json["perfilCached"] == 2

        # Clean removal of one favourite leaves the other intact
        fav_file.write_text(json.dumps({str(wp_fav): True, wp_fav.name: True}), encoding="utf-8")
        r_prune_one = subprocess.run(
            ["/usr/bin/python3", str(helper), "prune", str(fav_file), str(tmp_path)],
            env=base_env,
            capture_output=True,
            text=True,
            check=True,
        )
        prune_one_json = json.loads(r_prune_one.stdout.strip())
        assert prune_one_json["pruned"] == 1 and prune_one_json["perfilCached"] == 1

    print("WALLFX_AND_OVERVIEW_MEDIA_PASS: favourite-only gate, contagio spread, perfil auto-sync/prune, legacy basename preservation, video/gif overview")


if __name__ == "__main__":
    main()
