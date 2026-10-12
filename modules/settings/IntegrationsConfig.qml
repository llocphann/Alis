import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.services.deferred
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings
ContentPage {
 id:root
 settingsPageIndex:38
 settingsPageName:Translation.tr("Integrations")
 property string activeSection:"obsidian"
 function activateSettingsSearchSection(section:string):bool {
  const label=String(section ?? "").toLowerCase();
  activeSection=label.includes("calendar") ? "calendar" : label.includes("music") || label.includes("apps") ? "apps" : "obsidian";
  return true;
 }
 SettingsCardSection {
  id:hadalirdPackageSection
  title:"Optional integrations";icon:"extension";expanded:true
  property bool advanced:false
  property bool confirmRemoval:false
  property bool confirmSystemRemoval:false
  property bool confirmGatewayInstall:false
  property bool confirmGatewayRemoval:false

  // For a standalone Settings window, lower the toplevel as well.
  // Layer-shell Settings are lowered by the Hadalird authorization state.
  function privilegedAction(action:string):void {
   const window=root.Window.window
   if(window && window.lower) window.lower()
   Hadalird.manage(action)
  }

  StyledText {
   Layout.fillWidth:true;color:Appearance.colors.colSubtext
   text:Hadalird.managerBusy ? "Working…"
       : Hadalird.available ? "Hadalird "+Hadalird.version+" · installed"
       : "Hadalird · not installed"
  }
  Flow {
   Layout.fillWidth:true;spacing:8
   DialogButton {
    visible:!Hadalird.available
    enabled:!Hadalird.managerBusy
    buttonText:"Install Hadalird"
    onClicked:Hadalird.manage("install")
   }
   DialogButton {
    visible:Hadalird.available
    enabled:!Hadalird.managerBusy
    buttonText:"Check updates"
    onClicked:Hadalird.manage("check")
   }
   DialogButton {
    visible:Hadalird.available && Hadalird.updateAvailable
    enabled:!Hadalird.managerBusy
    buttonText:"Update"
    onClicked:Hadalird.manage("install")
   }
   DialogButton {
    buttonText:"Refresh"
    enabled:!Hadalird.managerBusy
    onClicked:{
     Hadalird.refresh()
     Hadalird.refreshSystemStatus()
    }
   }
  }
  StyledText {
   Layout.fillWidth:true;wrapMode:Text.WordWrap
   visible:Hadalird.managerError.length>0
   color:Appearance.colors.colError
   text:Hadalird.managerError
  }
  StyledText {
   Layout.fillWidth:true;wrapMode:Text.WordWrap
   visible:Hadalird.managerMessage.length>0 && Hadalird.managerError.length===0
   color:Appearance.colors.colSubtext
   text:Hadalird.managerMessage
  }
  StyledText {
   Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Appearance.colors.colSubtext
   text:"Gateway: "+(Hadalird.systemProvisionerAvailable?"Ready":"Not installed")
       +"  ·  Helpers: "+(Hadalird.systemHelpersDiagnostic==="unchecked"?"Not checked"
           : Hadalird.systemHelpersInstalled?"Ready":"Not installed")
  }
  Flow {
   Layout.fillWidth:true;spacing:8
   DialogButton {
    visible:Hadalird.available
    enabled:!Hadalird.managerBusy
    buttonText:Hadalird.systemHelpersInstalled?"Reinstall helpers":"Install helpers"
    onClicked:hadalirdPackageSection.privilegedAction("helpers-ensure")
   }
   DialogButton {
    buttonText:hadalirdPackageSection.advanced?"Hide advanced":"Advanced"
    enabled:!Hadalird.managerBusy
    onClicked:hadalirdPackageSection.advanced=!hadalirdPackageSection.advanced
   }
  }
  Flow {
   visible:hadalirdPackageSection.advanced
   Layout.fillWidth:true;spacing:8
   DialogButton {
    buttonText:"Check gateway"
    enabled:!Hadalird.managerBusy
    onClicked:Hadalird.manage("gateway-status")
   }
   DialogButton {
    visible:Hadalird.available && !Hadalird.systemProvisionerAvailable
        && !hadalirdPackageSection.confirmGatewayInstall
    buttonText:"Install gateway"
    enabled:!Hadalird.managerBusy
    onClicked:hadalirdPackageSection.confirmGatewayInstall=true
   }
   DialogButton {
    visible:hadalirdPackageSection.confirmGatewayInstall
    buttonText:"Confirm gateway install"
    enabled:!Hadalird.managerBusy
    onClicked:{
     hadalirdPackageSection.confirmGatewayInstall=false
     hadalirdPackageSection.privilegedAction("gateway-install")
    }
   }
   DialogButton {
    visible:hadalirdPackageSection.confirmGatewayInstall
    buttonText:"Cancel"
    onClicked:hadalirdPackageSection.confirmGatewayInstall=false
   }
   DialogButton {
    visible:Hadalird.available && Hadalird.canRollback
    buttonText:"Restore Hadalird"
    enabled:!Hadalird.managerBusy
    onClicked:Hadalird.manage("rollback")
   }
   DialogButton {
    visible:Hadalird.available && !hadalirdPackageSection.confirmRemoval
    buttonText:"Remove Hadalird"
    enabled:!Hadalird.managerBusy
    onClicked:hadalirdPackageSection.confirmRemoval=true
   }
   DialogButton {
    visible:hadalirdPackageSection.confirmRemoval
    buttonText:"Confirm removal"
    enabled:!Hadalird.managerBusy
    onClicked:{hadalirdPackageSection.confirmRemoval=false;Hadalird.manage("remove")}
   }
   DialogButton {
    visible:hadalirdPackageSection.confirmRemoval
    buttonText:"Cancel"
    onClicked:hadalirdPackageSection.confirmRemoval=false
   }
   DialogButton {
    visible:Hadalird.systemHelpersInstalled && !hadalirdPackageSection.confirmSystemRemoval
    buttonText:"Remove helpers"
    enabled:!Hadalird.managerBusy
    onClicked:hadalirdPackageSection.confirmSystemRemoval=true
   }
   DialogButton {
    visible:hadalirdPackageSection.confirmSystemRemoval
    buttonText:"Confirm helper removal"
    enabled:!Hadalird.managerBusy
    onClicked:{
     hadalirdPackageSection.confirmSystemRemoval=false
     hadalirdPackageSection.privilegedAction("helpers-remove")
    }
   }
   DialogButton {
    visible:hadalirdPackageSection.confirmSystemRemoval
    buttonText:"Cancel"
    onClicked:hadalirdPackageSection.confirmSystemRemoval=false
   }
   DialogButton {
    visible:Hadalird.gatewayPackageInstalled && !hadalirdPackageSection.confirmGatewayRemoval
    buttonText:"Remove gateway"
    enabled:!Hadalird.managerBusy && !Hadalird.systemHelpersInstalled
    onClicked:hadalirdPackageSection.confirmGatewayRemoval=true
   }
   DialogButton {
    visible:hadalirdPackageSection.confirmGatewayRemoval
    buttonText:"Confirm gateway removal"
    enabled:!Hadalird.managerBusy && !Hadalird.systemHelpersInstalled
    onClicked:{
     hadalirdPackageSection.confirmGatewayRemoval=false
     hadalirdPackageSection.privilegedAction("gateway-remove")
    }
   }
   DialogButton {
    visible:hadalirdPackageSection.confirmGatewayRemoval
    buttonText:"Cancel"
    onClicked:hadalirdPackageSection.confirmGatewayRemoval=false
   }
  }
  SettingsSwitch {text:"TLP";enabled:!Hadalird.managerBusy;autoToggle:false;checked:Config.options?.integrations?.hadalird?.tlp ?? false;onToggledByUser:value=>Config.setNestedValue("integrations.hadalird.tlp",value)}
  SettingsSwitch {text:"Thinkfan";enabled:!Hadalird.managerBusy;autoToggle:false;checked:Config.options?.integrations?.hadalird?.thinkfan ?? false;onToggledByUser:value=>Config.setNestedValue("integrations.hadalird.thinkfan",value)}
  SettingsSwitch {text:"Obsidian";enabled:!Hadalird.managerBusy;autoToggle:false;checked:Config.options?.integrations?.hadalird?.obsidian ?? false;onToggledByUser:value=>Config.setNestedValue("integrations.hadalird.obsidian",value)}
 }
 SettingsTaskNavigator {
  title:Translation.tr("Third-party integrations");icon:"extension";currentValue:root.activeSection
  description:Translation.tr("Connect your applications and data to Hadalis.")
  onSelected:value=>root.activeSection=value
  options:[{displayName:"Obsidian",icon:"diamond",value:"obsidian"},{displayName:"Calendar",icon:"calendar_month",value:"calendar"},{displayName:"Applications",icon:"apps",value:"apps"}]
 }
    ObsidianThemeSettings {settingsTaskSection:"obsidian";visible:root.activeSection === "obsidian"}
    ObsidianTodoSettings {
        visible: root.activeSection === "obsidian"
    }

    SettingsCardSection {
        settingsTaskSection: "calendar"
        visible: root.activeSection === "calendar"
        expanded: true
        icon: "calendar_month"
        title: Translation.tr("Calendar Sync")

        SettingsGroup {
            SettingsSwitch {
                buttonIcon: "sync"
                text: Translation.tr("Enable external calendar sync")
                checked: Config.options?.calendar?.externalSync?.enable ?? false
                onCheckedChanged: Config.setNestedValue("calendar.externalSync.enable", checked)
            }

            ConfigSpinBox {
                icon: "update"
                text: Translation.tr("Refresh interval (minutes)")
                value: Config.options?.calendar?.externalSync?.refreshMinutes ?? 15
                from: 5
                to: 120
                stepSize: 5
                onValueChanged: Config.setNestedValue("calendar.externalSync.refreshMinutes", value)
                enabled: Config.options?.calendar?.externalSync?.enable ?? false
            }

            SettingsSwitch {
                buttonIcon: "event"
                text: Translation.tr("Show upcoming events below calendar")
                checked: Config.options?.calendar?.showUpcoming ?? true
                onCheckedChanged: Config.setNestedValue("calendar.showUpcoming", checked)
            }

            ConfigSpinBox {
                icon: "event"
                text: Translation.tr("Maximum indicators per day")
                description: Translation.tr("Calendar Popup event dots (0 hides them; maximum 5)")
                value: Config.options?.calendar?.maxEventDots ?? 3
                from: 0
                to: 5
                stepSize: 1
                onValueChanged: Config.setNestedValue("calendar.maxEventDots", value)
            }

            ConfigSpinBox {
                icon: "date_range"
                text: Translation.tr("Upcoming days to show")
                value: Config.options?.calendar?.upcomingDays ?? 3
                from: 1
                to: 14
                stepSize: 1
                onValueChanged: Config.setNestedValue("calendar.upcomingDays", value)
            }
        }

        // Calendar source list
        SettingsGroup {
            visible: Config.options?.calendar?.externalSync?.enable ?? false

            // Section header for sources
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                Layout.bottomMargin: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Calendar Sources")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                RippleButton {
                    implicitWidth: addRow.implicitWidth + 16
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.80)
                    onClicked: addSourceForm.expanded = true

                    contentItem: RowLayout {
                        id: addRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: "add"
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Add")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            // Source list
            Repeater {
                model: Config.options?.calendar?.externalSync?.sources ?? []

                delegate: Item {
                    id: sourceItem
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: sourceRow.implicitHeight + 12

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: sourceMA.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                        RowLayout {
                            id: sourceRow
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            // Color dot
                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: sourceItem.modelData?.color ?? Appearance.colors.colPrimary
                            }

                            // Name and URL
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: sourceItem.modelData?.name ?? Translation.tr("Unnamed")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: sourceItem.modelData?.url ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                }
                            }

                            // Status indicator
                            MaterialSymbol {
                                visible: {
                                    const st = CalendarSync.sourceStatuses?.[sourceItem.modelData?.id]
                                    return st?.error && st.error !== ""
                                }
                                text: "error"
                                iconSize: 16
                                color: Appearance.colors.colError

                                StyledToolTip {
                                    text: CalendarSync.sourceStatuses?.[sourceItem.modelData?.id]?.error ?? ""
                                }
                            }

                            // Toggle enabled
                            Switch {
                                checked: sourceItem.modelData?.enabled ?? true
                                onCheckedChanged: {
                                    if (checked !== (sourceItem.modelData?.enabled ?? true)) {
                                        CalendarSync.toggleSource(sourceItem.modelData.id, checked)
                                    }
                                }
                            }

                            // Remove button
                            RippleButton {
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: 14
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: CalendarSync.removeSource(sourceItem.modelData.id)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }

                                StyledToolTip {
                                    text: Translation.tr("Remove")
                                }
                            }
                        }

                        MouseArea {
                            id: sourceMA
                            anchors.fill: parent
                            z: -1
                            hoverEnabled: true
                        }
                    }
                }
            }

            // Empty state
            StyledText {
                visible: (Config.options?.calendar?.externalSync?.sources ?? []).length === 0
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                text: Translation.tr("No calendar sources added yet")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                font.italic: true
            }

            // Help text for getting ICS URLs
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                text: Translation.tr("Paste a compatible ICS/iCal feed URL; no account sign-in within Alis.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                opacity: 0.7
            }

            // Inline add-source form (expands in place)
            Rectangle {
                id: addSourceForm
                Layout.fillWidth: true
                Layout.topMargin: 4

                property bool expanded: false

                implicitHeight: expanded ? addFormCol.implicitHeight + 24 : 0
                visible: expanded
                clip: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerLow
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                Behavior on implicitHeight {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                ColumnLayout {
                    id: addFormCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    StyledText {
                        text: Translation.tr("Add Calendar Source")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        StyledText {
                            text: Translation.tr("Name")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: sourceNameInput
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Work Calendar")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: sourceNameInput.activeFocus ? 2 : 1
                                border.color: sourceNameInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        StyledText {
                            text: Translation.tr("ICS URL")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        MaterialTextField {
                            id: sourceUrlInput
                            Layout.fillWidth: true
                            placeholderText: "https://calendar.google.com/calendar/ical/..."
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: sourceUrlInput.activeFocus ? 2 : 1
                                border.color: sourceUrlInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }
                        }
                    }

                    // Color picker
                    ColumnLayout {
                        spacing: 4

                        StyledText {
                            text: Translation.tr("Color")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        Row {
                            id: colorPickerRow
                            spacing: 6
                            property string selectedColor: CalendarSync.presetColors[0]

                            Repeater {
                                model: CalendarSync.presetColors

                                delegate: Rectangle {
                                    required property string modelData
                                    required property int index
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: modelData
                                    border.width: colorPickerRow.selectedColor === modelData ? 2 : 0
                                    border.color: Appearance.colors.colOnLayer1
                                    opacity: colorPickMA.containsMouse ? 0.8 : 1

                                    MouseArea {
                                        id: colorPickMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: colorPickerRow.selectedColor = modelData
                                    }
                                }
                            }
                        }
                    }

                    // Action buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            implicitWidth: cancelLabel.implicitWidth + 24
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: {
                                addSourceForm.expanded = false
                                sourceNameInput.text = ""
                                sourceUrlInput.text = ""
                            }

                            contentItem: StyledText {
                                id: cancelLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Cancel")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        RippleButton {
                            implicitWidth: addLabel.implicitWidth + 24
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            enabled: sourceNameInput.text.trim() !== "" && sourceUrlInput.text.trim() !== ""
                            opacity: enabled ? 1 : 0.5
                            onClicked: {
                                CalendarSync.addSource(
                                    sourceNameInput.text.trim(),
                                    sourceUrlInput.text.trim(),
                                    colorPickerRow.selectedColor
                                )
                                sourceNameInput.text = ""
                                sourceUrlInput.text = ""
                                addSourceForm.expanded = false
                            }

                            contentItem: StyledText {
                                id: addLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Add")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }
    }
    SettingsCardSection {
        settingsTaskSection: "apps"
        visible: root.activeSection === "apps"
        expanded: true
        icon: "music_cast"
        title: Translation.tr("Music Recognition")

        SettingsGroup {
            ConfigSpinBox {
                icon: "timer_off"
                text: Translation.tr("Total duration timeout (s)")
                value: Config.options?.musicRecognition?.timeout ?? 16
                from: 10
                to: 100
                stepSize: 2
                onValueChanged: {
                    Config.setNestedValue("musicRecognition.timeout", value)
                }
                StyledToolTip {
                    text: Translation.tr("Maximum time to wait for music recognition result")
                }
            }
            ConfigSpinBox {
                icon: "av_timer"
                text: Translation.tr("Polling interval (s)")
                value: Config.options?.musicRecognition?.interval ?? 4
                from: 2
                to: 10
                stepSize: 1
                onValueChanged: {
                    Config.setNestedValue("musicRecognition.interval", value)
                }
                StyledToolTip {
                    text: Translation.tr("How often to check for recognition result")
                }
            }
        }
    }

}
