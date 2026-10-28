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
    property string outputName:""
    property string monitorName:outputName
    property bool embedded:false
    property string browseFolder:""
    property string selectedColor:""
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
    function refreshLibrary(force=false):void {
        library.refresh(browseFolder || Directories.wallpapersPath,browseFolder ? [] : [FileUtils.parentDirectory(currentWallpaperPath),Wallpapers.effectiveDirectory],force)
    }
    function setMode(nextMode:string):void {
        if(!["static","animated"].includes(nextMode))return
        GlobalStates.wallpaperLauncherMode=nextMode
        GlobalStates.wallpaperLauncherSearchText=""
        Qt.callLater(carousel.syncCurrentIndexAndPreview)
    }
    function toggleColorFilter(colorId:string):void {
        if (colorId)
            library.ensureColorTags()
        root.selectedColor = (root.selectedColor === colorId) ? "" : colorId
        root.forceActiveFocus()
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
    Component.onCompleted:{if(GlobalStates.wallpaperLauncherOpen)refreshLibrary();Qt.callLater(()=>{root.forceActiveFocus();carousel.syncCurrentIndexAndPreview()})}
    Connections {
        target:GlobalStates
        function onWallpaperLauncherOpenChanged():void {if(GlobalStates.wallpaperLauncherOpen){root.refreshLibrary();Qt.callLater(root.forceActiveFocus)}}
    }
    FolderDialog {
        id:folderPicker
        title:"Wallpaper folder"
        currentFolder:browseFolder ? "file://"+browseFolder : "file://"+Directories.wallpapersPath
        onAccepted:root.browseFolder=FileUtils.trimFileProtocol(String(selectedFolder))
        onVisibleChanged:GlobalStates.settingsNativeDialogOpen=visible
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
                entries:root.entries;searchText:search.text;selectedColor:root.selectedColor;colorTagsByPath:library.colorTagsByPath;currentWallpaperPath:root.currentWallpaperPath;monitorName:root.selectionMonitorName
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
                    Keys.onDownPressed:{root.moveSelection(1);root.forceActiveFocus()}
                    Keys.onUpPressed:{root.moveSelection(-1);root.forceActiveFocus()}
                    Keys.onEscapePressed:GlobalStates.wallpaperLauncherOpen=false
                }
                AbyssButton {objectName:"wallpaperMode";outlined:false;glyph:root.mode==="static" ? "image" : "movie";description:root.mode==="static" ? "Show animated wallpapers" : "Show images";onClicked:root.setMode(root.mode==="static" ? "animated" : "static")}
                AbyssButton {objectName:"wallpaperFolder";outlined:false;glyph:"folder_open";description:root.browseFolder.length > 0 ? FileUtils.folderNameForPath(root.browseFolder) : "Choose wallpaper folder";onClicked:folderPicker.open()}
                AbyssButton {objectName:"wallpaperRefresh";outlined:false;glyph:"refresh";description:"Refresh wallpapers";enabled:!root.loading;onClicked:root.refreshLibrary(true)}
                AbyssButton {objectName:"wallpaperClose";outlined:false;glyph:"close";description:"Close wallpaper selector";onClicked:GlobalStates.wallpaperLauncherOpen=false}
            }
        }

    }
    Keys.onPressed:event=>{
        if(event.key===Qt.Key_Escape){GlobalStates.wallpaperLauncherOpen=false;event.accepted=true}
        else if((event.modifiers&Qt.ControlModifier) && (event.key===(Qt.Key_F ?? 70) || event.text==="f" || event.text==="F")){search.forceActiveFocus();event.accepted=true}
        else if(event.key===Qt.Key_Left || event.key===Qt.Key_Up || (!(event.modifiers&Qt.ControlModifier) && (event.key===(Qt.Key_H ?? 72) || event.key===(Qt.Key_K ?? 75)))){moveSelection(-1);event.accepted=true}
        else if(event.key===Qt.Key_Right || event.key===Qt.Key_Down || (!(event.modifiers&Qt.ControlModifier) && (event.key===(Qt.Key_L ?? 76) || event.key===(Qt.Key_J ?? 74)))){moveSelection(1);event.accepted=true}
        else if(event.key===Qt.Key_Return || event.key===Qt.Key_Enter){activateCurrent();event.accepted=true}
        else if(event.key===Qt.Key_Tab || event.key===Qt.Key_Backtab){setMode(mode==="static" ? "animated" : "static");event.accepted=true}
        else if(event.text && !(event.modifiers&Qt.ControlModifier)){search.text+=event.text;search.forceActiveFocus();event.accepted=true}
    }
}
