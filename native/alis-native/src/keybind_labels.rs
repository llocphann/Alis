// Keep labels in sync with the Python keybind reader in scripts/niri-config.py.
// This table is compiled into the Rust binary; it does not invoke Python at runtime.
const KB_ACTION_MAP: &[(&str, &str)] = &[
    ("toggle-overview", "Niri Overview"),
    ("quit", "Quit Niri"),
    (
        "toggle-keyboard-shortcuts-inhibit",
        "Toggle shortcuts inhibit",
    ),
    ("power-off-monitors", "Power off monitors"),
    ("show-hotkey-overlay", "Niri hotkey overlay"),
    ("close-window", "Close window"),
    ("maximize-column", "Maximize column"),
    ("maximize-window-to-edges", "Maximize to edges"),
    ("fullscreen-window", "Fullscreen"),
    ("toggle-window-floating", "Toggle floating"),
    (
        "switch-focus-between-floating-and-tiling",
        "Switch float/tile focus",
    ),
    ("center-column", "Center column"),
    ("center-visible-columns", "Center visible columns"),
    (
        "expand-column-to-available-width",
        "Expand to available width",
    ),
    ("consume-or-expel-window-left", "Consume/expel left"),
    ("consume-or-expel-window-right", "Consume/expel right"),
    ("expel-window-from-column", "Expel from column"),
    ("consume-window-into-column", "Consume into column"),
    ("switch-preset-column-width", "Cycle column width"),
    ("switch-preset-window-height", "Cycle window height"),
    ("reset-window-height", "Reset window height"),
    ("toggle-column-tabbed-display", "Toggle tabbed display"),
    ("focus-column-left", "Focus left"),
    ("focus-column-right", "Focus right"),
    ("focus-window-up", "Focus up"),
    ("focus-window-down", "Focus down"),
    ("focus-column-first", "Focus first column"),
    ("focus-column-last", "Focus last column"),
    ("focus-monitor-left", "Focus monitor left"),
    ("focus-monitor-right", "Focus monitor right"),
    ("focus-monitor-up", "Focus monitor up"),
    ("focus-monitor-down", "Focus monitor down"),
    ("move-column-left", "Move left"),
    ("move-column-right", "Move right"),
    ("move-window-up", "Move up"),
    ("move-window-down", "Move down"),
    ("move-column-to-first", "Move to first"),
    ("move-column-to-last", "Move to last"),
    ("move-column-to-monitor-left", "Move to monitor left"),
    ("move-column-to-monitor-right", "Move to monitor right"),
    ("move-column-to-monitor-up", "Move to monitor up"),
    ("move-column-to-monitor-down", "Move to monitor down"),
    ("focus-workspace-up", "Previous workspace"),
    ("focus-workspace-down", "Next workspace"),
    ("move-column-to-workspace-up", "Move to prev workspace"),
    ("move-column-to-workspace-down", "Move to next workspace"),
    ("move-workspace-up", "Move workspace up"),
    ("move-workspace-down", "Move workspace down"),
    ("screenshot", "Screenshot"),
    ("screenshot-screen", "Screenshot screen"),
    ("screenshot-window", "Screenshot window"),
];

const KB_IPC_MAP: &[((&str, &str), &str)] = &[
    (("altSwitcher", "next"), "Next window"),
    (("altSwitcher", "previous"), "Previous window"),
    (("overlay", "toggle"), "iNiR Overlay"),
    (("overview", "toggle"), "iNiR Overview"),
    (("clipboard", "toggle"), "Clipboard"),
    (("lock", "activate"), "Lock screen"),
    (("region", "screenshot"), "Screenshot region"),
    (("region", "ocr"), "OCR region"),
    (("region", "search"), "Reverse image search"),
    (("wallpaperSelector", "toggle"), "Wallpaper selector"),
    (("settings", "open"), "Settings"),
    (("cheatsheet", "toggle"), "Cheatsheet"),
    (("panelFamily", "cycle"), "Cycle panel style"),
    (("session", "toggle"), "Session dialog"),
    (("browser", "open"), "Browser"),
    (("audio", "volumeUp"), "Volume up"),
    (("audio", "volumeDown"), "Volume down"),
    (("audio", "mute"), "Mute audio"),
    (("audio", "micMute"), "Mute microphone"),
    (("brightness", "increment"), "Brightness up"),
    (("brightness", "decrement"), "Brightness down"),
    (("mpris", "playPause"), "Play/Pause"),
    (("mpris", "next"), "Next track"),
    (("mpris", "previous"), "Previous track"),
    (("notifications", "clearAll"), "Clear notifications"),
    (("gamemode", "toggle"), "Toggle game mode"),
    (("launcher", "terminal"), "Terminal"),
    (("launcher", "close-window"), "Close window"),
];

const KB_TERMINALS: &[&str] = &[
    "foot",
    "kitty",
    "alacritty",
    "wezterm",
    "ghostty",
    "konsole",
    "gnome-terminal",
];

const KB_FILE_MANAGERS: &[&str] = &["dolphin", "nautilus", "thunar", "nemo", "pcmanfm", "ranger"];

const KB_BROWSERS: &[&str] = &["firefox", "zen-browser", "chromium", "brave", "vivaldi"];

use regex::Regex;
use std::sync::LazyLock;

static IPC_CALL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"spawn\s+"(?:[^"]*/)?inir"\s+"ipc"\s+"call"\s+"([\w-]+)"\s+"([\w-]+)""#).unwrap()
});
static SPECIAL_COMMAND: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r#"spawn\s+"(?:[^"]*/)?inir"\s+"(settings|terminal|close-window|browser)"(?:\s|;|$)"#,
    )
    .unwrap()
});
static GENERAL_COMMAND: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"spawn\s+"(?:[^"]*/)?inir"\s+"([\w-]+)"\s+"([\w-]+)""#).unwrap());
static WORKSPACE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(focus-workspace|move-column-to-workspace)\s+(\d+)").unwrap());
static SIZE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"^set-(column-width|window-height)\s+"([+-]\d+%?)""#).unwrap());
static IPC_FALLBACK: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"ipc.*call.*"(\w+)".*"(\w+)""#).unwrap());
static SPAWN_APP: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"spawn\s+"([^"]+)""#).unwrap());
static SHELL_CATEGORY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"ipc.*call.*(overlay|overview|clipboard|lock|wallpaper|settings|cheatsheet|panelfamily)",
    )
    .unwrap()
});

fn contains_any(text: &str, words: &[&str]) -> bool {
    words.iter().any(|word| text.contains(word))
}

fn inir_action(action: &str) -> Option<(String, String)> {
    if let Some(caps) = IPC_CALL.captures(action) {
        return Some((caps[1].to_owned(), caps[2].to_owned()));
    }
    if let Some(caps) = SPECIAL_COMMAND.captures(action) {
        let (target, function) = match &caps[1] {
            "settings" => ("settings", "open"),
            "terminal" => ("launcher", "terminal"),
            "close-window" => ("launcher", "close-window"),
            _ => ("browser", "open"),
        };
        return Some((target.to_owned(), function.to_owned()));
    }
    GENERAL_COMMAND
        .captures(action)
        .map(|caps| (caps[1].to_owned(), caps[2].to_owned()))
}

pub(super) fn action_description(action: &str) -> String {
    let action = action.trim();
    if let Some((_, label)) = KB_ACTION_MAP.iter().find(|(key, _)| *key == action) {
        return (*label).to_owned();
    }
    if let Some(caps) = WORKSPACE.captures(action) {
        let verb = if caps[1].contains("focus") {
            "Focus"
        } else {
            "Move to"
        };
        return format!("{verb} workspace {}", &caps[2]);
    }
    if let Some(caps) = SIZE.captures(action) {
        let target = if caps[1].contains("column") {
            "column"
        } else {
            "window"
        };
        let direction = if caps[2].starts_with('-') {
            "Shrink"
        } else {
            "Grow"
        };
        return format!(
            "{direction} {target} {}",
            caps[2].trim_start_matches(['+', '-'])
        );
    }
    if action.starts_with("spawn") {
        if let Some((target, function)) = inir_action(action) {
            return KB_IPC_MAP
                .iter()
                .find(|((t, f), _)| *t == target && *f == function)
                .map(|(_, label)| (*label).to_owned())
                .unwrap_or_else(|| format!("{target} {function}"));
        }
        if let Some(caps) = IPC_FALLBACK.captures(action) {
            let (target, function) = (&caps[1], &caps[2]);
            return KB_IPC_MAP
                .iter()
                .find(|((t, f), _)| *t == target && *f == function)
                .map(|(_, label)| (*label).to_owned())
                .unwrap_or_else(|| format!("{target} {function}"));
        }
        if action.contains("launch-terminal.sh") || contains_any(action, KB_TERMINALS) {
            return "Terminal".into();
        }
        if contains_any(action, KB_FILE_MANAGERS) {
            return "File manager".into();
        }
        if contains_any(action, KB_BROWSERS) {
            return "Browser".into();
        }
        if action.contains("wpctl") {
            return if action.contains("set-volume") {
                if action.contains('+') {
                    "Volume up"
                } else {
                    "Volume down"
                }
            } else {
                "Mute toggle"
            }
            .into();
        }
        if action.contains("brightnessctl") || action.contains("light") {
            return if action.contains('+') || action.contains("inc") {
                "Brightness up"
            } else {
                "Brightness down"
            }
            .into();
        }
        if action.contains("close-window") {
            return "Close window".into();
        }
        if let Some(caps) = SPAWN_APP.captures(action) {
            return caps[1].rsplit('/').next().unwrap_or(&caps[1]).to_owned();
        }
    }
    if action.chars().count() > 30 {
        format!("{}...", action.chars().take(30).collect::<String>())
    } else {
        action.to_owned()
    }
}

pub(super) fn action_category(description: &str, action: &str) -> &'static str {
    let desc = description.to_lowercase();
    let act = action.to_lowercase();
    if contains_any(
        &desc,
        &[
            "niri overview",
            "quit niri",
            "inhibit",
            "power off",
            "hotkey overlay",
        ],
    ) {
        return "System";
    }
    if contains_any(
        &desc,
        &[
            "inir ",
            "clipboard",
            "lock screen",
            "wallpaper",
            "settings",
            "cheatsheet",
            "panel style",
        ],
    ) {
        return "iNiR Shell";
    }
    if let Some((target, _)) = inir_action(action) {
        if [
            "overlay",
            "overview",
            "clipboard",
            "lock",
            "wallpaperSelector",
            "settings",
            "cheatsheet",
            "panelFamily",
            "session",
        ]
        .contains(&target.as_str())
        {
            return "iNiR Shell";
        }
        if target == "altSwitcher" {
            return "Window Switcher";
        }
        if target == "audio" || target == "mpris" {
            return "Media";
        }
        if target == "brightness" {
            return "Brightness";
        }
    }
    if SHELL_CATEGORY.is_match(&act) {
        return "iNiR Shell";
    }
    if desc.contains("window") && (desc.contains("next") || desc.contains("previous")) {
        return "Window Switcher";
    }
    if act.contains("altswitcher") {
        return "Window Switcher";
    }
    if contains_any(&desc, &["screenshot", "ocr", "image search"]) {
        return "Screenshots";
    }
    if contains_any(&desc, &["terminal", "file manager", "browser"]) {
        return "Applications";
    }
    if KB_TERMINALS
        .iter()
        .chain(KB_FILE_MANAGERS)
        .chain(KB_BROWSERS)
        .any(|word| act.contains(word))
    {
        return "Applications";
    }
    if contains_any(
        &desc,
        &[
            "close",
            "maximize",
            "fullscreen",
            "floating",
            "consume",
            "expel",
            "float/tile",
        ],
    ) || act.contains("close-window")
    {
        return "Window Management";
    }
    if contains_any(
        &desc,
        &[
            "cycle column",
            "cycle window",
            "reset window",
            "center column",
            "center visible",
            "expand to available",
            "tabbed",
        ],
    ) || contains_any(
        &act,
        &[
            "switch-preset-column",
            "switch-preset-window",
            "reset-window-height",
            "center-column",
            "center-visible",
            "expand-column",
            "toggle-column-tabbed",
        ],
    ) {
        return "Layout";
    }
    if contains_any(
        &desc,
        &[
            "shrink column",
            "grow column",
            "shrink window",
            "grow window",
        ],
    ) || contains_any(&act, &["set-column-width", "set-window-height"])
    {
        return "Resize";
    }
    if desc.contains("monitor")
        || contains_any(
            &act,
            &[
                "focus-monitor",
                "move-column-to-monitor",
                "move-window-to-monitor",
                "move-workspace-to-monitor",
            ],
        )
    {
        return "Monitors";
    }
    if desc.contains("focus") && !desc.contains("workspace") {
        return "Focus";
    }
    if desc.contains("move") && !desc.contains("workspace") && !desc.contains("track") {
        return "Move Windows";
    }
    if desc.contains("workspace") {
        return "Workspaces";
    }
    if contains_any(
        &desc,
        &[
            "volume",
            "mute",
            "play",
            "pause",
            "track",
            "audio",
            "microphone",
        ],
    ) || act.contains("mpris")
        || act.contains("audio")
    {
        return "Media";
    }
    if desc.contains("brightness") {
        return "Brightness";
    }
    "Other"
}

#[cfg(test)]
mod tests {
    use super::{action_category, action_description};

    #[test]
    fn labels_niri_and_shell_actions() {
        let cases = [
            ("toggle-overview", "Niri Overview", "System"),
            ("focus-workspace 3", "Focus workspace 3", "Workspaces"),
            ("set-column-width \"-10%\"", "Shrink column 10%", "Resize"),
            (
                "spawn \"inir\" \"ipc\" \"call\" \"clipboard\" \"toggle\"",
                "Clipboard",
                "iNiR Shell",
            ),
            (
                "spawn \"wpctl\" \"set-volume\" \"@DEFAULT_AUDIO_SINK@\" \"5%+\"",
                "Volume up",
                "Media",
            ),
        ];
        for (action, description, category) in cases {
            assert_eq!(action_description(action), description);
            assert_eq!(action_category(description, action), category);
        }
    }
}
