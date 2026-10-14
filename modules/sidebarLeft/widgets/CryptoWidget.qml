pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "root:"

Item {
    id: root
    implicitHeight: card.implicitHeight + Appearance.sizes.elevationMargin

    property var cryptoData: ({})
    property var sparklineData: ({})
    property bool loading: false
    property bool error: false
    property bool _cacheLoaded: false
    property real _cacheTimestamp: 0

    readonly property var coins: Config.options?.sidebar?.widgets?.crypto_settings?.coins ?? []
    readonly property int refreshInterval: (Config.options?.sidebar?.widgets?.crypto_settings?.refreshInterval ?? 300) * 1000
    readonly property string cachePath: FileUtils.trimFileProtocol(`${Directories.state}/user/crypto_cache.json`)
    readonly property bool presentationActive: GlobalStates.sidebarLeftOpen && root.visible

    // --- File-based cache ---
    FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: false

        onLoaded: {
            try {
                const cached = JSON.parse(cacheFile.text())
                if (cached.cryptoData && Object.keys(cached.cryptoData).length > 0) {
                    root.cryptoData = cached.cryptoData
                }
                if (cached.sparklineData && Object.keys(cached.sparklineData).length > 0) {
                    root.sparklineData = cached.sparklineData
                }
                root._cacheTimestamp = Number(cached.timestamp) || 0
            } catch (e) {
                // Corrupted cache, ignore
            }
            root._cacheLoaded = true
        }

        onLoadFailed: (error) => {
            // No cache yet, that's fine
            root._cacheLoaded = true
        }
    }

    function saveCache() {
        try {
            const timestamp = Date.now()
            root._cacheTimestamp = timestamp
            cacheFile.setText(JSON.stringify({
                cryptoData: root.cryptoData,
                sparklineData: root.sparklineData,
                timestamp: timestamp
            }))
        } catch (e) {
            // Non-critical, ignore write failures
        }
    }

    function _hasMissingCoinData(): bool {
        for (const coin of root.coins) {
            if (!(coin in root.cryptoData))
                return true
        }
        return false
    }

    function _cacheNeedsRefresh(): bool {
        if (root.coins.length === 0)
            return false
        if (root._hasMissingCoinData())
            return true
        if (root._cacheTimestamp <= 0)
            return true
        return (Date.now() - root._cacheTimestamp) >= root.refreshInterval
    }

    function _scheduleRefreshIfNeeded(): void {
        if (!root.presentationActive || !root._cacheLoaded || root.coins.length === 0 || !Config.ready)
            return
        if (!root._cacheNeedsRefresh() || priceProcess.running)
            return

        const hasData = Object.keys(root.cryptoData).length > 0
        if (hasData && !root._hasMissingCoinData())
            refreshDelayTimer.restart()
        else
            Qt.callLater(() => root.fetchPrices())
    }

    Timer {
        id: fetchTimer
        interval: root.refreshInterval
        running: root.presentationActive && root.coins.length > 0 && Config.ready
        repeat: true
        triggeredOnStart: true
        onTriggered: root._scheduleRefreshIfNeeded()
    }

    onCoinsChanged: {
        if (root._cacheLoaded)
            root._scheduleRefreshIfNeeded()
    }

    on_CacheLoadedChanged: {
        if (root._cacheLoaded)
            root._scheduleRefreshIfNeeded()
    }

    onPresentationActiveChanged: {
        if (root.presentationActive) {
            root._scheduleRefreshIfNeeded()
        } else {
            refreshDelayTimer.stop()
            sparklineTimer.stop()
        }
    }

    Timer {
        id: refreshDelayTimer
        interval: 2000
        onTriggered: {
            if (root.presentationActive && root._cacheNeedsRefresh())
                root.fetchPrices()
        }
    }

    function fetchPrices() {
        if (!root.presentationActive || root.coins.length === 0 || priceProcess.running)
            return
        loading = true
        error = false
        priceProcess.url = "https://api.coingecko.com/api/v3/simple/price?ids=" + root.coins.join(",") + "&vs_currencies=usd&include_24hr_change=true"
        priceProcess.running = true
    }

    Process {
        id: priceProcess
        property string url: ""
        command: ["/usr/bin/curl", "-s", "--max-time", "10", url]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                if (text.length === 0) {
                    root.error = true
                    return
                }
                try {
                    root.cryptoData = JSON.parse(text)
                    root.error = false
                    root.saveCache()
                    if (root.presentationActive)
                        root.fetchSparklines()
                } catch (e) {
                    root.error = true
                }
            }
        }
    }

    property int _sparklineIdx: 0
    function fetchSparklines() {
        if (!root.presentationActive || root.coins.length === 0 || sparklineProcess.running)
            return
        root._sparklineIdx = 0
        sparklineTimer.restart()
    }

    function _startNextSparkline(): void {
        if (!root.presentationActive || sparklineProcess.running || root._sparklineIdx >= root.coins.length)
            return

        const id = root.coins[root._sparklineIdx]
        root._sparklineIdx++
        sparklineProcess.coinId = id
        sparklineProcess.url = "https://api.coingecko.com/api/v3/coins/" + id + "/market_chart?vs_currency=usd&days=1"
        sparklineProcess.running = true
    }

    Timer {
        id: sparklineTimer
        interval: 1000
        repeat: false
        onTriggered: root._startNextSparkline()
    }

    Process {
        id: sparklineProcess
        property string coinId: ""
        property string url: ""
        command: ["/usr/bin/curl", "-s", "--max-time", "10", url]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const data = JSON.parse(text)
                    if (data.prices && data.prices.length > 0) {
                        const prices = data.prices.map(p => p[1])
                        const min = Math.min.apply(null, prices)
                        const max = Math.max.apply(null, prices)
                        const range = max - min || 1
                        const step = Math.max(1, Math.floor(prices.length / 20))
                        const sampled = []
                        for (let i = 0; i < prices.length; i += step) {
                            sampled.push((prices[i] - min) / range)
                        }
                        const newData = Object.assign({}, root.sparklineData)
                        newData[sparklineProcess.coinId] = sampled.slice(-20)
                        root.sparklineData = newData
                        root.saveCache()
                    }
                } catch (e) {}
            }
        }
        onExited: {
            if (root.presentationActive && root._sparklineIdx < root.coins.length)
                sparklineTimer.restart()
        }
    }

    readonly property var coinSymbols: ({
        "bitcoin": "BTC", "ethereum": "ETH", "solana": "SOL", "cardano": "ADA",
        "dogecoin": "DOGE", "ripple": "XRP", "polkadot": "DOT", "avalanche-2": "AVAX",
        "chainlink": "LINK", "polygon": "MATIC", "litecoin": "LTC", "uniswap": "UNI",
        "stellar": "XLM", "monero": "XMR", "tron": "TRX", "toncoin": "TON",
        "shiba-inu": "SHIB", "pepe": "PEPE", "binancecoin": "BNB"
    })

    function getSymbol(id) { return coinSymbols[id] ?? id.toUpperCase().slice(0, 4) }
    function fmtPrice(p) {
        if (!p) return "---"
        return p >= 1000 ? p.toLocaleString(Qt.locale(), 'f', 0)
             : p >= 1 ? p.toLocaleString(Qt.locale(), 'f', 2)
             : p >= 0.01 ? p.toLocaleString(Qt.locale(), 'f', 4)
             : p.toLocaleString(Qt.locale(), 'f', 6)
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: parent.width
        implicitHeight: col.implicitHeight + 20
        radius: Appearance.zzzEverywhere ? Appearance.zzz.cardRadius : Appearance.alisEverywhere ? Appearance.alis.roundingNormal : Appearance.rounding.normal
        color: "transparent"
        Behavior on radius { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve } }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "currency_bitcoin"
                    iconSize: 16
                    color: Appearance.zzzEverywhere ? Appearance.zzz.accent : Appearance.alisEverywhere ? Appearance.alis.colPrimary : Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("Crypto")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer1
                }
                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: Appearance.zzzEverywhere ? Appearance.zzz.accent : Appearance.alisEverywhere ? Appearance.alis.colPrimary : Appearance.colors.colPrimary
                    Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    scale: root.loading ? 1 : 0
                    visible: scale > 0
                    Behavior on scale {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic }
                    }
                    opacity: 0.6
                    SequentialAnimation on opacity {
                        running: root.loading && GlobalStates.sidebarLeftOpen && Appearance.animationsEnabled
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 400 }
                        NumberAnimation { to: 0.8; duration: 400 }
                    }
                }

                RippleButton {
                    implicitWidth: 24; implicitHeight: 24
                    buttonRadius: Appearance.alisEverywhere ? Appearance.alis.roundingSmall : Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.zzzEverywhere ? Appearance.zzz.chrome : Appearance.alisEverywhere ? Appearance.alis.colLayer1Hover : Appearance.colors.colLayer1Hover
                    onClicked: root.fetchPrices()
                    contentItem: MaterialSymbol {
                        text: "refresh"; iconSize: 14
                        color: Appearance.alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colOnLayer1Inactive
                    }
                    StyledToolTip { text: Translation.tr("Refresh") }
                }
            }

            Repeater {
                model: root.coins

                RowLayout {
                    id: row
                    required property string modelData
                    readonly property var d: root.cryptoData[modelData]
                    readonly property real price: d?.usd ?? 0
                    readonly property real chg: d?.usd_24h_change ?? 0
                    readonly property bool up: chg >= 0
                    readonly property var spark: root.sparklineData[modelData] ?? []

                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: root.getSymbol(row.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer1
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                        Layout.preferredWidth: 36
                    }

                    StyledText {
                        text: "$" + root.fmtPrice(row.price)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        font.weight: Appearance.zzzEverywhere ? Font.Black : Font.Normal
                        font.italic: Appearance.zzzEverywhere
                        color: Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer1
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                        Layout.fillWidth: true
                    }

                    Graph {
                        visible: row.spark.length > 1
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        values: row.spark
                        color: row.up ? (Appearance.zzzEverywhere ? Appearance.zzz.accent : Appearance.alisEverywhere ? Appearance.alis.colPrimary : Appearance.colors.colPrimary)
                                      : (Appearance.zzzEverywhere ? Appearance.zzz.signal : Appearance.alisEverywhere ? Appearance.alis.colError : Appearance.colors.colError)
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                        fillOpacity: 0.25
                        alignment: Graph.Alignment.Right
                    }

                    RowLayout {
                        visible: row.price > 0
                        spacing: 0
                        Layout.preferredWidth: 44
                        Layout.alignment: Qt.AlignVCenter

                        MaterialSymbol {
                            text: row.up ? "arrow_drop_up" : "arrow_drop_down"
                            iconSize: 14
                            color: row.up ? (Appearance.zzzEverywhere ? Appearance.zzz.accent : Appearance.alisEverywhere ? Appearance.alis.colPrimary : Appearance.colors.colPrimary)
                                          : (Appearance.zzzEverywhere ? Appearance.zzz.signal : Appearance.alisEverywhere ? Appearance.alis.colError : Appearance.colors.colError)
                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                            }
                        }
                        StyledText {
                            text: Math.abs(row.chg).toFixed(1) + "%"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: row.up ? (Appearance.zzzEverywhere ? Appearance.zzz.accent : Appearance.alisEverywhere ? Appearance.alis.colPrimary : Appearance.colors.colPrimary)
                                          : (Appearance.zzzEverywhere ? Appearance.zzz.signal : Appearance.alisEverywhere ? Appearance.alis.colError : Appearance.colors.colError)
                            Behavior on color {
                                enabled: Appearance.animationsEnabled
                                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.error && Object.keys(root.cryptoData).length === 0
                text: Translation.tr("Failed to load")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.zzzEverywhere ? Appearance.zzz.signal : Appearance.alisEverywhere ? Appearance.alis.colError : Appearance.colors.colError
                Behavior on color {
                    enabled: Appearance.animationsEnabled
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
            }
            StyledText {
                visible: root.coins.length === 0
                text: Translation.tr("No coins configured")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.zzzEverywhere ? Appearance.zzz.inkMuted : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colSubtext
                Behavior on color {
                    enabled: Appearance.animationsEnabled
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
            }
        }
    }
}
