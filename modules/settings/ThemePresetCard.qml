import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    required property var preset
    property bool forceActive: false
    property bool isActive: forceActive || preset.id === ThemeService.currentTheme
    readonly property bool favoriteEnabled: preset.saved !== true
    readonly property bool isFavorite: favoriteEnabled && (Config.options?.appearance?.favoriteThemes ?? []).includes(preset.id)

    signal clicked()

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.preset.name
    Accessible.description: root.preset.description ?? ""
    Accessible.checkable: true
    Accessible.checked: root.isActive
    Accessible.onPressAction: root.clicked()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked()
            event.accepted = true
        }
    }

    function getColor(key, fallback) {
        if (!preset.colors) return Appearance.m3colors[key] ?? fallback
        if (preset.colors === "custom") return Config.options?.appearance?.customTheme?.[key] ?? fallback
        return preset.colors[key] ?? fallback
    }

    function toggleFavorite() {
        let favs = Config.options?.appearance?.favoriteThemes ?? []
        if (root.isFavorite) {
            favs = favs.filter(t => t !== preset.id)
        } else {
            favs = [...favs, preset.id]
        }
        Config.setNestedValue("appearance.favoriteThemes", favs)
    }

    implicitHeight: Math.round(42 * Appearance.fontSizeScale)

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: Appearance.rounding.small

        readonly property color presetPrimary: root.getColor("m3primary", "#6366f1")
        readonly property color presetSecondary: root.getColor("m3secondary", "#818cf8")
        readonly property color presetTertiary: root.getColor("m3tertiary", "#a5b4fc")
        readonly property color presetSurface: root.getColor("m3background", "#0f0f23")

        color: root.isActive
            ? ColorUtils.transparentize(cardBg.presetPrimary, 0.84)
            : (cardMouseArea.containsMouse || root.activeFocus
                ? Appearance.colors.colLayer2Hover
                : Appearance.colors.colLayer2)

        border.width: root.isActive ? 1.5 : 1
        border.color: root.isActive
            ? cardBg.presetPrimary
            : (root.activeFocus ? Appearance.colors.colPrimary : SettingsMaterialPreset.groupBorderColor)

        Behavior on color { enabled: Appearance.animationsEnabled; ColorAnimation { duration: 110 } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 6
        spacing: 8

        // iRiS mini palette specimen tile
        Rectangle {
            Layout.preferredWidth: Math.round(38 * Appearance.fontSizeScale)
            Layout.preferredHeight: Math.round(24 * Appearance.fontSizeScale)
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: cardBg.presetSurface
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)

            Row {
                anchors.centerIn: parent
                spacing: 3

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: cardBg.presetPrimary
                }
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: cardBg.presetSecondary
                }
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: cardBg.presetTertiary
                }
            }
        }

        MaterialSymbol {
            visible: root.preset.saved === true
            text: "bookmark"
            iconSize: 13
            color: cardBg.presetPrimary
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                text: preset.name
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: root.isActive ? Font.DemiBold : Font.Normal
                color: root.isActive
                    ? Appearance.colors.colOnSurface
                    : Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }

            MouseArea {
                id: cardMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.forceActiveFocus()
                    root.clicked()
                }
            }
        }

        Rectangle {
            id: starButton
            width: 26
            height: 26
            radius: 13
            activeFocusOnTab: root.favoriteEnabled
            Accessible.role: Accessible.Button
            Accessible.name: root.isFavorite ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
            Accessible.checkable: true
            Accessible.checked: root.isFavorite
            Accessible.onPressAction: root.toggleFavorite()
            color: starMouseArea.containsMouse || starButton.activeFocus
                ? (root.isFavorite ? Appearance.colors.colLayer1Hover : Appearance.colors.colTertiaryContainer)
                : "transparent"
            visible: root.favoriteEnabled && (root.isFavorite || root.activeFocus || starButton.activeFocus || cardMouseArea.containsMouse || starMouseArea.containsMouse)

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    root.toggleFavorite()
                    event.accepted = true
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "star"
                fill: root.isFavorite ? 1 : 0
                iconSize: 15
                color: root.isFavorite
                    ? Appearance.colors.colTertiary
                    : starMouseArea.containsMouse || starButton.activeFocus
                        ? Appearance.colors.colOnTertiaryContainer
                        : Appearance.colors.colSubtext
            }

            MouseArea {
                id: starMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    starButton.forceActiveFocus()
                    root.toggleFavorite()
                }
            }

            StyledToolTip {
                text: root.isFavorite ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
                visible: starMouseArea.containsMouse || starButton.activeFocus
            }
        }

        MaterialSymbol {
            visible: root.isActive && !starButton.visible
            text: "check"
            iconSize: 16
            color: cardBg.presetPrimary
        }
    }

    StyledToolTip {
        text: preset.description ?? ""
        visible: cardMouseArea.containsMouse && (preset.description ?? "").length > 0
        delay: 500
    }
}
