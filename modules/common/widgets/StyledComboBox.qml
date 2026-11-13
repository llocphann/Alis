import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions

ComboBox {
    id: root

    // Settings search integration (optional)
    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1
    property string settingsSearchLabel: ""
    property string settingsSearchDescription: ""
    property list<string> settingsSearchKeywords: []

    property real baseHeight: 38
    // Opt-in: compact triggers may open a wider menu for long option labels.
    property real popupMinimumWidth: 0
    readonly property bool abyssStyle: Config.options?.panelFamily === "abyss"
    property real radius: abyssStyle ? baseHeight/2 : Appearance.rounding.small

    hoverEnabled: true
    opacity: root.enabled ? 1 : 0.4

    HoverHandler {
        acceptedDevices: PointerDevice.Mouse
        cursorShape: Qt.PointingHandCursor
    }

    readonly property color _bgColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.08) : Appearance.colors.colLayer2
    readonly property color _bgHoverColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.16) : Appearance.colors.colLayer2Hover
    readonly property color _bgActiveColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.24) : Appearance.colors.colLayer2Active
    readonly property color _textColor: Appearance.colors.colOnLayer2
    readonly property color _subtextColor: Appearance.colors.colSubtext
    readonly property color _borderColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.28) : "transparent"
    readonly property real _borderWidth: abyssStyle && visualFocus ? 1 : 0
    readonly property color _popupColor: Appearance.colors.colLayer3Base
    readonly property color _popupBorderColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.35) : Appearance.colors.colLayer0Border
    readonly property color _popupHoverColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.12) : Appearance.colors.colLayer3Hover
    readonly property color _selectedColor: abyssStyle ? Qt.alpha(Appearance.colors.colPrimary,.22) : Appearance.colors.colPrimaryContainer

    background: Rectangle {
        implicitHeight: root.baseHeight
        radius: root.radius
        color: root.down ? root._bgActiveColor
            : root.hovered ? root._bgHoverColor
            : root._bgColor
        border.width: root._borderWidth
        border.color: root._borderColor

        Behavior on color {
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
        Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
    }

    contentItem: RowLayout {
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            text: {
                const dt = String(root.displayText ?? "").trim();
                if (dt.length > 0 && !dt.startsWith("[object ") && !dt.startsWith("QObject(") && dt !== "undefined" && dt !== "null")
                    return dt;
                if (root.currentIndex >= 0 && root.model) {
                    // Qt wraps list models as array-like objects, not JavaScript Arrays.
                    const item = typeof root.model.get === "function"
                        ? root.model.get(root.currentIndex)
                        : (root.model.length !== undefined && root.currentIndex < root.model.length
                            ? root.model[root.currentIndex] : null);
                    if (item) {
                        const resolved = root._resolveItemDisplayText(item, root.textRole, root.currentIndex);
                        if (resolved.length > 0)
                            return resolved;
                    }
                }
                return "";
            }
            color: root._textColor
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        MaterialSymbol {
            Layout.rightMargin: 8
            text: "expand_more"
            iconSize: Appearance.font.pixelSize.normal
            color: root._subtextColor
            rotation: root.popup.visible ? 180 : 0
            Behavior on rotation {
                enabled: Appearance.animationsEnabled
                RotationAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    direction: RotationAnimation.Shortest
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }
    }

    // Base ComboBox ships its own arrow indicator alongside this custom contentItem —
    // left unset, the two stack and eat into the text's width (root cause of dropdown
    // labels looking truncated/shoved right). Custom "expand_more" above is the only one.
    indicator: Item {}

    popup: Popup {
        y: root.height + 4
        margins: 8
        width: Math.max(root.width,root.popupMinimumWidth)
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 300)
        padding: 4
        onOpened: {
            const win = root.QsWindow?.window
            if (win && typeof win.registerOverlayPopup === "function")
                win.registerOverlayPopup(root.popup, popupBg)
        }
        onClosed: {
            const win = root.QsWindow?.window
            if (win && typeof win.unregisterOverlayPopup === "function")
                win.unregisterOverlayPopup(root.popup)
        }

        // Shared contextual reveal: grow + fade from the field instead of a hard
        // appear. Durations run through calcEffectiveDuration, so animations
        // become instant when the global animation switch is disabled.
        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: Appearance.motion.popupReveal.enableFade ? 0 : 1; to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.motion.popupReveal.enterBezierCurve
            }
            NumberAnimation {
                property: "scale"
                from: Appearance.motion.popupReveal.enableScale ? Appearance.motion.popupReveal.closedScale : 1; to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.motion.popupReveal.enterBezierCurve
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1; to: Appearance.motion.popupReveal.enableFade ? 0 : 1
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            NumberAnimation {
                property: "scale"
                from: 1; to: Appearance.motion.popupReveal.enableScale ? Appearance.motion.popupReveal.closedScale : 1
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
        }

        background: Rectangle {
            id: popupBg
            onXChanged: if (root.popup.visible) root.QsWindow?.window?.bumpOverlayBounds?.()
            onYChanged: if (root.popup.visible) root.QsWindow?.window?.bumpOverlayBounds?.()
            onWidthChanged: if (root.popup.visible) root.QsWindow?.window?.bumpOverlayBounds?.()
            onHeightChanged: if (root.popup.visible) root.QsWindow?.window?.bumpOverlayBounds?.()
            radius: root.abyssStyle ? 16 : root.radius
            color: root._popupColor
            border.width: root.abyssStyle ? 0 : 1
            border.color: root._popupBorderColor

            Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }
            Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
            Behavior on border.width { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
            Behavior on border.color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        }

        contentItem: ListView {
            id: popupList
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: popupList.contentHeight > 290 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }
        }
    }

    function _resolveItemDisplayText(item, role, idx): string {
        if (item === undefined || item === null)
            return "";
        if (typeof item !== "object") {
            const s = String(item).trim();
            return (!s.startsWith("[object ") && !s.startsWith("QObject(") && s !== "undefined" && s !== "null") ? s : "";
        }
        if (role) {
            try {
                const t = item[role];
                if (t !== undefined && t !== null && typeof t !== "object") {
                    const s = String(t).trim();
                    if (s.length > 0 && !s.startsWith("[object ") && !s.startsWith("QObject(") && s !== "undefined" && s !== "null")
                        return s;
                }
            } catch (_) {}
        }
        const candidates = [
            item.label,
            item.rawLabel,
            item.displayName,
            item.name,
            item.title,
            item.text,
            (typeof item.model === "string" ? item.model : undefined),
            (typeof item.id === "string" ? item.id : undefined),
            (typeof item.value === "string" ? item.value : undefined),
            (typeof item.key === "string" ? item.key : undefined)
        ];
        for (let i = 0; i < candidates.length; ++i) {
            const c = candidates[i];
            if (c !== undefined && c !== null && typeof c !== "object") {
                const s = String(c).trim();
                if (s.length > 0 && !s.startsWith("[object ") && !s.startsWith("QObject(") && s !== "undefined" && s !== "null")
                    return s;
            }
        }
        if (typeof item.model === "object" && item.model !== null) {
            const sub = [
                item.model.name,
                item.model.displayName,
                item.model.label,
                (typeof item.model.model === "string" ? item.model.model : undefined),
                (typeof item.model.id === "string" ? item.model.id : undefined)
            ];
            for (let i = 0; i < sub.length; ++i) {
                const sc = sub[i];
                if (sc !== undefined && sc !== null && typeof sc !== "object") {
                    const s = String(sc).trim();
                    if (s.length > 0 && !s.startsWith("[object ") && !s.startsWith("QObject(") && s !== "undefined" && s !== "null")
                        return s;
                }
            }
        }
        if (typeof root.textAt === "function" && idx !== undefined && idx >= 0) {
            try {
                const at = String(root.textAt(idx) ?? "").trim();
                if (at.length > 0 && !at.startsWith("[object ") && !at.startsWith("QObject(") && at !== "undefined" && at !== "null")
                    return at;
            } catch (_) {}
        }
        try {
            const str = String(item).trim();
            if (str.length > 0 && !str.startsWith("[object ") && !str.startsWith("QObject(") && str !== "undefined" && str !== "null")
                return str;
        } catch (_) {}
        return "";
    }

    delegate: ItemDelegate {
        id: delegateItem
        required property int index
        required property var modelData

        width: Math.max(root.width - 8, root.popup.width - 8)
        height: 36
        highlighted: root.highlightedIndex === index
        hoverEnabled: true

        HoverHandler {
            acceptedDevices: PointerDevice.Mouse
            cursorShape: Qt.PointingHandCursor
        }

        background: Rectangle {
            radius: Appearance.rounding.unsharpenmore
            color: delegateItem.index === root.currentIndex ? root._selectedColor
                : delegateItem.hovered || delegateItem.highlighted ? root._popupHoverColor
                : "transparent"

            Behavior on color {
                animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }
        }

        contentItem: RowLayout {
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                text: root._resolveItemDisplayText(delegateItem.modelData, root.textRole, delegateItem.index)
                font.pixelSize: Appearance.font.pixelSize.small
                color: root._textColor
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            MaterialSymbol {
                Layout.rightMargin: 8
                text: "check"
                iconSize: Appearance.font.pixelSize.small
                color: root._textColor
                visible: delegateItem.index === root.currentIndex
            }
        }
    }

    function _findSettingsContext() {
        var page = null;
        var sectionTitle = "";
        var groupTitle = "";
        var p = root.parent;
        while (p) {
            if (!page && p.hasOwnProperty("settingsPageIndex")) {
                page = p;
            }
            if (p.hasOwnProperty("title")) {
                if (!sectionTitle && p.hasOwnProperty("icon")) {
                    sectionTitle = p.title;
                } else if (!groupTitle && !p.hasOwnProperty("icon")) {
                    groupTitle = p.title;
                }
            }
            p = p.parent;
        }
        return { page: page, sectionTitle: sectionTitle, groupTitle: groupTitle };
    }

    function focusFromSettingsSearch() {
        var p = root.parent;
        while (p) {
            if (p.hasOwnProperty("expanded") && p.hasOwnProperty("collapsible")) {
                p.expanded = true;
                break;
            }
            p = p.parent;
        }
        root.forceActiveFocus();
    }

    Component.onCompleted: {
        if (!enableSettingsSearch)
            return;
        if (typeof SettingsSearchRegistry === "undefined")
            return;

        var ctx = _findSettingsContext();
        var page = ctx.page;
        var pageIndex = page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1;
        if (pageIndex < 0)
            return;

        var sectionTitle = ctx.sectionTitle;
        var label = root.settingsSearchLabel || ctx.groupTitle || sectionTitle;

        settingsSearchOptionId = SettingsSearchRegistry.registerOption({
            control: root,
            pageIndex: pageIndex,
            pageName: page && page.settingsPageName ? page.settingsPageName : "",
            section: sectionTitle,
            label: label,
            description: root.settingsSearchDescription || "",
            keywords: root.settingsSearchKeywords || []
        });
    }

    Component.onDestruction: {
        const win = root.QsWindow?.window
        if (win && typeof win.unregisterOverlayPopup === "function")
            win.unregisterOverlayPopup(root.popup)
        if (typeof SettingsSearchRegistry !== "undefined") {
            SettingsSearchRegistry.unregisterControl(root);
        }
    }
}
