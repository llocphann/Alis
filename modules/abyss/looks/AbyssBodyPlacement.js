// Allocate content around its physical Edge anchor. The allocator never searches
// laterally for a different anchor: it keeps the requested anchor center, stacks
// peers inward, then shrinks/reflows only as far as the host's readable minimum.
// If even that cannot fit, the lower-priority body is temporarily evicted. Its
// host keeps the loaded draft and animates the previous geometry closed.
function _number(value, fallback) {
    var number = Number(value);
    return Number.isFinite(number) ? number : fallback;
}
function _dedupeSteps(values) {
    return values.filter(function(value, index, list) {
        return list.findIndex(function(other) { return Math.abs(other-value) < .5; }) === index;
    });
}
function _steps(full, minimum, extra) {
    full = Math.max(0, _number(full, 0));
    minimum = Math.max(0, Math.min(full, _number(minimum, full)));
    if (full <= 0) return [0];
    var values = [full, Math.max(minimum, full * .88),
        Math.max(minimum, full * .74), minimum];
    (extra || []).forEach(function(v) {
        var n = _number(v, NaN);
        if (Number.isFinite(n) && n >= minimum - .01 && n <= full + .01)
            values.push(Math.max(minimum, Math.min(full, n)));
    });
    values.sort(function(a, b) { return b - a; });
    return _dedupeSteps(values);
}
function _blockerFitSteps(request, fullSpan, fullDepth, minSpan, minDepth, accepted, gap, width, height, insets) {
    var extraSpans = [], extraDepths = [];
    if (!request || !request.record || !accepted || !accepted.length)
        return {spans: extraSpans, depths: extraDepths};
    var record = request.record, edge = record.edge;
    var horizontal = edge === "top" || edge === "bottom";
    var fullContentSpan = horizontal ? record.content.width : record.content.height;
    var inferredPadding = Math.max(0, (record.span - fullContentSpan) / 2);
    var padding = Math.max(0, _number(request.padding, inferredPadding));
    var anchorCenter = record.along + record.span / 2;
    var minimumInward = Math.max(0, _number(request.minimumInward, 0));
    accepted.forEach(function(other) {
        var maxContentDepth;
        if (horizontal) {
            maxContentDepth = edge === "top"
                ? other.y - gap - (insets.top + padding + minimumInward)
                : (height - insets.bottom - padding - minimumInward) - (other.y + other.height + gap);
        } else {
            maxContentDepth = edge === "left"
                ? other.x - gap - (insets.left + padding + minimumInward)
                : (width - insets.right - padding - minimumInward) - (other.x + other.width + gap);
        }
        var fitDepth = maxContentDepth + 2 * padding;
        if (fitDepth >= minDepth && fitDepth <= fullDepth) {
            extraDepths.push(fitDepth);
            if (request.preserveAspect === true && fullDepth > 0)
                extraSpans.push(Math.max(minSpan, Math.min(fullSpan, fullSpan * (fitDepth / fullDepth))));
        }
        var otherStart = horizontal ? other.x : other.y;
        var otherEnd = otherStart + (horizontal ? other.width : other.height);
        if (otherEnd + gap <= anchorCenter) {
            var fitSpanBefore = 2 * ((anchorCenter - (otherEnd + gap)) + padding);
            if (fitSpanBefore >= minSpan && fitSpanBefore <= fullSpan)
                extraSpans.push(fitSpanBefore);
        }
        if (otherStart - gap >= anchorCenter) {
            var fitSpanAfter = 2 * (((otherStart - gap) - anchorCenter) + padding);
            if (fitSpanAfter >= minSpan && fitSpanAfter <= fullSpan)
                extraSpans.push(fitSpanAfter);
        }
    });
    return {spans: extraSpans, depths: extraDepths};
}
function _candidateSizes(fullSpan, fullDepth, minSpan, minDepth, extraSpans, extraDepths, preserveAspect) {
    var spans = _steps(fullSpan, minSpan, extraSpans), depths = _steps(fullDepth, minDepth, extraDepths);
    var result = [];
    spans.forEach(function(span) {
        depths.forEach(function(depth) {
            var spanRatio = fullSpan > 0 ? span / fullSpan : 1;
            var depthRatio = fullDepth > 0 ? depth / fullDepth : 1;
            var aspectPenalty = preserveAspect === true ? Math.abs(spanRatio - depthRatio) * .35 : 0;
            result.push({span:span, depth:depth,
                cost:(1 - spanRatio) + (1 - depthRatio) + aspectPenalty});
        });
    });
    result.sort(function(a,b) {
        return a.cost-b.cost || (b.span*b.depth)-(a.span*a.depth);
    });
    return result;
}
function _contentRect(request, span, depth, inward, width, height, insets) {
    var record = request.record, edge = record.edge;
    var horizontal = edge === "top" || edge === "bottom";
    var reverse = edge === "bottom" || edge === "right";
    var fullContentSpan = horizontal ? record.content.width : record.content.height;
    var inferredPadding = Math.max(0, (record.span-fullContentSpan)/2);
    var padding = Math.max(0, _number(request.padding, inferredPadding));
    var alongPadding = Math.min(padding, span/2);
    var crossPadding = Math.min(padding, depth/2);
    var anchorCenter = record.along + record.span/2;
    var along = anchorCenter-span/2;
    var contentSpan = Math.max(0, span-2*alongPadding);
    var contentDepth = Math.max(0, depth-2*crossPadding);
    var x, y;
    if (horizontal) {
        x = along+alongPadding;
        y = edge === "top"
            ? insets.top+crossPadding+inward
            : height-insets.bottom-depth+crossPadding-inward;
        return {x:x,y:y,width:contentSpan,height:contentDepth};
    }
    x = edge === "left"
        ? insets.left+crossPadding+inward
        : width-insets.right-depth+crossPadding-inward;
    y = along+alongPadding;
    return {x:x,y:y,width:contentDepth,height:contentSpan};
}
function _within(rect, width, height, insets) {
    return rect.width > 0 && rect.height > 0
        && rect.x >= insets.left-.01 && rect.y >= insets.top-.01
        && rect.x+rect.width <= width-insets.right+.01
        && rect.y+rect.height <= height-insets.bottom+.01;
}
function _collides(rect, accepted, gap) {
    return accepted.some(function(other) {
        return rect.x < other.x+other.width+gap
            && rect.x+rect.width+gap > other.x
            && rect.y < other.y+other.height+gap
            && rect.y+rect.height+gap > other.y;
    });
}
function _tiers(request, span, depth, accepted, gap, width, height, insets, sameEdgeOnly) {
    var base = _contentRect(request,span,depth,0,width,height,insets);
    var edge = request.record.edge;
    var horizontal = edge === "top" || edge === "bottom";
    var reverse = edge === "bottom" || edge === "right";
    var minimumInward=Math.max(0,_number(request.minimumInward,0));
    var tiers = [minimumInward];
    if (request.allowInward === false) return tiers;
    accepted.forEach(function(other) {
        if (sameEdgeOnly && other.edge && other.edge !== edge)
            return;
        var baseAlongStart = horizontal ? base.x : base.y;
        var baseAlongEnd = baseAlongStart+(horizontal ? base.width : base.height);
        var otherAlongStart = horizontal ? other.x : other.y;
        var otherAlongEnd = otherAlongStart+(horizontal ? other.width : other.height);
        if (baseAlongStart >= otherAlongEnd+gap || baseAlongEnd+gap <= otherAlongStart)
            return;
        var baseCrossStart = horizontal ? base.y : base.x;
        var baseCrossEnd = baseCrossStart+(horizontal ? base.height : base.width);
        var otherCrossStart = horizontal ? other.y : other.x;
        var otherCrossEnd = otherCrossStart+(horizontal ? other.height : other.width);
        var tier = reverse
            ? baseCrossEnd-otherCrossStart+gap
            : otherCrossEnd-baseCrossStart+gap;
        if (tier > minimumInward) tiers.push(tier);
    });
    return tiers.filter(function(value,index,list) {
        return list.findIndex(function(other) { return Math.abs(other-value) < .5; }) === index;
    }).sort(function(a,b) { return a-b; });
}
function _pyramidDescriptor(request) {
    var record=request?.record;
    if (!record) return null;
    var horizontal=record.edge === "top" || record.edge === "bottom";
    var content=record.content || {};
    var start=horizontal
        ? _number(content.x,_number(record.along,0))
        : _number(content.y,_number(record.along,0));
    var extent=horizontal
        ? _number(content.width,_number(record.span,0))
        : _number(content.height,_number(record.span,0));
    extent=Math.max(0,extent);
    return {
        edge:String(record.edge || ""),
        tangentStart:start,
        tangentEnd:start+extent,
        proximity:Math.max(0,_number(request?.stackProximity,24))
    };
}
function _pyramidDescriptorGap(a,b) {
    if (!a || !b || a.edge !== b.edge) return Infinity;
    if (a.tangentEnd < b.tangentStart)
        return b.tangentStart-a.tangentEnd;
    if (b.tangentEnd < a.tangentStart)
        return a.tangentStart-b.tangentEnd;
    return 0;
}
function _pyramidDescriptorsRelated(a,b) {
    if (!a || !b || a.edge !== b.edge) return false;
    return _pyramidDescriptorGap(a,b)
        <= Math.max(_number(a.proximity,24),_number(b.proximity,24));
}
function _samePyramidNeighborhood(a,b) {
    return a?.stackPolicy === "pyramid"
        && b?.stackPolicy === "pyramid"
        && _pyramidDescriptorsRelated(
            _pyramidDescriptor(a),_pyramidDescriptor(b));
}
function _requestedArea(request) {
    var record=request?.record;
    if (!record) return 0;
    return Math.max(0,_number(record.span,0))
        * Math.max(0,_number(record.targetDepth,record.depth || 0));
}
function _legacyCompare(a,b) {
    return (b.priority || 0)-(a.priority || 0)
        || (b.order || 0)-(a.order || 0)
        || String(a.id).localeCompare(String(b.id));
}
function _orderedRequests(requests) {
    // First establish the old globally-transitive order. Pyramid grouping is
    // then applied only inside the slots already occupied by each same-neighborhood
    // component. This preserves every outsider's relative position while
    // avoiding the previous pairwise comparator cycle:
    // large(A)<small(B), B<remote(C), C<A.
    var ordered=Array.from(requests || []).filter(function(request) {
        return request && request.open && request.record;
    }).sort(_legacyCompare);
    if (ordered.length < 2) return ordered;
    var parent=ordered.map(function(_,index) { return index; });
    function find(index) {
        while (parent[index] !== index) {
            parent[index]=parent[parent[index]];
            index=parent[index];
        }
        return index;
    }
    function join(first,second) {
        var a=find(first), b=find(second);
        if (a !== b) parent[b]=a;
    }
    for (var i=0;i<ordered.length;i++) {
        for (var j=i+1;j<ordered.length;j++) {
            if (_samePyramidNeighborhood(ordered[i],ordered[j]))
                join(i,j);
        }
    }
    var groups={};
    for (var index=0;index<ordered.length;index++) {
        var key=String(find(index));
        if (!groups[key]) groups[key]=[];
        groups[key].push(index);
    }
    Object.keys(groups).forEach(function(key) {
        var slots=groups[key];
        if (slots.length < 2) return;
        var members=slots.map(function(index) { return ordered[index]; });
        // All members of this component are pyramid peers connected by the
        // same overlap/proximity relation. Larger resting area owns the earlier
        // (more Edge-direct) slot; equal areas keep the legacy tie-breaks.
        members.sort(function(a,b) {
            var areaDelta=_requestedArea(b)-_requestedArea(a);
            return Math.abs(areaDelta)>.5 ? areaDelta : _legacyCompare(a,b);
        });
        for (var n=0;n<slots.length;n++)
            ordered[slots[n]]=members[n];
    });
    return ordered;
}
function arrange(requests, width, height, insets, gap) {
    gap = gap === undefined ? 24 : Math.max(0, gap);
    var result = {}, accepted = [];
    var ordered = _orderedRequests(requests);
    ordered.forEach(function(request) {
        var record = request.record;
        var fullSpan = Math.max(0,_number(record.span,0));
        var fullDepth = Math.max(0,_number(record.targetDepth,record.depth || 0));
        var minSpan = Math.max(0,Math.min(fullSpan,_number(request.minSpan,fullSpan)));
        var minDepth = Math.max(0,Math.min(fullDepth,_number(request.minDepth,fullDepth)));
        var placement = null;
        var minimumInward = Math.max(0,_number(request.minimumInward,0));
        var baseRect = _contentRect(request,fullSpan,fullDepth,minimumInward,width,height,insets);
        if (_within(baseRect,width,height,insets) && !_collides(baseRect,accepted,gap)) {
            var baseCenter = record.along+record.span/2;
            placement = {
                visible:true,
                evicted:false,
                along:baseCenter-fullSpan/2,
                inward:minimumInward,
                span:fullSpan,
                depth:fullDepth,
                shrunk:false,
                content:baseRect
            };
            accepted.push({x:baseRect.x,y:baseRect.y,width:baseRect.width,height:baseRect.height,edge:record.edge});
        }
        var fit = placement ? null : _blockerFitSteps(request,fullSpan,fullDepth,minSpan,minDepth,accepted,gap,width,height,insets);
        var sizes = placement ? [] : _candidateSizes(fullSpan,fullDepth,minSpan,minDepth,fit.spans,fit.depths,request.preserveAspect === true);
        var passes = [true, false];
        for (var p=0; p<passes.length && !placement; p++) {
            for (var s=0; s<sizes.length && !placement; s++) {
                var size = sizes[s];
                var tiers = _tiers(request,size.span,size.depth,accepted,gap,width,height,insets,passes[p]);
                for (var t=0; t<tiers.length && !placement; t++) {
                    var rect = _contentRect(request,size.span,size.depth,tiers[t],
                        width,height,insets);
                    if (!_within(rect,width,height,insets) || _collides(rect,accepted,gap))
                        continue;
                    var anchorCenter = record.along+record.span/2;
                    placement = {
                        visible:true,
                        evicted:false,
                        along:anchorCenter-size.span/2,
                        inward:tiers[t],
                        span:size.span,
                        depth:size.depth,
                        shrunk:size.span < fullSpan-.5 || size.depth < fullDepth-.5,
                        content:rect
                    };
                    accepted.push({x:rect.x,y:rect.y,width:rect.width,height:rect.height,edge:record.edge});
                }
            }
        }
        result[request.id] = placement || {
            visible:false,
            evicted:true,
            along:record.along,
            inward:0,
            span:fullSpan,
            depth:fullDepth,
            shrunk:false
        };
    });
    return result;
}
