pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

Rectangle {
    id: root
    objectName: "irisPrismRail"

    property int activePageIndex: 2
    property bool showingHome: false

    signal areaSelected(int pageIndex)

    color: IrisTheme.railBg

    // Left vertical divider hairline separating middle pane from right rail
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: 1
        color: IrisTheme.hairline
    }

    property int _avatarIdx: 0
    readonly property string avatarSource: {
        const candidate = String(Directories.avatarSourceAt(root._avatarIdx) ?? "")
        if (candidate.length > 0)
            return candidate
        return String(Directories.userAvatarSourcePrimary ?? "")
    }

    readonly property var quickJumpAreas: {
        void(IrisState.recentPageIndices)
        void(IrisState.pinnedAreaKeys)
        void(SettingsPageRegistry.pages)
        const out = []
        const seen = new Set()

        const recents = IrisState.recentPageIndices ?? []
        for (let i = 0; i < recents.length && out.length < 4; i++) {
            const idx = Number(recents[i])
            if (idx >= 0 && !seen.has(idx) && SettingsPageRegistry.isPageApplicable(idx) && SettingsPageRegistry.pages[idx]) {
                seen.add(idx)
                out.push({
                    pageIndex: idx,
                    name: String(SettingsPageRegistry.pages[idx].name ?? ""),
                    icon: String(SettingsPageRegistry.pages[idx].icon ?? "settings"),
                    tag: Translation.tr("Recent")
                })
            }
        }

        const pins = IrisState.pinnedAreaKeys ?? []
        for (let j = 0; j < pins.length && out.length < 4; j++) {
            const pIdx = SettingsPageRegistry.pageIndexForKey(String(pins[j]))
            if (pIdx >= 0 && !seen.has(pIdx) && SettingsPageRegistry.isPageApplicable(pIdx) && SettingsPageRegistry.pages[pIdx]) {
                seen.add(pIdx)
                out.push({
                    pageIndex: pIdx,
                    name: String(SettingsPageRegistry.pages[pIdx].name ?? ""),
                    icon: String(SettingsPageRegistry.pages[pIdx].icon ?? "bookmark"),
                    tag: Translation.tr("Pinned")
                })
            }
        }
        return out
    }

    Flickable {
        id: railFlick
        anchors.fill: parent
        anchors.margins: 10
        contentWidth: width
        contentHeight: railCol.implicitHeight + 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

        ColumnLayout {
            id: railCol
            width: railFlick.width
            spacing: 10

            // ── 1) Profile & Do Not Disturb Card ──
            Rectangle {
                objectName: "irisRailProfileCard"
                Layout.fillWidth: true
                implicitHeight: profileCol.implicitHeight + 24
                radius: IrisTheme.radiusCard
                color: IrisTheme.plate
                border.width: 1
                border.color: IrisTheme.hairline

                ColumnLayout {
                    id: profileCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // User Avatar Circle with graceful icon fallback
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: Math.round(42 * IrisTheme.scale)
                            height: Math.round(42 * IrisTheme.scale)
                            radius: Math.round(height / 2)
                            color: IrisTheme.accentTint
                            border.width: 1
                            border.color: IrisTheme.accentBorder
                            clip: true

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: avatarImg.status !== Image.Ready
                                text: "person"
                                iconSize: 22
                                color: IrisTheme.accent
                            }

                            Image {
                                id: avatarImg
                                anchors.fill: parent
                                source: root.avatarSource
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(96, 96)
                                visible: status === Image.Ready
                                onStatusChanged: {
                                    if (status === Image.Error && root._avatarIdx + 1 < (Directories.userAvatarPaths?.length ?? 0))
                                        root._avatarIdx++
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: String(SystemInfo.displayName || SystemInfo.username || Translation.tr("User"))
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: IrisTheme.text
                                maximumLineCount: 1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: {
                                    const uname = String(SystemInfo.username || "").trim()
                                    const up = String(DateTime.uptime || "").trim()
                                    if (uname && up)
                                        return "@" + uname + " · " + up
                                    return uname ? ("@" + uname) : (up || (SystemInfo.distroName || "Linux"))
                                }
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: IrisTheme.textMuted
                                maximumLineCount: 1
                            }
                        }

                        // 1-Click Do Not Disturb Bell Toggle
                        Rectangle {
                            id: dndBellBtn
                            objectName: "irisRailDndButton"
                            Layout.alignment: Qt.AlignVCenter
                            width: Math.round(34 * IrisTheme.scale)
                            height: Math.round(34 * IrisTheme.scale)
                            radius: Math.round(height / 2)
                            readonly property bool dndActive: Boolean(Notifications.silent)
                            color: dndActive
                                ? IrisTheme.accent
                                : (dndBellMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.plateRaised)
                            border.width: dndActive ? 0 : 1
                            border.color: IrisTheme.hairline

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: dndBellBtn.dndActive ? "notifications_off" : "notifications"
                                fill: dndBellBtn.dndActive ? 1 : 0
                                iconSize: 17
                                color: dndBellBtn.dndActive ? IrisTheme.onAccent : IrisTheme.textSecondary
                            }

                            MouseArea {
                                id: dndBellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notifications.silent = !Notifications.silent
                            }

                            StyledToolTip {
                                extraVisibleCondition: dndBellMouse.containsMouse
                                text: dndBellBtn.dndActive
                                    ? Translation.tr("Disable Do Not Disturb")
                                    : Translation.tr("Enable Do Not Disturb")
                            }
                        }
                    }

                    // Active Shell Snapshot Pills
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.round(24 * IrisTheme.scale)
                            radius: Math.round(implicitHeight / 2)
                            color: IrisTheme.plateRaised
                            border.width: 1
                            border.color: IrisTheme.hairline

                            Row {
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (Appearance.m3colors?.darkmode ?? true) ? "dark_mode" : "light_mode"
                                    iconSize: 13
                                    color: IrisTheme.accent
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (Appearance.m3colors?.darkmode ?? true) ? Translation.tr("Dark") : Translation.tr("Light")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: IrisTheme.textSecondary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: IrisState.triggerTile("darkMode")
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.round(24 * IrisTheme.scale)
                            radius: Math.round(implicitHeight / 2)
                            color: (Config.options?.abyss?.companion?.enabled ?? false) ? IrisTheme.accentTint : IrisTheme.plateRaised
                            border.width: 1
                            border.color: (Config.options?.abyss?.companion?.enabled ?? false) ? IrisTheme.accentBorder : IrisTheme.hairline

                            Row {
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "water_drop"
                                    iconSize: 13
                                    color: (Config.options?.abyss?.companion?.enabled ?? false) ? IrisTheme.accent : IrisTheme.textMuted
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Companion")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: (Config.options?.abyss?.companion?.enabled ?? false) ? IrisTheme.accent : IrisTheme.textSecondary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: IrisState.triggerTile("companion")
                            }
                        }
                    }
                }
            }

            // ── 2) Pinned & Recent Areas Card ──
            Rectangle {
                visible: root.quickJumpAreas.length > 0
                Layout.fillWidth: true
                implicitHeight: jumpCol.implicitHeight + 22
                radius: IrisTheme.radiusCard
                color: IrisTheme.plate
                border.width: 1
                border.color: IrisTheme.hairline

                ColumnLayout {
                    id: jumpCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 11
                    spacing: 4

                    StyledText {
                        Layout.leftMargin: 2
                        Layout.bottomMargin: 2
                        text: Translation.tr("RECENT & PINNED")
                        font.pixelSize: Appearance.font.pixelSize.smallest - 1
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                        color: IrisTheme.textDim
                    }

                    Repeater {
                        model: root.quickJumpAreas

                        delegate: Rectangle {
                            id: railJumpRow
                            required property var modelData
                            readonly property bool isCurrent: !root.showingHome
                                && root.activePageIndex === Number(modelData.pageIndex)
                            Layout.fillWidth: true
                            implicitHeight: Math.round(30 * IrisTheme.scale)
                            radius: IrisTheme.radiusSmall
                            color: isCurrent
                                ? IrisTheme.accentTint
                                : (railJumpMouse.containsMouse ? IrisTheme.plateHover : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: String(railJumpRow.modelData.icon || "settings")
                                    iconSize: 15
                                    color: railJumpRow.isCurrent ? IrisTheme.accent : IrisTheme.textMuted
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.alignment: Qt.AlignVCenter
                                    text: String(railJumpRow.modelData.name || "")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: railJumpRow.isCurrent ? Font.DemiBold : Font.Normal
                                    color: IrisTheme.text
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: String(railJumpRow.modelData.tag || "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                    color: IrisTheme.textDim
                                }
                            }

                            MouseArea {
                                id: railJumpMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.areaSelected(Number(railJumpRow.modelData.pageIndex))
                            }
                        }
                    }
                }
            }

            // ── 3) Now Playing Card ──
            IrisPrismNowPlaying {
                Layout.fillWidth: true
            }
        }
    }
}
