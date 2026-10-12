.pragma library

// Allocation results contain plain data, not QObjects or observable getters.
// Preserve the original record reference while all fields are exactly equal.
// Use primitive tokens; the host releases its entry on cold remount/destruction.
// QObject wrappers must not become weak-map keys in the native Qt engine.
var placements = new Map();
var nextToken = 0;
function token() { return ++nextToken; }
function release(key) { placements.delete(key); }
function equal(a,b) {
    if (Object.is(a,b)) return true;
    if (a===null || b===null || typeof a!=="object" || typeof b!=="object") return false;
    if (Array.isArray(a)!==Array.isArray(b)) return false;
    var keys=Object.keys(a),other=Object.keys(b);
    if (keys.length!==other.length) return false;
    for (var i=0;i<keys.length;i++) {
        var key=keys[i];
        if (!Object.prototype.hasOwnProperty.call(b,key) || !equal(a[key],b[key])) return false;
    }
    return true;
}
function stable(key,record) {
    var previous=placements.get(key);
    if (previous!==undefined && equal(previous,record)) return previous;
    placements.set(key,record);
    return record;
}
