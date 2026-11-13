pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks

FocusScope {
    id:root
    objectName:"wallpaperLauncherContent"
    property string outputName:""
    property string monitorName:outputName
    property bool embedded:false
    property string browseFolder:Config.options?.wallpapers?.directory ?? ""
    property string selectedColor:""
    property bool favouritesOnly:false
    readonly property var colorPalette:[
        {id:"",label:"All",swatch:"transparent"},
        {id:"red",label:"Red",swatch:"#ef4444"},
        {id:"orange",label:"Orange",swatch:"#f97316"},
        {id:"yellow",label:"Yellow",swatch:"#eab308"},
        {id:"green",label:"Green",swatch:"#22c55e"},
        {id:"cyan",label:"Cyan",swatch:"#06b6d4"},
        {id:"blue",label:"Blue",swatch:"#3b82f6"},
        {id:"purple",label:"Purple",swatch:"#a855f7"},
        {id:"pink",label:"Pink",swatch:"#ec4899"},
        {id:"monochrome",label:"Monochrome",swatch:"#94a3b8"}
    ]
    readonly property string mode:GlobalStates.wallpaperLauncherMode
    readonly property string displayMode:mode
    readonly property var entries:mode==="animated" ? library.animatedEntries : library.staticEntries
    readonly property string selectionTarget:Wallpapers.currentSelectionTarget()
    readonly property string selectionMonitorName:(Config.options?.background?.multiMonitor?.enable ?? false) ? monitorName : ""
    readonly property string currentWallpaperPath:Wallpapers.currentWallpaperPathForTarget(selectionTarget,selectionMonitorName)
    readonly property int currentIndex:carousel.currentIndex
    readonly property int count:carousel.count
    readonly property string selectedPath:carousel.selectedPath
    readonly property bool loading:library.scanning
    readonly property real padding:embedded ? 0 : AbyssStyle.contentPadding
    implicitWidth:1000
    implicitHeight:288+padding*2
    focus:true
    signal closeRequested()
    function _extraScanRoots():var {
        if (browseFolder) return []
        const candidates = []
        const defaultRoot = FileUtils.trimFileProtocol(Directories.wallpapersPath)
        const curDir = FileUtils.trimFileProtocol(FileUtils.parentDirectory(currentWallpaperPath))
        if (curDir && curDir !== defaultRoot) {
            const parentDir = FileUtils.trimFileProtocol(FileUtils.parentDirectory(curDir))
            const genericDirs = [
                "/",
                Directories.homePath,
                Directories.picturesPath,
                Directories.documentsPath,
                Directories.videosPath,
                Directories.downloadsPath,
                `${Directories.homePath}/Shared_Documents`
            ]
            const parentName = FileUtils.folderNameForPath(parentDir).toLowerCase()
            const curName = FileUtils.folderNameForPath(curDir)
            if (parentDir && !parentDir.startsWith("/tmp") && !genericDirs.includes(parentDir)
                    && (parentName.includes("wallpaper") || /^\d+[_\-\s]/.test(curName)))
                candidates.push(parentDir)
            candidates.push(curDir)
        }
        if (Wallpapers.effectiveDirectory)
            candidates.push(Wallpapers.effectiveDirectory)
        return candidates
    }
    function refreshLibrary(force=false):void {
        library.refresh(browseFolder || Directories.wallpapersPath,root._extraScanRoots(),force)
    }
    function setMode(nextMode:string):void {
        if(!["static","animated"].includes(nextMode))return
        GlobalStates.wallpaperLauncherMode=nextMode
        GlobalStates.wallpaperLauncherSearchText=""
        if(typeof root!=="undefined")root.focusPrimarySurface()
        Qt.callLater(carousel.syncCurrentIndexAndPreview)
    }
    function focusPrimarySurface():void {
        search.focus=false
        root.forceActiveFocus()
    }
    function toggleColorFilter(colorId:string):void {
        if (colorId)
            library.ensureColorTags()
        root.selectedColor = (root.selectedColor === colorId) ? "" : colorId
        root.focusPrimarySurface()
    }
    function applyPath(path:string):void {
        if(!path)return
        Wallpapers.commitWallpaperPreview(path)
        Wallpapers.applySelectionTarget(path,selectionTarget,Appearance.m3colors.darkmode,selectionMonitorName)
        GlobalStates.wallpaperLauncherOpen=false
        closeRequested()
    }
    function moveSelection(delta:int):void {carousel.moveSelection(delta)}
    function activateCurrent():void {carousel.activateCurrent()}
    // Compatibility IPC names select the single presentation.
    function openGrid():void {folderPicker.open()}
    function statusJson():string {
        return JSON.stringify({open:GlobalStates.wallpaperLauncherOpen,style:"caelestia",mode:mode,index:currentIndex,count:count,path:selectedPath,target:selectionTarget,monitor:selectionMonitorName,previewPath:Wallpapers.internalPreviewPath,previewMonitor:Wallpapers.internalPreviewMonitor,awwwPreview:AwwwBackend.previewActive})
    }
    IpcHandler {
        target:"wallpaperLauncher"
        function next():void {root.moveSelection(1)}
        function previous():void {root.moveSelection(-1)}
        function applyCurrent():void {root.activateCurrent()}
        function status():string {return root.statusJson()}
    }
    onBrowseFolderChanged:if(GlobalStates.wallpaperLauncherOpen)refreshLibrary(true)
    onVisibleChanged:if(visible)Qt.callLater(root.focusPrimarySurface)
    onEnabledChanged:if(enabled)Qt.callLater(root.focusPrimarySurface)
    Component.onCompleted:{if(GlobalStates.wallpaperLauncherOpen){refreshLibrary(true);Qt.callLater(()=>{root.focusPrimarySurface();carousel.syncCurrentIndexAndPreview()})}}
    Component.onDestruction:GlobalStates.setSettingsNativeDialogVisible("wallpaperLauncherFolder",false)
    Connections {
        target:GlobalStates
        function onWallpaperLauncherOpenChanged():void {if(GlobalStates.wallpaperLauncherOpen){root.refreshLibrary(true);Qt.callLater(root.focusPrimarySurface)}}
    }
    FolderDialog {
        id:folderPicker
        title:"Wallpaper folder"
        currentFolder:browseFolder ? "file://"+browseFolder : "file://"+Directories.wallpapersPath
        onAccepted:{
            const chosen=FileUtils.trimFileProtocol(String(selectedFolder))
            root.browseFolder=chosen
            Config.setNestedValue("wallpapers.directory",chosen)
        }
        onVisibleChanged:GlobalStates.setSettingsNativeDialogVisible("wallpaperLauncherFolder",visible)
    }
    WallpaperLibrary {id:library}
    Rectangle {anchors.fill:parent;visible:!root.embedded;radius:18;color:AbyssStyle.surface}
    ColumnLayout {
        anchors.fill:parent;anchors.margins:root.padding;spacing:12
        Item {
            Layout.fillWidth:true;Layout.fillHeight:true
            Rectangle {
                id:colorFilterBar
                objectName:"wallpaperColorFilterBar"
                anchors.top:parent.top
                anchors.horizontalCenter:parent.horizontalCenter
                z:5
                width:264
                height:26
                radius:13
                color:Qt.alpha(AbyssStyle.surfaceRaised,.78)
                border.width:1
                border.color:Qt.alpha(AbyssStyle.textColor,.08)
                Row {
                    id:colorRow
                    anchors.centerIn:parent
                    spacing:5
                    Repeater {
                        model:root.colorPalette
                        delegate:Item {
                            id:swatchDelegate
                            required property var modelData
                            readonly property bool isAll:modelData.id===""
                            readonly property bool active:root.selectedColor===modelData.id
                            objectName:"wallpaperColorSwatch_"+(modelData.id || "all")
                            width:isAll ? 36 : 18
                            height:18
                            Rectangle {
                                anchors.centerIn:parent
                                width:swatchDelegate.isAll ? 36 : (swatchDelegate.active ? 16 : 14)
                                height:swatchDelegate.isAll ? 18 : (swatchDelegate.active ? 16 : 14)
                                radius:height/2
                                color:swatchDelegate.isAll
                                    ? (swatchDelegate.active ? AbyssStyle.accent : Qt.alpha(AbyssStyle.surface,.8))
                                    : swatchDelegate.modelData.swatch
                                border.width:swatchDelegate.active ? 2 : 1
                                border.color:swatchDelegate.active
                                    ? AbyssStyle.textColor
                                    : Qt.alpha(AbyssStyle.textColor,.22)
                                AbyssLabel {
                                    anchors.centerIn:parent
                                    visible:swatchDelegate.isAll
                                    text:Translation.tr("All")
                                    font.pixelSize:10
                                    font.weight:swatchDelegate.active ? Font.DemiBold : Font.Medium
                                    color:swatchDelegate.active ? AbyssStyle.textColor : AbyssStyle.textColorMuted
                                }
                                MaterialSymbol {
                                    anchors.centerIn:parent
                                    visible:!swatchDelegate.isAll && swatchDelegate.active
                                    text:"check"
                                    iconSize:10
                                    color:AbyssStyle.textColor
                                }
                            }
                            MouseArea {
                                id:swatchMouse
                                anchors.fill:parent
                                cursorShape:Qt.PointingHandCursor
                                onClicked:root.toggleColorFilter(swatchDelegate.modelData.id)
                            }
                        }
                    }
                }
            }
            WallpaperLauncherList {
                id:carousel;objectName:"wallpaperCarousel"
                anchors.centerIn:parent;anchors.verticalCenterOffset:12;width:parent.width;height:implicitHeight
                cardWidth:Math.min(288,Math.max(150,parent.width/4.2))
                maxVisibleItems:Math.max(1,Math.min(5,Math.floor(parent.width/(cardWidth*.8))))
                entries:root.entries;fallbackEntries:(Config.options?.background?.enableAnimation ?? true) ? (root.mode==="animated" ? library.staticEntries : library.animatedEntries) : [];searchText:search.text;selectedColor:root.selectedColor;favouritesOnly:root.favouritesOnly;colorTagsByPath:library.colorTagsByPath;currentWallpaperPath:root.currentWallpaperPath;monitorName:root.selectionMonitorName
                onApplyRequested:path=>root.applyPath(path)
            }
            LoadingText {anchors.centerIn:parent;visible:carousel.count===0 && root.loading}
            AbyssLabel {anchors.centerIn:parent;visible:carousel.count===0 && !root.loading;text:"No matching wallpapers"}
        }
        Item {
            Layout.fillWidth:true;Layout.preferredHeight:44
            Rectangle {anchors.fill:parent;radius:22;color:Qt.alpha(AbyssStyle.surfaceRaised,.72)}
            RowLayout {
                anchors.fill:parent;anchors.leftMargin:10;anchors.rightMargin:5;spacing:4
                MaterialSymbol {objectName:"wallpaperSearchIcon";text:"search";iconSize:20;color:AbyssStyle.textColorMuted;Layout.alignment:Qt.AlignVCenter}
                AbyssSearchField {
                    id:search;objectName:"wallpaperSearch";Layout.fillWidth:true
                    placeholderText:Translation.tr("Search wallpapers");background:Item {}
                    text:GlobalStates.wallpaperLauncherSearchText
                    onTextChanged:GlobalStates.wallpaperLauncherSearchText=text
                    onAccepted:root.activateCurrent()
                    Keys.onDownPressed:{root.moveSelection(1);root.focusPrimarySurface()}
                    Keys.onUpPressed:{root.moveSelection(-1);root.focusPrimarySurface()}
                    Keys.onEscapePressed:{
                        if (search.text.length > 0) {
                            search.text = ""
                            root.focusPrimarySurface()
                        } else {
                            root.focusPrimarySurface()
                            GlobalStates.wallpaperLauncherOpen = false
                        }
                    }
                }
                AbyssButton {objectName:"wallpaperFavouritesFilter";outlined:root.favouritesOnly;glyph:"favorite";description:root.favouritesOnly ? "Show all wallpapers" : "Show favourite wallpapers";onClicked:{root.favouritesOnly=!root.favouritesOnly;root.focusPrimarySurface()}}
                AbyssButton {objectName:"wallpaperMode";outlined:false;glyph:root.mode==="static" ? "image" : "movie";description:root.mode==="static" ? "Show animated wallpapers" : "Show images";onClicked:root.setMode(root.mode==="static" ? "animated" : "static")}
                AbyssButton {objectName:"wallpaperFolder";outlined:false;glyph:"folder_open";description:root.browseFolder.length > 0 ? FileUtils.folderNameForPath(root.browseFolder) : "Choose wallpaper folder";onClicked:folderPicker.open()}
                AbyssButton {objectName:"wallpaperRefresh";outlined:false;glyph:"refresh";description:"Refresh wallpapers";enabled:!root.loading;onClicked:root.refreshLibrary(true)}
                AbyssButton {objectName:"wallpaperClose";outlined:false;glyph:"close";description:"Close wallpaper selector";onClicked:GlobalStates.wallpaperLauncherOpen=false}
            }
        }

    }
    Keys.onPressed:event=>{
        {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        const alt = (event.modifiers & Qt.AltModifier) !== 0
        const keyText = String(event.text ?? "").toLowerCase()
        if (event.key === Qt.Key_Escape) {
            if (search.activeFocus && search.text.length > 0) {
                search.text = ""
                if (typeof root !== "undefined") root.focusPrimarySurface()
            } else {
                if (typeof root !== "undefined") root.focusPrimarySurface()
                GlobalStates.wallpaperLauncherOpen = false
            }
            event.accepted = true
        } else if ((ctrl && ((Qt.Key_F !== undefined && event.key === Qt.Key_F) || keyText === "f"))
                || (!search.activeFocus && !ctrl && !alt && ((Qt.Key_Slash !== undefined && event.key === Qt.Key_Slash) || event.text === "/"))) {
            search.forceActiveFocus()
            event.accepted = true
        } else if (ctrl && ((Qt.Key_D !== undefined && event.key === Qt.Key_D) || keyText === "d")) {
            if (typeof root !== "undefined" && root.selectedPath)
                Wallpapers.toggleFavourite(root.selectedPath)
            event.accepted = true
        } else if (!search.activeFocus && !ctrl && !alt
                && (event.key === Qt.Key_Left || event.key === Qt.Key_Up
                    || (Qt.Key_H !== undefined && (event.key === Qt.Key_H || event.key === Qt.Key_K)))) {
            moveSelection(-1)
            event.accepted = true
        } else if (!search.activeFocus && !ctrl && !alt
                && (event.key === Qt.Key_Right || event.key === Qt.Key_Down
                    || (Qt.Key_L !== undefined && (event.key === Qt.Key_L || event.key === Qt.Key_J)))) {
            moveSelection(1)
            event.accepted = true
        } else if (!search.activeFocus && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            activateCurrent()
            event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            setMode(GlobalStates.wallpaperLauncherMode === "static" ? "animated" : "static")
            event.accepted = true
        } else if (!search.activeFocus && !ctrl && !alt && event.text && event.text.length === 1 && event.text >= " ") {
            search.forceActiveFocus()
            search.text += event.text
            event.accepted = true
        }
        }
    }
}
