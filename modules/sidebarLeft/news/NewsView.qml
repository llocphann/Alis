pragma ComponentBehavior: Bound
import qs
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks
import "root:services"
import qs.services.deferred
import qs.services

Item {
    id: root

    readonly property bool abyssMode: Config.options?.panelFamily === "abyss"
    readonly property real edgeOpacity: AbyssStyle.contentOpacity
    readonly property real edgeHighlight: AbyssStyle.highlightStrength
    readonly property real edgeLift: AbyssStyle.blurRadius > 0 ? 0.024 : 0
    readonly property real edgeRadius: Math.max(12, Math.min(26, AbyssStyle.perimeterRadius))
    readonly property color cloudColor: Qt.rgba(
        Math.min(1, AbyssStyle.surfaceDeep.r + edgeLift),
        Math.min(1, AbyssStyle.surfaceDeep.g + edgeLift),
        Math.min(1, AbyssStyle.surfaceDeep.b + edgeLift),
        edgeOpacity
    )
    readonly property color cloudBorderColor: edgeHighlight > 0.01
        ? Qt.alpha(AbyssStyle.specular, Math.max(0.08, 0.55 * edgeHighlight))
        : Qt.alpha(AbyssStyle.textColor, 0.06)

    function edgeSurfaceColor(depthWeight): color {
        const k = Math.max(0, Math.min(1, depthWeight * 0.38 * root.edgeHighlight))
        return Qt.rgba(
            root.cloudColor.r + (AbyssStyle.surfaceRaised.r - root.cloudColor.r) * k,
            root.cloudColor.g + (AbyssStyle.surfaceRaised.g - root.cloudColor.g) * k,
            root.cloudColor.b + (AbyssStyle.surfaceRaised.b - root.cloudColor.b) * k,
            root.edgeOpacity
        )
    }

    // Boards: "local" (geo, via Weather location) / "top" / one topic per entry.
    readonly property var boards: {
        const result = [
            { key: "local", topic: "", label: Translation.tr("Local"), icon: "place" },
            { key: "top", topic: "", label: Translation.tr("Top"), icon: "trending_up" }
        ]
        const topicLabels = {
            "WORLD": Translation.tr("World"),
            "NATION": Translation.tr("Nation"),
            "BUSINESS": Translation.tr("Business"),
            "TECHNOLOGY": Translation.tr("Technology"),
            "ENTERTAINMENT": Translation.tr("Entertainment"),
            "SCIENCE": Translation.tr("Science"),
            "SPORTS": Translation.tr("Sports"),
            "HEALTH": Translation.tr("Health")
        }
        NewsService.topics.forEach(t => result.push({ key: "topic", topic: t, label: topicLabels[t] ?? t, icon: "" }))
        return result
    }

    readonly property string configMode: Config.options?.sidebar?.news?.mode ?? "local"
    readonly property string configTopic: Config.options?.sidebar?.news?.topic ?? "WORLD"
    readonly property int currentBoardIndex: {
        for (let i = 0; i < boards.length; i++) {
            if (boards[i].key === configMode && (configMode !== "topic" || boards[i].topic === configTopic))
                return i
        }
        return 0
    }

    function fetchCurrent() {
        NewsService.fetch(root.configMode, root.configTopic)
    }

    function refreshCurrent() {
        NewsService.refresh(root.configMode, root.configTopic)
    }

    Component.onCompleted: fetchCurrent()
    // When Weather resolves the location after startup, the "local" board
    // upgrades from the top-stories fallback to the real geo feed.
    Connections {
        target: NewsService
        function onLocalCityChanged() {
            if (root.configMode === "local")
                root.fetchCurrent()
        }
    }

    Rectangle {
        id: newsCloudBackground
        visible: root.abyssMode
        anchors.fill: parent
        anchors.margins: 4
        radius: 14
        color: root.cloudColor
        border.width: 1
        border.color: root.cloudBorderColor
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: root.edgeSurfaceColor(1.0) }
            GradientStop { position: 1.0; color: root.edgeSurfaceColor(0.25) }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.edgeRadius * 0.7
            anchors.rightMargin: root.edgeRadius * 0.7
            height: 1.5
            radius: 1
            color: Qt.alpha(AbyssStyle.accent, 0.45)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.abyssMode ? 12 : 8
        spacing: 8

        // Board selector
        StyledFlickable {
            Layout.fillWidth: true
            implicitHeight: boardRow.implicitHeight
            contentWidth: boardRow.implicitWidth
            clip: true

            RowLayout {
                id: boardRow
                spacing: 4

                Repeater {
                    model: root.boards
                    delegate: GroupButton {
                        required property var modelData
                        required property int index

                        buttonText: modelData.label
                        toggled: root.currentBoardIndex === index
                        bounce: true
                        colBackground: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.05)
                            : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                            : Appearance.alisEverywhere ? Appearance.alis.colLayer2
                            : Appearance.auroraEverywhere ? "transparent"
                            : Appearance.colors.colLayer1
                        colBackgroundHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.12)
                            : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                            : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                            : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                            : Appearance.colors.colLayer1Hover
                        colBackgroundToggled: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.22)
                            : Appearance.angelEverywhere ? Appearance.angel.colGlassElevated
                            : Appearance.alisEverywhere ? Appearance.alis.colSecondaryContainer
                            : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                            : Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: root.abyssMode ? Qt.alpha(AbyssStyle.accent, 0.30)
                            : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                            : Appearance.alisEverywhere ? Appearance.alis.colPrimaryContainerHover
                            : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover
                            : Appearance.colors.colSecondaryContainerHover

                        onClicked: {
                            Config.setNestedValues({
                                "sidebar.news.mode": modelData.key,
                                "sidebar.news.topic": modelData.key === "topic" ? modelData.topic : root.configTopic
                            })
                            NewsService.fetch(modelData.key, modelData.topic)
                        }
                    }
                }
            }
        }

        // Content area
        Rectangle {
            id: contentContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.abyssMode ? 12
                : Appearance.angelEverywhere ? Appearance.angel.roundingNormal
                : Appearance.alisEverywhere ? Appearance.alis.roundingNormal : Appearance.rounding.normal
            color: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.04)
                : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                : Appearance.alisEverywhere ? Appearance.alis.colLayer1
                : Appearance.auroraEverywhere ? "transparent"
                : Appearance.colors.colLayer1
            border.width: root.abyssMode ? 1
                : Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth
                : Appearance.auroraEverywhere ? 0 : 1
            border.color: root.abyssMode ? Qt.alpha(AbyssStyle.textColor, 0.08)
                : Appearance.angelEverywhere ? Appearance.angel.colCardBorder
                : Appearance.alisEverywhere ? Appearance.alis.colBorderSubtle
                : Appearance.colors.colLayer0Border
            clip: true

            // Loading text only; refresh-without-text keeps the shared gear.
            LoadingText {
                anchors.centerIn: parent
                visible: NewsService.loading && NewsService.articles.length === 0
            }

            // Error
            MaterialPlaceholderMessage {
                anchors.centerIn: parent
                maximumWidth: 340
                shown: NewsService.lastError.length > 0 && NewsService.articles.length === 0
                icon: "error"
                actionIcon: "refresh"
                text: Translation.tr("Error")
                explanation: NewsService.lastError
                helpfulAction: Kirigami.Action {
                    icon.name: "refresh"
                    text: Translation.tr("Retry")
                    onTriggered: root.refreshCurrent()
                }
            }

            // Empty
            MaterialPlaceholderMessage {
                anchors.centerIn: parent
                maximumWidth: 340
                shown: !NewsService.loading && NewsService.lastError.length === 0 && NewsService.articles.length === 0
                icon: "newspaper"
                text: Translation.tr("No news")
                explanation: Translation.tr("Try a different board")
            }

            ScrollEdgeFade {
                z: 1
                target: listView
                vertical: true
                fadeSize: 25
                color: ColorUtils.transparentize(Appearance.colors.colShadow, 0.5)
            }

            StyledListView {
                id: listView
                anchors.fill: parent
                anchors.margins: 6
                visible: NewsService.articles.length > 0
                spacing: 4
                clip: true

                model: NewsService.articles

                delegate: RippleButton {
                    id: articleButton
                    required property var modelData
                    width: listView.width
                    implicitHeight: articleColumn.implicitHeight + 16
                    buttonRadius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                        : Appearance.colors.colLayer1Hover

                    onClicked: NewsService.openArticle(modelData)

                    contentItem: ColumnLayout {
                        id: articleColumn
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 3

                        StyledText {
                            Layout.fillWidth: true
                            text: articleButton.modelData.title
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: [articleButton.modelData.source, NewsService.formatTime(articleButton.modelData.timestamp)]
                                .filter(s => s && s.length > 0).join(" • ")
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                onDragEnded: {
                    if (verticalOvershoot > 60)
                        root.refreshCurrent()
                }
            }

            // Refresh indicator
            MaterialLoadingIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                visible: NewsService.loading && NewsService.articles.length > 0
                loading: true
                implicitSize: 32
            }
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                text: root.configMode === "local" && NewsService.localCity.length > 0
                    ? NewsService.localCity
                    : root.boards[root.currentBoardIndex].label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                enabled: !NewsService.loading

                colBackgroundHover: Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                    : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                    : Appearance.colors.colLayer2Hover

                onClicked: root.refreshCurrent()

                contentItem: MaterialSymbol {
                    id: refreshIcon
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1

                    RotationAnimation on rotation {
                        running: NewsService.loading && GlobalStates.sidebarLeftOpen
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) refreshIcon.rotation = 0
                    }
                }

                StyledToolTip { text: Translation.tr("Refresh") }
            }
        }
    }
}
