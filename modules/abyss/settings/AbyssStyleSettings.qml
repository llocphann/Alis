pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks
import "../../common/PanelFamilyPolicy.js" as FamilyPolicy
import "../looks/AbyssWave.js" as Wave

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 16
    property string activeSection: "surface"
    property var sections: ["surface","performance"]
    readonly property var waveValues: Wave.parameters(Config.options?.abyss?.waves)
    function spectrumChange(key,value): void {
        const options=Config.options?.abyss?.spectrum
        const updates={"abyss.spectrum.configured":true,
            "abyss.spectrum.enabled":options?.configured ? options.enabled : Config.options?.bar?.visualizer?.enable ?? false,
            "abyss.spectrum.multiMonitorMode":options?.configured ? options.multiMonitorMode : Config.options?.bar?.visualizer?.multiMonitorMode ?? "primary"}
        updates["abyss.spectrum."+key]=value
        Config.setNestedValues(updates)
    }
    function waveChange(key,value): void {
        const updates={"abyss.waves.preset":"custom"}
        Object.keys(Wave.presets.balanced).forEach(k => updates["abyss.waves."+k]=waveValues[k])
        updates["abyss.waves."+key]=value
        Config.setNestedValues(updates)
    }
    component Percent: WindowDialogSlider {
        id: control
        required property string configKey
        property real fallback: 0
        property real minimum: 0
        property real maximum: 1
        property string unit: maximum > 4 ? "px" : "%"
        Layout.fillWidth:true
        from:minimum;to:maximum;stepSize:unit === "%" ? .01 : 1
        value:Config.getNestedValue(configKey,fallback)
        valueText:Math.round(value*(unit === "%" ? 100 : 1))+" "+unit
        onMoved: Config.setNestedValue(configKey,value)
    }
    component WaveControl: WindowDialogSlider {
        id: control
        required property string parameter
        Layout.fillWidth:true
        from:0;to:parameter === "amplitude" ? 400 : 100;stepSize:1
        visible:(Config.options?.abyss?.waves?.preset ?? "balanced") === "custom"
        value:root.waveValues[parameter]*100
        valueText:parameter === "amplitude" ? Math.round(4+32*value/100)+" px" : Math.round(value)+" %"
        onMoved: root.waveChange(parameter,value/100)
    }
    SettingsTaskNavigator {
        icon:"water";title:"Abyss"
        description:"The Material layout you know, carried by one continuous Screen Edge."
        currentValue:root.activeSection
        onSelected:value=>root.activeSection=value
        visible:options.length > 1
        showIntro:false
        options:[
            {displayName:"Surface",value:"surface",icon:"opacity"},
            {displayName:"Waves",value:"waves",icon:"waves"},
            {displayName:"Spectrum",value:"spectrum",icon:"graphic_eq"},
            {displayName:"Modules",value:"modules",icon:"widgets"},
            {displayName:"Module behavior",value:"bar",icon:"tune"},
            {displayName:"Dock",value:"dock",icon:"dock_to_bottom"},
            {displayName:"Sidebars",value:"sidebars",icon:"side_navigation"},
            {displayName:"Popups",value:"popups",icon:"chat_bubble"},
            {displayName:"Live Editor",value:"editor",icon:"edit"},
            {displayName:"Interaction",value:"interaction",icon:"touch_app"},
            {displayName:"Performance",value:"performance",icon:"speed"}].filter(option=>root.sections.includes(option.value))
    }
    SettingsCardSection {
        title:"Audio spectrum";icon:"graphic_eq";settingsTaskSection:"spectrum"
        visible:root.activeSection==="spectrum"
        SettingsGroup {
            ConfigSwitch {
                text:"Audio-driven Screen Edge wave";autoToggle:false
                checked:(Config.options?.abyss?.spectrum?.configured ?? false) ? (Config.options?.abyss?.spectrum?.enabled ?? false) : (Config.options?.bar?.visualizer?.enable ?? false)
                onToggledByUser:checked=>root.spectrumChange("enabled",checked)
            }
            Percent { text:"Audio wave strength";configKey:"abyss.spectrum.strength";fallback:.45;maximum:4 }
            ConfigSelectionArray {
                currentValue:Config.options?.abyss?.spectrum?.edge ?? "bar"
                options:[{displayName:"Bar Edge",value:"bar"},{displayName:"All Edges",value:"all"},
                    {displayName:"Top",value:"top"},{displayName:"Right",value:"right"},{displayName:"Bottom",value:"bottom"},{displayName:"Left",value:"left"}]
                onSelected:value=>Config.setNestedValue("abyss.spectrum.edge",value)
            }
            ConfigSelectionArray {
                currentValue:(Config.options?.abyss?.spectrum?.configured ?? false) ? Config.options?.abyss?.spectrum?.multiMonitorMode : Config.options?.bar?.visualizer?.multiMonitorMode ?? "primary"
                options:[{displayName:"Primary output",value:"primary"},{displayName:"All outputs",value:"all"}]
                onSelected:value=>root.spectrumChange("multiMonitorMode",value)
            }
            SettingsNote { text:"Audio moves the same Screen Edge surface. It shares the existing analyzer, runs only during playback on visible outputs, and clears when paused, hidden or reduced motion is enabled. Interaction waves can remain off." }
        }
    }
    SettingsCardSection {
        title:"Surface";icon:"opacity";settingsTaskSection:"surface"
        visible:root.activeSection==="surface"
        SettingsGroup {
            ConfigSwitch {
                text:"Transparent surfaces";autoToggle:false
                checked:(Config.options?.abyss?.surface?.opacity ?? .78)<.999
                onToggledByUser:checked=>Config.setNestedValue("abyss.surface.opacity",checked ? .78 : 1)
            }
            Percent { text:"Surface opacity";configKey:"abyss.surface.opacity";fallback:.78;minimum:0 }
            Percent { text:"Screen Edge depth";configKey:"abyss.perimeter.thickness";fallback:16;minimum:0;maximum:40 }
            Percent { text:"Curvature";configKey:"abyss.perimeter.radius";fallback:34;minimum:12;maximum:64 }
            Percent { text:"Fusion softness";configKey:"abyss.surface.softness";fallback:24;minimum:4;maximum:48 }
            ConfigSwitch {
                text:"Wallpaper blur";autoToggle:false
                checked:Config.options?.abyss?.effects?.blur?.enabled ?? true
                onToggledByUser:checked=>Config.setNestedValue("abyss.effects.blur.enabled",checked)
            }
            Percent { text:"Blur strength";configKey:"abyss.effects.blur.radius";fallback:10;maximum:24 }
            ConfigSwitch {
                objectName:"abyssPanelOpacityFollow"
                text:"Panel and content opacity follows Screen Edge";autoToggle:false
                checked:(Config.options?.abyss?.content?.opacity ?? -1)<0
                onToggledByUser:checked=>Config.setNestedValue("abyss.content.opacity",checked ? -1 : AbyssStyle.contentOpacity)
            }
            WindowDialogSlider {
                objectName:"abyssPanelOpacity"
                text:"Panel & content opacity";Layout.fillWidth:true;from:0;to:1;stepSize:.01
                value:AbyssStyle.contentOpacity;valueText:Math.round(value*100)+" %"
                onMoved:Config.setNestedValue("abyss.content.opacity",value)
            }
            ConfigSwitch {
                objectName:"abyssPanelBlurFollow"
                text:"Panel blur follows Screen Edge";autoToggle:false
                checked:(Config.options?.abyss?.content?.blurRadius ?? -1)<0
                onToggledByUser:checked=>Config.setNestedValue("abyss.content.blurRadius",checked ? -1 : AbyssStyle.configuredContentBlurRadius)
            }
            WindowDialogSlider {
                objectName:"abyssPanelBlur"
                text:"Panel background blur";Layout.fillWidth:true;from:0;to:24;stepSize:1
                value:AbyssStyle.configuredContentBlurRadius;valueText:Math.round(value)+" px"
                onMoved:Config.setNestedValue("abyss.content.blurRadius",value)
            }
            SettingsNote { text:"Panel backgrounds and content cards share one opacity, including 0. Screen Edge opacity and panel blur remain separate. Performance quality and disabled effects preserve the saved blur radius." }
            ConfigSwitch {
                text:"Refraction (Quality)";autoToggle:false
                checked:Config.options?.abyss?.effects?.refraction?.enabled ?? false
                onToggledByUser:checked=>Config.setNestedValue("abyss.effects.refraction.enabled",checked)
            }
            Percent { text:"Refraction strength";configKey:"abyss.effects.refraction.strength";fallback:6;maximum:16 }
            Percent { text:"Rim highlight";configKey:"abyss.effects.surfaceHighlight";fallback:.45 }
            Percent { text:"Glow";configKey:"abyss.effects.glow.strength";fallback:.08;maximum:.3 }
            RippleButton {
                buttonText:"Use opaque Material appearance";implicitHeight:36;Layout.fillWidth:true
                onClicked:Config.setNestedValues({"abyss.surface.opacity":1,"abyss.content.opacity":1,"abyss.content.blurRadius":0,"abyss.waves.enabled":false,
                    "abyss.effects.blur.enabled":false,"abyss.effects.refraction.enabled":false,
                    "abyss.effects.glow.strength":0,"abyss.effects.surfaceHighlight":0,
                    "abyss.perimeter.radius":Config.options?.appearance?.screenEdge?.radius ?? 25})
            }
        }
    }
    SettingsCardSection {
        title:"Waves";icon:"waves";settingsTaskSection:"waves"
        visible:root.activeSection==="waves"
        SettingsGroup {
            ConfigSwitch {
                text:"Enable waves";autoToggle:false
                checked:Config.options?.abyss?.waves?.enabled ?? false
                onToggledByUser:checked=>Config.setNestedValue("abyss.waves.enabled",checked)
            }
            ConfigSelectionArray {
                currentValue:Config.options?.abyss?.waves?.preset ?? "balanced"
                options:[{displayName:"Calm",value:"calm"},{displayName:"Balanced",value:"balanced"},
                    {displayName:"Fluid",value:"fluid"},{displayName:"Deep",value:"deep"},{displayName:"Custom",value:"custom"}]
                onSelected:value=>{
                    const updates={"abyss.waves.preset":value}
                    if(Wave.presets[value]) Object.keys(Wave.presets[value]).forEach(k=>updates["abyss.waves."+k]=Wave.presets[value][k])
                    Config.setNestedValues(updates)
                }
            }
            AbyssWavePreview {}
            ConfigSwitch {
                text:"Traveling popup waves";autoToggle:false
                description:"Opening and closing a panel sends waves in both directions along the Screen Edges. They share wave size, speed, propagation and strength."
                visible:(Config.options?.abyss?.waves?.preset ?? "balanced") === "custom"
                checked:Config.options?.abyss?.waves?.popupTravel ?? true
                onToggledByUser:checked=>Config.setNestedValue("abyss.waves.popupTravel",checked)
            }
            WindowDialogSlider {
                text:"Surface wave strength";Layout.fillWidth:true;from:0;to:4;stepSize:.01
                visible:(Config.options?.abyss?.waves?.preset ?? "balanced") === "custom"
                value:Wave.bodyStrength(Config.options?.abyss?.waves)
                valueText:Math.round(value*100)+" %"
                onMoved:Config.setNestedValue("abyss.waves.strength",value)
            }
            WindowDialogSlider {
                text:"Breaker / whitewater";Layout.fillWidth:true;from:0;to:1;stepSize:.01
                visible:(Config.options?.abyss?.waves?.preset ?? "balanced") === "custom"
                value:Config.options?.abyss?.waves?.whitewater ?? .65
                valueText:Math.round(value*100)+" %"
                onMoved:Config.setNestedValue("abyss.waves.whitewater",value)
            }
            SettingsNote { text:"Ripples and rounded crests rise above the resting Edge. Whitewater follows moving steep crests, and is disabled with effects or Performance quality." }
            WaveControl { text:"Wave size";parameter:"amplitude" }
            WaveControl { text:"Propagation distance";parameter:"propagation" }
            WaveControl { text:"Wave speed";parameter:"speed" }
            WaveControl { text:"Decay";parameter:"decay" }
            WaveControl { text:"Surface tension";parameter:"tension" }
            WaveControl { text:"Viscosity";parameter:"viscosity" }
            WaveControl { text:"Secondary rebound";parameter:"rebound" }
            WaveControl { text:"Corner propagation";parameter:"corner" }
            ConfigSwitch {
                text:"Occasional idle ripple";autoToggle:false
                visible:(Config.options?.abyss?.waves?.preset ?? "balanced") === "custom"
                checked:Config.options?.abyss?.waves?.idle ?? false
                onToggledByUser:checked=>Config.setNestedValue("abyss.waves.idle",checked)
            }
            SettingsNote { text:"Idle ripples update at 10 Hz and sleep between disturbances. The preview uses the desktop solver; reduced motion also applies here." }
        }
    }
    SettingsCardSection {
        title:"Modules";icon:"widgets";settingsTaskSection:"modules"
        visible:root.activeSection==="modules"
        SettingsGroup {
            GridLayout {
                id: moduleToggleGrid
                Layout.fillWidth: true
                columns: width >= 980 ? 3 : (width >= 620 ? 2 : 1)
                rowSpacing: 4
                columnSpacing: 10

                Repeater {
                    model: FamilyPolicy.abyssPanels.filter(id => id.startsWith("abyss") && !FamilyPolicy.mandatoryPanels("abyss").includes(id))
                    SettingsSwitch {
                        required property string modelData
                        Layout.fillWidth: true
                        autoToggle: false
                        buttonIcon: "water"
                        text: modelData.replace(/^abyss/,"").replace(/([a-z])([A-Z])/g,"$1 $2")
                        checked: (Config.options?.enabledPanels ?? []).includes(modelData)
                        onToggledByUser: checked => {
                            const panels = (Config.options?.enabledPanels ?? []).filter(id => id !== modelData)
                            if (checked) panels.push(modelData)
                            Config.setNestedValue("enabledPanels",panels)
                        }
                    }
                }
            }
            SettingsNote { text:"Place modules on any edge with Live Editor. Their media, resource, clock, tray and workspace settings remain shared." }
            SettingsNote { text:"Modules inherit their Edge size. Enable Custom size in Live Editor to override one module. Per-output sizes, snapping guides and start/center/end groups are available there." }
            AbyssOutputSelector { configPath:"bar.screenList";title:"Module outputs" }
        }
    }
    SettingsCardSection {
        title:"Popups";icon:"chat_bubble";settingsTaskSection:"popups"
        visible:root.activeSection==="popups"
        SettingsGroup {
            SettingsNote {
                text:"Popups retain their existing layouts and follow the edge of their source module. Quick Notes / Timers and Notifications / Activity are Edge Bar surfaces: they participate in the same output field, Edge placement and collision rules while retaining their mature content."
            }
            AbyssPositionSettings {}

            SettingsNote { text:"Quick Notes / Timers Edge Bar size" }
            WindowDialogSlider {
                text:"Quick Notes / Timers width";Layout.fillWidth:true
                from:280;to:720;stepSize:10
                value:Config.options?.quickNotes?.popupWidth ?? 420
                valueText:Math.round(value)+" px"
                onMoved:Config.setNestedValue("quickNotes.popupWidth",value)
            }
            WindowDialogSlider {
                text:"Quick Notes / Timers height";Layout.fillWidth:true
                from:300;to:640;stepSize:10
                value:Config.options?.quickNotes?.popupHeight ?? 300
                valueText:Math.round(value)+" px"
                onMoved:Config.setNestedValue("quickNotes.popupHeight",value)
            }

            SettingsDivider {}

            SettingsNote { text:"Notifications / Activity Edge Bar size" }
            WindowDialogSlider {
                text:"Notifications / Activity width";Layout.fillWidth:true
                from:320;to:760;stepSize:10
                value:Config.options?.notificationCenter?.popupWidth ?? 420
                valueText:Math.round(value)+" px"
                onMoved:Config.setNestedValue("notificationCenter.popupWidth",value)
            }
            WindowDialogSlider {
                text:"Notifications / Activity height";Layout.fillWidth:true
                from:260;to:900;stepSize:10
                value:Config.options?.notificationCenter?.popupHeight ?? 560
                valueText:Math.round(value)+" px"
                onMoved:Config.setNestedValue("notificationCenter.popupHeight",value)
            }

            AbyssOutputSelector { configPath:"sidebar.screenList";title:"Sidebar outputs" }
            AbyssOutputSelector { configPath:"notifications.screenList";title:"Notification outputs" }
        }
    }
    SettingsCardSection {
        title:"Live Editor";icon:"edit";settingsTaskSection:"editor"
        visible:root.activeSection==="editor"
        SettingsGroup {
            SettingsNote { text:"Settings closes while you place modules on the desktop. Done saves; Cancel restores the saved layout. Choose a profile per output or use the layout as the global default." }
        }
    }
    SettingsCardSection {
        title:"Interaction";icon:"touch_app";settingsTaskSection:"interaction"
        visible:root.activeSection==="interaction"
        SettingsGroup {
            Percent { text:"Hover response";configKey:"abyss.waves.hover";fallback:1 }
            Percent { text:"Press response";configKey:"abyss.waves.press";fallback:1 }
            Percent { text:"Opening response";configKey:"abyss.waves.open";fallback:1 }
            Percent { text:"Closing response";configKey:"abyss.waves.close";fallback:1 }
            Percent { text:"Drag response";configKey:"abyss.waves.drag";fallback:1 }
            Percent { text:"Motion intensity";configKey:"abyss.motion.intensity";fallback:.6 }
            ConfigSwitch {
                text:"Reduce animations (all families)";autoToggle:false
                checked:Config.options?.performance?.reduceAnimations ?? false
                onToggledByUser:checked=>Config.setNestedValue("performance.reduceAnimations",checked)
            }
        }
    }
    SettingsCardSection {
        title:"Performance";icon:"speed";settingsTaskSection:"performance"
        visible:root.activeSection==="performance"
        SettingsSwitch {
            text:"Follow power profile"
            description:"Use Performance in Power Saver, Balanced in Balanced, and Quality in Performance."
            autoToggle:false;checked:Config.options?.abyss?.autoQuality ?? false
            onToggledByUser:checked=>Config.setNestedValue("abyss.autoQuality",checked)
        }
        SettingsGroup {
            ConfigSelectionArray {
                enabled:!(Config.options?.abyss?.autoQuality ?? false)
                currentValue:Config.options?.abyss?.quality ?? "balanced"
                options:[{displayName:"Performance",value:"performance"},{displayName:"Balanced",value:"balanced"},{displayName:"Quality",value:"quality"}]
                onSelected:value=>Config.setNestedValue("abyss.quality",value)
            }
            SettingsNote { text:"Performance uses 128 wave samples. Balanced and Quality use 256. The solver stops after settling and while the output is hidden or locked. Wallpaper glass uses a static image; application pixels are not captured." }
            ConfigSwitch {
                text:"Visible during fullscreen";autoToggle:false
                checked:Config.options?.abyss?.perimeter?.visibleInFullscreen ?? false
                onToggledByUser:checked=>Config.setNestedValue("abyss.perimeter.visibleInFullscreen",checked)
            }
        }
    }
}
