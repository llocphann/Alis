.pragma library

// Reduce only an explicitly consented app ID. Never accept a window title,
// filename, prompt, URL or process command as Companion context.
function category(appId) {
    if (typeof appId !== "string" || appId.length > 160) return "other"
    const id=appId.toLowerCase()
    if (["foot","footclient","kitty","alacritty","wezterm","org.wezfurlong.wezterm",
            "org.kde.konsole","org.gnome.terminal","com.mitchellh.ghostty"].includes(id)) return "terminal"
    if (["code","code-oss","vscodium","codium","dev.zed.zed","org.gnome.builder",
            "org.kde.kate","emacs","neovide","antigravity","google-antigravity",
            "cursor","windsurf","zed","obsidian"].includes(id)) return "editor"
    return id.length ? "other" : "none"
}
