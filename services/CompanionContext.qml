import QtQuick

// In-process host API. Authentication is the exact loaded session object's
// identity, never a field supplied by a frame. No socket, IPC or global hooks.
Item {
    id:root
    property var owner:null
    property bool permitted:false
    property bool shareFocus:false
    property bool shareAi:false
    property string category:"none"
    property bool aiBusy:false
    property bool aiWaiting:false
    property var clock:()=>Date.now()
    property var peer:null
    property string generation:""
    property double sequence:0
    property double lastClock:-1
    property string agentToken:""
    property bool active:false
    signal frame(string packet)
    signal revoked()

    function nonce(): string {return Qt.md5(String(clock())+":"+Math.random()+":"+Math.random()).slice(0,16)}
    function revoke(): void {
        active=false;peer=null;generation="";sequence=0;lastClock=-1;agentToken=""
        revoked()
    }
    function now(): double {
        const value=clock()
        if(!Number.isSafeInteger(value) || value<0 || value<lastClock){revoke();return -1}
        lastClock=value;return value
    }
    function bind(receiver): var {
        if(!permitted || !owner || receiver!==owner)return null
        revoke()
        const stamp=now()
        if(stamp<0)return null
        peer=receiver;generation=nonce()
        return {version:1,generation:generation,issuedAtMs:stamp}
    }
    function activate(receiver,connection): bool {
        if(!permitted || receiver!==owner || receiver!==peer || !generation || connection!==generation)return false
        active=true;publishFocus();synchronizeAgent();send("heartbeat",({}));return active
    }
    function send(kind,payload): bool {
        if(!active || !permitted || !owner || peer!==owner)return false
        const stamp=now()
        if(stamp<0)return false
        if(sequence>=Number.MAX_SAFE_INTEGER){revoke();return false}
        frame(JSON.stringify({version:1,generation:generation,sequence:++sequence,
            issuedAtMs:stamp,kind:kind,payload:payload}))
        return true
    }
    function publishFocus(): void {
        const value=shareFocus && ["none","terminal","editor","other"].includes(category) ? category : "none"
        send("focus",{category:value})
    }
    function synchronizeAgent(): void {
        if(!active)return
        if(!shareAi || (!aiBusy && !aiWaiting)) {
            if(agentToken){send("agent",{word:"ended",token:agentToken});agentToken=""}
            return
        }
        if(!agentToken){agentToken=nonce();send("agent",{word:"working",token:agentToken})}
        send("agent",{word:aiWaiting ? "needs_input" : "activity",token:agentToken})
    }
    function finished(): void {
        if(active && shareAi && agentToken && !aiWaiting){send("agent",{word:"finished",token:agentToken});agentToken=""}
    }
    onOwnerChanged: revoke()
    onPermittedChanged: if(!permitted)revoke()
    onShareFocusChanged: publishFocus()
    onCategoryChanged: publishFocus()
    onShareAiChanged: if(!shareAi)synchronizeAgent()
    // A short transition between tool approval and resumed generation must not
    // manufacture a completion. Only Alis' actual completion signal does that.
    onAiBusyChanged: if(active)agentSettle.restart()
    onAiWaitingChanged: if(active)agentSettle.restart()
    Timer {id:agentSettle;interval:100;onTriggered:root.synchronizeAgent()}
    Timer {interval:5000;repeat:true;running:root.active && root.permitted;onTriggered:{
        root.synchronizeAgent();root.send("heartbeat",({}))
    }}
    Component.onDestruction: revoke()
}
