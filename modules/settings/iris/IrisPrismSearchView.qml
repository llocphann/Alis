pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings

Rectangle {
    id: root
    objectName: "irisPrismSearchView"

    property string query: ""
    property var results: []
    property int selectedIndex: 0

    signal placeActivated(int pageIndex, string section)
    signal resultActivated(var entry)

    color: IrisTheme.panelBg

    // Compute matching Places (Areas + Sub-tabs) at top of search view
    readonly property var matchingPlaces: {
        const q = String(root.query ?? "").trim().toLowerCase()
        if (!q)
            return []
        const out = []
        const seen = new Set()
        const navIndices = SettingsPageRegistry.navigationPageIndexes(false) ?? []
        const indices = navIndices.slice()
        if (SettingsPageRegistry.isPageApplicable(40) && indices.indexOf(40) < 0)
            indices.push(40)

        for (let i = 0; i < indices.length && out.length < 8; i++) {
            const idx = indices[i]
            const p = SettingsPageRegistry.pages[idx]
            if (!p || seen.has("p:" + idx))
                continue
            const nameLower = String(p.name ?? "").toLowerCase()
            const descLower = String(p.desc ?? "").toLowerCase()
            const keyLower = String(p.key ?? "").toLowerCase()
            if (nameLower.indexOf(q) >= 0 || descLower.indexOf(q) >= 0 || keyLower.indexOf(q) >= 0) {
                seen.add("p:" + idx)
                out.push({
                    pageIndex: idx,
                    section: "",
                    title: String(p.name ?? ""),
                    subtitle: String(p.desc ?? ""),
                    icon: String(p.icon ?? "settings")
                })
            }
            const subTabs = p.subTabs ?? []
            for (let s = 0; s < subTabs.length && out.length < 8; s++) {
                const st = subTabs[s]
                const stName = String(st?.name ?? "")
                if (stName.toLowerCase().indexOf(q) >= 0) {
                    const sk = "s:" + idx + ":" + String(st?.value ?? "")
                    if (!seen.has(sk)) {
                        seen.add(sk)
                        out.push({
                            pageIndex: idx,
                            section: String(st?.value ?? ""),
                            title: stName,
                            subtitle: String(p.name ?? ""),
                            icon: String(st?.icon ?? p.icon ?? "tab")
                        })
                    }
                }
            }
        }
        return out
    }

    Flickable {
        id: searchFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: searchBody.implicitHeight + 36
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

        ColumnLayout {
            id: searchBody
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(Math.max(320, searchFlick.width - 40), IrisTheme.pageMaxWidth)
            spacing: 16

            // Search Summary Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "search"
                    iconSize: 18
                    color: IrisTheme.accent
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Translation.tr("Search results for \"%1\"").arg(root.query.trim())
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: IrisTheme.text
                    maximumLineCount: 1
                }

                StyledText {
                    text: Translation.tr("%1 match(es)").arg(String(root.matchingPlaces.length + (root.results?.length ?? 0)))
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.features: ({ "tnum": 1 })
                    color: IrisTheme.textMuted
                }
            }

            // ── Matching Places (Areas & Sub-Tabs) ──
            ColumnLayout {
                visible: root.matchingPlaces.length > 0
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("PLACES")
                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.9
                    color: IrisTheme.textDim
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: searchBody.width >= 560 ? 2 : 1
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: root.matchingPlaces

                        delegate: Rectangle {
                            id: placeCard
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: Math.round(56 * IrisTheme.scale)
                            radius: IrisTheme.radiusCard
                            color: placeMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.plate
                            border.width: 1
                            border.color: placeMouse.containsMouse ? IrisTheme.accentBorder : IrisTheme.hairline

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: Math.round(34 * IrisTheme.scale)
                                    height: Math.round(34 * IrisTheme.scale)
                                    radius: Math.round(10 * IrisTheme.scale)
                                    color: IrisTheme.accentTint
                                    border.width: 1
                                    border.color: IrisTheme.accentBorder

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: String(placeCard.modelData.icon || "settings")
                                        iconSize: 18
                                        color: IrisTheme.accent
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
                                        text: String(placeCard.modelData.title || "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: IrisTheme.text
                                        maximumLineCount: 1
                                    }

                                    StyledText {
                                        visible: String(placeCard.modelData.subtitle || "").length > 0
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: String(placeCard.modelData.subtitle || "")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: IrisTheme.textMuted
                                        maximumLineCount: 1
                                    }
                                }

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "arrow_forward"
                                    iconSize: 16
                                    color: IrisTheme.textDim
                                }
                            }

                            MouseArea {
                                id: placeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.placeActivated(
                                    Number(placeCard.modelData.pageIndex),
                                    String(placeCard.modelData.section || "")
                                )
                            }
                        }
                    }
                }
            }

            // ── Matching Individual Settings Plate ──
            ColumnLayout {
                visible: (root.results?.length ?? 0) > 0
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("SETTINGS")
                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.9
                    color: IrisTheme.textDim
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: settingsListCol.implicitHeight + 8
                    radius: IrisTheme.radiusCard
                    color: IrisTheme.plate
                    border.width: 1
                    border.color: IrisTheme.hairline

                    ColumnLayout {
                        id: settingsListCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        spacing: 0

                        Repeater {
                            model: root.results ?? []

                            delegate: ColumnLayout {
                                id: hitRowWrap
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === root.selectedIndex
                                readonly property string crumb: {
                                    const pName = String(modelData?.pageName ?? "").trim()
                                    const sec = String(modelData?.section ?? "").trim()
                                    if (pName && sec && sec.toLowerCase() !== pName.toLowerCase())
                                        return pName + " › " + sec
                                    return pName || sec
                                }

                                Layout.fillWidth: true
                                spacing: 0

                                Rectangle {
                                    visible: hitRowWrap.index > 0
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 12
                                    Layout.rightMargin: 12
                                    height: 1
                                    color: IrisTheme.hairline
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: hitInnerRow.implicitHeight + 16
                                    radius: IrisTheme.radiusSmall
                                    color: hitRowWrap.selected
                                        ? IrisTheme.accentTint
                                        : (hitMouse.containsMouse ? IrisTheme.plateHover : "transparent")

                                    RowLayout {
                                        id: hitInnerRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: SettingsPageRegistry.iconForPage(Number(hitRowWrap.modelData?.pageIndex ?? -1))
                                            iconSize: 18
                                            color: hitRowWrap.selected ? IrisTheme.accent : IrisTheme.textMuted
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 2

                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: String(hitRowWrap.modelData?.label ?? "")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.DemiBold
                                                color: IrisTheme.text
                                                maximumLineCount: 1
                                            }

                                            StyledText {
                                                visible: String(hitRowWrap.modelData?.description ?? "").length > 0
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: String(hitRowWrap.modelData?.description ?? "")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: IrisTheme.textMuted
                                                maximumLineCount: 1
                                            }
                                        }

                                        Rectangle {
                                            visible: hitRowWrap.crumb.length > 0 && searchBody.width >= 440
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitWidth: Math.min(220, crumbText.implicitWidth + 14)
                                            implicitHeight: Math.round(22 * IrisTheme.scale)
                                            radius: Math.round(implicitHeight / 2)
                                            color: IrisTheme.plateRaised
                                            border.width: 1
                                            border.color: IrisTheme.hairline

                                            StyledText {
                                                id: crumbText
                                                anchors.centerIn: parent
                                                width: Math.min(206, implicitWidth)
                                                text: hitRowWrap.crumb
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: IrisTheme.textSecondary
                                                maximumLineCount: 1
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: hitMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.selectedIndex = hitRowWrap.index
                                        onClicked: root.resultActivated(hitRowWrap.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Empty State ──
            Rectangle {
                visible: root.matchingPlaces.length === 0 && (root.results?.length ?? 0) === 0
                Layout.fillWidth: true
                implicitHeight: Math.round(140 * IrisTheme.scale)
                radius: IrisTheme.radiusCard
                color: IrisTheme.plate
                border.width: 1
                border.color: IrisTheme.hairline

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "search_off"
                        iconSize: 28
                        color: IrisTheme.textDim
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("No matching settings")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: IrisTheme.textSecondary
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Try another keyword or browse areas in the left sidebar.")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: IrisTheme.textMuted
                    }
                }
            }
        }
    }

    IrisScrollEdge {
        flickable: searchFlick
        edge: "top"
        fadeColor: IrisTheme.panelBg
    }

    IrisScrollEdge {
        flickable: searchFlick
        edge: "bottom"
        fadeColor: IrisTheme.panelBg
    }
}
