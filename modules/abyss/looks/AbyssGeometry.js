// Output-local geometry, shared by presentation, reservations and tests.
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, Number(v) || 0)); }
function edge(vertical, bottom) { return vertical ? (bottom ? "right" : "left") : (bottom ? "bottom" : "top"); }
function horizontal(edge) { return edge === "top" || edge === "bottom"; }
// Only the popup's tangent footprint reaches its owning inner Edge. Never
// capture the output-wide strip or the full content canvas hidden by reveal.
function popupInput(content,width,height,insets,edge,paintedSurface) {
    if (!content || content.width <= 0 || content.height <= 0)
        return {x:0,y:0,width:0,height:0};
    var x=content.x,y=content.y,right=x+content.width,bottom=y+content.height;
    // Feature bounds exclude the body's visual padding. Use the unjoined
    // painted footprint when supplied, trimming its off-output extrusion at
    // the owner seam below. Corner welding must not enlarge this hover lease.
    if (paintedSurface && paintedSurface.width > 0 && paintedSurface.height > 0) {
        if (horizontal(edge)) {
            x=paintedSurface.x;right=x+paintedSurface.width;
            if (edge === "top") bottom=paintedSurface.y+paintedSurface.height;
            else y=paintedSurface.y;
        } else {
            y=paintedSurface.y;bottom=y+paintedSurface.height;
            if (edge === "left") right=paintedSurface.x+paintedSurface.width;
            else x=paintedSurface.x;
        }
    }
    if (edge === "top") y=Math.min(y,insets.top);
    else if (edge === "bottom") bottom=Math.max(bottom,height-insets.bottom);
    else if (edge === "left") x=Math.min(x,insets.left);
    else if (edge === "right") right=Math.max(right,width-insets.right);
    x=clamp(x,0,width);y=clamp(y,0,height);
    right=clamp(right,x,width);bottom=clamp(bottom,y,height);
    return {x:x,y:y,width:right-x,height:bottom-y};
}
// The smooth union paints two concave shoulders beyond the body's tangent
// bounds. Rasterize only those small shoulder strips, using the same SDF as
// the field. Expanding the entire body rectangle would capture blank desktop.
function popupShoulders(width,height,insets,edge,record,radius,softness,recordRadius,roundZeroCorners,cornerWidthInsets) {
    if (!record || !record.surface || record.surface.width <= 0
            || record.surface.height <= 0) return [];
    var h=horizontal(edge),leading=edge === "top" || edge === "left";
    var surface=record.surface;
    var start=Math.floor(h ? surface.x : surface.y);
    var end=Math.ceil(h ? surface.x+surface.width : surface.y+surface.height);
    var extent=Math.floor(h ? width : height);
    var seam=leading ? insets[edge]
        : (h ? height : width)-insets[edge];
    var popupRadius=record.radius ?? recordRadius ?? radius;
    var contactEdges=physicalContactMask(cornerWidthInsets ?? insets,roundZeroCorners);
    var contactEnabled=contactEdges[{top:0,right:1,bottom:2,left:3}[edge]];
    var physicalDepth=leading ? (h ? surface.y+surface.height : surface.x+surface.width)
        : (h ? height-surface.y : width-surface.x);
    var touches=leading ? (h ? surface.y : surface.x)<=0
        : (h ? surface.y+surface.height>=height : surface.x+surface.width>=width);
    var contactRadius=touches && contactEnabled ? Math.max(0,Math.min(popupRadius,(h ? surface.width : surface.height)/2,physicalDepth)) : 0;
    var reach=Math.max(0,softness,contactRadius);
    if(reach<=0)return [];
    var normalReach=Math.max(0,softness,contactRadius-Math.max(0,insets[edge]));
    // 0px Edges still own the bounded contact of a local body with the screen.
    if (insets[edge] <= 0 && contactRadius<=0) return [];
    var firstCross=leading ? Math.floor(seam) : Math.ceil(seam)-1;
    var rows=[];
    // This function has exactly one non-empty record. The old distance()
    // path allocated a new workspace rectangle and walked the same record
    // array for each pixel-center SDF sample (many times per animation frame).
    // Hoist invariant geometry, retain the identical arithmetic/paint oracle.
    var left=insets.left>0 ? insets.left : -64;
    var top=insets.top>0 ? insets.top : -64;
    var right=insets.right>0 ? insets.right : -64;
    var bottom=insets.bottom>0 ? insets.bottom : -64;
    var workspaceRect={x:left,y:top,width:width-left-right,height:height-top-bottom};
    var zeroMask=zeroCornerMask(cornerWidthInsets ?? insets,roundZeroCorners);
    var cutCorners=zeroMask.some(function(value) {return value;});
    // 0px corner fields can fuse with the new contact beyond the corner arc.
    // Scan that finite support exactly; only the far, monotone intervals use
    // the binary search, so no empty gap is bridged by a native rectangle.
    var cornerSupport=radius+(cutCorners ? softness : 0);
    var cornerStart=(h ? insets.left : insets.top)+cornerSupport;
    var cornerEnd=extent-(h ? insets.right : insets.bottom)-cornerSupport;
    if(cutCorners && (start-reach<cornerStart || end+reach>cornerEnd))
        normalReach=Math.max(normalReach,cornerSupport-Math.max(0,insets[edge]));
    var painted=function(tangent,cross) {
        var x=h ? tangent+.5 : cross+.5;
        var y=h ? cross+.5 : tangent+.5;
        var d=-roundedDistance(x,y,workspaceRect,radius);
        if(cutCorners)d=zeroCornerField(d,x,y,width,height,insets,radius,roundZeroCorners,cornerWidthInsets);
        d=smoothUnion(d,surfaceDistance(x,y,width,height,surface,popupRadius,contactEdges),softness);
        if(cutCorners)d=clipZeroCornerField(d,x,y,width,height,insets,radius,roundZeroCorners,cornerWidthInsets);
        return d<0;
    };
    var append=function(first,last,cross) {
        rows.push(h ? {x:first,y:cross,width:Math.max(0,last-first),height:1}
            : {x:cross,y:first,width:1,height:Math.max(0,last-first)});
    };
    var scan=function(first,last,cross) {
        // A nearby physical corner can make the SDF non-monotone. Preserve
        // each filled interval instead of bridging an empty pixel gap.
        var segment=-1,before=rows.length;
        for (var t=first;t<last;t++) {
            if (painted(t,cross)) { if (segment < 0) segment=t; }
            else if (segment >= 0) { append(segment,t,cross);segment=-1; }
        }
        if (segment >= 0) append(segment,last,cross);
        if (rows.length === before) append(first,first,cross);
    };
    for (var i=0;i<Math.ceil(normalReach)+1;i++) {
        var cross=firstCross+(leading ? i : -i);
        if (cross < 0 || cross >= Math.floor(h ? height : width)) continue;
        var lo=Math.max(0,Math.floor(start-reach)),hi=Math.max(0,Math.min(extent,start));
        var first=lo,last=hi;
        while (lo < hi) {
            var middle=Math.floor((lo+hi)/2);
            if (painted(middle,cross)) hi=middle; else lo=middle+1;
        }
        if (first < cornerStart) scan(first,last,cross);
        else append(lo,last,cross);
        lo=Math.min(extent,end);hi=Math.min(extent,Math.ceil(end+reach));
        first=Math.max(0,lo);last=hi;
        while (lo < hi) {
            var middle=Math.floor((lo+hi)/2);
            if (painted(middle,cross)) lo=middle+1; else hi=middle;
        }
        if (last > cornerEnd) scan(first,last,cross);
        else append(first,lo,cross);
    }
    return rows;
}
function rectContains(rect,x,y) {
    return rect && rect.width > 0 && rect.height > 0 && x >= rect.x && y >= rect.y
        && x < rect.x+rect.width && y < rect.y+rect.height;
}
function insets(thickness, barEdge, barThickness, barShown) {
    var result = {left: thickness, top: thickness, right: thickness, bottom: thickness};
    if (barShown && barEdge in result) result[barEdge] = Math.max(thickness, barThickness);
    return result;
}
function targets(name, list, connected) {
    if (!list || !list.length) return true;
    return list.indexOf(name) >= 0 || !connected.some(function(n) { return list.indexOf(n) >= 0; });
}
function panel(width, height, insets, edge, along, span, depth, progress, padding, obstacles, largeSurface) {
    var h = horizontal(edge);
    var first = h ? insets.left : insets.top;
    var last = h ? width - insets.right : height - insets.bottom;
    var firstBound=first, lastBound=last;
    // Keep content out of perpendicular panels. Besides avoiding overlapping
    // controls this prevents a popup and sidebar sealing a second workspace
    // pocket at their corner. The final painter still computes one true union.
    for (var i=0;i<(obstacles || []).length;i++) {
        var other=obstacles[i];
        if (horizontal(other.edge) === h) continue;
        if (other.edge === "left" || other.edge === "top") first += other.depth + 48 * (other.progress ?? 1);
        else last -= other.depth + 48 * (other.progress ?? 1);
    }
    first = clamp(first,firstBound,lastBound);
    last = Math.max(first,Math.min(last,lastBound));
    var p = clamp(padding, 0, Math.max(0, (last-first)/8));
    span = clamp(span, 0, Math.max(0, last-first-2*p));
    along = clamp(along, first+p, Math.max(first+p, last-p-span));
    // Opposing panels can never close the workspace opening.
    depth = clamp(depth, 0, (h ? height-insets.top-insets.bottom : width-insets.left-insets.right)*(largeSurface ? 0.92 : 0.42));
    var d = depth * clamp(progress, 0, 1.035);
    var x = h ? along : edge === "left" ? insets.left : width-insets.right-d;
    var y = h ? edge === "top" ? insets.top : height-insets.bottom-d : along;
    var crossPad = Math.min(p,d/2);
    var content = {x:x+(h?p:crossPad), y:y+(h?crossPad:p), width:Math.max(0,h?span-2*p:d-2*crossPad), height:Math.max(0,h?d-2*crossPad:span-2*p)};
    // The geometry extends through its owner to the physical screen boundary.
    // There is no detached component fill, endpoint patch or alpha overlap.
    var surface = h ? {x:along, y:edge==="top"?-50:y, width:span, height:d+insets[edge]+50}
        : {x:edge==="left"?-50:x, y:along, width:d+insets[edge]+50, height:span};
    if (d <= 0) surface = {x:0,y:0,width:0,height:0};
    return {edge:edge, content:content, surface:surface, depth:d, targetDepth:depth, progress:clamp(progress,0,1.035), span:span, along:along};
}
// Keep each body's readable contents at its requested size while its one union
// record reaches through the inner tier to the physical Edge.
function placedPanel(width,height,insets,edge,along,span,depth,progress,padding,obstacles,largeSurface,placement) {
    if (!placement) return panel(width,height,insets,edge,along,span,depth,progress,padding,obstacles,largeSurface);

    // A resolved placement has already passed the allocator (and any temporary
    // vacancy post-pass). Trust that placement up to the output's hard safe
    // bounds instead of reapplying panel()'s normal 42/92% resting-depth cap.
    // Base allocator placements are already capped by their requested record, so
    // this is byte-for-byte equivalent while borrowing is inactive and lets the
    // existing placement Behavior restore a borrowed depth without a clamp snap.
    var h=horizontal(edge);
    var first=h ? insets.left : insets.top;
    var last=h ? width-insets.right : height-insets.bottom;
    var pad=clamp(padding,0,Math.max(0,(last-first)/8));
    var placedAlong=Number.isFinite(Number(placement.along))
        ? Number(placement.along) : along;
    var placedSpan=Number.isFinite(Number(placement.span))
        ? Number(placement.span) : span;
    var placedDepth=Number.isFinite(Number(placement.depth))
        ? Number(placement.depth) : depth;
    var placedInward=Number.isFinite(Number(placement.inward))
        ? Math.max(0,Number(placement.inward)) : 0;

    placedSpan=clamp(placedSpan,0,Math.max(0,last-first-2*pad));
    placedAlong=clamp(placedAlong,first+pad,
        Math.max(first+pad,last-pad-placedSpan));

    var crossExtent=Math.max(0,h
        ? height-insets.top-insets.bottom
        : width-insets.left-insets.right);
    placedInward=clamp(placedInward,0,crossExtent);
    // Content/input safety is enforced by the allocator/resolver. Do not
    // subtract inward from the panel depth here: legacy resting placements may
    // legitimately carry their padding beyond the inner safe-content bound,
    // and doing so changes inactive geometry. Depth itself still cannot exceed
    // one full output cross-axis.
    placedDepth=clamp(placedDepth,0,crossExtent);

    var reveal=clamp(progress,0,1.035);
    var currentDepth=placedDepth*reveal;
    var offset=placedInward*reveal;
    var x=h ? placedAlong
        : edge === "left"
            ? insets.left+offset
            : width-insets.right-currentDepth-offset;
    var y=h
        ? edge === "top"
            ? insets.top+offset
            : height-insets.bottom-currentDepth-offset
        : placedAlong;
    var crossPad=Math.min(pad,currentDepth/2);
    var content={
        x:x+(h ? pad : crossPad),
        y:y+(h ? crossPad : pad),
        width:Math.max(0,h
            ? placedSpan-2*pad
            : currentDepth-2*crossPad),
        height:Math.max(0,h
            ? currentDepth-2*crossPad
            : placedSpan-2*pad)
    };
    var reach=currentDepth+offset;
    var surface=h
        ? {
            x:placedAlong,
            y:edge === "top" ? -50 : y,
            width:placedSpan,
            height:reach+insets[edge]+50
        }
        : {
            x:edge === "left" ? -50 : x,
            y:placedAlong,
            width:reach+insets[edge]+50,
            height:placedSpan
        };
    if (reach <= 0 || placement.visible === false)
        surface={x:0,y:0,width:0,height:0};
    return {
        edge:edge,
        content:content,
        surface:surface,
        depth:reach,
        targetDepth:placedDepth+placedInward,
        progress:reveal,
        span:placedSpan,
        along:placedAlong
    };
}
function roundedDistance(x, y, rect, radius) {
    var r = Math.min(radius, rect.width/2, rect.height/2);
    var qx = Math.abs(x-rect.x-rect.width/2)-rect.width/2+r;
    var qy = Math.abs(y-rect.y-rect.height/2)-rect.height/2+r;
    return Math.hypot(Math.max(qx,0),Math.max(qy,0))+Math.min(Math.max(qx,qy),0)-r;
}
function smoothUnion(a, b, k) {
    if (k <= 0) return Math.min(a,b);
    var h = Math.max(k-Math.abs(a-b),0)/k;
    return Math.min(a,b)-h*h*k*0.25;
}
// A contact follows the actual rectangle crossing the physical boundary.
// Its concave quarter circle meets that boundary and the body's side with
// continuous tangents; no output-wide strip or fixed screen-corner patch.
function contactCornerDistance(tangent,normal,start,end,radius) {
    if(!(radius>0) || normal<0 || normal>radius)return Infinity;
    var q=Math.min(tangent-start+radius,end+radius-tangent);
    if(q<0)return Infinity;
    var circle=radius-Math.hypot(q,normal-radius);
    var clip=Math.max(-q,-normal,normal-radius);
    return Math.max(circle,clip);
}
function physicalContactDistance(x,y,width,height,rect,radius,enabledEdges) {
    if(!enabledEdges)return Infinity;
    var d=Infinity;
    if(enabledEdges[0] && rect.y<=0 && rect.y+rect.height>0)
        d=Math.min(d,contactCornerDistance(x,y,rect.x,rect.x+rect.width,
            Math.min(radius,rect.width/2,rect.y+rect.height)));
    if(enabledEdges[2] && rect.y+rect.height>=height && rect.y<height)
        d=Math.min(d,contactCornerDistance(x,height-y,rect.x,rect.x+rect.width,
            Math.min(radius,rect.width/2,height-rect.y)));
    if(enabledEdges[3] && rect.x<=0 && rect.x+rect.width>0)
        d=Math.min(d,contactCornerDistance(y,x,rect.y,rect.y+rect.height,
            Math.min(radius,rect.height/2,rect.x+rect.width)));
    if(enabledEdges[1] && rect.x+rect.width>=width && rect.x<width)
        d=Math.min(d,contactCornerDistance(y,width-x,rect.y,rect.y+rect.height,
            Math.min(radius,rect.height/2,width-rect.x)));
    return d;
}
function surfaceDistance(x,y,width,height,rect,radius,enabledEdges) {
    return Math.min(roundedDistance(x,y,rect,radius),
        physicalContactDistance(x,y,width,height,rect,radius,enabledEdges));
}
function distance(x, y, width, height, insets, radius, records, softness, recordRadius, roundZeroCorners, cornerWidthInsets) {
    var left=insets.left>0 ? insets.left : -64, top=insets.top>0 ? insets.top : -64;
    var right=insets.right>0 ? insets.right : -64, bottom=insets.bottom>0 ? insets.bottom : -64;
    var d = -roundedDistance(x,y,{x:left,y:top,width:width-left-right,height:height-top-bottom},radius);
    d=zeroCornerField(d,x,y,width,height,insets,radius,roundZeroCorners,cornerWidthInsets);
    var contactEdges=physicalContactMask(cornerWidthInsets ?? insets,roundZeroCorners);
    for (var i=0;i<records.length;i++) {
        var rec=records[i];
        if (rec.surface.width>0 && rec.surface.height>0)
            d=smoothUnion(d,surfaceDistance(x,y,width,height,rec.surface,rec.radius ?? recordRadius ?? radius,contactEdges),softness);
    }
    return clipZeroCornerField(d,x,y,width,height,insets,radius,roundZeroCorners,cornerWidthInsets);
}

function barZones(layout, vertical, modules) {
    var keys=vertical ? ["top","centerTop","center","centerBottom","bottom"] : ["left","centerLeft","center","centerRight","right"];
    var seen={};
    return keys.map(function(key) {
        return (layout[key] || []).map(function(id) { return id === "sysTray" ? "tray" : id; })
            .filter(function(id) {
                if (id === "spacer" || seen[id]) return false;
                seen[id]=true;
                return modules[id === "tray" ? "sysTray" : id] !== false;
            });
    });
}

// Extend the same union record through a nearby adjacent Edge. Content geometry
// and input bounds stay unchanged; no second connector/painter is constructed.
function joinCorner(record, adjacent, width, height, insets) {
    if (!record || !record.surface || record.surface.width<=0 || record.surface.height<=0
            || !["left","right","top","bottom"].includes(adjacent)
            || horizontal(record.edge)===horizontal(adjacent)) return record;
    var surface = record.surface;
    var gap = adjacent==="left" ? surface.x-insets.left
        : adjacent==="right" ? width-insets.right-surface.x-surface.width
        : adjacent==="top" ? surface.y-insets.top
        : height-insets.bottom-surface.y-surface.height;
    if (gap>160) return record; // A separately positioned popup cannot bridge the workspace.
    surface = Object.assign({},surface);
    if (adjacent==="left") { surface.width += surface.x+50;surface.x=-50; }
    else if (adjacent==="right") surface.width=width+50-surface.x;
    else if (adjacent==="top") { surface.height += surface.y+50;surface.y=-50; }
    else surface.height=height+50-surface.y;
    return Object.assign({},record,{surface:surface,joinedEdge:adjacent});
}

// Corner ownership is OR: either enabled zero-width adjoining Edge owns one arc.
// This changes only the workspace-facing quarter curve, never the outer boundary.
function physicalContactMask(insets,choices) {
    return ["top","right","bottom","left"].map(function(edge) {
        return choices?.[edge]===true && insets?.[edge]===0;
    });
}
function zeroCornerMask(insets,choices) {
    var on=function(edge) {return choices?.[edge]===true && insets[edge]===0;};
    return [on("top")||on("left"),on("top")||on("right"),
        on("bottom")||on("right"),on("bottom")||on("left")];
}
function innerCornerDistance(u,v,r) {
    // Exact distance to the finite quarter arc. A max/intersection SDF
    // underestimates outside this quadrant, painting a false circular shadow.
    if(u<=r && v<=r)return r-Math.hypot(u-r,v-r);
    var a=Math.hypot(u-r,v),b=Math.hypot(u,v-r);
    return u>r && v>r ? Math.min(a,b) : u>r ? a : b;
}
function zeroCornerField(d,x,y,width,height,insets,radius,choices,cornerWidthInsets) {
    if(!choices || !(choices.top || choices.right || choices.bottom || choices.left))return d;
    var mask=zeroCornerMask(cornerWidthInsets ?? insets,choices);
    if(!mask.some(function(enabled) {return enabled;}))return d;
    var left=Math.max(0,insets.left),right=Math.max(0,insets.right),top=Math.max(0,insets.top),bottom=Math.max(0,insets.bottom);
    var r=Math.max(0,Math.min(radius,(width-left-right)/2,(height-top-bottom)/2));
    if(r<=0)return d;
    var u=[x-left,width-right-x,width-right-x,x-left],v=[y-top,y-top,height-bottom-y,height-bottom-y];
    mask.forEach(function(enabled,i) {if(enabled)d=Math.min(d,innerCornerDistance(u[i],v[i],r));});
    return d;
}

// R02 regression: module/local-backdrop unions must not fill the workspace
// cutout of an enabled 0px corner. Clip only the finite quarter square,
// leaving module geometry, input regions and every other pixel unchanged.
function clipZeroCornerField(d,x,y,width,height,insets,radius,choices,cornerWidthInsets) {
    if(!choices || !(choices.top || choices.right || choices.bottom || choices.left))return d;
    var mask=zeroCornerMask(cornerWidthInsets ?? insets,choices);
    if(!mask.some(function(enabled) {return enabled;}))return d;
    var left=Math.max(0,insets.left),right=Math.max(0,insets.right),top=Math.max(0,insets.top),bottom=Math.max(0,insets.bottom);
    var r=Math.max(0,Math.min(radius,(width-left-right)/2,(height-top-bottom)/2));
    if(r<=0)return d;
    var u=[x-left,width-right-x,width-right-x,x-left],v=[y-top,y-top,height-bottom-y,height-bottom-y];
    mask.forEach(function(enabled,i) {
        if(enabled && u[i]>=0 && u[i]<=r && v[i]>=0 && v[i]<=r)
            d=Math.max(d,innerCornerDistance(u[i],v[i],r));
    });
    return d;
}
