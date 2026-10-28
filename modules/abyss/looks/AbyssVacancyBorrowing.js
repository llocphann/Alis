// Semantic vacancy borrowing for paired Abyss surfaces.
// The base allocator remains authoritative; this post-pass may only enlarge
// already-visible content into geometry proven free on this output.
var _vacancyPairs = [
    {role:"featureSidebar", peer:"quickNotes", automatic:"quickNotes"},
    {role:"systemSidebar", peer:"notificationCenter", automatic:"notificationCenter"},
    // Controls-owned connectivity dialogs are WindowDialog surfaces, not
    // StyledPopups. They fill the free strip parallel to the logical system
    // sidebar while preserving the already-resolved gap between both bodies.
    {role:"systemSidebar", peer:"connectivityDialog",
        automatic:"connectivityDialog", parallelEnvelope:true}
];

function _vacancyNumber(value, fallback) {
    var n=Number(value);
    return Number.isFinite(n) ? n : fallback;
}
function _vacancyRect(value) {
    return {
        x:_vacancyNumber(value?.x,0),
        y:_vacancyNumber(value?.y,0),
        width:Math.max(0,_vacancyNumber(value?.width,0)),
        height:Math.max(0,_vacancyNumber(value?.height,0))
    };
}
function _vacancyHorizontal(edge) {
    return edge === "top" || edge === "bottom";
}
function _vacancyPadding(request,width,height,insets) {
    var edge=String(request?.record?.edge ?? "");
    var h=_vacancyHorizontal(edge);
    var first=h ? _vacancyNumber(insets?.left,0) : _vacancyNumber(insets?.top,0);
    var last=h ? width-_vacancyNumber(insets?.right,0)
        : height-_vacancyNumber(insets?.bottom,0);
    return Math.max(0,Math.min(_vacancyNumber(request?.padding,0),
        Math.max(0,last-first)/8));
}
function _vacancyPanelRect(request,placement,width,height,insets) {
    var edge=String(request?.record?.edge ?? "");
    var h=_vacancyHorizontal(edge);
    var along=_vacancyNumber(placement?.along,0);
    var span=Math.max(0,_vacancyNumber(placement?.span,0));
    var depth=Math.max(0,_vacancyNumber(placement?.depth,0));
    var inward=Math.max(0,_vacancyNumber(placement?.inward,0));
    if (h) {
        return {x:along,
            y:edge === "top" ? _vacancyNumber(insets?.top,0)+inward
                : height-_vacancyNumber(insets?.bottom,0)-depth-inward,
            width:span,height:depth};
    }
    return {
        x:edge === "left" ? _vacancyNumber(insets?.left,0)+inward
            : width-_vacancyNumber(insets?.right,0)-depth-inward,
        y:along,width:depth,height:span
    };
}
function _vacancySafeBounds(request,width,height,insets) {
    var edge=String(request?.record?.edge ?? "");
    var h=_vacancyHorizontal(edge);
    var p=_vacancyPadding(request,width,height,insets);
    return {
        left:_vacancyNumber(insets?.left,0)+(h ? p : 0),
        top:_vacancyNumber(insets?.top,0)+(h ? 0 : p),
        right:width-_vacancyNumber(insets?.right,0)-(h ? p : 0),
        bottom:height-_vacancyNumber(insets?.bottom,0)-(h ? 0 : p)
    };
}
function _vacancyCenter(rect,axis) {
    return axis === "x" ? rect.x+rect.width/2 : rect.y+rect.height/2;
}
function _vacancyDirectionAllowed(edge,direction) {
    if (edge === "top" && direction === "top") return false;
    if (edge === "bottom" && direction === "bottom") return false;
    if (edge === "left" && direction === "left") return false;
    if (edge === "right" && direction === "right") return false;
    return true;
}
function _vacancyTowardPeer(owner,peer,direction) {
    // A direction is eligible only when the two final content rectangles are
    // actually separated on that axis. Center-to-center heuristics are wrong
    // for side-by-side panels whose vertical centers differ: they can turn a
    // narrow horizontal vacancy into a near-full-height expansion.
    var ownerRight=owner.x+owner.width;
    var ownerBottom=owner.y+owner.height;
    var peerRight=peer.x+peer.width;
    var peerBottom=peer.y+peer.height;
    if (direction === "top")
        return peerBottom <= owner.y+.01
            ? Math.max(0,owner.y-peerBottom) : 0;
    if (direction === "bottom")
        return peer.y >= ownerBottom-.01
            ? Math.max(0,peer.y-ownerBottom) : 0;
    if (direction === "left")
        return peerRight <= owner.x+.01
            ? Math.max(0,owner.x-peerRight) : 0;
    return peer.x >= ownerRight-.01
        ? Math.max(0,peer.x-ownerRight) : 0;
}
function _vacancyEnvelopeExtent(owner,peer,direction) {
    // When the owner is still Edge-direct and its peer was pushed inward by
    // the base allocator, the real vacancy is the remainder of the owner's
    // outer strip. Grow only as far as the peer's tangent envelope; blockers
    // and safe bounds still cap the result below.
    if (direction === "top") {
        if (_vacancyCenter(peer,"y") >= _vacancyCenter(owner,"y")-.01) return 0;
        return Math.max(0,owner.y-peer.y);
    }
    if (direction === "bottom") {
        if (_vacancyCenter(peer,"y") <= _vacancyCenter(owner,"y")+.01) return 0;
        return Math.max(0,peer.y+peer.height-(owner.y+owner.height));
    }
    if (direction === "left") {
        if (_vacancyCenter(peer,"x") >= _vacancyCenter(owner,"x")-.01) return 0;
        return Math.max(0,owner.x-peer.x);
    }
    if (_vacancyCenter(peer,"x") <= _vacancyCenter(owner,"x")+.01) return 0;
    return Math.max(0,peer.x+peer.width-(owner.x+owner.width));
}
function _vacancyParallelEnvelopeExtent(owner,peer,direction) {
    var ownerRight=owner.x+owner.width, peerRight=peer.x+peer.width;
    var ownerBottom=owner.y+owner.height, peerBottom=peer.y+peer.height;
    // Parallel growth is valid only when the semantic peers occupy separate
    // columns/rows. It preserves their existing orthogonal separation instead
    // of consuming the literal gap between them.
    if (direction === "top" || direction === "bottom") {
        if (!(ownerRight <= peer.x+.01 || peerRight <= owner.x+.01)) return 0;
        if (direction === "top")
            return peer.y < owner.y-.01 ? owner.y-peer.y : 0;
        return peerBottom > ownerBottom+.01 ? peerBottom-ownerBottom : 0;
    }
    if (!(ownerBottom <= peer.y+.01 || peerBottom <= owner.y+.01)) return 0;
    if (direction === "left")
        return peer.x < owner.x-.01 ? owner.x-peer.x : 0;
    return peerRight > ownerRight+.01 ? peerRight-ownerRight : 0;
}
function _vacancySafeExtent(panel,bounds,direction) {
    if (direction === "top") return Math.max(0,panel.y-bounds.top);
    if (direction === "bottom") return Math.max(0,bounds.bottom-(panel.y+panel.height));
    if (direction === "left") return Math.max(0,panel.x-bounds.left);
    return Math.max(0,bounds.right-(panel.x+panel.width));
}
function _vacancyProjectionOverlaps(a,b,direction,gap) {
    if (direction === "top" || direction === "bottom")
        return a.x < b.x+b.width+gap && a.x+a.width+gap > b.x;
    return a.y < b.y+b.height+gap && a.y+a.height+gap > b.y;
}
function _vacancyBlockerExtent(content,blocker,direction,gap) {
    if (!_vacancyProjectionOverlaps(content,blocker,direction,gap)) return Infinity;
    if (direction === "top") {
        var bb=blocker.y+blocker.height;
        return bb <= content.y+.01 ? Math.max(0,content.y-bb-gap) : Infinity;
    }
    if (direction === "bottom") {
        var cb=content.y+content.height;
        return blocker.y >= cb-.01 ? Math.max(0,blocker.y-cb-gap) : Infinity;
    }
    if (direction === "left") {
        var br=blocker.x+blocker.width;
        return br <= content.x+.01 ? Math.max(0,content.x-br-gap) : Infinity;
    }
    var cr=content.x+content.width;
    return blocker.x >= cr-.01 ? Math.max(0,blocker.x-cr-gap) : Infinity;
}
function _vacancyGrow(rect,direction,delta) {
    var r=_vacancyRect(rect);
    if (direction === "top") { r.y-=delta; r.height+=delta; }
    else if (direction === "bottom") r.height+=delta;
    else if (direction === "left") { r.x-=delta; r.width+=delta; }
    else r.width+=delta;
    return r;
}
function _vacancyCollides(a,b,gap) {
    return a.x < b.x+b.width+gap && a.x+a.width+gap > b.x
        && a.y < b.y+b.height+gap && a.y+a.height+gap > b.y;
}
function _vacancyExpandedPlacement(request,base,content,direction,delta) {
    var edge=String(request?.record?.edge ?? "");
    var h=_vacancyHorizontal(edge);
    var out=Object.assign({},base,{
        content:content,vacancyBorrowed:true,
        vacancyDirection:direction,vacancyDelta:delta
    });
    if (h) {
        if (direction === "left") { out.along=base.along-delta; out.span=base.span+delta; }
        else if (direction === "right") out.span=base.span+delta;
        else out.depth=base.depth+delta;
    } else {
        if (direction === "top") { out.along=base.along-delta; out.span=base.span+delta; }
        else if (direction === "bottom") out.span=base.span+delta;
        else out.depth=base.depth+delta;
    }
    return out;
}
function _vacancyMemberForRole(role,metadata,requestById,placements) {
    var list=(metadata || []).filter(function(item) {
        var id=String(item?.id ?? "");
        var req=requestById[id], p=placements?.[id];
        return String(item?.role ?? "") === role
            && req?.open === true && p && p.visible !== false && p.content;
    });
    list.sort(function(a,b) {
        var ar=requestById[String(a.id)] || {}, br=requestById[String(b.id)] || {};
        return _vacancyNumber(br.order,0)-_vacancyNumber(ar.order,0)
            || String(a.id).localeCompare(String(b.id));
    });
    if (!list.length) return null;
    var meta=list[0], id=String(meta.id);
    return {id:id,role:role,meta:meta,request:requestById[id],placement:placements[id]};
}
function _vacancyBestCandidate(owner,peer,placements,width,height,insets,gap,pair) {
    var panel=_vacancyPanelRect(owner.request,owner.placement,width,height,insets);
    var content=_vacancyRect(owner.placement.content);
    var peerContent=_vacancyRect(peer.placement.content);
    var bounds=_vacancySafeBounds(owner.request,width,height,insets);
    var edge=String(owner.request?.record?.edge ?? "");
    var peerEdge=String(peer.request?.record?.edge ?? "");
    var ownerInward=Math.max(0,_vacancyNumber(owner.placement?.inward,0));
    var peerInward=Math.max(0,_vacancyNumber(peer.placement?.inward,0));
    // Same-edge coexistence can push one member inward. If this owner is the
    // outer Edge-direct member and its semantic peer was pushed inward, fill
    // the exposed strip along the peer envelope. Otherwise use only literal
    // rectangle separation, avoiding the old full-height detour.
    var fillOuterStrip=edge === peerEdge && ownerInward+.5 < peerInward;
    var h=_vacancyHorizontal(edge);
    var preferParallel=pair?.parallelEnvelope === true;
    var dirs=["top","bottom","left","right"], best=null;
    for (var i=0;i<dirs.length;i++) {
        var dir=dirs[i];
        if (!_vacancyDirectionAllowed(edge,dir)) continue;
        var tangentDir=(dir === "top" || dir === "bottom") !== h;
        if (fillOuterStrip && !tangentDir) continue;
        var parallelGap=preferParallel
            ? _vacancyParallelEnvelopeExtent(content,peerContent,dir) : 0;
        var parallel=parallelGap >= .5;
        var peerGap=parallel ? parallelGap
            : (fillOuterStrip
                ? _vacancyEnvelopeExtent(content,peerContent,dir)
                : _vacancyTowardPeer(content,peerContent,dir));
        if (peerGap < .5) continue;
        var max=Math.min(peerGap,_vacancySafeExtent(panel,bounds,dir));
        if (max < .5) continue;
        var baseCollision=false;
        for (var id in placements) {
            if (String(id) === String(owner.id)
                    || ((parallel || fillOuterStrip) && String(id) === String(peer.id))) continue;
            var p=placements[id];
            if (!p || p.visible === false || !p.content) continue;
            var blocker=_vacancyRect(p.content);
            max=Math.min(max,_vacancyBlockerExtent(content,blocker,dir,gap));
            if (max < .5) break;
            if (!baseCollision
                    && _vacancyCollides(content,blocker,gap-.01))
                baseCollision=true;
        }
        if (max < .5 || baseCollision) continue;
        var grown=_vacancyGrow(content,dir,max);
        var gain=max*((dir === "top" || dir === "bottom") ? content.width : content.height);
        // The vacancy between semantic peers is their nearest separated side.
        // For diagonal layouts, prefer that nearest side; only use area gain as
        // a tie-breaker. This prevents a long vertical detour from winning over
        // the small horizontal gap visibly connecting two side-by-side panels.
        if (!best || Number(parallel)-Number(best.parallel) > 0
                || (parallel === best.parallel && peerGap < best.peerGap-.01)
                || (parallel === best.parallel
                    && Math.abs(peerGap-best.peerGap) <= .01
                    && gain > best.gain+.01))
            best={direction:dir,delta:max,content:grown,gain:gain,
                peerGap:peerGap,parallel:parallel};
    }
    return best;
}

function resolve(requests,metadata,placements,width,height,insets,gap) {
    if (!placements || !requests?.length || !metadata?.length) return placements;
    if (requests.length < 2) {
        var single=requests[0];
        var singlePlacement=single && single.id !== undefined ? placements[String(single.id)] : null;
        if (!singlePlacement || singlePlacement.shrunk !== true) return placements;
    }
    width=Math.max(0,_vacancyNumber(width,0));
    height=Math.max(0,_vacancyNumber(height,0));
    if (width <= 0 || height <= 0) return placements;
    gap=gap === undefined ? 24 : Math.max(0,_vacancyNumber(gap,24));

    var requestById={};
    requests.forEach(function(req) {
        if (req?.id !== undefined && req?.id !== null)
            requestById[String(req.id)]=req;
    });

    var winners={
        featureSidebar:null,
        quickNotes:null,
        systemSidebar:null,
        notificationCenter:null,
        connectivityDialog:null
    };
    metadata.forEach(function(item) {
        var role=String(item?.role ?? "");
        if (!Object.prototype.hasOwnProperty.call(winners,role)) return;
        var id=String(item?.id ?? "");
        var req=requestById[id], p=placements?.[id];
        if (!(req?.open === true && p && p.visible !== false && p.content)) return;
        var order=_vacancyNumber(req.order,0);
        var current=winners[role];
        if (!current || order > current.order
                || (order === current.order
                    && id.localeCompare(current.id) < 0))
            winners[role]={id:id,meta:item,request:req,placement:p,order:order};
    });

    var plans=[];
    _vacancyPairs.forEach(function(pair) {
        var firstWinner=winners[pair.role];
        var secondWinner=winners[pair.peer];
        var first=firstWinner ? {
            id:firstWinner.id,role:pair.role,meta:firstWinner.meta,
            request:firstWinner.request,placement:firstWinner.placement
        } : null;
        var second=secondWinner ? {
            id:secondWinner.id,role:pair.peer,meta:secondWinner.meta,
            request:secondWinner.request,placement:secondWinner.placement
        } : null;
        if (!first || !second) return;

        var choices=[first,second].map(function(owner) {
            var peer=owner.id === first.id ? second : first;
            var candidate=_vacancyBestCandidate(owner,peer,placements,width,height,insets,gap,pair);
            return candidate ? {
                owner:owner,peer:peer,candidate:candidate,
                requestOrder:_vacancyNumber(owner.request?.order,0)
            } : null;
        }).filter(function(x) { return x !== null; });
        if (!choices.length) return;

        // Geometry ownership is automatic and stable. Pointer hover is not an
        // allocator input: entering a moving body must never switch owners,
        // restart placement animation, or be required to obtain the vacancy.
        var ordered=[];
        var sameEdgeSidebarOuter=String(first.request?.record?.edge ?? "")
                === String(second.request?.record?.edge ?? "")
            && Math.max(0,_vacancyNumber(first.placement?.inward,0))+.5
                < Math.max(0,_vacancyNumber(second.placement?.inward,0));
        var preferred=choices.find(function(x) {
            return x.owner.role === pair.automatic;
        });
        if (preferred && !sameEdgeSidebarOuter) ordered.push(preferred);
        choices.slice().sort(function(a,b) {
            return b.requestOrder-a.requestOrder || b.candidate.gain-a.candidate.gain
                || String(a.owner.id).localeCompare(String(b.owner.id));
        }).forEach(function(x) {
            if (ordered.indexOf(x) < 0) ordered.push(x);
        });

        plans.push({
            pairRole:pair.role,choices:ordered,
            pairOrder:Math.max(_vacancyNumber(first.request?.order,0),
                _vacancyNumber(second.request?.order,0))
        });
    });

    // Priority matters only when expanded rectangles compete. Independent pairs
    // remain expanded together.
    plans.sort(function(a,b) {
        return b.pairOrder-a.pairOrder
            || String(a.pairRole).localeCompare(String(b.pairRole));
    });

    var accepted=[], result=null;
    plans.forEach(function(plan) {
        var chosen=null;
        for (var i=0;i<plan.choices.length;i++) {
            var candidate=plan.choices[i];
            var conflict=accepted.some(function(other) {
                return _vacancyCollides(candidate.candidate.content,
                    other.candidate.content,gap-.01);
            });
            if (!conflict) { chosen=candidate; break; }
        }
        if (!chosen) return;
        if (!result) result=Object.assign({},placements);
        result[chosen.owner.id]=_vacancyExpandedPlacement(
            chosen.owner.request,chosen.owner.placement,
            chosen.candidate.content,chosen.candidate.direction,chosen.candidate.delta);
        accepted.push(chosen);
    });

    // When a body was shrunk symmetrically around its anchorCenter by a one-sided
    // perpendicular blocker (e.g. a sidebar shrunk below an overview popup),
    // restore the unblocked side back toward its requested [along, along + span].
    var working=result || placements;
    requests.forEach(function(req) {
        var id=String(req?.id ?? "");
        if (!id || req?.open !== true) return;
        var p=working[id];
        if (!p || p.visible === false || !p.content || p.vacancyBorrowed || p.shrunk !== true)
            return;
        var reqAlong=_vacancyNumber(req?.record?.along,NaN);
        var reqSpan=_vacancyNumber(req?.record?.span,NaN);
        if (!Number.isFinite(reqAlong) || !Number.isFinite(reqSpan) || p.span >= reqSpan-.5)
            return;
        var edge=String(req?.record?.edge ?? "");
        var h=_vacancyHorizontal(edge);
        var panel=_vacancyPanelRect(req,p,width,height,insets);
        var content=_vacancyRect(p.content);
        var bounds=_vacancySafeBounds(req,width,height,insets);
        var dirs=h ? ["left","right"] : ["top","bottom"];
        var best=null;
        dirs.forEach(function(dir) {
            var baseWant=dir === "left" ? Math.max(0,panel.x-reqAlong)
                : dir === "right" ? Math.max(0,(reqAlong+reqSpan)-(panel.x+panel.width))
                : dir === "top" ? Math.max(0,panel.y-reqAlong)
                : Math.max(0,(reqAlong+reqSpan)-(panel.y+panel.height));
            var oppositeShift=dir === "left" ? Math.max(0,(panel.x+panel.width)-(reqAlong+reqSpan))
                : dir === "right" ? Math.max(0,panel.x-reqAlong)
                : dir === "top" ? Math.max(0,(panel.y+panel.height)-(reqAlong+reqSpan))
                : Math.max(0,panel.y-reqAlong);
            var want=Math.min(Math.max(0,reqSpan-p.span),baseWant+oppositeShift*.5);
            if (want < .5) return;
            var max=Math.min(want,_vacancySafeExtent(panel,bounds,dir));
            if (max < .5) return;
            for (var otherId in working) {
                if (String(otherId) === id) continue;
                var op=working[otherId];
                if (!op || op.visible === false || !op.content) continue;
                max=Math.min(max,_vacancyBlockerExtent(content,_vacancyRect(op.content),dir,gap));
                if (max < .5) break;
            }
            if (max < .5) return;
            var grown=_vacancyGrow(content,dir,max);
            if (!best || max > best.delta)
                best={direction:dir,delta:max,content:grown};
        });
        if (best) {
            if (!result) { result=Object.assign({},placements); working=result; }
            result[id]=_vacancyExpandedPlacement(req,p,best.content,best.direction,best.delta);
        }
    });
    return result || placements;
}
