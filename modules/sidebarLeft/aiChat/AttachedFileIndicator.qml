pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root

    signal remove()
    property bool canRemove: true
    property string filePath: ""
    property string mimeType: ""
    property real maxHeight: 200
    property real imageWidth: -1
    property real imageHeight: -1
    property real scale: (imageWidth > 0 && imageHeight > 0)
        ? Math.min(root.maxHeight / imageHeight, root.width / imageWidth)
        : 1
    property int _probeGeneration: 0
    property bool _destroyed: false
    onFilePathChanged: refresh()
    visible: filePath !== ""

    Component.onDestruction: {
        root._destroyed = true;
        fileTypeProc.queuedRequest = null;
        imageSizeProc.queuedRequest = null;
        imageSizeProc.awaitingResult = false;
        imageSizeFallbackProc.queuedRequest = null;
        fileTypeProc.running = false;
        imageSizeProc.running = false;
        imageSizeFallbackProc.running = false;
    }

    function _safeCliPath(path) {
        return path.startsWith("-") ? ("./" + path) : path;
    }

    function applyImageDimensions(rawText) {
        const firstLine = String(rawText ?? "").trim().split(/\r?\n/)[0]?.trim() ?? "";
        const match = firstLine.match(/^(\d+)(?:\s*[xX]\s*|\s+)(\d+)$/);
        if (!match)
            return false;
        const width = parseInt(match[1], 10);
        const height = parseInt(match[2], 10);
        if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0)
            return false;
        root.imageWidth = width;
        root.imageHeight = height;
        return true;
    }

    function _startOrQueue(proc, generation, targetPath, command) {
        if (root._destroyed || generation !== root._probeGeneration || targetPath === "")
            return;
        if (proc.running) {
            proc.queuedRequest = {
                generation: generation,
                targetPath: targetPath,
                command: command
            };
            proc.running = false;
            return;
        }
        proc.queuedRequest = null;
        proc.activeGeneration = generation;
        proc.activeTargetPath = targetPath;
        if (proc === imageSizeProc) {
            proc.matched = false;
            proc.awaitingResult = true;
        }
        proc.exec(command);
    }

    function _drainQueue(proc) {
        const req = proc.queuedRequest;
        proc.queuedRequest = null;
        if (!req || root._destroyed || req.generation !== root._probeGeneration || req.targetPath === "")
            return;
        root._startOrQueue(proc, req.generation, req.targetPath, req.command);
    }

    function refresh() {
        root._probeGeneration++;
        root.mimeType = "";
        root.imageWidth = -1;
        root.imageHeight = -1;
        fileTypeProc.queuedRequest = null;
        imageSizeProc.queuedRequest = null;
        imageSizeProc.awaitingResult = false;
        imageSizeFallbackProc.queuedRequest = null;
        imageSizeProc.running = false;
        imageSizeFallbackProc.running = false;
        if (filePath === "") {
            fileTypeProc.running = false;
            return;
        }
        root._startOrQueue(fileTypeProc, root._probeGeneration, filePath, ["file", "-b", "--mime-type", "--", root._safeCliPath(filePath)]);
    }

    Process {
        id: fileTypeProc
        property int activeGeneration: 0
        property string activeTargetPath: ""
        property var queuedRequest: null
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._destroyed || fileTypeProc.activeGeneration !== root._probeGeneration)
                    return;
                root.mimeType = this.text.trim();
                if (root.mimeType.startsWith("image/")) {
                    const targetPath = fileTypeProc.activeTargetPath;
                    root._startOrQueue(
                        imageSizeProc,
                        fileTypeProc.activeGeneration,
                        targetPath,
                        [Quickshell.shellPath("scripts/native-dispatch"), "image", "identify", targetPath]
                    );
                }
            }
        }
        onRunningChanged: {
            if (!running)
                root._drainQueue(fileTypeProc);
        }
    }

    Process {
        id: imageSizeProc
        property int activeGeneration: 0
        property string activeTargetPath: ""
        property var queuedRequest: null
        property bool awaitingResult: false
        property bool matched: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._destroyed || imageSizeProc.activeGeneration !== root._probeGeneration)
                    return;
                if (root.applyImageDimensions(this.text))
                    imageSizeProc.matched = true;
            }
        }
        onRunningChanged: {
            if (running)
                return;
            if (awaitingResult) {
                awaitingResult = false;
                const gen = activeGeneration;
                const path = activeTargetPath;
                if (!matched && !root._destroyed && gen === root._probeGeneration && path !== "") {
                    Qt.callLater(() => {
                        if (!root || root._destroyed || gen !== root._probeGeneration || imageSizeProc.matched || path === "")
                            return;
                        root._startOrQueue(
                            imageSizeFallbackProc,
                            gen,
                            path,
                            ["identify", "-ping", "-format", "%wx%h\n", root._safeCliPath(path)]
                        );
                    });
                }
            }
            root._drainQueue(imageSizeProc);
        }
    }

    Process {
        id: imageSizeFallbackProc
        property int activeGeneration: 0
        property string activeTargetPath: ""
        property var queuedRequest: null
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._destroyed || imageSizeFallbackProc.activeGeneration !== root._probeGeneration)
                    return;
                root.applyImageDimensions(this.text);
            }
        }
        onRunningChanged: {
            if (!running)
                root._drainQueue(imageSizeFallbackProc);
        }
    }

    // Styles/widgets
    property real horizontalPadding: 10
    property real verticalPadding: 10
    radius: Appearance.rounding.small - anchors.margins
    color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2 : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface : Appearance.colors.colLayer2
    implicitHeight: visible ? (contentItem.implicitHeight + verticalPadding * 2) : 0

    ColumnLayout {
        id: contentItem
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
        }

        RowLayout {
            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: {
                    if (root.mimeType.startsWith("image/"))
                        return "image";
                    if (root.mimeType.startsWith("audio/"))
                        return "music_note";
                    if (root.mimeType.startsWith("video/"))
                        return "movie";
                    if (root.mimeType === "application/pdf")
                        return "picture_as_pdf";
                    if (root.mimeType.startsWith("text/"))
                        return "description";
                    return "file_present";
                }
                iconSize: Appearance.font.pixelSize.hugeass
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: root.filePath
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.monospace
                wrapMode: Text.Wrap
            }

            RippleButton {
                visible: root.canRemove
                Layout.alignment: Qt.AlignTop
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                    : Appearance.alisEverywhere ? Appearance.alis.colLayer1
                    : Appearance.auroraEverywhere ? "transparent" : Appearance.colors.colLayer2
                implicitHeight: 28
                implicitWidth: 28
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colOnSurfaceVariant
                }

                onClicked: root.remove()
            }
        }

        Loader {
            id: imagePreviewLoader
            active: (root.imageWidth > 0) && (root.imageHeight > 0)
            visible: active
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: Item {
                implicitHeight: root.imageHeight * root.scale
                implicitWidth: imagePreview.implicitWidth
                StyledImage {
                    id: imagePreview
                    anchors.fill: parent
                    source: Qt.resolvedUrl(root.filePath)
                    fillMode: Image.PreserveAspectFit
                    antialiasing: true
                    width: root.imageWidth * root.scale
                    height: root.imageHeight * root.scale
                    sourceSize.width: root.imageWidth * root.scale
                    sourceSize.height: root.imageHeight * root.scale

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: imagePreview.width
                            height: imagePreview.height
                            radius: Appearance.rounding.normal
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: 1
                        border.color: Appearance.alisEverywhere ? Appearance.alis.colBorder : Appearance.colors.colOutlineVariant
                        radius: Appearance.rounding.normal
                    }
                }
            }
        }
    }
}
