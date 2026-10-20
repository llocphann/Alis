// Output-local geometry, shared by presentation, reservations and tests.
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, Number(v) || 0)); }
function edge(vertical, bottom) { return vertical ? (bottom ? "right" : "left") : (bottom ? "bottom" : "top"); }
function horizontal(edge) { return edge === "top" || edge === "bottom"; }
// A source can end just before the painted perimeter's inner seam. Keep only
// that source's overlap with its popup interactive across this narrow gap.
// The corridor lies inside the already-painted Edge band, never the workspace.
function popupSourceBridge(source,body,width,height,insets,edge) {
    var empty={x:0,y:0,width:0,height:0};
    if (!source || !body || !insets || !["top","right","bottom","left"].includes(edge)
            || ![width,height,source.x,source.y,source.width,source.height,
                body.x,body.y,body.width,body.height,insets[edge]].every(Number.isFinite)
            || width<=0 || height<=0 || source.width<=0 || source.height<=0
            || body.width<=0 || body.height<=0) return empty;
    var h=horizontal(edge);
    var start=Math.max(0,h ? source.x : source.y,h ? body.x : body.y);
    var end=Math.min(h ? width : height,
        h ? source.x+source.width : source.y+source.height,
        h ? body.x+body.width : body.y+body.height);
    var near,far;
    if (edge==="top") { near=source.y+source.height;far=Math.min(insets.top,body.y); }
    else if (edge==="left") { near=source.x+source.width;far=Math.min(insets.left,body.x); }
    else if (edge==="bottom") { near=Math.max(height-insets.bottom,body.y+body.height);far=source.y; }
    else { near=Math.max(width-insets.right,body.x+body.width);far=source.x; }
    near=Math.max(0,near);far=Math.min(h ? height : width,far);
    if (end<=start || far<=near) return empty;
    return h ? {x:start,y:near,width:end-start,height:far-near}
        : {x:near,y:start,width:far-near,height:end-start};
}
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
// BodyHost produces plain numeric geometry records locally. Only that path
// opts into scalar preparation; external callers retain the original reads.
function popupShouldersSnapshot(width,height,insets,edge,record,radius,softness,recordRadius,roundZeroCorners,cornerWidthInsets) {
    return _popupShoulders(width,height,insets,edge,record,radius,softness,recordRadius,roundZeroCorners,cornerWidthInsets,true);
}
function _shoulderSnapshotNumber(value) {
    return typeof value === "number" && Number.isFinite(value) && Math.abs(value)<=32768;
}
function popupShoulders(width,height,insets,edge,record,radius,softness,recordRadius,roundZeroCorners,cornerWidthInsets) {
    return _popupShoulders(width,height,insets,edge,record,radius,softness,recordRadius,roundZeroCorners,cornerWidthInsets,false);
}
function _popupShoulders(width,height,insets,edge,record,radius,softness,recordRadius,roundZeroCorners,cornerWidthInsets,numericSnapshot) {
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
    var contactRadius=touches && contactEnabled ? physicalContactRadius(
        surface,radius,popupRadius,h ? surface.width : surface.height,physicalDepth) : 0;
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
    // An adjacent real Edge can make the workspace boundary non-monotone.
    // Scan its finite support exactly instead of bridging an empty pixel gap.
    var cornerSupport=radius+softness;
    var cornerStart=(h ? insets.left : insets.top)+cornerSupport;
    var cornerEnd=extent-(h ? insets.right : insets.bottom)-cornerSupport;
    var painted;
    if (numericSnapshot === true && _shoulderSnapshotNumber(width) && _shoulderSnapshotNumber(height)
            && _shoulderSnapshotNumber(radius) && _shoulderSnapshotNumber(softness)
            && _shoulderSnapshotNumber(popupRadius) && _shoulderSnapshotNumber(surface.x)
            && _shoulderSnapshotNumber(surface.y) && _shoulderSnapshotNumber(surface.width)
            && _shoulderSnapshotNumber(surface.height)) {
        // Reuse scalar geometry only for the caller-owned numeric snapshot.
        var wx=workspaceRect.x,wy=workspaceRect.y,ww=workspaceRect.width/2,wh=workspaceRect.height/2;
        var wr=Math.min(radius,ww,wh);
        var sx=surface.x,sy=surface.y,sw=surface.width/2,sh=surface.height/2;
        var sr=Math.min(popupRadius,sw,sh),sxEnd=surface.x+surface.width,syEnd=surface.y+surface.height;
        var rt=contactEdges[0] && sy<=0 && syEnd>0 ? physicalContactRadius(surface,radius,popupRadius,surface.width,syEnd) : 0;
        var rb=contactEdges[2] && syEnd>=height && sy<height ? physicalContactRadius(surface,radius,popupRadius,surface.width,height-sy) : 0;
        var rl=contactEdges[3] && sx<=0 && sxEnd>0 ? physicalContactRadius(surface,radius,popupRadius,surface.height,sxEnd) : 0;
        var rr=contactEdges[1] && sxEnd>=width && sx<width ? physicalContactRadius(surface,radius,popupRadius,surface.height,width-sx) : 0;
        // Each strip has one fixed cross coordinate. Prepare that axis once
        // inside this numeric snapshot, retaining the original SDF arithmetic.
        // Nothing is retained across calls or shared between different bodies.
        var lastCross=NaN,workspaceCross=0,surfaceCross=0;
        painted=function(tangent,cross) {
            if (cross!==lastCross) {
                lastCross=cross;
                workspaceCross=h ? Math.abs(cross+.5-wy-wh)-wh+wr : Math.abs(cross+.5-wx-ww)-ww+wr;
                surfaceCross=h ? Math.abs(cross+.5-sy-sh)-sh+sr : Math.abs(cross+.5-sx-sw)-sw+sr;
            }
            var x=h ? tangent+.5 : cross+.5;
            var y=h ? cross+.5 : tangent+.5;
            var qx=h ? Math.abs(x-wx-ww)-ww+wr : workspaceCross;
            var qy=h ? workspaceCross : Math.abs(y-wy-wh)-wh+wr;
            var d=-(Math.hypot(Math.max(qx,0),Math.max(qy,0))+Math.min(Math.max(qx,qy),0)-wr);
            qx=h ? Math.abs(x-sx-sw)-sw+sr : surfaceCross;
            qy=h ? surfaceCross : Math.abs(y-sy-sh)-sh+sr;
            var bd=Math.hypot(Math.max(qx,0),Math.max(qy,0))+Math.min(Math.max(qx,qy),0)-sr;
            var cd=Infinity;
            if(rt>0)cd=Math.min(cd,contactCornerDistance(x,y,sx,sxEnd,rt));
            if(rb>0)cd=Math.min(cd,contactCornerDistance(x,height-y,sx,sxEnd,rb));
            if(rl>0)cd=Math.min(cd,contactCornerDistance(y,x,sy,syEnd,rl));
            if(rr>0)cd=Math.min(cd,contactCornerDistance(y,width-x,sy,syEnd,rr));
            d=smoothUnion(d,Math.min(bd,cd),softness);
            return d<0;
        };
    } else {
        painted=function(tangent,cross) {
            var x=h ? tangent+.5 : cross+.5;
            var y=h ? cross+.5 : tangent+.5;
            var d=-roundedDistance(x,y,workspaceRect,radius);
            d=smoothUnion(d,surfaceDistance(x,y,width,height,surface,popupRadius,contactEdges,radius),softness);
            return d<0;
        };
    }
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
    if(!(radius>0))return Infinity;
    var q=Math.min(tangent-start+radius,end+radius-tangent);
    // Finite distance outside the two endpoints keeps AA and shadow attached
    // to the actual contour rather than cutting them off at an invisible box.
    if(normal<0)return Math.hypot(Math.min(q,0),normal);
    if(normal>radius)return Math.min(Math.hypot(Math.min(q,0),normal),
        Math.hypot(Math.max(radius-q,0),normal-radius));
    if(q<0)return Math.hypot(q,normal);
    var circle=radius-Math.hypot(q,normal-radius);
    var clip=Math.max(-q,-normal,normal-radius);
    return Math.max(circle,clip);
}
function physicalContactRadius(rect,radius,bodyRadius,span,depth) {
    // The concave contact must end on the body's straight side, before the
    // inherited/custom bottom rounding begins. Otherwise their union produces
    // a protruding tip and a different shadow near the module's lower corner.
    var rounded=Math.max(0,Math.min(bodyRadius,rect.width/2,rect.height/2));
    return Math.max(0,Math.min(radius,span/2,depth-rounded));
}
function physicalContactDistance(x,y,width,height,rect,radius,enabledEdges,bodyRadius) {
    if(!enabledEdges)return Infinity;
    var d=Infinity;
    if(enabledEdges[0] && rect.y<=0 && rect.y+rect.height>0)
        d=Math.min(d,contactCornerDistance(x,y,rect.x,rect.x+rect.width,
            physicalContactRadius(rect,radius,bodyRadius ?? 0,rect.width,rect.y+rect.height)));
    if(enabledEdges[2] && rect.y+rect.height>=height && rect.y<height)
        d=Math.min(d,contactCornerDistance(x,height-y,rect.x,rect.x+rect.width,
            physicalContactRadius(rect,radius,bodyRadius ?? 0,rect.width,height-rect.y)));
    if(enabledEdges[3] && rect.x<=0 && rect.x+rect.width>0)
        d=Math.min(d,contactCornerDistance(y,x,rect.y,rect.y+rect.height,
            physicalContactRadius(rect,radius,bodyRadius ?? 0,rect.height,rect.x+rect.width)));
    if(enabledEdges[1] && rect.x+rect.width>=width && rect.x<width)
        d=Math.min(d,contactCornerDistance(y,width-x,rect.y,rect.y+rect.height,
            physicalContactRadius(rect,radius,bodyRadius ?? 0,rect.height,width-rect.x)));
    return d;
}
function surfaceDistance(x,y,width,height,rect,radius,enabledEdges,contactRadius) {
    return Math.min(roundedDistance(x,y,rect,radius),
        physicalContactDistance(x,y,width,height,rect,contactRadius ?? radius,enabledEdges,radius));
}
function distance(x, y, width, height, insets, radius, records, softness, recordRadius, roundZeroCorners, cornerWidthInsets) {
    var left=insets.left>0 ? insets.left : -64, top=insets.top>0 ? insets.top : -64;
    var right=insets.right>0 ? insets.right : -64, bottom=insets.bottom>0 ? insets.bottom : -64;
    var d = -roundedDistance(x,y,{x:left,y:top,width:width-left-right,height:height-top-bottom},radius);
    var contactEdges=physicalContactMask(cornerWidthInsets ?? insets,roundZeroCorners);
    for (var i=0;i<records.length;i++) {
        var rec=records[i];
        if (rec.surface.width>0 && rec.surface.height>0)
            d=smoothUnion(d,surfaceDistance(x,y,width,height,rec.surface,rec.radius ?? recordRadius ?? radius,contactEdges,radius),softness);
    }
    return d;
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
