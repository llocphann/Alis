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
    readonly property bool busy: prepareProcess.running || cleanupProcess.running
        || githubSecretProcess.running || githubStatusProcess.running

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

    onVisibleChanged: if (visible) Qt.callLater(root.refreshGithubStatus)
    Component.onCompleted: Qt.callLater(root.refreshGithubStatus)

    function activateSettingsSearchSection(section: string): bool {
        return true
    }

    function refreshTaskStatus(): void {
        if (!root.visible || !root.selectedTask || taskStatusProcess.running)
            return
        taskStatusProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "status", root.selectedTask.code, "--repo", root.selectedTask.repository]
        taskStatusProcess.running = true
    }

    function prepareTask(): void {
        if (root.busy)
            return
        const code = taskCodeField.text.trim()
        if (!/^(?:[A-Z][A-Z0-9]{1,15}-(?:F|R|I)[0-9]{2,3}|llocphann\/[A-Za-z0-9-]+#[1-9][0-9]*)$/.test(code)) {
            root.errorText = Translation.tr("Enter a task code such as AUTO-R01.")
            return
        }
        root.errorText = ""
        root.statusText = ""
        root.selectedTask = null
        root.taskSnapshot = null
        prepareProcess.command = [
            "python3", Quickshell.shellPath("scripts/alis-automation-task.py"),
            "prepare", code
        ]
        prepareProcess.running = true
    }

    Process {
        id: prepareProcess
        stdout: StdioCollector { id: commandOutput }
        stderr: StdioCollector { id: commandError }
        onExited: exitCode => {
            try {
                const response = JSON.parse(commandOutput.text)
                if (exitCode !== 0 || response.ok !== true)
                    throw new Error(response.error || "Task preparation failed")
                root.selectedTask = response.task
                Qt.callLater(root.refreshTaskStatus)
                // Prepared is not dispatched. AUTO-F01 restores the scheduler.
                root.statusText = response.duplicate
                    ? Translation.tr("This task is already prepared.")
                    : Translation.tr("Task prepared locally.")
            } catch (error) {
                root.errorText = String(error)
                root.selectedTask = null
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
        onTriggered: root.refreshTaskStatus()
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
        description: Translation.tr("Prepare a Cloudbot task from its GitHub Issue code.")
        currentValue: "tasks"
        options: [
            { displayName: Translation.tr("Tasks"), icon: "task_alt", value: "tasks" }
        ]
    }

    SettingsCardSection {
        expanded: true
        icon: "tag"
        title: Translation.tr("GitHub task")
        settingsTaskSection: "tasks"

        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Enter the task code. Cloudbot will generate the prompts and local test handoff; no manual prompt templates are needed.")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialTextField {
                    id: taskCodeField
                    objectName: "automationTaskCode"
                    Layout.fillWidth: true
                    placeholderText: "AUTO-R01"
                    onAccepted: root.prepareTask()
                }
                DialogButton {
                    objectName: "automationPrepareTask"
                    buttonText: root.busy ? Translation.tr("Preparing…") : Translation.tr("Prepare")
                    enabled: !root.busy && taskCodeField.text.trim().length > 0
                    onClicked: root.prepareTask()
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
                visible: !!root.selectedTask
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnSurface
                text: root.selectedTask
                    ? root.selectedTask.code + " · " + root.selectedTask.repository
                        + "\n" + root.selectedTask.branch + " @ "
                        + root.selectedTask.base_sha.slice(0, 12)
                        + "\n" + root.selectedTask.issue_url
                    : ""
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "info"
        title: Translation.tr("Execution status")
        settingsTaskSection: "tasks"
        SettingsGroup {
            SettingsNote {
                icon: "hourglass_empty"
                warning: true
                text: Translation.tr("Cloudbot/Localbot dispatch is not connected yet. Prepared tasks will not run until the Automation backend is restored and explicitly enabled.")
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Local tests require explicit approval. GitHub Issues remain open for owner verification.")
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
            SettingsNote {
                visible: !!root.taskSnapshot && root.taskSnapshot.rotation_pending
                warning: true
                icon: "autorenew"
                text: Translation.tr("Chat rollover is pending server confirmation; no prompt will be resent blindly.")
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "cleaning_services"
        title: Translation.tr("Automatic housekeeping")
        settingsTaskSection: "tasks"
        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Reports are capped per task. Acknowledged completed tasks lose temporary prompts and scripts after 7 days, and the task file after 30 days. Pending or uncertain jobs are protected.")
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
                text: Translation.tr("Safe cleanup also runs when a new task is prepared. Periodic cleanup requires the restored Automation scheduler.")
            }
        }
    }
    SettingsCardSection {
        expanded: true
        icon: "key"
        title: Translation.tr("GitHub credential")
        settingsTaskSection: "tasks"
        SettingsGroup {
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Optional token for Localbot Git operations. Stored in the system keyring; never inserted into Cloudbot prompts, command arguments or task files.")
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
        title: Translation.tr("Automatic chat rollover")
        settingsTaskSection: "tasks"
        SettingsGroup {
            SettingsNote {
                icon: "info"
                text: Translation.tr("No manual prompt/iteration thresholds. Cloudbot checkpoints are preserved; confirmed context or conversation limits will trigger a new managed chat when the authenticated Desktop bridge is restored.")
            }
        }
    }

}
