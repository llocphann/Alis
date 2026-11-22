pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets

/**
 * Pure Qt6/Quickshell replacement for Kirigami.Icon.
 * Resolves absolute paths, file:// URLs, image:// providers, and Freedesktop
 * theme icon names via Quickshell.iconPath, with automatic fallback and
 * optional monochrome masking.
 */
Item {
    id: root

    property var source: ""
    property string fallback: "application-x-executable"
    property bool isMask: false
    property color color: "transparent"
    property bool roundToIconSize: true
    property bool animated: false
    property real implicitSize: 24

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    property bool _primaryFailed: false

    onSourceChanged: root._primaryFailed = false

    function _toImageSource(raw, useFallbackOnMissing: bool): string {
        const text = String(raw ?? "").trim()
        if (text.length === 0)
            return ""
        if (text.startsWith("file://") || text.startsWith("qrc:/")
                || text.startsWith("image://") || text.startsWith("http://")
                || text.startsWith("https://")) {
            return text
        }
        if (text.startsWith("/"))
            return "file://" + text
        if (useFallbackOnMissing)
            return Quickshell.iconPath(text, "application-x-executable")
        return Quickshell.iconPath(text, true)
    }

    readonly property bool _hasSource: String(root.source ?? "").trim().length > 0
    readonly property string _primaryUrl: _toImageSource(root.source, false)
    readonly property string _fallbackUrl: {
        const rawFb = String(root.fallback ?? "").trim()
        if (rawFb.length === 0)
            return ""
        const fb = _toImageSource(rawFb, false)
        if (fb.length > 0)
            return fb
        return Quickshell.iconPath(rawFb, "application-x-executable")
    }
    readonly property string resolvedUrl: {
        if (!root._hasSource)
            return ""
        if (!root._primaryFailed && root._primaryUrl.length > 0)
            return root._primaryUrl
        return root._fallbackUrl
    }
    readonly property bool _maskActive: root.isMask && root.color.a > 0
    readonly property int _renderSize: {
        const dim = Math.max(root.width, root.height, root.implicitSize)
        return Math.max(1, Math.min(256, Math.round(dim)))
    }

    Image {
        id: iconImg
        anchors.fill: parent
        visible: !root._maskActive
        source: root.resolvedUrl
        fillMode: Image.PreserveAspectFit
        sourceSize.width: root._renderSize
        sourceSize.height: root._renderSize
        smooth: true
        mipmap: true
        asynchronous: true
        onStatusChanged: {
            if (status === Image.Error && !root._primaryFailed && root._primaryUrl.length > 0) {
                root._primaryFailed = true
            }
        }
    }

    Loader {
        active: root._maskActive && iconImg.status === Image.Ready
        anchors.fill: iconImg
        sourceComponent: ColorOverlay {
            source: iconImg
            color: root.color
        }
    }
}
