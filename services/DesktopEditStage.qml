pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common

// Coordinates the zoomed-out Desktop Edit Stage across Background.qml and
// AbyssPerimeter.qml whenever an Abyss customization mode (Widgets, Abyss
// Layout, Dashboard/Overview Layout, or Settings Layout) is active on an
// output. With no active stage on an output, cardFor() returns identity
// geometry (s = 1, x = 0, y = 0, p = 0) with zero overhead.
Singleton {
    id: root

    // outputName -> { mode, progress, dockWidth, dockHeight }
    property var stages: ({})

    // Outputs where AbyssPerimeter owns the external welded customization dock.
    property var hosts: ({})

    readonly property bool stageEnabled: (Config.options?.abyss?.editStage?.enable ?? true) === true
    readonly property real configuredScale: {
        const raw = Number(Config.options?.abyss?.editStage?.scale ?? 0.83);
        const safe = Number.isFinite(raw) ? raw : 0.83;
        return Math.max(0.70, Math.min(0.92, safe));
    }
    readonly property bool parkEmptyWorkspace: (Config.options?.abyss?.editStage?.parkEmptyWorkspace ?? true) === true
    readonly property bool wallpaperStageEnabled: root.stageEnabled
        && ((Config.options?.abyss?.editStage?.wallpaperPreview ?? true) === true)

    readonly property real topMargin: 16
    readonly property real bottomMargin: 16
    readonly property real sideMargin: 16
    readonly property real edgeClearanceMargin: 16
    readonly property real maxRestScale: root.configuredScale
    readonly property real configuredDockRadius: Math.max(12, Math.min(64, Number(Config.options?.abyss?.perimeter?.radius ?? 34)))

    onStageEnabledChanged: {
        if (!root.stageEnabled)
            root.unpark();
    }
    onParkEmptyWorkspaceChanged: {
        if (!root.parkEmptyWorkspace)
            root.unpark();
    }

    function setHost(output: string, active: bool): void {
        if (!output)
            return;
        if (Boolean(root.hosts[output]) === active)
            return;
        const next = Object.assign({}, root.hosts);
        if (active)
            next[output] = true;
        else
            delete next[output];
        root.hosts = next;
    }

    function hosted(output: string): bool {
        return root.stageEnabled && Boolean(output && root.hosts[output]);
    }

    function setStage(
        output: string,
        mode: string,
        progress: real,
        dockWidth: real,
        dockHeight: real,
        leftDockWidth = 0,
        leftDockHeight = 0,
        rightDockWidth = 0,
        rightDockHeight = 0,
        leftProgress = -1,
        rightProgress = -1
    ): void {
        if (!output)
            return;
        const clampedP = Math.max(0, Math.min(1, Number(progress) || 0));
        const cleanW = Math.round(Math.max(0, Number(dockWidth) || 0));
        const cleanH = Math.round(Math.max(0, Number(dockHeight) || 0));
        const cleanLW = Math.round(Math.max(0, Number(leftDockWidth) || 0));
        const cleanLH = Math.round(Math.max(0, Number(leftDockHeight) || 0));
        const cleanRW = Math.round(Math.max(0, Number(rightDockWidth) || 0));
        const cleanRH = Math.round(Math.max(0, Number(rightDockHeight) || 0));
        const clampedLP = Number(leftProgress) >= 0
            ? Math.max(0, Math.min(1, Number(leftProgress) || 0))
            : clampedP;
        const clampedRP = Number(rightProgress) >= 0
            ? Math.max(0, Math.min(1, Number(rightProgress) || 0))
            : clampedP;
        const now = root.stages[output];
        if (clampedP <= 0.0001) {
            if (!now)
                return;
            const next = Object.assign({}, root.stages);
            delete next[output];
            root.stages = next;
            return;
        }
        if (now
                && now.mode === mode
                && Math.abs(now.progress - clampedP) < 0.0001
                && now.dockWidth === cleanW
                && now.dockHeight === cleanH
                && now.leftDockWidth === cleanLW
                && now.leftDockHeight === cleanLH
                && now.rightDockWidth === cleanRW
                && now.rightDockHeight === cleanRH
                && Math.abs((now.leftProgress ?? clampedP) - clampedLP) < 0.0001
                && Math.abs((now.rightProgress ?? clampedP) - clampedRP) < 0.0001) {
            return;
        }
        const next = Object.assign({}, root.stages);
        next[output] = {
            mode: String(mode ?? ""),
            progress: clampedP,
            dockWidth: cleanW,
            dockHeight: cleanH,
            leftDockWidth: cleanLW,
            leftDockHeight: cleanLH,
            rightDockWidth: cleanRW,
            rightDockHeight: cleanRH,
            leftProgress: clampedLP,
            rightProgress: clampedRP
        };
        root.stages = next;
    }

    function clearStage(output: string): void {
        if (!output || !root.stages[output])
            return;
        const next = Object.assign({}, root.stages);
        delete next[output];
        root.stages = next;
    }

    function cardForGeometry(
        w: real,
        h: real,
        mode: string,
        rawProgress: real,
        dockWidth: real,
        dockHeight: real,
        leftDockWidth = 0,
        leftDockHeight = 0,
        rightDockWidth = 0,
        rightDockHeight = 0,
        leftProgress = -1,
        rightProgress = -1
    ): var {
        const width = Math.max(0, Number(w) || 0);
        const height = Math.max(0, Number(h) || 0);
        const fallbackDockW = Math.min(Math.max(240, Math.round(width * 0.80)), 960);
        const p = Math.max(0, Math.min(1, Number(rawProgress) || 0));
        if (width <= 0 || height <= 0 || !(p > 0.0001)) {
            return {
                active: false,
                mode: "",
                p: 0,
                s: 1,
                rest: 1,
                x: 0,
                y: 0,
                width: width,
                height: height,
                right: width,
                bottom: height,
                cornerRadius: 0,
                bezel: 0,
                dockRadius: root.configuredDockRadius,
                dockX: Math.round((width - fallbackDockW) / 2),
                dockY: height + 12,
                dockWidth: fallbackDockW,
                dockHeight: 0,
                dockBottom: height + 12,
                leftDockX: -12,
                leftDockY: Math.round(height / 2),
                leftDockWidth: 0,
                leftDockHeight: 0,
                leftProgress: 0,
                rightDockX: width + 12,
                rightDockY: Math.round(height / 2),
                rightDockWidth: 0,
                rightDockHeight: 0,
                rightProgress: 0
            };
        }

        const lp = Number(leftProgress) >= 0 ? Math.max(0, Math.min(1, Number(leftProgress) || 0)) : p;
        const rp = Number(rightProgress) >= 0 ? Math.max(0, Math.min(1, Number(rightProgress) || 0)) : p;
        const restBezel = 5;
        const bezel = restBezel * p;
        const cornerRadius = 14 * p;

        const hasBottom = (Number(dockHeight) || 0) > 0 && (Number(dockWidth) || 0) > 0;
        const dockH = hasBottom
            ? Math.round(Math.max(48, Math.min(height * 0.42, Number(dockHeight))))
            : 0;

        const hasLeft = (Number(leftDockWidth) || 0) > 0 && (Number(leftDockHeight) || 0) > 0;
        const leftW = hasLeft
            ? Math.round(Math.max(200, Math.min(width * 0.28, Number(leftDockWidth))))
            : 0;

        const hasRight = (Number(rightDockWidth) || 0) > 0 && (Number(rightDockHeight) || 0) > 0;
        const rightW = hasRight
            ? Math.round(Math.max(200, Math.min(width * 0.28, Number(rightDockWidth))))
            : 0;

        // Keep Desktop horizontally centered while sizing docks flexibly to their content
        // and preserving clean clearances from the outer physical edges.
        const minEdgeGap = root.edgeClearanceMargin;
        const maxSideNeed = Math.max(
            root.sideMargin,
            hasLeft ? (leftW + restBezel + minEdgeGap) : 0,
            hasRight ? (rightW + restBezel + minEdgeGap) : 0
        );
        const sideMaxScale = (width - 2 * maxSideNeed) / width;
        const bottomNeed = hasBottom ? (dockH + restBezel + minEdgeGap) : root.bottomMargin;
        const vertMaxScale = (height - root.topMargin - bottomNeed) / height;
        const fit = Math.max(0.45, Math.min(root.maxRestScale, sideMaxScale, vertMaxScale));
        const sRest = Math.round(width * fit) / width;
        const restW = Math.round(width * sRest);
        const restH = Math.round(height * sRest);
        const restX = Math.round((width - restW) / 2);
        const availVertSpace = Math.max(0, height - root.topMargin - bottomNeed - restH);
        const restY = Math.round(root.topMargin + availVertSpace * 0.5);

        const s = 1 + (sRest - 1) * p;
        const x = restX * p;
        const y = restY * p;
        const stageW = width * s;
        const stageH = height * s;
        const right = x + stageW;
        const bottom = y + stageH;

        // Content-driven dock dimensions capped at 80% of the shrunk Desktop span,
        // with pure edge-slide trajectories (zero scale/grow/shrink).
        const maxDockW = Math.max(240, Math.min(width - 2 * root.sideMargin, Math.round(restW * 0.80)));
        const requestedDockW = Number(dockWidth) > 0 ? Number(dockWidth) : maxDockW;
        const dockW = hasBottom
            ? Math.round(Math.min(maxDockW, Math.max(Math.min(maxDockW, 240), requestedDockW)))
            : 0;
        const dockRestX = Math.round(restX + (restW - dockW) / 2);
        const dockRestY = Math.round(restY + restH + restBezel);
        const dockClosedY = height + 12;
        const dockX = dockRestX;
        const dockY = hasBottom ? Math.round(dockClosedY + (dockRestY - dockClosedY) * p) : dockClosedY;

        const maxSideDockH = Math.max(120, Math.min(height - 2 * root.topMargin, Math.round(restH * 0.80)));
        const minSideDockH = Math.min(maxSideDockH, 120);
        const leftH = hasLeft
            ? Math.round(Math.max(minSideDockH, Math.min(maxSideDockH, Number(leftDockHeight))))
            : 0;
        const leftRestX = Math.round(restX - restBezel - leftW);
        const leftClosedX = -leftW - 12;
        const leftDockX = hasLeft && lp > 0.0001
            ? Math.round(leftClosedX + (leftRestX - leftClosedX) * lp)
            : leftClosedX;
        const leftDockY = hasLeft
            ? Math.round(Math.max(root.topMargin, Math.min(height - root.topMargin - leftH, restY + (restH - leftH) / 2)))
            : Math.round(height / 2);

        const rightH = hasRight
            ? Math.round(Math.max(minSideDockH, Math.min(maxSideDockH, Number(rightDockHeight))))
            : 0;
        const rightRestX = Math.round(restX + restW + restBezel);
        const rightClosedX = width + 12;
        const rightDockX = hasRight && rp > 0.0001
            ? Math.round(rightClosedX + (rightRestX - rightClosedX) * rp)
            : rightClosedX;
        const rightDockY = hasRight
            ? Math.round(Math.max(root.topMargin, Math.min(height - root.topMargin - rightH, restY + (restH - rightH) / 2)))
            : Math.round(height / 2);

        return {
            active: true,
            mode: String(mode ?? ""),
            p: p,
            s: s,
            rest: sRest,
            x: x,
            y: y,
            width: stageW,
            height: stageH,
            right: right,
            bottom: bottom,
            cornerRadius: cornerRadius,
            bezel: bezel,
            dockRadius: root.configuredDockRadius,
            dockX: dockX,
            dockY: dockY,
            dockWidth: dockW,
            dockHeight: dockH,
            dockBottom: dockY + dockH,
            leftDockX: leftDockX,
            leftDockY: leftDockY,
            leftDockWidth: leftW,
            leftDockHeight: leftH,
            leftProgress: lp,
            rightDockX: rightDockX,
            rightDockY: rightDockY,
            rightDockWidth: rightW,
            rightDockHeight: rightH,
            rightProgress: rp
        };
    }

    function cardFor(output: string, w: real, h: real): var {
        const stage = output ? root.stages[output] : null;
        if (!stage)
            return root.cardForGeometry(w, h, "", 0, 0, 0, 0, 0, 0, 0, 0, 0);
        return root.cardForGeometry(
            w,
            h,
            stage.mode,
            stage.progress,
            stage.dockWidth,
            stage.dockHeight,
            stage.leftDockWidth ?? 0,
            stage.leftDockHeight ?? 0,
            stage.rightDockWidth ?? 0,
            stage.rightDockHeight ?? 0,
            stage.leftProgress ?? -1,
            stage.rightProgress ?? -1
        );
    }

    // ── Temporary Niri empty-workspace parking while arranging desktop/edges ──
    property int parkedFrom: -1
    property int parkedOn: -1
    property string parkedOutput: ""

    function park(output: string): void {
        if (!root.stageEnabled || !root.parkEmptyWorkspace || !output || !CompositorService.isNiri || root.parkedFrom >= 0)
            return;
        const spaces = (NiriService.allWorkspaces ?? []).filter(ws => ws?.output === output);
        const active = spaces.find(ws => ws?.is_active);
        if (!active)
            return;
        const windows = Array.isArray(NiriService.windows) ? NiriService.windows : [];
        const hasApps = (active.active_window_id !== null && active.active_window_id !== undefined)
            || windows.some(win => win?.workspace_id === active.id);
        if (!hasApps)
            return;
        const empty = spaces
            .filter(ws => ws.id !== active.id && !windows.some(win => win?.workspace_id === ws.id))
            .sort((a, b) => (b.idx ?? 0) - (a.idx ?? 0))[0];
        if (!empty || empty.id === undefined)
            return;
        root.parkedFrom = active.id;
        root.parkedOn = empty.id;
        root.parkedOutput = output;
        NiriService.switchToWorkspaceById(empty.id);
    }

    function unpark(): void {
        const from = root.parkedFrom;
        const on = root.parkedOn;
        const output = root.parkedOutput;
        root.parkedFrom = -1;
        root.parkedOn = -1;
        root.parkedOutput = "";
        if (from < 0 || !CompositorService.isNiri)
            return;
        const active = (NiriService.allWorkspaces ?? []).find(ws => ws?.is_active && ws?.output === output);
        if (active && active.id === on)
            NiriService.switchToWorkspaceById(from);
    }
}
