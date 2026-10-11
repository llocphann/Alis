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
   tryCompare(Config,"ready",true,6000)
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
   Config.setNestedValue("dashboard.music.showScrollbars",false)
   tryVerify(()=>music.showMusicScrollbars===false,1200)
   for(const name of listNames){
    const list=findChild(music,name)
    check(list!==null && list.ScrollBar.vertical.policy===ScrollBar.AlwaysOff,
     "hidden Music scrollbar policy missing "+name)
   }
   const horizontal=findChild(music,"musicColumnsViewport")
   check(horizontal!==null && horizontal.ScrollBar.horizontal.policy===ScrollBar.AlwaysOff,
    "horizontal Music scrollbar should be hidden")
   music.libraryTab="genre"
   const results=findChild(music,"musicResultList")
   results.contentY=results.originY
   mouseMove(results,15,20);wait(150)
   mouseWheel(results,15,20,0,-120);wait(200)
   check(results.contentY>results.originY+1 && dashboard.currentPage===1,
    "hidden scrollbar must not block real vertical wheel")
   check(music===oldMusic,"scrollbar preference unloaded the music surface")
   Config.setNestedValue("dashboard.music.showScrollbars",true)
   tryVerify(()=>music.showMusicScrollbars===true,1200)
   check(results.ScrollBar.vertical.policy===ScrollBar.AsNeeded
      && horizontal.ScrollBar.horizontal.policy===ScrollBar.AsNeeded,
      "Music scrollbars did not return")
   console.info("MUSIC_SCROLL_PASS six overflow lists, hidden/visible preference, wheel and keyboard")
  } catch(e) { console.error("MUSIC_SCROLL_FAIL",e.message,e.stack) } Qt.quit() }
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
  result=run_qs(folder,env,timeout=60)
  if os.environ.get("ALIS_MUSIC_SCROLL_LOG"):
   Path(os.environ["ALIS_MUSIC_SCROLL_LOG"]).write_text(result.stdout)
  if result.returncode or "MUSIC_SCROLL_PASS" not in result.stdout or any(x in result.stdout for x in ["MUSIC_SCROLL_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration"]):
   print(result.stdout);raise SystemExit(1)
  print("PASS: six actual Music lists, vertical wheel, themed scrollbar drag and keyboard/end reveal")
