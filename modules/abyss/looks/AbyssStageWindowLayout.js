// Pure workspace-window geometry projection and preview image alignment
// for the zoomed Desktop Edit Stage (zero Qt dependencies).

function layoutNiriWorkspaceWindows(windows, workspaces, outputName, screenWidth, screenHeight, insets) {
    if (!Array.isArray(windows) || !Array.isArray(workspaces) || !outputName)
        return [];

    const activeWs = workspaces.find(ws => ws && ws.output === outputName && ws.is_active);
    if (!activeWs)
        return [];

    const wsWins = windows.filter(w => w && w.workspace_id === activeWs.id);
    if (!wsWins.length)
        return [];

    const leftInset = Math.max(0, Number(insets?.left ?? 0));
    const topInset = Math.max(0, Number(insets?.top ?? 0));
    const rightInset = Math.max(0, Number(insets?.right ?? 0));
    const bottomInset = Math.max(0, Number(insets?.bottom ?? 0));
    const workLeft = leftInset;
    const workTop = topInset;
    const workW = Math.max(1, Number(screenWidth || 0) - leftInset - rightInset);
    const workH = Math.max(1, Number(screenHeight || 0) - topInset - bottomInset);

    const tiled = [];
    const floating = [];
    for (let i = 0; i < wsWins.length; i++) {
        const w = wsWins[i];
        if (w.is_floating === true)
            floating.push(w);
        else
            tiled.push(w);
    }

    const out = [];

    if (tiled.length > 0) {
        const colMap = new Map();
        for (let i = 0; i < tiled.length; i++) {
            const w = tiled[i];
            const pos = Array.isArray(w.layout?.pos_in_scrolling_layout) ? w.layout.pos_in_scrolling_layout : [1, 1];
            const colIdx = Math.max(1, Number(pos[0] || 1));
            const rowIdx = Math.max(1, Number(pos[1] || 1));
            if (!colMap.has(colIdx))
                colMap.set(colIdx, []);
            colMap.get(colIdx).push({ win: w, rowIdx: rowIdx });
        }

        const sortedColKeys = Array.from(colMap.keys()).sort((a, b) => a - b);
        const cols = sortedColKeys.map(colKey => {
            const entries = colMap.get(colKey).slice().sort((a, b) => (a.rowIdx - b.rowIdx) || (Number(a.win.id) - Number(b.win.id)));
            let colW = 0;
            const rows = entries.map(entry => {
                const w = entry.win;
                const ts = Array.isArray(w.layout?.tile_size) ? w.layout.tile_size : null;
                const ws = Array.isArray(w.layout?.window_size) ? w.layout.window_size : null;
                const rw = Math.max(1, Math.min(workW, Number(ts?.[0] || ws?.[0] || workW)));
                const rh = Math.max(1, Math.min(workH, Number(ts?.[1] || ws?.[1] || workH)));
                if (rw > colW)
                    colW = rw;
                return { win: w, width: rw, height: rh };
            });
            return { colKey: colKey, width: Math.max(1, colW), rows: rows };
        });

        const hGap = 15;
        const colXs = new Array(cols.length);
        if (cols.length === 1) {
            colXs[0] = workLeft + Math.round((workW - cols[0].width) / 2);
        } else {
            let totalW = hGap * (cols.length - 1);
            for (let c = 0; c < cols.length; c++)
                totalW += cols[c].width;

            if (totalW <= workW) {
                let cursorX = workLeft + Math.round((workW - totalW) / 2);
                for (let c = 0; c < cols.length; c++) {
                    colXs[c] = cursorX;
                    cursorX += cols[c].width + hGap;
                }
            } else {
                let focusColIdx = cols.findIndex(col =>
                    col.rows.some(r => Boolean(r.win.is_focused) || r.win.id === activeWs.active_window_id)
                );
                if (focusColIdx < 0) {
                    let bestTs = -1;
                    for (let c = 0; c < cols.length; c++) {
                        for (let r = 0; r < cols[c].rows.length; r++) {
                            const ts = cols[c].rows[r].win.focus_timestamp;
                            const ns = ts ? (Number(ts.secs || 0) * 1e9 + Number(ts.nanos || 0)) : 0;
                            if (ns > bestTs) {
                                bestTs = ns;
                                focusColIdx = c;
                            }
                        }
                    }
                }
                if (focusColIdx < 0)
                    focusColIdx = 0;
                const focusedColW = cols[focusColIdx].width;
                let focusedX;
                if (focusColIdx === 0)
                    focusedX = workLeft + hGap;
                else if (focusColIdx === cols.length - 1)
                    focusedX = workLeft + workW - hGap - focusedColW;
                else
                    focusedX = workLeft + Math.round((workW - focusedColW) / 2);

                colXs[focusColIdx] = focusedX;
                for (let c = focusColIdx - 1; c >= 0; c--)
                    colXs[c] = colXs[c + 1] - hGap - cols[c].width;
                for (let c = focusColIdx + 1; c < cols.length; c++)
                    colXs[c] = colXs[c - 1] + cols[c - 1].width + hGap;
            }
        }

        for (let c = 0; c < cols.length; c++) {
            const col = cols[c];
            const colX = colXs[c];
            if (colX + col.width <= workLeft || colX >= workLeft + workW)
                continue;
            const rows = col.rows;
            if (rows.length === 1) {
                const r = rows[0];
                const y = workTop + Math.round((workH - r.height) / 2);
                const w = r.win;
                out.push({
                    id: w.id,
                    appId: String(w.app_id ?? ""),
                    title: String(w.title ?? ""),
                    x: colX,
                    y: y,
                    width: r.width,
                    height: r.height,
                    floating: false,
                    focused: Boolean(w.is_focused) || w.id === activeWs.active_window_id,
                    z: 1
                });
            } else {
                let sumRowH = 0;
                for (let ri = 0; ri < rows.length; ri++)
                    sumRowH += rows[ri].height;
                const vGap = Math.max(6, Math.min(24, Math.round((workH - sumRowH) / (rows.length + 1))));
                const totalH = sumRowH + vGap * (rows.length - 1);
                let cursorY = workTop + Math.round((workH - totalH) / 2);
                for (let ri = 0; ri < rows.length; ri++) {
                    const r = rows[ri];
                    const w = r.win;
                    out.push({
                        id: w.id,
                        appId: String(w.app_id ?? ""),
                        title: String(w.title ?? ""),
                        x: colX,
                        y: cursorY,
                        width: r.width,
                        height: r.height,
                        floating: false,
                        focused: Boolean(w.is_focused) || w.id === activeWs.active_window_id,
                        z: 1
                    });
                    cursorY += r.height + vGap;
                }
            }
        }
    }

    for (let i = 0; i < floating.length; i++) {
        const w = floating[i];
        const ts = Array.isArray(w.layout?.tile_size) ? w.layout.tile_size : null;
        const ws = Array.isArray(w.layout?.window_size) ? w.layout.window_size : null;
        const fw = Math.max(1, Math.min(workW, Number(ts?.[0] || ws?.[0] || Math.round(workW * 0.5))));
        const fh = Math.max(1, Math.min(workH, Number(ts?.[1] || ws?.[1] || Math.round(workH * 0.5))));
        const tpos = w.layout?.tile_pos_in_workspace_view;
        const hasPos = Array.isArray(tpos) && tpos.length >= 2
            && Number.isFinite(Number(tpos[0])) && Number.isFinite(Number(tpos[1]));
        const fx = hasPos ? (workLeft + Number(tpos[0])) : (workLeft + Math.round((workW - fw) / 2));
        const fy = hasPos ? (workTop + Number(tpos[1])) : (workTop + Math.round((workH - fh) / 2));
        out.push({
            id: w.id,
            appId: String(w.app_id ?? ""),
            title: String(w.title ?? ""),
            x: fx,
            y: fy,
            width: fw,
            height: fh,
            floating: true,
            focused: Boolean(w.is_focused) || w.id === activeWs.active_window_id,
            z: 2
        });
    }

    return out;
}

function previewImageGeometry(tileW, tileH, imgW, imgH) {
    const tw = Math.max(1, Number(tileW || 1));
    const th = Math.max(1, Number(tileH || 1));
    const iw = Number(imgW || 0);
    const ih = Number(imgH || 0);
    if (iw > 0 && ih > 0) {
        const extraW = iw - tw;
        const extraH = ih - th;
        if (extraW >= -2 && extraW <= 140 && extraH >= -2 && extraH <= 140) {
            return {
                x: -Math.round(extraW / 2),
                y: -Math.round(extraH * 0.38),
                width: iw,
                height: ih,
                fillMode: "pad"
            };
        }
    }
    return {
        x: 0,
        y: 0,
        width: tw,
        height: th,
        fillMode: "fit"
    };
}

function subRectUv(x, y, w, h, screenW, screenH) {
    const sw = Math.max(1, Number(screenW || 1));
    const sh = Math.max(1, Number(screenH || 1));
    const u0 = Math.max(0, Math.min(1, Number(x || 0) / sw));
    const v0 = Math.max(0, Math.min(1, Number(y || 0) / sh));
    const u1 = Math.max(u0, Math.min(1, (Number(x || 0) + Math.max(0, Number(w || 0))) / sw));
    const v1 = Math.max(v0, Math.min(1, (Number(y || 0) + Math.max(0, Number(h || 0))) / sh));
    return { u0: u0, v0: v0, uw: Math.max(0.0001, u1 - u0), vh: Math.max(0.0001, v1 - v0) };
}

const _NON_THEMED_EXCLUSIONS = new Set([
    "mpv", "vlc", "celluloid", "haruna", "gamescope", "obs", "com.obsproject.studio",
    "blender", "gimp", "org.gimp.gimp", "krita", "org.kde.krita",
    "inkscape", "org.inkscape.inkscape", "darktable", "rawtherapee",
    "kdenlive", "org.kde.kdenlive", "davinci-resolve", "shotcut",
    "imv", "loupe", "org.gnome.loupe", "eog", "swayimg"
]);

const _VSCODE_EDITORS = {
    "antigravity": "antigravity",
    "google-antigravity": "antigravity",
    "code": "code",
    "code-url-handler": "code",
    "codium": "codium",
    "vscodium": "codium",
    "code-oss": "codeOss",
    "code-insiders": "codeInsiders",
    "cursor": "cursor",
    "windsurf": "windsurf",
    "windsurf-next": "windsurfNext",
    "qoder": "qoder",
    "positron": "positron",
    "void": "voidEditor",
    "void-editor": "voidEditor",
    "melty": "melty",
    "pearai": "pearai",
    "aide": "aide"
};

const _TERMINALS = {
    "kitty": "kitty",
    "alacritty": "alacritty",
    "foot": "foot",
    "footclient": "foot",
    "wezterm": "wezterm",
    "org.wezfurlong.wezterm": "wezterm",
    "ghostty": "ghostty",
    "com.mitchellh.ghostty": "ghostty",
    "konsole": "konsole",
    "org.kde.konsole": "konsole",
    "rio": "rio",
    "ptyxis": "ptyxis",
    "org.gnome.ptyxis": "ptyxis"
};

const _BROWSER_APPS = new Set([
    "firefox", "org.mozilla.firefox", "firefox-esr", "librewolf",
    "zen", "zen-browser", "app.zen_browser.zen", "floorp", "waterfox",
    "google-chrome", "chromium", "brave-browser", "vivaldi-stable", "microsoft-edge"
]);

const _GTK_APPS = new Set([
    "nautilus", "org.gnome.nautilus", "thunar", "nemo", "pcmanfm",
    "pavucontrol", "org.pulseaudio.pavucontrol", "obsidian", "blueman-manager",
    "nm-connection-editor", "easyeffects", "com.github.wwmm.easyeffects",
    "io.missioncenter.missioncenter", "org.telegram.desktop",
    "file-roller", "gparted", "baobab", "evince", "papers"
]);

const _QT_APPS = new Set([
    "dolphin", "org.kde.dolphin", "kate", "org.kde.kate",
    "okular", "org.kde.okular", "gwenview", "org.kde.gwenview",
    "pcmanfm-qt", "qt6ct", "qt5ct", "kvantummanager",
    "org.qbittorrent.qbittorrent", "ark"
]);

function isAppAutoThemed(appId, appearanceConfig) {
    if ((appearanceConfig?.theme ?? "auto") !== "auto")
        return false;
    const wt = appearanceConfig?.wallpaperTheming ?? {};
    const id = String(appId ?? "").trim().toLowerCase();
    if (!id || _NON_THEMED_EXCLUSIONS.has(id) || id.startsWith("steam_app_"))
        return false;

    const appsEnabled = wt.enableAppsAndShell !== false;

    const editorKey = _VSCODE_EDITORS[id];
    if (editorKey) {
        return appsEnabled
            && wt.enableVSCode !== false
            && (wt.vscodeEditors?.[editorKey] !== false);
    }

    const termKey = _TERMINALS[id];
    if (termKey) {
        return wt.enableTerminal !== false
            && (wt.terminals?.[termKey] !== false);
    }

    if (id === "dev.zed.zed" || id === "zed")
        return appsEnabled && wt.enableZed !== false;
    if (id === "vesktop" || id === "dev.vencord.vesktop" || id === "discord" || id === "equibop" || id === "legcord")
        return appsEnabled && wt.enableVesktop !== false;
    if (_BROWSER_APPS.has(id) || id.includes("chrome") || id.includes("chromium")
            || id.includes("brave") || id.includes("vivaldi") || id.includes("firefox") || id.includes("zen_browser"))
        return appsEnabled && wt.enableChrome !== false;
    if (id === "spotify" || id === "com.spotify.client")
        return appsEnabled && wt.enableSpicetify !== false;
    if (id === "steam" || id === "steamwebhelper")
        return appsEnabled && wt.enableSteam !== false;
    if (id.includes("peardesktop") || id.includes("pear-desktop") || id.includes("youtube-music"))
        return appsEnabled && wt.enablePearDesktop !== false;

    if (id.startsWith("org.alis.") || id.startsWith("alis-") || id === "alis"
            || id.startsWith("org.gnome.") || id.startsWith("org.gtk.")
            || id.startsWith("org.xfce.") || id.startsWith("org.mate.")
            || id.startsWith("org.freedesktop.") || _GTK_APPS.has(id))
        return appsEnabled;

    if (id.startsWith("org.kde.") || _QT_APPS.has(id))
        return appsEnabled && wt.enableQtApps !== false;

    return false;
}
