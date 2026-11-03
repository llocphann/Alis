import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls

/**
 * Material 3 styled TextField (filled style)
 * https://m3.material.io/components/text-fields/overview
 */
T.TextField {
    id: root
    color: Appearance.colors.colOnSurface
    renderType: Text.NativeRendering
    leftPadding: 12
    rightPadding: 12
    topPadding: 8
    bottomPadding: 8
    implicitHeight: Math.max(40, contentHeight + topPadding + bottomPadding)
    verticalAlignment: TextInput.AlignVCenter

    // Settings search integration
    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1

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
        if (!page || page.settingsPageIndex === undefined || page.settingsPageIndex < 0)
            return;
        var sectionTitle = ctx.sectionTitle;
        var label = root.placeholderText || root.text || ctx.groupTitle || sectionTitle;

        settingsSearchOptionId = SettingsSearchRegistry.registerOption({
            control: root,
            pageIndex: page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1,
            pageName: page && page.settingsPageName ? page.settingsPageName : "",
            section: sectionTitle,
            label: label,
            description: "",
            keywords: []
        });
    }

    Component.onDestruction: {
        if (typeof SettingsSearchRegistry !== "undefined") {
            SettingsSearchRegistry.unregisterControl(root);
        }
    }

    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.colors.colSubtext
    clip: true

    Text {
        anchors.fill: parent
        anchors.leftMargin: root.leftPadding
        anchors.rightMargin: root.rightPadding
        verticalAlignment: Text.AlignVCenter
        visible: !root.length && !root.preeditText
        text: root.placeholderText
        font: root.font
        color: root.placeholderTextColor
        opacity: 0.65
        elide: Text.ElideRight
    }

    background: Item {
        implicitHeight: 40

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer1
            topLeftRadius: 4
            topRightRadius: 4

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 1
                color: root.activeFocus ? Appearance.colors.colPrimary
                    : root.hovered ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant

                Behavior on color {
                    animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
            }
        }
    }

    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.normal ?? 16
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
    }

    TextInputContextMenu {
        target: root
    }
}
