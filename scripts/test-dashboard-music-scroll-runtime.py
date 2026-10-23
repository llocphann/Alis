#!/usr/bin/env python3
"""Real Dashboard overlay routing, six overflow lists, scrollbar drag and keyboard."""
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
import QtQuick.Controls
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services
import qs.modules.dashboard
import qs.modules.settings
ShellRoot {
 id: root
 property int captures: 0
 property int checks:0
 property string action:Quickshell.env("MUSIC_SCROLL_ACTION")
 FileView {id:disk;path:Config.filePath;property var snapshot:null;onLoaded:{try{snapshot=JSON.parse(text())}catch(error){snapshot=null}}}
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
  function check(v,m) { root.checks++;if(!v) throw new Error(m) }
  function renderFrame(item,message) {
   const before=root.captures
   check(item.grabToImage(image=>root.captures++),message+": render request refused")
   tryVerify(()=>root.captures>before,3000)
  }
  function runChecks() { try {
   tryCompare(Config,"ready",true,6000)
   if(root.action==="restart"){
    check(Config.options.dashboard.music.showScrollbars===false,"saved OFF preference lost on actual restart")
    check(Config.options.dashboard.lastPageId==="music","restart fixture lost the persisted Music selection")
    tryCompare(dashboard,"currentPageId","music",2000)
    tryVerify(()=>findChild(dashboard,"dashboardMusic")!==null,4000)
    const music=findChild(dashboard,"dashboardMusic")
    check(!music.showMusicScrollbars,"restarted Music ignored saved OFF preference")
    renderFrame(dashboard,"restarted hidden Music")
    for(const name of ["musicResultList","musicQueueList","musicLyricsList","musicGenreList","musicFolderList","musicPlaylistList"])
     check(findChild(music,name).ScrollBar.vertical.policy===ScrollBar.AlwaysOff,"restart hidden policy missing "+name)
    check(findChild(music,"musicColumnsViewport").ScrollBar.horizontal.policy===ScrollBar.AlwaysOff,"restart horizontal policy missing")
    Config.setNestedValue("dashboard.music.showScrollbars",true)
    renderFrame(dashboard,"short lists no-overflow frame")
    const names=["musicResultList","musicQueueList","musicLyricsList","musicGenreList","musicFolderList","musicPlaylistList"]
    for(const name of names){
     if(name==="musicGenreList")music.libraryTab="genre"
     if(name==="musicFolderList"||name==="musicPlaylistList")music.libraryTab="folder"
     renderFrame(dashboard,"visible short list "+name)
     const list=findChild(music,name)
     console.info("MUSIC_SHORT_RECEIPT",name,JSON.stringify({count:list.count,height:list.height,contentHeight:list.contentHeight,visible:list.ScrollBar.vertical.visible,opacity:list.ScrollBar.vertical.opacity,size:list.ScrollBar.vertical.size,thumbOpacity:list.ScrollBar.vertical.contentItem.opacity}))
     check(list.height>0&&list.contentHeight<=list.height+1&&!list.ScrollBar.vertical.visible,"visible short/empty list forces a scrollbar "+name)
    }
    fake.libraryTracks=[];fake.activeQueue=[];fake.playlists=[];fake.localLyricsLines=[]
    renderFrame(dashboard,"empty lists no-overflow frame")
    for(const name of names){
     if(name==="musicGenreList")music.libraryTab="genre"
     if(name==="musicFolderList"||name==="musicPlaylistList")music.libraryTab="folder"
     renderFrame(dashboard,"empty list "+name)
     const list=findChild(music,name)
     check(list.count===0&&!list.ScrollBar.vertical.visible,"empty list forces a scrollbar "+name)
    }
    // Request an actual wider client on this fixture's private Niri socket.
    // A 1280px hint alone can still be allocated906px by the compositor.
    Quickshell.execDetached(["niri","msg","action","set-column-width","1300"])
    const viewport=findChild(music,"musicColumnsViewport"),bar=viewport.ScrollBar.horizontal
    tryVerify(()=>viewport.width>=1000,3000)
    renderFrame(dashboard,"actual wider non-overflow viewport")
    console.info("MUSIC_WIDE_RECEIPT",JSON.stringify({windowWidth:window.width,viewportWidth:viewport.width,contentWidth:viewport.contentWidth,size:bar.size}))
    tryVerify(()=>bar.size>=1&&(!bar.visible||(bar.contentItem.opacity===0&&(!bar.background?.visible||bar.background.opacity===0))),1400)
    check(viewport.contentWidth<=viewport.width,"wide case never reached actual non-overflow allocation")
    Config.setNestedValue("dashboard.music.enable",false)
    check(!dashboard.pageIds.includes("music"),"disabled Music page remains navigable")
    Config.setNestedValue("dashboard.music.showScrollbars",false)
    tryVerify(()=>{disk.reload();return disk.snapshot?.dashboard?.music?.showScrollbars===false&&disk.snapshot?.dashboard?.music?.enable===false},5000)
    console.info("MUSIC_SCROLL_RESTART_PASS",root.checks,"checks",root.captures,"rendered frames saved OFF, restored selection, disabled page and short/empty lists");Qt.quit();return
   }
   check(Config.options.dashboard.music.showScrollbars===true,"old config missing scrollbar flag must default ON")
   check(findChild(dashboard,"dashboardMusic")===null,"Music unexpectedly allocated before its first visit on a fresh configuration")
   Config.setNestedValues({"performance.reduceAnimations":true,"dashboard.music.enable":true,"dashboard.music.showScrollbars":true,"dashboard.showHeader":true,"dashboard.canvas.widgets":[]})
   GlobalStates.dashboardPage=1
   tryVerify(()=>findChild(dashboard,"dashboardMusic")!==null,4000)
   const music=findChild(dashboard,"dashboardMusic")
   const tracks=[]
   for(let i=0;i<100;i++)tracks.push({uri:"Folder"+i+"/track.flac",folder:"Folder"+i,title:"Track "+i,artist:"Fixture",genre:"Genre"+i})
   fake.libraryTracks=tracks;fake.activeQueue=tracks
   fake.playlists=tracks.map((track,i)=>({name:"List "+i,tracks:[track]}))
   fake.localLyricsLines=tracks.map((track,i)=>({time:i,text:"Line "+i}))
   fake.hasCurrentTrack=true
   music.query="Track";music.sourceMode="search"
   renderFrame(dashboard,"long Music frame pending")
   for(const name of ["musicResultList","musicQueueList","musicLyricsList","musicGenreList","musicFolderList","musicPlaylistList"]){
    if(name==="musicGenreList")music.libraryTab="genre"
    if(name==="musicFolderList" || name==="musicPlaylistList")music.libraryTab="folder"
    const scroll=findChild(music,name)
    check(scroll!==null,"long list missing "+name)
    const before=scroll.mapToItem(dashboard,0,0)
    if(before.x<12)music.panHorizontally(12-before.x)
    else if(before.x+scroll.width>dashboard.width-12)music.panHorizontally(-(before.x+scroll.width-dashboard.width+12))
    // Leave expanded Queue before moving to other panes.
    mouseMove(scroll,Math.min(16,scroll.width/2),Math.min(24,scroll.height/2));wait(300)
    renderFrame(dashboard,"list layout pending")
    check(scroll.visible && scroll.contentHeight>scroll.height+30,"list has no visible overflow "+name+": "+scroll.contentHeight+"/"+scroll.height)
    scroll.contentY=scroll.originY
    mouseWheel(scroll,Math.min(16,scroll.width/2),Math.min(24,scroll.height/2),0,-120)
    wait(250)
    console.info("MUSIC_SCROLL_RECEIPT",name,JSON.stringify({height:scroll.height,contentHeight:scroll.contentHeight,contentY:scroll.contentY,originY:scroll.originY,currentPage:dashboard.currentPage}))
    check(dashboard.currentPage===1,"vertical list wheel navigated away from Music")
    check(scroll.contentY>scroll.originY+1,"real vertical wheel did not scroll "+name)
    const scrollbar=scroll.ScrollBar.vertical
    check(scrollbar.visible && scrollbar.contentItem.opacity>0 && String(scrollbar.contentItem.color)===String(music.accent),"overflow scrollbar missing/un-themed "+name)
    scroll.cancelFlick();scroll.contentY=scroll.originY
    renderFrame(dashboard,"scrollbar layout pending")
    const thumb=scrollbar.contentItem
    const from=thumb.mapToItem(scrollbar,thumb.width/2,thumb.height/2)
    console.info("MUSIC_THUMB_RECEIPT",name,JSON.stringify({start:from,barHeight:scrollbar.height,at:scrollbar.mapToItem(dashboard,0,0),windowWidth:dashboard.width}))
    mousePress(scrollbar,from.x,from.y)
    check(scrollbar.pressed,"scrollbar press missed "+name)
    mouseMove(scrollbar,from.x,Math.min(scrollbar.height-4,from.y+scrollbar.height*.5),40)
    mouseRelease(scrollbar,from.x,Math.min(scrollbar.height-4,from.y+scrollbar.height*.5));wait(150)
    check(scroll.contentY>scroll.originY+1,"scrollbar drag did not scroll "+name)
    scroll.contentY=scroll.originY;scroll.forceActiveFocus()
    keyClick(Qt.Key_Down);keyClick(Qt.Key_Down)
    check(scroll.currentIndex>=1,"keyboard navigation unavailable "+name)
    scroll.currentIndex=scroll.count-1;scroll.positionViewAtEnd()
    check(scroll.contentY>scroll.originY+1,"keyboard selection/end reveal unavailable "+name)
   }
   // Turning the preference off hides only scrollbar chrome. All list and
   // horizontal viewport navigation must stay alive, with no Music reload.
   const listNames=["musicResultList","musicQueueList","musicLyricsList","musicGenreList","musicFolderList","musicPlaylistList"]
   const oldMusic=music
   const queueBefore=JSON.stringify(fake.activeQueue),playlistsBefore=JSON.stringify(fake.playlists)
   const offsets=listNames.map(name=>{const list=findChild(music,name);return {name:name,y:list.contentY,index:list.currentIndex,width:list.width,height:list.height}})
   const viewport=findChild(music,"musicColumnsViewport"),oldX=viewport.contentX
   Config.setNestedValue("dashboard.music.showScrollbars",false)
   tryVerify(()=>music.showMusicScrollbars===false,1200)
   renderFrame(dashboard,"hidden Music layout")
   for(const before of offsets){
    const list=findChild(music,before.name)
    check(Math.abs(list.contentY-before.y)<.1&&Math.abs(list.width-before.width)<.1&&Math.abs(list.height-before.height)<.1,"preference changed scroll offset or pane allocation "+before.name)
    check(list.currentIndex===before.index,"preference changed selected list index "+before.name)
   }
   check(viewport.contentX===oldX,"preference changed horizontal offset")
   for(const name of listNames){
    const list=findChild(music,name)
    check(list!==null && list.ScrollBar.vertical.policy===ScrollBar.AlwaysOff,
     "hidden Music scrollbar policy missing "+name)
   }
   const horizontal=findChild(music,"musicColumnsViewport")
   check(horizontal!==null && horizontal.ScrollBar.horizontal.policy===ScrollBar.AlwaysOff,
    "horizontal Music scrollbar should be hidden")
   for(const name of listNames){
    if(name==="musicGenreList")music.libraryTab="genre"
    if(name==="musicFolderList"||name==="musicPlaylistList")music.libraryTab="folder"
    renderFrame(dashboard,"hidden list pre-pan allocation")
    const list=findChild(music,name),before=list.mapToItem(dashboard,0,0)
    if(before.x<12)music.panHorizontally(12-before.x)
    else if(before.x+list.width>dashboard.width-12)music.panHorizontally(-(before.x+list.width-dashboard.width+12))
    mouseMove(list,Math.min(16,list.width/2),Math.min(24,list.height/2));wait(300)
    renderFrame(dashboard,"hidden list layout")
    check(!list.ScrollBar.vertical.visible&&list.contentHeight>list.height,"hidden scrollbar chrome/overflow "+name)
    // The visible-phase keyboard oracle intentionally selected the last row.
    // Prepare a stable start selection before the independent hidden-wheel
    // oracle, including ListView highlight/focus repositioning after tab reveal.
    list.currentIndex=0;list.positionViewAtBeginning()
    renderFrame(dashboard,"hidden wheel start selection")
    list.cancelFlick();list.contentY=list.originY
    console.info("MUSIC_HIDDEN_BEFORE",name,JSON.stringify({contentY:list.contentY,originY:list.originY,currentIndex:list.currentIndex,moving:list.moving,flicking:list.flicking,dragging:list.dragging,activeFocus:list.activeFocus}))
    mouseWheel(list,Math.min(16,list.width/2),Math.min(24,list.height/2),0,-120);wait(200)
    console.info("MUSIC_HIDDEN_RECEIPT",name,JSON.stringify({at:list.mapToItem(dashboard,0,0),width:list.width,height:list.height,contentHeight:list.contentHeight,contentY:list.contentY,originY:list.originY,windowWidth:dashboard.width,windowHeight:dashboard.height,contentX:horizontal.contentX}))
    check(list.contentY>list.originY+1&&dashboard.currentPage===1,"hidden scrollbar must not block actual wheel "+name)
    list.forceActiveFocus();keyClick(Qt.Key_Down);keyClick(Qt.Key_Down)
    check(list.currentIndex>=1,"hidden scrollbar blocked keyboard "+name)
    list.currentIndex=list.count-1;list.positionViewAtEnd()
    check(list.contentY>list.originY+1,"hidden scrollbar blocked end reveal "+name)
   }
   horizontal.cancelFlick();horizontal.contentX=0
   mouseWheel(horizontal,12,12,-120,0);wait(250)
   check(horizontal.contentX>0&&dashboard.currentPage===1,"hidden scrollbar blocked horizontal wheel or changed page")
   check(music===oldMusic,"scrollbar preference unloaded the music surface")
   check(JSON.stringify(fake.activeQueue)===queueBefore&&JSON.stringify(fake.playlists)===playlistsBefore&&!fake.playing,"preference changed queue/playlist/transport")
   Config.setNestedValue("dashboard.music.showScrollbars",true)
   tryVerify(()=>music.showMusicScrollbars===true,1200)
   check(findChild(music,"musicResultList").ScrollBar.vertical.policy===ScrollBar.AsNeeded
      && horizontal.ScrollBar.horizontal.policy===ScrollBar.AsNeeded,
      "Music scrollbars did not return")
   const settings=Qt.createComponent(Qt.resolvedUrl("modules/settings/DashboardMusicSettings.qml"))
   check(settings.status===Component.Ready,"Music settings failed to compile: "+settings.errorString())
   let page=settings.createObject(window.contentItem,{width:360,x:16,y:16,z:500})
   const toggles=Array.from(page.contentData).filter(item=>item.text===Translation.tr("Show Music scrollbars"))
   check(toggles.length===1,"Music settings must contain exactly one preference checkbox")
   renderFrame(page,"Settings checkbox frame")
   check(toggles[0].width>0&&toggles[0].height>0,"Music settings checkbox has no input bounds")
   mouseClick(toggles[0]);check(Config.options.dashboard.music.showScrollbars===false&&!music.showMusicScrollbars,"actual Settings click did not hide chrome")
   page.destroy();wait(80)
   page=settings.createObject(window.contentItem,{width:360,x:16,y:16,z:500})
   check(Array.from(page.contentData).find(item=>item.text===Translation.tr("Show Music scrollbars")).checked===false,"Settings close/reopen lost preference")
   page.destroy()
   tryVerify(()=>{disk.reload();return disk.snapshot?.dashboard?.music?.showScrollbars===false&&disk.snapshot?.dashboard?.lastPageId==="music"},5000)
   console.info("MUSIC_SCROLL_PASS",root.checks,"checks",root.captures,"rendered frames six overflow lists, hidden/visible preference, wheel and keyboard")
  } catch(e) { console.error("MUSIC_SCROLL_FAIL",e.message,e.stack) } Qt.quit() }
 }
 Timer { interval:100; running:true; onTriggered:test.runChecks() }
}
''')
 with private_wayland(folder) as env:
  if env is None: raise SystemExit("SKIP: Dashboard music requires a private Niri surface")
  config=folder/"config/alis";config.mkdir(parents=True,exist_ok=True)
  data=json.loads((ROOT/"defaults/config.json").read_text());data["panelFamily"]="abyss";data["abyss"]["companion"]["enabled"]=False
  data["dashboard"]["music"].pop("showScrollbars",None)
  (config/"config.json").write_text(json.dumps(data))
  capture=Path(os.environ.get("HADALIS_MUSIC_CAPTURE",str(folder/"dashboard-music.png")))
  env.update(QSG_RHI_BACKEND="opengl",MUSIC_CAPTURE=str(capture),MUSIC_CAPTURE_NARROW=str(capture.with_name(capture.stem+"-narrow.png")))
  result=run_qs(folder,env,timeout=60)
  if os.environ.get("ALIS_MUSIC_SCROLL_LOG"):
   Path(os.environ["ALIS_MUSIC_SCROLL_LOG"]).write_text(result.stdout)
  if result.returncode or "MUSIC_SCROLL_PASS" not in result.stdout or any(x in result.stdout for x in ["MUSIC_SCROLL_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration"]):
   print(result.stdout);raise SystemExit(1)
  saved=json.loads((config/"config.json").read_text())
  assert saved["dashboard"]["music"]["showScrollbars"] is False,"independent disk readback missing OFF preference"
  assert saved["dashboard"]["lastPageId"]=="music","independent disk readback missing selected Music page"
  if os.environ.get("ALIS_MUSIC_SCROLL_LOG"):
   Path(os.environ["ALIS_MUSIC_SCROLL_LOG"]).with_name("config-off.json").write_text(json.dumps(saved["dashboard"],indent=2)+"\n")
  restarted=run_qs(folder,dict(env,MUSIC_SCROLL_ACTION="restart"),timeout=25)
  if os.environ.get("ALIS_MUSIC_SCROLL_LOG"):
   Path(os.environ["ALIS_MUSIC_SCROLL_LOG"]).with_name("restart.log").write_text(restarted.stdout)
  if restarted.returncode or "MUSIC_SCROLL_RESTART_PASS" not in restarted.stdout or any(x in restarted.stdout for x in ["MUSIC_SCROLL_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration"]):
   print(restarted.stdout);raise SystemExit(1)
  print("PASS: six actual Music lists, vertical wheel, themed scrollbar drag and keyboard/end reveal")
  print("PASS: hidden six-list/horizontal wheel, exact allocation/offsets/transport, Settings click/reopen, disk readback and process restart")
