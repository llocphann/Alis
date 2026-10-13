import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * GitHub contributions card: total count + heatmap for the last 6 months.
 * Fetches once per panel session (cached 1h) and only when a username is
 * configured — zero cost otherwise.
 */
DashCard {
    id: root

    readonly property string username: Config.options?.dashboard?.github?.username ?? ""
    property var weeks: [] // [[level 0–4 per day] per week]
    property int total: -1
    property double _lastFetch: 0
    property bool fetching: false
    readonly property bool hasData: total >= 0 && weeks.length > 0

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: if (visible) refresh()
    onUsernameChanged: { total = -1; weeks = []; _lastFetch = 0; if (visible) refresh() }

    function refresh() {
        if (root.username.length === 0 || root.fetching) return
        if (Date.now() - root._lastFetch < 3600 * 1000) return
        root.fetching = true
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (!root) return  // dashboard closed mid-fetch
            root.fetching = false
            if (xhr.status !== 200) return
            try {
                const data = JSON.parse(xhr.responseText)
                const days = data?.contributions ?? []
                // The Dashboard intentionally presents only the most recent
                // 26 weeks. Keep the headline total on the exact same window
                // so the number and heatmap always describe one period.
                const recentDays = days.slice(Math.max(0, days.length - 26 * 7))
                let total = 0
                const wk = []
                let week = []
                for (let i = 0; i < recentDays.length; i++) {
                    const day = recentDays[i]
                    total += day.count ?? 0
                    week.push(day.level ?? 0)
                    if (week.length === 7) {
                        wk.push(week)
                        week = []
                    }
                }
                if (week.length > 0)
                    wk.push(week)
                root.total = total
                root.weeks = wk
                root._lastFetch = Date.now()
                heatmap.requestPaint()
            } catch (e) {
                console.log("[DashGithub] failed to parse contributions:", e)
            }
        }
        xhr.open("GET", `https://github-contributions-api.jogruber.de/v4/${encodeURIComponent(root.username)}?y=last`)
        xhr.send()
    }

    // No username configured
    ColumnLayout {
        visible: root.username.length === 0
        Layout.fillWidth: true
        spacing: 6

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "code"
            shape: MaterialShape.Shape.PixelCircle
            padding: 10
            iconSize: 32
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Set your GitHub username in Settings to see your contributions")
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colSubtext
            wrapMode: Text.WordWrap
        }
    }

    ColumnLayout {
        id: contributionContent
        visible: root.username.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        // The contribution map is the primary visual. Keep chrome and summary
        // compact so resized Dashboard slots give most of their height to it.
        spacing: root.compact ? 2 : 4

        readonly property bool roomy: root.height >= 150

        // A compact identity row gives the card some visual character when
        // there is enough vertical room, but yields entirely to the heatmap in
        // smaller/resized Dashboard slots.
        RowLayout {
            visible: contributionContent.roomy
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                spacing: 6

                Rectangle {
                    implicitWidth: 24
                    implicitHeight: 24
                    radius: Appearance.rounding.full
                    color: ColorUtils.applyAlpha(root.colAccent, 0.10)
                    border.width: 1
                    border.color: ColorUtils.applyAlpha(root.colAccent, 0.16)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "deployed_code"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.colAccent
                    }
                }

                StyledText {
                    text: "GitHub"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: root.colText
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: periodLabel.implicitWidth + 16
                implicitHeight: 22
                radius: Appearance.rounding.full
                color: ColorUtils.applyAlpha(Appearance.colors.colLayer2, 0.72)
                border.width: 1
                border.color: ColorUtils.applyAlpha(
                    Appearance.colors.colOutlineVariant, 0.32)

                StyledText {
                    id: periodLabel
                    anchors.centerIn: parent
                    text: "6M"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.colSubtext
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.hasData
                    ? root.total.toLocaleString(Qt.locale(), 'f', 0)
                    : (root.fetching ? "…" : "—")
                font.pixelSize: Appearance.font.pixelSize.title
                    * (contributionContent.roomy ? 1.20 : 1.05)
                font.family: Appearance.font.family.numbers
                font.weight: Font.DemiBold
                color: root.colAccent
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("contributions · last 6 months")
                    + "  ·  @" + root.username
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: root.colSubtext
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: heatmapSurface
            visible: root.hasData
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 48
            Layout.preferredHeight: contributionContent.roomy ? 112 : 72
            Layout.topMargin: contributionContent.roomy ? 2 : 1

            radius: Math.max(Appearance.rounding.small, 8)
            color: ColorUtils.applyAlpha(Appearance.colors.colLayer2, 0.28)
            border.width: 1
            border.color: ColorUtils.applyAlpha(
                Appearance.colors.colOutlineVariant, 0.18)

            Canvas {
                id: heatmap
                anchors.fill: parent
                anchors.margins: contributionContent.roomy ? 6 : 4

                readonly property color cellColor: root.colAccent
                readonly property color emptyColor: root.alisEverywhere
                    ? Appearance.alis.colLayer2
                    : Appearance.angelEverywhere
                        ? Appearance.angel.colGlassCardHover
                        : Appearance.colors.colLayer2

                onCellColorChanged: requestPaint()
                onEmptyColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    const wk = root.weeks
                    if (!wk.length || width <= 0 || height <= 0)
                        return

                    // Six months keeps the graph legible enough to be the
                    // card's primary visual instead of compressing 53 columns.
                    const cols = Math.min(wk.length, 26)
                    const start = Math.max(0, wk.length - cols)
                    const pitch = Math.max(2.5, Math.min(
                        contributionContent.roomy ? 14 : 11,
                        width / Math.max(1, cols),
                        height / 7))
                    const gap = Math.max(0.75, Math.min(1.5, pitch * 0.18))
                    const cell = Math.max(1.5, pitch - gap)
                    const gridWidth = cols * pitch - gap
                    const gridHeight = 7 * pitch - gap
                    const xOff = Math.max(0, (width - gridWidth) / 2)
                    const yOff = Math.max(0, (height - gridHeight) / 2)
                    const radius = Math.max(1, Math.min(2.5, cell * 0.28))

                    for (let col = 0; col < cols; ++col) {
                        const week = wk[start + col] ?? []
                        for (let row = 0; row < 7; ++row) {
                            const level = week[row] ?? 0
                            ctx.fillStyle = level === 0
                                ? emptyColor
                                : Qt.alpha(cellColor,
                                    0.22 + 0.78 * Math.min(level, 4) / 4)
                            ctx.beginPath()
                            ctx.roundedRect(
                                xOff + col * pitch,
                                yOff + row * pitch,
                                cell,
                                cell,
                                radius,
                                radius)
                            ctx.fill()
                        }
                    }
                }
            }
        }
    }

}
