pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var lineData: null
    property real nextLineTime: -1
    property real position: 0
    property bool active: false
    property bool playing: false
    property bool synced: true
    property bool singleLine: false
    property int horizontalAlignment: Text.AlignLeft
    property int fontPixelSize: Appearance.font.pixelSize.normal
    property int activeFontWeight: Font.DemiBold
    property int inactiveFontWeight: Font.Normal
    property bool fontItalic: false
    property color inactiveColor: Appearance.colors.colSubtext
    property color activeColor: Appearance.colors.colOnSurface
    property color accentColor: Appearance.colors.colPrimary

    readonly property string lineText: {
        if (!root.lineData)
            return "";
        if (typeof root.lineData === "string")
            return root.lineData;
        return String(root.lineData.text ?? root.lineData.line ?? "");
    }

    readonly property real lineStartTime: {
        if (!root.lineData || typeof root.lineData !== "object")
            return 0;
        const t = Number(root.lineData.time ?? root.lineData.t ?? 0);
        return Number.isFinite(t) && t >= 0 ? t : 0;
    }

    readonly property real lineEndTime: {
        if (root.lineData && typeof root.lineData === "object") {
            const explicitEnd = Number(root.lineData.endTime ?? 0);
            if (Number.isFinite(explicitEnd) && explicitEnd > root.lineStartTime + 0.15)
                return explicitEnd;
        }
        if (root.nextLineTime > root.lineStartTime + 0.15) {
            const gap = root.nextLineTime - root.lineStartTime;
            return root.lineStartTime + Math.min(Math.max(0.35, gap - 0.06), Math.max(1.4, Math.min(8.5, gap * 0.92)));
        }
        return root.lineStartTime + 3.8;
    }

    // Smooth 60fps position clock active ONLY on the active line while playing
    property real _anchorPos: 0
    property real _anchorWallMs: 0
    property real _livePos: 0

    function _syncPositionAnchor(externalPos: real, snap: bool): void {
        const cleanPos = Math.max(0, Number(externalPos) || 0);
        const now = Date.now();
        if (snap || root._anchorWallMs <= 0 || !root.playing) {
            root._anchorPos = cleanPos;
            root._anchorWallMs = now;
            root._livePos = cleanPos;
            return;
        }
        const predicted = root._anchorPos + Math.max(0, (now - root._anchorWallMs) / 1000);
        const drift = cleanPos - predicted;
        if (Math.abs(drift) > 0.32) {
            root._anchorPos = cleanPos;
            root._anchorWallMs = now;
            root._livePos = cleanPos;
        } else if (Math.abs(drift) > 0.02) {
            // Softly blend small timing drift so word animations never jump backward
            const blended = predicted + drift * 0.45;
            root._anchorPos = blended;
            root._anchorWallMs = now;
            root._livePos = blended;
        }
    }

    onPositionChanged: root._syncPositionAnchor(root.position, false)
    onPlayingChanged: root._syncPositionAnchor(root.position, true)
    onActiveChanged: {
        if (root.active) {
            const initPos = (root.position >= root.lineStartTime - 0.25 && root.position <= root.lineEndTime + 1.0)
                ? Math.max(root.lineStartTime, root.position)
                : root.lineStartTime;
            root._syncPositionAnchor(initPos, true);
        }
    }
    onLineDataChanged: {
        if (root.active)
            root._syncPositionAnchor(Math.max(root.lineStartTime, root.position), true);
    }

    Timer {
        id: frameTimer
        interval: 16
        repeat: true
        running: root.visible && root.active && root.playing && root.synced && Appearance.animationsEnabled
        onTriggered: {
            if (root._anchorWallMs <= 0) {
                root._syncPositionAnchor(root.position, true);
                return;
            }
            const elapsed = Math.max(0, (Date.now() - root._anchorWallMs) / 1000);
            root._livePos = root._anchorPos + elapsed;
        }
    }

    readonly property real effectivePosition: (root.active && root.playing && root._anchorWallMs > 0)
        ? root._livePos
        : Math.max(0, root.position)

    // Built-in prosody & vocal expression analyzer (used both to enrich backend words and synthesize fallback words)
    function _analyzeWordProsody(wordText: string, start: real, end: real, index: int, total: int, avgDur: real, existing: var): var {
        const dur = Math.max(0.04, end - start);
        const stripped = String(wordText ?? "").trim();
        const core = stripped.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");
        const lower = core.toLowerCase();
        const relDur = dur / Math.max(0.16, avgDur);

        let vibrato = Number(existing?.vibrato ?? -1);
        let sustain = Number(existing?.sustain ?? -1);
        let rise = Number(existing?.rise ?? -1);
        let fall = Number(existing?.fall ?? -1);

        if (vibrato < 0 || sustain < 0 || rise < 0 || fall < 0) {
            vibrato = 0.0;
            sustain = 0.0;
            rise = 0.0;
            fall = 0.0;

            const repeatVowel = /([aăâeêioôơuưyáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ])\1+/i.test(core);
            const repeatSonorant = /([mnhlrw])\1{2,}/i.test(core);
            const vibratoVocals = /^(oh+|ooh+|ah+|aah+|uh+|huh|mmm+|hm+|la+|lala+|na+|nana+|da+|whoa|woah|yeah|yea|yay|ha+|hah|hey|ơ|hơ|ư|hư|à|ơi|hơi|ố|á|hà|nà|ờ)$/i.test(lower);
            const openTail = /[aăâeêioôơuưyáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵmnhw~…\.]$/i.test(core);
            const diphthong = /(?:ươi|ươu|oai|oay|uôi|uây|iêu|yêu|uya|ai|ay|ao|au|âu|êu|iu|ui|ee|oo|ea|ou|ow|igh|ey)/i.test(core);

            if (stripped.includes("~") || stripped.includes("…") || stripped.includes(".."))
                vibrato = 1.0;
            else if (repeatVowel || repeatSonorant)
                vibrato = 0.95;
            else if (vibratoVocals)
                vibrato = 0.90;
            else if (dur >= 0.72 && openTail)
                vibrato = Math.min(0.88, 0.45 + (dur - 0.60) * 0.75);

            if (dur >= 0.48 || relDur >= 1.32)
                sustain = Math.min(1.0, Math.max((dur - 0.34) / 0.80, (relDur - 1.10) / 1.05));
            if (index === total - 1 && dur >= 0.40)
                sustain = Math.max(sustain, Math.min(0.95, dur / 0.82));
            if (diphthong && dur >= 0.36)
                sustain = Math.max(sustain, 0.58);

            const viRising = /[áắấéếíóốớúứýảẩểỉỏổởủửỷãẫễĩõỗỡũữỹ]/.test(lower);
            const viFalling = /[àằầèềìòồờùừỳạặậẹệịọộợụựỵ]/.test(lower);
            const riseWords = /^(high|sky|fly|cry|why|shine|fire|light|rise|up|love|heart|soul|scream|shout|burn|dream|free|alive|forever|sun|star|heaven|cao|bay|sáng|cháy|yêu|thương|vời|trời|mơ|say|vang|lên|bừng|rực|hát|vươn)$/i.test(lower);
            const fallWords = /^(down|fall|fade|slow|low|gone|away|sleep|deep|night|dark|cold|quiet|whisper|end|alone|shadow|rain|tears|buồn|rơi|tàn|phai|xa|chìm|đêm|lặng|thầm|sâu|cuối|thôi|rồi|xuống|nhòa|khóc)$/i.test(lower);

            if (/[!\?]+$/.test(stripped))
                rise = 0.95;
            else if (core.length >= 2 && core === core.toUpperCase() && core !== core.toLowerCase())
                rise = 0.90;
            if (riseWords)
                rise = Math.max(rise, 0.82);
            if (viRising)
                rise = Math.max(rise, relDur >= 1.0 ? 0.68 : 0.50);
            const posRatio = (index + 0.5) / Math.max(1, total);
            if (posRatio >= 0.40 && posRatio <= 0.85 && relDur >= 1.18 && !viFalling)
                rise = Math.max(rise, Math.min(0.80, 0.45 + (relDur - 1.0) * 0.45));

            if (fallWords)
                fall = 0.82;
            if (viFalling && rise < 0.65)
                fall = Math.max(fall, index >= total - 2 ? 0.72 : 0.52);
            if (index === total - 1 && /[\.,;…]+$/.test(stripped) && !/[!\?]+$/.test(stripped))
                fall = Math.max(fall, 0.68);
            else if (index === total - 1 && rise < 0.45 && vibrato < 0.55 && sustain < 0.65)
                fall = Math.max(fall, 0.54);
        }

        const bestScore = Math.max(vibrato, rise, sustain, fall);
        let effect = String(existing?.effect ?? "");
        if (!effect) {
            if (bestScore < 0.45)
                effect = "normal";
            else if (vibrato === bestScore)
                effect = "vibrato";
            else if (rise === bestScore)
                effect = "rise";
            else if (sustain === bestScore)
                effect = "sustain";
            else
                effect = "fall";
        }
        const intensity = Number(existing?.intensity ?? (bestScore >= 0.45 ? Math.min(1.0, Math.max(0.45, bestScore)) : Math.min(0.75, Math.max(0.30, relDur * 0.45))));

        return {
            text: stripped,
            start: start,
            end: end,
            duration: dur,
            effect: effect,
            intensity: intensity,
            sustain: sustain,
            rise: rise,
            fall: fall,
            vibrato: vibrato
        };
    }

    readonly property var resolvedWords: {
        const text = root.lineText.trim();
        if (!text || text === "♪")
            return [];

        const lStart = root.lineStartTime;
        const lEnd = Math.max(lStart + 0.35, root.lineEndTime);
        const preWords = (root.lineData && typeof root.lineData === "object" && Array.isArray(root.lineData.words))
            ? root.lineData.words
            : [];

        if (preWords.length > 0) {
            const total = preWords.length;
            let sumDur = 0;
            for (let i = 0; i < total; i++) {
                const s = Number(preWords[i]?.start ?? lStart);
                const e = Number(preWords[i]?.end ?? (s + 0.3));
                sumDur += Math.max(0.04, e - s);
            }
            const avgDur = sumDur / Math.max(1, total);
            const enriched = [];
            for (let i = 0; i < total; i++) {
                const w = preWords[i];
                const s = Number(w?.start ?? lStart);
                const e = Math.max(s + 0.04, Number(w?.end ?? (s + avgDur)));
                enriched.push(root._analyzeWordProsody(String(w?.text ?? ""), s, e, i, total, avgDur, w));
            }
            return enriched;
        }

        // Fallback: synthesize prosody-weighted word timings from lineText
        const rawTokens = text.split(/\s+/).filter(t => t.length > 0);
        const total = rawTokens.length;
        if (total === 0)
            return [];

        const span = Math.max(0.28, lEnd - lStart);
        const weights = [];
        const pauses = [];
        let totalWeight = 0;
        let totalPause = 0;

        for (let i = 0; i < total; i++) {
            const tok = rawTokens[i];
            const core = tok.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");
            let w = Math.max(0.75, Math.pow(Math.max(1, core.length), 0.72));
            if (/^(a|an|the|to|in|on|of|at|is|it|và|là|của|cho|với|như)$/i.test(core))
                w *= 0.72;
            if (/([aăâeêioôơuưy])\1+/i.test(core) || tok.includes("~"))
                w += 1.55;
            else if (/(?:ươi|ươu|oai|uôi|iêu|yêu|ai|ay|ao|au|âu|êu|ee|oo|ea|ou|ow|igh)/i.test(core))
                w += 0.42;

            let p = 0;
            if (/(?:\.\.\.|…|~)$/.test(tok)) {
                w += 0.75;
                p = 0.16;
            } else if (/[!\?\.]$/.test(tok)) {
                w += 0.50;
                p = 0.14;
            } else if (/[,;:\-—]$/.test(tok)) {
                w += 0.32;
                p = 0.09;
            }
            if (i === total - 1) {
                w += 0.70;
                p = 0;
            }
            weights.push(w);
            pauses.push(p);
            totalWeight += w;
            totalPause += p;
        }

        const pauseScale = totalPause > 0 ? Math.min(1.0, (span * 0.22) / totalPause) : 0.0;
        const vocalSpan = Math.max(0.15, span - totalPause * pauseScale);
        const avgDur = vocalSpan / Math.max(1, total);

        const out = [];
        let cursor = lStart;
        for (let i = 0; i < total; i++) {
            const wDur = vocalSpan * (weights[i] / Math.max(0.01, totalWeight));
            const wStart = cursor;
            const wEnd = cursor + wDur;
            out.push(root._analyzeWordProsody(rawTokens[i], wStart, wEnd, i, total, avgDur, null));
            cursor = wEnd + pauses[i] * pauseScale;
        }
        return out;
    }

    readonly property bool useWordFlow: root.active && root.synced && root.resolvedWords.length > 0

    implicitWidth: 200
    implicitHeight: root.useWordFlow
        ? Math.max(fallbackText.implicitHeight, wordFlow.implicitHeight)
        : fallbackText.implicitHeight

    // Inactive or unsynced fallback text (zero overhead when line is inactive)
    StyledText {
        id: fallbackText
        width: root.width
        visible: !root.useWordFlow
        text: root.lineText.length > 0 ? root.lineText : "♪"
        wrapMode: root.singleLine ? Text.NoWrap : Text.WordWrap
        elide: root.singleLine ? Text.ElideRight : Text.ElideNone
        horizontalAlignment: root.horizontalAlignment
        font.pixelSize: root.fontPixelSize
        font.weight: root.active ? root.activeFontWeight : root.inactiveFontWeight
        font.italic: root.fontItalic
        color: root.active ? root.activeColor : root.inactiveColor
    }

    // Active word-by-word expressive flow
    Flow {
        id: wordFlow
        width: root.width
        visible: root.useWordFlow
        spacing: Math.max(4, Math.round(root.fontPixelSize * 0.28))
        flow: Flow.LeftToRight
        layoutDirection: Qt.LeftToRight

        function updateRowAlignment(): void {
            if (!root.useWordFlow)
                return;
            const count = wordRepeater.count;
            if (count <= 0)
                return;
            if (root.horizontalAlignment !== Text.AlignHCenter && root.horizontalAlignment !== Text.AlignRight) {
                for (let i = 0; i < count; i++) {
                    const item = wordRepeater.itemAt(i);
                    if (item)
                        item.rowShiftX = 0;
                }
                return;
            }
            let rowStart = 0;
            while (rowStart < count) {
                const firstItem = wordRepeater.itemAt(rowStart);
                if (!firstItem) {
                    rowStart++;
                    continue;
                }
                const rowY = firstItem.y;
                let maxRight = firstItem.x + firstItem.width;
                let rowEnd = rowStart + 1;
                while (rowEnd < count) {
                    const nextItem = wordRepeater.itemAt(rowEnd);
                    if (!nextItem || Math.abs(nextItem.y - rowY) > 2)
                        break;
                    maxRight = Math.max(maxRight, nextItem.x + nextItem.width);
                    rowEnd++;
                }
                const extra = Math.max(0, wordFlow.width - maxRight);
                const shift = root.horizontalAlignment === Text.AlignHCenter ? Math.round(extra / 2) : Math.round(extra);
                for (let k = rowStart; k < rowEnd; k++) {
                    const rowItem = wordRepeater.itemAt(k);
                    if (rowItem)
                        rowItem.rowShiftX = shift;
                }
                rowStart = rowEnd;
            }
        }

        onPositioningComplete: wordFlow.updateRowAlignment()
        onWidthChanged: Qt.callLater(wordFlow.updateRowAlignment)

        Repeater {
            id: wordRepeater
            model: root.useWordFlow ? root.resolvedWords : []
            onCountChanged: Qt.callLater(wordFlow.updateRowAlignment)

            delegate: Item {
                id: wordSlot
                required property int index
                required property var modelData
                property real rowShiftX: 0

                readonly property string wordText: String(modelData.text ?? "")
                readonly property real wStart: Number(modelData.start ?? 0)
                readonly property real wEnd: Math.max(wStart + 0.04, Number(modelData.end ?? (wStart + 0.3)))
                readonly property real wDuration: Math.max(0.04, wEnd - wStart)
                readonly property real sustainAmt: Number(modelData.sustain ?? 0)
                readonly property real riseAmt: Number(modelData.rise ?? 0)
                readonly property real fallAmt: Number(modelData.fall ?? 0)
                readonly property real vibratoAmt: Number(modelData.vibrato ?? 0)
                readonly property real intensity: Number(modelData.intensity ?? 0.5)

                // Word progress: 0 = not yet sung, (0..1) = currently being sung, 1 = finished singing
                readonly property real rawProgress: (root.effectivePosition - wStart) / wDuration
                readonly property real progress: Math.max(0.0, Math.min(1.0, rawProgress))
                readonly property bool isSinging: rawProgress >= -0.02 && rawProgress <= 1.04
                readonly property bool isSung: rawProgress > 1.04

                // Smooth bell envelope (0 -> 1 -> 0) peaking while the singer is singing the word
                readonly property real envelope: isSinging
                    ? Math.sin(Math.max(0.0, Math.min(1.0, progress)) * Math.PI)
                    : 0.0

                // 1. Kéo dài (Sustain): horizontal vocal stretch + slight vertical breath
                readonly property real sustainStretchX: isSinging && sustainAmt > 0.30
                    ? (0.13 * envelope * sustainAmt)
                    : 0.0
                readonly property real sustainStretchY: isSinging && sustainAmt > 0.30
                    ? (0.05 * envelope * sustainAmt)
                    : 0.0

                // 2. Lên giọng (Pitch Rise): upward float + crescendo scale boost
                readonly property real riseLiftY: isSinging && riseAmt > 0.30
                    ? (-5.8 * Math.sin(Math.pow(progress, 0.85) * Math.PI) * riseAmt)
                    : 0.0
                readonly property real riseScale: isSinging && riseAmt > 0.30
                    ? (0.14 * envelope * riseAmt)
                    : 0.0

                // 3. Xuống giọng (Pitch Fall): gentle downward pitch glide + soft settle
                readonly property real fallDropY: isSinging && fallAmt > 0.30 && riseAmt < 0.60
                    ? (4.0 * Math.sin(Math.pow(progress, 0.9) * Math.PI) * fallAmt)
                    : 0.0
                readonly property real fallScale: isSinging && fallAmt > 0.30 && riseAmt < 0.55
                    ? (-0.03 * progress * fallAmt)
                    : 0.0

                // 4. Ngân nga (Vibrato / Melisma): continuous sine-wave vertical oscillation & harmonic sway
                readonly property real vibratoWaveY: isSinging && vibratoAmt > 0.30
                    ? (Math.sin(root.effectivePosition * 17.5 + index * 1.3) * 3.4 * vibratoAmt * Math.max(0.25, envelope))
                    : 0.0
                readonly property real vibratoTilt: isSinging && vibratoAmt > 0.30
                    ? (Math.sin(root.effectivePosition * 11.0 + index * 0.9) * 2.5 * vibratoAmt * envelope)
                    : 0.0

                // Standard articulation lift for normal words
                readonly property real baseLiftY: isSinging
                    ? (-1.8 * envelope * (1.0 - Math.max(riseAmt, fallAmt) * 0.7))
                    : 0.0
                readonly property real baseScale: isSinging ? (0.05 * envelope) : 0.0

                readonly property real totalOffsetY: baseLiftY + riseLiftY + fallDropY + vibratoWaveY
                readonly property real totalScaleX: 1.0 + baseScale + riseScale + sustainStretchX + fallScale
                readonly property real totalScaleY: 1.0 + baseScale + riseScale + sustainStretchY + fallScale

                readonly property color sungHighlightColor: {
                    if (isSinging && (riseAmt > 0.45 || vibratoAmt > 0.45 || sustainAmt > 0.55)) {
                        return ColorUtils.mix(root.activeColor, root.accentColor, 0.48 * envelope);
                    }
                    return root.activeColor;
                }

                implicitWidth: baseWordLabel.implicitWidth
                implicitHeight: baseWordLabel.implicitHeight + 6
                width: implicitWidth
                height: implicitHeight

                Item {
                    id: animatedStage
                    width: baseWordLabel.implicitWidth
                    height: baseWordLabel.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter

                    transform: [
                        Scale {
                            origin.x: animatedStage.width / 2
                            origin.y: animatedStage.height / 2
                            xScale: wordSlot.totalScaleX
                            yScale: wordSlot.totalScaleY
                        },
                        Rotation {
                            origin.x: animatedStage.width / 2
                            origin.y: animatedStage.height / 2
                            angle: wordSlot.vibratoTilt
                        },
                        Translate {
                            x: wordSlot.rowShiftX
                            y: wordSlot.totalOffsetY
                        }
                    ]

                    // Soft luminous vocal aura behind sustained / rising / vibrato words while sung
                    Rectangle {
                        id: vocalAura
                        anchors.centerIn: parent
                        width: parent.width + 12
                        height: parent.height + 6
                        radius: height / 2
                        visible: wordSlot.isSinging && (wordSlot.sustainAmt > 0.35 || wordSlot.riseAmt > 0.40 || wordSlot.vibratoAmt > 0.35)
                        color: root.accentColor
                        opacity: wordSlot.envelope * 0.22 * Math.max(wordSlot.sustainAmt, wordSlot.riseAmt, wordSlot.vibratoAmt)
                    }

                    // Unsung / base word layer
                    StyledText {
                        id: baseWordLabel
                        text: wordSlot.wordText
                        font.pixelSize: root.fontPixelSize
                        font.weight: root.activeFontWeight
                        font.italic: root.fontItalic
                        color: wordSlot.isSung
                            ? ColorUtils.applyAlpha(root.activeColor, 0.90)
                            : ColorUtils.applyAlpha(root.activeColor, 0.36)
                    }

                    // Progressive left-to-right karaoke fill sweep while singing
                    Item {
                        id: progressiveFillClip
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.ceil(parent.width * wordSlot.progress)
                        clip: true
                        visible: wordSlot.progress > 0 && !wordSlot.isSung

                        StyledText {
                            width: baseWordLabel.implicitWidth
                            height: baseWordLabel.implicitHeight
                            text: wordSlot.wordText
                            font.pixelSize: root.fontPixelSize
                            font.weight: root.activeFontWeight
                            font.italic: root.fontItalic
                            color: wordSlot.sungHighlightColor
                        }
                    }

                    // Kéo dài (Sustain) / Ngân nga (Vibrato) expressive underline bar
                    Rectangle {
                        id: sustainBar
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -2
                        height: wordSlot.vibratoAmt > 0.45 ? 2.5 : 2
                        radius: height / 2
                        visible: wordSlot.isSinging && (wordSlot.sustainAmt > 0.40 || wordSlot.vibratoAmt > 0.40)
                        width: Math.max(4, parent.width * wordSlot.progress)
                        color: root.accentColor
                        opacity: 0.85 * wordSlot.envelope
                    }
                }
            }
        }
    }
}
