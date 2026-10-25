var edges = ["top","right","bottom","left"];
var osds = ["volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"];
var cornerJoinKinds = ["osd","quickNotes","notificationCenter","notifications","wifi","launcher","leftPanel","rightPanel"].concat(osds);
function key(kind) {
    if (kind==="calendar") return "clock";
    // Wi-Fi and Bluetooth are the same System Tray connectivity surface.
    if (kind==="bluetooth") return "wifi";
    return kind;
}
function canJoin(kind) { return cornerJoinKinds.indexOf(key(kind)) >= 0; }
function resolve(positions, kind, outputName) {
    kind=key(kind);
    var fallback=osds.indexOf(kind)>=0 ? "osd" : ["clock","resources","battery","media","weather","workspaces","tray","audio","wifi","utilities","launcher","dockAppMenu"].indexOf(kind)>=0 ? "popup" : "";
    var list=Array.from(positions || []).filter(function(p) { return p && typeof p==="object"; });
    return list.find(function(p) { return key(p.kind)===kind && p.outputName===outputName; })
        || list.find(function(p) { return key(p.kind)===kind && !p.outputName; })
        || list.find(function(p) { return p.kind===fallback && p.outputName===outputName; })
        || list.find(function(p) { return p.kind===fallback && !p.outputName; }) || {};
}
function edge(position, fallback) { return edges.indexOf(position?.edge)>=0 ? position.edge : fallback; }
function along(position, edge, span, width, height, fallback, insets) {
    if (!position?.alignment || position.alignment==="source") return edges.indexOf(position?.edge)>=0 ? ((edge==="top" || edge==="bottom" ? width : height)-span)/2 : fallback;
    var horizontal=edge==="top" || edge==="bottom";
    var length=horizontal ? width : height;
    var start=(horizontal ? insets?.left : insets?.top) ?? 16;
    var end=Math.max(start,length-((horizontal ? insets?.right : insets?.bottom) ?? 16)-span);
    if (position.alignment==="start") return start;
    if (position.alignment==="end") return end;
    var ratio=position.alignment==="custom" && Number.isFinite(Number(position.position)) ? Math.max(0,Math.min(1,Number(position.position))) : .5;
    return start+(end-start)*ratio;
}
function save(positions, kind, outputName, values) {
    kind=key(kind);
    var result=Array.from(positions || []).filter(function(p) {
        return p && (key(p.kind)!==kind || (p.outputName || "")!==outputName);
    });
    if (values) result.push(Object.assign({},values,{kind:kind,outputName:outputName}));
    return result;
}

function nearbyEdge(edge, along, span, width, height) {
    var horizontal=edge==="top" || edge==="bottom";
    var length=horizontal ? width : height;
    var first=Math.max(0,Number(along)||0);
    var last=Math.max(0,length-first-Math.max(0,Number(span)||0));
    if (Math.min(first,last)>160) return "";
    return horizontal ? (first<=last ? "left" : "right")
        : (first<=last ? "top" : "bottom");
}
function joinedEdge(kind, position, edge, along, span, width, height) {
    if (!canJoin(kind) || position?.joinCorner!==true) return "";
    return nearbyEdge(edge,along,span,width,height);
}
