import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    // Detail cards share the field's palette; neutral Material fills remain
    // available for the other supported panel families.
    readonly property color cardColor: abyss
        ? ColorUtils.mix(AbyssStyle.contentLayer, AbyssStyle.accent, .88)
        : Appearance.colors.colSurfaceContainerHigh
    readonly property color ink: abyss
        ? ColorUtils.ensureReadable(AbyssStyle.textColor, cardColor, 4.5)
        : Appearance.colors.colOnSurface
    readonly property color mutedInk: abyss
        ? ColorUtils.readableSubtext(ink, cardColor, .7)
        : Appearance.colors.colOnSurfaceVariant
    readonly property color accent: abyss ? AbyssStyle.accent : Appearance.colors.colPrimary
    readonly property color outline: abyss ? Qt.alpha(ink, .2) : Appearance.colors.colOutlineVariant

    property bool compact: false
    property bool verticalLayout: false
    readonly property real compactBreakpoint: 900
    readonly property real panelWidth: root.compact ? 344 : 372
    readonly property real orbitHeight: root.compact ? 250 : 276
    readonly property real detailContentHeight: Math.max(
        root.compact ? 228 : 248,
        detailColumn.implicitHeight + (root.compact ? 20 : 24))
    readonly property real panelHeight: root.verticalLayout
        ? (root.orbitHeight + 13 + root.detailContentHeight)
        : Math.max(root.orbitHeight, root.detailContentHeight)
    readonly property real orbitalInset: root.compact ? 6 : 8
    readonly property real orbitalRightInset: root.orbitalInset
    property date now: new Date()
    readonly property real sunProgress: {
        const sunrise = root.timeToMinutes(Weather.data?.sunrise)
        const sunset = root.timeToMinutes(Weather.data?.sunset)
        const current = root.now.getHours() * 60 + root.now.getMinutes()
        if (sunrise < 0 || sunset <= sunrise)
            return 0.5
        return Math.max(0, Math.min(1, (current - sunrise) / (sunset - sunrise)))
    }

    implicitWidth: root.verticalLayout ? root.panelWidth : (root.panelWidth * 2 + 13)
    implicitHeight: root.panelHeight

    function timeToMinutes(value): int {
        const match = String(value ?? "").trim()
            .match(/^(\d{1,2}):(\d{2})(?:\s*([AP]M))?/i)
        if (!match)
            return -1

        let hour = parseInt(match[1], 10)
        const minute = parseInt(match[2], 10)
        const suffix = String(match[3] ?? "").toUpperCase()
        if (suffix === "AM")
            hour = hour === 12 ? 0 : hour
        else if (suffix === "PM")
            hour = hour === 12 ? 12 : hour + 12
        if (isNaN(hour) || isNaN(minute))
            return -1
        return hour * 60 + minute
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.visible && root.width > 0 && root.height > 0
        onTriggered: root.now = new Date()
    }

    Item {
        id: weatherViewport
        anchors.fill: parent
        clip: true
        readonly property real viewportW: width > 0 ? width : root.implicitWidth
        readonly property real viewportH: height > 0 ? height : root.implicitHeight

    Rectangle {
        id: timeWeatherPanel
        x: 0
        y: 0
        width: root.verticalLayout ? weatherViewport.viewportW : root.panelWidth
        height: root.verticalLayout ? root.orbitHeight : weatherViewport.viewportH
        radius: Appearance.rounding.large
        color: "transparent"


        Loader {
            id: orbitalTimeline
            anchors {
                fill: parent
                leftMargin: root.orbitalInset
                rightMargin: root.orbitalRightInset
                topMargin: root.orbitalInset
                bottomMargin: root.orbitalInset
            }
            sourceComponent:Config.options?.panelFamily === "abyss" ? abyssOrbit : materialOrbit
        }
        Component { id:abyssOrbit;AbyssOrbitalWeather { now:root.now } }
        Component {
            id:materialOrbit
            OrbitalWeather {
                now: root.now
                liquidMode: true
                liquidAnimationActive: root.visible
            }
        }
    }

    Rectangle {
        id: sectionDivider
        x: root.verticalLayout ? 24 : (root.panelWidth + 6)
        y: root.verticalLayout
            ? (root.orbitHeight + 6)
            : Math.round((weatherViewport.viewportH - height) / 2)
        width: root.verticalLayout ? Math.max(120, weatherViewport.viewportW - 48) : 1
        height: root.verticalLayout
            ? 1
            : Math.max(120, Math.min(weatherViewport.viewportH - 40, weatherViewport.viewportH - 56))
        color: Appearance.colors.colPrimary
        opacity: 0.24
    }

    Rectangle {
        id: detailPanel
        x: root.verticalLayout ? 0 : (root.panelWidth + 13)
        y: root.verticalLayout ? (root.orbitHeight + 13) : 0
        width: root.verticalLayout
            ? weatherViewport.viewportW
            : Math.max(root.panelWidth, weatherViewport.viewportW - x)
        height: root.verticalLayout
            ? Math.max(root.detailContentHeight, weatherViewport.viewportH - y)
            : weatherViewport.viewportH
        radius: Appearance.rounding.small
        color: "transparent"


        ColumnLayout {
            id: detailColumn
            anchors {
                fill: parent
                leftMargin: root.compact ? 10 : 12
                rightMargin: root.compact ? 10 : 12
                topMargin: root.compact ? 10 : 12
                bottomMargin: root.compact ? 10 : 12
            }
            spacing: root.compact ? 6 : 7

            RowLayout {
                id: detailSummary
                Layout.fillWidth: true
                Layout.preferredHeight: root.compact ? 44 : 46
                spacing: root.compact ? 8 : 10

                MaterialSymbol {
                    text: Icons.getWeatherIcon(
                        Weather.data?.wCode,
                        Weather.isNightNow()) ?? "cloud"
                    iconSize: 30
                    color: root.accent
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    spacing: -1

                    StyledText {
                        text: Weather.data?.temp ?? "--°"
                        color: root.ink
                        font {
                            pixelSize: 25
                            weight: Font.Medium
                        }
                    }

                    StyledText {
                        text: Translation.tr("Feels like %1")
                            .arg(Weather.data?.tempFeelsLike ?? "--°")
                        color: root.mutedInk
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: 1

                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: Weather.data?.description ?? ""
                        color: root.ink
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: Font.DemiBold
                        }
                        elide: Text.ElideRight
                        Layout.maximumWidth: root.compact ? 118 : 130
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: Weather.showVisibleCity
                            ? Weather.visibleCity
                            : Translation.tr("Last refresh: %1")
                                .arg(Weather.data?.lastRefresh ?? "--:--")
                        color: root.mutedInk
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideRight
                        Layout.maximumWidth: root.compact ? 118 : 130
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        visible: Weather.showVisibleCity
                        text: Translation.tr("Last refresh: %1")
                            .arg(Weather.data?.lastRefresh ?? "--:--")
                        color: root.mutedInk
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }
            }

            GridLayout {
                id: primaryMetrics
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 6
                rowSpacing: root.compact ? 4 : 6
                uniformCellWidths: true

                PrimaryMetric {
                    title: Translation.tr("Humidity")
                    symbol: "humidity_low"
                    value: Weather.data?.humidity ?? "--"
                }
                PrimaryMetric {
                    title: Translation.tr("Wind")
                    symbol: "air"
                    value: ((Weather.data?.windDir ?? "") + " "
                        + (Weather.data?.wind ?? "--")).trim()
                }
                PrimaryMetric {
                    title: Translation.tr("Precipitation")
                    symbol: "rainy_light"
                    value: Weather.data?.precip ?? "--"
                }
                PrimaryMetric {
                    title: Translation.tr("UV Index")
                    symbol: "wb_sunny"
                    value: Weather.data?.uv ?? "--"
                }
            }

            Rectangle {
                id: secondaryStrip
                objectName: "weatherSecondaryMetrics"
                Layout.fillWidth: true
                implicitHeight: root.compact ? 32 : 34
                radius: Appearance.rounding.small
                color: root.cardColor

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    SecondaryMetric {
                        Layout.fillWidth: true
                        title: Translation.tr("Visibility")
                        symbol: "visibility"
                        value: Weather.data?.visib ?? "--"
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 18
                        color: root.outline
                    }

                    SecondaryMetric {
                        Layout.fillWidth: true
                        title: Translation.tr("Pressure")
                        symbol: "readiness_score"
                        value: Weather.data?.press ?? "--"
                    }
                }
            }

            Rectangle {
                id: sunTimeline
                objectName: "weatherSunTimeline"
                Layout.fillWidth: true
                implicitHeight: root.compact ? 52 : 56
                radius: Appearance.rounding.small
                color: root.cardColor

                MaterialSymbol {
                    id: sunriseIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.top: parent.top
                    anchors.topMargin: root.compact ? 7 : 8
                    text: "wb_twilight"
                    iconSize: 16
                    color: root.accent
                }

                MaterialSymbol {
                    id: sunsetIcon
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.top: parent.top
                    anchors.topMargin: root.compact ? 7 : 8
                    text: "bedtime"
                    iconSize: 16
                    color: root.accent
                }

                Rectangle {
                    id: sunTrack
                    anchors.left: sunriseIcon.right
                    anchors.right: sunsetIcon.left
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.verticalCenter: sunriseIcon.verticalCenter
                    height: 2
                    radius: 1
                    color: root.outline

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        x: Math.max(0, Math.min(parent.width - width,
                            root.sunProgress * parent.width - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.accent
                        border.width: 1
                        border.color: root.abyss ? root.cardColor : Appearance.colors.colLayer2
                    }
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.compact ? 6 : 7
                    text: Weather.data?.sunrise ?? "--:--"
                    color: root.ink
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.compact ? 6 : 7
                    text: Translation.tr("Sun")
                    color: root.mutedInk
                    font {
                        pixelSize: Appearance.font.pixelSize.smallest
                        weight: Font.DemiBold
                    }
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.compact ? 6 : 7
                    text: Weather.data?.sunset ?? "--:--"
                    color: root.ink
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }
    }

    component PrimaryMetric: Rectangle {
        id: primaryMetric
        objectName: "weatherPrimaryMetric"
        required property string title
        required property string symbol
        required property string value

        Layout.fillWidth: true
        implicitHeight: root.compact ? 36 : 42
        radius: Appearance.rounding.small
        color: root.cardColor

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 9
                rightMargin: 9
            }
            spacing: 7

            MaterialSymbol {
                text: primaryMetric.symbol
                iconSize: 15
                color: root.mutedInk
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: -1

                StyledText {
                    Layout.fillWidth: true
                    text: primaryMetric.title.toUpperCase()
                    color: root.mutedInk
                    font {
                        pixelSize: Appearance.font.pixelSize.smallest
                        weight: Font.DemiBold
                        letterSpacing: 0.4
                    }
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: primaryMetric.value
                    color: root.ink
                    font {
                        pixelSize: Appearance.font.pixelSize.small
                        weight: Font.DemiBold
                    }
                    elide: Text.ElideRight
                }
            }
        }
    }

    component SecondaryMetric: RowLayout {
        id: secondaryMetric
        required property string title
        required property string symbol
        required property string value
        spacing: 5

        MaterialSymbol {
            text: secondaryMetric.symbol
            iconSize: 15
            color: root.mutedInk
        }

        StyledText {
            text: secondaryMetric.title
            color: root.mutedInk
            font.pixelSize: Appearance.font.pixelSize.smallest
        }

        Item { Layout.fillWidth: true }

        StyledText {
            text: secondaryMetric.value
            color: root.ink
            font {
                pixelSize: Appearance.font.pixelSize.smaller
                weight: Font.DemiBold
            }
        }
    }
}
