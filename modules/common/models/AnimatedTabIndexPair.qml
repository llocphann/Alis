import QtQuick

// idx1 is the "leading" indicator position, idx2 is the "following" one
// The former animates faster than the latter, see the NumberAnimations below
QtObject {
    id: root
    required property real index
    property bool animate: false

    property real idx1: index
    property real idx2: index
    property int idx1Duration: 100
    property int idx2Duration: 300

    onIndexChanged: {
        if (!root.animate) {
            root.idx1 = root.index
            root.idx2 = root.index
        }
    }
    onAnimateChanged: {
        if (!root.animate) {
            root.idx1 = root.index
            root.idx2 = root.index
        }
    }

    Behavior on idx1 {
        enabled: root.animate
        NumberAnimation {
            duration: root.idx1Duration
            easing.type: Easing.OutSine
        }
    }
    Behavior on idx2 {
        enabled: root.animate
        NumberAnimation {
            duration: root.idx2Duration
            easing.type: Easing.OutSine
        }
    }
}
