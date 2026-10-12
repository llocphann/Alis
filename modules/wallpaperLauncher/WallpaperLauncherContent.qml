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
    implicitHeight:260+padding*2
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
    function applyPath(path:string):void {
        if(!path)return
        Wallpapers.clearWallpaperPreview()
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
    onBrowseFolderChanged:refreshLibrary(true)
    Component.onCompleted:{refreshLibrary();Qt.callLater(()=>{root.forceActiveFocus();carousel.syncCurrentIndexAndPreview()})}
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
            WallpaperLauncherList {
                id:carousel;objectName:"wallpaperCarousel"
                anchors.centerIn:parent;width:parent.width;height:implicitHeight
                cardWidth:Math.min(288,Math.max(150,parent.width/4.2))
                maxVisibleItems:Math.max(1,Math.min(5,Math.floor(parent.width/(cardWidth*.8))))
                entries:root.entries;searchText:search.text;currentWallpaperPath:root.currentWallpaperPath;monitorName:root.selectionMonitorName
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
                    Keys.onDownPressed:root.moveSelection(1)
                    Keys.onUpPressed:root.moveSelection(-1)
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
        else if(event.key===Qt.Key_Left || event.key===Qt.Key_Up){moveSelection(-1);event.accepted=true}
        else if(event.key===Qt.Key_Right || event.key===Qt.Key_Down){moveSelection(1);event.accepted=true}
        else if(event.key===Qt.Key_Return || event.key===Qt.Key_Enter){activateCurrent();event.accepted=true}
        else if(event.key===Qt.Key_Tab || event.key===Qt.Key_Backtab){setMode(mode==="static" ? "animated" : "static");event.accepted=true}
        else if(event.text && !(event.modifiers&Qt.ControlModifier)){search.text+=event.text;search.forceActiveFocus();event.accepted=true}
    }
}
