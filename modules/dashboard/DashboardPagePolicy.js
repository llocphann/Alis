// Stable page identity/order and one horizontal navigation per gesture burst.
// Numeric legacy selections are confined to this compatibility map.
var defaultOrder = ["dashboard", "music", "weeklyPlanner"];

function normalized(raw) {
    var result=[];
    (typeof raw==="string" ? [] : Array.from(raw || [])).concat(defaultOrder).forEach(function(id) {
        if (typeof id==="string" && id.length && result.indexOf(id)<0) result.push(id);
    });
    return result;
}

// Only substitute visible slots. Hidden and future pages retain their stored
// positions and identity when a currently available page moves around them.
function move(raw, available, id, target) {
    var result=normalized(raw), visible=ordered(result,available), from=visible.indexOf(id);
    if (from<0 || !Number.isFinite(target)) return result;
    target=Math.max(0,Math.min(visible.length-1,Math.round(target)));
    visible.splice(from,1);visible.splice(target,0,id);
    var index=0;
    return result.map(function(page) {return available.indexOf(page)>=0 ? visible[index++] : page;});
}

function ordered(raw, available) {
    var result = [];
    Array.from(raw || []).concat(available).forEach(function(id) {
        if (available.indexOf(id) >= 0 && result.indexOf(id) < 0) result.push(id);
    });
    return result;
}

function idle() {
    return {direction:0, distance:0, fired:false, phased:false, last:0};
}

function delta(event) {
    var pixel = event.pixelDelta || {};
    if (pixel.x || pixel.y) return {x:Number(pixel.x) || 0, y:Number(pixel.y) || 0};
    var angle = event.angleDelta || {};
    return {x:(Number(angle.x) || 0)/3, y:(Number(angle.y) || 0)/3};
}

// phase follows Qt::ScrollPhase: none=0, begin=1, update=2, end=3, momentum=4.
function advance(previous, movement, phase, now, ids, currentId, contentConsumed) {
    var state = Object.assign({}, previous);
    if (phase === 3) return {state:idle(), accepted:false, target:""};
    if (phase === 1 || (!phase && state.phased)
            || (!state.phased && state.last && now-state.last > 180)) state = idle();
    if (phase) state.phased = true;
    state.last = now;
    var x = movement.x, y = movement.y;
    if (!Number.isFinite(x) || !Number.isFinite(y) || !x || Math.abs(x) <= Math.abs(y)) {
        state.distance = 0;
        return {state:state, accepted:false, target:""};
    }
    var direction = x < 0 ? 1 : -1;
    if (direction !== state.direction) {
        state.direction = direction;
        state.distance = 0;
        state.fired = false;
    }
    // An inner horizontal browser owns this burst even after reaching its edge.
    // Keep that latch across header/body handoff; a new burst or reversal releases it.
    if (contentConsumed) {
        state.fired = true;
        return {state:state, accepted:true, target:""};
    }
    var at = ids.indexOf(currentId), next = at+direction;
    if (at < 0 || next < 0 || next >= ids.length)
        return {state:state, accepted:false, target:""};
    if (state.fired) return {state:state, accepted:true, target:""};
    state.distance += Math.abs(x);
    if (state.distance < 32) return {state:state, accepted:true, target:""};
    state.fired = true;
    return {state:state, accepted:true, target:ids[next]};
}
