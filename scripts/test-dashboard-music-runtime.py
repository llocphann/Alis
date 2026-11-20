#!/usr/bin/env python3
"""Real Dashboard navigation, responsive Music columns and owned MPD adapter."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-dashboard-music-") as name:
 folder=Path(name)
 for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:
  (folder/entry).symlink_to(ROOT/entry)
 (folder/"shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.services
import qs.modules.dashboard
import qs.modules.settings
ShellRoot {
 id: root
 property int captures: 0
 Component.onCompleted: Quickshell.watchFiles=false
 QtObject {
  id: fake
  property var libraryTracks: [
   {uri:"Jazz/Live/one.flac",folder:"Jazz/Live",title:"One",artist:"Aqua",genre:"Jazz"},
   {uri:"Jazz/two.flac",folder:"Jazz",title:"Two",artist:"Octo",genre:"Jazz"},
   {uri:"Rock/three.flac",folder:"Rock",title:"Three",artist:"Band",genre:"Rock"}]
  property var mprisPlayer: null
  property var playlists: [{name:"Evening",tracks:[libraryTracks[0]]}]
  property var activeQueue: [libraryTracks[0],libraryTracks[2]]
  property real volume: .4
  property bool playing: false
  property bool hasCurrentTrack: false
  property bool available: true
  property string error: ""
  property string currentTitle: "One"
  property string currentArtist: "Aqua"
  property var localLyricsLines: [{time:0,text:"A little rhythm beneath the water"},{time:10,text:"A quiet song for the evening"}]
  property int localLyricsActiveIndex: 0
  property string selectedUri: ""
  property bool selectedPlay: false
  function enqueueTrack(track,play) { selectedUri=track.uri; selectedPlay=play }
  property var enqueued: []
  property int queueIndex: -1
  property string created: ""
  property int removed: -1
  function enqueueTracks(tracks) { enqueued=tracks }
  function playQueue(tracks,index,name) { enqueued=tracks;queueIndex=index }
  // Match LocalMusic's actual public transport API; no invented UI methods.
  function jumpTo(index) { queueIndex=index }
  function createPlaylist(name,tracks) { created=name;enqueued=tracks }
  function addTracksToPlaylist(name,tracks) { created=name;enqueued=tracks }
  function removeQueueTrack(index) { removed=index }
  function clearQueue() { activeQueue=[] }
  function setVolume(value) { volume=value }
  function updateDatabase() {}
 }
 FloatingWindow {
  id: window; visible:true; implicitWidth:1280; implicitHeight:720; color:"#111820"
  DashboardContent { id: dashboard; width:window.width; height:Math.min(window.height,720); embeddedSurface:true; presentationActive:true; musicBackend:fake }
 }
 // The owner keeps nested debug Niri unfocused. An occluded parent can stop
 // Wayland frame callbacks; request bounded private QSG frames for animation
 // assertions without focusing an owner window or changing the deadlines.
 Timer {interval:16;repeat:true;running:true;onTriggered:dashboard.grabToImage(()=>{},Qt.size(64,36))}
 TestCase {
  id:test; when:false; optional:true
  function check(v,m) { if(!v) throw new Error(m) }
  function liveMusic() {
   const loader=findChild(dashboard,"dashboardMusicPageLoader")
   check(loader!==null,"Music Loader unavailable")
   tryCompare(loader,"status",Loader.Ready,4000)
   check(loader.item!==null && loader.item===findChild(dashboard,"dashboardMusic"),
    "Music fixture found an old or partially incubated item")
   return loader.item
  }
  function renderFrame(item,message) {
   const before=root.captures
   check(item.grabToImage(image=>root.captures++),message+": render request refused")
   tryVerify(()=>root.captures>before,3000)
  }
  function checkLibraryReplacements(music) {
   const original = fake.libraryTracks
   for (const season of ["Spring", "Autumn"]) {
    const library = []
    for (let index = 0; index < 12000; index++) {
     const folder = "Bộ " + (index % 12) + "/Album " + (index % 71)
     library.push({uri: folder + "/" + index + ".ogg", folder: folder,
      title: season + " " + index, artist: "Nghệ sĩ " + (index % 100),
      genre: index % 3 === 0 ? "Rock; Live" : "Pop"})
    }
    fake.libraryTracks = library
    music.chooseGenre("Live")
    check(music.results.length === 4000 && music.results[1].track === library[3],
     "Genre retained stale metadata or lost source track identity")
    check(music.folders.reduce((sum, folder) => sum + folder.count, 0) === library.length,
     "Root folder counts lost tracks")
    music.query = "nghe si"
    music.query = "nghe si 37"
    check(music.results.length === 120 && music.results[0].track === library[37],
     "Incremental accent-folded search lost tracks after source replacement")
    music.query = season + " 11999"
    check(music.results.length === 1 && music.results[0].track === library[11999],
     "Library tail does not resolve to the replacement track")
    music.query = ""
   }
   fake.libraryTracks = original
  }
  function runChecks() { try {
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValues({"performance.reduceAnimations":true,"dashboard.music.enable":true,"dashboard.showHeader":true,"dashboard.canvas.widgets":[]})
   GlobalStates.dashboardPage=0
   check(waitForPolish(window.contentItem,2000),"initial Dashboard layout pending")
   renderFrame(dashboard,"initial Dashboard frame pending")
   const dimensions=[dashboard.canvasController.width,dashboard.canvasController.height]
   const dots=findChild(dashboard,"dashboardPageDots")
   check(Math.abs(dots.mapToItem(dashboard,0,0).x+dots.width/2-dashboard.width/2)<1,"page dots are not centered")
   check(findChild(dashboard,"dashboardPageDot0").width===8 && findChild(dashboard,"dashboardPageDot0").height===8,"page indicator must remain a small circular dot")
   check(findChild(dashboard,"dashboardMusic")===null,"Music UI eagerly allocated before its first visit")
   // Real Qt wheel dispatch across body, header and the page indicators.
   for(const area of [dashboard,dots.parent,dots]) {
    for(const dy of [-120,120]) {
     mouseWheel(area,area.width/2,area.height/2,0,dy)
     check(dashboard.currentPageId==="dashboard","vertical wheel changed Dashboard page")
    }
    mouseWheel(area,area.width/2,area.height/2,0,-120,Qt.NoButton,Qt.ShiftModifier)
    check(dashboard.currentPageId==="dashboard","Shift-only vertical signal changed page")
    mouseWheel(area,area.width/2,area.height/2,-120,-160)
    check(dashboard.currentPageId==="dashboard","vertical-dominant diagonal changed page")
   }
   for(let tick=0;tick<3;tick++) {
    mouseWheel(dots,dots.width/2,dots.height/2,-30,0)
    check(dashboard.currentPageId==="dashboard" && !dashboard._pendingPageId,"small horizontal ticks skipped threshold")
   }
   mouseWheel(dots,dots.width/2,dots.height/2,-30,0)
   tryCompare(dashboard,"currentPageId","music",1000)
   mouseWheel(dots.parent,dots.parent.width/2,dots.parent.height/2,120,0)
   tryCompare(dashboard,"currentPageId","dashboard",1000)
   dashboard.resetPageWheel()
   // QtTest mouseWheel dispatches angle deltas. Exercise pixel/phase state in
   // the actual QV4 owners separately; this does not simulate physical touchpad delivery.
   function phaseEvent(x,y,phase,header) {
    const event={pixelDelta:{x,y},angleDelta:{x:0,y:0},phase,accepted:false}
    if(header)dots.parent.horizontalWheel(event)
    else dashboard.handlePageWheel(event,true)
    return event
   }
   phaseEvent(0,0,1,false)
   phaseEvent(-16,0,2,false)
   check(dashboard.currentPageId==="dashboard" && !dashboard._pendingPageId,"body pixel threshold bypassed")
   phaseEvent(-16,0,2,true)
   // A requested target can still be incubating. Check burst intent before
   // commitment so momentum/reversal cannot hide a queued extra page.
   check((dashboard._pendingPageId || dashboard.currentPageId)==="music","header/body did not share phased threshold")
   phaseEvent(-64,0,4,true)
   check((dashboard._pendingPageId || dashboard.currentPageId)==="music","momentum changed another page")
   phaseEvent(32,0,2,true)
   check((dashboard._pendingPageId || dashboard.currentPageId)==="dashboard","phased reversal failed")
   tryCompare(dashboard,"currentPageId","dashboard",1000)
   check(!dashboard._pendingPageId,"reversal retained an uncommitted target")
   phaseEvent(0,0,3,false)
   check(!phaseEvent(0,40,0,true).accepted && dashboard.currentPageId==="dashboard","pixel vertical event was intercepted")
   dashboard.resetPageWheel()
   dashboard.openAgendaDialog(null)
   check(!dashboard.navigationAllowed && !findChild(dashboard,"dashboardPage1").enabled,"dialog retained page input")
   phaseEvent(-40,0,1,false)
   check(dashboard.currentPageId==="dashboard","page gesture interrupted dialog input")
   check(dashboard.handleEscape(),"Agenda dialog did not release its navigation guard")
   mouseWheel(dashboard,dashboard.width/2,dashboard.height/2,-120,0)
   tryCompare(dashboard,"currentPage",1,1000)
   renderFrame(dashboard,"wheel music frame pending")
   mouseWheel(dashboard,dashboard.width/2,dashboard.height/2,120,0)
   tryCompare(dashboard,"currentPage",0,1000)
   mouseClick(findChild(dashboard,"dashboardPage1"))
   tryCompare(dashboard,"currentPage",1,1000)
   tryVerify(()=>findChild(dashboard,"dashboardMusic")!==null,3000)
   let music=liveMusic()
   check(music.backend===fake,"music created another playback owner")
   check(music.results.length===0,"results must start empty")
   check(waitForPolish(window.contentItem,2000),"music column layout pending")
   const columns=["musicLibrary","musicResults","musicPlaybackAndQueue"].map(name=>findChild(music,name))
   const genreTab=findChild(music,"musicGenreTab"), folderTab=findChild(music,"musicFolderTab")
   check(genreTab && folderTab && genreTab.parent===folderTab.parent,
      "Genre and Folders are not tab buttons in the same Library column")
   const playerPanel=findChild(music,"musicPlayer"), queuePanel=findChild(music,"musicQueuePanel"), lyricsPanel=findChild(music,"musicLyrics")
   check(playerPanel && queuePanel && lyricsPanel && playerPanel.height>0 && queuePanel.height>0,
      "Persistent player bar and right drawer panels missing")
   check(columns.every(column=>column && column.width>0 && column.height>0),"missing music column")
   check(waitForPolish(columns[0].parent,2000),"music Row layout pending")
   check(columns.every((column,index)=>index===0 || column.x>=columns[index-1].x+columns[index-1].width),"music columns overlap: "+JSON.stringify(columns.map(column=>({x:column.x,width:column.width,height:column.height,visible:column.visible}))))
   // Sonora Equalizer lives in the right drawer EQ tab and activates its DSP consumer only when open on Music
   const eq=findChild(music,"musicEqualizer")
   check(eq && !eq.active,"EQ DSP consumer must stay suspended while Queue tab is active")
   music.rightDrawerTab="eq"
   tryCompare(eq,"active",true,1500)
   check(eq.visible && eq.compactLayout,"Music EQ tab did not activate shared EqualizerPanel")
   const pages=findChild(dashboard,"dashboardPages")
   Config.setNestedValue("performance.reduceAnimations",false)
   mouseClick(findChild(dashboard,"dashboardPage0"))
   tryVerify(()=>pages.slideProgress>0 && pages.slideProgress<1,1000)
   check(!eq.active,"outgoing Music retained the DSP consumer")
   tryCompare(pages,"slideProgress",0,2000)
   mouseClick(findChild(dashboard,"dashboardPage1"))
   tryVerify(()=>pages.slideProgress>0 && pages.slideProgress<1,1000)
   tryCompare(pages,"slideProgress",1,2000)
   check(eq.active,"returning Music failed to reacquire the shared DSP consumer")
   Config.setNestedValue("performance.reduceAnimations",true)
   // Verify merged Lyrics & EQ drawer tab (Lyrics above compact EQ) + Ambient karaoke mode + Escape dismissal
   music.rightDrawerTab="lyrics"
   tryCompare(lyricsPanel,"visible",true,1000)
   renderFrame(dashboard,"merged lyrics and eq frame pending")
   check(eq.active && eq.visible && lyricsPanel.height>eq.height,"merged Lyrics & EQ tab did not keep Lyrics larger above compact EQ")
   music.ambientOpen=true
   const ambient=findChild(music,"musicAmbientView")
   tryCompare(ambient,"visible",true,1000)
   check(music.restoreBrowserColumns() && !music.ambientOpen,"Escape must close Ambient mode first")
   const lyricLines=fake.localLyricsLines
   fake.localLyricsLines=[]
   renderFrame(dashboard,"empty lyrics frame pending")
   check(findChild(music,"musicLyricsList").count===0,"empty lyrics retained stale rows")
   fake.localLyricsLines=lyricLines
   music.rightDrawerTab="queue"
   tryCompare(queuePanel,"visible",true,1000)
   check(!eq.active,"switching to Queue tab did not suspend EQ DSP")
   const playerSurface=findChild(playerPanel,"musicPlayerSurface")
   const musicVolume=findChild(playerPanel,"musicVolume")
   check(playerSurface && musicVolume,"missing musicPlayerSurface or musicVolume")
   // Verify Sonora album & artist library grouping + Hero view
   check(music.albums.length>=1 && music.artists.length===3,"Sonora albums/artists grouping incomplete")
   music.openAlbum(music.albums[0].key)
   check(music.sourceMode==="album" && music.allResultTracks.length>=1,"Album hero drilldown failed")
   music.restoreBrowserColumns()
   const originalWidths=columns.map(column=>column.width)
   check(originalWidths.every(w=>w>=200),"Sonora 3-column widths collapsed on desktop")
   const list=findChild(music,"musicResultList")
   renderFrame(dashboard,"music frame pending")
   mouseClick(findChild(music,"musicGenreList").itemAtIndex(0))
   check(music.results.length===2,"genre did not fill results column")
   check(music.libraryTab==="genre" && columns[0].visible && !findChild(music,"musicFolders").visible,
      "Genre tab did not remain active after choosing a genre")
   const genreList=findChild(music,"musicGenreList")
   tryVerify(()=>genreList.itemAtIndex(1)!==null,2000)
   mouseClick(genreList.itemAtIndex(1),10,10,Qt.LeftButton,Qt.ControlModifier)
   check(music.selectedGenres.length===2 && music.results.length===3,
      "Ctrl Genre selection did not combine results")
   mouseClick(genreList.itemAtIndex(0),10,10,Qt.LeftButton,Qt.ShiftModifier)
   check(music.selectedGenres.length===2 && music.results.length===3,
      "Shift Genre selection lost its anchor range")
   mouseClick(genreList.itemAtIndex(1),10,10,Qt.LeftButton,Qt.ControlModifier)
   check(music.selectedGenres.length===1 && music.results.length===2,
      "Ctrl Genre deselection removed other genres")
   mouseClick(genreList.itemAtIndex(0),10,10,Qt.LeftButton,Qt.ControlModifier)
   check(music.selectedGenres.length===0 && music.results.length===0,
      "empty Genre selection retained results")
   mouseClick(genreList.itemAtIndex(0))
   mouseClick(findChild(music,"musicPlayAll"))
   check(fake.enqueued.length===2,"Play All did not use current result tracks")
   tryCompare(list,"count",2,2000);check(waitForPolish(list.contentItem,2000),"genre result layout pending")
   renderFrame(dashboard,"genre frame pending")
   mouseClick(list.itemAtIndex(0))
   check(music.selectedKeys.length===1,"single selection missed the row: "+JSON.stringify({listHeight:list.height,rowHeight:list.itemAtIndex(0)?.height,rowPosition:list.itemAtIndex(0)?.mapToItem(dashboard,0,0),listPosition:list.mapToItem(dashboard,0,0)}))
   tryVerify(()=>list.itemAtIndex(1)!==null,2000)
   check(waitForPolish(list,2000),"selection toolbar layout pending")
   renderFrame(dashboard,"selection frame pending")
   mouseClick(list.itemAtIndex(1),10,10,Qt.LeftButton,Qt.ControlModifier)
   check(music.selectedKeys.length===2,"Ctrl selection lost a selected track: "+JSON.stringify(music.selectedKeys))
   mouseClick(findChild(music,"musicPlaySelection"))
   check(fake.enqueued.length===2,"Play Selected lost the selected tracks")
   mouseClick(findChild(music,"musicEnqueueSelection"))
   check(fake.enqueued.length===2 && !fake.selectedUri,"selection enqueue started playback or lost tracks")
   check(music.restoreBrowserColumns() && columns[0].visible && !music.sourceMode,
      "first Escape did not clear the Library drill-down")
   check(!music.restoreBrowserColumns(),"second Escape must be handled by Dashboard")
   mouseClick(folderTab)
   check(music.libraryTab==="folder" && !findChild(music,"musicGenres").visible
      && findChild(music,"musicFolders").visible,"Folder tab did not select the shared Library column")
   const folderList=findChild(music,"musicFolderList")
   tryVerify(()=>folderList.itemAtIndex(0)!==null,2000)
   check(waitForPolish(folderList,2000),"Folder tab layout pending")
   renderFrame(dashboard,"Folder tab frame pending")
   mouseClick(findChild(music,"musicFolderList").itemAtIndex(0))
   check(music.libraryTab==="folder","selecting a folder lost the Folder tab")
   check(music.results.length===2 && music.results[0].kind==="folder","folder did not show children and files")
   tryVerify(()=>folderList.itemAtIndex(1)!==null,2000)
   mouseClick(folderList.itemAtIndex(1),10,10,Qt.LeftButton,Qt.ControlModifier)
   check(music.selectedFolders.length===2 && music.allResultTracks.length===3,
      "Ctrl Folder selection lost a folder or duplicated playback")
   mouseClick(findChild(music,"musicPlayAll"))
   check(fake.enqueued.length===3,"Play All did not include both selected folders")
   mouseClick(folderList.itemAtIndex(0),10,10,Qt.LeftButton,Qt.ShiftModifier)
   check(music.selectedFolders.length===2,"Shift Folder range selection failed")
   mouseClick(folderList.itemAtIndex(0))
   tryVerify(()=>list.itemAtIndex(0)!==null,2000)
   check(waitForPolish(list.contentItem,2000),"folder result layout pending")
   renderFrame(dashboard,"folder frame pending")
   mouseDoubleClickSequence(list.itemAtIndex(0))
   check(music.resultFolder==="Jazz/Live" && music.results.length===1,"child folder did not drill down")
   check(waitForPolish(window.contentItem,2000),"result list layout pending")
   tryVerify(()=>list.itemAtIndex(0)!==null,2000)
   mouseClick(list.itemAtIndex(0))
   check(!fake.selectedUri,"single selection must not start playback")
   mouseDoubleClickSequence(list.itemAtIndex(0))
   check(fake.selectedUri==="Jazz/Live/one.flac" && fake.selectedPlay,"native double click did not use existing MPD command")
   music.openCreatePlaylist(music.selectedTracks)
   findChild(music,"musicPlaylistName").text="Night"
   music.commitPlaylist()
   check(fake.created==="Night" && fake.enqueued.length===1,"playlist creation lost selected tracks")
   check(dashboard.canvasController.width===dimensions[0] && dashboard.canvasController.height===dimensions[1],"changing pages resized the widget workspace")
   const count=root.captures
   check(dashboard.grabToImage(image=>{if(image.saveToFile(Quickshell.env("MUSIC_CAPTURE"))) root.captures++}),"capture refused")
   tryVerify(()=>root.captures>count,3000)
   // Capture Ambient karaoke view too when requested
   const ambPath = Quickshell.env("MUSIC_CAPTURE_AMBIENT")
   if (ambPath) {
    music.ambientOpen = true
    renderFrame(dashboard, "ambient view pending")
    const ac = root.captures
    check(dashboard.grabToImage(image=>{if(image.saveToFile(ambPath)) root.captures++}),"ambient capture refused")
    tryVerify(()=>root.captures>ac,3000)
    music.ambientOpen = false
   }
   checkLibraryReplacements(music)
   mouseClick(findChild(music,"musicQueue"));tryCompare(list,"count",2,2000)
   check(findChild(music,"musicQueueList").count===2,"secondary Queue must remain populated independently of Results")
   tryVerify(()=>list.itemAtIndex(0)!==null,2000)
   check(waitForPolish(list.contentItem,2000),"queue layout pending")
   mouseDoubleClickSequence(list.itemAtIndex(0));check(fake.queueIndex===0,"queue playback changed the queue order")
   music.openContext(music.results[0],0,list.itemAtIndex(0))
   music.contextActions[music.contextActions.length-1].action()
   check(fake.removed===0,"queue removal did not target the selected queue item")
   music.query="Three";tryCompare(list,"count",1,2000)
   check(music.results[0].queueIndex===1,"queue search changed the original playback index")
   renderFrame(dashboard,"filtered queue frame pending")
   mouseDoubleClickSequence(list.itemAtIndex(0));check(fake.queueIndex===1,"filtered queue played a different entry")
   music.query="";tryCompare(list,"count",2,2000)
   const volume=findChild(music,"musicVolume")
   mouseClick(volume,volume.width*.7,volume.height/2)
   check(Math.abs(fake.volume-.4)>.05,"volume control did not reach the existing MPD adapter")
   dashboard.width=720;dashboard.height=650
   renderFrame(dashboard,"narrow music frame pending")
   check(Math.abs(dots.mapToItem(dashboard,0,0).x+dots.width/2-dashboard.width/2)<1,"narrow page dots moved off center")
   check(findChild(music,"musicResultList").height>250,"narrow search controls consumed the results viewport")
   const viewport=findChild(music,"musicColumnsViewport")
   const initialX=viewport.contentX
   mouseWheel(dashboard,dashboard.width/2,dashboard.height/2,-120,0)
   tryVerify(()=>viewport.contentX>initialX,1000)
   check(dashboard.currentPage===1,"panning narrow music changed the active page")
   check(music.panHorizontally(-400),"narrow tabbed Music browser must allow horizontal panning")
   const narrow=root.captures
   check(dashboard.grabToImage(image=>{if(image.saveToFile(Quickshell.env("MUSIC_CAPTURE_NARROW"))) root.captures++}),"narrow capture refused")
   tryVerify(()=>root.captures>narrow,3000)
   const beforeUnload=music
   Config.setNestedValue("dashboard.music.enable",false)
   tryVerify(()=>findChild(dashboard,"dashboardMusic")===null,2000)
   check(GlobalStates.dashboardMusicBrowser.mode==="queue","unload lost lightweight browsing state")
   Config.setNestedValue("dashboard.music.enable",true)
   tryVerify(()=>findChild(dashboard,"dashboardMusic")!==null,2000)
   music=liveMusic()
   check(music!==beforeUnload && music.sourceMode==="queue","cold UI did not restore browsing identity")
   music.chooseGenre("Jazz");music.chooseGenre("Rock",Qt.ControlModifier)
   Config.setNestedValue("dashboard.music.enable",false)
   tryVerify(()=>findChild(dashboard,"dashboardMusic")===null,2000)
   check(GlobalStates.dashboardMusicBrowser.genres.length===2,
      "unload lost Genre multi selection")
   Config.setNestedValue("dashboard.music.enable",true)
   tryVerify(()=>findChild(dashboard,"dashboardMusic")!==null,2000)
   music=liveMusic()
   check(music.selectedGenres.length===2 && music.results.length===3,
      "cold UI did not restore Genre multi selection")
   check(waitForPolish(dots,2000),"restored page navigation layout pending");renderFrame(dashboard,"restored page frame pending")
   // Disabling the selected page repairs selection to Dashboard. Re-enabling
   // it must not steal that selection; visit Music before checking its banner.
   check(dashboard.currentPageId==="dashboard","re-enabling Music changed the selected page")
   mouseClick(findChild(dashboard,"dashboardPage1"))
   tryCompare(dashboard,"currentPageId","music",1000)
   renderFrame(dashboard,"reselected Music frame pending")
   // Backend errors are surfaced without altering playback queue, audio or
   // browser state. A successful later status update hides the notification.
   const musicQueueBefore=fake.activeQueue
   fake.error="ACK [50@0] {play} Bad song index"
   const backendError=findChild(music,"musicBackendError")
   tryVerify(()=>backendError && backendError.visible && backendError.height>0 && backendError.width>0,1500)
   check(backendError.height>0 && backendError.width>0,
      "MPD failure lacks a visible in-Dashboard banner")
   check(fake.activeQueue===musicQueueBefore,"diagnostic mutated playback queue")
   renderFrame(dashboard,"visible MPD error pending")
   fake.error=""
   tryCompare(backendError,"visible",false,1000)
   Config.setNestedValue("performance.reduceAnimations",false)
   dashboard.canvasController.beginEditMode();wait(60)
   check(dashboard.currentPage===0 && pages.slideProgress===0,"entering edit mode slid or offset the widget workspace: "+JSON.stringify({page:dashboard.currentPage,progress:pages.slideProgress,editing:dashboard.editMode}))
   check(!music.presentationActive && !music.visible,"editing retained outgoing Music presentation work")
   mouseClick(findChild(dashboard,"dashboardPage1"))
   check(dashboard.currentPageId==="dashboard","page click must not interrupt layout editing")
   mouseWheel(dashboard,dashboard.width/2,dashboard.height/2,-120,0)
   check(dashboard.currentPage===0,"horizontal gesture interrupted layout editing")
   dashboard.canvasController.cancelEditMode()
   for(const destination of ["dashboard/music","sidebar-left/music","sidebar-left/ytmusic"]) {
    check(DevNavigation.request(destination)==="ok:"+destination,"Music navigation destination rejected "+destination)
    check(GlobalStates.dashboardOpen && !GlobalStates.sidebarLeftOpen && dashboard.currentPage===1,"Music navigation opened the retired Sidebar")
   }
   DevNavigation.closeAll()
   // Stable identity survives order changes; legacy public numeric intent
   // remains Music=1 regardless of its rendered index.
   dashboard.selectPage("music")
   Config.setNestedValue("dashboard.pageOrder",["music","dashboard","weeklyPlanner"])
   check(dashboard.currentPageId==="music" && dashboard.currentPage===0,"reorder changed selected identity")
   check(GlobalStates.dashboardPage===1,"reorder changed public Music intent")
   mouseClick(findChild(dashboard,"dashboardPage1"))
   tryCompare(dashboard,"currentPageId","dashboard",1000)
   check(dashboard.currentPageId==="dashboard" && GlobalStates.dashboardPage===0,"reordered dot selected wrong identity")
   dots.parent.forceActiveFocus();keyClick(Qt.Key_Left)
   tryCompare(dashboard,"currentPageId","music",1000)
   check(dashboard.currentPageId==="music","accessible Left ignored persisted order")
   keyClick(Qt.Key_Right)
   tryCompare(dashboard,"currentPageId","dashboard",1000)
   check(dashboard.currentPageId==="dashboard","accessible Right ignored persisted order")
   Config.setNestedValue("dashboard.music.enable",false)
   check(dashboard.pageIds.length===2 && !dashboard.pageIds.includes("music") && dashboard.pageIds.includes("weeklyPlanner") && dashboard.currentPageId==="dashboard","disabling Music lost Planner or retained Music")
   check(Config.options.dashboard.pageOrder[0]==="music","disabled page rewrote stored order")
   Config.setNestedValues({"dashboard.music.enable":true,"dashboard.pageOrder":["dashboard","music","weeklyPlanner"]})
   tryVerify(()=>findChild(dashboard,"dashboardMusic")!==null,2000)
   music=liveMusic()
   const settings=Qt.createComponent(Qt.resolvedUrl("modules/settings/DashboardMusicSettings.qml"))
   check(settings.status===Component.Ready,"Music settings failed to compile: "+settings.errorString())
   const settingsItem=settings.createObject(window.contentItem,{visible:false})
   check(settingsItem!==null,"Music settings failed to load")
   const scrollbarToggle=Array.from(settingsItem.contentData).find(item=>item.text===Translation.tr("Show Music scrollbars"))
   check(scrollbarToggle===undefined,"Music scrollbar toggle must be removed from Settings")
   Config.setNestedValue("dashboard.music.showScrollbars",false)
   check(Config.options.dashboard.music.showScrollbars===false && !music.showMusicScrollbars,"Music scrollbar disable failed typed persistence/binding")
   Config.setNestedValue("dashboard.music.showScrollbars",true)
   check(Config.options.dashboard.music.showScrollbars===true && music.showMusicScrollbars,"Music scrollbar enable failed typed persistence/binding")
   settingsItem.destroy()
   check(findChild(dashboard,"dashboardWeeklyPlanner")===null,"Planner allocated before its first visit")
   dashboard.selectPage("weeklyPlanner")
   tryVerify(()=>findChild(dashboard,"dashboardWeeklyPlanner")!==null,4000)
   check(dashboard.currentPage===2 && GlobalStates.dashboardPage===2,"Planner lost stable/legacy identity")
   const planner=findChild(dashboard,"dashboardWeeklyPlanner")
   planner.changeWeek(1)
   const pinnedWeek=planner.days[0].date.getTime()
   dashboard.openAgendaDialog({plannerDate:new Date(2030,0,2,9,15)})
   tryVerify(()=>findChild(dashboard,"dashboardAgendaDialog")!==null,2000)
   const form=findChild(dashboard,"dashboardAgendaDialog")
   check(form.eventTime==="09:15" && form.eventEndTime==="10:15" && form.eventDate.getDate()===2,"Planner click lost date/time in shared Agenda form")
   check(dashboard.handleEscape(),"Planner Agenda form did not dismiss")
   Config.setNestedValue("dashboard.pageOrder",["weeklyPlanner","dashboard","music"])
   check(dashboard.currentPageId==="weeklyPlanner" && dashboard.currentPage===0 && GlobalStates.dashboardPage===2,"reordering moved Planner identity")
   dashboard.presentationActive=false
   tryVerify(()=>findChild(dashboard,"dashboardWeeklyPlanner")===null,2000)
   dashboard.presentationActive=true
   tryVerify(()=>findChild(dashboard,"dashboardWeeklyPlanner")!==null,4000)
   check(findChild(dashboard,"dashboardWeeklyPlanner").days[0].date.getTime()===pinnedWeek,"cold Planner forgot selected week")
   Config.setNestedValue("dashboard.pageOrder",["dashboard","music","weeklyPlanner"])
   dashboard.selectPage("music")
   console.info("DASHBOARD_MUSIC_RUNTIME_PASS native-page-dots responsive-columns genre folder child-folder actual-playback-click stable-canvas hidden-presentation edit-lock horizontal-only-shared-burst reordered-stable-ids keyboard disabled-order-preservation")
  } catch(e) {
   const player=findChild(dashboard,"musicPlayer"),queue=findChild(dashboard,"musicQueuePanel")
   console.error("DASHBOARD_MUSIC_RUNTIME_FAIL",e.message,e.stack)
   console.info("DASHBOARD_MUSIC_FAILURE_GEOMETRY",JSON.stringify({page:dashboard.currentPageId,player:player?{y:player.y,height:player.height,implicitHeight:player.implicitHeight}:null,queue:queue?{y:queue.y,height:queue.height}:null}))
  } Qt.quit() }
 }
 Timer { interval:100; running:true; onTriggered:test.runChecks() }
}
''')
 with private_wayland(folder) as env:
  if env is None: raise SystemExit("SKIP: Dashboard music requires a private Niri surface")
  config=folder/"config/alis";config.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/"defaults/config.json").read_text());data["panelFamily"]="abyss";data["abyss"]["companion"]["enabled"]=False
  (config/"config.json").write_text(json.dumps(data))
  capture=Path(os.environ.get("ALIS_MUSIC_CAPTURE",str(folder/"dashboard-music.png")))
  env.update(QSG_RHI_BACKEND="opengl",MUSIC_CAPTURE=str(capture),MUSIC_CAPTURE_NARROW=str(capture.with_name(capture.stem+"-narrow.png")),MUSIC_CAPTURE_AMBIENT=str(capture.with_name(capture.stem+"-ambient.png")))
  result=run_qs(folder,env,timeout=60)
  if os.environ.get("ALIS_DASHBOARD_MUSIC_LOG"):
   Path(os.environ["ALIS_DASHBOARD_MUSIC_LOG"]).write_text(result.stdout)
  if result.returncode or "DASHBOARD_MUSIC_RUNTIME_PASS" not in result.stdout or any(x in result.stdout for x in ["DASHBOARD_MUSIC_RUNTIME_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Cannot assign to non-existent property","Failed to load configuration"]):
   print(result.stdout);raise SystemExit(1)
  print("DASHBOARD_MUSIC_RUNTIME_PASS native dots/wheel/panning, tabbed Library/Results/Media+Queue/optional Lyrics, genre/folder/search, single/double/Ctrl actions, queue/playlist/volume, cold restore and edit lock")
