pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.abyss.looks
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Standalone screenshot annotation editor (Edit snip action). Reuses
// RegionAnnotationCanvas for all drawing/mosaic/step/text tools and exports
// the composited image to clipboard and Directories.screenshotsPath.
PanelWindow {
    id: root

    property string imagePath: GlobalStates.annotationEditorPath
    signal finished()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:annotationEditor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }

    property string tool: "pen"
    property color strokeColor: Appearance.m3colors.m3primary
    property real strokeWidth: 4
    property bool stylePopoverOpen: false
    property bool _exportPending: false
    property bool _exportInFlight: false
    property bool _closeAfterExport: false

    readonly property var toolDefs: [
        { "tool": "pen",       "icon": "edit",                   "tip": Translation.tr("Pen (1)") },
        { "tool": "arrow",     "icon": "north_east",             "tip": Translation.tr("Arrow (2)") },
        { "tool": "rect",      "icon": "rectangle",              "tip": Translation.tr("Rectangle (3)") },
        { "tool": "ellipse",   "icon": "radio_button_unchecked", "tip": Translation.tr("Ellipse (4)") },
        { "tool": "highlight", "icon": "ink_highlighter",        "tip": Translation.tr("Highlighter (5)") },
        { "tool": "text",      "icon": "title",                  "tip": Translation.tr("Text (6)") },
        { "tool": "pixelate",  "icon": "blur_on",                "tip": Translation.tr("Pixelate (7)") },
        { "tool": "step",      "icon": "looks_one",              "tip": Translation.tr("Step badge (8)") }
    ]

    function undo() { annotationCanvas.undo(); }
    function redo() { annotationCanvas.redo(); }
    function clearAll() { annotationCanvas.clearAll(); }

    function close() {
        // Keep the QML callback context alive until an accepted grab finishes.
        if (_exportInFlight) {
            _closeAfterExport = true;
            return;
        }
        _exportPending = false;
        exportWaitTimer.stop();
        exportGiveUpTimer.stop();
        GlobalStates.annotationEditorOpen = false;
        GlobalStates.annotationEditorPath = "";
        root.finished();
    }

    Item {
        id: keySink
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) {
                if (annotationCanvas.textEditing) {
                    annotationCanvas.cancelActiveText();
                } else if (root.stylePopoverOpen) {
                    root.stylePopoverOpen = false;
                } else {
                    root.close();
                }
                e.accepted = true;
                return;
            }
            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                    && (e.modifiers & Qt.ControlModifier)) {
                root.exportImage();
                e.accepted = true;
                return;
            }
            if (annotationCanvas.handleKey(e))
                return;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    ColumnLayout {
        id: editorStack
        anchors.centerIn: parent
        spacing: 14
        opacity: sourceImage.status === Image.Ready || sourceImage.status === Image.Error ? 1 : 0
        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            animation: NumberAnimation { duration: Appearance.animation.elementMoveEnter.duration; easing.type: Appearance.animation.elementMoveEnter.type }
        }

        // Composited canvas (image + annotations)
        Item {
            id: captureArea
            Layout.alignment: Qt.AlignHCenter
            readonly property real maxW: root.width * 0.84
            readonly property real maxH: root.height * 0.78
            readonly property real iw: sourceImage.sourceSize.width
            readonly property real ih: sourceImage.sourceSize.height
            readonly property real fit: (iw > 0 && ih > 0) ? Math.min(maxW / iw, maxH / ih, 1) : 1
            implicitWidth: iw > 0 ? Math.round(iw * fit) : 480
            implicitHeight: ih > 0 ? Math.round(ih * fit) : 320
            width: implicitWidth
            height: implicitHeight

            Rectangle {
                id: captureClip
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
            }

            Image {
                id: sourceImage
                anchors.fill: parent
                source: root.imagePath !== "" ? `file://${root.imagePath}` : ""
                fillMode: Image.Stretch
                smooth: true
                cache: false
            }

            RegionAnnotationCanvas {
                id: annotationCanvas
                anchors.fill: parent
                z: 5
                imageSource: sourceImage.source
                tool: root.tool
                strokeColor: root.strokeColor
                strokeWidth: root.strokeWidth
                interactive: true
                handleInternalPointer: true
                onToolSelected: (nextTool) => {
                    if (nextTool.length > 0)
                        root.tool = nextTool;
                }
                onEditingTextFinished: keySink.forceActiveFocus()
            }
        }

        // Compact color & width strip
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: root.stylePopoverOpen
            implicitWidth: editorStyleRow.implicitWidth + 16
            implicitHeight: 34
            radius: 12
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            RowLayout {
                id: editorStyleRow
                anchors.centerIn: parent
                spacing: 6

                Repeater {
                    model: annotationCanvas.palette
                    delegate: Rectangle {
                        id: editorSwatch
                        required property var modelData
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 16
                        implicitHeight: 16
                        radius: 8
                        color: modelData
                        border.width: String(root.strokeColor) === String(modelData) ? 2 : 1
                        border.color: String(root.strokeColor) === String(modelData)
                            ? Appearance.colors.colOnLayer0
                            : Appearance.colors.colLayer0Border
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -2
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.strokeColor = editorSwatch.modelData
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 16
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.4
                }

                Repeater {
                    model: [
                        { "label": "S", "width": 2 },
                        { "label": "M", "width": 4 },
                        { "label": "L", "width": 8 }
                    ]
                    delegate: RippleButton {
                        id: editorWidthBtn
                        required property var modelData
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 24
                        implicitHeight: 22
                        buttonRadius: 8
                        toggled: Math.abs(root.strokeWidth - modelData.width) < 0.5
                        colBackground: "transparent"
                        colBackgroundHover: Qt.alpha(AbyssStyle.accent, 0.16)
                        colBackgroundToggled: Qt.alpha(AbyssStyle.accent, 0.28)
                        onClicked: root.strokeWidth = editorWidthBtn.modelData.width
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: editorWidthBtn.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: editorWidthBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }

        // Compact 38px Abyss-styled toolbar matching screenshot overlay
        Toolbar {
            id: editorToolbar
            Layout.alignment: Qt.AlignHCenter
            padding: 4
            spacing: 2
            minBackgroundHeight: 38
            radius: 16

            component EditorBtn: RippleButton {
                id: eb
                required property string iconName
                property string tip: ""
                property bool emphasized: false
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: 12
                colBackground: emphasized
                    ? Appearance.colors.colPrimary
                    : (toggled ? Qt.alpha(AbyssStyle.accent, 0.24) : "transparent")
                colBackgroundHover: emphasized
                    ? Appearance.colors.colPrimaryHover
                    : Qt.alpha(AbyssStyle.accent, 0.16)
                colBackgroundToggled: Qt.alpha(AbyssStyle.accent, 0.24)
                colRipple: Qt.alpha(AbyssStyle.accent, 0.24)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: eb.iconName
                    iconSize: 17
                    fill: (eb.toggled || eb.emphasized) ? 1 : 0
                    animateFill: true
                    color: eb.emphasized
                        ? Appearance.colors.colOnPrimary
                        : (eb.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2)
                }
                StyledToolTip {
                    text: eb.tip
                    visible: eb.tip.length > 0 && eb.buttonHovered
                }
            }

            Repeater {
                model: root.toolDefs
                delegate: EditorBtn {
                    required property var modelData
                    iconName: modelData.icon
                    tip: modelData.tip
                    toggled: root.tool === modelData.tool
                    onClicked: root.tool = modelData.tool
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                implicitWidth: 1
                implicitHeight: 20
                color: Appearance.colors.colOutlineVariant
                opacity: 0.35
            }

            RippleButton {
                id: editorStyleBtn
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: 12
                toggled: root.stylePopoverOpen
                colBackground: toggled ? Qt.alpha(AbyssStyle.accent, 0.22) : "transparent"
                colBackgroundHover: Qt.alpha(AbyssStyle.accent, 0.16)
                onClicked: root.stylePopoverOpen = !root.stylePopoverOpen
                contentItem: Item {
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.max(10, Math.min(18, Math.round(9 + root.strokeWidth)))
                        height: width
                        radius: width / 2
                        color: root.strokeColor
                        border.width: 1.5
                        border.color: Appearance.colors.colOnLayer0
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Color & stroke width")
                    visible: editorStyleBtn.buttonHovered
                }
            }

            EditorBtn {
                iconName: "undo"
                tip: Translation.tr("Undo (Ctrl+Z)")
                enabled: annotationCanvas.canUndo
                onClicked: annotationCanvas.undo()
            }

            EditorBtn {
                iconName: "redo"
                tip: Translation.tr("Redo (Ctrl+Shift+Z)")
                enabled: annotationCanvas.canRedo
                onClicked: annotationCanvas.redo()
            }

            EditorBtn {
                visible: annotationCanvas.hasAnnotations
                iconName: "delete_sweep"
                tip: Translation.tr("Clear annotations")
                onClicked: annotationCanvas.clearAll()
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                implicitWidth: 1
                implicitHeight: 20
                color: Appearance.colors.colOutlineVariant
                opacity: 0.35
            }

            EditorBtn {
                iconName: "done"
                emphasized: true
                tip: Translation.tr("Save & copy to clipboard")
                onClicked: root.exportImage()
            }

            EditorBtn {
                iconName: "close"
                tip: Translation.tr("Discard (Esc)")
                onClicked: root.close()
            }
        }
    }

    // ── Export ────────────────────────────────────────────────────────────────
    readonly property string _tempDir: (Quickshell.env("XDG_RUNTIME_DIR") && Quickshell.env("XDG_RUNTIME_DIR").length > 0)
        ? Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell"
        : "/tmp/quickshell"
    property string _outPath: _tempDir + "/annotated.png"

    function exportImage() {
        if (_exportInFlight) return;
        annotationCanvas.commitActiveText();
        keySink.forceActiveFocus();

        if (sourceImage.status !== Image.Ready) {
            if (_exportPending) return;
            _exportPending = true;
            exportWaitTimer.start();
            exportGiveUpTimer.start();
            return;
        }
        _exportPending = false;
        exportWaitTimer.stop();
        exportGiveUpTimer.stop();

        const iw = sourceImage.sourceSize.width;
        const ih = sourceImage.sourceSize.height;
        if (iw <= 0 || ih <= 0) {
            console.warn("[AnnotationEditor] source size 0, aborting export");
            Quickshell.execDetached(["/usr/bin/notify-send", "Edit failed", "Image not ready", "-a", "Screenshot", "-t", "3000"]);
            return;
        }

        _exportInFlight = true;
        const accepted = captureArea.grabToImage(function(result) {
            const saved = result.saveToFile(root._outPath);
            if (!saved) {
                root._exportInFlight = false;
                console.warn("[AnnotationEditor] saveToFile failed for", root._outPath);
                Quickshell.execDetached(["/usr/bin/notify-send", "Edit failed", "Could not write temp file", "-a", "Screenshot", "-t", "3000"]);
                if (root._closeAfterExport) root.close();
                return;
            }
            cleanupProc.startDetached();
            saveProc.startDetached();
            root._exportInFlight = false;
            root.close();
        }, Qt.size(iw, ih));
        if (!accepted) {
            _exportInFlight = false;
            console.warn("[AnnotationEditor] render grab refused");
            if (_closeAfterExport) close();
        }
    }

    Process {
        id: cleanupProc
        command: ["/usr/bin/bash", "-c", `sleep 3 && /usr/bin/rm -f '${root._outPath}'`]
        onExited: (code) => { if (code !== 0) console.warn("[AnnotationEditor] cleanup exit", code); }
    }

    Process {
        id: prepareTempProc
        command: ["/usr/bin/mkdir", "-p", root._tempDir]
        running: true
        onExited: (code) => { if (code !== 0) console.warn("[AnnotationEditor] temp dir mkdir exit", code); }
    }

    Timer {
        id: exportWaitTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (sourceImage.status === Image.Ready) {
                stop();
                _exportPending = false;
                root.exportImage();
            }
        }
    }
    Timer {
        id: exportGiveUpTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (_exportPending) {
                _exportPending = false;
                exportWaitTimer.stop();
                console.warn("[AnnotationEditor] image load timed out");
                Quickshell.execDetached(["/usr/bin/notify-send", "Edit failed", "Image load timed out", "-a", "Screenshot", "-t", "3000"]);
            }
        }
    }

    Process {
        id: saveProc
        command: ["/usr/bin/bash", "-c", `
            _dir='${StringUtils.shellSingleQuoteEscape(Directories.screenshotsPath)}';
            _fmt='${StringUtils.shellSingleQuoteEscape(Config.options?.regionSelector?.screenshotNameFormat ?? "ss-%Y%m%d-%H%M%S")}';
            mkdir -p "$_dir" || { echo "mkdir failed: $_dir" >&2; exit 1; };
            _ss="$_dir/$(date +"$_fmt").png";
            if ! cp '${root._outPath}' "$_ss"; then
                echo "cp failed: ${root._outPath} -> $_ss" >&2;
                /usr/bin/notify-send "Edit failed" "Could not copy to screenshots folder" -a "Screenshot" -i camera-photo -t 4000;
                exit 2;
            fi;
            _clip_msg="";
            if command -v /usr/bin/wl-copy >/dev/null 2>&1 && /usr/bin/wl-copy < "$_ss" 2>/dev/null && echo -n "$_ss" | /usr/bin/wl-copy --primary 2>/dev/null; then
                _clip_msg=" — copied to clipboard";
            else
                _clip_msg=" — clipboard unavailable (is wl-clipboard running?)";
            fi;
            /usr/bin/notify-send "Screenshot edited" "Saved to $_ss$_clip_msg" -a "Screenshot" -i camera-photo -t 4000;
        `]
        onExited: (code) => {
            if (code !== 0) console.warn("[AnnotationEditor] saveProc exit", code);
        }
    }
}
