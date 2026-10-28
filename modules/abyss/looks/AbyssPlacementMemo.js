.pragma library

// Allocation results contain plain data, not QObjects or observable getters.
// Preserve the original record reference while all fields are exactly equal.
// The plain JS cache belongs to the host. No module registry retains destroyed
// hosts, and no QObject wrappers become weak-map keys in the native Qt engine.
function equal(a,b) {
    if (Object.is(a,b)) return true;
    if (a===null || b===null || typeof a!=="object" || typeof b!=="object") return false;
    if (a.along!==b.along || a.inward!==b.inward || a.span!==b.span || a.depth!==b.depth
            || a.visible!==b.visible || a.evicted!==b.evicted || a.shrunk!==b.shrunk
            || a.x!==b.x || a.y!==b.y || a.width!==b.width || a.height!==b.height)
        return false;
    if (Array.isArray(a)!==Array.isArray(b)) return false;
    var keys=Object.keys(a),other=Object.keys(b);
    if (keys.length!==other.length) return false;
    for (var i=0;i<keys.length;i++) {
        var key=keys[i];
        if (!Object.prototype.hasOwnProperty.call(b,key) || !equal(a[key],b[key])) return false;
    }
    return true;
}
function stable(cache,record) {
    var previous=cache.record;
    if (previous!==undefined && equal(previous,record)) return previous;
    cache.record=record;
    return record;
}
