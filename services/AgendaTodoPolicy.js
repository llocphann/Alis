// Versioned metadata is additive. Events without a link are historical/read-only.
function validLink(link) {
    return link && link.version === 1 && typeof link.key === "string"
        && /^agenda-[a-z0-9-]{8,96}$/.test(link.key)
        && ["pending", "linked", "detached"].indexOf(link.state) >= 0;
}
function newLink(id, now, random) {
    return {version: 1, key: "agenda-" + Number(now).toString(36) + "-"
        + Number(id).toString(36) + "-" + String(random).replace(/[^a-z0-9]/g, ""),
        state: "pending", provider: "", fingerprint: ""};
}
function desired(event) {
    const start = new Date(event.startDate || event.dateTime);
    const end = new Date(event.endDate || "");
    const pad = value => (value < 10 ? "0" : "") + value;
    const valid = Number.isFinite(start.getTime());
    return {content: String(event.title || "Untitled event").replace(/[\r\n]+/g, " "),
        description: String(event.description || ""),
        date: valid ? start.getFullYear() + "-" + pad(start.getMonth()+1) + "-" + pad(start.getDate()) : "",
        startTime: valid && !event.allDay ? pad(start.getHours())+":"+pad(start.getMinutes()) : "",
        endTime: Number.isFinite(end.getTime()) && !event.allDay ? pad(end.getHours())+":"+pad(end.getMinutes()) : "",
        startDate: String(event.startDate || event.dateTime || ""),
        endDate: String(event.endDate || ""), allDay: event.allDay === true};
}
function fingerprint(event) { return JSON.stringify(desired(event)); }
function linkedItem(event, previous) {
    const fields = desired(event);
    const next = Object.assign({}, previous || {done: false}, fields);
    next.id = "agenda:" + event.todoLink.key;
    next.agenda = {version: 1, key: event.todoLink.key, eventId: event.id,
        fingerprint: fingerprint(event), sourceDate: event.todoLink.sourceDate || ""};
    // notes and completion belong to the task; updating the event never owns them.
    if (previous) next.done = previous.done === true;
    return next;
}
