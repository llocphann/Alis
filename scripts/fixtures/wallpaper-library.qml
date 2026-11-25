import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.modules.abyss.content
import qs.modules.common
import qs.modules.wallpaperLauncher
import qs.services

Window {
    id: win
    visible: true
    width: 1024
    height: 400
    readonly property string base: Quickshell.env("WALLPAPER_TEST_DIR")
    readonly property string folder: base + "/catalog"
    readonly property string still: folder + "/Ảnh\nblue 'trăng' #1.png"
    readonly property string animated: folder + "/BLUE đô thị.GIF"
    property bool abyss: false

    property bool chooseExtraOnFinish: false
    WallpaperLibrary {
        id: catalog
        onScanningChanged: {
            if (!scanning && win.chooseExtraOnFinish) {
                win.chooseExtraOnFinish = false
                refresh(win.base + "/extra", [], true)
            }
        }
    }
    FileView { id: requests; path: win.base + "/home/requests"; watchChanges: true; printErrors: false; onFileChanged: reload() }
    FileView { id: release; path: win.base + "/home/release"; printErrors: false }
    FileView { id: helperMode; path: win.base + "/home/mode"; printErrors: false }
    Component { id: dock; AbyssWallpaperContent { browseFolder: win.folder } }
    Component { id: standalone; WallpaperLauncherContent { browseFolder: win.folder } }
    Loader {
        id: loader
        anchors.fill: parent
        active: false
        sourceComponent: win.abyss ? dock : standalone
    }
    SignalSpy { id: publications; target: catalog; signalName: "refreshed" }
    SignalSpy { id: models; signalName: "filteredEntriesChanged" }

    TestCase {
        id: test
        when: false
        optional: true
        property int checks: 0
        function check(value, message) {
            if (!value) throw Error(message)
            checks++
        }

        function records() {
            return catalog.staticEntries.concat(catalog.animatedEntries)
        }

        function catalogChecks() {
            // The legacy newline caller coexists with lossless NUL-delimited scans.
            catalog.directory = "/base"
            catalog.consume("   /base/a.png  \n/base/demo.MP4\n/base/a.png\n")
            check(catalog.staticEntries.length === 1 && catalog.staticEntries[0].relativePath === "a.png", "legacy paths")
            check(catalog.animatedEntries[0].kind === "video", "mixed-case video")
            const paths = ["/base/a.png", "/base/café.gif", "/else/海.webM", "/base/a.png",
                           "/base/line\nbreak.png", "/base/片.avi", "/base/b.MKV", "/base/c.MOV"]
            const raw = paths.join("\0") + "\0"
            catalog.consume(raw, "\0")
            const expected = JSON.stringify(records())
            check(catalog.staticEntries.length === 2 && catalog.animatedEntries.length === 5, "kinds and deduplication")
            check(records().some(e => e.name === "line\nbreak.png" && e.searchKey.includes("break.png")), "literal line break")
            check(records().some(e => e.relativePath === "/else/海.webM" && e.kind === "video"), "external root")
            const old = catalog.staticEntries
            const emitted = publications.count
            old[0].name = "changed in consumer"
            catalog.consume(raw, "\0")
            check(catalog.staticEntries !== old && JSON.stringify(records()) === expected, "fresh records on identical refresh")
            check(publications.count === emitted + 1, "refresh signal")
            catalog.directory = "/else"
            catalog.consume(raw, "\0")
            check(records().some(e => e.relativePath === "海.webM"), "prefix change with identical bytes")
            catalog.consume(raw.replace("/base/c.MOV", "/base/d.MOV"), "\0")
            check(records().some(e => e.name === "d.MOV") && !records().some(e => e.name === "c.MOV"), "equal-count replacement")
            catalog.consume("")
            check(records().length === 0, "clear")

            catalog.refresh(win.folder, [win.base + "/extra", win.base + "/missing"], true)
            tryVerify(() => !catalog.scanning && catalog.staticEntries.length === 322, 5000)
            check(catalog.animatedEntries.length === 1 && records().some(e => e.path === win.still), "real find, partial root failure")
            catalog.refresh(win.base + "/missing", [], true)
            tryVerify(() => !catalog.scanning && !records().length, 5000)
            catalog.refresh(win.folder, [], true)
            tryVerify(() => !catalog.scanning && catalog.staticEntries.length === 321, 5000)
            win.chooseExtraOnFinish = true
            catalog.refresh(win.folder, [], true)
            catalog.refresh(win.base + "/missing", [], true)
            tryVerify(() => !catalog.scanning && catalog.staticEntries[0]?.name === "extra still.png", 4000)
            wait(80)
            check(catalog.directory === win.base + "/extra", "older queued request won")
        }

        function tagChecks() {
            const originalScripts = Directories.scriptPath
            const extra = win.base + "/extra"
            const seen = []
            const track = () => seen.push(Object.keys(catalog.colorTagsByPath))
            catalog.colorTagsByPathChanged.connect(track)
            Directories.scriptPath = win.base + "/tag-helper"
            try {
                catalog.refresh(win.folder, [], true)
                catalog.ensureColorTags()
                tryVerify(() => requests.text().includes("catalog"), 3000)
                catalog.refresh(extra, [], true)
                tryVerify(() => !catalog.scanning && catalog.directory === extra, 3000)
                catalog.ensureColorTags()
                wait(2100)  // The second folder's prefetch timer expires while the first helper is busy.
                release.setText("released")
                tryVerify(() => catalog.colorTagsByPath[extra + "/ok.png"]?.[0] === "blue", 4000)
                check(!seen.some(paths => paths.includes(win.folder + "/ok.png")), "retired folder published colors")
                check(requests.text().trim() === "catalog\nextra", "duplicate background lookup")
                for (const [i, mode] of ["failed", "malformed", "updated"].entries()) {
                    helperMode.setText(mode)
                    tryVerify(() => helperMode.text().trim() === mode, 2000)
                    catalog.ensureColorTags()
                    tryVerify(() => requests.text().trim().split("\n").length === 3 + i, 3000)
                    if (mode === "updated") {
                        tryVerify(() => catalog.colorTagsByPath[extra + "/updated.png"]?.[0] === "blue", 3000)
                        check(!catalog.colorTagsByPath[extra + "/ok.png"], "retired tag retained")
                    } else {
                        wait(100)
                        check(Object.keys(catalog.colorTagsByPath).join() === extra + "/ok.png", "failed lookup overwrote colors")
                    }
                }
            } finally {
                catalog.colorTagsByPathChanged.disconnect(track)
                Directories.scriptPath = originalScripts
            }
        }

        function pickerChecks(abyss) {
            win.abyss = abyss
            Config.setNestedValue("panelFamily", abyss ? "abyss" : "waffle")
            GlobalStates.wallpaperLauncherSearchText = ""
            GlobalStates.wallpaperLauncherMode = "static"
            loader.active = true
            tryCompare(loader, "status", Loader.Ready, 4000)
            GlobalStates.wallpaperLauncherOpen = true
            const picker = loader.item
            const view = findChild(picker, "wallpaperCarousel")
            tryVerify(() => !picker.loading && picker.count === 321, 5000)
            if (abyss)
                GlobalStates.wallpaperLauncherSearchText = "blue"
            else
                findChild(picker, "wallpaperSearch").text = "blue"
            tryCompare(picker, "count", 2, 3000)
            check(view.filteredEntries[0].path === win.still && view.filteredEntries[1].path === win.animated, "mixed search order")
            view.colorTagsByPath = ({})
            wait(180)
            picker.moveSelection(1)
            tryCompare(picker, "selectedPath", win.animated, 2000)
            models.target = view
            models.clear()
            const tags = {}
            tags[win.animated] = ["blue"]
            view.colorTagsByPath = tags
            wait(100)
            check(models.count === 0 && picker.selectedPath === win.animated, "unrelated colors reset text search")
            picker.selectedColor = "blue"
            tryVerify(() => picker.count === 1 && picker.selectedPath === win.animated, 3000)
            const moreTags = {}
            moreTags[win.still] = ["blue"]
            view.colorTagsByPath = moreTags
            tryVerify(() => picker.count === 1 && picker.selectedPath === win.still, 3000)
            check(models.count > 0, "active color results must update")
            picker.selectedColor = ""
            // The fallback may include a primary path supplied by another model.
            view.fallbackEntries = [view.entries.find(e => e.path === win.still), {path: win.animated, name: "BLUE đô thị.GIF", kind: "gif", searchKey: "blue"}]
            tryCompare(picker, "count", 2, 2000)
            check(view.filteredEntries[1].path === win.animated, "duplicate fallback")
            models.target = null
            wait(100)
            picker.setMode("animated")
            if (abyss) {
                // Random wallpaper must only preview (never mutate durable wallpaperPath)
                GlobalStates.wallpaperLauncherSearchText = ""
                picker.setMode("static")
                const savedPath = String(Config.options?.background?.wallpaperPath ?? "")
                view.fallbackEntries = [view.entries.find(e => e.path === win.animated) ?? {path: win.animated, name: "BLUE đô thị.GIF", kind: "gif", searchKey: "blue"}, {path: win.still, name: "still.png", kind: "static", searchKey: "still"}]
                tryVerify(() => picker.count >= 2, 2000)
                picker.pickRandomWallpaper()
                check(Wallpapers.internalPreviewPath.length > 0, "random wallpaper did not trigger preview")
                check(String(Config.options?.background?.wallpaperPath ?? "") === savedPath, "random wallpaper applied instead of previewing")

                // Folder post-close Escape race must absorb 1st Escape and close on 2nd Escape
                picker._folderDialogClosedAtMs = Date.now()
                picker.handleEscape()
                check(GlobalStates.wallpaperLauncherOpen === true, "first Escape after folder close should keep Change Wallpaper open")
                wait(340)
                picker.handleEscape()
                check(GlobalStates.wallpaperLauncherOpen === false, "second Escape did not close Change Wallpaper")
            }
            GlobalStates.wallpaperLauncherOpen = false
            loader.active = false
            tryVerify(() => loader.item === null, 2000)
            wait(100)
        }

        function runChecks() {
            try {
                tryCompare(Config, "ready", true, 5000)
                catalogChecks()
                tagChecks()
                pickerChecks(false)
                pickerChecks(true)
                console.info("WALLPAPER_LIBRARY_PASS", checks)
            } catch (error) {
                console.error("WALLPAPER_LIBRARY_FAIL", error.message, error.stack)
            }
            Qt.quit()
        }
    }

    Timer { interval: 120; running: true; onTriggered: test.runChecks() }
}
