// Persist normalized positions; derive pixel geometry independently per output.
var catalog = ["distroIcon","activeWindow","resources","media",
    "workspaces","clock","utilButtons","battery","tray",
    "timer","shellUpdate","weather","taskbar"];
var labels = {distroIcon:"Launcher",activeWindow:"Active window",
    resources:"System resources",media:"Media",workspaces:"Workspaces",clock:"Clock",
    utilButtons:"Quick actions",battery:"Battery",tray:"System tray",
    timer:"Timer",shellUpdate:"Updates",weather:"Weather",taskbar:"Taskbar"};
function label(kind) { return labels[kind] || kind; }
function bounded(value, fallback, low, high) {
    var number = Number(value);
    return Number.isFinite(number) ? Math.max(low,Math.min(high,number)) : fallback;
}
function extent(kind, vertical) {
    var sizes = {utilButtons:36,distroIcon:88,
        activeWindow:178,resources:178,media:166,workspaces:192,clock:104,battery:72,
        tray:72,timer:68,shellUpdate:86,weather:80,taskbar:40};
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
function resolve(options, outputName, fallback) {
    var profiles = Array.from(options?.outputLayouts || []);
    var profile = profiles.find(function(p) { return p.outputName === outputName; });
    if (profile) return normalize(profile.placements,"top");
    return options?.configured ? normalize(options.placements,"top") : fallback;
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
    return (placement.customSize ? placement.size : edgeSize(options,placement.edge)*inheritedWidth/16)*bounded(options?.size,1,.6,1.8);
}
function project(x, y, width, height) {
    var distances = [y,width-x,height-y,x];
    var index = distances.indexOf(Math.min.apply(null,distances));
    var edge = ["top","right","bottom","left"][index];
    return {edge:edge,position:bounded((index%2===0 ? x : y)/Math.max(1,index%2===0 ? width : height),.5,0,1)};
}
function move(placements, id, x, y, width, height) {
    if (placements.some(function(p) { return p.id===id && p.locked; })) return normalize(placements,"top");
    var location = project(x,y,width,height);
    return normalize(placements.map(function(p) { return p.id===id ? Object.assign({},p,location,{alignment:"free"}) : p; }),"top");
}
// Snap to the output center, end margins, and adjacent modules at the configured gap.
// Guides are presentation data only; positions stay normalized for other resolutions.
function snapMove(placements, id, x, y, width, height, options, fontScale) {
    if (placements.some(function(p) { return p.id===id && p.locked; })) return {placements:normalize(placements,"top"),guides:[],rejected:"Unlock this module before moving it"};
    var moved = move(placements,id,x,y,width,height);
    var selected = moved.find(function(p) { return p.id===id; });
    if (!selected) return {placements:moved,guides:[]};
    var horizontal = selected.edge==="top" || selected.edge==="bottom";
    var length = horizontal ? width : height;
    var margin = 0, usable = length;
    var records = geometry(moved,width,height,options,fontScale);
    var own = records.find(function(p) { return p.id===id; });
    if (!own || usable<=0) return {placements:moved,guides:[]};
    var center = margin+selected.position*usable;
    var gap = bounded(options?.gap,8,0,32);
    var targets = [{center:length/2,line:length/2,label:"Center"},
        {center:margin+own.span/2,line:margin,label:"Start"},
        {center:length-margin-own.span/2,line:length-margin,label:"End"}];
    geometry(moved.filter(function(p) { return p.id!==id; }),width,height,options,fontScale)
        .filter(function(p) { return p.edge===selected.edge; }).forEach(function(p) {
        targets.push({center:p.along-gap-own.span/2,line:p.along-gap,label:Math.round(gap)+" px gap"});
        targets.push({center:p.along+p.span+gap+own.span/2,line:p.along+p.span+gap,label:Math.round(gap)+" px gap"});
    });
    var target = targets.filter(function(t) { return t.center-own.span/2>=margin && t.center+own.span/2<=length-margin; })
        .sort(function(a,b) { return Math.abs(a.center-center)-Math.abs(b.center-center); })[0];
    if (!target || Math.abs(target.center-center)>10) return {placements:moved,guides:[]};
    moved = moved.map(function(p) { return p.id===id ? Object.assign({},p,{position:(target.center-margin)/usable}) : p; });
    var actual = geometry(moved,width,height,options,fontScale).find(function(p) { return p.id===id; });
    // Do not show a misleading guide when collision packing prevented this snap.
    return {placements:moved,guides:Math.abs(actual.along+actual.span/2-target.center)<1
        ? [{horizontal:horizontal,along:target.line,label:target.label}] : []};
}
// Capture the displayed center and compression, not a neighbor-dependent aligned
// group's future position. Anchors are normalized independently on each output.
function setLocked(placements,id,locked,width,height,options,fontScale) {
    var records=locked ? geometry(placements,width,height,options,fontScale) : [];
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
function checkedMove(placements,id,x,y,width,height,options,fontScale,snap) {
    var p=placements.find(function(p) {return p.id===id;});
    if(!p)return {placements:placements,guides:[],rejected:"This module is no longer available"};
    if(p?.locked)return {placements:placements,guides:[],rejected:"Unlock this module before moving it"};
    var result=snap ? snapMove(placements,id,x,y,width,height,options,fontScale) : {placements:move(placements,id,x,y,width,height),guides:[]};
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
function checkedBatch(placements,ids,action,value,width,height,options,fontScale) {
    var selection=selectedModules(placements,ids),items=selection.items;
    function deny(message) {return {placements:placements,rejected:message};}
    if(!items.length)return deny("Select a module first");
    if(items.some(function(p) {return !p;}))return deny("The selection changed. Select the modules again.");
    var placementKeys=["edge","position","alignment","size","customSize","depth"];
    if(placementKeys.indexOf(action)>=0 && items.some(function(p) {return p.locked;}))
        return deny("Unlock every selected module before changing its placement or size");
    if(["remove","locked","enabled","joinCorner"].concat(placementKeys).indexOf(action)<0)
        return deny("This action cannot be applied to modules");
    var records=(action==="locked" || action==="joinCorner") && value ? geometry(placements,width,height,options,fontScale) : [];
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
    var location=project(x,y,width,height),horizontal=location.edge==="top" || location.edge==="bottom";
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
    if(cursor>length+1e-6)return deny("The selected group cannot fit on this Edge");
    var primary=offsets.find(function(p) {return p.id===primaryId;});
    var start=Math.max(0,Math.min(length-cursor,location.position*length-primary.along-primary.span/2)),guides=[];
    if(snap) {
        var targets=[{start:0,line:0,label:"Start"},{start:(length-cursor)/2,line:length/2,label:"Center"},
            {start:length-cursor,line:length,label:"End"}];
        var gap=bounded(options?.gap,8,0,32);
        geometry(placements.filter(function(p) {return selection.ids.indexOf(p.id)<0;}),width,height,options,fontScale)
            .filter(function(p) {return p.edge===location.edge;}).forEach(function(p) {
                targets.push({start:p.along-gap-cursor,line:p.along-gap,label:Math.round(gap)+" px gap"});
                targets.push({start:p.along+p.span+gap,line:p.along+p.span+gap,label:Math.round(gap)+" px gap"});
            });
        var target=targets.filter(function(t) {return t.start>=0 && t.start+cursor<=length;})
            .sort(function(a,b) {return Math.abs(a.start-start)-Math.abs(b.start-start);})[0];
        if(target && Math.abs(target.start-start)<=10){start=target.start;guides=[{horizontal:horizontal,along:target.line,label:target.label}];}
    }
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
function saveProfile(options, outputName, placements, gap, outputOnly, edgeSizes, singleModuleExpansion, size, edgeThicknesses, edgeWidthAffectsModules, edgeJoinModules, edgeModuleRadii) {
    var normalized = normalize(placements,"top");
    var profiles = Array.from(options?.outputLayouts || []);
    var current = optionsForOutput(options,outputName);
    var expansion = edgeMap(singleModuleExpansion ?? current.singleModuleExpansion);
    var scale = bounded(size ?? current.size,1,.6,1.8);
    var thicknesses = edgeMap(edgeThicknesses ?? current.edgeThicknesses);
    var affects = edgeMap(edgeWidthAffectsModules ?? current.edgeWidthAffectsModules);
    var joins = edgeMap(edgeJoinModules ?? current.edgeJoinModules);
    var radii = edgeMap(edgeModuleRadii ?? current.edgeModuleRadii);
    if (outputOnly) {
        var existing = profiles.find(function(p) { return p.outputName===outputName; });
        profiles = profiles.filter(function(p) { return p.outputName!==outputName; });
        profiles.push(Object.assign({},existing,{outputName:outputName,placements:normalized,gap:bounded(gap,8,0,32),
            edgeSizes:edgeMap(edgeSizes ?? current.edgeSizes),singleModuleExpansion:expansion,size:scale,edgeThicknesses:thicknesses,edgeWidthAffectsModules:affects,edgeJoinModules:joins,edgeModuleRadii:radii}));
        return {"abyss.modules.outputLayouts":profiles};
    }
    return {"abyss.modules.configured":true,"abyss.modules.placements":normalized,
        "abyss.modules.gap":bounded(gap,8,0,32),"abyss.modules.outputLayouts":profiles.filter(function(p) { return p.outputName!==outputName; }),
        "abyss.modules.edgeSizes":edgeMap(edgeSizes ?? options?.edgeSizes),
        "abyss.modules.singleModuleExpansion":expansion,"abyss.modules.size":scale,
        "abyss.modules.edgeThicknesses":thicknesses,"abyss.modules.edgeWidthAffectsModules":affects,"abyss.modules.edgeJoinModules":joins,"abyss.modules.edgeModuleRadii":radii};
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
// chooses the closest feasible packing, including the existing 1% size floor.
function packLockedEdge(list,sizes,length,gap,options,horizontal) {
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
    var end=-gap;
    for(var i=0;i<locked.length;i++) {
        var own=locked[i];
        if(own.along<-1e-7 || own.along+own.span>length+1e-7)
            return {error:"A locked module no longer fits this output. Undo the size change or unlock it."};
        if(own.along<end-1e-7)
            return {error:"Locked modules overlap at this size. Undo the size change or unlock them."};
        if(i>0)gap=Math.min(gap,Math.max(0,own.along-end));
        end=own.along+own.span;
    }
    ["start","center","end"].forEach(function(alignment) {
        var group=free.filter(function(item) {return item.p.alignment===alignment;});
        var span=group.reduce(function(sum,item) {return sum+item.size;},0)+Math.max(0,group.length-1)*gap;
        var cursor=alignment==="start" ? 0 : alignment==="end" ? length-span : (length-span)/2;
        group.forEach(function(item) {item.center=cursor+item.size/2;cursor+=item.size+gap;});
    });
    free.sort(function(a,b) {return a.center-b.center || a.p.id.localeCompare(b.p.id);});
    var intervals=[],cursor=0;
    locked.forEach(function(p) {intervals.push({start:cursor,end:Math.max(cursor,p.along-gap)});cursor=p.along+p.span+gap;});
    intervals.push({start:Math.min(length,cursor),end:length});
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
function geometry(placements, width, height, options, fontScale) {
    var result = [];
    ["top","right","bottom","left"].forEach(function(edge) {
        var horizontal = edge === "top" || edge === "bottom";
        var length = horizontal ? width : height;
        // The full edge is editable. Foreground bounds and collision packing
        // keep controls on screen without a permanent corner exclusion zone.
        var margin = 0, gap = bounded(options?.gap,8,0,32);
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
        var capacityError=total+gap*(list.length-1)>length-2*margin+1e-7
            ? "Not enough space on this Edge. Move a module or choose a smaller size." : "";
        var lockedResult=list.some(function(p) {return p.locked;}) ? packLockedEdge(list,sizes,length,gap,options,horizontal) : null;
        if(lockedResult?.records)capacityError="";
        var records=lockedResult?.records;
        if(!records) {
        // Each aligned group keeps its internal order; free placements keep their
        // requested position. Resolve collisions once across the entire edge.
        var targets = list.map(function(p,index) { return margin+p.position*(length-2*margin)-sizes[index]*scale/2; });
        ["start","center","end"].forEach(function(alignment) {
            var indices = list.map(function(p,i) { return p.alignment===alignment ? i : -1; }).filter(function(i) { return i>=0; });
            var groupSpan = indices.reduce(function(sum,i) { return sum+sizes[i]*scale; },0)+Math.max(0,indices.length-1)*gap;
            var start = alignment==="start" ? margin : alignment==="end" ? length-margin-groupSpan : (length-groupSpan)/2;
            indices.forEach(function(i) { targets[i]=start;start+=sizes[i]*scale+gap; });
        });
        var order = list.map(function(p,index) { return {placement:p,index:index}; }).sort(function(a,b) {
            return targets[a.index]-targets[b.index] || a.placement.id.localeCompare(b.placement.id);
        });
        var cursor = margin;
        records = order.map(function(entry) {
            var p=entry.placement,index=entry.index;
            var size = sizes[index]*scale;
            var start = Math.max(cursor,targets[index]);
            cursor = start+size+gap;
            return Object.assign({},p,{along:start,span:size,vertical:!horizontal,
                depth:bounded(options?.depth,36,22,64)*p.depth,
                compact:p.compact});
        });
        var end = length-margin;
        for (var i=records.length-1;i>=0;i--) {
            records[i].along = Math.max(margin,Math.min(records[i].along,end-records[i].span));
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
