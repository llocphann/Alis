import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
 id:root
 component Snapshot: QtObject {
  property bool mpdConnected:false
  property string error:"before"
  property string mpdHost:"private.invalid"
  property int mpdPort:6600
  property string detectedLibraryFolder:""
  property var libraryTracks:[]
  property var playlists:[]
  property var activeQueue:[]
  property string mpdState:"stop"
  property int currentIndex:-1
  property int resumeIndex:-1
  property real currentPosition:0
  property real currentDuration:0
  property real volume:.5
  property bool shuffleMode:false
  property int repeatMode:0
  property string currentUri:""
  property string currentPath:""
  property string currentTitle:""
  property string currentArtist:""
  property string currentAlbum:""
  property string currentArt:""
      function _applyCurrentTrack(track): void {
        if (!track) {
            currentTitle = currentPath.length > 0
                ? currentPath.substring(currentPath.lastIndexOf("/") + 1) : ""
            currentArtist = ""
            currentAlbum = ""
            currentArt = ""
            return
        }
        currentUri = String(track.uri ?? "")
        currentPath = String(track.path ?? track.uri ?? "")
        currentTitle = String(track.title ?? "")
        currentArtist = String(track.artist ?? "")
        currentAlbum = String(track.album ?? "")
        currentArt = String(track.art ?? "")
        currentDuration = Math.max(0, Number(track.duration ?? currentDuration) || 0)
    }
    function _applyPayload(payload, includeLibrary = false): void {
        if (!payload || payload.connected === false) {
            mpdConnected = false
            if (payload?.error) error = String(payload.error)
            return
        }

        mpdConnected = true
        MprisController.ensureMpdMprisBridge(mpdHost, mpdPort)
        if (String(payload.musicRoot ?? "").length > 0)
            detectedLibraryFolder = String(payload.musicRoot)

        if (includeLibrary) {
            libraryTracks = payload.tracks ?? []
            playlists = payload.playlists ?? []
        }

        if (Array.isArray(payload.queue))
            activeQueue = payload.queue

        const status = payload.status ?? {}
        // MPD can remain connected while its decoder reports a failure.
        // Keep the server's status error visible instead of treating a
        // successful socket poll as successful audio decoding.
        error = String(status.error ?? "").trim()
        mpdState = String(status.state ?? "stop")
        currentIndex = Number(status.song ?? -1)
        if (currentIndex >= 0)
            resumeIndex = currentIndex
        currentPosition = Math.max(0, Number(status.elapsed ?? 0) || 0)
        currentDuration = Math.max(0, Number(status.duration ?? 0) || 0)
        const mpdVolume = Number(status.volume)
        if (Number.isFinite(mpdVolume) && mpdVolume >= 0)
            volume = Math.max(0, Math.min(1, mpdVolume / 100))
        shuffleMode = String(status.random ?? "0") === "1"
        repeatMode = String(status.single ?? "0") === "1"
            ? 1
            : (String(status.repeat ?? "0") === "1" ? 2 : 0)

        const current = payload.current ?? (
            currentIndex >= 0 && currentIndex < activeQueue.length
                ? activeQueue[currentIndex] : null
        )
        if (current) {
            _applyCurrentTrack(current)
        } else {
            const resumable = mpdState === "stop"
                && resumeIndex >= 0 && resumeIndex < activeQueue.length
                ? activeQueue[resumeIndex] : null
            if (resumable) {
                currentIndex = resumeIndex
                currentPosition = 0
                _applyCurrentTrack(resumable)
            } else {
                currentIndex = -1
                currentUri = ""
                currentPath = ""
                currentTitle = ""
                currentArtist = ""
                currentAlbum = ""
                currentArt = ""
                currentDuration = 0
                currentPosition = 0
                if (activeQueue.length === 0)
                    resumeIndex = -1
            }
        }
    }
 }
 Snapshot {id:before}
 Snapshot {id:after}
 FileView {id:full;path:Quickshell.env("FIXTURE_ROOT")+"/full.json";blockLoading:true}
 FileView {id:lean;path:Quickshell.env("FIXTURE_ROOT")+"/lean.json";blockLoading:true}
 property int checks:0
 property var timings:[]
 property int round:0
 property var sink:null
 function check(value,message){checks++;if(!value)throw new Error(message)}
 function parity(){
  const keys=["mpdConnected","error","detectedLibraryFolder","libraryTracks","playlists","activeQueue",
    "mpdState","currentIndex","resumeIndex","currentPosition","currentDuration","volume","shuffleMode",
    "repeatMode","currentUri","currentPath","currentTitle","currentArtist","currentAlbum","currentArt"]
  for(const state of ["play","pause","stop"])for(const song of [-1,0,2,99])for(const library of [false,true]){
   const a=JSON.parse(full.text()),b=JSON.parse(lean.text())
   a.status.state=b.status.state=state;a.status.song=b.status.song=song
   if(song!==0){delete a.current;delete b.current}
   before._applyPayload(a,library);after._applyPayload(b,library)
   for(const key of keys)check(JSON.stringify(before[key])===JSON.stringify(after[key]),key+" changed")
   check(before.activeQueue===a.queue && after.activeQueue===b.queue,"queue identity changed")
   if(library)check(before.libraryTracks===a.tracks && after.libraryTracks===b.tracks,"library identity changed")
  }
  for(const a of [null,{connected:false,error:"offline"},{connected:true},{connected:true,status:{error:"decoder"}}]){
   before._applyPayload(a,true);after._applyPayload(a,true)
   for(const key of keys)check(JSON.stringify(before[key])===JSON.stringify(after[key]),"edge "+key)
  }
  const payload=JSON.parse(full.text())
  Object.defineProperty(payload,"folders",{get(){throw new Error("Unused folders was read")}})
  before._applyPayload(payload,true)
  check(true,"unused folder getter")
 }
 function measure(label){
  const text=label==="full"?full.text():lean.text()
  const start=Date.now()
  for(let i=0;i<8;i++){
   const payload=JSON.parse(text)
   if(payload.tracks.length!==10000)throw new Error("Parse result lost tracks")
   sink=payload.tracks[0].title
  }
  timings.push({round:round,mode:label,milliseconds:Date.now()-start,iterations:8})
 }
 Timer {interval:50;running:true;repeat:true;onTriggered:{try{
  if(root.round===0)root.parity()
  if(Quickshell.env("FIXTURE_BENCHMARK")==="1"){
   if(root.round%2===0){root.measure("full");root.measure("lean")}
   else{root.measure("lean");root.measure("full")}
  }
  root.round++
  if(root.round===(Quickshell.env("FIXTURE_BENCHMARK")==="1"?8:1)){
   console.info("LEAN_QML_RESULT",JSON.stringify({checks:root.checks,timings:root.timings,scope:"QV4 synthetic JSON parse and production interpreter methods; no GPU or whole-shell gain"}))
   Qt.quit()
  }
 }catch(e){console.error("LEAN_QML_FAIL",e.message,e.stack);Qt.quit()}}}
}
