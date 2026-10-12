// Transient editor-only selection. No Config writes; no QML object references.
// Modifier flags are booleans so both Qt inputs and pure JS fixtures can use it.
function select(ids, primary, anchor, id, ordered, ctrl, shift) {
    if (!ordered.includes(id))
        return {ids:ids.slice(),primary:primary,anchor:anchor}
    const valid = ids.filter(value => ordered.includes(value))
    const oldAnchor = ordered.includes(anchor) ? anchor
                    : ordered.includes(primary) ? primary : id
    if (shift) {
        const first = ordered.indexOf(oldAnchor)
        const last = ordered.indexOf(id)
        const slice = ordered.slice(Math.min(first,last),Math.max(first,last)+1)
        const result = ctrl ? [...new Set([...valid,...slice])] : slice
        return {ids:result,primary:id,anchor:oldAnchor}
    }
    if (ctrl) {
        const result = valid.includes(id) ? valid.filter(value=>value!==id)
                     : valid.concat([id])
        return {ids:result,primary:result.includes(id) ? id : result[result.length-1] || "",
                anchor:result.includes(id) ? id : result[result.length-1] || ""}
    }
    return {ids:[id],primary:id,anchor:id}
}

// Keep a selected group intact on pointer press; the normal click only
// collapses it on release when no drag happened.
function deferCollapseOnPress(ids, id, ctrl, shift) {
    return !ctrl && !shift && ids.length > 1 && ids.includes(id)
}

function orderedIds(draft) {
    const edgeOrder={top:0,right:1,bottom:2,left:3}
    return draft.filter(value=>!!value && typeof value.id === "string")
        .slice().sort((a,b)=> {
            const x=(edgeOrder[a.edge] ?? 4)-(edgeOrder[b.edge] ?? 4)
            return x || (Number(a.position ?? 0)-Number(b.position ?? 0))
                || a.id.localeCompare(b.id)
        }).map(value=>value.id)
}
