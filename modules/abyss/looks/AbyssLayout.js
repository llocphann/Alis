// Persist normalized positions; derive pixel geometry independently per output.
var catalog = ["distroIcon","activeWindow","resources","media",
    "workspaces","clock","utilButtons","battery","tray",
    "timer","shellUpdate","weather","taskbar","notesTimers","notificationActivity"];
var labels = {distroIcon:"Launcher",activeWindow:"Active window",
    resources:"System resources",media:"Media",workspaces:"Workspaces",clock:"Clock",
    utilButtons:"Quick actions",battery:"Battery",tray:"System tray",
    timer:"Timer",shellUpdate:"Updates",weather:"Weather",taskbar:"Taskbar",
    notesTimers:"QuickNotes & Timers",notificationActivity:"Notifications & Activities"};
function isUnifiedKind(kind) { return kind === "notesTimers" || kind === "notificationActivity"; }
function unifiedLauncherMode(options) {
    return options?.launcherMode === "edgebar" ? "edgebar" : "module";
}
// In Edgebar mode the legacy corner is the *sole* source. The module's
// persisted placement and icon preference remain intact for mode reversal.
function livePlacements(placements, options, editing) {
    var all=normalize(placements,"top");
    return editing || unifiedLauncherMode(options)==="module" ? all
        : all.filter(function(p) { return !isUnifiedKind(p.kind); });
}
// Legacy corner launchers stay available until an enabled replacement is
// actually installed on this output. No mutation or destructive migration.
function hasEnabledModule(options,outputName,kind) {
    return resolve(options,outputName,[]).some(function(p) {
        return p.enabled && p.kind === kind;
    });
}
function label(kind) { return labels[kind] || kind; }
function bounded(value, fallback, low, high) {
    var number = Number(value);
    return Number.isFinite(number) ? Math.max(low,Math.min(high,number)) : fallback;
}
function extent(kind, vertical) {
    var sizes = {utilButtons:36,distroIcon:88,
        activeWindow:178,resources:178,media:166,workspaces:192,clock:104,battery:72,
        tray:72,timer:68,shellUpdate:86,weather:80,taskbar:40,
        notesTimers:36,notificationActivity:36};
    // A side Edge rotates this same full design, so its along-axis extent
    // remains the horizontal width. It never chooses a compact substitute.
    return sizes[kind] || 48;
}
function normalize(list, fallbackEdge) {
    var seen = {};
    return Array.from(list || []).filter(function(p) {
        if (!p || catalog.indexOf(String(p.kind)) < 0) return false;
        var id = String(p.id || p.kind);
        if (seen[id]) return false;
        seen[id] = true;
        return true;
    }).slice(0,24).map(function(p) {
        return {id:String(p.id || p.kind),kind:String(p.kind),
            edge:["top","right","bottom","left"].indexOf(p.edge)>=0 ? p.edge : fallbackEdge,
            position:bounded(p.position,0.5,0,1),enabled:p.enabled !== false,
            alignment:["start","center","end"].indexOf(p.alignment)>=0 ? p.alignment : "free",
            customSize:p.customSize === true || (p.customSize === undefined && Number.isFinite(Number(p.size)) && Number(p.size)!==1),
            size:bounded(p.size,1,0.6,1.8),depth:bounded(p.depth,1,0.5,2),
            influence:bounded(p.influence,1,0,2),compact:p.compact === true,joinCorner:p.joinCorner === true,
            showIcon:p.showIcon !== false,
            locked:p.locked === true,
            lockPosition:p.locked === true ? bounded(p.lockPosition,bounded(p.position,.5,0,1),0,1) : undefined,
            lockScale:p.locked === true ? bounded(p.lockScale,1,.01,1) : undefined};
    });
}
function seed(zones, edge, width, height) {
    var vertical = edge === "left" || edge === "right";
    var length = vertical ? height : width;
    var result = [];
    zones.forEach(function(ids, group) {
        var total = ids.reduce(function(sum,kind) { return sum+extent(kind,vertical)+8; },0)-8;
        var cursor = (group+0.5)*length/5-total/2;
        ids.forEach(function(kind) {
            var size = extent(kind,vertical);
            result.push({id:kind,kind:kind,edge:edge,position:(cursor+size/2)/Math.max(1,length)});
            cursor += size+8;
        });
    });
    return normalize(result,edge);
}
// New installations and existing layouts opt into these two launchers by
// default, without changing stored placements. Explicit per-output or global
// Done records a durable migration marker, so removing an entry never causes
// it to reappear after restart. With autoUnifiedEdgeLaunchers disabled, callers
// that construct temporary/baseline layout objects remain unchanged.
function withUnifiedEdgeModules(placements, shouldAdd) {
    var normalized = normalize(placements,"top");
    if (!shouldAdd) return normalized;
    var defaults=[
        {id:"notesTimers",kind:"notesTimers",edge:"bottom",position:.065,showIcon:true},
        {id:"notificationActivity",kind:"notificationActivity",edge:"bottom",position:.935,showIcon:true}
    ];
    defaults.forEach(function(p) {
        if (!normalized.some(function(entry) { return entry.kind===p.kind; })
                && normalized.length<24)
            normalized.push(p);
    });
    return normalize(normalized,"top");
}
function resolve(options, outputName, fallback) {
    var profiles = Array.from(options?.outputLayouts || []);
    var profile = profiles.find(function(p) { return p.outputName === outputName; });
    // Output-specific overrides independently remember completed migrations.
    // A global editor save must not accidentally suppress first-run launchers
    // on an unrelated output with its own older legacy profile.
    if (profile) return withUnifiedEdgeModules(profile.placements,
        options?.autoUnifiedEdgeLaunchers===true
        && profile.unifiedLaunchersConfigured!==true);
    return withUnifiedEdgeModules(options?.configured
        ? options.placements : fallback,
        options?.autoUnifiedEdgeLaunchers===true
        && options?.unifiedLaunchersConfigured!==true);
}
// QML JsonObject also enumerates QObject signals. Persist only the four owned
// Edge fields, never objectNameChanged/destroyed or other QObject internals.
function edgeMap(base,overrides) {
    var result={};
    ["top","right","bottom","left"].forEach(function(edge) {
        var value=overrides?.[edge]!==undefined ? overrides[edge] : base?.[edge];
        if(value!==undefined)result[edge]=value;
    });
    return result;
}
function optionsForOutput(options, outputName) {
    var profile = Array.from(options?.outputLayouts || []).find(function(p) { return p.outputName === outputName; });
    return Object.assign({},options,{gap:profile?.gap ?? options?.gap ?? 8,
        size:bounded(profile?.size ?? options?.size,1,.6,1.8),
        edgeSizes:edgeMap(options?.edgeSizes,profile?.edgeSizes),
        edgeThicknesses:edgeMap(options?.edgeThicknesses,profile?.edgeThicknesses),
        edgeWidthAffectsModules:edgeMap(options?.edgeWidthAffectsModules,profile?.edgeWidthAffectsModules),
        edgeJoinModules:edgeMap(options?.edgeJoinModules,profile?.edgeJoinModules),
        edgeModuleRadii:edgeMap(options?.edgeModuleRadii,profile?.edgeModuleRadii),
        edgeRoundZeroCorners:edgeMap(options?.edgeRoundZeroCorners,profile?.edgeRoundZeroCorners),
        singleModuleExpansion:edgeMap(options?.singleModuleExpansion,profile?.singleModuleExpansion)});
}
function edgeSize(options, edge) { return bounded(options?.edgeSizes?.[edge],1,.6,1.8); }
function edgeThickness(options, edge, fallback) {
    var inherited=bounded(fallback ?? options?.edgeThickness,16,0,40);
    var value=options?.edgeThicknesses?.[edge];
    return Number.isFinite(Number(value)) && Number(value)>=0 ? bounded(value,inherited,0,40) : inherited;
}
function moduleSize(placement, options) {
    var inheritedWidth=options?.edgeWidthAffectsModules?.[placement.edge]===false
        ? bounded(options?.edgeThickness,16,10,40) : edgeThickness(options,placement.edge);
    // Unified launchers must retain a bounded physical hover target when the
    // decorative Edge is 0px. Hiding their icon never removes the hit zone.
    var width = isUnifiedKind(placement.kind) ? Math.max(12,inheritedWidth) : inheritedWidth;
    return (placement.customSize ? placement.size : edgeSize(options,placement.edge)*width/16)*bounded(options?.size,1,.6,1.8);
}
function project(x, y, width, height, preferredEdge) {
    var distances = [y,width-x,height-y,x];
    var index = distances.indexOf(Math.min.apply(null,distances));
    var edge = ["top","right","bottom","left"].indexOf(preferredEdge)>=0 ? preferredEdge : ["top","right","bottom","left"][index];
    index=["top","right","bottom","left"].indexOf(edge);
    return {edge:edge,position:bounded((index%2===0 ? x : y)/Math.max(1,index%2===0 ? width : height),.5,0,1)};
}
function move(placements, id, x, y, width, height, preferredEdge) {
    if (placements.some(function(p) { return p.id===id && p.locked; })) return normalize(placements,"top");
    var location = project(x,y,width,height,preferredEdge);
    return normalize(placements.map(function(p) { return p.id===id ? Object.assign({},p,location,{alignment:"free"}) : p; }),"top");
}
// Snap to the output center, end margins, and adjacent modules at the configured gap.
// Guides are presentation data only; positions stay normalized for other resolutions.
function snapMove(placements, id, x, y, width, height, options, fontScale) {
    if (placements.some(function(p) { return p.id===id && p.locked; })) return {placements:normalize(placements,"top"),guides:[],rejected:"Unlock this module before moving it"};
    var moved = move(placements,id,x,y,width,height,options?.dragEdge);
    var selected = moved.find(function(p) { return p.id===id; });
    if (!selected) return {placements:moved,guides:[]};
    var horizontal = selected.edge==="top" || selected.edge==="bottom";
    var length = horizontal ? width : height;
    var usable = length;
    var records = geometry(moved,width,height,options,fontScale);
    var own = records.find(function(p) { return p.id===id; });
    if (!own || usable<=0) return {placements:moved,guides:[]};
    var low=own.edgeStart,high=own.edgeEnd;
    var center = selected.position*usable;
    var gap = bounded(options?.gap,8,0,32);
    var targets = [{center:length/2,line:length/2,label:"Center"},
        {center:low+own.span/2,line:low,label:"Start"},
        {center:high-own.span/2,line:high,label:"End"}];
    geometry(moved.filter(function(p) { return p.id!==id; }),width,height,options,fontScale)
        .filter(function(p) { return p.edge===selected.edge; }).forEach(function(p) {
        targets.push({center:p.along-gap-own.span/2,line:p.along-gap,label:Math.round(gap)+" px gap"});
        targets.push({center:p.along+p.span+gap+own.span/2,line:p.along+p.span+gap,label:Math.round(gap)+" px gap"});
    });
    var target = targets.filter(function(t) { return t.center-own.span/2>=low && t.center+own.span/2<=high; })
        .sort(function(a,b) { return Math.abs(a.center-center)-Math.abs(b.center-center); })[0];
    if (!target || Math.abs(target.center-center)>10) return {placements:moved,guides:[]};
    moved = moved.map(function(p) { return p.id===id ? Object.assign({},p,{position:target.center/usable}) : p; });
    var actual = geometry(moved,width,height,options,fontScale).find(function(p) { return p.id===id; });
    // Do not show a misleading guide when collision packing prevented this snap.
    return {placements:moved,guides:Math.abs(actual.along+actual.span/2-target.center)<1
        ? [{horizontal:horizontal,along:target.line,label:target.label}] : []};
}
// Capture the displayed center and compression, not a neighbor-dependent aligned
// group's future position. Anchors are normalized independently on each output.
function setLocked(placements,id,locked,width,height,options,fontScale,displayedRecords) {
    var records=locked ? (displayedRecords || geometry(placements,width,height,options,fontScale)) : [];
    return normalize(placements.map(function(p) {
        if(p.id!==id) return p;
        var record=records.find(function(r) {return r.id===id;});
        return lockPlacement(p,record,locked,width,height,options,fontScale);
    }),"top");
}
function lockPlacement(p,record,locked,width,height,options,fontScale) {
    if(!locked)return Object.assign({},p,{locked:false});
    if(p.locked)return p;
    var horizontal=p.edge==="top" || p.edge==="bottom",length=horizontal ? width : height;
    var measured=options?.extents?.[p.id];
    var natural=Number.isFinite(measured) && !(options?.editing && measured<1) ? Math.max(0,measured)
        : extent(p.kind,!horizontal)*bounded(fontScale,1,.7,2);
    return Object.assign({},p,{locked:true,
        lockPosition:record && length>0 ? (record.along+record.span/2)/length : p.position,
        lockScale:record && natural*moduleSize(p,options)>0 ? record.span/(natural*moduleSize(p,options)) : 1});
}
function conflicts(records) {
    var result=[];
    records.forEach(function(p) {
        var message=p.capacityConflict || p.lockConflict;
        if(message && result.indexOf(message)<0)result.push(message);
    });
    return result;
}
// The editor relocates for a real geometric obstruction, not for a change in
// selected/edited Edge or the number of modules elsewhere on that Edge.
// A 3px intersection on each axis is ignored to avoid one-pixel drag jitter.
function toolbarOverlapArea(a,b) {
    if (!a || !b || !(a.width>0 && a.height>0 && b.width>0 && b.height>0)) return 0;
    var width=Math.max(0,Math.min(a.x+a.width,b.x+b.width)-Math.max(a.x,b.x));
    var height=Math.max(0,Math.min(a.y+a.height,b.y+b.height)-Math.max(a.y,b.y));
    return width>3 && height>3 ? width*height : 0;
}
function toolbarObstruction(footprint,records,previewRects) {
    if (!footprint) return 0;
    var area=0;
    (records || []).forEach(function(record) {
        if (record && record.enabled!==false && !record.capacityConflict && record.content)
            area+=toolbarOverlapArea(footprint,record.content);
    });
    (previewRects || []).forEach(function(rect) {
        area+=toolbarOverlapArea(footprint,rect);
    });
    return area;
}
function toolbarEdgeForRects(currentEdge,footprints,records,previewRects) {
    var edges=["bottom","top","right","left"];
    if (edges.indexOf(currentEdge)<0 || !footprints?.[currentEdge]) return "bottom";
    var currentArea=toolbarObstruction(footprints[currentEdge],records,previewRects);
    // Empty (or merely adjacent) stays put, even if other Edges are emptier.
    if (currentArea<=0) return currentEdge;
    var best=currentEdge,bestArea=currentArea;
    edges.forEach(function(edge) {
        if (edge===currentEdge || !footprints[edge]) return;
        var area=toolbarObstruction(footprints[edge],records,previewRects);
        // A small improvement alone must not cause an edge-to-edge oscillation.
        if (area+4<bestArea) {best=edge;bestArea=area;}
    });
    return best;
}

function checkedMove(placements,id,x,y,width,height,options,fontScale,snap) {
    var p=placements.find(function(p) {return p.id===id;});
    if(!p)return {placements:placements,guides:[],rejected:"This module is no longer available"};
    if(p?.locked)return {placements:placements,guides:[],rejected:"Unlock this module before moving it"};
    var result=snap ? snapMove(placements,id,x,y,width,height,options,fontScale) : {placements:move(placements,id,x,y,width,height,options?.dragEdge),guides:[]};
    var failures=conflicts(geometry(result.placements,width,height,options,fontScale));
    if(failures.length)return {placements:placements,guides:[],rejected:failures[0]};
    return result;
}
// Selection is editor state, never persisted with a placement. Every batch is
// validated in full before changing any target; stale IDs cannot become a
// partial transaction after a concurrent remove or a reset.
function selectedModules(placements,ids) {
    var unique=Array.from(new Set(Array.from(ids || [])));
    return {ids:unique,items:unique.map(function(id) {return placements.find(function(p) {return p.id===id;});})};
}
function checkedBatch(placements,ids,action,value,width,height,options,fontScale,displayedRecords) {
    var selection=selectedModules(placements,ids),items=selection.items;
    function deny(message) {return {placements:placements,rejected:message};}
    if(!items.length)return deny("Select a module first");
    if(items.some(function(p) {return !p;}))return deny("The selection changed. Select the modules again.");
    var placementKeys=["edge","position","alignment","size","customSize","depth"];
    if(placementKeys.indexOf(action)>=0 && items.some(function(p) {return p.locked;}))
        return deny("Unlock every selected module before changing its placement or size");
    if(["remove","locked","enabled","joinCorner","showIcon"].concat(placementKeys).indexOf(action)<0)
        return deny("This action cannot be applied to modules");
    if(action==="showIcon" && items.some(function(p) {return !isUnifiedKind(p.kind);}))
        return deny("Only unified edge launchers support hiding their icons");
    var records=(action==="locked" || action==="joinCorner") && value ? (displayedRecords || geometry(placements,width,height,options,fontScale)) : [];
    if(action==="joinCorner" && value && items.some(function(p) {
        return !cornerForModule(records,p.id,width,height);
    }))return deny("Every selected module must be beside a corner to connect the group");
    var proposed=placements.filter(function(p) {return action!=="remove" || selection.ids.indexOf(p.id)<0;})
        .map(function(p) {
            if(selection.ids.indexOf(p.id)<0)return p;
            if(action==="locked") {
                // Capture all anchors from the same rendered layout.
                var own=records.find(function(r) {return r.id===p.id;});
                return lockPlacement(p,own,!!value,width,height,options,fontScale);
            }
            var update={};update[action]=value;
            if(action==="customSize" && value && !p.customSize)update.size=edgeSize(options,p.edge);
            return Object.assign({},p,update);
        });
    proposed=normalize(proposed,"top");
    var failures=conflicts(geometry(proposed,width,height,options,fontScale));
    // A saved overfull layout can be repaired in several steps. Removing,
    // disabling or unlocking must remain available until the final layout fits.
    var repair=action==="remove" || (action==="enabled" && !value) || (action==="locked" && !value);
    if(failures.length && !repair)return deny(failures[0]);
    return {placements:proposed,rejected:""};
}
// Move a same-Edge group as one transaction using the production geometry.
// Preserve rendered offsets on that Edge. Across Edges, retain ordering and
// visible gaps while adapting spans to the destination's orientation/scale.
// A mixed-Edge selection has batch controls but cannot be dragged as one row.
function checkedGroupMove(placements,ids,primaryId,x,y,width,height,options,fontScale,snap,originRecords) {
    var selection=selectedModules(placements,ids),items=selection.items;
    function deny(message) {return {placements:placements,guides:[],rejected:message};}
    if(!items.length || selection.ids.indexOf(primaryId)<0 || items.some(function(p) {return !p;}))
        return deny("The selection changed. Select the modules again.");
    if(items.length===1)return checkedMove(placements,primaryId,x,y,width,height,options,fontScale,snap);
    if(items.some(function(p) {return p.locked;}))return deny("Unlock every selected module before dragging the group");
    var sourceEdge=items[0].edge;
    if(items.some(function(p) {return p.edge!==sourceEdge;}))return deny("Select modules on one Edge to drag together. Batch controls work across Edges.");
    var source=(originRecords || geometry(placements,width,height,options,fontScale)).filter(function(r) {return selection.ids.indexOf(r.id)>=0;})
        .sort(function(a,b) {return a.along-b.along || a.id.localeCompare(b.id);});
    if(source.length!==items.length || source.some(function(p) {return p.span<=0;}))
        return deny("Enable and show every selected module before dragging the group");
    var location=project(x,y,width,height,options?.dragEdge),horizontal=location.edge==="top" || location.edge==="bottom";
    var length=horizontal ? width : height;
    var candidate=placements.map(function(p) {return selection.ids.indexOf(p.id)>=0
        ? Object.assign({},p,{edge:location.edge,alignment:"free",position:(source.findIndex(function(r) {return r.id===p.id;})+1)/(items.length+1)}) : p;});
    var destination=geometry(candidate,width,height,options,fontScale);
    var offsets=[],cursor=0;
    for(var i=0;i<source.length;i++) {
        var record=destination.find(function(r) {return r.id===source[i].id;});
        if(!record)return deny("This Edge hides a selected module. Adjust its width or size first.");
        if(i)cursor+=Math.max(0,source[i].along-source[i-1].along-source[i-1].span);
        offsets.push({id:source[i].id,along:cursor,span:record.span});cursor+=record.span;
    }
    var bounds=destination.find(function(r) {return r.id===primaryId;});
    var low=bounds?.edgeStart ?? cornerInset(options,fontScale,length),high=bounds?.edgeEnd ?? length-low;
    if(cursor>high-low+1e-6)return deny("The selected group cannot fit on this Edge");
    var primary=offsets.find(function(p) {return p.id===primaryId;});
    var start=Math.max(low,Math.min(high-cursor,location.position*length-primary.along-primary.span/2)),guides=[];
    if(snap) {
        var targets=[{start:low,line:low,label:"Start"},{start:(length-cursor)/2,line:length/2,label:"Center"},
            {start:high-cursor,line:high,label:"End"}];
        var gap=bounded(options?.gap,8,0,32);
        geometry(placements.filter(function(p) {return selection.ids.indexOf(p.id)<0;}),width,height,options,fontScale)
            .filter(function(p) {return p.edge===location.edge;}).forEach(function(p) {
                targets.push({start:p.along-gap-cursor,line:p.along-gap,label:Math.round(gap)+" px gap"});
                targets.push({start:p.along+p.span+gap,line:p.along+p.span+gap,label:Math.round(gap)+" px gap"});
            });
        var target=targets.filter(function(t) {return t.start>=low && t.start+cursor<=high;})
            .sort(function(a,b) {return Math.abs(a.start-start)-Math.abs(b.start-start);})[0];
        if(target && Math.abs(target.start-start)<=10){start=target.start;guides=[{horizontal:horizontal,along:target.line,label:target.label}];}
    }
    // Fit the whole group into one free band rather than letting a neighbor
    // split its members during the normal collision pass. Keep every outsider's
    // placement/lock intent intact; reject if no contiguous band is available.
    var outsiders=geometry(placements.filter(function(p) {return selection.ids.indexOf(p.id)<0;}),width,height,options,fontScale)
        .filter(function(r) {return r.edge===location.edge&&!r.capacityConflict;})
        .sort(function(a,b) {return a.along-b.along;});
    var bands=[],cursorEnd=low,spacing=bounded(options?.gap,8,0,32);
    outsiders.forEach(function(r) {bands.push({start:cursorEnd,end:Math.max(cursorEnd,r.along-spacing)});cursorEnd=Math.max(cursorEnd,r.along+r.span+spacing);});
    bands.push({start:cursorEnd,end:high});
    var fits=bands.filter(function(b) {return b.end-b.start>=cursor-1e-7;})
        .map(function(b) {return Math.max(b.start,Math.min(b.end-cursor,start));})
        .sort(function(a,b) {return Math.abs(a-start)-Math.abs(b-start) || a-b;});
    if(!fits.length)return deny("The group is blocked here. Move it to free space or move modules separately.");
    if(Math.abs(fits[0]-start)>.05)guides=[];
    start=fits[0];
    candidate=normalize(candidate.map(function(p) {
        var offset=offsets.find(function(r) {return r.id===p.id;});
        return offset ? Object.assign({},p,{position:(start+offset.along+offset.span/2)/length}) : p;
    }),"top");
    var actual=geometry(candidate,width,height,options,fontScale),failures=conflicts(actual);
    if(failures.length)return deny(failures[0]);
    if(offsets.some(function(p) {
        var r=actual.find(function(r) {return r.id===p.id;});
        return !r || Math.abs(r.along-start-p.along)>.05 || Math.abs(r.span-p.span)>.05;
    }))return deny("The group is blocked here. Move it to free space or move modules separately.");
    return {placements:candidate,guides:guides,rejected:""};
}
function saveProfile(options, outputName, placements, gap, outputOnly, edgeSizes, singleModuleExpansion, size, edgeThicknesses, edgeWidthAffectsModules, edgeJoinModules, edgeModuleRadii, edgeRoundZeroCorners) {
    var normalized = normalize(placements,"top");
    var profiles = Array.from(options?.outputLayouts || []);
    var current = optionsForOutput(options,outputName);
    var expansion = edgeMap(singleModuleExpansion ?? current.singleModuleExpansion);
    var scale = bounded(size ?? current.size,1,.6,1.8);
    var thicknesses = edgeMap(edgeThicknesses ?? current.edgeThicknesses);
    var affects = edgeMap(edgeWidthAffectsModules ?? current.edgeWidthAffectsModules);
    var joins = edgeMap(edgeJoinModules ?? current.edgeJoinModules);
    var radii = edgeMap(edgeModuleRadii ?? current.edgeModuleRadii);
    var zeroCorners=edgeMap(edgeRoundZeroCorners ?? current.edgeRoundZeroCorners);
    if (outputOnly) {
        var existing = profiles.find(function(p) { return p.outputName===outputName; });
        profiles = profiles.filter(function(p) { return p.outputName!==outputName; });
        profiles.push(Object.assign({},existing,{outputName:outputName,placements:normalized,unifiedLaunchersConfigured:true,gap:bounded(gap,8,0,32),
            edgeSizes:edgeMap(edgeSizes ?? current.edgeSizes),singleModuleExpansion:expansion,size:scale,edgeThicknesses:thicknesses,edgeWidthAffectsModules:affects,edgeJoinModules:joins,edgeModuleRadii:radii,edgeRoundZeroCorners:zeroCorners}));
        return {"abyss.modules.outputLayouts":profiles};
    }
    return {"abyss.modules.configured":true,"abyss.modules.unifiedLaunchersConfigured":true,"abyss.modules.placements":normalized,
        "abyss.modules.gap":bounded(gap,8,0,32),"abyss.modules.outputLayouts":profiles.filter(function(p) { return p.outputName!==outputName; }),
        "abyss.modules.edgeSizes":edgeMap(edgeSizes ?? options?.edgeSizes),
        "abyss.modules.singleModuleExpansion":expansion,"abyss.modules.size":scale,
        "abyss.modules.edgeThicknesses":thicknesses,"abyss.modules.edgeWidthAffectsModules":affects,"abyss.modules.edgeJoinModules":joins,"abyss.modules.edgeModuleRadii":radii,"abyss.modules.edgeRoundZeroCorners":zeroCorners};
}
function stripDepth(placements, edge, options, fontScale) {
    return placements.filter(function(p) { return p.enabled && p.edge===edge; }).reduce(function(depth,p) {
        return moduleSize(p,options)>0
            ? Math.max(depth,32*bounded(fontScale,1,.7,2)*moduleSize(p,options)*p.depth+16) : depth;
    },0);
}
function edgeInsetsForModules(placements, options, fontScale, thickness, minimum, reservation) {
    var insets = {};
    ["top","right","bottom","left"].forEach(function(edge) {
        insets[edge]=edgeThickness(options,edge,thickness);
        // A configured 0px Edge has no continuous paint strip. Its modules
        // already supply localSurfaces; only Wayland reservations span the
        // whole side to keep application windows clear of that foreground.
        if(!reservation && insets[edge]===0)return;
        var enabled = placements.filter(function(p) { return p.enabled && p.edge===edge && moduleSize(p,options)>0; });
        if (!enabled.length) return;
        // Wayland reserves a whole edge. Local paint still reserves enough room
        // for its module so application windows cannot obscure that foreground.
        if (reservation || (options?.edgeWidthAffectsModules?.[edge]!==false
                && (enabled.length!==1 || options?.singleModuleExpansion?.[edge]!=="local")))
            insets[edge] = Math.max(insets[edge],minimum,stripDepth(placements,edge,options,fontScale));
    });
    return insets;
}
function localSurfaces(records, width, height, options, fontScale, minimum) {
    records=records.filter(function(p) {return !p.capacityConflict;});
    var surfaces=records.filter(function(p) {
        return edgeThickness(options,p.edge)===0 || options?.edgeWidthAffectsModules?.[p.edge]===false || options?.singleModuleExpansion?.[p.edge]==="local"
            && records.filter(function(other) { return other.edge===p.edge; }).length===1;
    }).map(function(p) {
        // Geometry records express depth in pixels, unlike placement depth's
        // multiplier. Derive the paint extent from the packed foreground.
        var depth = Math.max(minimum,(p.vertical ? p.content.width : p.content.height)+16);
        var surface = p.edge==="top" ? {x:p.along-8,y:-50,width:p.span+16,height:depth+50}
            : p.edge==="bottom" ? {x:p.along-8,y:height-depth,width:p.span+16,height:depth+50}
            : p.edge==="left" ? {x:-50,y:p.along-8,width:depth+50,height:p.span+16}
            : {x:width-depth,y:p.along-8,width:depth+50,height:p.span+16};
        var along=p.along,span=p.span;
        var corner=p.joinCorner ? cornerForModule(records,p.id,width,height) : "";
        if(corner) {
            var horizontal=p.edge==="top" || p.edge==="bottom";
            var length=horizontal ? width : height;
            var start=corner==="left" || corner==="top";
            if(horizontal) {
                if(start) { surface.width+=surface.x+50;surface.x=-50; }
                else surface.width=width+50-surface.x;
            } else {
                if(start) { surface.height+=surface.y+50;surface.y=-50; }
                else surface.height=height+50-surface.y;
            }
            span=start ? p.along+p.span : length-p.along;
            along=start ? 0 : p.along;
        }
        var record={edge:p.edge,surface:surface,content:p.content,span:span,along:along,depth:depth,progress:1,mass:1};
        var radius=options?.edgeModuleRadii?.[p.edge];
        if(options?.edgeWidthAffectsModules?.[p.edge]===false && Number.isFinite(Number(radius)) && Number(radius)>=0)
            record.radius=bounded(radius,0,0,64);
        return record;
    });
    var result=[],nearby=bounded(options?.gap,8,0,32)+16;
    surfaces.forEach(function(record) {
        var previous=result[result.length-1];
        if(options?.edgeWidthAffectsModules?.[record.edge]===false && options?.edgeJoinModules?.[record.edge]===true
                && previous?.edge===record.edge && record.along-previous.along-previous.span<=nearby) {
            // Only paint is joined. Packed module items and their input bounds
            // keep their identities and dimensions, including mixed depths.
            previous.span=Math.max(previous.span,record.along+record.span-previous.along);
            previous.depth=Math.max(previous.depth,record.depth);
            var a=previous.surface,b=record.surface;
            var x=Math.min(a.x,b.x),y=Math.min(a.y,b.y);
            previous.surface={x:x,y:y,width:Math.max(a.x+a.width,b.x+b.width)-x,height:Math.max(a.y+a.height,b.y+b.height)-y};
        } else result.push(record);
    });
    return result;
}
function clearanceInsets(insets, localRecords, edge, along, span) {
    var result=Object.assign({},insets);
    localRecords.forEach(function(record) {
        if(record.edge===edge && record.along-8<along+span && record.along+record.span+8>along)
            result[edge]=Math.max(result[edge],record.depth);
    });
    return result;
}
// Solve contiguous unlocked groups in the free intervals between immutable
// reservations. A bounded dynamic program preserves their relative order and
// chooses the closest feasible full-size packing, without automatic shrinking.
function packLockedEdge(list,sizes,length,gap,options,horizontal,low,high) {
    low=low ?? 0;high=high ?? length;
    function record(p,start,span,scale) {
        return Object.assign({},p,{along:start,span:span,layoutScale:scale,vertical:!horizontal,
            depth:bounded(options?.depth,36,22,64)*p.depth,
            compact:p.compact});
    }
    var locked=[],free=[];
    list.forEach(function(p,i) {
        if(p.locked) {
            var scale=bounded(p.lockScale,1,.01,1),span=sizes[i]*scale;
            locked.push(record(p,bounded(p.lockPosition,p.position,0,1)*length-span/2,span,scale));
        } else free.push({p:p,size:sizes[i],center:p.position*length});
    });
    locked.sort(function(a,b) {return a.along-b.along || a.id.localeCompare(b.id);});
    var end=low-gap;
    for(var i=0;i<locked.length;i++) {
        var own=locked[i];
        if(own.along<low-1e-7 || own.along+own.span>high+1e-7)
            return {error:"A locked module no longer fits this output. Undo the size change or unlock it."};
        if(own.along<end-1e-7)
            return {error:"Locked modules overlap at this size. Undo the size change or unlock them."};
        if(i>0)gap=Math.min(gap,Math.max(0,own.along-end));
        end=own.along+own.span;
    }
    ["start","center","end"].forEach(function(alignment) {
        var group=free.filter(function(item) {return item.p.alignment===alignment;});
        var span=group.reduce(function(sum,item) {return sum+item.size;},0)+Math.max(0,group.length-1)*gap;
        var cursor=alignment==="start" ? low : alignment==="end" ? high-span : (length-span)/2;
        group.forEach(function(item) {item.center=cursor+item.size/2;cursor+=item.size+gap;});
    });
    free.sort(function(a,b) {return a.center-b.center || a.p.id.localeCompare(b.p.id);});
    var intervals=[],cursor=low;
    locked.forEach(function(p) {intervals.push({start:cursor,end:Math.max(cursor,p.along-gap)});cursor=p.along+p.span+gap;});
    intervals.push({start:Math.min(high,cursor),end:high});
    function pack(start,count,interval) {
        if(!count)return {records:[],cost:0};
        var group=free.slice(start,start+count),total=group.reduce(function(sum,p) {return sum+p.size;},0);
        var available=interval.end-interval.start-gap*(count-1);
        if(available<total-1e-7)return null;
        var scale=1;
        var cursor=interval.start;
        var records=group.map(function(item) {
            var span=item.size*scale,start=Math.max(cursor,item.center-span/2);
            cursor=start+span+gap;return record(item.p,start,span,scale);
        });
        var end=interval.end,cost=0;
        for(var i=records.length-1;i>=0;i--) {
            var p=records[i];p.along=Math.max(interval.start,Math.min(p.along,end-p.span));end=p.along-gap;
            cost+=Math.abs(p.along+p.span/2-group[i].center);
        }
        return {records:records,cost:cost};
    }
    var states=[{cost:0,records:[]}];
    intervals.forEach(function(interval) {
        var next=[];
        states.forEach(function(state,used) {
            for(var count=0;count<=free.length-used;count++) {
                var candidate=pack(used,count,interval);
                if(!candidate)break;
                var at=used+count,cost=state.cost+candidate.cost;
                if(!next[at] || cost<next[at].cost-1e-7)next[at]={cost:cost,records:state.records.concat(candidate.records)};
            }
        });
        states=next;
    });
    if(!states[free.length])return {error:"Not enough space around locked modules. Undo this change or unlock a module."};
    return {records:locked.concat(states[free.length].records).sort(function(a,b) {return a.along-b.along || a.id.localeCompare(b.id);})};
}
function packGeometry(placements, width, height, options, fontScale, bounds) {
    var result = [];
    ["top","right","bottom","left"].forEach(function(edge) {
        var horizontal = edge === "top" || edge === "bottom";
        var length = horizontal ? width : height;
        var low=bounds[edge].start,high=length-bounds[edge].end;
        var gap = bounded(options?.gap,8,0,32);
        // A measured empty module must not keep a zero-span placement:
        // even a zero-sized record consumes gaps and can leave a tiny
        // deformation at Screen Edges. Preserve edit-mode placeholders.
        var list = placements.filter(function(p) {
            if (!p.enabled || p.edge !== edge || moduleSize(p,options) <= 0) return false;
            var measured = options?.extents?.[p.id];
            return options?.editing || !Number.isFinite(measured) || measured > 0;
        })
            .sort(function(a,b) { return a.position-b.position || a.id.localeCompare(b.id); });
        var sizes = list.map(function(p) {
            var measured = options?.extents?.[p.id];
            var natural = Number.isFinite(measured) && !(options?.editing && measured<1) ? Math.max(0,measured)
                : extent(p.kind,!horizontal)*bounded(fontScale,1,0.7,2);
            return natural*moduleSize(p,options);
        });
        var total = sizes.reduce(function(sum,n) { return sum+n; },0);
        if (!list.length || length < 1) return;
        // Capacity is an explicit placement constraint, never a font/icon
        // scaling policy. A failed layout preserves its saved placements.
        var scale = 1;
        var capacityError=total+gap*(list.length-1)>high-low+1e-7
            ? "Not enough space on this Edge. Move a module or choose a smaller size." : "";
        var lockedResult=list.some(function(p) {return p.locked;}) ? packLockedEdge(list,sizes,length,gap,options,horizontal,low,high) : null;
        if(lockedResult?.records)capacityError="";
        var records=lockedResult?.records;
        if(!records) {
        // Each aligned group keeps its internal order; free placements keep their
        // requested position. Resolve collisions once across the entire edge.
        var targets = list.map(function(p,index) { return p.position*length-sizes[index]*scale/2; });
        ["start","center","end"].forEach(function(alignment) {
            var indices = list.map(function(p,i) { return p.alignment===alignment ? i : -1; }).filter(function(i) { return i>=0; });
            var groupSpan = indices.reduce(function(sum,i) { return sum+sizes[i]*scale; },0)+Math.max(0,indices.length-1)*gap;
            var start = alignment==="start" ? low : alignment==="end" ? high-groupSpan : (length-groupSpan)/2;
            indices.forEach(function(i) { targets[i]=start;start+=sizes[i]*scale+gap; });
        });
        var order = list.map(function(p,index) { return {placement:p,index:index}; }).sort(function(a,b) {
            return targets[a.index]-targets[b.index] || a.placement.id.localeCompare(b.placement.id);
        });
        var cursor = low;
        records = order.map(function(entry) {
            var p=entry.placement,index=entry.index;
            var size = sizes[index]*scale;
            var start = Math.max(cursor,targets[index]);
            cursor = start+size+gap;
            return Object.assign({},p,{along:start,span:size,vertical:!horizontal,
                depth:bounded(options?.depth,36,22,64)*p.depth,
                compact:p.compact});
        });
        var end = high;
        for (var i=records.length-1;i>=0;i--) {
            records[i].along = Math.max(low,Math.min(records[i].along,end-records[i].span));
            end = records[i].along-gap;
        }
        // Infeasible output changes retain anchors/lock flags in saved data.
        // Reject the Edge as a whole with one repair notice, never silently
        // shrink, overlap or drop arbitrary members from the saved layout.
        if(lockedResult?.error)records=records.map(function(p) {return Object.assign({},p,{lockConflict:lockedResult.error});});
        }
        if(capacityError || lockedResult?.error)records=records.map(function(p) {
            return Object.assign({},p,{capacityConflict:capacityError || lockedResult.error});
        });
        records.forEach(function(p) {
            p.edgeStart=low;p.edgeEnd=high;
            var inset = 8, cross = 32*bounded(fontScale,1,.7,2)*moduleSize(p,options)*(p.layoutScale ?? scale);
            p.content = horizontal ? {x:p.along,y:edge==="top"?inset:height-inset-cross,width:p.span,height:cross}
                : {x:edge==="left"?inset:width-inset-cross,y:p.along,width:cross,height:p.span};
            result.push(p);
        });
    });
    return result;
}

// Rejected saved layouts keep every module in the editor inventory. A single
// exact input/paint footprint on the affected Edge opens that existing editor.
function capacityNotices(records,width,height,fontScale) {
    var result=[],seen={};
    records.forEach(function(p) {
        if(!p.capacityConflict || seen[p.edge])return;
        seen[p.edge]=true;
        var horizontal=p.edge==="top" || p.edge==="bottom",length=horizontal?width:height;
        var crossLength=horizontal?height:width;
        var size=Math.min(32*bounded(fontScale,1,.7,2),Math.max(1,length-16),Math.max(1,crossLength-16));
        var along=(length-size)/2,inset=Math.min(8,Math.max(0,(crossLength-size)/2));
        var content=horizontal?{x:along,y:p.edge==="top"?inset:height-inset-size,width:size,height:size}
            :{x:p.edge==="left"?inset:width-inset-size,y:along,width:size,height:size};
        result.push({id:"capacity_"+p.edge,edge:p.edge,vertical:!horizontal,along:along,span:size,
            content:content,customSize:true,size:1,joinCorner:false,message:p.capacityConflict});
    });
    return result;
}

// Only modules within a short distance of a physical corner offer a second weld.
function adjacentEdge(record,width,height) {
    if (!record) return "";
    var horizontal = record.edge === "top" || record.edge === "bottom";
    var length = horizontal ? width : height;
    var first = Math.max(0,record.along);
    var last = Math.max(0,length-record.along-record.span);
    if (Math.min(first,last)>160) return "";
    return horizontal ? (first<=last ? "left" : "right") : (first<=last ? "top" : "bottom");
}
// Only the visible end-most module can extend its local field to a corner.
// Foreground packing and popup anchors remain independent of this paint weld.
function cornerForModule(records,id,width,height) {
    var own=records.find(function(p) {return p.id===id && p.span>0;});
    var corner=adjacentEdge(own,width,height);
    if(!corner) return "";
    var start=corner==="left" || corner==="top";
    var closer=records.some(function(p) {
        return p.id!==id && p.edge===own.edge && p.span>0
            && (start ? p.along<own.along : p.along+p.span>own.along+own.span);
    });
    return closer ? "" : corner;
}

// Small corner token, derived from the existing curvature and type scale.
// Additional clearance is allocated only when perpendicular controls collide.
function cornerInset(options,fontScale,length) {
    return Math.min(Math.max(0,length)/8,bounded(Math.min(
        bounded(options?.cornerRadius,28,0,80)/4,8*bounded(fontScale,1,.7,2)),7,4,12));
}
function geometry(placements,width,height,options,fontScale) {
    var bounds={};
    ["top","right","bottom","left"].forEach(function(edge) {
        var inset=cornerInset(options,fontScale,edge==="top"||edge==="bottom" ? width : height);
        bounds[edge]={start:inset,end:inset};
    });
    var corners=[["top","left","start","start"],["top","right","end","start"],
        ["bottom","left","start","end"],["bottom","right","end","end"]];
    var gap=bounded(options?.gap,8,0,32),records=[];
    for(var pass=0;pass<8;pass++) {
        records=packGeometry(placements,width,height,options,fontScale,bounds);
        var changed=false;
        corners.forEach(function(pair) {
            records.filter(function(r) {return r.edge===pair[0]&&!r.capacityConflict;}).forEach(function(a) {
                records.filter(function(r) {return r.edge===pair[1]&&!r.capacityConflict;}).forEach(function(b) {
                    var x=a.content,y=b.content;
                    if(x.x>=y.x+y.width+gap || y.x>=x.x+x.width+gap || x.y>=y.y+y.height+gap || y.y>=x.y+x.height+gap)return;
                    var h=y.width+8+gap,v=x.height+8+gap;
                    if(h>bounds[pair[0]][pair[2]]){bounds[pair[0]][pair[2]]=h;changed=true;}
                    if(v>bounds[pair[1]][pair[3]]){bounds[pair[1]][pair[3]]=v;changed=true;}
                });
            });
        });
        if(!changed)return records;
    }
    return packGeometry(placements,width,height,options,fontScale,bounds);
}
// Preserve the grab point in the full component's coordinates across rotation.
// The active Edge has a small hysteresis band, avoiding corner tie oscillation.
function dragContext(record,x,y) {
    var c=record.content,dx=x-c.x-c.width/2,dy=y-c.y-c.height/2;
    return {edge:record.edge,originX:x,originY:y,along:record.vertical ? (record.edge==="left"?-dy:dy) : dx,
        cross:record.vertical ? (record.edge==="left"?dx:-dx) : dy};
}
function dragPoint(context,x,y,width,height,fontScale) {
    var edges=["top","right","bottom","left"],distances=[y,width-x,height-y,x];
    var nearest=distances.indexOf(Math.min.apply(null,distances)),current=edges.indexOf(context.edge);
    var stationary=Number.isFinite(context.originX) && Math.hypot(x-context.originX,y-context.originY)<4*bounded(fontScale,1,.7,2);
    var edge=current>=0 && (stationary || distances[current]<=distances[nearest]+14*bounded(fontScale,1,.7,2)) ? context.edge : edges[nearest];
    var dx=edge==="left"?context.cross:edge==="right"?-context.cross:context.along;
    var dy=edge==="left"?-context.along:edge==="right"?context.along:context.cross;
    return {edge:edge,x:x-dx,y:y-dy};
}
