import QtQuick

// A single Image retains Main.qml's blur/scale layer. The greeter must have a
// bundled fallback even before any user-session theme sync has run.
Image {
    id: root
    property url configuredSource: ""
    property url configuredFallback: ""
    readonly property url bundledFallback: Qt.resolvedUrl("assets/default-background.svg")
    property int fallbackStage: 2
    readonly property bool showingFallback: fallbackStage > 0

    function resetSource(): void {
        fallbackStage = configuredSource.toString().length > 0 ? 0
            : configuredFallback.toString().length > 0 ? 1 : 2
    }
    onConfiguredSourceChanged: resetSource()
    onConfiguredFallbackChanged: resetSource()
    Component.onCompleted: resetSource()

    source: fallbackStage === 0 ? configuredSource
        : fallbackStage === 1 ? configuredFallback : bundledFallback
    onStatusChanged: {
        if (status !== Image.Error || fallbackStage >= 2) return
        // Legacy themes use the same missing URL for both settings. Skip that
        // duplicate, otherwise assigning the same source cannot trigger retry.
        fallbackStage = fallbackStage === 0
            && configuredFallback.toString().length > 0
            && configuredFallback.toString() !== configuredSource.toString() ? 1 : 2
    }
}
