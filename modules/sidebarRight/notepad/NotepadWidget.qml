import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "MarkdownNote.js" as MarkdownNote
import "NoteRailWheel.js" as NoteRailWheel

Item {
    id: root

    signal editorActivated()
    signal editorDeactivated()

    property int margin: 10
    // Dashboard can opt into a denser chrome while Sidebar keeps the full
    // title/stats/toolbar presentation. The editor and draft semantics stay
    // identical across both surfaces.
    property bool compactPresentation: false
    // Hot-corner Quick Notes is a capture surface rather than a tab manager.
    // Keep the same editor/autosave backend while hiding Dashboard/Sidebar
    // navigation chrome that would slow down a one-thought interaction.
    property bool quickCapturePresentation: false
    // Dashboard and corner Quick Notes render Markdown until the text input
    // actually has focus. Full Notepad and Sidebar keep Source-first behavior.
    property bool autoMarkdownReading: false
    // The corner layer-shell popup handles Escape as a window shortcut.
    // Avoid handling the same press in both the editor and its host.
    property bool externalEscapeHandling: false
    property bool markdownEditing: !root.autoMarkdownReading
    readonly property bool markdownReading: root.autoMarkdownReading && !root.markdownEditing
    property int _markdownFocusEpoch: 0
    property bool verticalDotNavigation: false
    property var _noteRailWheelState: NoteRailWheel.idle()
    // Quick Notes can coexist on Dashboard, Sidebar Left and the bottom-left
    // corner. In that mode each surface keeps the stable ID of the note it is
    // actually displaying instead of letting another surface's currentTab
    // change steal the editor out from under an in-progress draft.
    property bool surfaceLocalTabSelection: false
    readonly property bool narrowCompact:
        root.compactPresentation && root.width > 0 && root.width < 260
    readonly property bool veryNarrowCompact:
        root.compactPresentation && root.width > 0 && root.width < 220

    // Style tokens (5-style support)
    readonly property color colText: Appearance.angelEverywhere ? Appearance.angel.colText
        : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
    readonly property color colTextSecondary: Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
        : Appearance.inirEverywhere ? Appearance.inir.colTextSecondary : Appearance.colors.colSubtext
    readonly property color colCard: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : Appearance.inirEverywhere ? Appearance.inir.colLayer0
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
        : Appearance.colors.colLayer0
    readonly property color colBorder: Appearance.angelEverywhere ? Appearance.angel.colCardBorder
        : Appearance.inirEverywhere ? Appearance.inir.colBorder : Appearance.colors.colLayer0Border
    readonly property int borderWidth: Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth
        : Appearance.inirEverywhere ? 1 : (Appearance.auroraEverywhere ? 0 : 1)
    readonly property real radius: Appearance.angelEverywhere ? Appearance.angel.roundingNormal
        : Appearance.inirEverywhere ? Appearance.inir.roundingNormal : Appearance.rounding.normal
    readonly property color colPrimary: Appearance.angelEverywhere ? Appearance.angel.colPrimary
        : Appearance.inirEverywhere ? Appearance.inir.colPrimary : Appearance.colors.colPrimary

    // Word count helper
    readonly property int wordCount: textArea.text.trim().length > 0
        ? textArea.text.trim().split(/\s+/).length : 0
    readonly property int tabCount: Notepad.tabs.length
    readonly property string attachmentDirectory: Directories.stateUserPath + "/notepad-attachments"
    readonly property var imageUrls:
        MarkdownNote.attachmentUrls(textArea.text, root.attachmentDirectory)
    readonly property bool attachmentBusy: clipboardProc.pending
    function pasteFromClipboard(): bool {
        return root._startAttachment("")
    }
    function importImage(source): bool {
        return root._startAttachment(String(source))
    }
    function _startAttachment(source): bool {
        if (!Notepad.ready || root.attachmentBusy || !root._loadedTabId)
            return false
        root.flushPendingSave()
        clipboardProc.noteId = root._loadedTabId
        clipboardProc.cursor = textArea.cursorPosition
        clipboardProc.selectionStart = textArea.selectionStart
        clipboardProc.selectionEnd = textArea.selectionEnd
        clipboardProc.snapshot = String(textArea.text)
        clipboardProc.command = ["/usr/bin/python3",
            Directories.scriptsPath + "/notes/attachments.py", "--root", root.attachmentDirectory]
        if (source.length > 0)
            clipboardProc.command = clipboardProc.command.concat(["--import-image", source])
        clipboardProc.startObserved = false
        clipboardProc.pending = true
        clipboardProc.running = true
        return true
    }
    function insertAttachmentResult(noteId, cursor, payload, selectionStart = -1, selectionEnd = -1, snapshot = ""): bool {
        if (!Notepad.ready || Notepad.indexForTabId(noteId) < 0)
            return false
        const value = String(payload.text ?? "")
        if (!value.length) return true
        if (root._loadedTabId === noteId) {
            if (selectionEnd > selectionStart && selectionStart >= 0 && snapshot === textArea.text) {
                textArea.remove(selectionStart, selectionEnd)
                cursor = selectionStart
            }
            textArea.insert(Math.max(0, Math.min(cursor, textArea.length)), value)
            root.flushPendingSave()
        } else {
            const draft = String(Notepad.tabs[Notepad.indexForTabId(noteId)]?.text ?? "")
            const selected = selectionEnd > selectionStart && selectionStart >= 0 && snapshot === draft
            const position = Math.max(0, Math.min(selected ? selectionStart : cursor, draft.length))
            Notepad.setTabTextById(noteId, draft.slice(0, position) + value + draft.slice(selected ? selectionEnd : position))
        }
        return true
    }
    // The corner Quick Notes capture surface does not expose Zettelkasten
    // actions. Keep that optional singleton (and its Todo backend dependency)
    // cold while the hover popup is only being used as a shared editor.
    readonly property bool zettelkastenIntegrationEnabled:
        !root.quickCapturePresentation
    readonly property bool canSaveZettel: root.zettelkastenIntegrationEnabled
        && Notepad.ready
        && Zettelkasten.ready
        && !Zettelkasten.busy
        && textArea.text.trim().length > 0
    function _captureZettel(): bool {
        if (!root.canSaveZettel)
            return false

        // Persist the visible editor first, then capture a snapshot without
        // consuming or clearing the Notepad draft. Capture is intentionally
        // non-destructive; draft cleanup remains an explicit user action.
        root.flushPendingSave()

        const index = Notepad.indexForTabId(root._loadedTabId)
        const tabTitle = String(Notepad.tabs[index]?.title ?? "").trim()
        const title = /^Note \d+$/.test(tabTitle) ? "" : tabTitle
        const draftText = String(textArea.text)
        if (root.imageUrls.length > 0)
            return Zettelkasten.captureWithAttachments(title, draftText, root.attachmentDirectory)
        return Zettelkasten.capture(title, draftText)
    }

    function saveAsZettel(): bool {
        return root._captureZettel()
    }

    function captureQuickNote(): bool {
        return root._captureZettel()
    }

    // Public focus/save hooks for lightweight secondary surfaces such as the
    // bottom-left Quick Notes popup. They keep the canonical editor in charge
    // of autosave semantics without exposing its private TextArea.
    function focusEditor(): void {
        if (!Notepad.ready)
            return
        root.markdownEditing = true
        const focusEpoch = ++root._markdownFocusEpoch
        Qt.callLater(() => {
            if (focusEpoch === root._markdownFocusEpoch
                    && root.markdownEditing && root.visible && root.enabled)
                textArea.forceActiveFocus()
        })
    }

    function releaseEditorFocus(): void {
        ++root._markdownFocusEpoch
        root.flushPendingSave()
        if (root.autoMarkdownReading)
            root.markdownEditing = false
        textArea.focus = false
        root.focus = false
    }

    function formatMarkdown(kind): bool {
        // This is Source editing, never conversion to rendered text.
        if (!Notepad.ready || !root.markdownEditing || !textArea.activeFocus)
            return false
        const start = textArea.selectionStart >= 0
            ? textArea.selectionStart : textArea.cursorPosition
        const end = textArea.selectionEnd >= 0
            ? textArea.selectionEnd : textArea.cursorPosition
        const patch = MarkdownNote.format(textArea.text, start, end, kind)
        if (!patch)
            return false
        // TextArea's incremental edits retain the native undo stack.
        textArea.remove(patch.from, patch.to)
        textArea.insert(patch.from, patch.insert)
        textArea.select(patch.selectionStart, patch.selectionEnd)
        return true
    }

    function _activeTabId(): string {
        return String(Notepad.tabs[Notepad.currentTab]?.id ?? "")
    }

    function _loadedTabText(): string {
        const index = Notepad.indexForTabId(root._loadedTabId)
        if (index < 0)
            return ""
        return String(Notepad.tabs[index]?.text ?? "")
    }

    function _persistEditorText(): bool {
        if (!Notepad.ready || root._loadingTab || !root._loadedTabId)
            return false
        if (textArea.text === root._loadedTabText())
            return true
        return Notepad.setTabTextById(root._loadedTabId, textArea.text)
    }

    function flushPendingSave(): void {
        saveTimer.stop()
        root._persistEditorText()
    }

    // Tab mutations can change Notepad.currentTab synchronously. Persist the
    // current editor first so an 800ms autosave still pending in the old tab
    // can never be written into, or discarded by, the newly-selected tab.
    function switchToTab(index): void {
        if (!Notepad.ready || index < 0 || index >= Notepad.tabs.length)
            return
        const targetId = String(Notepad.tabs[index]?.id ?? "")
        root.flushPendingSave()
        if (!Notepad.switchTab(index))
            return
        if (root.surfaceLocalTabSelection)
            root._loadTabById(targetId)
    }

    function addTabSafely(): void {
        root.flushPendingSave()
        if (!Notepad.addTab())
            return
        if (root.surfaceLocalTabSelection)
            root._loadActiveTab()
    }

    function removeTabSafely(index): void {
        if (!Notepad.ready || index < 0 || index >= Notepad.tabs.length)
            return
        const removedId = String(Notepad.tabs[index]?.id ?? "")
        const removingDisplayedTab = removedId === root._loadedTabId
        let fallbackId = ""
        if (removingDisplayedTab && Notepad.tabs.length > 1) {
            const fallbackIndex = index + 1 < Notepad.tabs.length ? index + 1 : index - 1
            fallbackId = String(Notepad.tabs[fallbackIndex]?.id ?? "")
        }

        root.flushPendingSave()
        if (!Notepad.removeTab(index))
            return

        if (root.surfaceLocalTabSelection && removingDisplayedTab) {
            if (!root._loadTabById(fallbackId))
                root._loadActiveTab()
        }
    }

    // When this widget gets focus (from BottomWidgetGroup.focusActiveItem),
    // move focus to the internal text area on the next event loop tick.
    onFocusChanged: (focus) => {
        if (focus)
            root.focusEditor()
    }
    Component.onDestruction: root.flushPendingSave()

    // Guards programmatic text loads (tab switch / external reload) so they
    // don't trigger the save timer and clobber the freshly-loaded tab. Track the
    // tab identity separately from Notepad.currentTab: several NotepadWidget
    // instances can exist at once (Sidebar, Dashboard and Quick Notes), and a
    // delayed autosave must always write back to the tab it actually displays.
    property bool _loadingTab: false
    property string _loadedTabId: ""
    readonly property string displayedTabId: root._loadedTabId
    readonly property int displayedTabIndex:
        Notepad.indexForTabId(root._loadedTabId)
    readonly property string displayedTabTitle:
        root.displayedTabIndex >= 0
            ? String(Notepad.tabs[root.displayedTabIndex]?.title ?? "")
            : ""

    onDisplayedTabIndexChanged: {
        if (!root.verticalDotNavigation || noteRailFlick.height <= 0)
            return
        noteRailFlick.contentY = Math.max(0, Math.min(
            noteRailFlick.contentHeight - noteRailFlick.height,
            root.displayedTabIndex * 19 - noteRailFlick.height / 2))
    }

    function _loadTabById(tabId): bool {
        if (!Notepad.ready)
            return false
        const id = String(tabId ?? "")
        const index = Notepad.indexForTabId(id)
        if (!id || index < 0)
            return false

        saveTimer.stop()
        root._loadingTab = true
        root._loadedTabId = id
        textArea.text = String(Notepad.tabs[index]?.text ?? "")
        root._loadingTab = false
        return true
    }

    function _loadActiveTab(): bool {
        return root._loadTabById(root._activeTabId())
    }

    // The TextArea.text binding to Notepad.text breaks the moment the user
    // types, so tab switches and external reloads must be reflected manually.
    // Flush the old displayed tab before adopting a newly-selected one.
    Connections {
        target: Notepad
        function onCurrentTabChanged() {
            if (root.surfaceLocalTabSelection) {
                if (!root._loadedTabId)
                    root._loadActiveTab()
                return
            }
            root.flushPendingSave()
            root._loadActiveTab()
        }
        function onTabsChanged() {
            if (!Notepad.ready)
                return

            if (root.surfaceLocalTabSelection) {
                if (!root._loadedTabId) {
                    root._loadActiveTab()
                    return
                }
                if (Notepad.indexForTabId(root._loadedTabId) < 0) {
                    // Another surface may delete this note before Notepad has
                    // finished repairing currentTab. Reconcile after the
                    // service mutation completes instead of loading a transient
                    // array index.
                    Qt.callLater(() => {
                        if (Notepad.ready
                                && Notepad.indexForTabId(root._loadedTabId) < 0)
                            root._loadActiveTab()
                    })
                    return
                }
                if (!saveTimer.running
                        && textArea.text !== root._loadedTabText())
                    root._loadTabById(root._loadedTabId)
                return
            }

            if (root._loadedTabId !== root._activeTabId()) {
                root.flushPendingSave()
                root._loadActiveTab()
                return
            }
            if (!saveTimer.running && textArea.text !== root._loadedTabText())
                root._loadActiveTab()
        }
        function onReadyChanged() {
            if (!Notepad.ready)
                return
            if (root._loadedTabId !== root._activeTabId()
                    || textArea.text !== Notepad.text)
                root._loadActiveTab()
            if (root.focus)
                root.focusEditor()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.margin
        spacing: root.compactPresentation ? 4 : 6

        // Header with title and stats. Dashboard already owns the module title,
        // so compactPresentation removes this duplicate row entirely.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !root.compactPresentation

            StyledText {
                text: Translation.tr("Notepad")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: root.colText
            }

            Item { Layout.fillWidth: true }

            // Stats badge
            Rectangle {
                scale: textArea.text.length > 0 ? 1 : 0
                visible: scale > 0
                Behavior on scale {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                implicitWidth: statsRow.implicitWidth + 12
                implicitHeight: 22
                radius: 11
                color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                    : Appearance.inirEverywhere ? Appearance.inir.colLayer1
                    : Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: statsRow
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        text: root.wordCount + " " + (root.wordCount === 1 ? Translation.tr("word") : Translation.tr("words"))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        color: Appearance.angelEverywhere ? Appearance.angel.colText
                            : Appearance.inirEverywhere ? Appearance.inir.colText
                            : Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }

        // Tab bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: !root.quickCapturePresentation
                && (root.tabCount > 1 || root.tabCount === 1) // Always show outside quick capture

            Flickable {
                id: tabFlick
                visible: !root.verticalDotNavigation
                Layout.fillWidth: true
                implicitHeight: root.compactPresentation ? 24 : 28
                contentWidth: Math.max(width, tabRow.implicitWidth)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: tabRow
                    x: Math.max(0, (tabFlick.width - implicitWidth) / 2)
                    spacing: root.compactPresentation ? 3 : 4

                    Repeater {
                        model: Notepad.tabs
                        delegate: Rectangle {
                            id: tabPill
                            required property var modelData
                            required property int index
                            readonly property bool active: root.surfaceLocalTabSelection
                                ? String(modelData?.id ?? "") === root._loadedTabId
                                : index === Notepad.currentTab
                            width: tabLabel.implicitWidth
                                + ((!root.compactPresentation && tabCount > 1)
                                    ? closeBtn.width + 14 : 12)
                            height: root.compactPresentation ? 22 : 26
                            radius: height / 2
                            color: active
                                ? (Appearance.angelEverywhere ? Appearance.angel.colPrimary
                                    : Appearance.inirEverywhere ? Appearance.inir.colPrimary
                                    : Appearance.colors.colPrimary)
                                : (tabMA.containsMouse
                                    ? (Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                                        : Appearance.inirEverywhere ? Appearance.inir.colLayer1Hover
                                        : Appearance.colors.colLayer1Hover)
                                    : "transparent")
                            Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 4

                                StyledText {
                                    id: tabLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.title || `Note ${index + 1}`
                                    font.pixelSize: root.compactPresentation
                                        ? Appearance.font.pixelSize.smallest
                                        : Appearance.font.pixelSize.smaller
                                    font.weight: tabPill.active ? Font.Medium : Font.Normal
                                    color: tabPill.active
                                        ? (Appearance.angelEverywhere ? Appearance.angel.colOnPrimary
                                            : Appearance.inirEverywhere ? Appearance.inir.colOnPrimary
                                            : Appearance.colors.colOnPrimary)
                                        : root.colTextSecondary
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    width: Math.min(implicitWidth,
                                        root.compactPresentation ? 58 : 80)
                                }

                                // Close button (only when multiple tabs)
                                MaterialSymbol {
                                    id: closeBtn
                                    opacity: !root.compactPresentation && tabCount > 1 ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity {
                                        enabled: Appearance.animationsEnabled
                                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                                    }
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "close"
                                    iconSize: 12
                                    color: tabPill.active
                                        ? (Appearance.angelEverywhere ? Appearance.angel.colOnPrimary
                                            : Appearance.inirEverywhere ? Appearance.inir.colOnPrimary
                                            : Appearance.colors.colOnPrimary)
                                        : root.colTextSecondary

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        enabled: Notepad.ready
                                        onClicked: root.removeTabSafely(tabPill.index)
                                    }
                                }
                            }

                            MouseArea {
                                id: tabMA
                                anchors.fill: parent
                                enabled: Notepad.ready
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                z: -1
                                onClicked: root.switchToTab(tabPill.index)
                            }
                        }
                    }
                }
            }

            Item {
                visible: root.verticalDotNavigation
                Layout.fillWidth: true
            }

            // Full Sidebar presentation keeps Add beside the tabs. Compact
            // Quick Notes surfaces keep Add/Remove with their note indicators.
            NotepadToolButton {
                visible: !root.compactPresentation
                icon: "add"
                tooltipText: Translation.tr("New tab")
                enabled: Notepad.ready
                onClicked: root.addTabSafely()
            }
        }

        // Full toolbar remains unchanged for Sidebar; Dashboard folds these
        // actions into the tab row above.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: !root.compactPresentation

            NotepadToolButton {
                icon: "content_copy"
                tooltipText: Translation.tr("Copy all")
                enabled: textArea.text.length > 0
                onClicked: {
                    Quickshell.execDetached(["wl-copy", textArea.text])
                    copiedToast.show(Translation.tr("Copied!"))
                }
            }

            NotepadToolButton {
                icon: "content_paste"
                tooltipText: Translation.tr("Paste from clipboard")
                enabled: Notepad.ready
                onClicked: root.pasteFromClipboard()
            }

            NotepadToolButton {
                icon: "add_photo_alternate"
                tooltipText: Translation.tr("Add image")
                enabled: Notepad.ready && !root.attachmentBusy
                onClicked: imageDialog.open()
            }

            NotepadToolButton {
                icon: "select_all"
                tooltipText: Translation.tr("Select all")
                enabled: textArea.text.length > 0
                onClicked: textArea.selectAll()
            }

            NotepadToolButton {
                icon: "note_add"
                tooltipText: !root.zettelkastenIntegrationEnabled
                    ? ""
                    : Zettelkasten.ready
                        ? Translation.tr("Save as Zettelkasten quick note")
                        : Translation.tr("Configure an Obsidian vault to enable Zettelkasten")
                enabled: root.canSaveZettel
                onClicked: root.saveAsZettel()
            }

            Item { Layout.fillWidth: true }

            NotepadToolButton {
                icon: "delete"
                tooltipText: Translation.tr("Clear all")
                enabled: Notepad.ready && textArea.text.length > 0
                destructive: true
                onClicked: {
                    textArea.text = ""
                    root.flushPendingSave()
                }
            }
        }

        Item {
            id: editorStage
            Layout.fillWidth: true
            Layout.fillHeight: true

            HoverHandler {
                id: editorStageHover
            }

            RowLayout {
                anchors.fill: parent
                spacing: root.compactPresentation ? 5 : 0

                // Note indicators live outside the writing surface. This keeps
                // the editor visually clean while preserving fast note switching.
                Item {
                    id: noteRail
                    objectName: "quickNotesIndicatorGroup"
                    visible: root.verticalDotNavigation
                    Layout.preferredWidth: 24
                    Layout.fillHeight: true

                    Flickable {
                        id: noteRailFlick
                        anchors.fill: parent
                        anchors.bottomMargin: groupedNoteActions.height + 4
                        contentWidth: width
                        contentHeight: noteDotColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        Column {
                            id: noteDotColumn
                            width: noteRailFlick.width
                            spacing: 1

                            Repeater {
                                model: Notepad.tabs

                                delegate: Item {
                                    id: noteDot
                                    required property var modelData
                                    required property int index
                                    readonly property bool selected:
                                        String(modelData?.id ?? "") === root._loadedTabId
                                    width: noteDotColumn.width
                                    height: 18
                                    Accessible.name: String(modelData?.title
                                        ?? `Note ${index + 1}`)

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: noteDot.selected ? 9 : 6
                                        height: width
                                        radius: width / 2
                                        color: noteDot.selected
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colOutline
                                        opacity: noteDot.selected ? 1 : 0.65
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: Notepad.ready
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.switchToTab(noteDot.index)
                                    }

                                    StyledToolTip {
                                        text: String(noteDot.modelData?.title
                                            ?? `Note ${noteDot.index + 1}`)
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        id: groupedNoteActions
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 1
                        NotepadToolButton {
                            objectName: "quickNotesAdd"
                            icon: "add"
                            tooltipText: Translation.tr("New tab")
                            enabled: Notepad.ready
                            onClicked: root.addTabSafely()
                        }
                        NotepadToolButton {
                            objectName: "quickNotesRemove"
                            visible: root.tabCount > 1
                            icon: "close"
                            tooltipText: Translation.tr("Remove current note")
                            enabled: Notepad.ready && root.displayedTabIndex >= 0
                            onClicked: root.removeTabSafely(root.displayedTabIndex)
                        }
                    }

                    WheelHandler {
                        target: null
                        orientation: Qt.Vertical
                        acceptedDevices:
                            PointerDevice.Mouse | PointerDevice.TouchPad
                        enabled: Notepad.ready && root.verticalDotNavigation
                        onWheel: event => {
                            const result = NoteRailWheel.advance(
                                root._noteRailWheelState, {
                                    pixelDelta: event.pixelDelta,
                                    angleDelta: event.angleDelta,
                                    phase: event.phase,
                                    shifted: !!(event.modifiers & Qt.ShiftModifier),
                                    blocked: !!(event.modifiers
                                        & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                                }, Date.now())
                            root._noteRailWheelState = result.state
                            event.accepted = result.accepted
                            if (!result.step)
                                return
                            const next = root.displayedTabIndex + result.step
                            if (next >= 0 && next < root.tabCount)
                                root.switchToTab(next)
                        }
                    }
                }

                Rectangle {
                    id: editorCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.angelEverywhere
                        ? Appearance.angel.roundingNormal
                        : Appearance.rounding.normal
                    color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                        : Appearance.inirEverywhere ? Appearance.inir.colLayer0
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
                        : Appearance.colors.colLayer0
                    border.width: Appearance.angelEverywhere
                        ? Appearance.angel.cardBorderWidth
                        : Appearance.inirEverywhere ? 1
                        : (Appearance.auroraEverywhere ? 0 : 1)
                    border.color: Appearance.angelEverywhere
                        ? Appearance.angel.colCardBorder
                        : Appearance.inirEverywhere ? Appearance.inir.colBorder
                        : Appearance.colors.colLayer0Border
                    clip: true

                    Flickable {
                        id: markdownReader
                        objectName: "quickNotesMarkdownReading"
                        visible: root.markdownReading
                        anchors.fill: parent
                        anchors.margins: root.compactPresentation ? 6 : 8
                        anchors.bottomMargin: (root.compactPresentation ? 6 : 8)
                            + (imagePreview.active ? imagePreview.height + 4 : 0)
                        contentWidth: width
                        contentHeight: Math.max(height, markdownBody.implicitHeight + 12)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: root.focusEditor()
                            onWheel: wheel => wheel.accepted = false
                        }

                        Text {
                            id: markdownBody
                            objectName: "quickNotesMarkdownBody"
                            x: 4
                            y: 4
                            width: Math.max(1, markdownReader.width - 8)
                            textFormat: Text.MarkdownText
                            wrapMode: Text.Wrap
                            color: root.colText
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: textArea.text.length > 0
                                ? MarkdownNote.safeReading(textArea.text)
                                : Translation.tr("Click to edit this note")
                            // Markdown links are visual text, never an
                            // automatic external process/network action.
                            onLinkActivated: link => {}
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: root.focusEditor()
                                onWheel: wheel => wheel.accepted = false
                            }
                        }
                    }

                    ScrollView {
                        id: scrollView
                        visible: !root.markdownReading
                        anchors.fill: parent
                        anchors.margins: root.compactPresentation ? 6 : 8
                        anchors.bottomMargin: (root.compactPresentation ? 6 : 8)
                            + (imagePreview.active ? imagePreview.height + 4 : 0)
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        // Wrapped notes occupy the viewport, with no horizontal
                        // extent inferred from the text or placeholder.
                        contentWidth: availableWidth

                        TextArea {
                            id: textArea
                            objectName: "quickNotesSourceEditor"
                            enabled: Notepad.ready
                            // Qt's wrapped placeholder derives its implicit
                            // width from this width. The viewport owns sizing.
                            implicitWidth: 0
                            // Only the note owns scroll extent. The wrapped
                            // placeholder must not feed its height back into
                            // viewport width while a card is being laid out.
                            implicitHeight: contentHeight + topPadding + bottomPadding
                            width: scrollView.availableWidth
                            wrapMode: TextArea.Wrap
                            renderType: Text.NativeRendering
                            font.pixelSize: Appearance.inirEverywhere
                                ? Appearance.font.pixelSize.smaller
                                : Appearance.font.pixelSize.small
                            color: Appearance.inirEverywhere
                                ? Appearance.inir.colText
                                : Appearance.colors.colOnLayer0
                            selectionColor: Appearance.angelEverywhere
                                ? Appearance.angel.colPrimary
                                : Appearance.inirEverywhere ? Appearance.inir.colPrimary
                                : Appearance.colors.colSecondaryContainer
                            selectedTextColor: Appearance.angelEverywhere
                                ? Appearance.angel.colOnPrimary
                                : Appearance.inirEverywhere ? Appearance.inir.colOnPrimary
                                : Appearance.colors.colOnSecondaryContainer
                            property bool placeholderReady: false
                            placeholderText: placeholderReady
                                ? Translation.tr("Write your notes here...") : ""
                            placeholderTextColor: Appearance.inirEverywhere
                                ? Appearance.inir.colTextSecondary
                                : Appearance.colors.colOutline
                            Component.onCompleted: {
                                root._loadActiveTab()
                                // The style's wrapped placeholder must not
                                // measure against an unfinished layout.
                                Qt.callLater(() => {
                                    if (textArea)
                                        textArea.placeholderReady = true
                                })
                            }
                            selectByMouse: true
                            persistentSelection: true
                            activeFocusOnTab: true
                            background: null

                            onActiveFocusChanged: {
                                if (activeFocus) {
                                    root.markdownEditing = true
                                    root.editorActivated()
                                } else if (root.autoMarkdownReading && root.markdownEditing) {
                                    // Defer one tick: the corner can briefly lose input
                                    // focus while its layer-shell keyboard lease upgrades.
                                    Qt.callLater(() => {
                                        if (!root.autoMarkdownReading || !root.markdownEditing
                                                || textArea.activeFocus)
                                            return
                                        root.releaseEditorFocus()
                                        root.editorDeactivated()
                                    })
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                hoverEnabled: true
                                cursorShape: Qt.IBeamCursor
                            }

                            // First-click focus catcher mirrors the desktop
                            // NotesWidget contract and disappears once focused.
                            MouseArea {
                                id: editorFocusCatcher
                                anchors.fill: parent
                                visible: Notepad.ready && !textArea.activeFocus
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.IBeamCursor
                                onPressed: mouse => {
                                    textArea.forceActiveFocus()
                                    textArea.cursorPosition = textArea.positionAt(
                                        mouse.x, mouse.y)
                                    mouse.accepted = true
                                }
                            }

                            TextInputContextMenu {
                                target: textArea
                                pasteAction: () => root.pasteFromClipboard()
                            }

                            Keys.onPressed: event => {
                                if (root.autoMarkdownReading && !root.externalEscapeHandling
                                        && event.key === Qt.Key_Escape
                                        && event.modifiers === Qt.NoModifier) {
                                    // First Escape consumes the edit and flushes the draft.
                                    // A subsequent Escape reaches the Dashboard owner.
                                    root.releaseEditorFocus()
                                    event.accepted = true
                                    return
                                }
                                if (Notepad.ready && event.modifiers === Qt.ControlModifier) {
                                    const formatKind = event.key === Qt.Key_B ? "bold"
                                        : event.key === Qt.Key_I ? "italic"
                                        : event.key === Qt.Key_U ? "underline"
                                        : event.key === Qt.Key_K ? "link" : ""
                                    if (formatKind && root.formatMarkdown(formatKind)) {
                                        event.accepted = true
                                        return
                                    }
                                }
                                // Explicit Control+Shift shortcuts apply alignment to
                                // the current paragraph or selected paragraphs.
                                if (Notepad.ready
                                        && event.modifiers === (Qt.ControlModifier | Qt.ShiftModifier)) {
                                    const alignKind = event.key === Qt.Key_L ? "align-left"
                                        : event.key === Qt.Key_E ? "align-center"
                                        : event.key === Qt.Key_R ? "align-right"
                                        : event.key === Qt.Key_J ? "align-justify" : ""
                                    if (alignKind && root.formatMarkdown(alignKind)) {
                                        event.accepted = true
                                        return
                                    }
                                }
                                if (Notepad.ready && (event.modifiers & Qt.ControlModifier)
                                        && event.key === Qt.Key_V) {
                                    root.pasteFromClipboard()
                                    event.accepted = true
                                    return
                                }
                                if (Notepad.ready
                                        && (event.modifiers & Qt.ControlModifier)
                                        && event.key === Qt.Key_S) {
                                    root.flushPendingSave()
                                    event.accepted = true
                                }
                            }

                            onTextChanged: {
                                if (root._loadingTab || !Notepad.ready)
                                    return
                                saveTimer.restart()
                            }

                            onCursorRectangleChanged: {
                                scrollView.ScrollBar.vertical.position = Math.max(
                                    0, Math.min(
                                        (cursorRectangle.y - scrollView.height / 2)
                                            / contentHeight,
                                        1 - scrollView.height / contentHeight))
                            }
                        }
                    }

                    Loader {
                        id: imagePreview
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom; anchors.margins: 6
                        height: Math.min(92, editorCard.height * .4)
                        active: root.visible && root.imageUrls.length > 0
                        visible: active
                        sourceComponent: ListView {
                            orientation: ListView.Horizontal
                            spacing: 6; clip: true; cacheBuffer: 0
                            model: root.imageUrls
                            delegate: Rectangle {
                                required property string modelData
                                width: 118; height: ListView.view.height
                                radius: Appearance.rounding.small; color: root.colCard
                                Image {
                                    objectName: "quickNoteImage"
                                    anchors.fill: parent; anchors.margins: 3
                                    source: parent.modelData
                                    sourceSize.width: 236; sourceSize.height: 184
                                    asynchronous: true; fillMode: Image.PreserveAspectFit
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["xdg-open", parent.modelData])
                                }
                            }
                        }
                    }
                }

                // Compact Quick Notes keeps only the two note-lifecycle
                // actions persistently visible. Everything else fades in on
                // hover/focus, all in the same external vertical rail.
                Item {
                    id: compactActionRail
                    visible: root.compactPresentation
                    Layout.preferredWidth: root.veryNarrowCompact ? 24 : 28
                    Layout.fillHeight: true

                    Column {
                        id: primaryNoteActions
                        visible: !root.verticalDotNavigation
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 1

                        NotepadToolButton {
                            icon: "add"
                            tooltipText: Translation.tr("New tab")
                            enabled: Notepad.ready
                            onClicked: root.addTabSafely()
                        }

                        NotepadToolButton {
                            visible: root.tabCount > 1
                            icon: "close"
                            tooltipText: Translation.tr("Remove current note")
                            enabled: Notepad.ready && root.displayedTabIndex >= 0
                            onClicked: root.removeTabSafely(root.displayedTabIndex)
                        }
                    }

                    Column {
                        id: secondaryNoteActions
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        spacing: 1
                        opacity: editorStageHover.hovered || textArea.activeFocus ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }

                        NotepadToolButton {
                            icon: "content_copy"
                            tooltipText: Translation.tr("Copy all")
                            enabled: textArea.text.length > 0
                            onClicked: {
                                Quickshell.execDetached(["wl-copy", textArea.text])
                                copiedToast.show(Translation.tr("Copied!"))
                            }
                        }

                        NotepadToolButton {
                            icon: "content_paste"
                            tooltipText: Translation.tr("Paste from clipboard")
                            enabled: Notepad.ready
                            onClicked: root.pasteFromClipboard()
                        }

                        NotepadToolButton {
                            icon: "add_photo_alternate"
                            tooltipText: Translation.tr("Add image")
                            enabled: Notepad.ready && !root.attachmentBusy
                            onClicked: imageDialog.open()
                        }

                        NotepadToolButton {
                            icon: "select_all"
                            tooltipText: Translation.tr("Select all")
                            enabled: textArea.text.length > 0
                            onClicked: textArea.selectAll()
                        }

                        NotepadToolButton {
                            icon: "delete"
                            tooltipText: Translation.tr("Clear all")
                            enabled: Notepad.ready && textArea.text.length > 0
                            destructive: true
                            onClicked: {
                                textArea.text = ""
                                root.flushPendingSave()
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 800
        repeat: false
        onTriggered: root._persistEditorText()
    }

    FileDialog {
        id: imageDialog
        title: Translation.tr("Add image")
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.tif *.tiff)"]
        fileMode: FileDialog.OpenFile
        onAccepted: root.importImage(String(selectedFile))
    }

    // One bounded receipt, retaining the note ID across tab switches/deletion.
    Process {
        id: clipboardProc
        property string noteId: ""
        property int cursor: 0
        property int selectionStart: 0
        property int selectionEnd: 0
        property string snapshot: ""
        property bool pending: false
        property bool startObserved: false
        running: false
        stdout: StdioCollector { id: clipboardReceipt }
        onStarted: startObserved = true
        onRunningChanged: {
            if (!running && pending && !startObserved)
                Qt.callLater(() => {
                    if (!clipboardProc || !clipboardProc.pending || clipboardProc.startObserved) return
                    clipboardProc.pending = false
                    copiedToast.show(Translation.tr("Could not paste attachment"))
                })
        }
        onExited: (code, status) => {
            try {
                const payload = JSON.parse(clipboardReceipt.text)
                if (code !== 0 || !payload.ok)
                    copiedToast.show(String(payload.error ?? "Could not paste attachment"))
                else if (!root.insertAttachmentResult(noteId, cursor, payload, selectionStart, selectionEnd, snapshot))
                    copiedToast.show(Translation.tr("Note no longer exists"))
            } catch (error) {
                copiedToast.show(Translation.tr("Could not paste attachment"))
            } finally {
                clipboardProc.pending = false
            }
        }
    }

    // Copied toast notification
    Connections {
        target: root.zettelkastenIntegrationEnabled ? Zettelkasten : null

        function onCaptured(payload): void {
            copiedToast.show(Translation.tr("Saved to Zettelkasten"))
        }
    }

    Rectangle {
        id: copiedToast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        implicitWidth: toastContent.implicitWidth + 20
        implicitHeight: 32
        radius: 16
        color: root.colPrimary
        opacity: 0
        visible: opacity > 0
        property string message: Translation.tr("Copied!")

        function show(message) {
            copiedToast.message = String(message ?? Translation.tr("Copied!"))
            opacity = 1
            toastTimer.restart()
        }

        Behavior on opacity {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        RowLayout {
            id: toastContent
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: "check"
                iconSize: 14
                color: Appearance.angelEverywhere ? Appearance.angel.colOnPrimary
                    : Appearance.inirEverywhere ? Appearance.inir.colOnPrimary
                    : Appearance.colors.colOnPrimary
            }

            StyledText {
                text: copiedToast.message
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.angelEverywhere ? Appearance.angel.colOnPrimary
                    : Appearance.inirEverywhere ? Appearance.inir.colOnPrimary
                    : Appearance.colors.colOnPrimary
            }
        }

        Timer {
            id: toastTimer
            interval: 1500
            onTriggered: copiedToast.opacity = 0
        }
    }

    // Toolbar button component
    component NotepadToolButton: Item {
        id: toolBtn
        required property string icon
        property string tooltipText: ""
        property bool destructive: false

        signal clicked()

        implicitWidth: root.compactPresentation ? 24 : 32
        implicitHeight: root.compactPresentation ? 24 : 28

        opacity: enabled ? 1 : 0.4

        Rectangle {
            anchors.fill: parent
            radius: Appearance.angelEverywhere ? Appearance.angel.roundingSmall
                : Appearance.inirEverywhere ? Appearance.inir.roundingSmall : Appearance.rounding.small
            color: {
                if (!toolBtn.enabled) return "transparent"
                if (toolBtnMA.containsPress)
                    return toolBtn.destructive
                        ? ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                        : (Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
                         : Appearance.inirEverywhere ? Appearance.inir.colLayer1Active
                         : Appearance.colors.colLayer1Active)
                if (toolBtnMA.containsMouse)
                    return toolBtn.destructive
                        ? ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                        : (Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
                         : Appearance.inirEverywhere ? Appearance.inir.colLayer1Hover
                         : Appearance.colors.colLayer1Hover)
                return "transparent"
            }
            Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

            MaterialSymbol {
                anchors.centerIn: parent
                text: toolBtn.icon
                iconSize: root.compactPresentation ? 15 : 18
                color: toolBtn.destructive && toolBtn.enabled
                    ? Appearance.colors.colError
                    : root.colTextSecondary
            }

            MouseArea {
                id: toolBtnMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: toolBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (toolBtn.enabled) toolBtn.clicked()
            }

            StyledToolTip {
                visible: toolBtnMA.containsMouse && toolBtn.tooltipText !== ""
                text: toolBtn.tooltipText
            }
        }
    }
}
