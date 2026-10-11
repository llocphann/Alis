#!/usr/bin/env python3
"""Real Dashboard navigation, responsive Music columns and owned MPD adapter."""
import json, os, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hadalis-dashboard-music-") as name:
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
 TestCase {
  id:test; when:false; optional:true
  function check(v,m) { if(!v) throw new Error(m) }
  function renderFrame(item,message) {
   const before=root.captures
   check(item.grabToImage(image=>root.captures++),message+": render request refused")
   tryVerify(()=>root.captures>before,3000)
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
    check(dashboard.currentPageId==="dashboard","small horizontal ticks skipped threshold")
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
   check(dashboard.currentPageId==="dashboard","body pixel threshold bypassed")
   phaseEvent(-16,0,2,true)
   check(dashboard.currentPageId==="music","header/body did not share phased threshold")
   phaseEvent(-64,0,4,true)
   check(dashboard.currentPageId==="music","momentum changed another page")
   phaseEvent(32,0,2,true)
   check(dashboard.currentPageId==="dashboard","phased reversal failed")
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
   let music=findChild(dashboard,"dashboardMusic")
   check(music.backend===fake,"music created another playback owner")
   check(music.results.length===0,"results must start empty")
   check(waitForPolish(window.contentItem,2000),"music column layout pending")
   const columns=["musicLibrary","musicResults","musicPlaybackAndQueue","musicLyrics"].map(name=>findChild(music,name))
   const genreTab=findChild(music,"musicGenreTab"), folderTab=findChild(music,"musicFolderTab")
   check(genreTab && folderTab && genreTab.parent===folderTab.parent,
      "Genre and Folders are not tab buttons in the same Library column")
   const playerPanel=findChild(music,"musicPlayer"), queuePanel=findChild(music,"musicQueuePanel")
   check(playerPanel && queuePanel && playerPanel.parent===queuePanel.parent && playerPanel.height>0 && queuePanel.height>0,
      "Media card and Queue must share one vertical column with real content")
   check(playerPanel.height <= Math.ceil(playerPanel.implicitHeight)+1,
      "Media card vertically stretched and left blank space above/below player or DSP")
   check(columns[2].width <= 381,
      "Media/Queue column is wider than its intended control footprint")
   check(playerPanel.mediaBackend===fake && playerPanel.playbackAdapter!==null && playerPanel.showEqualizer,
      "Music tab did not reuse DashMedia with the LocalMusic adapter")
   check(findChild(music,"musicQueueList")!==null,"secondary Queue list missing")
   check(columns.every(column=>column && column.width>0 && column.height>0),"missing music column")
   check(waitForPolish(columns[0].parent,2000),"music Row layout pending")
   check(columns.every((column,index)=>index===0 || column.x>=columns[index-1].x+columns[index-1].width),"music columns overlap: "+JSON.stringify(columns.map(column=>({x:column.x,width:column.width,height:column.height,visible:column.visible,parent:String(column.parent),rowVisible:column.parent.visible,musicVisible:music.visible}))))
   mouseMove(columns[0],columns[0].width/2,columns[0].height/2)
   tryCompare(music,"queueExpanded",false,1500)
   renderFrame(dashboard,"collapsed Queue frame pending")
   const eq=findChild(music,"musicEqualizer")
   check(eq && eq.active && eq.visible && eq.compactLayout,
      "Music tab must show the shared Dashboard EQ when Queue is collapsed")
   const mediaHeight=playerPanel.height
   const queueBottom=queuePanel.y+queuePanel.height, queueTop=queuePanel.y
   Config.setNestedValue("performance.reduceAnimations",false)
   mouseMove(queuePanel,queuePanel.width/2,Math.max(8,queuePanel.height/2))
   tryCompare(music,"queueExpanded",true,1500)
   check(!playerPanel.showEqualizer && !eq.visible && !eq.active,
      "Queue hover did not hide/suspend the shared EQ/DSP panel")
   tryVerify(()=>queuePanel.y<queueTop && playerPanel.height>playerPanel.implicitHeight,1000)
   for(let frame=0;frame<16;frame++) {
    check(Math.abs(queuePanel.y+queuePanel.height-queueBottom)<.5,
       "Queue bottom moved during upward expansion")
    check(playerPanel.y===0 && queuePanel.y>=playerPanel.y+playerPanel.height+7,
       "Queue animation moved or overlapped the Player")
    wait(16)
   }
   tryVerify(()=>queuePanel.height>0 && playerPanel.height<mediaHeight,2000)
   check(playerPanel.height <= Math.ceil(playerPanel.implicitHeight)+1,
      "Expanded Queue left unused vertical space inside the media card")
   mouseMove(columns[1],columns[1].width/2,columns[1].height/2)
   tryCompare(music,"queueExpanded",false,1500)
   check(playerPanel.showEqualizer && eq.visible && eq.active,
      "Queue exit did not restore the shared Dashboard EQ")
   for(let frame=0;frame<16;frame++) {
    check(Math.abs(queuePanel.y+queuePanel.height-queueBottom)<.5,
       "Queue bottom moved during downward collapse")
    wait(16)
   }
   Config.setNestedValue("performance.reduceAnimations",true)
   tryVerify(()=>playerPanel.height>0 && playerPanel.height<=Math.ceil(playerPanel.implicitHeight)+1,2000)
   const lyricLines=fake.localLyricsLines, originalWidths=columns.map(column=>column.width)
   fake.localLyricsLines=[]
   renderFrame(dashboard,"three-column frame pending")
   check(!columns[3].visible && columns[3].width===0,"missing Lyrics left an empty column")
   check(columns[1].width>originalWidths[1] && columns[0].width>=200,"missing Lyrics did not expand Results while preserving a readable Library: "+JSON.stringify({music:music.width,row:columns[0].parent.width,before:originalWidths,after:columns.map(column=>column.width)}))
   check(columns[2].width>=315 && columns[2].width<=381,"missing Lyrics violated the bounded Media/Queue control width")
   check(Math.abs(columns[2].x+columns[2].width-columns[0].parent.width)<1,"three-column row left unused space")
   fake.localLyricsLines=lyricLines
   renderFrame(dashboard,"restored Lyrics frame pending")
   check(columns[3].visible && columns.every((column,index)=>Math.abs(column.width-originalWidths[index])<1),"restored Lyrics changed the column proportions")
   Config.setNestedValue("performance.reduceAnimations",false)
   const pages=findChild(dashboard,"dashboardPages")
   mouseClick(findChild(dashboard,"dashboardPage0"))
   tryVerify(()=>pages.slideProgress>0 && pages.slideProgress<1,1000)
   check(!eq.active,"outgoing Music retained the DSP consumer")
   tryCompare(pages,"slideProgress",0,2000)
   mouseClick(findChild(dashboard,"dashboardPage1"))
   tryVerify(()=>pages.slideProgress>0 && pages.slideProgress<1,1000)
   tryCompare(pages,"slideProgress",1,2000)
   check(eq.active,"returning Music failed to reacquire the shared DSP consumer")
   Config.setNestedValue("performance.reduceAnimations",true)
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
   mouseClick(findChild(music,"musicQueue"));tryCompare(list,"count",2,2000)
   check(findChild(music,"musicQueueList").count===2,"secondary Queue must remain populated independently of Results")
   check(!music.queueExpanded,"Queue expansion must reset after pointer leaves")
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
   music=findChild(dashboard,"dashboardMusic")
   check(music!==beforeUnload && music.sourceMode==="queue","cold UI did not restore browsing identity")
   music.chooseGenre("Jazz");music.chooseGenre("Rock",Qt.ControlModifier)
   Config.setNestedValue("dashboard.music.enable",false)
   tryVerify(()=>findChild(dashboard,"dashboardMusic")===null,2000)
   check(GlobalStates.dashboardMusicBrowser.genres.length===2,
      "unload lost Genre multi selection")
   Config.setNestedValue("dashboard.music.enable",true)
   tryVerify(()=>findChild(dashboard,"dashboardMusic")!==null,2000)
   music=findChild(dashboard,"dashboardMusic")
   check(music.selectedGenres.length===2 && music.results.length===3,
      "cold UI did not restore Genre multi selection")
   check(waitForPolish(dots,2000),"restored page navigation layout pending");renderFrame(dashboard,"restored page frame pending")
   // Backend errors are surfaced without altering playback queue, audio or
   // browser state. A successful later status update hides the notification.
   const musicQueueBefore=fake.activeQueue
   fake.error="ACK [50@0] {play} Bad song index"
   const backendError=findChild(music,"musicBackendError")
   tryVerify(()=>backendError && backendError.visible,1000)
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
   check(!findChild(dashboard,"dashboardPage1").enabled,"page switch must not interrupt layout editing")
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
   check(dashboard.currentPageId==="dashboard" && GlobalStates.dashboardPage===0,"reordered dot selected wrong identity")
   dots.parent.forceActiveFocus();keyClick(Qt.Key_Left)
   check(dashboard.currentPageId==="music","accessible Left ignored persisted order")
   keyClick(Qt.Key_Right)
   check(dashboard.currentPageId==="dashboard","accessible Right ignored persisted order")
   Config.setNestedValue("dashboard.music.enable",false)
   check(dashboard.pageIds.length===1 && dashboard.currentPageId==="dashboard","disabled page retained navigation")
   check(Config.options.dashboard.pageOrder[0]==="music","disabled page rewrote stored order")
   Config.setNestedValues({"dashboard.music.enable":true,"dashboard.pageOrder":["dashboard","music","weeklyPlanner"]})
   const settings=Qt.createComponent(Qt.resolvedUrl("modules/settings/DashboardMusicSettings.qml"))
   check(settings.status===Component.Ready,"Music settings failed to compile: "+settings.errorString())
   const settingsItem=settings.createObject(window.contentItem,{visible:false})
   check(settingsItem!==null,"Music settings failed to load")
   settingsItem.destroy()
   console.info("DASHBOARD_MUSIC_RUNTIME_PASS native-page-dots responsive-columns genre folder child-folder actual-playback-click stable-canvas hidden-presentation edit-lock horizontal-only-shared-burst reordered-stable-ids keyboard disabled-order-preservation")
  } catch(e) { console.error("DASHBOARD_MUSIC_RUNTIME_FAIL",e.message,e.stack) } Qt.quit() }
 }
 Timer { interval:100; running:true; onTriggered:test.runChecks() }
}
''')
 with private_wayland(folder) as env:
  if env is None: raise SystemExit("SKIP: Dashboard music requires a private Niri surface")
  config=folder/"config/illogical-impulse";config.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/"defaults/config.json").read_text());data["panelFamily"]="abyss";data["abyss"]["companion"]["enabled"]=False
  (config/"config.json").write_text(json.dumps(data))
  capture=Path(os.environ.get("HADALIS_MUSIC_CAPTURE",str(folder/"dashboard-music.png")))
  env.update(QSG_RHI_BACKEND="opengl",MUSIC_CAPTURE=str(capture),MUSIC_CAPTURE_NARROW=str(capture.with_name(capture.stem+"-narrow.png")))
  result=run_qs(folder,env,timeout=40)
  if os.environ.get("ALIS_DASHBOARD_MUSIC_LOG"):
   Path(os.environ["ALIS_DASHBOARD_MUSIC_LOG"]).write_text(result.stdout)
  if result.returncode or "DASHBOARD_MUSIC_RUNTIME_PASS" not in result.stdout or any(x in result.stdout for x in ["DASHBOARD_MUSIC_RUNTIME_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration"]):
   print(result.stdout);raise SystemExit(1)
  print("DASHBOARD_MUSIC_RUNTIME_PASS native dots/wheel/panning, tabbed Library/Results/Media+Queue/optional Lyrics, genre/folder/search, single/double/Ctrl actions, queue/playlist/volume, cold restore and edit lock")
