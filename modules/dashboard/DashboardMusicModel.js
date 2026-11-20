.pragma library

// The widget owns one index per immutable source. Replacing the source releases
// its metadata, folder listings and search results together.
function createIndex(tracks) {
    return {
        tracks: tracks ?? [],
        byUri: Object.create(null),
        genres: null,
        roots: null,
        albums: null,
        artists: null,
        contents: new Map(),
        lastQuery: "",
        lastMatches: []
    }
}

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

function _meta(track, index) {
    if (!track || typeof track !== "object") return null
    const uri = String(track.uri ?? track.path ?? "")
    const cached = index?.byUri[uri]
    if (cached && cached.track === track) return cached
    const name = String(track.title || track.uri || "")
    const parentFolder = _computeTrackFolder(track)
    const trackLabels = _computeLabels(track)
    const meta = {
        track,
        uri,
        name,
        folder: parentFolder,
        labels: trackLabels,
        searchRaw: null,
        searchFolded: null
    }
    if (index) index.byUri[uri] = meta
    return meta
}

function trackFolder(track) {
    return _computeTrackFolder(track)
}

function labels(track) {
    return _computeLabels(track)
}

function genres(tracks, index) {
    const lib = index && index.tracks === tracks ? index : null
    if (lib && lib.genres) return lib.genres
    const values = new Map()
    for (const track of tracks ?? []) {
        if (!track) continue
        for (const label of (_meta(track, index)?.labels ?? labels(track))) values.set(label, (values.get(label) ?? 0) + 1)
    }
    const result = Array.from(values, ([key, count]) => ({key, count}))
        .sort((a, b) => a.key.localeCompare(b.key))
    if (lib) lib.genres = result
    return result
}

function contents(tracks, path, index) {
    const current = folder(path), prefix = current ? current + "/" : ""
    const lib = index && index.tracks === tracks ? index : null
    if (lib && lib.contents.has(current)) return lib.contents.get(current)
    const children = new Map(), files = []
    for (const track of tracks ?? []) {
        if (!track) continue
        const meta = _meta(track, index)
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

function roots(tracks, index) {
    const lib = index && index.tracks === tracks ? index : null
    if (lib && lib.roots) return lib.roots
    const entries = contents(tracks, "", index)
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

function results(tracks, mode, genre, path, index) {
    if (mode === "genre") {
        const selected = new Set(Array.isArray(genre) ? genre : [genre])
        if (selected.size === 0) return []
        const out = []
        for (const track of tracks ?? []) {
            if (!track) continue
            const meta = _meta(track, index)
            const trackLabels = meta ? meta.labels : labels(track)
            if (trackLabels.some(label => selected.has(label)))
                out.push({kind: "track", track, name: meta ? meta.name : String(track.title || track.uri || "")})
        }
        return out
    }
    if (mode !== "folder") return []
    if (!Array.isArray(path)) return contents(tracks, path, index)
    if (path.length === 0) return []
    if (path.length === 1) return contents(tracks, path[0], index)
    const entries = new Map()
    for (const current of path) for (const entry of contents(tracks, current, index)) {
        const entryKey = key(entry)
        if (!entries.has(entryKey)) entries.set(entryKey, entry)
    }
    return Array.from(entries.values())
}

function parent(path) {
    const value = folder(path)
    return value.substring(0, Math.max(0, value.lastIndexOf("/")))
}

function matching(tracks, query, index) {
    const text = String(query ?? "").trim().toLowerCase()
    if (!text) return tracks ?? []
    const folded = _foldSearch(text)
    return (tracks ?? []).filter(track => {
        if (!track) return false
        const meta = _meta(track, index)
        if (!meta) return false
        if (meta.searchRaw === null) {
            meta.searchRaw = [track.title, track.artist, track.album, track.folder]
                .map(value => String(value ?? "").toLowerCase()).join(" ")
            meta.searchFolded = _foldSearch(meta.searchRaw)
        }
        return meta.searchRaw.includes(text) || (folded.length > 0 && meta.searchFolded.includes(folded))
    })
}

function search(index, rawQuery) {
    const query = String(rawQuery ?? "").trim().toLowerCase()
    if (!query) return index.tracks
    if (query === index.lastQuery) return index.lastMatches
    const extendsPrevious = index.lastQuery.length > 0 && query.startsWith(index.lastQuery)
    const pool = extendsPrevious ? index.lastMatches : index.tracks
    index.lastMatches = matching(pool, query, index)
    index.lastQuery = query
    return index.lastMatches
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

function selectedTracks(tracks, keys, index) {
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
        const meta = _meta(track, index)
        const uri = meta ? meta.uri : String(track.uri ?? track.path ?? "")
        if (seen.has(uri)) return false
        const path = meta ? meta.folder : trackFolder(track)
        if (!(selected.has("t:" + uri) || _folderMatches(path, folderSet))) return false
        seen.add(uri)
        return true
    })
}

function formatDuration(seconds) {
    const raw = Number(seconds)
    if (!Number.isFinite(raw) || raw <= 0) return "0:00"
    const whole = Math.floor(raw)
    const hours = Math.floor(whole / 3600)
    const mins = Math.floor((whole % 3600) / 60)
    const secs = whole % 60
    const pad2 = n => (n < 10 ? "0" + n : String(n))
    return hours > 0 ? `${hours}:${pad2(mins)}:${pad2(secs)}` : `${mins}:${pad2(secs)}`
}

function totalDuration(tracks) {
    let sum = 0
    for (const track of tracks ?? []) {
        const d = Number(track?.duration ?? 0)
        if (Number.isFinite(d) && d > 0) sum += d
    }
    return sum
}

function albums(tracks, index) {
    const lib = index && index.tracks === tracks ? index : null
    if (lib && lib.albums) return lib.albums
    const map = new Map()
    for (const track of tracks ?? []) {
        if (!track) continue
        const albumName = String(track.album ?? "").trim() || trackFolder(track) || "Unknown Album"
        const trackArtist = String(track.artist ?? "").trim()
        const dur = Number(track.duration ?? 0)
        const safeDur = Number.isFinite(dur) && dur > 0 ? dur : 0
        const art = String(track.art ?? "")
        const artUrl = String(track.artUrl ?? "")
        let entry = map.get(albumName)
        if (!entry) {
            entry = {
                key: albumName,
                name: albumName,
                artist: trackArtist,
                _multipleArtists: false,
                art,
                artUrl,
                trackCount: 0,
                totalDuration: 0,
                tracks: []
            }
            map.set(albumName, entry)
        } else {
            if (trackArtist && entry.artist && trackArtist !== entry.artist)
                entry._multipleArtists = true
            else if (trackArtist && !entry.artist)
                entry.artist = trackArtist
            if (!entry.art && art) entry.art = art
            if (!entry.artUrl && artUrl) entry.artUrl = artUrl
        }
        entry.tracks.push(track)
        entry.trackCount++
        entry.totalDuration += safeDur
    }
    const result = Array.from(map.values()).map(entry => ({
        key: entry.key,
        name: entry.name,
        artist: entry._multipleArtists ? "Various Artists" : (entry.artist || "Unknown Artist"),
        art: entry.art,
        artUrl: entry.artUrl,
        trackCount: entry.trackCount,
        totalDuration: entry.totalDuration,
        tracks: entry.tracks
    })).sort((a, b) => a.name.localeCompare(b.name))
    if (lib) lib.albums = result
    return result
}

function artists(tracks, index) {
    const lib = index && index.tracks === tracks ? index : null
    if (lib && lib.artists) return lib.artists
    const map = new Map()
    for (const track of tracks ?? []) {
        if (!track) continue
        const artistName = String(track.artist ?? "").trim() || "Unknown Artist"
        const albumName = String(track.album ?? "").trim()
        const art = String(track.art ?? "")
        const artUrl = String(track.artUrl ?? "")
        let entry = map.get(artistName)
        if (!entry) {
            entry = {
                key: artistName,
                name: artistName,
                art,
                artUrl,
                _albums: new Set(),
                trackCount: 0,
                tracks: []
            }
            map.set(artistName, entry)
        } else {
            if (!entry.art && art) entry.art = art
            if (!entry.artUrl && artUrl) entry.artUrl = artUrl
        }
        if (albumName) entry._albums.add(albumName)
        entry.tracks.push(track)
        entry.trackCount++
    }
    const result = Array.from(map.values()).map(entry => ({
        key: entry.key,
        name: entry.name,
        art: entry.art,
        artUrl: entry.artUrl,
        albumCount: entry._albums.size,
        trackCount: entry.trackCount,
        tracks: entry.tracks
    })).sort((a, b) => a.name.localeCompare(b.name))
    if (lib) lib.artists = result
    return result
}

function sortEntries(entries, field, ascending) {
    const list = (entries ?? []).slice()
    const keyName = String(field ?? "default")
    const dir = ascending === false ? -1 : 1
    if (keyName === "default")
        return dir < 0 ? list.reverse() : list
    return list.sort((a, b) => {
        if (a?.kind !== b?.kind && (a?.kind === "folder" || b?.kind === "folder"))
            return a?.kind === "folder" ? -1 : 1
        let cmp = 0
        if (keyName === "duration") {
            const da = Number(a?.duration ?? a?.totalDuration ?? a?.track?.duration ?? 0) || 0
            const db = Number(b?.duration ?? b?.totalDuration ?? b?.track?.duration ?? 0) || 0
            cmp = da - db
        } else if (keyName === "artist") {
            const aa = String(a?.artist ?? a?.track?.artist ?? "")
            const ab = String(b?.artist ?? b?.track?.artist ?? "")
            cmp = aa.localeCompare(ab)
        } else if (keyName === "album") {
            const la = String(a?.album ?? a?.track?.album ?? "")
            const lb = String(b?.album ?? b?.track?.album ?? "")
            cmp = la.localeCompare(lb)
        } else {
            const ta = String(a?.name ?? a?.title ?? a?.track?.title ?? a?.track?.uri ?? "")
            const tb = String(b?.name ?? b?.title ?? b?.track?.title ?? b?.track?.uri ?? "")
            cmp = ta.localeCompare(tb)
        }
        if (cmp !== 0) return cmp * dir
        const fa = String(a?.name ?? a?.track?.title ?? a?.track?.uri ?? "")
        const fb = String(b?.name ?? b?.track?.title ?? b?.track?.uri ?? "")
        return fa.localeCompare(fb) * dir
    })
}
