import QtQuick

// idx1 is the "leading" indicator position, idx2 is the "following" one
// The former animates faster than the latter, see the NumberAnimations below
QtObject {
    id: root
    required property real index
    property bool animate: true

    property real idx1: root.index
    property real idx2: root.index
    property int idx1Duration: 100
    property int idx2Duration: 300

    onAnimateChanged: {
        if (!root.animate) {
            anim1.complete()
            anim2.complete()
        }
    }

    Behavior on idx1 {
        enabled: root.animate
        NumberAnimation {
            id: anim1
            duration: root.idx1Duration
            easing.type: Easing.OutSine
        }
    }
    Behavior on idx2 {
        enabled: root.animate
        NumberAnimation {
            id: anim2
            duration: root.idx2Duration
            easing.type: Easing.OutSine
        }
    }
}
