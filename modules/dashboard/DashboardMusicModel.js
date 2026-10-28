.pragma library

const _trackMeta = new WeakMap()
const _libraryCache = new WeakMap()

function _foldSearch(value) {
    const lower = String(value ?? "").toLowerCase()
    try {
        return lower.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/đ/g, "d")
    } catch (_e) {
        return lower
    }
}

function folder(value) {
    return String(value ?? "").replace(/^\/+|\/+$/g, "")
}

function _computeTrackFolder(track) {
    if (track?.folder !== undefined) return folder(track.folder)
    const uri = String(track?.uri ?? "")
    return folder(uri.substring(0, Math.max(0, uri.lastIndexOf("/"))))
}

function _computeLabels(track) {
    const raw = Array.isArray(track?.genre) ? track.genre : [track?.genre ?? ""]
    const values = new Set()
    for (const value of raw) for (const token of String(value).split(";")) {
        const label = token.trim()
        if (label.length > 0) values.add(label)
    }
    return values.size > 0 ? Array.from(values) : [""]
}

function _meta(track) {
    if (!track || typeof track !== "object") return null
    let cached = _trackMeta.get(track)
    if (cached !== undefined) return cached
    const uri = String(track.uri ?? track.path ?? "")
    const name = String(track.title || track.uri || "")
    const parentFolder = _computeTrackFolder(track)
    const trackLabels = _computeLabels(track)
    const searchRaw = [track.title, track.artist, track.album, track.folder]
        .map(value => String(value ?? "").toLowerCase())
        .join(" ")
    const searchFolded = _foldSearch(searchRaw)
    cached = {
        uri,
        name,
        folder: parentFolder,
        labels: trackLabels,
        searchRaw,
        searchFolded
    }
    _trackMeta.set(track, cached)
    return cached
}

function _lib(tracks) {
    if (!Array.isArray(tracks)) return null
    let cached = _libraryCache.get(tracks)
    if (cached !== undefined) return cached
    cached = {
        genres: null,
        roots: null,
        contents: new Map()
    }
    _libraryCache.set(tracks, cached)
    return cached
}

function trackFolder(track) {
    const meta = _meta(track)
    return meta ? meta.folder : _computeTrackFolder(track)
}

function labels(track) {
    const meta = _meta(track)
    return meta ? meta.labels : _computeLabels(track)
}

function genres(tracks) {
    const lib = _lib(tracks)
    if (lib && lib.genres) return lib.genres
    const values = new Map()
    for (const track of tracks ?? []) {
        if (!track) continue
        for (const label of labels(track)) values.set(label, (values.get(label) ?? 0) + 1)
    }
    const result = Array.from(values, ([key, count]) => ({key, count}))
        .sort((a, b) => a.key.localeCompare(b.key))
    if (lib) lib.genres = result
    return result
}

function contents(tracks, path) {
    const current = folder(path), prefix = current ? current + "/" : ""
    const lib = _lib(tracks)
    if (lib && lib.contents.has(current)) return lib.contents.get(current)
    const children = new Map(), files = []
    for (const track of tracks ?? []) {
        if (!track) continue
        const meta = _meta(track)
        const parent = meta ? meta.folder : trackFolder(track)
        if (parent === current) {
            files.push({kind: "track", track, name: meta ? meta.name : String(track.title || track.uri || "")})
            continue
        }
        if (current && !parent.startsWith(prefix)) continue
        const rest = parent.substring(prefix.length), slash = rest.indexOf("/")
        const name = slash >= 0 ? rest.substring(0, slash) : rest
        if (!name) continue
        const child = prefix + name
        let folderEntry = children.get(child)
        if (!folderEntry) {
            folderEntry = {kind: "folder", name, path: child, count: 0}
            children.set(child, folderEntry)
        }
        folderEntry.count++
    }
    const result = Array.from(children.values()).sort((a, b) => a.name.localeCompare(b.name)).concat(files)
    if (lib) lib.contents.set(current, result)
    return result
}

function roots(tracks) {
    const lib = _lib(tracks)
    if (lib && lib.roots) return lib.roots
    const entries = contents(tracks, "")
    const directories = []
    let rootTrackCount = 0
    for (const entry of entries) {
        if (entry.kind === "folder") directories.push(entry)
        else if (entry.kind === "track") rootTrackCount++
    }
    if (rootTrackCount > 0)
        directories.unshift({kind: "folder", name: "Music library", path: "", count: rootTrackCount})
    if (lib) lib.roots = directories
    return directories
}

function results(tracks, mode, genre, path) {
    if (mode === "genre") {
        const selected = new Set(Array.isArray(genre) ? genre : [genre])
        if (selected.size === 0) return []
        const out = []
        for (const track of tracks ?? []) {
            if (!track) continue
            const meta = _meta(track)
            const trackLabels = meta ? meta.labels : labels(track)
            if (trackLabels.some(label => selected.has(label)))
                out.push({kind: "track", track, name: meta ? meta.name : String(track.title || track.uri || "")})
        }
        return out
    }
    if (mode !== "folder") return []
    if (!Array.isArray(path)) return contents(tracks, path)
    if (path.length === 0) return []
    if (path.length === 1) return contents(tracks, path[0])
    const entries = new Map()
    for (const current of path) for (const entry of contents(tracks, current)) {
        const entryKey = key(entry)
        if (!entries.has(entryKey)) entries.set(entryKey, entry)
    }
    return Array.from(entries.values())
}

function parent(path) {
    const value = folder(path)
    return value.substring(0, Math.max(0, value.lastIndexOf("/")))
}

function matching(tracks, query) {
    const text = String(query ?? "").trim().toLowerCase()
    if (!text) return tracks ?? []
    const folded = _foldSearch(text)
    return (tracks ?? []).filter(track => {
        if (!track) return false
        const meta = _meta(track)
        if (!meta) return false
        return meta.searchRaw.includes(text) || (folded.length > 0 && meta.searchFolded.includes(folded))
    })
}

function key(entry) {
    return entry.kind === "folder" ? "d:"+entry.path : "t:"+String(entry.track?.uri ?? entry.track?.path ?? "")
}

function select(entries, selected, anchor, index, control, shift) {
    const entry=entries[index]
    if (!entry) return {keys:selected,anchor}
    if (shift && anchor>=0) {
        const keys=new Set(control ? selected : [])
        for (const value of entries.slice(Math.min(anchor,index),Math.max(anchor,index)+1)) keys.add(key(value))
        return {keys:Array.from(keys),anchor}
    }
    const keys=new Set(control ? selected : []), value=key(entry)
    if(control && keys.has(value)) keys.delete(value)
    else keys.add(value)
    return {keys:Array.from(keys),anchor:index}
}

// Genre names and folder paths include the empty string (unknown/root).
function selectValues(values, selected, anchor, index, control, shift) {
    if (index < 0 || index >= values.length) return {keys:selected, anchor}
    if (shift && anchor >= 0 && anchor < values.length) {
        const keys = new Set(control ? selected : [])
        for (const value of values.slice(Math.min(anchor,index), Math.max(anchor,index)+1)) keys.add(value)
        return {keys:Array.from(keys), anchor}
    }
    const keys = new Set(control ? selected : []), value = values[index]
    if (control && keys.has(value)) keys.delete(value)
    else keys.add(value)
    return {keys:Array.from(keys), anchor:index}
}

function _folderMatches(path, folderSet) {
    if (folderSet.size === 0) return false
    if (folderSet.has(path)) return true
    let idx = path.indexOf("/")
    while (idx > 0) {
        if (folderSet.has(path.substring(0, idx))) return true
        idx = path.indexOf("/", idx + 1)
    }
    return false
}

function selectedTracks(tracks, keys) {
    if (!keys || keys.length === 0 || !tracks || tracks.length === 0) return []
    const selected = new Set(keys)
    const folderSet = new Set()
    for (const value of keys) {
        if (typeof value === "string" && value.startsWith("d:"))
            folderSet.add(value.substring(2))
    }
    const seen = new Set()
    return (tracks ?? []).filter(track => {
        if (!track) return false
        const meta = _meta(track)
        const uri = meta ? meta.uri : String(track.uri ?? track.path ?? "")
        if (seen.has(uri)) return false
        const path = meta ? meta.folder : trackFolder(track)
        if (!(selected.has("t:" + uri) || _folderMatches(path, folderSet))) return false
        seen.add(uri)
        return true
    })
}
