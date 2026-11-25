// Smart Abyss Popup & Surface Yielding Allocator.
//
// Resolution hierarchy for every open participant:
//   0. Pre-pass cooperative negotiation: heavy overlays (`cooperativeShrink: true`)
//      and perpendicular sidebars (`cooperativePeer: true`) share available width/height
//      above their readable minimums before either side is evicted.
//   1. Exact requested anchor at full size (`inward = minimumInward`, `lateralShift = 0`).
//   2. Bounded tangential lateral shift along the same Screen Edge (`|shift| <= maxLateralShift`)
//      at full size before shrinking or stacking inward.
//   3. Readable reflow/shrinking at `inward = minimumInward` (center first, then bounded shift).
//   4. Pyramid inward stacking (same-edge peers first, then cross-edge) with priority strictly
//      outranking resting area so explicit/pinned/typing surfaces beat hover-only peers.
//   5. Clean eviction (`visible: false, evicted: true`) when readable minima cannot fit.
//
// External blockers (e.g. Alis-Companion TalkCloud / Pocket) participate in collision avoidance
// whenever their priority >= the candidate request's priority.

function _number(value, fallback) {
    var number = Number(value);
    return Number.isFinite(number) ? number : fallback;
}
function _dedupeSteps(values) {
    return values.filter(function(value, index, list) {
        return list.findIndex(function(other) { return Math.abs(other - value) < .5; }) === index;
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
function _paddingFor(request) {
    var record = request.record, edge = record.edge;
    var horizontal = edge === "top" || edge === "bottom";
    var fullContentSpan = horizontal ? record.content.width : record.content.height;
    var inferredPadding = Math.max(0, (record.span - fullContentSpan) / 2);
    return Math.max(0, _number(request.padding, inferredPadding));
}
function _insetsFor(request, fallback) {
    return (request && request.edgeInsets) ? request.edgeInsets : fallback;
}
function _pairGap(request, other, baseGap, softness) {
    var reqModal = request && request.intent === "modal";
    var otherModal = other && other.isModal === true;
    if (!reqModal && !otherModal)
        return baseGap;
    var reqPad = request ? _paddingFor(request) : 0;
    var otherPad = Math.max(0, _number(other && other.padding, 0));
    var surfaceGap = Math.max(baseGap, _number(softness, 24) + 8);
    return Math.max(baseGap, reqPad + otherPad + surfaceGap);
}
function _maxLateralShift(request, fullSpan) {
    if (request.allowLateralShift === false) return 0;
    if (request.maxLateralShift !== undefined && request.maxLateralShift !== null)
        return Math.max(0, _number(request.maxLateralShift, 0));
    if (request.allowLateralShift === true)
        return Math.min(240, Math.max(120, fullSpan * 0.6));
    return 0;
}
function _blockerFitSteps(request, fullSpan, fullDepth, minSpan, minDepth, accepted, baseGap, width, height, insets, softness) {
    var extraSpans = [], extraDepths = [];
    if (!request || !request.record)
        return {spans: extraSpans, depths: extraDepths};
    var record = request.record, edge = record.edge;
    var reqInsets = _insetsFor(request, insets);
    var horizontal = edge === "top" || edge === "bottom";
    var padding = _paddingFor(request);
    var anchorCenter = record.along + record.span / 2;
    var minimumInward = Math.max(0, _number(request.minimumInward, 0));
    var oppositeClearance = Math.max(0, _number(request.oppositeClearance, 0));
    if (minimumInward > 0 || oppositeClearance > 0) {
        var viewportFitDepth = (horizontal
            ? height - reqInsets.top - reqInsets.bottom
            : width - reqInsets.left - reqInsets.right) - minimumInward - oppositeClearance;
        if (viewportFitDepth >= minDepth && viewportFitDepth <= fullDepth) {
            extraDepths.push(viewportFitDepth);
            if (request.preserveAspect === true && fullDepth > 0)
                extraSpans.push(Math.max(minSpan, Math.min(fullSpan, fullSpan * (viewportFitDepth / fullDepth))));
        }
    }
    if (!accepted || !accepted.length)
        return {spans: extraSpans, depths: extraDepths};
    accepted.forEach(function(other) {
        var gap = _pairGap(request, other, baseGap, softness);
        var maxContentDepth;
        if (horizontal) {
            maxContentDepth = edge === "top"
                ? other.y - gap - (reqInsets.top + padding + minimumInward)
                : (height - reqInsets.bottom - padding - minimumInward) - (other.y + other.height + gap);
        } else {
            maxContentDepth = edge === "left"
                ? other.x - gap - (reqInsets.left + padding + minimumInward)
                : (width - reqInsets.right - padding - minimumInward) - (other.x + other.width + gap);
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
        if (request.allowPerpendicularShift === true && other.edge) {
            var otherH = other.edge === "top" || other.edge === "bottom";
            if (otherH !== horizontal) {
                var axisFirst = horizontal ? reqInsets.left : reqInsets.top;
                var axisLast = horizontal ? (width - reqInsets.right) : (height - reqInsets.bottom);
                var availAfter = (axisLast - 2 * padding) - (otherEnd + gap);
                if (availAfter > 0) {
                    var oneSideAfter = availAfter + 2 * padding;
                    if (oneSideAfter >= minSpan && oneSideAfter <= fullSpan)
                        extraSpans.push(oneSideAfter);
                }
                var availBefore = (otherStart - gap) - (axisFirst + 2 * padding);
                if (availBefore > 0) {
                    var oneSideBefore = availBefore + 2 * padding;
                    if (oneSideBefore >= minSpan && oneSideBefore <= fullSpan)
                        extraSpans.push(oneSideBefore);
                }
            }
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
            result.push({span: span, depth: depth,
                cost: (1 - spanRatio) + (1 - depthRatio) + aspectPenalty});
        });
    });
    result.sort(function(a, b) {
        return a.cost - b.cost || (b.span * b.depth) - (a.span * a.depth);
    });
    return result;
}
function _contentRect(request, span, depth, inward, width, height, insets, lateralShift) {
    var record = request.record, edge = record.edge;
    var reqInsets = _insetsFor(request, insets);
    var horizontal = edge === "top" || edge === "bottom";
    var padding = _paddingFor(request);
    var alongPadding = Math.min(padding, span / 2);
    var crossPadding = Math.min(padding, depth / 2);
    var anchorCenter = record.along + record.span / 2 + _number(lateralShift, 0);
    var along = anchorCenter - span / 2;
    var contentSpan = Math.max(0, span - 2 * alongPadding);
    var contentDepth = Math.max(0, depth - 2 * crossPadding);
    var x, y;
    if (horizontal) {
        x = along + alongPadding;
        y = edge === "top"
            ? reqInsets.top + crossPadding + inward
            : height - reqInsets.bottom - depth + crossPadding - inward;
        return {x: x, y: y, width: contentSpan, height: contentDepth};
    }
    x = edge === "left"
        ? reqInsets.left + crossPadding + inward
        : width - reqInsets.right - depth + crossPadding - inward;
    y = along + alongPadding;
    return {x: x, y: y, width: contentDepth, height: contentSpan};
}
function _within(rect, width, height, insets, request) {
    var reqInsets = _insetsFor(request, insets);
    return rect.width > 0 && rect.height > 0
        && rect.x >= reqInsets.left - .01 && rect.y >= reqInsets.top - .01
        && rect.x + rect.width <= width - reqInsets.right + .01
        && rect.y + rect.height <= height - reqInsets.bottom + .01;
}
function _withinOpposite(rect, request, depth, width, height, insets) {
    var oppositeClearance = Math.max(0, _number(request && request.oppositeClearance, 0));
    if (oppositeClearance <= 0) return true;
    var reqInsets = _insetsFor(request, insets);
    var record = request.record, edge = record.edge;
    var padding = _paddingFor(request);
    var crossPadding = Math.min(padding, depth / 2);
    if (edge === "top")
        return rect.y + rect.height + crossPadding <= height - reqInsets.bottom - oppositeClearance + .01;
    if (edge === "bottom")
        return rect.y - crossPadding >= reqInsets.top + oppositeClearance - .01;
    if (edge === "left")
        return rect.x + rect.width + crossPadding <= width - reqInsets.right - oppositeClearance + .01;
    if (edge === "right")
        return rect.x - crossPadding >= reqInsets.left + oppositeClearance - .01;
    return true;
}
function _collides(rect, accepted, baseGap, request, softness) {
    return accepted.some(function(other) {
        var gap = _pairGap(request, other, baseGap, softness);
        return rect.x < other.x + other.width + gap - 1e-4
            && rect.x + rect.width + gap > other.x + 1e-4
            && rect.y < other.y + other.height + gap - 1e-4
            && rect.y + rect.height + gap > other.y + 1e-4;
    });
}
function _lateralShifts(request, span, depth, inward, blockers, baseGap, width, height, insets, maxShift, softness) {
    if (!(maxShift > .5)) return [];
    var base = _contentRect(request, span, depth, inward, width, height, insets, 0);
    var edge = request.record.edge;
    var reqInsets = _insetsFor(request, insets);
    var horizontal = edge === "top" || edge === "bottom";
    var minBound = horizontal ? reqInsets.left : reqInsets.top;
    var maxBound = horizontal ? (width - reqInsets.right) : (height - reqInsets.bottom);
    var baseStart = horizontal ? base.x : base.y;
    var baseLen = horizontal ? base.width : base.height;
    var baseEnd = baseStart + baseLen;
    var baseCrossStart = horizontal ? base.y : base.x;
    var baseCrossEnd = baseCrossStart + (horizontal ? base.height : base.width);
    var raw = [];
    // Include viewport edge clamp shifts if base slightly overhangs a screen edge
    if (baseStart < minBound - .01) raw.push(minBound - baseStart);
    if (baseEnd > maxBound + .01) raw.push(maxBound - baseEnd);
    blockers.forEach(function(other) {
        var gap = _pairGap(request, other, baseGap, softness);
        var oCrossStart = horizontal ? other.y : other.x;
        var oCrossEnd = oCrossStart + (horizontal ? other.height : other.width);
        if (baseCrossStart >= oCrossEnd + gap || baseCrossEnd + gap <= oCrossStart)
            return;
        var oStart = horizontal ? other.x : other.y;
        var oEnd = oStart + (horizontal ? other.width : other.height);
        raw.push((oStart - gap) - baseEnd);
        raw.push((oEnd + gap) - baseStart);
    });
    var filtered = raw.filter(function(s) {
        return Number.isFinite(s) && Math.abs(s) > .5 && Math.abs(s) <= maxShift + .01;
    });
    var deduped = _dedupeSteps(filtered);
    deduped.sort(function(a, b) {
        var d = Math.abs(a) - Math.abs(b);
        return Math.abs(d) > .25 ? d : a - b;
    });
    return deduped;
}
function _perpendicularBlockersOnly(request, span, depth, inward, blockers, baseGap, width, height, insets, softness) {
    var rect = _contentRect(request, span, depth, inward, width, height, insets, 0);
    var edge = request.record.edge;
    var horizontal = edge === "top" || edge === "bottom";
    var hitAny = false;
    for (var i = 0; i < blockers.length; i++) {
        var other = blockers[i];
        var gap = _pairGap(request, other, baseGap, softness);
        if (rect.x < other.x + other.width + gap - 1e-4
                && rect.x + rect.width + gap > other.x + 1e-4
                && rect.y < other.y + other.height + gap - 1e-4
                && rect.y + rect.height + gap > other.y + 1e-4) {
            hitAny = true;
            if (!other.edge) return false;
            var otherH = other.edge === "top" || other.edge === "bottom";
            if (otherH === horizontal) return false;
        }
    }
    return hitAny;
}
function _withinPanelAxis(request, span, shift, width, height, insets) {
    var edge = request.record.edge;
    var reqInsets = _insetsFor(request, insets);
    var horizontal = edge === "top" || edge === "bottom";
    var first = horizontal ? reqInsets.left : reqInsets.top;
    var last = horizontal ? (width - reqInsets.right) : (height - reqInsets.bottom);
    var pad = _paddingFor(request);
    var along = (request.record.along + request.record.span / 2 + _number(shift, 0)) - span / 2;
    return along >= first + pad - .01 && along + span <= last - pad + .01;
}
function _tiers(request, span, depth, accepted, baseGap, width, height, insets, sameEdgeOnly, softness) {
    var base = _contentRect(request, span, depth, 0, width, height, insets, 0);
    var edge = request.record.edge;
    var horizontal = edge === "top" || edge === "bottom";
    var reverse = edge === "bottom" || edge === "right";
    var minimumInward = Math.max(0, _number(request.minimumInward, 0));
    var tiers = [minimumInward];
    if (request.allowInward === false) return tiers;
    accepted.forEach(function(other) {
        if (sameEdgeOnly && other.edge && other.edge !== edge)
            return;
        var gap = _pairGap(request, other, baseGap, softness);
        var baseAlongStart = horizontal ? base.x : base.y;
        var baseAlongEnd = baseAlongStart + (horizontal ? base.width : base.height);
        var otherAlongStart = horizontal ? other.x : other.y;
        var otherAlongEnd = otherAlongStart + (horizontal ? other.width : other.height);
        if (baseAlongStart >= otherAlongEnd + gap || baseAlongEnd + gap <= otherAlongStart)
            return;
        var baseCrossStart = horizontal ? base.y : base.x;
        var baseCrossEnd = baseCrossStart + (horizontal ? base.height : base.width);
        var otherCrossStart = horizontal ? other.y : other.x;
        var otherCrossEnd = otherCrossStart + (horizontal ? other.height : other.width);
        var tier = reverse
            ? baseCrossEnd - otherCrossStart + gap
            : otherCrossEnd - baseCrossStart + gap;
        if (tier > minimumInward) tiers.push(tier);
    });
    return tiers.filter(function(value, index, list) {
        return list.findIndex(function(other) { return Math.abs(other - value) < .5; }) === index;
    }).sort(function(a, b) { return a - b; });
}
function _pyramidDescriptor(request) {
    var record = request?.record;
    if (!record) return null;
    var horizontal = record.edge === "top" || record.edge === "bottom";
    var content = record.content || {};
    var start = horizontal
        ? _number(content.x, _number(record.along, 0))
        : _number(content.y, _number(record.along, 0));
    var extent = horizontal
        ? _number(content.width, _number(record.span, 0))
        : _number(content.height, _number(record.span, 0));
    extent = Math.max(0, extent);
    return {
        edge: String(record.edge || ""),
        tangentStart: start,
        tangentEnd: start + extent,
        proximity: Math.max(0, _number(request?.stackProximity, 24))
    };
}
function _pyramidDescriptorGap(a, b) {
    if (!a || !b || a.edge !== b.edge) return Infinity;
    if (a.tangentEnd < b.tangentStart)
        return b.tangentStart - a.tangentEnd;
    if (b.tangentEnd < a.tangentStart)
        return a.tangentStart - b.tangentEnd;
    return 0;
}
function _pyramidDescriptorsRelated(a,b) {
    if (!a || !b || a.edge !== b.edge) return false;
    return _pyramidDescriptorGap(a, b)
        <= Math.max(_number(a.proximity, 24), _number(b.proximity, 24));
}
function _samePyramidNeighborhood(a,b) {
    // Only same-intent Pyramid peers reorder by resting area (keeping Recording +
    // Notification Pyramid contour intact while explicit/pinned/typing surfaces
    // strictly outrank hover-only peers).
    return a?.stackPolicy === "pyramid"
        && b?.stackPolicy === "pyramid"
        && (a.intentWeight || 0) === (b.intentWeight || 0)
        && _pyramidDescriptorsRelated(
            _pyramidDescriptor(a), _pyramidDescriptor(b));
}
function _requestedArea(request) {
    var record = request?.record;
    if (!record) return 0;
    return Math.max(0, _number(record.span, 0))
        * Math.max(0, _number(record.targetDepth, record.depth || 0));
}
function _legacyCompare(a, b) {
    return (b.priority || 0) - (a.priority || 0)
        || (b.intentWeight || 0) - (a.intentWeight || 0)
        || (b.order || 0) - (a.order || 0)
        || String(a.id).localeCompare(String(b.id));
}
function _orderedRequests(requests) {
    var ordered = Array.from(requests || []).filter(function(request) {
        return request && request.open && request.record;
    }).sort(_legacyCompare);
    if (ordered.length < 2) return ordered;
    var parent = ordered.map(function(_, index) { return index; });
    function find(index) {
        while (parent[index] !== index) {
            parent[index] = parent[parent[index]];
            index = parent[index];
        }
        return index;
    }
    function join(first, second) {
        var a = find(first), b = find(second);
        if (a !== b) parent[b] = a;
    }
    for (var i = 0; i < ordered.length; i++) {
        for (var j = i + 1; j < ordered.length; j++) {
            if (_samePyramidNeighborhood(ordered[i], ordered[j]))
                join(i, j);
        }
    }
    var groups = {};
    for (var index = 0; index < ordered.length; index++) {
        var key = String(find(index));
        if (!groups[key]) groups[key] = [];
        groups[key].push(index);
    }
    Object.keys(groups).forEach(function(key) {
        var slots = groups[key];
        if (slots.length < 2) return;
        var members = slots.map(function(index) { return ordered[index]; });
        members.sort(function(a, b) {
            var intentDelta = (b.intentWeight || 0) - (a.intentWeight || 0);
            if (intentDelta !== 0) return intentDelta;
            var areaDelta = _requestedArea(b)-_requestedArea(a);
            return Math.abs(areaDelta) > .5 ? areaDelta : _legacyCompare(a, b);
        });
        for (var n = 0; n < slots.length; n++)
            ordered[slots[n]] = members[n];
    });
    return ordered;
}

function _normalizeExternalBlockers(externalBlockers) {
    if (!externalBlockers || typeof externalBlockers.length !== "number" || !externalBlockers.length) return [];
    var out = [];
    for (var i = 0; i < externalBlockers.length; i++) {
        var b = externalBlockers[i];
        if (!b || typeof b !== "object") continue;
        var w = Math.max(0, _number(b.width, 0));
        var h = Math.max(0, _number(b.height, 0));
        if (w <= 0 || h <= 0) continue;
        out.push({
            x: _number(b.x, 0),
            y: _number(b.y, 0),
            width: w,
            height: h,
            edge: String(b.edge || ""),
            priority: _number(b.priority, 1),
            intentWeight: _number(b.intentWeight, 0),
            isExternal: true
        });
    }
    return out;
}

function _activeExternalBlockersFor(request, extBlockers) {
    if (!extBlockers || !extBlockers.length) return [];
    var reqPrio = _number(request && request.priority, 0);
    var reqIntent = _number(request && request.intentWeight, 0);
    return extBlockers.filter(function(b) {
        return b.priority > reqPrio || (b.priority === reqPrio && b.intentWeight >= reqIntent);
    });
}

// Pre-pass cooperative shrinking (A1): when an open heavy overlay (`cooperativeShrink: true`)
// collides laterally with one or two perpendicular sidebars (`cooperativePeer: true`),
// cooperatively size both within their readable minimums so they coexist cleanly instead of
// crushing sidebars or prematurely evicting.
function _negotiateCooperative(ordered, width, height, insets, gap, extBlockers, softness) {
    var empty = { overlayId: "", entries: {} };
    var overrides = {};
    var overlay = ordered.find(function(r) { return r.cooperativeShrink === true; });
    if (!overlay || !overlay.record) return empty;

    var ovEdge = overlay.record.edge;
    var ovInsets = _insetsFor(overlay, insets);
    var ovHorizontal = ovEdge === "top" || ovEdge === "bottom";
    var startEdge = ovHorizontal ? "left" : "top";
    var endEdge = ovHorizontal ? "right" : "bottom";
    var ovMinInward = Math.max(0, _number(overlay.minimumInward, 0));
    var ovFullSpan = Math.max(0, _number(overlay.record.span, 0));
    var ovFullDepth = Math.max(0, _number(overlay.record.targetDepth, overlay.record.depth || 0));
    var ovMinSpan = Math.max(0, Math.min(ovFullSpan, _number(overlay.minSpan, ovFullSpan)));
    var ovPad = _paddingFor(overlay);
    var ovBase = _contentRect(overlay, ovFullSpan, ovFullDepth, ovMinInward, width, height, ovInsets, 0);

    var peers = ordered.filter(function(r) {
        if (r.id === overlay.id || r.cooperativePeer !== true || !r.record) return false;
        var pe = r.record.edge;
        if (pe !== startEdge && pe !== endEdge) return false;
        var pDepth = Math.max(0, _number(r.record.targetDepth, r.record.depth || 0));
        var pMinDepth = Math.max(0, Math.min(pDepth, _number(r.minDepth, pDepth)));
        var pSpan = Math.max(0, _number(r.record.span, 0));
        var pInward = Math.max(0, _number(r.minimumInward, 0));
        var pRect = _contentRect(r, pSpan, pDepth, pInward, width, height, insets, 0);
        // Skip peers already blocked at their minimum size by a higher-or-equal external blocker
        var peerExt = _activeExternalBlockersFor(r, extBlockers);
        if (peerExt.length) {
            var pMinRect = _contentRect(r, pSpan, pMinDepth, pInward, width, height, insets, 0);
            if (_collides(pMinRect, peerExt, gap, r, softness)) return false;
        }
        // Only negotiate if the peer actually overlaps the overlay on the overlay's depth axis
        var ovCross0 = ovHorizontal ? ovBase.y : ovBase.x;
        var ovCross1 = ovCross0 + (ovHorizontal ? ovBase.height : ovBase.width);
        var pCross0 = ovHorizontal ? pRect.y : pRect.x;
        var pCross1 = pCross0 + (ovHorizontal ? pRect.height : pRect.width);
        return pCross0 < ovCross1 + gap && pCross1 + gap > ovCross0;
    });
    if (!peers.length) return empty;

    // Pick at most one start-side peer and one end-side peer (highest priority/order first)
    var startPeer = peers.find(function(r) { return r.record.edge === startEdge; }) || null;
    var endPeer = peers.find(function(r) { return r.record.edge === endEdge; }) || null;

    var boundStart = ovHorizontal ? ovInsets.left : ovInsets.top;
    var boundEnd = ovHorizontal ? (width - ovInsets.right) : (height - ovInsets.bottom);
    var usableAxis = Math.max(0, boundEnd - boundStart);

    function solveSet(sp, ep) {
        var spPad = sp ? _paddingFor(sp) : 0;
        var epPad = ep ? _paddingFor(ep) : 0;
        var spInward = sp ? Math.max(0, _number(sp.minimumInward, 0)) : 0;
        var epInward = ep ? Math.max(0, _number(ep.minimumInward, 0)) : 0;
        var spFull = sp ? Math.max(0, _number(sp.record.targetDepth, sp.record.depth || 0)) : 0;
        var spMin = sp ? Math.max(0, Math.min(spFull, _number(sp.minDepth, spFull))) : 0;
        var epFull = ep ? Math.max(0, _number(ep.record.targetDepth, ep.record.depth || 0)) : 0;
        var epMin = ep ? Math.max(0, Math.min(epFull, _number(ep.minDepth, epFull))) : 0;

        // Exact content-axis budget (including any minimumInward offsets on peers):
        // startOccupied = sp ? (spInward + spDepth - spPad + gap) : ovPad
        // endOccupied   = ep ? (epInward + epDepth - epPad + gap) : ovPad
        // ovContentW    = ovSpan - 2 * ovPad
        // Total needed  = startOccupied + (ovSpan - 2*ovPad) + endOccupied <= usableAxis
        var fixedOverhead = (sp ? (spInward - spPad + gap) : ovPad)
            + (ep ? (epInward - epPad + gap) : ovPad) - 2 * ovPad;
        var minTotal = spMin + ovMinSpan + epMin + fixedOverhead;
        if (minTotal > usableAxis + .01) return null;

        var wantTotal = spFull + ovFullSpan + epFull + fixedOverhead;
        var allocStart = spFull, allocOv = ovFullSpan, allocEnd = epFull;
        if (wantTotal > usableAxis + .01) {
            var extra = Math.max(0, usableAxis - minTotal);
            var hStart = Math.max(0, spFull - spMin);
            var hOv = Math.max(0, ovFullSpan - ovMinSpan);
            var hEnd = Math.max(0, epFull - epMin);
            // Weight overlay headroom 1.35x so heavy overlays keep generous room while
            // sidebars stay comfortably above their readable minimums.
            var wStart = hStart, wOv = hOv * 1.35, wEnd = hEnd;
            var wSum = wStart + wOv + wEnd;
            allocStart = spMin;
            allocOv = ovMinSpan;
            allocEnd = epMin;
            if (wSum > 0 && extra > 0) {
                var addStart = Math.min(hStart, extra * (wStart / wSum));
                var addOv = Math.min(hOv, extra * (wOv / wSum));
                var addEnd = Math.min(hEnd, extra * (wEnd / wSum));
                allocStart += addStart;
                allocOv += addOv;
                allocEnd += addEnd;
                // Second pass distributes any capped remainder cleanly
                var leftover = Math.max(0, extra - (addStart + addOv + addEnd));
                if (leftover > .5) {
                    var remStart = Math.max(0, spFull - allocStart);
                    var remOv = Math.max(0, ovFullSpan - allocOv);
                    var remEnd = Math.max(0, epFull - allocEnd);
                    var remSum = remStart + remOv + remEnd;
                    if (remSum > 0) {
                        allocStart += Math.min(remStart, leftover * (remStart / remSum));
                        allocOv += Math.min(remOv, leftover * (remOv / remSum));
                        allocEnd += Math.min(remEnd, leftover * (remEnd / remSum));
                    }
                }
            }
            allocStart = sp ? Math.floor(allocStart) : 0;
            allocEnd = ep ? Math.floor(allocEnd) : 0;
            allocOv = Math.min(ovFullSpan, Math.max(ovMinSpan, Math.floor(usableAxis - fixedOverhead - allocStart - allocEnd)));
        }

        // Compute exact safe tangent slot [slotMinAlong .. slotMaxAlong] for overlay
        var slotContentLeft = boundStart + (sp ? (spInward + allocStart - spPad + gap) : ovPad);
        var slotContentRight = boundEnd - (ep ? (epInward + allocEnd - epPad + gap) : ovPad);
        var ovContentW = Math.max(0, allocOv - 2 * ovPad);
        var minAlong = slotContentLeft - ovPad;
        var maxAlong = Math.max(minAlong, (slotContentRight - ovContentW) - ovPad);
        var idealAlong = (overlay.record.along + ovFullSpan / 2) - allocOv / 2;
        var chosenAlong = Math.max(minAlong, Math.min(maxAlong, idealAlong));

        return {
            sp: sp, ep: ep,
            allocStart: allocStart, allocEnd: allocEnd,
            allocOv: allocOv, chosenAlong: chosenAlong
        };
    }

    var solution = solveSet(startPeer, endPeer);
    if (!solution && startPeer && endPeer) {
        // Both sidebars cannot coexist with the overlay at readable minimums.
        // Prefer the higher-priority (or more recently opened) sidebar; the other falls through to eviction.
        var keepStartFirst = _legacyCompare(startPeer, endPeer) <= 0;
        solution = keepStartFirst
            ? (solveSet(startPeer, null) || solveSet(null, endPeer))
            : (solveSet(null, endPeer) || solveSet(startPeer, null));
    }
    if (!solution) return empty;

    // Only apply overrides if at least one body actually needed adaptation (collision exists at full sizes)
    var needAdaptation = false;
    var checkPeers = [solution.sp, solution.ep].filter(Boolean);
    for (var i = 0; i < checkPeers.length; i++) {
        var p = checkPeers[i];
        var pr = _contentRect(p, _number(p.record.span, 0), _number(p.record.targetDepth, p.record.depth || 0),
            Math.max(0, _number(p.minimumInward, 0)), width, height, insets, 0);
        if (_collides(ovBase, [pr], gap)) {
            needAdaptation = true;
            break;
        }
    }
    if (!needAdaptation) return empty;

    var ovShift = (solution.chosenAlong + solution.allocOv / 2) - (overlay.record.along + ovFullSpan / 2);
    var ovRect = _contentRect(overlay, solution.allocOv, ovFullDepth, ovMinInward, width, height, insets, ovShift);
    if (!_within(ovRect, width, height, insets, overlay) || !_withinOpposite(ovRect, overlay, ovFullDepth, width, height, insets))
        return empty;

    overrides[overlay.id] = {
        visible: true,
        evicted: false,
        along: solution.chosenAlong,
        inward: ovMinInward,
        span: solution.allocOv,
        depth: ovFullDepth,
        shrunk: solution.allocOv < ovFullSpan - .5,
        cooperativeShrunk: solution.allocOv < ovFullSpan - .5,
        lateralShift: Math.abs(ovShift) > .5 ? ovShift : 0,
        content: ovRect
    };

    if (solution.sp) {
        var spSpan = Math.max(0, _number(solution.sp.record.span, 0));
        var spInward = Math.max(0, _number(solution.sp.minimumInward, 0));
        var spFullD = Math.max(0, _number(solution.sp.record.targetDepth, solution.sp.record.depth || 0));
        var spRect = _contentRect(solution.sp, spSpan, solution.allocStart, spInward, width, height, insets, 0);
        if (_within(spRect, width, height, insets, solution.sp)) {
            overrides[solution.sp.id] = {
                visible: true,
                evicted: false,
                along: solution.sp.record.along,
                inward: spInward,
                span: spSpan,
                depth: solution.allocStart,
                shrunk: solution.allocStart < spFullD - .5,
                cooperativeShrunk: solution.allocStart < spFullD - .5,
                lateralShift: 0,
                content: spRect
            };
        }
    }
    if (solution.ep) {
        var epSpan = Math.max(0, _number(solution.ep.record.span, 0));
        var epInward = Math.max(0, _number(solution.ep.minimumInward, 0));
        var epFullD = Math.max(0, _number(solution.ep.record.targetDepth, solution.ep.record.depth || 0));
        var epRect = _contentRect(solution.ep, epSpan, solution.allocEnd, epInward, width, height, insets, 0);
        if (_within(epRect, width, height, insets, solution.ep)) {
            overrides[solution.ep.id] = {
                visible: true,
                evicted: false,
                along: solution.ep.record.along,
                inward: epInward,
                span: epSpan,
                depth: solution.allocEnd,
                shrunk: solution.allocEnd < epFullD - .5,
                cooperativeShrunk: solution.allocEnd < epFullD - .5,
                lateralShift: 0,
                content: epRect
            };
        }
    }
    return { overlayId: overlay.id, entries: overrides };
}

function arrange(requests, width, height, insets, gap, externalBlockers, softness) {
    gap = gap === undefined ? 24 : Math.max(0, gap);
    softness = softness === undefined ? gap : Math.max(0, _number(softness, gap));
    var result = {}, accepted = [];
    var ordered = _orderedRequests(requests);
    var extBlockers = _normalizeExternalBlockers(externalBlockers);
    var coopState = _negotiateCooperative(ordered, width, height, insets, gap, extBlockers, softness);
    var cooperativeOverrides = coopState.entries;
    var coopOverlayAccepted = false;

    function blockersFor(request) {
        var activeExt = _activeExternalBlockersFor(request, extBlockers);
        return activeExt.length ? accepted.concat(activeExt) : accepted;
    }

    function acceptPlacement(request, span, depth, inward, shift, fullSpan, fullDepth, rect) {
        var anchorCenter = request.record.along + request.record.span / 2 + shift;
        accepted.push({
            x: rect.x, y: rect.y, width: rect.width, height: rect.height,
            edge: request.record.edge,
            padding: _paddingFor(request),
            isModal: request.intent === "modal"
        });
        return {
            visible: true,
            evicted: false,
            along: anchorCenter - span / 2,
            inward: inward,
            span: span,
            depth: depth,
            shrunk: span < fullSpan - .5 || depth < fullDepth - .5,
            lateralShift: Math.abs(shift) > .5 ? shift : 0,
            content: rect
        };
    }

    ordered.forEach(function(request) {
        var record = request.record;
        var fullSpan = Math.max(0, _number(record.span, 0));
        var fullDepth = Math.max(0, _number(record.targetDepth, record.depth || 0));
        var minSpan = Math.max(0, Math.min(fullSpan, _number(request.minSpan, fullSpan)));
        var minDepth = Math.max(0, Math.min(fullDepth, _number(request.minDepth, fullDepth)));
        var minimumInward = Math.max(0, _number(request.minimumInward, 0));
        var maxShift = _maxLateralShift(request, fullSpan);
        var blockers = blockersFor(request);
        var placement = null;

        // 0. Cooperative pre-negotiated slot (peers only accept if the overlay's cooperative slot succeeded)
        var coopAllowed = request.id === coopState.overlayId || coopOverlayAccepted;
        var coop = coopAllowed ? cooperativeOverrides[request.id] : null;
        if (coop && coop.content && _within(coop.content, width, height, insets, request)
                && _withinOpposite(coop.content, request, coop.depth, width, height, insets)
                && !_collides(coop.content, blockers, gap, request, softness)) {
            placement = coop;
            if (request.id === coopState.overlayId)
                coopOverlayAccepted = true;
            accepted.push({
                x: coop.content.x, y: coop.content.y,
                width: coop.content.width, height: coop.content.height,
                edge: record.edge,
                padding: _paddingFor(request),
                isModal: request.intent === "modal"
            });
        }

        // 1. Exact requested anchor at full size
        if (!placement) {
            var baseRect = _contentRect(request, fullSpan, fullDepth, minimumInward, width, height, insets, 0);
            if (_within(baseRect, width, height, insets, request)
                    && _withinOpposite(baseRect, request, fullDepth, width, height, insets)
                    && !_collides(baseRect, blockers, gap, request, softness)) {
                placement = acceptPlacement(request, fullSpan, fullDepth, minimumInward, 0, fullSpan, fullDepth, baseRect);
            }
        }

        // 2. Bounded tangential lateral shift along the same Screen Edge at full size (A2 #1)
        if (!placement && maxShift > .5) {
            var fullShifts = _lateralShifts(request, fullSpan, fullDepth, minimumInward, blockers, gap, width, height, insets, maxShift, softness);
            for (var fs = 0; fs < fullShifts.length && !placement; fs++) {
                var shiftedRect = _contentRect(request, fullSpan, fullDepth, minimumInward, width, height, insets, fullShifts[fs]);
                if (_within(shiftedRect, width, height, insets, request)
                        && _withinOpposite(shiftedRect, request, fullDepth, width, height, insets)
                        && !_collides(shiftedRect, blockers, gap, request, softness)) {
                    placement = acceptPlacement(request, fullSpan, fullDepth, minimumInward, fullShifts[fs], fullSpan, fullDepth, shiftedRect);
                }
            }
        }

        // 3 & 4. Shrink / Reflow & Pyramid Inward Stacking (same-edge tiers first, then cross-edge)
        if (!placement) {
            var fit = _blockerFitSteps(request, fullSpan, fullDepth, minSpan, minDepth, blockers, gap, width, height, insets, softness);
            var sizes = _candidateSizes(fullSpan, fullDepth, minSpan, minDepth, fit.spans, fit.depths, request.preserveAspect === true);
            var passes = [true, false];
            for (var p = 0; p < passes.length && !placement; p++) {
                // Before cross-edge inward stacking, allow perpendicular-shift opted-in
                // bodies (e.g. Sidebars blocked only by a perpendicular top/bottom popup)
                // to slide cleanly along their own Screen Edge at inward = minimumInward.
                if (p === 1 && !placement && request.allowPerpendicularShift === true
                        && _perpendicularBlockersOnly(request, fullSpan, fullDepth, minimumInward, blockers, gap, width, height, insets, softness)) {
                    var perpH = record.edge === "top" || record.edge === "bottom";
                    var perpMaxShift = Math.max(240, (perpH ? width : height) * 0.45);
                    for (var ps = 0; ps < sizes.length && !placement; ps++) {
                        var pSize = sizes[ps];
                        var pShifts = _lateralShifts(request, pSize.span, pSize.depth, minimumInward, blockers, gap, width, height, insets, perpMaxShift, softness);
                        for (var psi = 0; psi < pShifts.length && !placement; psi++) {
                            var pRect = _contentRect(request, pSize.span, pSize.depth, minimumInward, width, height, insets, pShifts[psi]);
                            if (_within(pRect, width, height, insets, request)
                                    && _withinPanelAxis(request, pSize.span, pShifts[psi], width, height, insets)
                                    && _withinOpposite(pRect, request, pSize.depth, width, height, insets)
                                    && !_collides(pRect, blockers, gap, request, softness)) {
                                placement = acceptPlacement(request, pSize.span, pSize.depth, minimumInward, pShifts[psi], fullSpan, fullDepth, pRect);
                                break;
                            }
                        }
                    }
                    if (placement) break;
                }
                for (var s = 0; s < sizes.length && !placement; s++) {
                    var size = sizes[s];
                    var tiers = _tiers(request, size.span, size.depth, blockers, gap, width, height, insets, passes[p], softness);
                    for (var t = 0; t < tiers.length && !placement; t++) {
                        var tier = tiers[t];
                        var rect = _contentRect(request, size.span, size.depth, tier, width, height, insets, 0);
                        if (_within(rect, width, height, insets, request)
                                && _withinOpposite(rect, request, size.depth, width, height, insets)
                                && !_collides(rect, blockers, gap, request, softness)) {
                            placement = acceptPlacement(request, size.span, size.depth, tier, 0, fullSpan, fullDepth, rect);
                            break;
                        }
                        if (maxShift > .5) {
                            var subShifts = _lateralShifts(request, size.span, size.depth, tier, blockers, gap, width, height, insets, maxShift, softness);
                            for (var ss = 0; ss < subShifts.length && !placement; ss++) {
                                var subRect = _contentRect(request, size.span, size.depth, tier, width, height, insets, subShifts[ss]);
                                if (_within(subRect, width, height, insets, request)
                                        && _withinOpposite(subRect, request, size.depth, width, height, insets)
                                        && !_collides(subRect, blockers, gap, request, softness)) {
                                    placement = acceptPlacement(request, size.span, size.depth, tier, subShifts[ss], fullSpan, fullDepth, subRect);
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        result[request.id] = placement || {
            visible: false,
            evicted: true,
            along: record.along,
            inward: 0,
            span: fullSpan,
            depth: fullDepth,
            shrunk: false,
            lateralShift: 0
        };
    });
    return result;
}
