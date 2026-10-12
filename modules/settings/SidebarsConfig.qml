import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    settingsPageIndex: embedded ? 2 : 23
    settingsPageName: Translation.tr("Sidebars")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"

    property string activeSection: "general"

    SettingsTaskNavigator {
        icon: "side_navigation"
        title: Translation.tr("Sidebars")
        description: Translation.tr("Sidebar layout, widgets, media and edge behavior.")
        summary: Translation.tr("General \u00b7 Left \u00b7 Right \u00b7 Media \u00b7 Opening")
        currentValue: root.activeSection
        onSelected: value => root.activeSection = value
        options: [
            { displayName: Translation.tr("General"), icon: "tune", value: "general" },
            { displayName: Translation.tr("Left sidebar"), icon: "first_page", value: "left" },
            { displayName: Translation.tr("Right sidebar"), icon: "last_page", value: "right" },
            { displayName: Translation.tr("Media & content"), icon: "music_note", value: "media" },
            { displayName: Translation.tr("Opening"), icon: "swipe", value: "open" }
        ]
    }

    component SidebarSize: ContentSubsection {
        id:sizing
        required property string role
        readonly property var state:ShellLayoutController.currentState(role,"")
        WindowDialogSlider {
            text:"Width";Layout.fillWidth:true;from:320;to:900;stepSize:1
            value:sizing.state.width;valueText:Math.round(value)+" px"
            onMoved:ShellLayoutController.setProperty(sizing.role,"thickness",value,"")
        }
        ConfigSelectionArray {
            currentValue:sizing.state.sizeMode === "custom" ? "custom" : "fit"
            options:[{displayName:"Fit content",value:"fit"},{displayName:"Custom height",value:"custom"}]
            onSelected:value=>ShellLayoutController.setProperty(sizing.role,"sizeMode",value,"")
        }
        WindowDialogSlider {
            text:"Height";Layout.fillWidth:true;from:320;to:2160;stepSize:1
            visible:sizing.state.sizeMode === "custom"
            value:sizing.state.customHeight;valueText:Math.round(value)+" px"
            onMoved:ShellLayoutController.setProperty(sizing.role,"height",value,"")
        }
    }
    SettingsCardSection {
        settingsTaskSection: "general"
        visible: root.isIiActive && root.activeSection === "general"
        expanded: true
        icon: "tune"
        title: Translation.tr("General")

        SettingsGroup {
            SidebarSize { role:"featureSidebar";title:"Left Sidebar size" }
            SidebarSize { role:"systemSidebar";title:"Right Sidebar size" }
            ContentSubsection {
                title: Translation.tr("General")

                SettingsSwitch {
                    buttonIcon: "fit_screen"
                    text: Translation.tr("Fit left sidebar to content")
                    checked: Config.options.sidebar?.collapseWidgetsTab ?? false
                    onCheckedChanged: Config.setNestedValue("sidebar.collapseWidgetsTab", checked)
                    StyledToolTip {
                        text: Translation.tr("Shrink the left sidebar to a tab's preferred content height when available")
                    }
                }

                SidebarHeightPreview {
                    Layout.fillWidth: true
                }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Sidebar content stays loaded between openings.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.WordWrap
            }

            SettingsSwitch {
                buttonIcon: "folder_open"
                text: Translation.tr("Open folder after wallpaper download")
                checked: Config.options.sidebar?.openFolderOnDownload ?? false
                onCheckedChanged: Config.setNestedValue("sidebar.openFolderOnDownload", checked)
                StyledToolTip {
                    text: Translation.tr("Open the file manager after downloading a wallpaper")
                }
            }
            }

            ContentSubsection {
                title: Translation.tr("Arrange")
                tooltip: Translation.tr("Arrange sidebar sections, tab order and elastic heights")

                SidebarLayoutEditor {
                    Layout.fillWidth: true
                }
            }

        }
    }

    SettingsCardSection {
        settingsTaskSection: "left"
        visible: root.isIiActive && root.activeSection === "left"
        expanded: true
        icon: "first_page"
        title: Translation.tr("Left sidebar")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Left Sidebar")
                tooltip: Translation.tr("Choose which tabs appear in the left sidebar")

                SettingsSwitch {
                    buttonIcon: "translate"
                    text: Translation.tr("Translator")
                    checked: Config.options.sidebar?.translator?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("sidebar.translator.enable", checked)
                    StyledToolTip {
                        text: Translation.tr("Translate text between languages")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "newspaper"
                    text: Translation.tr("News")
                    checked: Config.options.sidebar?.news?.enable ?? true
                    onCheckedChanged: Config.setNestedValue("sidebar.news.enable", checked)
                    StyledToolTip {
                        text: Translation.tr("Local and topic headlines from Google News")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "calendar_month"
                    text: Translation.tr("Anime Schedule")
                    checked: Config.options.sidebar?.animeSchedule?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("sidebar.animeSchedule.enable", checked)
                    StyledToolTip {
                        text: Translation.tr("View anime airing schedule, seasonal and top anime")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "build"
                    text: Translation.tr("Tools")
                    checked: Config.options.sidebar?.tools?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("sidebar.tools.enable", checked)
                    StyledToolTip {
                        text: Translation.tr("Niri debug options and quick actions")
                    }
                }

                // DISABLED: webapps — requires quickshell-webengine rebuild
                // SettingsSwitch {
                //     buttonIcon: "extension"
                //     text: Translation.tr("Web Apps")
                //     checked: Config.options?.sidebar?.plugins?.enable ?? false
                //     onCheckedChanged: Config.setNestedValue("sidebar.plugins.enable", checked)
                //     StyledToolTip {
                //         text: Translation.tr("Embed web apps like Discord, YouTube Music and more in the sidebar (requires quickshell-webengine)")
                //     }
                // }
            }

        }
    }

    SettingsCardSection {
        settingsTaskSection: "right"
        visible: root.isIiActive && root.activeSection === "right"
        expanded: true
        icon: "last_page"
        title: Translation.tr("Right sidebar")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Right sidebar header")
                tooltip: Translation.tr("Look of the system section at the top of the right sidebar")

                ConfigSelectionArray {
                    Layout.fillWidth: false
                    currentValue: Config.options?.sidebar?.right?.headerStyle ?? "profile"
                    onSelected: newValue => {
                        Config.setNestedValue("sidebar.right.headerStyle", newValue);
                    }
                    options: [
                        { displayName: Translation.tr("Profile card"), icon: "account_box", value: "profile" },
                        { displayName: Translation.tr("Classic"), icon: "view_agenda", value: "classic" }
                    ]
                }

                ContentSubsectionLabel {
                    visible: (Config.options?.sidebar?.right?.headerStyle ?? "profile") === "profile"
                    text: Translation.tr("Banner")
                }

                ConfigSelectionArray {
                    Layout.fillWidth: false
                    visible: (Config.options?.sidebar?.right?.headerStyle ?? "profile") === "profile"
                    currentValue: Config.options?.sidebar?.right?.headerBanner ?? "wallpaper"
                    onSelected: newValue => {
                        Config.setNestedValue("sidebar.right.headerBanner", newValue);
                    }
                    options: [
                        { displayName: Translation.tr("Wallpaper"), icon: "wallpaper", value: "wallpaper" },
                        { displayName: Translation.tr("Custom media"), icon: "perm_media", value: "custom" },
                        { displayName: Translation.tr("Solid"), icon: "format_color_fill", value: "solid" },
                        { displayName: Translation.tr("None"), icon: "block", value: "none" }
                    ]
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: (Config.options?.sidebar?.right?.headerStyle ?? "profile") === "profile"
                        && (Config.options?.sidebar?.right?.headerBanner ?? "wallpaper") === "custom"

                    StyledText {
                        Layout.fillWidth: true
                        text: (Config.options?.sidebar?.right?.headerBannerPath ?? "").length > 0
                            ? Directories.shortHomePath(Config.options.sidebar.right.headerBannerPath)
                            : Translation.tr("No media selected")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideMiddle
                        wrapMode: Text.NoWrap
                    }

                    RippleButtonWithIcon {
                        materialIcon: "folder_open"
                        mainText: Translation.tr("Choose")
                        onClicked: bannerImageDialog.open()
                    }
                }

                FileDialog {
                    id: bannerImageDialog
                    title: Translation.tr("Choose header media")
                    fileMode: FileDialog.OpenFile
                    nameFilters: [
                        Translation.tr("Images and animations") + " (*.png *.jpg *.jpeg *.webp *.bmp *.avif *.gif *.mp4 *.webm *.mkv *.avi *.mov)",
                        Translation.tr("All files") + " (*)"
                    ]
                    onAccepted: Config.setNestedValue("sidebar.right.headerBannerPath",
                        FileUtils.trimFileProtocol(String(selectedFile)))
                }

                SettingsNativeDialogGuard {
                    dialog: bannerImageDialog
                    dialogKey: "sidebar-header-media"
                }
            }

            ContentSubsection {
                id: rightSidebarWidgets
                title: Translation.tr("Right Sidebar")
                tooltip: Translation.tr("Toggle which widgets appear in the right sidebar")

                readonly property var defaults: ["calculator", "sysmon"]

                function isEnabled(widgetId) {
                    return (Config.options?.sidebar?.right?.enabledWidgets ?? defaults).includes(widgetId)
                }

                function setWidget(widgetId, active) {
                    _log(`[RightSidebar] setWidget(${widgetId}, ${active})`)
                    let current = [...(Config.options?.sidebar?.right?.enabledWidgets ?? defaults)]
                    _log(`[RightSidebar] Current widgets:`, JSON.stringify(current))

                    const index = current.indexOf(widgetId)
                    // includes() uses SameValueZero while indexOf() uses strict
                    // equality. Preserve the old malformed NaN behavior without
                    // repeating a full membership scan for normal widget ids.
                    const included = index !== -1
                        || (widgetId !== widgetId && current.includes(widgetId))
                    if (active && !included) {
                        current.push(widgetId)
                        _log(`[RightSidebar] Adding ${widgetId}, new array:`, JSON.stringify(current))
                        Config.setNestedValue("sidebar.right.enabledWidgets", current)
                    } else if (!active && included) {
                        current.splice(index, 1)
                        _log(`[RightSidebar] Removing ${widgetId}, new array:`, JSON.stringify(current))
                        Config.setNestedValue("sidebar.right.enabledWidgets", current)
                    } else {
                        _log(`[RightSidebar] No change needed`)
                    }
                }

                SettingsSwitch {
                    buttonIcon: "calculate"
                    text: Translation.tr("Calculator")
                    Component.onCompleted: checked = rightSidebarWidgets.isEnabled("calculator")
                    onClicked: {
                        rightSidebarWidgets.setWidget("calculator", checked)
                    }
                }

                SettingsSwitch {
                    buttonIcon: "monitor_heart"
                    text: Translation.tr("System Monitor")
                    Component.onCompleted: checked = rightSidebarWidgets.isEnabled("sysmon")
                    onClicked: {
                        rightSidebarWidgets.setWidget("sysmon", checked)
                    }
                }

            }

            ContentSubsection {
                title: Translation.tr("Quick toggles")

                ConfigSelectionArray {
                    Layout.fillWidth: false
                    currentValue: Config.options.sidebar.quickToggles.style
                    onSelected: newValue => {
                        Config.setNestedValue("sidebar.quickToggles.style", newValue);
                    }
                    options: [
                        { displayName: Translation.tr("Classic"), icon: "password_2", value: "classic" },
                        { displayName: Translation.tr("Android"), icon: "action_key", value: "android" }
                    ]
                }

                ConfigSpinBox {
                    enabled: Config.options.sidebar.quickToggles.style === "android"
                    icon: "splitscreen_left"
                    text: Translation.tr("Columns")
                    value: Config.options.sidebar.quickToggles.android.columns
                    from: 1
                    to: 8
                    stepSize: 1
                    onValueChanged: {
                        Config.setNestedValue("sidebar.quickToggles.android.columns", value);
                    }
                    StyledToolTip {
                        text: Translation.tr("Number of columns for the Android-style quick settings grid")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Sliders")

                SettingsSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.sidebar.quickSliders.enable
                    onCheckedChanged: {
                        Config.setNestedValue("sidebar.quickSliders.enable", checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Show volume/brightness/mic sliders in the sidebar")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "brightness_6"
                    text: Translation.tr("Brightness")
                    enabled: Config.options.sidebar.quickSliders.enable
                    checked: Config.options.sidebar.quickSliders.showBrightness
                    onCheckedChanged: {
                        Config.setNestedValue("sidebar.quickSliders.showBrightness", checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Show brightness slider")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Volume")
                    enabled: Config.options.sidebar.quickSliders.enable
                    checked: Config.options.sidebar.quickSliders.showVolume
                    onCheckedChanged: {
                        Config.setNestedValue("sidebar.quickSliders.showVolume", checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Show volume slider")
                    }
                }

                SettingsSwitch {
                    buttonIcon: "mic"
                    text: Translation.tr("Microphone")
                    enabled: Config.options.sidebar.quickSliders.enable
                    checked: Config.options.sidebar.quickSliders.showMic
                    onCheckedChanged: {
                        Config.setNestedValue("sidebar.quickSliders.showMic", checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Show microphone input level slider")
                    }
                }
            }

        }
    }

    SettingsCardSection {
        settingsTaskSection: "media"
        visible: root.isIiActive && root.activeSection === "media"
        expanded: true
        icon: "music_note"
        title: Translation.tr("Media & content")

        SettingsGroup {

            ContentSubsection {
                title: Translation.tr("Anime Schedule")
                visible: Config.options.sidebar?.animeSchedule?.enable ?? false

                SettingsSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Show NSFW")
                    checked: Config.options.sidebar?.animeSchedule?.showNsfw ?? false
                    onCheckedChanged: Config.setNestedValue("sidebar.animeSchedule.showNsfw", checked)
                    StyledToolTip {
                        text: Translation.tr("Include adult-rated anime in results")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    MaterialSymbol {
                        text: "play_circle"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: Translation.tr("Watch site")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }

                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: "https://9animetv.to/search?keyword=%s"
                            text: Config.options.sidebar?.animeSchedule?.watchSite ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurface
                            placeholderTextColor: Appearance.colors.colSubtext
                            background: Rectangle {
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                border.width: parent.activeFocus ? 2 : 1
                                border.color: parent.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                            }
                            onTextEdited: Config.setNestedValue("sidebar.animeSchedule.watchSite", text)

                            StyledToolTip {
                                text: Translation.tr("Custom streaming site URL. Use %s for search query.")
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Gelbooru")
                visible: (Config.options?.policies?.weeb ?? 0) !== 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Gelbooru currently requires account API credentials for API access.")
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                ConfigRow {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("User ID")
                        text: Config.options?.sidebar?.booru?.gelbooru?.userId ?? ""
                        onEditingFinished: Config.setNestedValue("sidebar.booru.gelbooru.userId", text.trim())
                    }

                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("API key")
                        echoMode: TextInput.Password
                        text: Config.options?.sidebar?.booru?.gelbooru?.apiKey ?? ""
                        onEditingFinished: Config.setNestedValue("sidebar.booru.gelbooru.apiKey", text.trim())
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Booru download paths")
                visible: (Config.options?.policies?.weeb ?? 0) !== 0

                ContentSubsectionLabel {
                    text: Translation.tr("SFW download folder (empty = wallpapers dir)")
                }
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Directories.wallpapersPath
                    text: Config.options?.sidebar?.booru?.downloadPath?.sfw ?? ""
                    onEditingFinished: Config.setNestedValue("sidebar.booru.downloadPath.sfw", text)
                }

                ContentSubsectionLabel {
                    text: Translation.tr("NSFW download folder (empty = wallpapers/pepper)")
                }
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Directories.wallpapersPath + "/pepper"
                    text: Config.options?.sidebar?.booru?.downloadPath?.nsfw ?? ""
                    onEditingFinished: Config.setNestedValue("sidebar.booru.downloadPath.nsfw", text)
                }
            }

        }
    }

    SettingsCardSection {
        settingsTaskSection: "open"
        visible: root.isIiActive && root.activeSection === "open"
        expanded: true
        icon: "swipe"
        title: Translation.tr("Opening")

        SettingsGroup {
            ContentSubsection {
                title: Translation.tr("Side edge open")
                tooltip: Config.options?.panelFamily === "abyss" ? "Hover a side Screen Edge; enter the sidebar to keep it open." : Translation.tr("Open the left or right sidebar by touching that screen edge")

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "dock_to_left"
                        text: Translation.tr("Hover screen edges")
                        checked: Config.options?.panelFamily === "abyss" ? (Config.options?.abyss?.sidebars?.hoverEnabled ?? true) : (Config.options?.sidebar?.edgeOpen?.enable ?? false)
                        onCheckedChanged: Config.setNestedValue(Config.options?.panelFamily === "abyss" ? "abyss.sidebars.hoverEnabled" : "sidebar.edgeOpen.enable", checked)
                    }
                    ConfigSpinBox {
                        icon: "width"
                        text: Translation.tr("Trigger width (px)")
                        value: Config.options?.sidebar?.edgeOpen?.regionWidth ?? 2
                        from: 1
                        to: 12
                        stepSize: 1
                        enabled: Config.options?.panelFamily === "abyss" ? (Config.options?.abyss?.sidebars?.hoverEnabled ?? true) : (Config.options?.sidebar?.edgeOpen?.enable ?? false)
                        opacity: enabled ? 1 : 0.5
                        onValueChanged: Config.setNestedValue("sidebar.edgeOpen.regionWidth", value)
                    }
                }
            }

            ContentSubsection {
                visible: Config.options?.panelFamily !== "abyss"
                title: Translation.tr("Corner open")
                tooltip: Translation.tr("Open sidebars from screen corners.")
                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "check"
                        text: Translation.tr("Enable")
                        checked: Config.options.sidebar.cornerOpen.enable
                        onCheckedChanged: {
                            Config.setNestedValue("sidebar.cornerOpen.enable", checked);
                        }
                        StyledToolTip {
                            text: Translation.tr("Allow opening sidebars by interacting with screen corners")
                        }
                    }
                }
                SettingsSwitch {
                    buttonIcon: "highlight_mouse_cursor"
                    text: Translation.tr("Hover to trigger")
                    checked: Config.options.sidebar.cornerOpen.clickless
                    onCheckedChanged: {
                        Config.setNestedValue("sidebar.cornerOpen.clickless", checked);
                    }

                    StyledToolTip {
                        text: Translation.tr("When this is off you'll have to click")
                    }
                }
                ConfigRow {
                    SettingsSwitch {
                        enabled: !Config.options.sidebar.cornerOpen.clickless
                        text: Translation.tr("Force hover open at absolute corner")
                        checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                        onCheckedChanged: {
                            Config.setNestedValue("sidebar.cornerOpen.clicklessCornerEnd", checked);
                        }

                        StyledToolTip {
                            text: Translation.tr("Hover the corner tip; scroll controls remain available elsewhere.")
                        }
                    }
                    ConfigSpinBox {
                        icon: "arrow_cool_down"
                        text: Translation.tr("with vertical offset")
                        value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                        from: 0
                        to: 20
                        stepSize: 1
                        onValueChanged: {
                            Config.setNestedValue("sidebar.cornerOpen.clicklessCornerVerticalOffset", value);
                        }
                        StyledToolTip {
                            text: Translation.tr("Offset corner hover vertically to avoid horizontal-edge triggers.")
                        }
                    }
                }

                ConfigRow {
                    uniform: true
                    SettingsSwitch {
                        buttonIcon: "vertical_align_bottom"
                        text: Translation.tr("Place at bottom")
                        checked: Config.options.sidebar.cornerOpen.bottom
                        onCheckedChanged: {
                            Config.setNestedValue("sidebar.cornerOpen.bottom", checked);
                        }

                        StyledToolTip {
                            text: Translation.tr("Place the corners to trigger at the bottom")
                        }
                    }
                    SettingsSwitch {
                        buttonIcon: "unfold_more_double"
                        text: Translation.tr("Value scroll")
                        checked: Config.options.sidebar.cornerOpen.valueScroll
                        onCheckedChanged: {
                            Config.setNestedValue("sidebar.cornerOpen.valueScroll", checked);
                        }

                        StyledToolTip {
                            text: Translation.tr("Brightness and volume")
                        }
                    }
                }
                SettingsSwitch {
                    buttonIcon: "visibility"
                    text: Translation.tr("Visualize region")
                    checked: Config.options.sidebar.cornerOpen.visualize
                    onCheckedChanged: {
                        Config.setNestedValue("sidebar.cornerOpen.visualize", checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Show a colored overlay indicating the corner trigger areas (debug)")
                    }
                }
                ConfigRow {
                    ConfigSpinBox {
                        icon: "arrow_range"
                        text: Translation.tr("Region width")
                        value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                        from: 1
                        to: 300
                        stepSize: 1
                        onValueChanged: {
                            Config.setNestedValue("sidebar.cornerOpen.cornerRegionWidth", value);
                        }
                        StyledToolTip {
                            text: Translation.tr("Horizontal size of the active corner area")
                        }
                    }
                    ConfigSpinBox {
                        icon: "height"
                        text: Translation.tr("Region height")
                        value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                        from: 1
                        to: 300
                        stepSize: 1
                        onValueChanged: {
                            Config.setNestedValue("sidebar.cornerOpen.cornerRegionHeight", value);
                        }
                        StyledToolTip {
                            text: Translation.tr("Vertical size of the active corner area")
                        }
                    }
                }
            }
        }
    }

}
