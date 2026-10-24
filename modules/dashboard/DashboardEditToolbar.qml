import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks

Rectangle {
    id: root

    required property var canvasController
    property var tabController: null
    readonly property bool naming: tabController?.tabNamingActive ?? false
    onNamingChanged: if (naming) Qt.callLater(() => {
        if (root.naming) tabNameInput.forceActiveFocus()
    })
    property bool embeddedSurface: false
    readonly property bool editing: root.canvasController?.editMode ?? false
    readonly property var hiddenIds: root.canvasController?.hiddenIds ?? []
    readonly property bool abyssMode:
        (Config.options?.panelFamily ?? "abyss") === "abyss"

    readonly property real horizontalPadding: root.abyssMode
        ? Math.max(10, AbyssStyle.contentPadding * 0.55) : 7
    readonly property real sectionGap: 8
    readonly property real availableModulesNaturalWidth:
        root.hiddenIds.length > 0 ? availableModulesRow.implicitWidth : 0
    readonly property int visibleActionCount:
        7 + ((root.canvasController?.responsiveWorkspace ?? false) ? 0 : 1)
            + (root.hiddenIds.length > 0 ? 1 : 0)
    readonly property real toolbarRowNaturalWidth:
        root.visibleActionCount*34 + (root.visibleActionCount-1)*6
        + (root.hiddenIds.length > 0
            ? root.sectionGap + root.availableModulesNaturalWidth : 0)
    implicitWidth: Math.ceil(Math.max(
        toolbarTitle.implicitWidth,
        root.naming ? 390 : Math.min(760,root.toolbarRowNaturalWidth))
        + root.horizontalPadding * 2)
    implicitHeight: toolbarColumn.implicitHeight + root.horizontalPadding * 2
    visible: root.editing || root.naming
    radius: Appearance.rounding.large
    topLeftRadius: radius
    topRightRadius: radius
    bottomLeftRadius: root.abyssMode ? radius : 0
    bottomRightRadius: root.abyssMode ? radius : 0
    color: root.embeddedSurface ? "transparent" : root.abyssMode
        ? Qt.alpha(AbyssStyle.surfaceDeep,
            Math.max(0.72, AbyssStyle.contentOpacity))
        : Appearance.colors.colLayer0
    border.width: root.abyssMode && !root.embeddedSurface ? 1 : 0
    border.color: root.abyssMode
        ? Qt.alpha(AbyssStyle.accent, 0.22) : "transparent"
    clip: true

    ColumnLayout {
        id: toolbarColumn
        anchors.fill: parent
        anchors.margins: root.horizontalPadding
        spacing: 5

        StyledText {
            id: toolbarTitle
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.naming
                ? (root.tabController?._customDialogMode === "rename"
                    ? Translation.tr("Rename custom tab") : Translation.tr("Create custom tab"))
                : root.canvasController?.layoutMessage
                || ((root.canvasController?.workspace?.overflow?.length ?? 0) > 0
                    ? Translation.tr("%1 modules need more space").arg(root.canvasController.workspace.overflow.length)
                    : root.canvasController?.selectedId?.length > 0
                        ? Translation.tr("Editing %1").arg(root.canvasController._label(root.canvasController.selectedId))
                        : Translation.tr("Edit widgets"))
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: root.abyssMode
                ? AbyssStyle.textColor : Appearance.colors.colOnLayer0
            elide: Text.ElideRight
        }

        // Temporarily occupy the original Edit Dashboard Layout bar instead
        // of opening a modal over the cards. The host reserves the same space.
        RowLayout {
            id: tabNamingRow
            objectName: "dashboardTabNamingToolbar"
            visible: root.naming
            Layout.fillWidth: true
            spacing: 6
            TextField {
                id: tabNameInput
                objectName: "dashboardToolbarTabName"
                Layout.fillWidth: true
                Layout.minimumWidth: 160
                implicitHeight: 40
                maximumLength: 41
                hoverEnabled: true
                font.pixelSize: Appearance.font.pixelSize.normal
                verticalAlignment: TextInput.AlignVCenter
                leftPadding: 14
                rightPadding: 14
                topPadding: 6
                bottomPadding: 6
                color: root.abyssMode
                    ? AbyssStyle.textColor : Appearance.colors.colOnLayer1
                placeholderTextColor: root.abyssMode
                    ? AbyssStyle.textColorMuted : Appearance.colors.colSubtext
                selectionColor: Appearance.colors.colPrimaryContainer
                selectedTextColor: Appearance.colors.colOnPrimaryContainer
                placeholderText: Translation.tr("Custom tab name")
                text: root.tabController?._customDialogName ?? ""
                onTextEdited: root.tabController?.setCustomTabName(text)
                onAccepted: root.tabController?.acceptCustomTabDialog()
                readonly property bool invalidName:
                    (root.tabController?._customDialogError?.length ?? 0) > 0

                // Qt's default rectangular focus border doesn't follow our
                // dashboard palette. Provide a rounded, theme-aware surface
                // for Abyss and the other Alis panel families.
                background: Rectangle {
                    id: tabNameBackground
                    objectName: "dashboardTabNameBackground"
                    radius: 12
                    color: root.abyssMode
                        ? AbyssStyle.contentLayer : Appearance.colors.colLayer1
                    border.width: tabNameInput.activeFocus ? 1.5 : 1
                    border.color: tabNameInput.invalidName
                        ? Appearance.colors.colError
                        : tabNameInput.activeFocus
                            ? (root.abyssMode
                                ? Qt.alpha(AbyssStyle.accent, 0.85)
                                : Appearance.colors.colPrimary)
                            : Qt.alpha(root.abyssMode
                                ? AbyssStyle.accent : Appearance.colors.colOutline,
                                tabNameInput.hovered ? 0.52 : 0.30)
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: AbyssStyle.motionFast }
                    }
                    Behavior on border.color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: AbyssStyle.motionFast }
                    }
                    // A subtle inner focus ring gives the field depth without
                    // the hard blue rectangular outline from the default style.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: Math.max(0, tabNameBackground.radius - 3)
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(tabNameInput.invalidName
                            ? Appearance.colors.colError
                            : (root.abyssMode
                                ? AbyssStyle.accent : Appearance.colors.colPrimary), 0.16)
                        visible: tabNameInput.activeFocus
                    }
                }
            }
            RippleButton {
                objectName: "dashboardToolbarCreate"
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                onClicked: root.tabController?.acceptCustomTabDialog()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "check"
                    color: Appearance.colors.colOnPrimaryContainer
                    iconSize: Appearance.font.pixelSize.normal
                }
                StyledToolTip {
                    text: root.tabController?._customDialogMode === "rename"
                        ? Translation.tr("Save name") : Translation.tr("Create tab")
                }
            }
            RippleButton {
                objectName: "dashboardToolbarCancelCreate"
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                onClicked: root.tabController?.cancelCustomTabDialog()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    color: Appearance.colors.colOnLayer1
                    iconSize: Appearance.font.pixelSize.normal
                }
                StyledToolTip { text: Translation.tr("Cancel") }
            }
        }
        StyledText {
            visible: root.naming
                && (root.tabController?._customDialogError?.length ?? 0) > 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.tabController?._customDialogError ?? ""
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smallest
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            id: toolbarRow
            visible: !root.naming
            Layout.fillWidth: true
            spacing: root.sectionGap

            GridLayout {
                id: editActions
                Layout.alignment: Qt.AlignHCenter
                columns: Math.max(1,Math.min(root.visibleActionCount,
                    Math.floor((root.width-root.horizontalPadding*2+6)/40)))
                rowSpacing: 6
                columnSpacing: 6

                EditToolButton {
                    objectName: "dashboardEditDone"
                    iconName: "done"
                    tooltipText: Translation.tr("Done editing")
                    onClicked: root.canvasController?.commitEditMode()
                }
                EditToolButton {
                    objectName: "dashboardEditCancel"
                    iconName: "close"
                    tooltipText: Translation.tr("Cancel editing")
                    onClicked: root.canvasController?.cancelEditMode()
                }
                EditToolButton {
                    objectName: "dashboardEditUndo"
                    iconName: "undo"
                    tooltipText: Translation.tr("Undo last layout change")
                    enabled: root.canvasController?.canUndo ?? false
                    onClicked: root.canvasController?.undoLastEdit()
                }

                EditToolButton {
                    iconName: root.canvasController?.snapEnabled
                        ? "grid_on" : "grid_off"
                    tooltipText: root.canvasController?.snapEnabled
                        ? Translation.tr("Snap to grid: on")
                        : Translation.tr("Snap to grid: off")
                    toggled: root.canvasController?.snapEnabled ?? false
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController.toggleSnap()
                    }
                }

                EditToolButton {
                    visible: !(root.canvasController?.responsiveWorkspace ?? false)
                    iconName: "fit_screen"
                    tooltipText: root.canvasController?.autoAdjustSizeEnabled
                        ? Translation.tr("Auto-adjust affected module sizes: on")
                        : Translation.tr("Auto-adjust affected module sizes: off")
                    toggled:
                        root.canvasController?.autoAdjustSizeEnabled ?? true
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController.toggleAutoAdjustSize()
                    }
                }

                EditToolButton {
                    iconName: root.canvasController?.gridStyle === "lines"
                        ? "grid_4x4"
                        : (root.canvasController?.gridStyle === "cross"
                            ? "add" : "drag_indicator")
                    tooltipText: Translation.tr("Grid style: %1 — click to cycle")
                        .arg(root.canvasController?.gridStyle ?? "dots")
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController._cycleGridStyle()
                    }
                }

                EditToolButton {
                    iconName: "grid_view"
                    tooltipText: Translation.tr("Grid size: %1px — click to cycle")
                        .arg(root.canvasController?.gridSize ?? 24)
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController._cycleGridSize()
                    }
                }

                EditToolButton {
                    iconName: "restart_alt"
                    tooltipText: Translation.tr("Reset dashboard layout")
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController.resetLayout()
                    }
                }

                EditToolButton {
                    visible: root.hiddenIds.length > 0
                    iconName: "auto_awesome_motion"
                    tooltipText: Translation.tr(
                        "Add all modules and fit them automatically")
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController.fitAllWidgets()
                    }
                }
            }

            Flickable {
                id: availableModulesViewport
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.availableModulesNaturalWidth
                Layout.preferredHeight: availableModulesRow.implicitHeight
                visible: root.hiddenIds.length > 0
                contentWidth: availableModulesRow.implicitWidth
                contentHeight: availableModulesRow.implicitHeight
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width

                Row {
                    id: availableModulesRow
                    spacing: 5

                    Repeater {
                        model: root.hiddenIds
                        delegate: RippleButton {
                            required property var modelData
                            implicitHeight: 28
                            implicitWidth: addRow.implicitWidth + 14
                            buttonRadius: Appearance.rounding.full
                            colBackground: root.abyssMode
                                ? Qt.alpha(AbyssStyle.accent, 0.10)
                                : Appearance.colors.colLayer1
                            colBackgroundHover: root.abyssMode
                                ? Qt.alpha(AbyssStyle.accent, 0.18)
                                : Appearance.colors.colLayer2
                            focusPolicy: Qt.StrongFocus
                            onClicked: {
                                if (root.canvasController)
                                    root.canvasController.setWidgetVisible(
                                        String(modelData), true)
                            }

                            RowLayout {
                                id: addRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: root.canvasController?._icon(
                                        String(modelData)) ?? "widgets"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: root.abyssMode
                                        ? AbyssStyle.textColor
                                        : Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    text: root.canvasController?._label(
                                        String(modelData)) ?? String(modelData)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.abyssMode
                                        ? AbyssStyle.textColor
                                        : Appearance.colors.colOnLayer1
                                }
                                MaterialSymbol {
                                    text: "add"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: root.abyssMode
                                        ? AbyssStyle.accent
                                        : Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component EditToolButton: RippleButton {
        id: tool
        property alias iconName: toolIcon.text
        property string tooltipText: ""

        implicitWidth: 34
        implicitHeight: 34
        // Keep every button (including a wrapped row) geometrically centered.
        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
        focusPolicy: Qt.StrongFocus
        buttonText: tool.tooltipText
        buttonRadius: Appearance.rounding.full
        colBackground: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.10)
            : Appearance.colors.colLayer1
        colBackgroundHover: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.18)
            : Appearance.colors.colLayer2
        colBackgroundToggled: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.28)
            : Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.34)
            : Appearance.colors.colPrimaryContainer
        colRippleToggled: root.abyssMode
            ? AbyssStyle.accent : Appearance.colors.colPrimary

        contentItem: Item {
            implicitWidth: tool.implicitWidth
            implicitHeight: tool.implicitHeight
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Appearance.rounding.full
                color: "transparent"
                border.width: tool.visualFocus ? 2 : (tool.toggled ? 1 : 0)
                border.color: tool.visualFocus
                    ? (root.abyssMode
                        ? AbyssStyle.accent : Appearance.colors.colPrimary)
                    : ColorUtils.applyAlpha(
                        root.abyssMode
                            ? AbyssStyle.accent
                            : Appearance.colors.colPrimary, 0.72)
            }

            MaterialSymbol {
                id: toolIcon
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: Appearance.font.pixelSize.normal
                color: root.abyssMode
                    ? (tool.toggled
                        ? AbyssStyle.accent : AbyssStyle.textColor)
                    : (tool.toggled
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer1)
            }
        }

        StyledToolTip { text: tool.tooltipText }
    }
}
