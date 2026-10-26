import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property string settingsTaskSection: "power"
    property bool showIntegrationSettings: true
    property int selectedCategoryIndex: 0
    readonly property var navigationCategories: content.item?.navigationCategories ?? ([])

    onSelectedCategoryIndexChanged: {
        if (content.item && content.item.selectedCategoryIndex !== root.selectedCategoryIndex)
            content.item.selectedCategoryIndex = root.selectedCategoryIndex
    }
    implicitHeight: content.item?.implicitHeight ?? fallback.item?.implicitHeight ?? 0
    Loader {
        id: content
        width: parent.width
        active: root.showIntegrationSettings && root.visible && AlisIntergration.tlpEnabled
        source: AlisIntergration.settingsSource("tlp")
        onLoaded: item.selectedCategoryIndex = root.selectedCategoryIndex
    }
    Connections {
        target: content.item
        function onSelectedCategoryIndexChanged(): void {
            if (content.item)
                root.selectedCategoryIndex = content.item.selectedCategoryIndex
        }
    }
    Loader {
        id: fallback
        width: parent.width
        // Warning/suspend preferences belong to Core even without TLP. Retire
        // this tree only once the optional settings page is actually ready.
        active: !content.item
        sourceComponent: ColumnLayout {
            spacing: SettingsMaterialPreset.pageSpacing

            SettingsCardSection {
                expanded: true
                collapsible: false
                icon: "battery_saver"
                title: Translation.tr("Battery")

                SettingsGroup {
                    ConfigRow {
                        uniform: true

                        ConfigSpinBox {
                            objectName: "batteryLowWarningControl"
                            icon: "warning"
                            text: Translation.tr("Low warning")
                            value: Config.options?.battery?.low ?? 0
                            from: 0
                            to: 100
                            stepSize: 5
                            onValueModified: value => Config.setNestedValue("battery.low", value)
                            StyledToolTip {
                                text: Translation.tr("Show warning notification when battery drops below this level")
                            }
                        }
                        ConfigSpinBox {
                            objectName: "batteryCriticalWarningControl"
                            icon: "dangerous"
                            text: Translation.tr("Critical warning")
                            value: Config.options?.battery?.critical ?? 0
                            from: 0
                            to: 100
                            stepSize: 5
                            onValueModified: value => Config.setNestedValue("battery.critical", value)
                            StyledToolTip {
                                text: Translation.tr("Show critical warning when battery drops below this level")
                            }
                        }
                        ConfigSpinBox {
                            objectName: "batteryFullWarningControl"
                            icon: "charger"
                            text: Translation.tr("Full warning")
                            value: Config.options?.battery?.full ?? 0
                            from: 0
                            to: 101
                            stepSize: 5
                            onValueModified: value => Config.setNestedValue("battery.full", value)
                            StyledToolTip {
                                text: Translation.tr("Notify when battery reaches this level while charging (101 = disabled)")
                            }
                        }
                    }
                    SettingsDivider {}
                    ConfigRow {
                        uniform: false

                        SettingsSwitch {
                            objectName: "batteryAutomaticSuspendControl"
                            buttonIcon: "pause"
                            text: Translation.tr("Automatic suspend")
                            checked: Config.options?.battery?.automaticSuspend ?? false
                            autoToggle: false
                            onToggledByUser: checked => Config.setNestedValue("battery.automaticSuspend", checked)
                            StyledToolTip {
                                text: Translation.tr("Automatically suspends the system when battery is low")
                            }
                        }
                        ConfigSpinBox {
                            objectName: "batterySuspendThresholdControl"
                            enabled: Config.options?.battery?.automaticSuspend ?? false
                            text: Translation.tr("at")
                            value: Config.options?.battery?.suspend ?? 0
                            from: 0
                            to: 100
                            stepSize: 5
                            onValueModified: value => Config.setNestedValue("battery.suspend", value)
                            StyledToolTip {
                                text: Translation.tr("Percentage of battery to trigger suspend")
                            }
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: "Install Alis-Intergration and enable this integration in Settings → Integrations."
            }
        }
    }
}
