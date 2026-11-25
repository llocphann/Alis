pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

// Host proxy only. Spaced Repetition ships exclusively inside the optional
// Alis-Intergration spaced_repetition plugin and remains inert until installed
// and enabled by the user.
Singleton {
    id: root

    readonly property var implementation: AlisIntergration.spacedRepetition
        ?? AlisIntergration.session?.spacedRepetition
        ?? null
    readonly property bool available: root.implementation !== null
    readonly property bool enabled: AlisIntergration.spacedRepetitionEnabled
    readonly property bool ready: root.implementation?.ready ?? false
    readonly property var cards: root.implementation?.cards ?? []
    readonly property var historyByDay: root.implementation?.historyByDay ?? ({})
    readonly property var statsSummary: root.implementation?.statsSummary ?? ({})
    readonly property int dueCount: root.implementation?.dueCount ?? 0
    readonly property int newDueCount: root.implementation?.newDueCount ?? 0
    readonly property int totalCards: root.implementation?.totalCards ?? 0

    function ensureLoaded(): void {
        if (root.implementation && typeof root.implementation.ensureLoaded === "function")
            root.implementation.ensureLoaded()
    }
}
