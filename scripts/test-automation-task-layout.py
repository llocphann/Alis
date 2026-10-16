#!/usr/bin/env python3
"""GitHub tasks UI: compact single queue, visible job status, unchanged action guards."""
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "modules/settings/AutomationTaskConfig.qml"
qml = path.read_text(encoding="utf-8")
start = qml.index('title: Translation.tr("GitHub tasks")')
end = qml.index('title: Translation.tr("Status")', start)
card = qml[start:end]

def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)

require("readonly property string queueJobSummary" in qml,
        "job status must be derived from the queue snapshot")
require('objectName: "automationJobStatus"' in card,
        "missing compact live job status")
require('root.stopAcknowledgementPending' in card,
        "stop ack must not appear as completed")
require('root.queueStatusConfirmed' in card,
        "queue Start must remain gated by live verification")
require('Layout.fillWidth: true' in card,
        "compact controls should adapt to available width")

# The UI must not show the same queue twice or rely on long help labels.
require(card.count('objectName: "automationQueueGrid"') == 1
        and card.count('objectName: "automationTaskStatusTag"') == 1,
        "there must be exactly one aligned two-column queue")
require("columns: 2" in card and "rows: 10" in card
        and "flow: GridLayout.TopToBottom" in card,
        "each column must list at most ten tasks vertically")
require("Layout.preferredWidth: 112" in card,
        "aligned status tags need consistent fixed width")
require("modelData.code" in card and "root.queueTag(queueTaskRow.modelData)" in card,
        "task code and status tag are required on each row")
require("onClicked: root.selectQueueTask(queueTaskRow.modelData)" in card,
        "clicking a task row must keep task status/activity selection")
require('Translation.tr("Verified")' in qml
        and 'Translation.tr("Done")' in qml
        and 'Translation.tr("Working")' in qml
        and 'Translation.tr("Queue")' in qml,
        "primary status vocabulary must contain Verified, Done, Working, Queue")
require('join("\\n")' not in card and '(i + 1) + ". "' not in card,
        "the numbered multiline queue was not removed")
require('Cloudbot will select the next task' not in card
        and 'Task codes separated by' not in card
        and 'Last known queue only' not in card,
        "non-actionable task notes must be removed")

# Keep the existing backend paths and confirmation contracts; CSS-only
# redesigns have broken queue Start/Stop/Clear before.
for symbol in [
    'objectName: "automationCloudSelectToggle"',
    'objectName: "automationTaskCode"',
    'objectName: "automationPrepareTask"',
    'objectName: "automationRefreshQueue"',
    'objectName: "automationClearQueue"',
    'objectName: "automationStopQueue"',
    'objectName: "automationStartQueue"',
    "onClicked: root.prepareTask()",
    "onClicked: root.refreshQueue()",
    "onClicked: root.clearQueue()",
    "onClicked: root.stopQueue()",
    "onClicked: root.startQueue()",
    "onClicked: root.selectQueueTask(queueTaskRow.modelData)",
    "root.stopQueueConfirmation",
    "root.clearQueueConfirmation",
    "root.uiQueueStartConfirmation",
    "root.backendTransportReady",
    "root.uiQueueStartAvailable",
    "root.uiQueueFirstTask",
    '"waiting"',
]:
    require(symbol in card, "missing UI contract: " + symbol)

require('objectName: "automationResetChat"' in card,
        "missing owner-confirmed Reset chat control")
require('onClicked: root.resetActiveChat()' in card,
        "Reset chat must route through guarded queue action")
require('"queue-reset-chat", "--approve", "--expected-active", identity' in qml,
        "Reset Chat must be pinned to the exact active task")
require('root.resetChatConfirmation' in card,
        "Reset Chat must require an additional owner confirmation")
require('root.chatResetNotice' in qml,
        "Reset request must appear in the compact Job Status")
require("property string queuePrepareError" in qml,
        "prepare errors must remain visible while queue status is refreshed")
require("prepareFailureRefresh.restart()" in qml
        and "root.refreshQueue()" in qml,
        "after rejected task intake, refresh queue status read-only")
require('root.errorText = root.queuePrepareError' in qml,
        "status refresh must not erase task-conflict reason")
require("root.stopAcknowledgementPending = true" in qml,
        "stop request must remain visibly pending until manager ack")
require("root.stopAcknowledgementPending = false" in qml,
        "pending state must reset when the queue leaves active mode")
require("Qt.callLater(root.refreshTaskStatus)" in qml
        and "Qt.callLater(root.refreshActivity)" in qml,
        "clicking a task must refresh detail/activity")
print("PASS Automation vertical queue 2 columns × 10 rows, tagged statuses, controls")
