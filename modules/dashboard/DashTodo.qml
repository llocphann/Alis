import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Dashboard-native Todo presentation.
 *
 * The shared Todo service remains the only data/mutation owner. This card keeps
 * Dashboard composition independent from the Sidebar widget so both surfaces
 * can evolve without UI regressions in the other.
 */
DashCard {
    id: root

    title: ""
    icon: ""
    Layout.fillHeight: true
    focus: true

    property int currentTab: 0
    property bool showAddDialog: false

    // The dashboard card can be resized independently from the Sidebar. Keep
    // chrome proportional so the task viewport, not fixed controls, absorbs
    // most of the size change.
    readonly property bool narrowLayout: root.width > 0 && root.width < 285
    readonly property bool shallowLayout: root.height > 0 && root.height < 300
    readonly property bool veryShallowLayout:
        root.height > 0 && root.height < 210
    readonly property int tabControlHeight:
        root.veryShallowLayout ? 28 : (root.narrowLayout ? 30 : 32)
    readonly property int safeEdgeInset: 2
    readonly property int actionButtonSize:
        root.veryShallowLayout ? 30 : 32

    readonly property var indexedTasks: Todo.list.map(function(item, index) {
        return Object.assign({}, item, { originalIndex: index })
    })
    readonly property var unfinishedTasks: root.indexedTasks.filter(
        function(item) { return item.done !== true })
    readonly property var doneTasks: root.indexedTasks.filter(
        function(item) { return item.done === true })
    readonly property var visibleTasks:
        root.currentTab === 0 ? root.unfinishedTasks : root.doneTasks

    function openTodoSettings(): void {
        GlobalStates.openSettingsSection(7, "To-do & Quick Notes")
    }

    function toggleTask(item): void {
        if (!item || Todo.busy)
            return
        if (item.done === true)
            Todo.markUnfinished(item.originalIndex)
        else
            Todo.markDone(item.originalIndex)
    }

    function deleteTask(item): void {
        if (!item || Todo.busy)
            return
        Todo.deleteItem(item.originalIndex)
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_N && Todo.ready && !Todo.busy) {
            root.showAddDialog = true
            event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
            root.currentTab = Math.min(1, root.currentTab + 1)
            event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
            root.currentTab = Math.max(0, root.currentTab - 1)
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false
            event.accepted = true
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: root.veryShallowLayout
            ? 4 : (root.narrowLayout ? 5 : (root.compact ? 6 : 8))

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.safeEdgeInset
            Layout.rightMargin: root.safeEdgeInset
            spacing: root.narrowLayout ? 6 : 10

            MaterialShapeWrappedMaterialSymbol {
                Layout.preferredWidth: root.veryShallowLayout
                    ? 32 : (root.narrowLayout ? 34 : (root.compact ? 38 : 44))
                Layout.preferredHeight: Layout.preferredWidth
                text: "checklist"
                shape: MaterialShape.Shape.Cookie4Sided
                padding: root.veryShallowLayout
                    ? 5 : (root.narrowLayout ? 5 : (root.compact ? 6 : 8))
                iconSize: root.veryShallowLayout
                    ? 18 : (root.narrowLayout ? 19 : (root.compact ? 21 : 24))
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("To Do")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: root.colText
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: !root.veryShallowLayout

                    Rectangle {
                        implicitWidth: Math.min(sourceRow.implicitWidth + 12,
                            root.narrowLayout ? 110 : 150)
                        implicitHeight: sourceRow.implicitHeight + 5
                        radius: height / 2
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            id: sourceRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                text: Todo.backend === "obsidian"
                                    ? "description" : "database"
                                iconSize: Appearance.font.pixelSize.small
                                color: root.colAccent
                            }

                            StyledText {
                                Layout.maximumWidth: root.narrowLayout ? 72 : 112
                                text: Todo.sourceLabel
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: root.colSubtext
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Todo.list.length + " " + Translation.tr("Tasks")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

        }

        Item {
            id: tabShell
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.max(1, Math.min(
                320, root.width - 24))
            implicitHeight: root.tabControlHeight
            clip: false

            readonly property real halfWidth: width / 2
            readonly property real inset: 2
            readonly property real innerHeight: height - inset * 2
            readonly property real cornerRadius: innerHeight / 2
            readonly property real arcKappa: 0.5522847498
            readonly property int tabIconSize: root.narrowLayout ? 14 : 15
            readonly property int badgeSize: root.narrowLayout ? 17 : 18
            readonly property real labelSpacing: 4

            // One canonical inactive silhouette is mirrored between left/right.
            // The outer end and the inward contact end are built from the same
            // radius R and the same cubic-circle constant, so both states are
            // mathematically identical instead of being maintained separately.
            Shape {
                id: inactiveTabShape
                x: root.currentTab === 1
                    ? tabShell.inset
                    : tabShell.halfWidth - tabShell.cornerRadius
                y: tabShell.inset
                width: tabShell.halfWidth + tabShell.cornerRadius
                    - tabShell.inset
                height: tabShell.innerHeight
                z: 1
                preferredRendererType: Shape.CurveRenderer

                transform: Scale {
                    origin.x: inactiveTabShape.width / 2
                    origin.y: inactiveTabShape.height / 2
                    xScale: root.currentTab === 0 ? -1 : 1
                    yScale: 1
                }

                ShapePath {
                    strokeWidth: 0
                    fillColor: {
                        const hovered = root.currentTab === 1
                            ? leftTabHover.hovered
                            : rightTabHover.hovered
                        return hovered
                            ? Appearance.colors.colLayer1Hover
                            : Appearance.colors.colLayer1
                    }

                    startX: tabShell.cornerRadius
                    startY: 0

                    PathLine {
                        x: inactiveTabShape.width
                        y: 0
                    }

                    // Concave half-circle, radius R.
                    PathCubic {
                        control1X: inactiveTabShape.width
                            - tabShell.arcKappa * tabShell.cornerRadius
                        control1Y: 0
                        control2X: inactiveTabShape.width
                            - tabShell.cornerRadius
                        control2Y: tabShell.cornerRadius
                            - tabShell.arcKappa * tabShell.cornerRadius
                        x: inactiveTabShape.width - tabShell.cornerRadius
                        y: tabShell.cornerRadius
                    }
                    PathCubic {
                        control1X: inactiveTabShape.width
                            - tabShell.cornerRadius
                        control1Y: tabShell.cornerRadius
                            + tabShell.arcKappa * tabShell.cornerRadius
                        control2X: inactiveTabShape.width
                            - tabShell.arcKappa * tabShell.cornerRadius
                        control2Y: inactiveTabShape.height
                        x: inactiveTabShape.width
                        y: inactiveTabShape.height
                    }

                    PathLine {
                        x: tabShell.cornerRadius
                        y: inactiveTabShape.height
                    }

                    // Outer half-circle, the exact same R and kappa as above.
                    PathCubic {
                        control1X: tabShell.cornerRadius
                            - tabShell.arcKappa * tabShell.cornerRadius
                        control1Y: inactiveTabShape.height
                        control2X: 0
                        control2Y: tabShell.cornerRadius
                            + tabShell.arcKappa * tabShell.cornerRadius
                        x: 0
                        y: tabShell.cornerRadius
                    }
                    PathCubic {
                        control1X: 0
                        control1Y: tabShell.cornerRadius
                            - tabShell.arcKappa * tabShell.cornerRadius
                        control2X: tabShell.cornerRadius
                            - tabShell.arcKappa * tabShell.cornerRadius
                        control2Y: 0
                        x: tabShell.cornerRadius
                        y: 0
                    }
                }
            }

            // Active tabs are equal-sized half-width pills. Their rounded end
            // uses the same R as the inactive concavity, so the two boundaries
            // meet cleanly without one state becoming wider than the other.
            Rectangle {
                id: activeTabPill
                x: root.currentTab === 0
                    ? tabShell.inset
                    : tabShell.halfWidth
                y: tabShell.inset
                width: tabShell.halfWidth - tabShell.inset
                height: tabShell.innerHeight
                radius: tabShell.cornerRadius
                z: 2
                color: (root.currentTab === 0
                        ? leftTabHover.hovered : rightTabHover.hovered)
                    ? Appearance.colors.colPrimaryContainerHover
                    : Appearance.colors.colPrimaryContainer

                Behavior on x {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve:
                            Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                Behavior on color {
                    enabled: Appearance.animationsEnabled
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }
            }

            Item {
                id: leftTabHit
                x: 0
                width: tabShell.halfWidth
                height: tabShell.height
                z: 5

                HoverHandler {
                    id: leftTabHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.currentTab = 0
                }
            }

            Item {
                id: rightTabHit
                x: tabShell.halfWidth
                width: tabShell.halfWidth
                height: tabShell.height
                z: 5

                HoverHandler {
                    id: rightTabHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.currentTab = 1
                }
            }

            Item {
                x: 0
                width: tabShell.halfWidth
                height: tabShell.height
                z: 4

                Row {
                    id: leftTabLabel
                    anchors.centerIn: parent
                    spacing: tabShell.labelSpacing

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "checklist"
                        iconSize: tabShell.tabIconSize
                        color: root.currentTab === 0
                            ? Appearance.colors.colOnPrimaryContainer
                            : root.colSubtext
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Unfinished")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: root.currentTab === 0
                            ? Appearance.colors.colOnPrimaryContainer
                            : root.colSubtext
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: tabShell.badgeSize
                    height: tabShell.badgeSize
                    radius: height / 2
                    color: root.currentTab === 0
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer2

                    StyledText {
                        id: leftCountText
                        anchors.centerIn: parent
                        text: root.unfinishedTasks.length
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: root.currentTab === 0
                            ? Appearance.colors.colOnPrimary
                            : root.colSubtext
                    }
                }
            }

            Item {
                x: tabShell.halfWidth
                width: tabShell.halfWidth
                height: tabShell.height
                z: 4

                Row {
                    id: rightTabLabel
                    anchors.centerIn: parent
                    spacing: tabShell.labelSpacing

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "check_circle"
                        iconSize: tabShell.tabIconSize
                        color: root.currentTab === 1
                            ? Appearance.colors.colOnPrimaryContainer
                            : root.colSubtext
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Done")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: root.currentTab === 1
                            ? Appearance.colors.colOnPrimaryContainer
                            : root.colSubtext
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: tabShell.badgeSize
                    height: tabShell.badgeSize
                    radius: height / 2
                    color: root.currentTab === 1
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer2

                    StyledText {
                        id: rightCountText
                        anchors.centerIn: parent
                        text: root.doneTasks.length
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: root.currentTab === 1
                            ? Appearance.colors.colOnPrimary
                            : root.colSubtext
                    }
                }
            }

            WheelHandler {
                acceptedDevices:
                    PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (event.angleDelta.y < 0)
                        root.currentTab = 1
                    else if (event.angleDelta.y > 0)
                        root.currentTab = 0
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.veryShallowLayout
                ? 8 : (root.shallowLayout ? 56 : 72)
            clip: true

            Flickable {
                id: taskFlick
                anchors.fill: parent
                visible: root.visibleTasks.length > 0
                contentWidth: width
                contentHeight: taskColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Column {
                    id: taskColumn
                    width: taskFlick.width
                    spacing: root.compact ? 4 : 6

                    Repeater {
                        model: root.visibleTasks

                        delegate: Rectangle {
                            id: taskRow
                            required property var modelData
                            width: taskColumn.width
                            implicitHeight: Math.max(root.compact ? 44 : 50,
                                rowContent.implicitHeight + 12)
                            radius: Appearance.rounding.small
                            color: rowHover.hovered
                                ? Appearance.colors.colLayer2Hover
                                : Appearance.colors.colLayer2

                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                }
                            }

                            RowLayout {
                                id: rowContent
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 7
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                                spacing: 8

                                Item {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        radius: 7
                                        color: taskRow.modelData.done === true
                                            ? Appearance.colors.colPrimary
                                            : "transparent"
                                        border.width: 2
                                        border.color: taskRow.modelData.done === true
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colOutline

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: taskRow.modelData.done === true
                                            text: "check"
                                            iconSize: 16
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }

                                    TapHandler {
                                        enabled: !Todo.busy
                                        onTapped: root.toggleTask(taskRow.modelData)
                                    }

                                    HoverHandler {
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }

                                Rectangle {
                                    visible: String(taskRow.modelData.startTime ?? "").length > 0
                                    implicitWidth: taskTimeLabel.implicitWidth + 12
                                    implicitHeight: 24
                                    radius: height / 2
                                    color: Appearance.colors.colLayer1

                                    StyledText {
                                        id: taskTimeLabel
                                        anchors.centerIn: parent
                                        text: {
                                            const start = String(taskRow.modelData.startTime ?? "")
                                            const end = String(taskRow.modelData.endTime ?? "")
                                            return end.length > 0 ? start + "–" + end : start
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.numbers
                                        font.weight: Font.DemiBold
                                        color: root.colAccent
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: taskRow.modelData.content ?? ""
                                    color: taskRow.modelData.done === true
                                        ? root.colSubtext : root.colText
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: taskRow.modelData.done === true
                                        ? Font.Normal : Font.Medium
                                    font.strikeout: taskRow.modelData.done === true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                RippleButton {
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    buttonRadius: height / 2
                                    enabled: !Todo.busy
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                    onClicked: root.deleteTask(taskRow.modelData)

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "delete"
                                        iconSize: 17
                                        color: root.colSubtext
                                    }
                                }
                            }

                            HoverHandler {
                                id: rowHover
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - (root.narrowLayout ? 12 : 24),
                    root.narrowLayout ? 190 : 220)
                spacing: root.shallowLayout ? 3 : 5
                visible: root.visibleTasks.length === 0

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !root.veryShallowLayout
                    width: root.shallowLayout ? 42 : (root.compact ? 46 : 54)
                    height: width
                    text: root.currentTab === 0 ? "task_alt" : "done_all"
                    shape: MaterialShape.Shape.Clover4Leaf
                    padding: root.shallowLayout ? 6 : 8
                    iconSize: root.shallowLayout ? 22 : (root.compact ? 24 : 28)
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Todo.errorMessage.length > 0
                        ? Todo.errorMessage
                        : root.currentTab === 0
                            ? Translation.tr("Nothing here!")
                            : Translation.tr("Finished tasks will go here")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: root.colText
                    wrapMode: Text.WordWrap
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.safeEdgeInset
            Layout.rightMargin: root.safeEdgeInset
            spacing: root.narrowLayout ? 5 : 7

            RippleButton {
                visible: Todo.backend !== "obsidian"
                Layout.preferredWidth: root.actionButtonSize
                Layout.minimumWidth: root.actionButtonSize
                Layout.maximumWidth: root.actionButtonSize
                Layout.preferredHeight: root.actionButtonSize
                Layout.minimumHeight: root.actionButtonSize
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.actionButtonSize
                implicitHeight: root.actionButtonSize
                buttonRadius: root.actionButtonSize / 2
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.openTodoSettings()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "link"
                    iconSize: 17
                    color: root.colAccent
                }

                StyledToolTip {
                    text: Translation.tr("Prepare Obsidian")
                }
            }

            Item {
                Layout.fillWidth: true
            }

            RippleButton {
                Layout.preferredWidth: root.actionButtonSize
                Layout.minimumWidth: root.actionButtonSize
                Layout.maximumWidth: root.actionButtonSize
                Layout.preferredHeight: root.actionButtonSize
                Layout.minimumHeight: root.actionButtonSize
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.actionButtonSize
                implicitHeight: root.actionButtonSize
                buttonRadius: root.actionButtonSize / 2
                enabled: Todo.ready
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: Todo.openSource("")

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit_note"
                    iconSize: 17
                    color: root.colAccent
                }

                StyledToolTip {
                    text: Translation.tr("Edit task source")
                }
            }

            RippleButton {
                Layout.preferredWidth: root.actionButtonSize
                Layout.minimumWidth: root.actionButtonSize
                Layout.maximumWidth: root.actionButtonSize
                Layout.preferredHeight: root.actionButtonSize
                Layout.minimumHeight: root.actionButtonSize
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: root.actionButtonSize
                implicitHeight: root.actionButtonSize
                buttonRadius: root.actionButtonSize / 2
                enabled: Todo.ready && !Todo.busy
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: root.showAddDialog = true

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "add"
                    iconSize: 18
                    color: Appearance.colors.colOnPrimary
                }

                StyledToolTip {
                    text: Translation.tr("Add task")
                }
            }
        }
    }

    property Item addDialogOverlay: Item {
        parent: root
        anchors.fill: parent
        z: 100
        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0

        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim

            TapHandler {
                onTapped: root.showAddDialog = false
            }
        }

        Rectangle {
            id: addDialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.compact ? 10 : 18
            implicitHeight: addDialogColumn.implicitHeight + 28
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHigh

            ColumnLayout {
                id: addDialogColumn
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Add task")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: root.colText
                }

                TextField {
                    id: todoInput
                    Layout.fillWidth: true
                    focus: root.showAddDialog
                    padding: 10
                    color: Appearance.colors.colOnSurface
                    placeholderText: Translation.tr("Task description")
                    placeholderTextColor: Appearance.colors.colOutline
                    onAccepted: addTask()

                    function addTask(): void {
                        const text = todoInput.text.trim()
                        if (text.length === 0 || Todo.busy)
                            return
                        const start = Todo.useMarkdownNote
                            ? todoStartTime.text.trim() : ""
                        const end = Todo.useMarkdownNote
                            ? todoEndTime.text.trim() : ""
                        if (Todo.addTaskWithTime(text, start, end)) {
                            todoInput.text = ""
                            todoStartTime.text = ""
                            todoEndTime.text = ""
                            root.currentTab = 0
                            root.showAddDialog = false
                        }
                    }

                    background: Rectangle {
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: todoInput.activeFocus ? 2 : 1
                        border.color: todoInput.activeFocus
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOutline
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: Todo.backend === "obsidian"
                        && Todo.useMarkdownNote

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            text: Translation.tr("Start time")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.colSubtext
                        }

                        TextField {
                            id: todoStartTime
                            Layout.fillWidth: true
                            placeholderText: "HH:mm"
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colOutline
                            validator: RegularExpressionValidator {
                                regularExpression: /^(?:|(?:[01]\d|2[0-3]):[0-5]\d)$/
                            }
                            background: Rectangle {
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer1
                                border.width: todoStartTime.activeFocus ? 2 : 1
                                border.color: todoStartTime.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOutline
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            text: Translation.tr("End time")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.colSubtext
                        }

                        TextField {
                            id: todoEndTime
                            Layout.fillWidth: true
                            enabled: todoStartTime.text.trim().length > 0
                            placeholderText: "HH:mm"
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colOutline
                            validator: RegularExpressionValidator {
                                regularExpression: /^(?:|(?:[01]\d|2[0-3]):[0-5]\d)$/
                            }
                            background: Rectangle {
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer1
                                border.width: todoEndTime.activeFocus ? 2 : 1
                                border.color: todoEndTime.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOutline
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Item {
                        Layout.fillWidth: true
                    }

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showAddDialog = false
                    }

                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: Todo.ready && !Todo.busy
                            && todoInput.text.trim().length > 0
                        onClicked: todoInput.addTask()
                    }
                }
            }
        }

        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => todoInput.forceActiveFocus())
            else {
                todoInput.text = ""
                todoStartTime.text = ""
                todoEndTime.text = ""
            }
        }
    }
}
