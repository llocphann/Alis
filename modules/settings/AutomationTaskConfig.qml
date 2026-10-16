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
    property bool clearQueueConfirmation: false
    property bool stopQueueConfirmation: false
    property bool resetChatConfirmation: false
    property string resetChatTarget: ""
    property bool chatResetNotice: false
    property string stopQueueTarget: ""
    property string stopQueueSnapshotId: ""
    property string clearQueueTarget: ""
    property string clearQueueSnapshotId: ""
    property string pendingSudoPassword: ""
    property string sudoOperation: ""
    property string sudoStatusText: ""
    property bool sudoCredentialSaved: false
    property bool sudoKeyringAvailable: false
    property bool sudoStatusKnown: false
    property var queueSnapshot: null
    property bool queueStatusConfirmed: false
    property string queuePrepareError: ""
    property bool stopAcknowledgementPending: false
    readonly property string queueJobSummary: {
        const queue = root.queueSnapshot
        if (queueProcess.running && root.queueOperation === "status")
            return Translation.tr("Checking")
        if (!queue) return Translation.tr("Idle")
        if (root.chatResetNotice)
            return Translation.tr("Reset requested · awaiting manager")
        if (!root.queueStatusConfirmed)
            return Translation.tr("Unverified")
        const tasks = queue.items ?? []
        const current = queue.active || tasks.find(t =>
            t.state === "active" || t.state === "waiting") || null
        const currentIndex = current ? tasks.findIndex(t =>
            t.repository === current.repository && t.code === current.code) : -1
        let phase
        if (root.stopAcknowledgementPending || queue.state === "stopping")
            phase = Translation.tr("Stopping · awaiting ack")
        else if (queue.state === "active") phase = Translation.tr("Running")
        else if (queue.state === "waiting") phase = Translation.tr("Waiting")
        else if (queue.state === "prepared") phase = Translation.tr("Ready")
        else if (queue.state === "review_required")
            phase = Translation.tr("Needs review")
        else if (queue.state === "finished") phase = Translation.tr("Finished")
        else if (["stopped", "cancelled"].includes(queue.state))
            phase = Translation.tr("Stopped")
        else if (queue.state === "empty") phase = Translation.tr("Idle")
        else phase = Translation.tr("Idle")
        const details = [phase]
        if (current?.code) details.push(current.code)
        if (currentIndex >= 0 && tasks.length)
            details.push((currentIndex + 1) + "/" + tasks.length)
        else if (tasks.length) {
            const ready = tasks.filter(t => t.state === "queued").length
            const deferred = tasks.filter(t => t.state === "deferred").length
            if (ready) details.push(Translation.tr("%1 ready").arg(ready))
            if (deferred) details.push(Translation.tr("%1 parked").arg(deferred))
        }
        return details.join(" · ")
    }
    property bool backendInstalled: false
    property bool backendStatusKnown: false
    property bool backendTransportReady: false
    property bool uiQueueStartAvailable: false
    property bool uiQueueStageAvailable: false
    property string uiQueueFirstTask: ""
    property var uiQueuePreflightBlockers: []
    property string uiQueueServiceMode: ""
    property string uiQueueServiceState: ""
    property bool uiQueueStageConfirmation: false
    property string uiQueueStageTarget: ""
    property string uiQueueStageSnapshotId: ""
    property bool uiQueueStartConfirmation: false
    property string uiQueueStartTarget: ""
    property string uiQueueStartSnapshotId: ""
    property string backendTransportBlocker: ""
    property var backendServices: ({})
    property string backendStatusText: ""
    readonly property string queueStartGuidance: {
        const q = root.queueSnapshot
        if (!q || !root.queueStatusConfirmed) return ""
        if (q.state === "review_required")
            return Translation.tr("All tasks are parked. Leave the code field blank and use Recheck; Start must not replay an unresolved task.")
        if (q.state !== "prepared") return ""
        if (!(q.items || []).some(t => t.state === "queued"))
            return Translation.tr("No eligible task is queued; review saved receipts before Start.")
        if (root.uiQueueStartAvailable || root.backendTransportReady) return ""
        if (root.uiQueueStageAvailable)
            return Translation.tr("Prepare UI creates an idle task profile; after readiness refresh, confirm Start UI separately. No message is sent by Prepare.")
        const blockers = root.uiQueuePreflightBlockers || []
        if (blockers.includes("FOREIGN_PROFILE_UNSETTLED")
                || blockers.includes("NATIVE_SESSION_REQUIRES_REVIEW"))
            return Translation.tr("Start blocked: a previous profile/session or job requires evidence reconciliation. Do not reset or replay it.")
        if (root.uiQueueServiceState === "active"
                && root.uiQueueServiceMode === "native_mode")
            return Translation.tr("Start blocked: bridge is running in native mode. Native server receipts are not attested; switch to queue-only UI mode only after checking and stopping existing work.")
        if (root.uiQueueServiceState === "active"
                && root.uiQueueServiceMode === "ui_mode")
            return Translation.tr("Start blocked: bridge is running in single-profile UI mode, not queue-only UI mode. Preserve the current chat before changing mode.")
        if (root.uiQueueServiceState !== "active"
                || root.uiQueueServiceMode !== "ui_queue_mode")
            return Translation.tr("Start blocked: queue-only UI manager is not active. Configure/start that service explicitly after safe cutover.")
        if (blockers.includes("TASKFLOW_PROFILE_NOT_MATERIALIZED"))
            return Translation.tr("Start blocked: task profile staging is unavailable. Check other manager profiles and Refresh.")
        return Translation.tr("Start blocked by UI Queue preflight. Check the saved queue and backend status before retrying.")
    }
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
    property bool githubStatusKnown: false
    property string githubStatusText: ""
    property string pendingSecretInput: ""
    property string pendingSecretOperation: ""
    readonly property bool busy: queueProcess.running || cleanupProcess.running
        || sudoAuthProcess.running
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
        Qt.callLater(root.refreshSudoCredentialStatus)
        Qt.callLater(root.refreshQueue)
        Qt.callLater(root.refreshBackendStatus)
    }
    Component.onCompleted: {
        Qt.callLater(root.refreshGithubStatus)
        Qt.callLater(root.refreshSudoCredentialStatus)
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
        // A read-only refresh must not erase a user's confirmation if
        // the exact queued list is unchanged. The backend rechecks the
        // live queue atomically before any removal.
        root.queueStatusConfirmed = false
        root.uiQueueStartConfirmation = false
        root.uiQueueStartTarget = ""
        root.uiQueueStartSnapshotId = ""
        root.uiQueueStageConfirmation = false
        root.uiQueueStageTarget = ""
        root.uiQueueStageSnapshotId = ""
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

    function stageUiQueue(): void {
        if (root.busy || !root.queueStatusConfirmed || !root.uiQueueStageAvailable
                || !root.queueSnapshot || root.queueSnapshot.state !== "prepared"
                || root.queueSnapshot.mode !== "ordered")
            return
        const first = root.queueSnapshot.items.find(item => item.state === "queued")
        const identity = first ? first.repository + ":" + first.code : ""
        const snapshotId = root.queueSnapshot.snapshot_id || ""
        if (!first || first.code !== root.uiQueueFirstTask
                || !/^[a-f0-9]{64}$/.test(snapshotId)) {
            root.errorText = Translation.tr("Queue identity changed · Refresh before Prepare UI")
            return
        }
        if (!root.uiQueueStageConfirmation) {
            root.uiQueueStageConfirmation = true
            root.uiQueueStageTarget = identity
            root.uiQueueStageSnapshotId = snapshotId
            root.statusText = Translation.tr(
                "Confirm Prepare UI: create an idle profile for %1. No task, ChatGPT send, service restart or queue Start occurs."
            ).arg(first.code)
            return
        }
        if (root.uiQueueStageTarget !== identity
                || root.uiQueueStageSnapshotId !== snapshotId) {
            root.uiQueueStageConfirmation = false
            root.uiQueueStageTarget = ""
            root.uiQueueStageSnapshotId = ""
            root.errorText = Translation.tr("Queue changed · Refresh before Prepare UI")
            return
        }
        root.uiQueueStageConfirmation = false
        root.uiQueueStageTarget = ""
        root.uiQueueStageSnapshotId = ""
        root.uiQueueStageAvailable = false
        root.queueOperation = "stage-ui"
        root.errorText = ""
        queueProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "queue-stage-ui", "--approve", "--expected-first", identity,
            "--expected-snapshot-id", snapshotId]
        queueProcess.running = true
    }

    function startQueue(): void {
        if (root.busy || !root.queueSnapshot || !root.queueStatusConfirmed)
            return
        const first = root.queueSnapshot.items.find(item => item.state === "queued")
        const identity = first ? first.repository + ":" + first.code : ""
        const snapshotId = root.queueSnapshot.snapshot_id || ""
        const uiReady = root.backendInstalled && root.uiQueueStartAvailable
            && root.queueSnapshot.mode === "ordered"
            && root.queueSnapshot.state === "prepared"
            && first && first.code === root.uiQueueFirstTask
        if (!root.backendTransportReady && !uiReady)
            return
        root.clearQueueConfirmation = false
        root.errorText = ""
        if (uiReady) {
            if (!/^[a-f0-9]{64}$/.test(snapshotId)) {
                root.errorText = Translation.tr("Queue identity unavailable · update Automation backend and refresh")
                return
            }
            if (!root.uiQueueStartConfirmation) {
                root.uiQueueStartConfirmation = true
                root.uiQueueStartTarget = identity
                root.uiQueueStartSnapshotId = snapshotId
                root.statusText = Translation.tr("Confirm UI-only Start: responses are verified locally, not by the ChatGPT server. Existing native pending records remain preserved.")
                return
            }
            if (root.uiQueueStartTarget !== identity
                    || root.uiQueueStartSnapshotId !== snapshotId) {
                root.uiQueueStartConfirmation = false
                root.uiQueueStartTarget = ""
                root.uiQueueStartSnapshotId = ""
                root.errorText = Translation.tr("Queue changed · refresh before UI Start")
                return
            }
            root.uiQueueStartConfirmation = false
            root.uiQueueStartTarget = ""
            root.uiQueueStartSnapshotId = ""
            root.queueOperation = "start"
            queueProcess.command = ["python3",
                Quickshell.shellPath("scripts/alis-automation-task.py"),
                "start-ui-queue", "--approve", "--accept-ui-only-receipts",
                "--expected-first", identity,
                "--expected-snapshot-id", snapshotId]
        } else {
            root.uiQueueStartConfirmation = false
            root.uiQueueStartTarget = ""
            root.uiQueueStartSnapshotId = ""
            root.queueOperation = "start"
            queueProcess.command = ["python3",
                Quickshell.shellPath("scripts/alis-automation-task.py"),
                "start-queue", "--approve"]
        }
        queueProcess.running = true
    }

    function prepareTask(): void {
        if (root.busy)
            return
        // The empty input is NOT permission to replace an old, fully
        // parked queue with different auto-discovered Issues. Recheck the
        // displayed original set first, preserving every original receipt.
        if (!taskCodeField.text.trim().length && root.reviewRecheckAvailable) {
            root.recheckQueue()
            return
        }
        root.clearQueueConfirmation = false
        root.uiQueueStartConfirmation = false
        root.uiQueueStartTarget = ""
        root.uiQueueStartSnapshotId = ""
        root.uiQueueStageConfirmation = false
        root.uiQueueStageTarget = ""
        root.uiQueueStageSnapshotId = ""
        const codes = taskCodeField.text.trim()
        const entries = codes.length ? codes.split(";").map(s => s.trim()) : []
        if (codes.length && (entries.length > 20 ||
                entries.some(s => !/^(?:[A-Z][A-Z0-9]{1,15}-(?:F|R|I)[0-9]{2,3}|llocphann\/[A-Za-z0-9-]+#[1-9][0-9]*)$/.test(s)))) {
            root.errorText = Translation.tr("Enter task codes separated by ;")
            return
        }
        root.errorText = ""
        root.queuePrepareError = ""
        root.statusText = ""
        root.queueStatusConfirmed = false
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

    readonly property bool reviewRecheckAvailable: !!root.queueSnapshot
        && root.queueStatusConfirmed && root.queueSnapshot.state === "review_required"
        && root.queueSnapshot.items.length > 0
        && root.queueSnapshot.items.every(task => task.state === "deferred")

    function recheckQueue(): void {
        if (root.busy || !root.reviewRecheckAvailable) return
        const snapshotId = root.queueSnapshot.snapshot_id || ""
        if (!/^[a-f0-9]{64}$/.test(snapshotId)) {
            root.errorText = Translation.tr("Queue identity unavailable · update Alis backend and refresh")
            return
        }
        root.clearQueueConfirmation = false
        root.stopQueueConfirmation = false
        root.uiQueueStartConfirmation = false
        root.errorText = ""
        root.statusText = ""
        root.queuePrepareError = ""
        root.queueStatusConfirmed = false
        root.queueOperation = "recheck"
        queueProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "queue-recheck", "--expected-snapshot-id", snapshotId]
        queueProcess.running = true
    }

    function queuedTaskIdentities(snapshot): string {
        if (!snapshot || !snapshot.items) return ""
        return snapshot.items.filter(task => task.state === "queued")
            .map(task => task.repository + ":" + task.code).join(";")
    }

    function resetActiveChat(): void {
        if (root.busy || !root.queueStatusConfirmed || !root.queueSnapshot
                || root.queueSnapshot.mode !== "ordered"
                || root.queueSnapshot.state !== "active"
                || !root.queueSnapshot.active)
            return
        const active = root.queueSnapshot.active
        const identity = active.repository + ":" + active.code
        if (!root.resetChatConfirmation) {
            root.stopQueueConfirmation = false
            root.clearQueueConfirmation = false
            root.resetChatTarget = identity
            root.resetChatConfirmation = true
            root.statusText = Translation.tr(
                "Confirm fresh chat for %1. Unsettled submissions and jobs cannot be reset."
            ).arg(active.code)
            return
        }
        if (root.resetChatTarget !== identity) {
            root.resetChatConfirmation = false
            root.resetChatTarget = ""
            root.errorText = Translation.tr("Active task changed · refresh before reset")
            return
        }
        root.resetChatConfirmation = false
        root.resetChatTarget = ""
        root.errorText = ""
        root.queueStatusConfirmed = false
        root.queueOperation = "reset-chat"
        queueProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "queue-reset-chat", "--approve", "--expected-active", identity]
        queueProcess.running = true
    }

    function stopQueue(): void {
        if (root.busy || !root.queueSnapshot) return
        const active = root.queueSnapshot.active
        const identity = active ? active.repository + ":" + active.code : ""
        const snapshotId = root.queueSnapshot.snapshot_id || ""
        if (!["active", "waiting", "stopping"].includes(root.queueSnapshot.state))
            return
        if (!/^[a-f0-9]{64}$/.test(snapshotId)) {
            root.errorText = Translation.tr("Queue identity unavailable · update Automation backend and refresh")
            return
        }
        if (!root.stopQueueConfirmation) {
            root.stopQueueTarget = identity
            root.stopQueueSnapshotId = snapshotId
            root.stopQueueConfirmation = true
            root.statusText = Translation.tr("Confirm Stop: no next task will start. In-flight jobs and receipts remain for review.")
            return
        }
        if (root.stopQueueTarget !== identity
                || root.stopQueueSnapshotId !== snapshotId) {
            root.stopQueueConfirmation = false
            root.stopQueueTarget = ""
            root.stopQueueSnapshotId = ""
            root.errorText = Translation.tr("Queue changed · refresh before Stop")
            return
        }
        root.stopQueueConfirmation = false
        root.stopQueueTarget = ""
        root.stopQueueSnapshotId = ""
        root.clearQueueConfirmation = false
        root.queueStatusConfirmed = false
        root.queueOperation = "stop"
        root.stopAcknowledgementPending = true
        root.errorText = ""
        queueProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "queue-stop", "--approve", "--expected-active", identity,
            "--expected-snapshot-id", snapshotId]
        queueProcess.running = true
    }

    function queueTag(task): string {
        if (!task) return Translation.tr("Blocked")
        const state = task.state || ""
        if (state === "verified" || state === "owner_verified"
                || (state === "deferred" && task.reason === "already_completed"))
            return Translation.tr("Verified")
        if (state === "completed" || state === "done")
            return Translation.tr("Done")
        if (state === "active" || state === "working")
            return Translation.tr("Working")
        if (state === "queued") return Translation.tr("Queue")
        if (state === "waiting") return Translation.tr("Waiting")
        if (state === "paused" || state === "stopped")
            return Translation.tr("Paused")
        if (state === "failed" || state === "cancelled")
            return Translation.tr("Blocked")
        if (state === "deferred") return root.parkedReason(task.reason)
        return Translation.tr("Needs review")
    }

    function queueTagColor(task): color {
        if (!task) return Appearance.colors.colSubtext
        if (task.state === "verified" || task.state === "owner_verified"
                || (task.state === "deferred" && task.reason === "already_completed"))
            return Appearance.colors.colPrimary
        if (task.state === "completed" || task.state === "done")
            return Appearance.colors.colOnSurface
        if (task.state === "active" || task.state === "working")
            return Appearance.colors.colPrimary
        if (task.state === "queued")
            return Appearance.colors.colSubtext
        return Appearance.colors.colError
    }

    function selectQueueTask(entry): void {
        if (!entry) return
        root.selectedTask = entry
        root.taskSnapshot = null
        root.activitySnapshot = null
        Qt.callLater(root.refreshTaskStatus)
        Qt.callLater(root.refreshActivity)
    }

    function parkedReason(reason): string {
        if (reason === "cloud_ack_pending") return Translation.tr("Ack pending")
        if (reason === "owner_review_pending") return Translation.tr("Owner review")
        if (reason === "already_completed") return Translation.tr("Completed")
        if (reason === "cloud_continuation_pending") return Translation.tr("Cloud pending")
        if (reason === "source_pin_changed") return Translation.tr("Legacy pin")
        if (reason === "source_pin_unverified") return Translation.tr("Pin unverified")
        if (reason === "saved_work_requires_review") return Translation.tr("Review record")
        if (reason === "previous_dispatch_unsettled") return Translation.tr("Job pending")
        if (reason === "previous_receipt_exists") return Translation.tr("Receipt pending")
        if (reason === "unresolved_work") return Translation.tr("Reconcile send")
        if (reason === "previous_handoff_pending") return Translation.tr("Handoff pending")
        return Translation.tr("Needs review")
    }

    function clearQueue(): void {
        // A stale display may still offer a cleanup action. This is safe:
        // the backend must match the exact on-screen queue snapshot under
        // queue.lock, and never cancels/edits the active task.
        if (root.busy || !root.queueSnapshot)
            return
        const targets = root.queuedTaskIdentities(root.queueSnapshot)
        const snapshotId = root.queueSnapshot.snapshot_id || ""
        if (!/^[a-f0-9]{64}$/.test(snapshotId)) {
            root.errorText = Translation.tr("Queue identity unavailable · update the Automation backend and refresh")
            return
        }
        if (!targets.length && !["finished", "cancelled", "stopped",
                "review_required"].includes(root.queueSnapshot.state))
            return
        if (!root.clearQueueConfirmation) {
            root.clearQueueTarget = targets
            root.clearQueueSnapshotId = snapshotId
            root.clearQueueConfirmation = true
            root.statusText = root.queueSnapshot.state === "stopped"
                ? Translation.tr("Confirm archiving stopped queue. Prior active job and receipts remain in history.")
                : Translation.tr("Confirm removal of queued tasks only. Active job and receipts stay intact.")
            return
        }
        if (root.clearQueueTarget !== targets
                || root.clearQueueSnapshotId !== snapshotId) {
            root.clearQueueConfirmation = false
            root.clearQueueTarget = ""
            root.clearQueueSnapshotId = ""
            root.errorText = Translation.tr("Queue changed · refresh and confirm again")
            return
        }
        root.clearQueueConfirmation = false
        root.clearQueueTarget = ""
        root.clearQueueSnapshotId = ""
        root.queueStatusConfirmed = false
        root.errorText = ""
        root.queueOperation = "clear"
        queueProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "queue-clear", "--approve", "--expected-queued", targets,
            "--expected-snapshot-id", snapshotId]
        queueProcess.running = true
    }

    function refreshSudoCredentialStatus(): void {
        if (sudoAuthProcess.running) return
        root.sudoOperation = "status"
        sudoAuthProcess.stdinEnabled = false
        sudoAuthProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "sudo-credential-status"]
        sudoAuthProcess.running = true
    }

    function saveSudoPassword(): void {
        if (root.busy || sudoPasswordField.text.length === 0)
            return
        root.pendingSudoPassword = sudoPasswordField.text
        sudoPasswordField.clear()
        root.sudoOperation = "save"
        sudoAuthProcess.stdinEnabled = true
        sudoAuthProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "sudo-credential-save"]
        sudoAuthProcess.running = true
    }

    function clearSudoPassword(): void {
        if (root.busy || !root.sudoCredentialSaved) return
        root.sudoOperation = "clear"
        root.pendingSudoPassword = ""
        sudoAuthProcess.stdinEnabled = false
        sudoAuthProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "sudo-credential-clear"]
        sudoAuthProcess.running = true
    }

    function checkSudoStatus(): void {
        if (root.busy) return
        root.sudoOperation = "check"
        root.sudoStatusText = ""
        sudoAuthProcess.stdinEnabled = false
        sudoAuthProcess.command = ["python3",
            Quickshell.shellPath("scripts/alis-automation-task.py"),
            "sudo-status"]
        sudoAuthProcess.running = true
    }

    // Quickshell may emit Process.exited before StdioCollector.streamFinished.
    // Never parse an empty/incomplete stdout buffer as an API response.
    property var automationCompletion: ({})

    function _automationExited(name, exitCode) {
        const entry = root.automationCompletion[name] || {}
        entry.exited = true
        entry.exitCode = exitCode
        root.automationCompletion[name] = entry
        root._finishAutomationWhenReady(name)
        ioCompletionFallback.restart()
    }

    function _automationStdoutClosed(name) {
        const entry = root.automationCompletion[name] || {}
        entry.closed = true
        root.automationCompletion[name] = entry
        root._finishAutomationWhenReady(name)
    }

    function _finishAutomationWhenReady(name) {
        const entry = root.automationCompletion[name]
        if (!entry || !entry.exited || !entry.closed)
            return
        delete root.automationCompletion[name]
        if (name === "backendStatusProcess") root._handle_backendStatusProcess(entry.exitCode)
        else if (name === "queueProcess") root._handle_queueProcess(entry.exitCode)
        else if (name === "activityProcess") root._handle_activityProcess(entry.exitCode)
        else if (name === "ownerActionProcess") root._handle_ownerActionProcess(entry.exitCode)
        else if (name === "taskStatusProcess") root._handle_taskStatusProcess(entry.exitCode)
        else if (name === "cleanupProcess") root._handle_cleanupProcess(entry.exitCode)
        else if (name === "githubStatusProcess") root._handle_githubStatusProcess(entry.exitCode)
        else if (name === "githubSecretProcess") root._handle_githubSecretProcess(entry.exitCode)
        else if (name === "sudoAuthProcess") root._handle_sudoAuthProcess(entry.exitCode)
    }

    Timer {
        id: prepareFailureRefresh
        interval: 180
        repeat: false
        onTriggered: {
            if (!queueProcess.running)
                root.refreshQueue()
        }
    }

    Timer {
        id: resetNoticeTimer
        interval: 7000
        repeat: false
        onTriggered: root.chatResetNotice = false
    }

    Timer {
        id: ioCompletionFallback
        interval: 350
        repeat: false
        onTriggered: {
            for (const name of Object.keys(root.automationCompletion)) {
                const entry = root.automationCompletion[name]
                if (entry && entry.exited && !entry.closed) {
                    // Handle empty stdout/execution failure rather than staying busy
                    // indefinitely. Real parse errors include a useful error label.
                    entry.closed = true
                    root._finishAutomationWhenReady(name)
                }
            }
        }
    }

    function readAutomationReply(action, stdoutText, stderrText, exitCode) {
        const text = String(stdoutText || "").trim()
        if (!text) {
            const error = String(stderrText || "")
            const reason = /can't open file|No such file or directory/i.test(error)
                ? "Automation script missing from shell config"
                : /ModuleNotFoundError|ImportError/i.test(error)
                ? "Automation modules missing from installed Alis; update runtime"
                : /Permission denied/i.test(error)
                ? "Automation helper permission denied"
                : "Automation helper returned no output"
            throw new Error(action + ": " + reason + " (exit " + exitCode + ")")
        }
        let response
        try {
            response = JSON.parse(text)
        } catch (error) {
            throw new Error(action + ": helper returned invalid JSON (exit " + exitCode + ")")
        }
        if (!response || response.ok !== true || exitCode !== 0)
            throw new Error(response?.error || (action + ": helper failed (exit " + exitCode + ")"))
        return response
    }

    function _handle_backendStatusProcess(exitCode) {
            try {
                const report = root.readAutomationReply("backendStatusProcess", backendStatusOutput.text, backendStatusError.text, exitCode)
                if (exitCode !== 0 || report.ok !== true)
                    throw new Error(report.error || "Service status unavailable")
                root.backendInstalled = report.installed === true
                // A loaded/running systemd service or a successful UI smoke
                // does not attest a managed ChatGPT Project delivery receipt.
                root.backendTransportReady = report.transport_ready === true
                    && report.unattended_submission_authorized === true
                root.backendTransportBlocker = typeof report.transport_blocker === "string"
                    ? report.transport_blocker : ""
                root.uiQueueStartAvailable = report.ui_queue_start_available === true
                root.uiQueueStageAvailable = report.ui_queue_stage_available === true
                root.uiQueueFirstTask = (root.uiQueueStartAvailable || root.uiQueueStageAvailable)
                    && typeof report.ui_queue_first_task === "string"
                    ? report.ui_queue_first_task : ""
                root.uiQueueServiceMode = typeof report.ui_queue_service_mode === "string"
                    ? report.ui_queue_service_mode : ""
                root.uiQueueServiceState = typeof report.ui_queue_service_state === "string"
                    ? report.ui_queue_service_state : ""
                root.uiQueuePreflightBlockers = Array.isArray(report.ui_queue_preflight_blockers)
                    ? report.ui_queue_preflight_blockers : []
                root.backendStatusKnown = true
                root.backendStatusText = ""
                root.backendServices = report.services
            } catch (error) {
                root.backendInstalled = false
                root.backendTransportReady = false
                root.uiQueueStartAvailable = false
                root.uiQueueStageAvailable = false
                root.uiQueueFirstTask = ""
                root.uiQueuePreflightBlockers = []
                root.uiQueueServiceMode = ""
                root.uiQueueServiceState = ""
                root.uiQueueStartConfirmation = false
                root.backendTransportBlocker = ""
                root.backendStatusKnown = false
                root.backendStatusText = String(error)
            }
        
    }

    function _handle_queueProcess(exitCode) {
            try {
                const result = root.readAutomationReply("queueProcess", queueOutput.text, queueError.text, exitCode)
                if (exitCode !== 0 || result.ok !== true)
                    throw new Error(result.error || "Queue unavailable")
                if (result.items) {
                    if (root.resetChatConfirmation) {
                        const target = result.active
                            ? result.active.repository + ":" + result.active.code : ""
                        if (target !== root.resetChatTarget
                                || result.state !== "active") {
                            root.resetChatConfirmation = false
                            root.resetChatTarget = ""
                        }
                    }
                    if (root.uiQueueStageConfirmation) {
                        const first = (result.items || []).find(item => item.state === "queued")
                        const current = first ? first.repository + ":" + first.code : ""
                        if (current !== root.uiQueueStageTarget
                                || root.uiQueueStageSnapshotId !== (result.snapshot_id || "")
                                || result.state !== "prepared") {
                            root.uiQueueStageConfirmation = false
                            root.uiQueueStageTarget = ""
                            root.uiQueueStageSnapshotId = ""
                        }
                    }
                    if (root.stopQueueConfirmation) {
                        const active = result.active
                        const current = active ? active.repository + ":" + active.code : ""
                        if (current !== root.stopQueueTarget
                                || root.stopQueueSnapshotId !== (result.snapshot_id || "")
                                || !["active", "waiting", "stopping"].includes(result.state)) {
                            root.stopQueueConfirmation = false
                            root.stopQueueTarget = ""
                            root.stopQueueSnapshotId = ""
                        }
                    }
                    if (root.clearQueueConfirmation
                            && (root.clearQueueTarget !== root.queuedTaskIdentities(result)
                                || root.clearQueueSnapshotId !== (result.snapshot_id || ""))) {
                        root.clearQueueConfirmation = false
                        root.clearQueueTarget = ""
                        root.clearQueueSnapshotId = ""
                    }
                    root.queueSnapshot = result
                    // Stop can be acknowledged asynchronously by the manager.
                    // Preserve that distinct state until the queue leaves
                    // active/waiting/stopping; never label pending as stopped.
                    if (result.state === "stopping"
                            || (root.queueOperation === "stop"
                                && result.stop_confirmed !== true))
                        root.stopAcknowledgementPending = true
                    else if (!["active", "waiting"].includes(result.state))
                        root.stopAcknowledgementPending = false
                    root.queueStatusConfirmed = true
                    if (root.queueOperation === "status")
                        root.cloudSelectTasks = result.mode === "cloud"
                }
                if (result.items && !result.items.length) {
                    root.selectedTask = null
                    root.taskSnapshot = null
                    root.activitySnapshot = null
                }
                if (result.items && result.items.length) {
                    const first = result.items[0]
                    if (!root.selectedTask || !result.items.some(t =>
                            t.code === root.selectedTask.code && t.repository === root.selectedTask.repository))
                        root.selectedTask = first
                    Qt.callLater(root.refreshTaskStatus)
                    Qt.callLater(root.refreshActivity)
                }
                if (root.queueOperation === "reset-chat") {
                    root.chatResetNotice = true
                    resetNoticeTimer.restart()
                    root.statusText = ""
                    Qt.callLater(root.refreshQueue)
                } else if (root.queueOperation === "stop") {
                    root.statusText = result.stop_confirmed
                        ? result.profile_stop_confirmed === false
                            ? Translation.tr("Queue scheduling stopped · manager profile missing. Prior worker actions remain independent.")
                            : Translation.tr("Queue stopped · no next task will start. In-flight work remains intact.")
                        : Translation.tr("Stop requested · manager acknowledgment pending")
                    Qt.callLater(root.refreshQueue)
                } else if (root.queueOperation === "stage-ui") {
                    root.statusText = Translation.tr("Idle UI profile prepared · no job started. Rechecking service readiness.")
                    Qt.callLater(root.refreshBackendStatus)
                } else if (root.queueOperation === "clear")
                    root.statusText = result.cleared
                        ? result.state === "empty"
                            ? Translation.tr("Queue archived · task records and in-flight receipts preserved")
                            : Translation.tr("Removed %1 queued tasks · active job and receipts preserved")
                                .arg(result.removed_queued || 0)
                        : Translation.tr("No queued tasks to clear")
                else if (root.queueOperation === "recheck") {
                    root.statusText = Translation.tr("Queue rechecked · %1 ready · %2 parked; saved receipts untouched")
                        .arg((result.items || []).filter(t => t.state === "queued").length)
                        .arg(result.deferred_count || 0)
                    Qt.callLater(root.refreshBackendStatus)
                } else if (root.queueOperation === "prepare") {
                    root.statusText = result.state === "active"
                        ? Translation.tr("Queue already active")
                        : result.duplicate
                        ? Translation.tr("Queue already prepared")
                        : result.auto_discovered
                        ? Translation.tr("Backend-first tasks discovered · review before Start")
                        : Translation.tr("Queue prepared")
                    Qt.callLater(root.refreshBackendStatus)
                } else if (root.queueOperation === "start") {
                    root.statusText = result.mode === "alis-ui-once"
                        ? Translation.tr("UI Queue profile scheduled · awaiting manager; ChatGPT delivery not yet verified")
                        : Translation.tr("Cloudbot queue launch requested · check manager status")
                    Qt.callLater(root.refreshQueue)
                    Qt.callLater(root.refreshBackendStatus)
                } else if (root.queueOperation === "status") {
                    Qt.callLater(root.refreshBackendStatus)
                    root.statusText = result.state === "active"
                        ? Translation.tr("Queue active")
                        : result.state === "prepared"
                        ? Translation.tr("Queue prepared")
                        : result.state === "stopping"
                        ? Translation.tr("Stop requested · manager acknowledgment pending")
                        : result.state === "stopped"
                        ? Translation.tr("Queue stopped · no next task will start. In-flight work remains intact.")
                        : ""
                }
                // A failed preparation is not a failed queue-status read.
                // Preserve the actionable task conflict while recovering a
                // VERIFIED read-only queue snapshot. Never enable Start from
                // a stale UI, and never retry intake automatically.
                if (root.queueOperation === "status")
                    root.errorText = root.queuePrepareError
                else {
                    root.queuePrepareError = ""
                    root.errorText = ""
                }
            } catch (error) {
                const failedOperation = root.queueOperation
                root.queueStatusConfirmed = false
                root.stopAcknowledgementPending = false
                root.statusText = ""
                root.errorText = String(error)
                if (failedOperation === "prepare" || failedOperation === "recheck") {
                    root.queuePrepareError = root.errorText
                    prepareFailureRefresh.restart()
                }
            }
            root.queueOperation = ""
        
    }

    function _handle_activityProcess(exitCode) {
            try {
                const result = root.readAutomationReply("activityProcess", activityOutput.text, activityError.text, exitCode)
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

    function _handle_ownerActionProcess(exitCode) {
            try {
                const reply = root.readAutomationReply("ownerActionProcess", ownerActionOutput.text, ownerActionError.text, exitCode)
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

    function _handle_taskStatusProcess(exitCode) {
            try {
                const reply = root.readAutomationReply("taskStatusProcess", taskStatusOutput.text, taskStatusError.text, exitCode)
                if (exitCode !== 0 || reply.ok !== true)
                    throw new Error(reply.error || "Task status unavailable")
                if (root.selectedTask && root.selectedTask.code === reply.code
                        && root.selectedTask.repository === reply.repository)
                    root.taskSnapshot = reply
            } catch (error) {
                root.statusText = Translation.tr("Task status unavailable: %1").arg(String(error))
            }
        
    }

    function _handle_cleanupProcess(exitCode) {
            try {
                const result = root.readAutomationReply("cleanupProcess", cleanupOutput.text, cleanupError.text, exitCode)
                if (exitCode !== 0 || result.ok !== true)
                    throw new Error(result.error || "Cleanup failed")
                root.cleanupResult = Translation.tr("Old payloads: %1 · receipts: %2 · task files: %3")
                    .arg(result.retired_payloads).arg(result.compacted_receipts)
                    .arg(result.deleted_task_files)
            } catch (error) {
                root.cleanupResult = Translation.tr("Cleanup unavailable: %1").arg(String(error))
            }
        
    }

    function _handle_githubStatusProcess(exitCode) {
            try {
                const result = root.readAutomationReply("githubStatusProcess", githubStatusOutput.text, githubStatusError.text, exitCode)
                if (exitCode !== 0 || result.ok !== true)
                    throw new Error(result.error || "Credential status unavailable")
                if (result.repository !== root.selectedGithubRepo)
                    return
                root.githubKeyringAvailable = result.keyring_available === true
                root.githubStatusKnown = true
                root.githubTokenSaved = result.saved === true
                root.githubStatusText = ""
            } catch (error) {
                root.githubStatusKnown = false
                root.githubKeyringAvailable = false
                root.githubStatusText = Translation.tr("GitHub status unavailable: %1").arg(String(error))
            }
        
    }

    function _handle_githubSecretProcess(exitCode) {
            root.pendingSecretInput = ""
            try {
                const result = root.readAutomationReply("githubSecretProcess", githubSecretOutput.text, githubSecretError.text, exitCode)
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
    function _handle_sudoAuthProcess(exitCode) {
        const operation = root.sudoOperation
        root.pendingSudoPassword = ""
        try {
            const result = root.readAutomationReply("sudoAuthProcess",
                sudoAuthOutput.text, "", exitCode)
            if (exitCode !== 0 || result.ok !== true)
                throw new Error("Keyring operation failed")
            if (["save", "clear", "status"].includes(operation)) {
                root.sudoStatusKnown = true
                root.sudoCredentialSaved = result.saved === true
                root.sudoKeyringAvailable = result.keyring_available === true
                root.sudoStatusText = result.saved
                    ? Translation.tr("Sudo password saved to local keyring · used only for approved administrator tasks")
                    : Translation.tr("No sudo password saved")
            } else {
                root.sudoStatusText = result.authenticated === true
                    ? Translation.tr("Sudo cache ready for approved administrator tasks")
                    : Translation.tr("Sudo cache unavailable · saved password used on demand")
            }
        } catch (error) {
            root.sudoStatusText = Translation.tr("Sudo keyring or authentication unavailable")
            if (operation === "status") root.sudoStatusKnown = false
        }
        root.sudoOperation = ""
    }

    Process {
        id: backendStatusProcess
        stdout: StdioCollector {
            id: backendStatusOutput
            onStreamFinished: root._automationStdoutClosed("backendStatusProcess")
        }
        stderr: StdioCollector { id: backendStatusError }
        onExited: exitCode => root._automationExited("backendStatusProcess", exitCode)
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
        stdout: StdioCollector {
            id: queueOutput
            onStreamFinished: root._automationStdoutClosed("queueProcess")
        }
        stderr: StdioCollector { id: queueError }
        onExited: exitCode => root._automationExited("queueProcess", exitCode)
    }

    Process {
        id: sudoAuthProcess
        stdout: StdioCollector {
            id: sudoAuthOutput
            onStreamFinished: root._automationStdoutClosed("sudoAuthProcess")
        }
        stderr: StdioCollector { id: sudoAuthError }
        onStarted: {
            if (root.sudoOperation === "save") {
                sudoAuthProcess.write(root.pendingSudoPassword)
                root.pendingSudoPassword = ""
                sudoAuthProcess.stdinEnabled = false
            }
        }
        onExited: exitCode => root._automationExited("sudoAuthProcess", exitCode)
    }

    Process {
        id: activityProcess
        stdout: StdioCollector {
            id: activityOutput
            onStreamFinished: root._automationStdoutClosed("activityProcess")
        }
        stderr: StdioCollector { id: activityError }
        onExited: exitCode => root._automationExited("activityProcess", exitCode)
    }


    Process {
        id: ownerActionProcess
        stdout: StdioCollector {
            id: ownerActionOutput
            onStreamFinished: root._automationStdoutClosed("ownerActionProcess")
        }
        stderr: StdioCollector { id: ownerActionError }
        onExited: exitCode => root._automationExited("ownerActionProcess", exitCode)
    }

    Process {
        id: taskStatusProcess
        stdout: StdioCollector {
            id: taskStatusOutput
            onStreamFinished: root._automationStdoutClosed("taskStatusProcess")
        }
        stderr: StdioCollector { id: taskStatusError }
        onExited: exitCode => root._automationExited("taskStatusProcess", exitCode)
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
        stdout: StdioCollector {
            id: cleanupOutput
            onStreamFinished: root._automationStdoutClosed("cleanupProcess")
        }
        stderr: StdioCollector { id: cleanupError }
        onExited: exitCode => root._automationExited("cleanupProcess", exitCode)
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
        stdout: StdioCollector {
            id: githubStatusOutput
            onStreamFinished: root._automationStdoutClosed("githubStatusProcess")
        }
        stderr: StdioCollector { id: githubStatusError }
        onExited: exitCode => root._automationExited("githubStatusProcess", exitCode)
    }

    Process {
        id: githubSecretProcess
        stdout: StdioCollector {
            id: githubSecretOutput
            onStreamFinished: root._automationStdoutClosed("githubSecretProcess")
        }
        stderr: StdioCollector { id: githubSecretError }
        onStarted: {
            if (root.pendingSecretOperation === "save") {
                githubSecretProcess.write(root.pendingSecretInput)
                root.pendingSecretInput = ""
                githubSecretProcess.stdinEnabled = false
            }
        }
        onExited: exitCode => root._automationExited("githubSecretProcess", exitCode)
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
                text: !root.backendStatusKnown
                    ? Translation.tr("Backend status unknown")
                    : root.backendInstalled
                    ? (root.backendTransportReady
                        ? Translation.tr("Backend installed · managed transport ready")
                        : root.uiQueueStartAvailable
                        ? Translation.tr("Backend installed · UI Queue mode ready for owner confirmation")
                        : root.uiQueueStageAvailable
                        ? Translation.tr("Backend installed · Prepare UI profile before Start")
                        : Translation.tr("Backend installed · automatic ChatGPT submission not authorized"))
                    : Translation.tr("Backend not installed")
            }
            StyledText {
                visible: root.backendStatusKnown && root.backendInstalled
                    && !root.backendTransportReady
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: root.uiQueueStartAvailable
                    ? Translation.tr("UI Queue mode uses local UI-only response evidence, not server-attested ChatGPT receipts. Starting requires a separate confirmation.")
                    : root.uiQueueStageAvailable
                    ? Translation.tr("An eligible task needs its idle UI profile staged first. Use Prepare UI in GitHub tasks; this never dispatches a job.")
                    : root.backendTransportBlocker === "CHATGPT_PROJECT_SERVER_RECEIPT_UNATTESTED"
                    ? Translation.tr("Native ChatGPT transport lacks verified message receipts. UI Loop requires separate owner-approved validation before queue Start.")
                    : Translation.tr("Queue Start is blocked until the managed ChatGPT transport is accepted.")
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
                    enabled: !root.busy && root.backendStatusKnown && !root.backendInstalled
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
            // Compact control row: order mode on the left, one live job
            // status on the right. Queue state is NEVER inferred from
            // locally guessed timings or stale items.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SettingsSwitch {
                    objectName: "automationCloudSelectToggle"
                    text: Translation.tr("Auto task order")
                    buttonIcon: "smart_toy"
                    checked: root.cloudSelectTasks
                    autoToggle: false
                    onToggledByUser: checked => root.cloudSelectTasks = checked
                }
                DialogButton {
                    objectName: "automationResetChat"
                    buttonText: root.resetChatConfirmation
                        ? Translation.tr("Confirm reset") : Translation.tr("Reset chat")
                    visible: !!root.queueSnapshot
                        && root.queueSnapshot.mode === "ordered"
                        && root.queueSnapshot.state === "active"
                    enabled: !root.busy && root.queueStatusConfirmed
                        && !!root.queueSnapshot && !!root.queueSnapshot.active
                        && root.queueSnapshot.state === "active"
                    onClicked: root.resetActiveChat()
                }
                Rectangle {
                    id: automationJobStatusPill
                    objectName: "automationJobStatus"
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: Math.min(330,
                        Math.max(110, jobStatusLabel.implicitWidth + 24))
                    radius: height / 2
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 6
                            radius: 3
                            color: root.stopAcknowledgementPending
                                || root.queueSnapshot?.state === "stopping"
                                ? Appearance.colors.colError
                                : root.queueSnapshot?.state === "active"
                                    && root.queueStatusConfirmed
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                        }
                        StyledText {
                            id: jobStatusLabel
                            Layout.fillWidth: true
                            text: Translation.tr("Job") + " · " + root.queueJobSummary
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }
            }

            // One input and one short action toolbar: all original safety
            // confirmations and backend commands remain unchanged.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialTextField {
                    id: taskCodeField
                    objectName: "automationTaskCode"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 130
                    placeholderText: Translation.tr("Task codes (;) or auto-discover")
                    onAccepted: root.prepareTask()
                }
                DialogButton {
                    objectName: "automationPrepareTask"
                    buttonText: root.busy ? Translation.tr("Wait")
                        : taskCodeField.text.trim().length === 0
                        ? (root.reviewRecheckAvailable
                            ? Translation.tr("Recheck") : Translation.tr("Find"))
                        : Translation.tr("Queue")
                    enabled: !root.busy
                    onClicked: root.prepareTask()
                }
                DialogButton {
                    objectName: "automationRefreshQueue"
                    buttonText: Translation.tr("Refresh")
                    enabled: !root.busy
                    onClicked: root.refreshQueue()
                }
                DialogButton {
                    objectName: "automationClearQueue"
                    buttonText: root.clearQueueConfirmation
                        ? Translation.tr("Confirm clear") : Translation.tr("Clear")
                    enabled: !root.busy && !!root.queueSnapshot
                        && (root.queueSnapshot.items.some(task => task.state === "queued")
                            || (["finished", "cancelled", "stopped", "review_required"].includes(root.queueSnapshot.state)
                                && root.queueSnapshot.items.length > 0))
                    onClicked: root.clearQueue()
                }
                DialogButton {
                    objectName: "automationStopQueue"
                    buttonText: root.stopQueueConfirmation
                        ? Translation.tr("Confirm stop") : Translation.tr("Stop")
                    visible: !!root.queueSnapshot
                        && ["active", "waiting", "stopping"].includes(root.queueSnapshot.state)
                    enabled: !root.busy && !!root.queueSnapshot
                        && ["active", "waiting", "stopping"].includes(root.queueSnapshot.state)
                    onClicked: root.stopQueue()
                }
                DialogButton {
                    objectName: "automationStageUiQueue"
                    buttonText: root.uiQueueStageConfirmation
                        ? Translation.tr("Confirm Prepare") : Translation.tr("Prepare UI")
                    visible: root.uiQueueStageAvailable
                        && !!root.queueSnapshot && root.queueSnapshot.state === "prepared"
                        && root.queueSnapshot.mode === "ordered"
                    enabled: !root.busy && root.queueStatusConfirmed
                        && root.uiQueueStageAvailable && !!root.queueSnapshot
                    onClicked: root.stageUiQueue()
                }
                DialogButton {
                    objectName: "automationStartQueue"
                    buttonText: root.uiQueueStartConfirmation
                        ? Translation.tr("Confirm UI Start")
                        : root.uiQueueStartAvailable && !root.backendTransportReady
                        ? Translation.tr("Start UI") : Translation.tr("Start")
                    // The native transport can Start a waiting queue;
                    // hiding the control in that state would regress resume.
                    visible: !root.queueSnapshot
                        || !["active", "stopping"].includes(root.queueSnapshot.state)
                    enabled: !root.busy && root.backendInstalled
                        && root.queueStatusConfirmed && !!root.queueSnapshot
                        && ((root.backendTransportReady
                            && ["prepared", "waiting"].includes(root.queueSnapshot.state)
                            && ["ordered", "cloud"].includes(root.queueSnapshot.mode))
                            || (root.uiQueueStartAvailable
                                && root.queueSnapshot.state === "prepared"
                                && root.queueSnapshot.mode === "ordered"
                                && root.queueSnapshot.items.some(item =>
                                    item.state === "queued" && item.code === root.uiQueueFirstTask)))
                    onClicked: root.startQueue()
                }
            }

            StyledText {
                visible: root.queueStartGuidance.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: root.queueStartGuidance
            }

            // Safety-critical second-click explanations stay visible ONLY
            // when the user is actively confirming a destructive action
            // or acceptance of UI-only receipts.
            StyledText {
                visible: root.errorText.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colError
                text: root.errorText
            }
            StyledText {
                visible: root.statusText.length > 0
                    && (root.clearQueueConfirmation
                        || root.stopQueueConfirmation
                        || root.uiQueueStartConfirmation
                        || root.uiQueueStageConfirmation
                        || root.resetChatConfirmation)
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colPrimary
                text: root.statusText
            }
            // Vertical queue: exactly ten rows per column, up to the
            // backend's twenty-item bound. The fixed-width status tags form
            // aligned vertical lanes across all rows and both columns.
            GridLayout {
                objectName: "automationQueueGrid"
                visible: !!root.queueSnapshot && root.queueSnapshot.items.length > 0
                Layout.fillWidth: true
                columns: 2
                rows: 10
                flow: GridLayout.TopToBottom
                columnSpacing: 10
                rowSpacing: 5

                Repeater {
                    model: root.queueSnapshot
                        ? root.queueSnapshot.items.slice(0, 20) : []
                    delegate: Rectangle {
                        id: queueTaskRow
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: !!root.selectedTask
                            && root.selectedTask.code === modelData.code
                            && root.selectedTask.repository === modelData.repository
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: 36
                        radius: 9
                        color: isSelected
                            ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                        border.width: isSelected ? 1 : 0
                        border.color: Appearance.colors.colPrimary

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: queueTaskRow.modelData.code
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Rectangle {
                                objectName: "automationTaskStatusTag"
                                Layout.preferredWidth: 112
                                Layout.preferredHeight: 24
                                radius: 7
                                color: Appearance.colors.colLayer2
                                border.width: 1
                                border.color: root.queueTagColor(queueTaskRow.modelData)
                                StyledText {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 5
                                    text: root.queueTag(queueTaskRow.modelData)
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: root.queueTagColor(queueTaskRow.modelData)
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectQueueTask(queueTaskRow.modelData)
                        }
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
                text: !root.backendStatusKnown
                    ? Translation.tr("Backend status unknown")
                    : !root.backendInstalled
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
                    root.githubStatusKnown = false
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
                text: !root.githubStatusKnown
                    ? Translation.tr("GitHub token status unknown")
                    : !root.githubKeyringAvailable
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
        icon: "admin_panel_settings"
        title: Translation.tr("Administrator access")
        settingsTaskSection: "tasks"
        visible: root.activeSection === "tasks"
        SettingsGroup {
            SettingsNote {
                icon: "security"
                text: Translation.tr("Optional sudo password is stored in the local Secret Service keyring, separate from GitHub. Ordinary tasks run without root; approved allowlisted administrator actions use it only when necessary.")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialTextField {
                    id: sudoPasswordField
                    objectName: "automationSudoPassword"
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Sudo password · local keyring")
                    echoMode: TextInput.Password
                    onAccepted: root.saveSudoPassword()
                }
                DialogButton {
                    objectName: "automationSudoSave"
                    buttonText: Translation.tr("Save password")
                    enabled: !root.busy && sudoPasswordField.text.length > 0
                        && root.sudoKeyringAvailable
                    onClicked: root.saveSudoPassword()
                }
                DialogButton {
                    objectName: "automationSudoClear"
                    buttonText: Translation.tr("Clear")
                    enabled: !root.busy && root.sudoCredentialSaved
                    onClicked: root.clearSudoPassword()
                }
                DialogButton {
                    buttonText: Translation.tr("Check sudo cache")
                    enabled: !root.busy
                    onClicked: root.checkSudoStatus()
                }
            }
            SettingsNote {
                icon: root.sudoCredentialSaved ? "lock" : "key"
                text: !root.sudoStatusKnown
                    ? Translation.tr("Local sudo keyring status unknown")
                    : !root.sudoKeyringAvailable
                    ? Translation.tr("System keyring unavailable · unlock Secret Service")
                    : root.sudoCredentialSaved
                    ? Translation.tr("Sudo password saved locally · no automatic root for ordinary tasks")
                    : Translation.tr("No sudo password saved locally")
            }
            StyledText {
                visible: root.sudoStatusText.length > 0
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                text: root.sudoStatusText
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
