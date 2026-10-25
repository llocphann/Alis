pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.waffle.settings

WSettingsPage {
    id: root
    settingsPageIndex: 18
    pageTitle: Translation.tr("Battery")
    pageIcon: "battery-saver"
    pageDescription: Translation.tr("Charge care, power profiles, processor, devices, and the effective TLP configuration")
    property int selectedCategoryIndex: 0
    property string filterText: ""
    onSelectedCategoryIndexChanged: {
        if (content.item && content.item.selectedCategoryIndex !== selectedCategoryIndex)
            content.item.selectedCategoryIndex = selectedCategoryIndex
    }
    onFilterTextChanged: {
        if (content.item && content.item.filterText !== filterText)
            content.item.filterText = filterText
    }
    Loader {
        id: content
        Layout.fillWidth: true
        Layout.preferredHeight: item?.implicitHeight ?? 0
        active: root.visible && Hadalird.tlpEnabled
        source: Hadalird.settingsSource("tlpWaffle")
        onLoaded: {
            const savedFilter = root.filterText
            item.selectedCategoryIndex = root.selectedCategoryIndex
            item.filterText = savedFilter
        }
    }
    Connections {
        target: content.item
        function onSelectedCategoryIndexChanged(): void {
            if (content.item) root.selectedCategoryIndex = content.item.selectedCategoryIndex
        }
        function onFilterTextChanged(): void {
            if (content.item) root.filterText = content.item.filterText
        }
    }
    WSettingsInfoBar {
        visible: !content.item
        message: Translation.tr("Install Alis-Intergration; enable TLP in Settings → Integrations.")
    }
    WSettingsButton {
        visible: !content.item
        label: Translation.tr("Battery notifications")
        buttonText: Translation.tr("General")
        onButtonClicked: root.navigateRequested(1)
    }
}
