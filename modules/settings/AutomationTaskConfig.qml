pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: root
    settingsPageIndex: 35
    settingsPageName: Translation.tr("Automation")

    property string activeSection: "tasks"
    property bool cloudSelectTasks: false
    property var queueSnapshot: null
    property bool backendInstalled: false
    property var backendServices: ({})
    property string backendStatusText: ""
    property var activitySnapshot: null
    property string historyError: ""
    readonly property string activityText: {
        const data = root.activitySnapshot?.events ?? []
        return data.map(x => new Date(x.at_unix * 1000).toLocaleString()
            + "  " + x.kind + (x.detail ? " · " + x.detail : "")).join("\n") || Translation.tr("No activity")
    }
    readonly property string diagnosticText: {
        const data = root.activitySnapshot?.logs ?? []
        return data.map(x => new Date(x.at_unix * 1000).toLocaleString()
            + "  " + x.kind + ": " + x.text).join("\n\n") || Translation.tr("No logs")
    }

    property string errorText: ""
    property string statusText: ""
    property var selectedTask: null
    property var taskSnapshot: null
    property string cleanupResult: ""
    property string selectedGithubRepo: "llocphann/Alis"
    property bool githubTokenSaved: false
    property bool githubKeyringAvailable: false
    property string githubStatusText: ""
    property string pendingSecretInput: ""
    property string pendingSecretOperation: ""
    readonly property bool busy: queueProcess.running || cleanupProcess.running
        || githubSecretProcess.running || githubStatusProcess.running
        || installerProcess.running || backendStatusProcess.running
        || ownerActionProcess.running

    function refreshGithubStatus(): void {
        if (githubStatusProcess.running || githubSecretProcess.running)
            return
        githubStatusProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "github-token-status", root.selectedGithubRepo]
        githubStatusProcess.running = true
    }

    function saveGithubToken(): void {
        if (root.busy || !githubToken.text.length)
            return
        root.pendingSecretInput = githubToken.text
        githubToken.clear()
        root.githubStatusText = ""
        root.pendingSecretOperation = "save"
        githubSecretProcess.stdinEnabled = true
        githubSecretProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "github-token-save", root.selectedGithubRepo]
        githubSecretProcess.running = true
    }

    function clearGithubToken(): void {
        if (root.busy || !root.githubTokenSaved)
            return
        root.pendingSecretOperation = "clear"
        root.pendingSecretInput = ""
        githubSecretProcess.stdinEnabled = false
        githubSecretProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "github-token-clear", root.selectedGithubRepo]
        githubSecretProcess.running = true
    }

    onVisibleChanged: if (visible) {
        Qt.callLater(root.refreshGithubStatus)
        Qt.callLater(root.refreshQueue)
        Qt.callLater(root.refreshBackendStatus)
    }
    Component.onCompleted: {
        Qt.callLater(root.refreshGithubStatus)
        Qt.callLater(root.refreshQueue)
        Qt.callLater(root.refreshBackendStatus)
    }

    function activateSettingsSearchSection(section: string): bool {
        const name = String(section ?? "").toLowerCase()
        root.activeSection = name.includes("log") || name.includes("diagnos") ? "logs"
            : name.includes("activ") || name.includes("histor") ? "activity" : "tasks"
        Qt.callLater(root.refreshActivity)
        return true
    }

    function refreshBackendStatus(): void {
        if (backendStatusProcess.running || installerProcess.running)
            return
        backendStatusProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"), "backend-status"]
        backendStatusProcess.running = true
    }

    function installBackend(): void {
        if (root.busy || root.backendInstalled)
            return
        root.backendStatusText = ""
        installerProcess.command = ["python3",
            Quickshell.shellPath("scripts/install-hadalis-automation.py")]
        installerProcess.running = true
    }

    function refreshQueue(): void {
        if (queueProcess.running)
            return
        queueOperation = "status"
        queueProcess.command = ["python3", Quickshell.shellPath("scripts/alis-automation-task.py"), "queue-status"]
        queueProcess.running = true
    }

    function refreshActivity(): void {
        if (!root.visible || !root.selectedTask || activityProcess.running)
            return
        activityProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "activity", root.selectedTask.code, "--repo", root.selectedTask.repository]
        activityProcess.running = true
    }

    function copyHistory(): void {
        Quickshell.clipboardText = root.activeSection === "logs" ? root.diagnosticText : root.activityText
    }

    property string queueOperation: ""
    onActiveSectionChanged: Qt.callLater(root.refreshActivity)

    function verifySelectedTask(): void {
        if (root.busy || !root.selectedTask
                || root.taskSnapshot?.status !== "awaiting_owner")
            return
        ownerActionProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "owner-verify", root.selectedTask.code, "--repo",
            root.selectedTask.repository, "--approve"]
        ownerActionProcess.running = true
    }

    function refreshTaskStatus(): void {
        if (!root.visible || !root.selectedTask || taskStatusProcess.running)
            return
        taskStatusProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "status", root.selectedTask.code, "--repo", root.selectedTask.repository]
        taskStatusProcess.running = true
    }

    function startQueue(): void {
        if (root.busy || !root.queueSnapshot)
            return
        root.queueOperation = "start"
        root.errorText = ""
        queueProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "start-queue", "--approve"]
        queueProcess.running = true
    }

    function prepareTask(): void {
        if (root.busy)
            return
        const codes = taskCodeField.text.trim()
        const entries = codes.split(";").map(s => s.trim())
        if (!entries.length || entries.length > 20 ||
                entries.some(s => !/^(?:[A-Z][A-Z0-9]{1,15}-(?:F|R|I)[0-9]{2,3}|llocphann\/[A-Za-z0-9-]+#[1-9][0-9]*)$/.test(s))) {
            root.errorText = Translation.tr("Enter task codes separated by ;")
            return
        }
        root.errorText = ""
        root.statusText = ""
        root.selectedTask = null
        root.taskSnapshot = null
        root.activitySnapshot = null
        root.queueOperation = "prepare"
        queueProcess.command = [
            "python3", Quickshell.shellPath("scripts/alis-automation-task.py"),
            "queue-prepare", codes, "--mode", root.cloudSelectTasks ? "cloud" : "ordered"
        ]
        queueProcess.running = true
    }

    Process {
        id: backendStatusProcess
        stdout: StdioCollector { id: backendStatusOutput }
        stderr: StdioCollector { id: backendStatusError }
        onExited: exitCode => {
            try {
                const report = JSON.parse(backendStatusOutput.text)
                if (exitCode !== 0 || report.ok !== true)
                    throw new Error(report.error || "Service status unavailable")
                root.backendInstalled = report.installed === true
                root.backendServices = report.services
            } catch (error) {
                root.backendInstalled = false
                root.backendStatusText = Translation.tr("Backend status unavailable")
            }
        }
    }

    Process {
        id: installerProcess
        stdout: StdioCollector { id: installerOutput }
        stderr: StdioCollector { id: installerError }
        onExited: exitCode => {
            root.backendStatusText = exitCode === 0
                ? Translation.tr("Backend installed · services not auto-started")
                : Translation.tr("Install failed · check local system logs")
            Qt.callLater(root.refreshBackendStatus)
        }
    }

    Process {
        id: queueProcess
        stdout: StdioCollector { id: queueOutput }
        stderr: StdioCollector { id: queueError }
        onExited: exitCode => {
            try {
                const result = JSON.parse(queueOutput.text)
                if (exitCode !== 0 || result.ok !== true)
                    throw new Error(result.error || "Queue unavailable")
                if (result.items) {
                    root.queueSnapshot = result
                    if (root.queueOperation === "status")
                        root.cloudSelectTasks = result.mode === "cloud"
                }
                if (result.items && result.items.length) {
                    const first = result.items[0]
                    if (!root.selectedTask || !result.items.some(t =>
                            t.code === root.selectedTask.code && t.repository === root.selectedTask.repository))
                        root.selectedTask = first
                    Qt.callLater(root.refreshTaskStatus)
                    Qt.callLater(root.refreshActivity)
                }
                if (root.queueOperation === "prepare")
                    root.statusText = result.duplicate
                        ? Translation.tr("Queue already prepared")
                        : Translation.tr("Queue prepared")
                else if (root.queueOperation === "start") {
                    root.statusText = Translation.tr("Cloudbot launch requested")
                    Qt.callLater(root.refreshQueue)
                }
            } catch (error) {
                root.errorText = String(error)
            }
            root.queueOperation = ""
        }
    }

    Process {
        id: activityProcess
        stdout: StdioCollector { id: activityOutput }
        stderr: StdioCollector { id: activityError }
        onExited: exitCode => {
            try {
                const result = JSON.parse(activityOutput.text)
                if (exitCode !== 0 || result.ok !== true)
                    throw new Error(result.error || "History unavailable")
                if (root.selectedTask && result.code === root.selectedTask.code
                        && result.repository === root.selectedTask.repository) {
                    root.activitySnapshot = result
                    root.historyError = ""
                }
            } catch (error) {
                root.historyError = String(error)
            }
        }
    }


    Process {
        id: ownerActionProcess
        stdout: StdioCollector { id: ownerActionOutput }
        stderr: StdioCollector { id: ownerActionError }
        onExited: exitCode => {
            try {
                const reply = JSON.parse(ownerActionOutput.text)
                if (exitCode !== 0 || reply.ok !== true)
                    throw new Error(reply.error || "Owner approval failed")
                root.statusText = Translation.tr("Owner verified · Issue remains open")
                Qt.callLater(root.refreshTaskStatus)
                Qt.callLater(root.refreshActivity)
                Qt.callLater(root.refreshQueue)
            } catch (error) {
                root.errorText = String(error)
            }
        }
    }

    Process {
        id: taskStatusProcess
        stdout: StdioCollector { id: taskStatusOutput }
        stderr: StdioCollector { id: taskStatusError }
        onExited: exitCode => {
            try {
                const reply = JSON.parse(taskStatusOutput.text)
                if (exitCode !== 0 || reply.ok !== true)
                    throw new Error(reply.error || "Task status unavailable")
                if (root.selectedTask && root.selectedTask.code === reply.code
                        && root.selectedTask.repository === reply.repository)
                    root.taskSnapshot = reply
            } catch (error) {
                root.statusText = Translation.tr("Task status unavailable: %1").arg(String(error))
            }
        }
    }

    Timer {
        interval: 8000
        repeat: true
        running: root.visible && !!root.selectedTask
        onTriggered: {
            root.refreshTaskStatus()
            root.refreshQueue()
            if (root.activeSection !== "tasks") root.refreshActivity()
        }
    }

    Process {
        id: cleanupProcess
        stdout: StdioCollector { id: cleanupOutput }
        stderr: StdioCollector { id: cleanupError }
        onExited: exitCode => {
            try {
                const result = JSON.parse(cleanupOutput.text)
                if (exitCode !== 0 || result.ok !== true)
                    throw new Error(result.error || "Cleanup failed")
                root.cleanupResult = Translation.tr("Old payloads: %1 · receipts: %2 · task files: %3")
                    .arg(result.retired_payloads).arg(result.compacted_receipts)
                    .arg(result.deleted_task_files)
            } catch (error) {
                root.cleanupResult = Translation.tr("Cleanup unavailable: %1").arg(String(error))
            }
        }
    }

    function inspectCleanup(apply: bool): void {
        if (root.busy)
            return
        root.cleanupResult = ""
        cleanupProcess.command = ["python3", Quickshell.shellPath("scripts/alis-automation-task.py"), "cleanup"]
        if (apply)
            cleanupProcess.command = cleanupProcess.command.concat(["--apply"])
        cleanupProcess.running = true
    }

    Process {
        id: githubStatusProcess
        stdout: StdioCollector { id: githubStatusOutput }
        stderr: StdioCollector { id: githubStatusError }
        onExited: exitCode => {
            try {
                const result = JSON.parse(githubStatusOutput.text)
                if (exitCode !== 0 || result.ok !== true)
                    throw new Error(result.error || "Credential status unavailable")
                if (result.repository !== root.selectedGithubRepo)
                    return
                root.githubKeyringAvailable = result.keyring_available === true
                root.githubTokenSaved = result.saved === true
            } catch (error) {
                root.githubStatusText = Translation.tr("GitHub keyring unavailable: %1").arg(String(error))
            }
        }
    }

    Process {
        id: githubSecretProcess
        stdout: StdioCollector { id: githubSecretOutput }
        stderr: StdioCollector { id: githubSecretError }
        onStarted: {
            if (root.pendingSecretOperation === "save") {
                githubSecretProcess.write(root.pendingSecretInput)
                root.pendingSecretInput = ""
                githubSecretProcess.stdinEnabled = false
            }
        }
        onExited: exitCode => {
            root.pendingSecretInput = ""
            try {
                const result = JSON.parse(githubSecretOutput.text)
                if (exitCode !== 0 || result.ok !== true)
                    throw new Error(result.error || "Keyring operation failed")
                root.githubTokenSaved = result.saved === true
                root.githubStatusText = result.saved
                    ? Translation.tr("GitHub token saved in system keyring.")
                    : Translation.tr("GitHub token removed from system keyring.")
            } catch (error) {
                root.githubStatusText = Translation.tr("GitHub token operation failed: %1").arg(String(error))
            }
            root.pendingSecretOperation = ""
            Qt.callLater(root.refreshGithubStatus)
        }
    }

    SettingsTaskNavigator {
        icon: "smart_toy"
        title: Translation.tr("Automation")
        description: Translation.tr("GitHub tasks · Cloudbot · Localbot")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("Tasks"), icon: "task_alt", value: "tasks" },
            { displayName: Translation.tr("Activity"), icon: "history", value: "activity" },
            { displayName: Translation.tr("Logs"), icon: "monitor_heart", value: "logs" }
        ]
    }

    SettingsCardSection {
        expanded: true
        icon: "dns"
        title: Translation.tr("Backend")
        settingsTaskSection: "tasks"
        visible: root.activeSection === "tasks"
        SettingsGroup {
            SettingsNote {
                icon: root.backendInstalled ? "check_circle" : "warning"
                warning: !root.backendInstalled
                text: root.backendInstalled
                    ? Translation.tr("Installed · start a queue when ready")
                    : Translation.tr("Backend not installed")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                DialogButton {
                    buttonText: Translation.tr("Check status")
                    enabled: !root.busy
                    onClicked: root.refreshBackendStatus()
                }
                DialogButton {
                    buttonText: Translation.tr("Install backend")
                    enabled: !root.busy && !root.backendInstalled
                    onClicked: root.installBackend()
                }
            }
            StyledText {
                visible: root.backendStatusText.length > 0
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                text: root.backendStatusText
                wrapMode: Text.WordWrap
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "tag"
        title: Translation.tr("GitHub tasks")
        settingsTaskSection: "tasks"
        visible: root.activeSection === "tasks"

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Task codes separated by ;")
            }
            SettingsSwitch {
                objectName: "automationCloudSelectToggle"
                text: Translation.tr("Cloudbot chooses task order")
                buttonIcon: "smart_toy"
                checked: root.cloudSelectTasks
                autoToggle: false
                onToggledByUser: checked => root.cloudSelectTasks = checked
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialTextField {
                    id: taskCodeField
                    objectName: "automationTaskCode"
                    Layout.fillWidth: true
                    placeholderText: "AUTO-R01; ABYSS-R09; BRAND-F01"
                    onAccepted: root.prepareTask()
                }
                DialogButton {
                    objectName: "automationPrepareTask"
                    buttonText: root.busy ? Translation.tr("Preparing…") : Translation.tr("Queue tasks")
                    enabled: !root.busy && taskCodeField.text.trim().length > 0
                    onClicked: root.prepareTask()
                }
                DialogButton {
                    objectName: "automationStartQueue"
                    buttonText: Translation.tr("Start")
                    enabled: !root.busy && root.backendInstalled && !!root.queueSnapshot
                        && ["prepared", "waiting"].includes(root.queueSnapshot.state)
                        && ["ordered", "cloud"].includes(root.queueSnapshot.mode)
                    onClicked: root.startQueue()
                }
            }
            StyledText {
                visible: root.errorText.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colError
                text: root.errorText
            }
            StyledText {
                visible: root.statusText.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colPrimary
                text: root.statusText
            }
            StyledText {
                visible: !!root.queueSnapshot && root.queueSnapshot.items.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnSurface
                text: root.queueSnapshot
                    ? root.queueSnapshot.items.map((task, i) =>
                        (i + 1) + ". " + task.code + " · " + task.state).join("\n")
                    : ""
            }
            StyledText {
                visible: !!root.queueSnapshot && !!root.queueSnapshot.cloud_selection_required
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Cloudbot will select the next task")
            }
            ConfigSelectionArray {
                visible: !!root.queueSnapshot && root.queueSnapshot.items.length > 0
                currentValue: root.selectedTask
                    ? root.selectedTask.repository + ":" + root.selectedTask.code : ""
                options: root.queueSnapshot
                    ? root.queueSnapshot.items.map(t => ({
                        displayName: t.code + " · " + t.state,
                        value: t.repository + ":" + t.code
                    })) : []
                onSelected: value => {
                    const entry = root.queueSnapshot.items.find(t =>
                        t.repository + ":" + t.code === value)
                    if (entry) {
                        root.selectedTask = entry
                        root.taskSnapshot = null
                        root.activitySnapshot = null
                        Qt.callLater(root.refreshTaskStatus)
                        Qt.callLater(root.refreshActivity)
                    }
                }
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "info"
        title: Translation.tr("Status")
        settingsTaskSection: "tasks"
        visible: root.activeSection === "tasks"
        SettingsGroup {
            SettingsNote {
                icon: "hourglass_empty"
                warning: true
                text: !root.backendInstalled
                    ? Translation.tr("Backend unavailable · install first")
                    : root.queueSnapshot?.state === "active"
                    ? Translation.tr("Cloudbot running · Localbot receipts required")
                    : root.queueSnapshot?.state === "finished"
                    ? Translation.tr("Queue finished · owner review may remain")
                    : Translation.tr("Ready · Start a prepared queue")
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Local tests need approval · Owner verifies")
            }
            StyledText {
                visible: !!root.taskSnapshot
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnSurface
                text: root.taskSnapshot
                    ? Translation.tr("Task: %1 · local job: %2 · chat rollover: %3")
                        .arg(root.taskSnapshot.status)
                        .arg(root.taskSnapshot.current_job || "—")
                        .arg(root.taskSnapshot.rotation_pending ? "Pending" : "Idle")
                    : ""
            }
            DialogButton {
                buttonText: Translation.tr("Mark owner verified")
                enabled: !root.busy && !!root.taskSnapshot
                    && root.taskSnapshot.status === "awaiting_owner"
                visible: !!root.taskSnapshot && root.taskSnapshot.status === "awaiting_owner"
                onClicked: root.verifySelectedTask()
            }
            SettingsNote {
                visible: !!root.taskSnapshot && root.taskSnapshot.rotation_pending
                warning: true
                icon: "autorenew"
                text: Translation.tr("Chat rollover · awaiting confirmation")
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "cleaning_services"
        title: Translation.tr("Cleanup")
        settingsTaskSection: "tasks"
        visible: root.activeSection === "tasks"
        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Old prompts: 7 days · task files: 30 days")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                DialogButton {
                    buttonText: Translation.tr("Preview cleanup")
                    enabled: !root.busy
                    onClicked: root.inspectCleanup(false)
                }
                DialogButton {
                    buttonText: Translation.tr("Clean now")
                    enabled: !root.busy
                    onClicked: root.inspectCleanup(true)
                }
            }
            StyledText {
                visible: root.cleanupResult.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: root.cleanupResult
            }
            SettingsNote {
                icon: "info"
                text: Translation.tr("Pending tasks are protected")
            }
        }
    }
    SettingsCardSection {
        expanded: true
        icon: "key"
        title: Translation.tr("GitHub token")
        settingsTaskSection: "tasks"
        visible: root.activeSection === "tasks"
        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Saved privately in system keyring")
            }
            ConfigSelectionArray {
                currentValue: root.selectedGithubRepo
                options: [
                    { displayName: "Alis", value: "llocphann/Alis" },
                    { displayName: "Alis-Companion", value: "llocphann/Alis-Companion" },
                    { displayName: "Alis-Intergration", value: "llocphann/Alis-Intergration" }
                ]
                onSelected: value => {
                    if (root.busy) return
                    githubToken.clear()
                    root.selectedGithubRepo = value
                    root.githubTokenSaved = false
                    root.githubStatusText = ""
                    Qt.callLater(root.refreshGithubStatus)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialTextField {
                    id: githubToken
                    objectName: "automationGithubToken"
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("GitHub personal access token")
                    echoMode: TextInput.Password
                    onAccepted: root.saveGithubToken()
                }
                DialogButton {
                    buttonText: Translation.tr("Save token")
                    enabled: !root.busy && root.githubKeyringAvailable && githubToken.text.length > 0
                    onClicked: root.saveGithubToken()
                }
                DialogButton {
                    buttonText: Translation.tr("Clear")
                    enabled: !root.busy && root.githubTokenSaved
                    onClicked: root.clearGithubToken()
                }
            }
            SettingsNote {
                icon: root.githubTokenSaved ? "lock" : "key"
                text: !root.githubKeyringAvailable
                    ? Translation.tr("System keyring unavailable. Install and unlock Secret Service.")
                    : root.githubTokenSaved
                    ? Translation.tr("Saved for the selected repository · local Git only")
                    : Translation.tr("No GitHub token saved for this repository")
            }
            StyledText {
                visible: root.githubStatusText.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: root.githubStatusText
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "autorenew"
        title: Translation.tr("Chat rollover")
        settingsTaskSection: "tasks"
        visible: root.activeSection === "tasks"
        SettingsGroup {
            SettingsNote {
                icon: "info"
                text: Translation.tr("Auto-detect chat limits · keep checkpoint")
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "history"
        title: Translation.tr("Recent activity")
        settingsTaskSection: "activity"
        visible: root.activeSection === "activity"
        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                DialogButton {
                    buttonText: Translation.tr("Refresh")
                    enabled: !activityProcess.running
                    onClicked: root.refreshActivity()
                }
                DialogButton {
                    buttonText: Translation.tr("Copy")
                    enabled: !!root.activitySnapshot
                    onClicked: root.copyHistory()
                }
            }
            StyledText {
                visible: root.historyError.length > 0
                Layout.fillWidth: true
                color: Appearance.colors.colError
                text: root.historyError
                wrapMode: Text.WordWrap
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 240
                TextArea {
                    id: automationActivityLog
                    objectName: "automationActivityLog"
                    text: root.activityText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "monitor_heart"
        title: Translation.tr("Diagnostics")
        settingsTaskSection: "logs"
        visible: root.activeSection === "logs"
        SettingsGroup {
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                DialogButton {
                    buttonText: Translation.tr("Refresh")
                    enabled: !activityProcess.running
                    onClicked: root.refreshActivity()
                }
                DialogButton {
                    buttonText: Translation.tr("Copy")
                    enabled: !!root.activitySnapshot
                    onClicked: root.copyHistory()
                }
            }
            SettingsNote {
                icon: "lock"
                text: Translation.tr("Private logs · review before sharing")
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                TextArea {
                    objectName: "automationDiagnosticLog"
                    text: root.diagnosticText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

}
