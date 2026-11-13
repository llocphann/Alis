pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import qs.services
import "root:"

/**
 * NewsService - Google News RSS (no auth/API key required)
 *
 * Feeds:
 *  - "local": geo headlines for the city resolved by the Weather service
 *    (reuses its manual-location/GPS/IP chain — no duplicate detection here)
 *  - "top": top stories for the user's locale
 *  - topic boards: WORLD, NATION, BUSINESS, TECHNOLOGY, ENTERTAINMENT,
 *    SCIENCE, SPORTS, HEALTH
 */
Singleton {
    id: root

    // Data
    property var articles: []
    property bool loading: false
    property string lastError: ""

    // Cache per feed key
    property var _cache: ({})
    property var _cacheTimestamps: ({})
    property int _requestGeneration: 0
    readonly property int cacheValidityMs: 15 * 60 * 1000

    readonly property var topics: ["WORLD", "NATION", "BUSINESS", "TECHNOLOGY", "ENTERTAINMENT", "SCIENCE", "SPORTS", "HEALTH"]

    // Locale params for Google News. Qt.locale().name is "es_AR"-style (guard "C" locale).
    readonly property string _normalizedLocaleName: {
        const raw = String(Qt.locale().name || "").trim()
        if (!raw || raw === "C" || raw.startsWith("C."))
            return "en_US"
        return raw
    }
    readonly property string _lang: {
        const lang = _normalizedLocaleName.split(/[_.-]/)[0] || "en"
        return lang.toLowerCase() === "c" ? "en" : lang
    }
    readonly property string _country: {
        const parts = _normalizedLocaleName.split(/[_.-]/)
        return (parts.length > 1 && parts[1].length >= 2) ? parts[1].toUpperCase() : "US"
    }
    readonly property string _localeQuery: `hl=${_lang}&gl=${_country}&ceid=${_country}:${_lang}`

    // City for the geo feed, from Weather's already-resolved location.
    readonly property string localCity: {
        const name = Weather.location?.name ?? ""
        return (Weather.location?.valid ?? false) ? name.split(",")[0].trim() : ""
    }

    function feedUrl(mode, topic) {
        if (mode === "local" && root.localCity.length > 0)
            return `https://news.google.com/rss/headlines/section/geo/${encodeURIComponent(root.localCity)}?${root._localeQuery}`
        if (mode === "topic" && root.topics.includes(topic))
            return `https://news.google.com/rss/headlines/section/topic/${topic}?${root._localeQuery}`
        return `https://news.google.com/rss?${root._localeQuery}`
    }

    function localSearchUrl() {
        return `https://news.google.com/rss/search?q=${encodeURIComponent(root.localCity)}&${root._localeQuery}`
    }

    function _mergeUniqueArticles(primaryList, supplementList, maxCount = 30) {
        const merged = []
        const seenUrls = ({})
        const seenTitles = ({})
        const appendFrom = (list) => {
            if (!Array.isArray(list))
                return
            for (let i = 0; i < list.length && merged.length < maxCount; i++) {
                const item = list[i]
                if (!item || !item.title || !item.url)
                    continue
                const normTitle = String(item.title).trim().toLowerCase()
                if (seenUrls[item.url] || seenTitles[normTitle])
                    continue
                seenUrls[item.url] = true
                seenTitles[normTitle] = true
                merged.push(item)
            }
        }
        appendFrom(primaryList)
        appendFrom(supplementList)
        return merged
    }

    function _fetchLocalSearchSupplement(cacheKeyUrl, generation, baseArticles) {
        const searchUrl = root.localSearchUrl()
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (generation !== root._requestGeneration)
                return
            let combined = Array.isArray(baseArticles) ? baseArticles : []
            if (xhr.status === 200) {
                const extra = root._parseRss(xhr.responseText)
                combined = root._mergeUniqueArticles(combined, extra, 30)
            }
            if (combined.length === 0) {
                root.fetch("top", "")
                return
            }
            root._cache[cacheKeyUrl] = combined
            root._cacheTimestamps[cacheKeyUrl] = Date.now()
            root.loading = false
            root.lastError = ""
            root.articles = combined
        }
        xhr.open("GET", searchUrl)
        xhr.setRequestHeader("User-Agent", Config.options?.networking?.userAgent ?? "Mozilla/5.0")
        xhr.send()
    }

    function fetch(mode, topic) {
        const url = root.feedUrl(mode, topic)
        const generation = ++root._requestGeneration
        if (root._isCacheValid(url) && root._cache[url]) {
            root.loading = false
            root.lastError = ""
            root.articles = root._cache[url]
            return
        }
        root.loading = true
        root.lastError = ""
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                if (generation === root._requestGeneration) {
                    if (mode === "local" && root.localCity.length > 0) {
                        root._fetchLocalSearchSupplement(url, generation, [])
                        return
                    }
                    root.loading = false
                    root.lastError = "HTTP " + xhr.status
                }
                return
            }
            const parsed = root._parseRss(xhr.responseText)
            if (generation !== root._requestGeneration)
                return
            if (mode === "local" && root.localCity.length > 0 && parsed.length < 6) {
                root._fetchLocalSearchSupplement(url, generation, parsed)
                return
            }
            root._cache[url] = parsed
            root._cacheTimestamps[url] = Date.now()
            root.loading = false
            root.lastError = ""
            root.articles = parsed
        }
        xhr.open("GET", url)
        xhr.setRequestHeader("User-Agent", Config.options?.networking?.userAgent ?? "Mozilla/5.0")
        xhr.send()
    }

    function refresh(mode, topic) {
        root._cache = {}
        root._cacheTimestamps = {}
        root.fetch(mode, topic)
    }

    function _isCacheValid(key) {
        const ts = root._cacheTimestamps[key]
        return ts ? (Date.now() - ts) < root.cacheValidityMs : false
    }

    // Minimal RSS <item> extraction — Google News items are flat and regular,
    // a full XML parser buys nothing here.
    function _parseRss(xml) {
        const items = []
        const itemRe = /<item>([\s\S]*?)<\/item>/g
        const titleRe = /<title[^>]*>([\s\S]*?)<\/title>/
        const linkRe = /<link[^>]*>([\s\S]*?)<\/link>/
        const pubDateRe = /<pubDate[^>]*>([\s\S]*?)<\/pubDate>/
        const sourceRe = /<source[^>]*>([\s\S]*?)<\/source>/
        let m
        while ((m = itemRe.exec(xml)) !== null && items.length < 30) {
            const block = m[1]
            const title = root._decodeHtml(root._tagWithRegex(block, titleRe))
            const link = root._tagWithRegex(block, linkRe)
            const pubDate = root._tagWithRegex(block, pubDateRe)
            const source = root._decodeHtml(root._tagWithRegex(block, sourceRe))
            if (!title || !link)
                continue
            // Google News titles end in " - Source"; strip when source is known.
            const cleanTitle = source && title.endsWith(" - " + source)
                ? title.slice(0, title.length - source.length - 3) : title
            items.push({
                title: cleanTitle,
                url: link,
                source: source,
                timestamp: pubDate ? Date.parse(pubDate) / 1000 : 0
            })
        }
        return items
    }

    function _tagWithRegex(block, regex) {
        const m = block.match(regex)
        if (!m)
            return ""
        return m[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/, "$1").trim()
    }

    function _tag(block, name) {
        const m = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`))
        if (!m)
            return ""
        return m[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/, "$1").trim()
    }

    function _decodeHtml(html) {
        if (!html)
            return ""
        return html.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&apos;/g, "'")
    }

    function formatTime(timestamp) {
        if (!timestamp)
            return ""
        const diff = Date.now() / 1000 - timestamp
        if (diff < 3600)
            return Math.max(1, Math.floor(diff / 60)) + "m"
        if (diff < 86400)
            return Math.floor(diff / 3600) + "h"
        return Math.floor(diff / 86400) + "d"
    }

    function openArticle(article) {
        // Focus an existing browser window first so the link doesn't open unseen.
        if (typeof NiriService !== "undefined" && NiriService.windows) {
            const browserPatterns = ["firefox", "chromium", "chrome", "brave", "zen", "librewolf", "vivaldi", "opera"]
            const windows = NiriService.windows ?? []
            for (let i = 0; i < windows.length; i++) {
                const appId = (windows[i].app_id ?? "").toLowerCase()
                if (browserPatterns.some(p => appId.includes(p))) {
                    NiriService.focusWindow(windows[i].id)
                    break
                }
            }
        }
        Qt.openUrlExternally(article.url)
    }
}
