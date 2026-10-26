.pragma library

function abyss(manual, automatic, profile) {
    if (automatic)
        return profile === "power-saver" ? "performance"
            : profile === "performance" ? "quality" : "balanced";
    return ["performance","balanced","quality"].includes(manual)
        ? manual : "balanced";
}

function aqua(manual, automatic, profile, shellQuality) {
    if (automatic)
        return profile === "power-saver" ? "performance"
            : profile === "performance" ? "detailed" : "quality";
    return manual === "performance" ? "performance"
        : manual === "detailed" ? "detailed" : "quality";
}

function aquaLabel(quality) {
    return quality === "performance" ? "Performance"
        : quality === "detailed" ? "Quality" : "Balanced";
}
