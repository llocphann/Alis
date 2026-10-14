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
    readonly property bool busy: prepareProcess.running

    function activateSettingsSearchSection(section: string): bool {
        return true
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
        }
    }
}
