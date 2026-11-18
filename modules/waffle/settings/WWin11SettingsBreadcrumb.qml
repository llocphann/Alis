pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks as Waffle

Item {
    id: root
    objectName: "waffleSettingsBreadcrumbHeader"

    property string categoryTitle: ""
    property string subPageTitle: ""
    property bool hasSubTabs: false
    property real contentLeftMargin: 28

    readonly property bool showSubPageCrumb: root.hasSubTabs
        && root.subPageTitle.trim().length > 0
        && root.subPageTitle.trim() !== root.categoryTitle.trim()

    readonly property string fullBreadcrumbText: root.showSubPageCrumb
        ? `${root.categoryTitle} > ${root.subPageTitle}`
        : root.categoryTitle

    signal categoryRootClicked()

    implicitHeight: Waffle.Looks.dp(52)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.contentLeftMargin
        anchors.rightMargin: 24
        anchors.topMargin: 6
        anchors.bottomMargin: 2
        spacing: 10

        MouseArea {
            id: rootCrumbArea
            visible: root.showSubPageCrumb
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: rootCrumbText.implicitWidth
            implicitHeight: rootCrumbText.implicitHeight
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.categoryRootClicked()

            Waffle.WText {
                id: rootCrumbText
                objectName: "waffleSettingsBreadcrumbRoot"
                anchors.centerIn: parent
                verticalAlignment: Text.AlignVCenter
                text: root.categoryTitle
                font.family: SettingsMaterialPreset.fontFamily
                font.pixelSize: Waffle.Looks.dp(28)
                font.weight: Font.DemiBold
                color: rootCrumbArea.containsMouse
                    ? SettingsMaterialPreset.textColor
                    : SettingsMaterialPreset.secondaryTextColor
            }
        }

        Waffle.FluentIcon {
            objectName: "waffleSettingsBreadcrumbChevron"
            visible: root.showSubPageCrumb
            Layout.alignment: Qt.AlignVCenter
            monochrome: true
            icon: "chevron-right"
            implicitSize: Waffle.Looks.dp(16)
            color: SettingsMaterialPreset.secondaryTextColor
        }

        Waffle.WText {
            objectName: "waffleSettingsBreadcrumbLeaf"
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            verticalAlignment: Text.AlignVCenter
            text: root.showSubPageCrumb ? root.subPageTitle : root.categoryTitle
            font.family: SettingsMaterialPreset.fontFamily
            font.pixelSize: Waffle.Looks.dp(28)
            font.weight: Font.DemiBold
            color: SettingsMaterialPreset.textColor
            elide: Text.ElideRight
        }
    }
}
