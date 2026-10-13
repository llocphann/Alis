use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, anyhow, bail};
use clap::Subcommand;
use kdl::KdlDocument;
use regex::Regex;
use serde_json::{Map, Value, json};

const DEFAULT_NIRI_FILES: &[&str] = &[
    "config.kdl",
    "config.d/10-input-and-cursor.kdl",
    "config.d/20-layout-and-overview.kdl",
    "config.d/30-window-rules.kdl",
    "config.d/40-environment.kdl",
    "config.d/50-startup.kdl",
    "config.d/60-animations.kdl",
    "config.d/70-binds.kdl",
    "config.d/80-layer-rules.kdl",
    "config.d/90-user-extra.kdl",
];

const BACKDROP_SHADOW_OVERRIDE_START: &str = "// >>> inir-backdrop-only >>>";
const BACKDROP_SHADOW_OVERRIDE_END: &str = "// <<< inir-backdrop-only <<<";

const ANIMATION_TYPES: &[&str] = &[
    "workspace-switch",
    "window-open",
    "window-close",
    "horizontal-view-movement",
    "window-movement",
    "window-resize",
    "config-notification-open-close",
    "exit-confirmation-open-close",
    "screenshot-ui-open",
    "overview-open-close",
    "recent-windows-close",
];

#[derive(Debug, Subcommand)]
pub enum NiriCommand {
    Outputs,
    ApplyOutput {
        name: String,
        #[arg(required = true)]
        changes: Vec<String>,
    },
    PersistOutput {
        name: String,
        #[arg(required = true)]
        changes: Vec<String>,
    },
    PersistLayout {
        layout: String,
    },
    GetInput,
    GetHotCorners,
    GetLayout,
    GetAnimations,
    GetWindowRules,
    ListCursorThemes,
    SyncCursor,
    Validate,
    DetectCustomizations {
        #[arg(long)]
        defaults_dir: Option<PathBuf>,
    },
    SyncBackdropOverviewShadow {
        mode: String,
    },
    Set {
        section: String,
        key: String,
        value: String,
    },
    GetBinds,
    SetBind {
        key_combo: String,
        action: String,
        #[arg(long)]
        options: Option<String>,
    },
    RemoveBind {
        key_combo: String,
    },
}

pub struct Outcome {
    pub value: Value,
    pub code: i32,
}

impl Outcome {
    fn ok(value: Value) -> Self {
        Self { value, code: 0 }
    }

    fn code(value: Value, code: i32) -> Self {
        Self { value, code }
    }
}

pub fn run(command: NiriCommand) -> Result<Outcome> {
    match command {
        NiriCommand::Outputs => outputs(),
        NiriCommand::ApplyOutput { name, changes } => apply_output(&name, &changes),
        NiriCommand::PersistOutput { name, changes } => persist_output(&name, &changes),
        NiriCommand::PersistLayout { layout } => persist_layout(&layout),
        NiriCommand::GetInput => get_input(),
        NiriCommand::GetHotCorners => get_hot_corners(),
        NiriCommand::GetLayout => get_layout(),
        NiriCommand::GetAnimations => get_animations(),
        NiriCommand::GetWindowRules => get_window_rules(),
        NiriCommand::ListCursorThemes => list_cursor_themes(),
        NiriCommand::SyncCursor => sync_cursor(),
        NiriCommand::Validate => validate(),
        NiriCommand::DetectCustomizations { defaults_dir } => {
            detect_customizations(defaults_dir.as_deref())
        }
        NiriCommand::SyncBackdropOverviewShadow { mode } => sync_backdrop_shadow(&mode),
        NiriCommand::Set {
            section,
            key,
            value,
        } => set_value(&section, &key, &value),
        NiriCommand::GetBinds => get_binds(),
        NiriCommand::SetBind {
            key_combo,
            action,
            options,
        } => set_bind(&key_combo, &action, options.as_deref().unwrap_or("")),
        NiriCommand::RemoveBind { key_combo } => remove_bind(&key_combo),
    }
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn config_dir() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".config"))
        .join("niri")
}

fn root_config() -> PathBuf {
    config_dir().join("config.kdl")
}

fn root_includes(relative: &str) -> bool {
    let Ok(content) = fs::read_to_string(root_config()) else {
        return false;
    };
    content.lines().any(|line| {
        let line = line.trim();
        line == format!("include \"{relative}\"")
    })
}

fn resolve_section_file(relative: &str) -> PathBuf {
    let modular = config_dir().join(relative);
    if modular.exists() && root_includes(relative) {
        modular
    } else if root_config().exists() {
        root_config()
    } else {
        modular
    }
}

fn run_process(program: &str, args: &[String]) -> Result<(String, i32)> {
    let output = Command::new(program)
        .args(args)
        .output()
        .with_context(|| format!("run {program}"))?;
    let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
    text.push_str(&String::from_utf8_lossy(&output.stderr));
    Ok((text.trim().to_owned(), output.status.code().unwrap_or(1)))
}

fn run_niri(args: &[&str]) -> Result<(String, i32)> {
    run_process(
        "niri",
        &std::iter::once("msg".to_owned())
            .chain(args.iter().map(|value| (*value).to_owned()))
            .collect::<Vec<_>>(),
    )
}

fn brace_depth_before(content: &str, end: usize) -> i32 {
    let bytes = content.as_bytes();
    let mut depth = 0i32;
    let mut quoted = false;
    let mut escaped = false;
    let mut line_comment = false;
    let mut i = 0usize;

    while i < end && i < bytes.len() {
        let byte = bytes[i];
        if line_comment {
            if byte == b'\n' {
                line_comment = false;
            }
            i += 1;
            continue;
        }
        if quoted {
            if escaped {
                escaped = false;
            } else if byte == b'\\' {
                escaped = true;
            } else if byte == b'"' {
                quoted = false;
            }
            i += 1;
            continue;
        }
        if byte == b'/' && i + 1 < end && bytes[i + 1] == b'/' {
            line_comment = true;
            i += 2;
            continue;
        }
        if byte == b'"' {
            quoted = true;
        } else if byte == b'{' {
            depth += 1;
        } else if byte == b'}' {
            depth -= 1;
        }
        i += 1;
    }
    depth
}

fn matching_brace(content: &str, opening: usize) -> Option<usize> {
    let bytes = content.as_bytes();
    let mut depth = 0i32;
    let mut quoted = false;
    let mut escaped = false;
    let mut line_comment = false;
    let mut i = opening;

    while i < bytes.len() {
        let byte = bytes[i];
        if line_comment {
            if byte == b'\n' {
                line_comment = false;
            }
            i += 1;
            continue;
        }
        if quoted {
            if escaped {
                escaped = false;
            } else if byte == b'\\' {
                escaped = true;
            } else if byte == b'"' {
                quoted = false;
            }
            i += 1;
            continue;
        }
        if byte == b'/' && i + 1 < bytes.len() && bytes[i + 1] == b'/' {
            line_comment = true;
            i += 2;
            continue;
        }
        if byte == b'"' {
            quoted = true;
        } else if byte == b'{' {
            depth += 1;
        } else if byte == b'}' {
            depth -= 1;
            if depth == 0 {
                return Some(i);
            }
        }
        i += 1;
    }
    None
}

fn find_block_bounds(
    content: &str,
    section: &str,
    top_level: bool,
) -> Option<(usize, usize, usize, usize)> {
    let pattern = Regex::new(&format!(
        r#"(?m)^[ \t]*{}(?:[ \t]+[^{{\n]*)?[ \t]*\{{"#,
        regex::escape(section)
    ))
    .ok()?;

    for matched in pattern.find_iter(content) {
        if top_level && brace_depth_before(content, matched.start()) != 0 {
            continue;
        }
        let opening = content[matched.start()..matched.end()].rfind('{')? + matched.start();
        let closing = matching_brace(content, opening)?;
        return Some((matched.start(), opening + 1, closing, closing + 1));
    }
    None
}

fn find_output_bounds(content: &str, output_name: &str) -> Option<(usize, usize, usize, usize)> {
    let pattern = Regex::new(&format!(
        r#"(?m)^[ \t]*output[ \t]+"{}"[ \t]*\{{"#,
        regex::escape(output_name)
    ))
    .ok()?;
    for matched in pattern.find_iter(content) {
        if brace_depth_before(content, matched.start()) != 0 {
            continue;
        }
        let opening = content[matched.start()..matched.end()].rfind('{')? + matched.start();
        let closing = matching_brace(content, opening)?;
        return Some((matched.start(), opening + 1, closing, closing + 1));
    }
    None
}

fn extract_block(content: &str, section: &str, top_level: bool) -> Option<String> {
    let (_, start, end, _) = find_block_bounds(content, section, top_level)?;
    Some(content[start..end].to_owned())
}

fn indentation_at(content: &str, block_start: usize) -> String {
    let line_start = content[..block_start]
        .rfind('\n')
        .map_or(0, |index| index + 1);
    content[line_start..block_start]
        .chars()
        .take_while(|value| *value == ' ' || *value == '\t')
        .collect()
}

fn set_line_in_block(
    content: &str,
    section: &str,
    key: &str,
    rendered_value: &str,
    top_level: bool,
) -> Result<String> {
    let (block_start, inner_start, inner_end, _) =
        find_block_bounds(content, section, top_level)
            .ok_or_else(|| anyhow!("section_not_found:{section}"))?;
    let inner = &content[inner_start..inner_end];
    let line_re = Regex::new(&format!(
        r"(?m)^([ \t]*){}(?:[ \t]+[^\n]*)?[ \t]*$",
        regex::escape(key)
    ))?;

    let replacement = |caps: &regex::Captures<'_>| {
        if rendered_value.is_empty() {
            format!("{}{}", &caps[1], key)
        } else {
            format!("{}{} {}", &caps[1], key, rendered_value)
        }
    };

    let next_inner = if line_re.is_match(inner) {
        line_re.replace(inner, replacement).into_owned()
    } else {
        let mut trimmed = inner.trim_end_matches([' ', '\t', '\n', '\r']).to_owned();
        let indent = format!("{}    ", indentation_at(content, block_start));
        if !trimmed.ends_with('\n') {
            trimmed.push('\n');
        }
        trimmed.push_str(&indent);
        trimmed.push_str(key);
        if !rendered_value.is_empty() {
            trimmed.push(' ');
            trimmed.push_str(rendered_value);
        }
        trimmed.push('\n');
        trimmed.push_str(&indentation_at(content, block_start));
        trimmed
    };
    Ok(format!(
        "{}{}{}",
        &content[..inner_start],
        next_inner,
        &content[inner_end..]
    ))
}

fn remove_line_in_block(
    content: &str,
    section: &str,
    key: &str,
    top_level: bool,
) -> Result<String> {
    let (_, inner_start, inner_end, _) = find_block_bounds(content, section, top_level)
        .ok_or_else(|| anyhow!("section_not_found:{section}"))?;
    let inner = &content[inner_start..inner_end];
    let line_re = Regex::new(&format!(
        r"(?m)^[ \t]*{}(?:[ \t]+[^\n]*)?[ \t]*\n?",
        regex::escape(key)
    ))?;
    let next_inner = line_re.replacen(inner, 1, "").into_owned();
    Ok(format!(
        "{}{}{}",
        &content[..inner_start],
        next_inner,
        &content[inner_end..]
    ))
}

fn toggle_flag(
    content: &str,
    section: &str,
    flag: &str,
    enabled: bool,
    top_level: bool,
) -> Result<String> {
    if enabled {
        set_line_in_block(content, section, flag, "", top_level)
    } else {
        remove_line_in_block(content, section, flag, top_level)
    }
}

fn ensure_subsection(
    content: &str,
    parent: &str,
    subsection: &str,
    parent_top_level: bool,
) -> Result<String> {
    let (parent_start, inner_start, inner_end, _) =
        find_block_bounds(content, parent, parent_top_level)
            .ok_or_else(|| anyhow!("section_not_found:{parent}"))?;
    let inner = &content[inner_start..inner_end];
    if find_block_bounds(inner, subsection, true).is_some() {
        return Ok(content.to_owned());
    }
    let parent_indent = indentation_at(content, parent_start);
    let child_indent = format!("{parent_indent}    ");
    let mut next_inner = inner.trim_end_matches([' ', '\t', '\n', '\r']).to_owned();
    next_inner.push_str(&format!(
        "\n{child_indent}{subsection} {{\n{child_indent}}}\n{parent_indent}"
    ));
    Ok(format!(
        "{}{}{}",
        &content[..inner_start],
        next_inner,
        &content[inner_end..]
    ))
}

fn set_nested_line(
    content: &str,
    parent: &str,
    child: &str,
    key: &str,
    rendered: &str,
    parent_top_level: bool,
) -> Result<String> {
    let content = ensure_subsection(content, parent, child, parent_top_level)?;
    let (_, parent_inner_start, parent_inner_end, _) =
        find_block_bounds(&content, parent, parent_top_level)
            .ok_or_else(|| anyhow!("section_not_found:{parent}"))?;
    let parent_inner = &content[parent_inner_start..parent_inner_end];
    let next_parent_inner = set_line_in_block(parent_inner, child, key, rendered, true)?;
    Ok(format!(
        "{}{}{}",
        &content[..parent_inner_start],
        next_parent_inner,
        &content[parent_inner_end..]
    ))
}

fn toggle_nested_flag(
    content: &str,
    parent: &str,
    child: &str,
    flag: &str,
    enabled: bool,
    parent_top_level: bool,
) -> Result<String> {
    let content = ensure_subsection(content, parent, child, parent_top_level)?;
    let (_, parent_inner_start, parent_inner_end, _) =
        find_block_bounds(&content, parent, parent_top_level)
            .ok_or_else(|| anyhow!("section_not_found:{parent}"))?;
    let parent_inner = &content[parent_inner_start..parent_inner_end];
    let next_parent_inner = toggle_flag(parent_inner, child, flag, enabled, true)?;
    Ok(format!(
        "{}{}{}",
        &content[..parent_inner_start],
        next_parent_inner,
        &content[parent_inner_end..]
    ))
}

fn parse_kdl(text: &str) -> Result<()> {
    text.parse::<KdlDocument>()
        .map(|_| ())
        .map_err(|error| anyhow!("kdl_parse_failed:{error}"))
}

fn validate_root_config() -> Result<(bool, String)> {
    let config = root_config();
    if !config.exists() {
        return Ok((true, String::new()));
    }
    match Command::new("niri")
        .args(["validate", "-c"])
        .arg(&config)
        .output()
    {
        Ok(output) => {
            let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
            text.push_str(&String::from_utf8_lossy(&output.stderr));
            Ok((output.status.success(), text.trim().to_owned()))
        }
        Err(_) => Ok((true, String::new())),
    }
}

fn write_validated(path: &Path, content: &str) -> Result<Outcome> {
    parse_kdl(content)?;
    let backup = fs::read(path).ok();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, content)?;
    let (valid, error) = validate_root_config()?;
    if !valid {
        if let Some(backup) = backup {
            fs::write(path, backup)?;
        } else {
            let _ = fs::remove_file(path);
        }
        return Ok(Outcome::code(
            json!({"success": false, "error": format!("Validation failed: {error}")}),
            1,
        ));
    }
    Ok(Outcome::ok(
        json!({"success": true, "file": path.to_string_lossy()}),
    ))
}

fn vrr_modes() -> BTreeMap<String, String> {
    let path = resolve_section_file("config.d/15-outputs.kdl");
    let Ok(content) = fs::read_to_string(path) else {
        return BTreeMap::new();
    };
    let mut modes = BTreeMap::new();
    let output_re = Regex::new(r#"(?m)^[ \t]*output[ \t]+"([^"]+)"[ \t]*\{"#).unwrap();
    for caps in output_re.captures_iter(&content) {
        let Some(full) = caps.get(0) else { continue };
        let Some(name) = caps.get(1) else { continue };
        let Some(opening) = content[full.start()..full.end()].rfind('{') else {
            continue;
        };
        let opening = full.start() + opening;
        let Some(closing) = matching_brace(&content, opening) else {
            continue;
        };
        let block = &content[opening + 1..closing];
        let line = block
            .lines()
            .map(str::trim)
            .find(|line| line.starts_with("variable-refresh-rate"));
        let mode = match line {
            None => "off",
            Some(line) if line.contains("on-demand=true") => "on-demand",
            Some(_) => "on",
        };
        modes.insert(name.as_str().to_owned(), mode.to_owned());
    }
    modes
}

fn outputs() -> Result<Outcome> {
    let (raw, code) = run_niri(&["-j", "outputs"])?;
    if code != 0 {
        return Ok(Outcome::code(
            json!({"error": format!("niri msg failed: {raw}")}),
            1,
        ));
    }
    let data: Value = serde_json::from_str(&raw)?;
    let modes_by_output = vrr_modes();
    let mut result = Vec::new();

    let Some(outputs) = data.as_object() else {
        bail!("invalid_niri_outputs_json");
    };
    for (name, output) in outputs {
        let modes = output.get("modes").and_then(Value::as_array);
        let current_index = output
            .get("current_mode")
            .and_then(Value::as_u64)
            .unwrap_or(0) as usize;
        let logical = output.get("logical").and_then(Value::as_object);

        let mut resolution_map: BTreeMap<String, usize> = BTreeMap::new();
        let mut resolutions = Vec::new();
        for (index, mode) in modes.into_iter().flatten().enumerate() {
            let width = mode.get("width").and_then(Value::as_i64).unwrap_or(0);
            let height = mode.get("height").and_then(Value::as_i64).unwrap_or(0);
            let refresh = mode
                .get("refresh_rate")
                .and_then(Value::as_f64)
                .unwrap_or(0.0)
                / 1000.0;
            let preferred = mode
                .get("is_preferred")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let key = format!("{width}x{height}");
            let position = *resolution_map.entry(key).or_insert_with(|| {
                resolutions.push(json!({
                    "width": width,
                    "height": height,
                    "rates": [],
                    "preferred": preferred,
                }));
                resolutions.len() - 1
            });
            let entry = &mut resolutions[position];
            if let Some(object) = entry.as_object_mut() {
                if preferred {
                    object.insert("preferred".into(), Value::Bool(true));
                }
                if let Some(rates) = object.get_mut("rates").and_then(Value::as_array_mut) {
                    let rounded = (refresh * 1000.0).round() / 1000.0;
                    if !rates.iter().any(|item| {
                        item.get("rate")
                            .and_then(Value::as_f64)
                            .is_some_and(|value| (value - rounded).abs() < 0.0005)
                    }) {
                        rates.push(json!({
                            "rate": rounded,
                            "rate_string": format!("{rounded:.3}"),
                            "mode_index": index,
                            "preferred": preferred,
                        }));
                    }
                }
            }
        }

        let current_mode = modes.and_then(|modes| modes.get(current_index));
        let current_width = current_mode
            .and_then(|mode| mode.get("width"))
            .and_then(Value::as_i64)
            .unwrap_or(0);
        let current_height = current_mode
            .and_then(|mode| mode.get("height"))
            .and_then(Value::as_i64)
            .unwrap_or(0);
        let current_rate = current_mode
            .and_then(|mode| mode.get("refresh_rate"))
            .and_then(Value::as_f64)
            .map(|value| (value / 1000.0 * 1000.0).round() / 1000.0)
            .unwrap_or(0.0);
        let current_resolution = if current_mode.is_some() {
            format!("{current_width}x{current_height}")
        } else {
            String::new()
        };

        let vrr_enabled = output
            .get("vrr_enabled")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        result.push(json!({
            "name": name,
            "make": output.get("make").cloned().unwrap_or(json!("")),
            "model": output.get("model").cloned().unwrap_or(json!("")),
            "serial": output.get("serial").cloned().unwrap_or(json!("")),
            "physical_size": output.get("physical_size").cloned().unwrap_or(json!([0, 0])),
            "current_resolution": current_resolution,
            "current_rate": current_rate,
            "current_rate_string": if current_mode.is_some() { format!("{current_rate:.3}") } else { String::new() },
            "scale": logical.and_then(|value| value.get("scale")).cloned().unwrap_or(json!(1.0)),
            "transform": logical.and_then(|value| value.get("transform")).cloned().unwrap_or(json!("Normal")),
            "position": {
                "x": logical.and_then(|value| value.get("x")).cloned().unwrap_or(json!(0)),
                "y": logical.and_then(|value| value.get("y")).cloned().unwrap_or(json!(0)),
            },
            "vrr_supported": output.get("vrr_supported").cloned().unwrap_or(json!(false)),
            "vrr_enabled": vrr_enabled,
            "vrr_mode": modes_by_output
                .get(name)
                .cloned()
                .unwrap_or_else(|| if vrr_enabled { "on".into() } else { "off".into() }),
            "resolutions": resolutions,
        }));
    }
    Ok(Outcome::ok(Value::Array(result)))
}

fn apply_output(name: &str, changes: &[String]) -> Result<Outcome> {
    let mut results = Vec::new();
    let mut failed = false;
    for change in changes {
        let Some((key, value)) = change.split_once('=') else {
            results.push(json!({"key": change, "error": "missing value"}));
            failed = true;
            continue;
        };
        let mut args = vec!["output".to_owned(), name.to_owned()];
        match key {
            "mode" | "scale" | "transform" => {
                args.push(key.to_owned());
                args.push(value.to_owned());
            }
            "vrr" if value == "on-demand" => {
                args.extend(["vrr".into(), "--on-demand".into(), "on".into()]);
            }
            "vrr" => {
                args.extend(["vrr".into(), value.to_owned()]);
            }
            "position" => {
                args.push("position".into());
                if let Some((x, y)) = value.split_once(',') {
                    args.extend(["set".into(), x.into(), y.into()]);
                } else {
                    args.push("auto".into());
                }
            }
            "dpms" => args.push(value.to_owned()),
            _ => {
                results.push(json!({"key": key, "error": "unknown key"}));
                failed = true;
                continue;
            }
        }
        let (output, code) = run_process(
            "niri",
            &std::iter::once("msg".to_owned())
                .chain(args)
                .collect::<Vec<_>>(),
        )?;
        if code != 0 {
            failed = true;
        }
        results.push(json!({
            "key": key,
            "value": value,
            "success": code == 0,
            "output": output,
        }));
    }
    Ok(Outcome::code(
        json!({"results": results}),
        i32::from(failed),
    ))
}

fn set_line_in_inner(inner: &str, key: &str, rendered: &str, indent: &str) -> Result<String> {
    let line_re = Regex::new(&format!(
        r"(?m)^([ \t]*){}(?:[ \t]+[^\n]*)?[ \t]*$",
        regex::escape(key)
    ))?;
    if line_re.is_match(inner) {
        return Ok(line_re
            .replace(inner, |caps: &regex::Captures<'_>| {
                if rendered.is_empty() {
                    format!("{}{}", &caps[1], key)
                } else {
                    format!("{}{} {}", &caps[1], key, rendered)
                }
            })
            .into_owned());
    }
    let mut next = inner.trim_end().to_owned();
    next.push('\n');
    next.push_str(indent);
    next.push_str(key);
    if !rendered.is_empty() {
        next.push(' ');
        next.push_str(rendered);
    }
    next.push('\n');
    Ok(next)
}

fn ensure_vrr_rule() -> Result<()> {
    const VRR_WINDOW_RULE: &str = r#"
// On-demand VRR: variable refresh rate only turns on for windows matched here.
// Add your own app-ids to extend it, or remove the block to keep VRR always off.
window-rule {
    match app-id="^(gamescope|steam_app_[0-9]+|lutris|heroic|com\\.heroicgameslauncher\\.hgl|mpv|vlc)$"

    variable-refresh-rate true
}
"#;

    let path = resolve_section_file("config.d/30-window-rules.kdl");
    let content = fs::read_to_string(&path).unwrap_or_default();
    let configured = Regex::new(r"(?m)^[ \t]*variable-refresh-rate\b")?;
    if configured.is_match(&content) {
        return Ok(());
    }

    let next = format!("{}\n{VRR_WINDOW_RULE}", content.trim_end());
    let _ = write_validated(&path, &next)?;
    Ok(())
}

fn persist_output(name: &str, changes: &[String]) -> Result<Outcome> {
    let allowed = ["mode", "scale", "transform", "vrr", "position"];
    let mut parsed = BTreeMap::new();
    for change in changes {
        let Some((key, value)) = change.split_once('=') else {
            bail!("invalid_output_change:{change}");
        };
        if !allowed.contains(&key) {
            bail!("unknown_output_key:{key}");
        }
        parsed.insert(key.to_owned(), value.to_owned());
    }
    if parsed.is_empty() {
        bail!("no_output_changes");
    }
    if parsed.get("vrr").is_some_and(|value| value == "on-demand") {
        ensure_vrr_rule()?;
    }

    let path = resolve_section_file("config.d/15-outputs.kdl");
    let mut content = fs::read_to_string(&path).unwrap_or_default();
    if let Some((_, inner_start, inner_end, _)) = find_output_bounds(&content, name) {
        let mut inner = content[inner_start..inner_end].to_owned();
        let indent = format!(
            "{}    ",
            indentation_at(&content, inner_start.saturating_sub(1))
        );
        let vrr_line_re = Regex::new(r"(?m)^[ \t]*variable-refresh-rate[^\n]*\n?")?;
        for (key, value) in &parsed {
            match key.as_str() {
                "mode" => {
                    inner = set_line_in_inner(&inner, "mode", &format!("\"{value}\""), &indent)?
                }
                "scale" => inner = set_line_in_inner(&inner, "scale", value, &indent)?,
                "transform" => {
                    inner =
                        set_line_in_inner(&inner, "transform", &format!("\"{value}\""), &indent)?
                }
                "position" => {
                    if let Some((x, y)) = value.split_once(',') {
                        inner = set_line_in_inner(
                            &inner,
                            "position",
                            &format!("x={x} y={y}"),
                            &indent,
                        )?;
                    }
                }
                "vrr" if value == "off" => {
                    inner = vrr_line_re.replacen(&inner, 1, "").into_owned();
                }
                "vrr" if value == "on-demand" => {
                    inner = set_line_in_inner(
                        &inner,
                        "variable-refresh-rate",
                        "on-demand=true",
                        &indent,
                    )?;
                }
                "vrr" => {
                    inner = set_line_in_inner(&inner, "variable-refresh-rate", "", &indent)?;
                }
                _ => {}
            }
        }
        content = format!(
            "{}{}{}",
            &content[..inner_start],
            inner,
            &content[inner_end..]
        );
    } else {
        let mut lines = Vec::new();
        if let Some(value) = parsed.get("mode") {
            lines.push(format!("    mode \"{value}\""));
        }
        if let Some(value) = parsed.get("scale") {
            lines.push(format!("    scale {value}"));
        }
        if let Some(value) = parsed.get("transform") {
            lines.push(format!("    transform \"{value}\""));
        }
        if let Some(value) = parsed.get("position")
            && let Some((x, y)) = value.split_once(',')
        {
            lines.push(format!("    position x={x} y={y}"));
        }
        if let Some(value) = parsed.get("vrr") {
            if value == "on-demand" {
                lines.push("    variable-refresh-rate on-demand=true".into());
            } else if value != "off" {
                lines.push("    variable-refresh-rate".into());
            }
        }
        let block = format!("output \"{name}\" {{\n{}\n}}", lines.join("\n"));
        if !content.trim().is_empty() {
            content = format!("{}\n\n{block}\n", content.trim_end());
        } else {
            content = format!("{block}\n");
        }
    }
    write_validated(&path, &content)
}

fn persist_layout(layout_json: &str) -> Result<Outcome> {
    let layout: BTreeMap<String, Value> = serde_json::from_str(layout_json)?;
    if layout.is_empty() {
        bail!("layout_must_be_non_empty");
    }
    let path = resolve_section_file("config.d/15-outputs.kdl");
    let mut content = fs::read_to_string(&path).unwrap_or_default();
    for (name, position) in layout {
        let x = position
            .get("x")
            .and_then(Value::as_i64)
            .ok_or_else(|| anyhow!("missing_x:{name}"))?;
        let y = position
            .get("y")
            .and_then(Value::as_i64)
            .ok_or_else(|| anyhow!("missing_y:{name}"))?;
        if let Some((_, inner_start, inner_end, _)) = find_output_bounds(&content, &name) {
            let inner = &content[inner_start..inner_end];
            let indent = format!(
                "{}    ",
                indentation_at(&content, inner_start.saturating_sub(1))
            );
            let next = set_line_in_inner(inner, "position", &format!("x={x} y={y}"), &indent)?;
            content = format!(
                "{}{}{}",
                &content[..inner_start],
                next,
                &content[inner_end..]
            );
        } else {
            let block = format!("output \"{name}\" {{\n    position x={x} y={y}\n}}");
            content = if content.trim().is_empty() {
                format!("{block}\n")
            } else {
                format!("{}\n\n{block}\n", content.trim_end())
            };
        }
    }
    write_validated(&path, &content)
}

fn quoted_value(block: &str, key: &str) -> Option<String> {
    Regex::new(&format!(
        r#"(?m)^[ \t]*{}[ \t]+"([^"]*)""#,
        regex::escape(key)
    ))
    .ok()?
    .captures(block)?
    .get(1)
    .map(|value| value.as_str().to_owned())
}

fn numeric_value(block: &str, key: &str) -> Option<f64> {
    Regex::new(&format!(
        r"(?m)^[ \t]*{}[ \t]+([-0-9.]+)",
        regex::escape(key)
    ))
    .ok()?
    .captures(block)?
    .get(1)?
    .as_str()
    .parse()
    .ok()
}

fn bool_line_value(block: &str, key: &str) -> Option<bool> {
    let re = Regex::new(&format!(
        r"(?m)^[ \t]*{}[ \t]+(true|false)[ \t]*$",
        regex::escape(key)
    ))
    .ok()?;
    re.captures(block)
        .and_then(|caps| caps.get(1))
        .map(|value| value.as_str() == "true")
}

fn has_flag(block: &str, key: &str) -> bool {
    Regex::new(&format!(
        r"(?m)^[ \t]*{}(?:[ \t]+true)?[ \t]*$",
        regex::escape(key)
    ))
    .is_ok_and(|regex| regex.is_match(block))
}

fn get_input() -> Result<Outcome> {
    let mut result = json!({
        "keyboard": {
            "layout": "us", "variant": "", "options": "", "track_layout": "global",
            "repeat_delay": 250, "repeat_rate": 50, "numlock": false
        },
        "touchpad": {
            "tap": true, "natural_scroll": false, "dwt": false, "dwtp": false,
            "drag_lock": false, "disabled_on_external_mouse": false, "left_handed": false,
            "middle_emulation": false, "accel_profile": "adaptive", "accel_speed": 0.0,
            "tap_button_map": "left-right-middle", "click_method": "button-areas",
            "scroll_method": "two-finger", "scroll_button_lock": false
        },
        "mouse": {
            "natural_scroll": false, "left_handed": false, "middle_emulation": false,
            "scroll_button_lock": false, "accel_profile": "flat", "accel_speed": 0.0,
            "scroll_method": "no-scroll"
        },
        "trackpoint": {
            "natural_scroll": false, "left_handed": false, "middle_emulation": false,
            "scroll_button_lock": false, "accel_profile": "flat", "accel_speed": 0.0,
            "scroll_method": "on-button-down"
        },
        "cursor": {"theme": "capitaine-cursors-light", "size": 24, "hide_when_typing": true},
        "general": {
            "disable_power_key_handling": false, "warp_mouse_to_focus": false,
            "warp_mouse_to_focus_mode": "separate", "focus_follows_mouse": false,
            "focus_follows_mouse_max_scroll": 0, "workspace_auto_back_and_forth": false,
            "mod_key": "Super", "mod_key_nested": "Alt"
        }
    });
    let path = resolve_section_file("config.d/10-input-and-cursor.kdl");
    let Ok(content) = fs::read_to_string(path) else {
        return Ok(Outcome::ok(result));
    };
    let input = extract_block(&content, "input", true).unwrap_or_default();
    let cursor = extract_block(&content, "cursor", true).unwrap_or_default();

    if let Some(keyboard) = extract_block(&input, "keyboard", true) {
        if let Some(xkb) = extract_block(&keyboard, "xkb", true) {
            if let Some(value) = quoted_value(&xkb, "layout") {
                result["keyboard"]["layout"] = json!(value);
            }
            if let Some(value) = quoted_value(&xkb, "variant") {
                result["keyboard"]["variant"] = json!(value);
            }
            if let Some(value) = quoted_value(&xkb, "options") {
                result["keyboard"]["options"] = json!(value);
            }
        }
        if let Some(value) = quoted_value(&keyboard, "track-layout") {
            result["keyboard"]["track_layout"] = json!(value);
        }
        if let Some(value) = numeric_value(&keyboard, "repeat-delay") {
            result["keyboard"]["repeat_delay"] = json!(value as i64);
        }
        if let Some(value) = numeric_value(&keyboard, "repeat-rate") {
            result["keyboard"]["repeat_rate"] = json!(value as i64);
        }
        result["keyboard"]["numlock"] = json!(has_flag(&keyboard, "numlock"));
    }

    for section in ["touchpad", "mouse", "trackpoint"] {
        if let Some(block) = extract_block(&input, section, true) {
            let key = section;
            for (kdl_key, json_key) in [
                ("natural-scroll", "natural_scroll"),
                ("left-handed", "left_handed"),
                ("middle-emulation", "middle_emulation"),
                ("scroll-button-lock", "scroll_button_lock"),
                ("drag-lock", "drag_lock"),
                ("disabled-on-external-mouse", "disabled_on_external_mouse"),
                ("tap", "tap"),
                ("dwt", "dwt"),
                ("dwtp", "dwtp"),
            ] {
                if result[key].get(json_key).is_some() {
                    result[key][json_key] = json!(has_flag(&block, kdl_key));
                }
            }
            for (kdl_key, json_key) in [
                ("accel-profile", "accel_profile"),
                ("tap-button-map", "tap_button_map"),
                ("click-method", "click_method"),
                ("scroll-method", "scroll_method"),
            ] {
                if let Some(value) = quoted_value(&block, kdl_key)
                    && result[key].get(json_key).is_some()
                {
                    result[key][json_key] = json!(value);
                }
            }
            if let Some(value) = numeric_value(&block, "accel-speed") {
                result[key]["accel_speed"] = json!(value);
            }
        }
    }

    if let Some(value) = quoted_value(&cursor, "xcursor-theme") {
        result["cursor"]["theme"] = json!(value);
    }
    if let Some(value) = numeric_value(&cursor, "xcursor-size") {
        result["cursor"]["size"] = json!(value as i64);
    }
    result["cursor"]["hide_when_typing"] = json!(has_flag(&cursor, "hide-when-typing"));

    result["general"]["disable_power_key_handling"] =
        json!(has_flag(&input, "disable-power-key-handling"));
    result["general"]["workspace_auto_back_and_forth"] =
        json!(has_flag(&input, "workspace-auto-back-and-forth"));
    if let Some(value) = quoted_value(&input, "mod-key") {
        result["general"]["mod_key"] = json!(value);
    }
    if let Some(value) = quoted_value(&input, "mod-key-nested") {
        result["general"]["mod_key_nested"] = json!(value);
    }

    let warp_re = Regex::new(r#"(?m)^[ \t]*warp-mouse-to-focus(?:[ \t]+mode="([^"]+)")?"#)?;
    if let Some(caps) = warp_re.captures(&input) {
        result["general"]["warp_mouse_to_focus"] = json!(true);
        if let Some(mode) = caps.get(1) {
            result["general"]["warp_mouse_to_focus_mode"] = json!(mode.as_str());
        }
    }
    let focus_re =
        Regex::new(r#"(?m)^[ \t]*focus-follows-mouse(?:[ \t]+max-scroll-amount="?([^" \n]+)"?)?"#)?;
    if let Some(caps) = focus_re.captures(&input) {
        result["general"]["focus_follows_mouse"] = json!(true);
        if let Some(value) = caps.get(1) {
            result["general"]["focus_follows_mouse_max_scroll"] =
                json!(value.as_str().parse::<i64>().unwrap_or(0));
        }
    }

    Ok(Outcome::ok(result))
}

fn flatten_config(path: &Path, seen: &mut HashSet<PathBuf>) -> String {
    let Ok(canonical) = path.canonicalize() else {
        return fs::read_to_string(path).unwrap_or_default();
    };
    if !seen.insert(canonical.clone()) {
        return String::new();
    }
    let content = fs::read_to_string(&canonical).unwrap_or_default();
    let include_re = Regex::new(r#"(?m)^[ \t]*include[ \t]+"([^"]+)"[ \t]*$"#).unwrap();
    let base = canonical.parent().unwrap_or_else(|| Path::new("."));
    include_re
        .replace_all(&content, |caps: &regex::Captures<'_>| {
            flatten_config(&base.join(&caps[1]), seen)
        })
        .into_owned()
}

fn strip_line_comments(content: &str) -> String {
    content
        .lines()
        .map(|line| line.split("//").next().unwrap_or_default())
        .collect::<Vec<_>>()
        .join("\n")
}

fn parse_hot_corners(block: Option<String>) -> Option<Vec<String>> {
    let block = block?;
    let tokens = block.lines().map(str::trim).collect::<Vec<_>>();
    if tokens.contains(&"off") {
        return Some(Vec::new());
    }
    let mapping = [
        ("top-left", "topLeft"),
        ("top-right", "topRight"),
        ("bottom-left", "bottomLeft"),
        ("bottom-right", "bottomRight"),
    ];
    let corners = mapping
        .iter()
        .filter(|(source, _)| tokens.contains(source))
        .map(|(_, target)| (*target).to_owned())
        .collect::<Vec<_>>();
    if corners.is_empty() {
        Some(vec!["topLeft".into()])
    } else {
        Some(corners)
    }
}

fn iter_output_blocks(content: &str) -> Vec<(String, String)> {
    let regex = Regex::new(r#"(?m)^[ \t]*output[ \t]+"([^"]+)"[ \t]*\{"#).unwrap();
    let mut result = Vec::new();
    for caps in regex.captures_iter(content) {
        let Some(full) = caps.get(0) else { continue };
        let Some(name) = caps.get(1) else { continue };
        let Some(offset) = content[full.start()..full.end()].rfind('{') else {
            continue;
        };
        let opening = full.start() + offset;
        let Some(closing) = matching_brace(content, opening) else {
            continue;
        };
        result.push((
            name.as_str().to_owned(),
            content[opening + 1..closing].to_owned(),
        ));
    }
    result
}

fn get_hot_corners() -> Result<Outcome> {
    let flattened = strip_line_comments(&flatten_config(&root_config(), &mut HashSet::new()));
    let gestures = extract_block(&flattened, "gestures", true);
    let global = gestures
        .as_deref()
        .and_then(|block| parse_hot_corners(extract_block(block, "hot-corners", true)))
        .unwrap_or_else(|| vec!["topLeft".into()]);

    let mut overrides = BTreeMap::new();
    for (name, block) in iter_output_blocks(&flattened) {
        if let Some(value) = parse_hot_corners(extract_block(&block, "hot-corners", true)) {
            overrides.insert(name, value);
        }
    }

    let mut effective = Map::new();
    if let Ok((raw, 0)) = run_niri(&["-j", "outputs"])
        && let Ok(Value::Object(outputs)) = serde_json::from_str::<Value>(&raw)
    {
        for (connector, data) in outputs {
            let identity = ["make", "model", "serial"]
                .iter()
                .filter_map(|key| data.get(*key).and_then(Value::as_str))
                .filter(|value| !value.trim().is_empty())
                .collect::<Vec<_>>()
                .join(" ");
            let value = overrides
                .get(&connector)
                .or_else(|| overrides.get(&identity))
                .cloned()
                .unwrap_or_else(|| global.clone());
            effective.insert(connector, json!(value));
        }
    }

    Ok(Outcome::ok(json!({
        "global": global,
        "overrides": overrides,
        "effective": effective,
    })))
}

fn get_layout() -> Result<Outcome> {
    let mut result = json!({
        "gaps": 25,
        "center_focused": "never",
        "always_center_single_column": true,
        "empty_workspace_above_first": false,
        "default_column_display": "normal",
        "border": {"enabled": false, "width": 4, "active_color": "#707070", "inactive_color": "#d0d0d0", "urgent_color": "#cc4444"},
        "focus_ring": {"enabled": false, "width": 1, "active_color": "#808080", "inactive_color": "#505050"},
        "shadow": {"enabled": true, "softness": 30, "spread": 5, "offset_x": 0, "offset_y": 5, "color": "#0007"},
        "struts": {"left": 0, "right": 0, "top": 0, "bottom": 0},
        "overview_zoom": 0.75
    });
    let path = resolve_section_file("config.d/20-layout-and-overview.kdl");
    let Ok(content) = fs::read_to_string(path) else {
        return Ok(Outcome::ok(result));
    };
    if let Some(layout) = extract_block(&content, "layout", true) {
        if let Some(value) = numeric_value(&layout, "gaps") {
            result["gaps"] = json!(value as i64);
        }
        if let Some(value) = quoted_value(&layout, "center-focused-column") {
            result["center_focused"] = json!(value);
        }
        if let Some(value) = quoted_value(&layout, "default-column-display") {
            result["default_column_display"] = json!(value);
        }
        result["always_center_single_column"] =
            json!(has_flag(&layout, "always-center-single-column"));
        result["empty_workspace_above_first"] =
            json!(has_flag(&layout, "empty-workspace-above-first"));

        let offset_re = Regex::new(r"(?m)^[ \t]*offset[ \t]+x=([-0-9.]+)[ \t]+y=([-0-9.]+)")?;
        for (section, key) in [
            ("border", "border"),
            ("focus-ring", "focus_ring"),
            ("shadow", "shadow"),
        ] {
            if let Some(block) = extract_block(&layout, section, true) {
                result[key]["enabled"] = json!(!has_flag(&block, "off"));
                if let Some(value) = numeric_value(&block, "width")
                    && result[key].get("width").is_some()
                {
                    result[key]["width"] = json!(value as i64);
                }
                for (kdl, json_key) in [
                    ("active-color", "active_color"),
                    ("inactive-color", "inactive_color"),
                    ("urgent-color", "urgent_color"),
                    ("color", "color"),
                ] {
                    if let Some(value) = quoted_value(&block, kdl)
                        && result[key].get(json_key).is_some()
                    {
                        result[key][json_key] = json!(value);
                    }
                }
                if key == "shadow" {
                    if let Some(value) = numeric_value(&block, "softness") {
                        result[key]["softness"] = json!(value as i64);
                    }
                    if let Some(value) = numeric_value(&block, "spread") {
                        result[key]["spread"] = json!(value as i64);
                    }
                    if let Some(caps) = offset_re.captures(&block) {
                        result[key]["offset_x"] =
                            json!(caps[1].parse::<f64>().unwrap_or(0.0) as i64);
                        result[key]["offset_y"] =
                            json!(caps[2].parse::<f64>().unwrap_or(0.0) as i64);
                    }
                }
            }
        }
        if let Some(struts) = extract_block(&layout, "struts", true) {
            for edge in ["left", "right", "top", "bottom"] {
                if let Some(value) = numeric_value(&struts, edge) {
                    result["struts"][edge] = json!(value as i64);
                }
            }
        }
    }
    if let Some(overview) = extract_block(&content, "overview", true)
        && let Some(value) = numeric_value(&overview, "zoom")
    {
        result["overview_zoom"] = json!(value);
    }
    Ok(Outcome::ok(result))
}

fn animation_defaults(kind: &str) -> Value {
    let (damping, stiffness, epsilon) = match kind {
        "window-close" => (0.18, 300.0, 0.0001),
        "window-movement" => (0.98, 900.0, 0.0001),
        "exit-confirmation-open-close" => (0.6, 500.0, 0.01),
        "overview-open-close" => (1.0, 800.0, 0.0001),
        "recent-windows-close" => (1.0, 800.0, 0.001),
        _ => (0.98, 300.0, 0.0001),
    };
    json!({"mode": "spring", "damping_ratio": damping, "stiffness": stiffness, "epsilon": epsilon})
}

fn get_animations() -> Result<Outcome> {
    let mut types = Map::new();
    for kind in ANIMATION_TYPES {
        types.insert((*kind).into(), animation_defaults(kind));
    }
    let mut result = json!({"enabled": true, "slowdown": 1.0, "types": types});
    let path = resolve_section_file("config.d/60-animations.kdl");
    let Ok(content) = fs::read_to_string(path) else {
        return Ok(Outcome::ok(result));
    };
    let Some(block) = extract_block(&content, "animations", true) else {
        return Ok(Outcome::ok(result));
    };
    result["enabled"] = json!(!has_flag(&block, "off"));
    if let Some(value) = numeric_value(&block, "slowdown") {
        result["slowdown"] = json!(value);
    }
    for kind in ANIMATION_TYPES {
        let Some(type_block) = extract_block(&block, kind, true) else {
            continue;
        };
        let mut settings = animation_defaults(kind);
        if let Some(line) = type_block
            .lines()
            .map(str::trim)
            .find(|line| line.starts_with("spring "))
        {
            for token in line.split_whitespace().skip(1) {
                let Some((parameter, raw_value)) = token.split_once('=') else {
                    continue;
                };
                let key = match parameter {
                    "damping-ratio" => "damping_ratio",
                    "stiffness" => "stiffness",
                    "epsilon" => "epsilon",
                    _ => continue,
                };
                if let Ok(value) = raw_value.parse::<f64>() {
                    settings[key] = json!(value);
                }
            }
        } else if numeric_value(&type_block, "duration-ms").is_some()
            || quoted_value(&type_block, "curve").is_some()
        {
            settings = json!({
                "mode": "easing",
                "duration_ms": numeric_value(&type_block, "duration-ms").unwrap_or(150.0) as i64,
                "curve": quoted_value(&type_block, "curve").unwrap_or_else(|| "ease-out-expo".into()),
                "curve_args": ""
            });
        }
        if has_flag(&type_block, "off") {
            settings["off"] = json!(true);
        }
        result["types"][*kind] = settings;
    }
    Ok(Outcome::ok(result))
}

fn get_window_rules() -> Result<Outcome> {
    let mut result =
        json!({"corner_radius": 16, "clip_to_geometry": true, "inactive_opacity": 0.9});
    let path = resolve_section_file("config.d/30-window-rules.kdl");
    let Ok(content) = fs::read_to_string(path) else {
        return Ok(Outcome::ok(result));
    };
    let regex = Regex::new(r"(?m)^[ \t]*window-rule[ \t]*\{")?;
    for matched in regex.find_iter(&content) {
        let opening = content[matched.start()..matched.end()].rfind('{').unwrap() + matched.start();
        let Some(closing) = matching_brace(&content, opening) else {
            continue;
        };
        let block = &content[opening + 1..closing];
        if block.contains("is-active=false") || block.contains("is-active = false") {
            if let Some(value) = numeric_value(block, "opacity") {
                result["inactive_opacity"] = json!(value);
            }
        } else {
            if let Some(value) = numeric_value(block, "geometry-corner-radius") {
                result["corner_radius"] = json!(value as i64);
            }
            if let Some(value) = bool_line_value(block, "clip-to-geometry") {
                result["clip_to_geometry"] = json!(value);
            }
        }
    }
    Ok(Outcome::ok(result))
}

fn list_cursor_themes() -> Result<Outcome> {
    let mut themes = BTreeSet::new();
    let data_home = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".local/share"));
    for directory in [
        data_home.join("icons"),
        PathBuf::from("/usr/share/icons"),
        home_dir().join(".icons"),
    ] {
        let Ok(entries) = fs::read_dir(directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.join("cursors").is_dir()
                && let Some(name) = path.file_name().and_then(|name| name.to_str())
            {
                themes.insert(name.to_owned());
            }
        }
    }
    Ok(Outcome::ok(json!(themes.into_iter().collect::<Vec<_>>())))
}

fn validate() -> Result<Outcome> {
    let config = root_config();
    if !config.exists() {
        return Ok(Outcome::ok(json!({
            "valid": false,
            "config_path": config.to_string_lossy(),
            "output": "config.kdl not found"
        })));
    }
    let output = Command::new("niri")
        .args(["validate", "-c"])
        .arg(&config)
        .output();
    match output {
        Ok(output) => {
            let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
            text.push_str(&String::from_utf8_lossy(&output.stderr));
            Ok(Outcome::ok(json!({
                "valid": output.status.success(),
                "config_path": config.to_string_lossy(),
                "output": text.trim()
            })))
        }
        Err(error) => Ok(Outcome::ok(json!({
            "valid": false,
            "config_path": config.to_string_lossy(),
            "output": error.to_string()
        }))),
    }
}

fn meaningful_lines(text: &str) -> Vec<String> {
    text.lines()
        .filter(|line| !line.trim().is_empty() && !line.trim_start().starts_with("//"))
        .map(|line| line.trim_end().to_owned())
        .collect()
}

// Match Python's difflib.SequenceMatcher edit ordering for the UI preview.
// A set difference loses moved/repeated lines and can hide a real override.
fn customization_diff_preview(default: &[String], user: &[String]) -> Vec<String> {
    let mut b2j: HashMap<&str, Vec<usize>> = HashMap::new();
    for (j, line) in user.iter().enumerate() {
        b2j.entry(line).or_default().push(j);
    }
    if user.len() >= 200 {
        let popular = user.len() / 100 + 1;
        b2j.retain(|_, positions| positions.len() <= popular);
    }

    let mut queue = vec![(0, default.len(), 0, user.len())];
    let mut matches = Vec::new();
    while let Some((alo, ahi, blo, bhi)) = queue.pop() {
        let (mut best_i, mut best_j, mut best_len) = (alo, blo, 0);
        let mut j2len: HashMap<usize, usize> = HashMap::new();
        for (i, line) in default.iter().enumerate().take(ahi).skip(alo) {
            let mut next = HashMap::new();
            if let Some(positions) = b2j.get(line.as_str()) {
                for &j in positions {
                    if j < blo {
                        continue;
                    }
                    if j >= bhi {
                        break;
                    }
                    let len = j
                        .checked_sub(1)
                        .and_then(|prior| j2len.get(&prior))
                        .copied()
                        .unwrap_or(0)
                        + 1;
                    next.insert(j, len);
                    if len > best_len {
                        (best_i, best_j, best_len) = (i + 1 - len, j + 1 - len, len);
                    }
                }
            }
            j2len = next;
        }
        while best_i > alo && best_j > blo && default[best_i - 1] == user[best_j - 1] {
            best_i -= 1;
            best_j -= 1;
            best_len += 1;
        }
        while best_i + best_len < ahi
            && best_j + best_len < bhi
            && default[best_i + best_len] == user[best_j + best_len]
        {
            best_len += 1;
        }
        if best_len > 0 {
            matches.push((best_i, best_j, best_len));
            if alo < best_i && blo < best_j {
                queue.push((alo, best_i, blo, best_j));
            }
            if best_i + best_len < ahi && best_j + best_len < bhi {
                queue.push((best_i + best_len, ahi, best_j + best_len, bhi));
            }
        }
    }
    matches.sort_unstable();
    matches.push((default.len(), user.len(), 0));
    let (mut ai, mut bj) = (0, 0);
    let mut preview = Vec::new();
    for (i, j, len) in matches {
        for line in &default[ai..i] {
            preview.push(format!("-{line}"));
            if preview.len() == 8 {
                return preview;
            }
        }
        for line in &user[bj..j] {
            preview.push(format!("+{line}"));
            if preview.len() == 8 {
                return preview;
            }
        }
        ai = i + len;
        bj = j + len;
    }
    preview
}

fn defaults_dir(override_path: Option<&Path>) -> Result<PathBuf> {
    if let Some(path) = override_path {
        return Ok(path.to_path_buf());
    }
    if let Some(root) = std::env::var_os("INIR_SHELL_ROOT") {
        let path = PathBuf::from(root).join("defaults/niri");
        if path.is_dir() {
            return Ok(path);
        }
    }

    // The settings UI launches inir-native from an arbitrary process working
    // directory. Resolve the shipped defaults from the binary location before
    // consulting cwd so direct native invocations work in both repo and
    // installed native/bin layouts.
    if let Ok(executable) = std::env::current_exe()
        && let Some(parent) = executable.parent()
    {
        for ancestor in parent.ancestors() {
            let candidate = ancestor.join("defaults/niri");
            if candidate.is_dir() {
                return Ok(candidate);
            }
        }
    }

    let cwd = std::env::current_dir()?;
    let candidate = cwd.join("defaults/niri");
    if candidate.is_dir() {
        return Ok(candidate);
    }
    bail!("defaults_dir_not_found")
}

fn detect_customizations(default_override: Option<&Path>) -> Result<Outcome> {
    let defaults = defaults_dir(default_override)?;
    let config = config_dir();
    let mut files = Vec::new();
    let mut managed = 0usize;
    let mut extra = 0usize;
    let mut generated = 0usize;
    let mut user_extra = 0usize;

    for relative in DEFAULT_NIRI_FILES {
        let user_path = config.join(relative);
        let default_path = defaults.join(relative);
        if !user_path.exists() || !default_path.exists() {
            continue;
        }
        let user = fs::read_to_string(&user_path)?;
        let default = fs::read_to_string(&default_path)?;
        if *relative == "config.d/90-user-extra.kdl" {
            let lines = meaningful_lines(&user);
            if !lines.is_empty() {
                user_extra += 1;
                files.push(json!({
                    "path": relative,
                    "kind": "user-extra",
                    "reason": "User-owned extension file for personal Niri rules.",
                    "preview": lines.iter().take(8).collect::<Vec<_>>(),
                    "line_count": lines.len()
                }));
            }
            continue;
        }
        let user_lines = meaningful_lines(&user);
        let default_lines = meaningful_lines(&default);
        if user_lines == default_lines {
            continue;
        }
        managed += 1;
        let preview = customization_diff_preview(&default_lines, &user_lines);
        files.push(json!({
            "path": relative,
            "kind": "managed-override",
            "reason": "This managed Niri file differs from the shipped iNiR default.",
            "preview": if preview.is_empty() { user_lines.iter().take(8).cloned().collect::<Vec<_>>() } else { preview },
            "line_count": user_lines.len()
        }));
    }

    let default_set = DEFAULT_NIRI_FILES.iter().copied().collect::<HashSet<_>>();
    let config_d = config.join("config.d");
    if let Ok(entries) = fs::read_dir(config_d) {
        let mut paths = entries
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| path.extension().is_some_and(|ext| ext == "kdl"))
            .collect::<Vec<_>>();
        paths.sort();
        for path in paths {
            let relative = path
                .strip_prefix(&config)
                .unwrap_or(&path)
                .to_string_lossy()
                .into_owned();
            if default_set.contains(relative.as_str()) {
                continue;
            }
            let text = fs::read_to_string(&path)?;
            let lines = meaningful_lines(&text);
            if lines.is_empty() {
                continue;
            }
            let expected = relative == "config.d/15-outputs.kdl";
            if expected {
                generated += 1;
            } else {
                extra += 1;
            }
            files.push(json!({
                "path": relative,
                "kind": if expected { "expected-generated" } else { "extra-file" },
                "reason": if expected {
                    "Generated by Niri output settings and expected in customized setups."
                } else {
                    "Additional user config file not shipped by iNiR defaults."
                },
                "preview": lines.iter().take(8).collect::<Vec<_>>(),
                "line_count": lines.len()
            }));
        }
    }

    let actionable = managed + extra;
    Ok(Outcome::ok(json!({
        "customized": actionable > 0,
        "config_dir": config.to_string_lossy(),
        "summary": {
            "managed_override": managed,
            "extra_file": extra,
            "expected_generated": generated,
            "user_extra": user_extra,
            "actionable": actionable,
            "total": files.len()
        },
        "files": files
    })))
}

fn sync_backdrop_shadow(mode: &str) -> Result<Outcome> {
    if mode != "on" && mode != "off" {
        bail!("mode_must_be_on_or_off");
    }
    let path = resolve_section_file("config.d/90-user-extra.kdl");
    let content = fs::read_to_string(&path).unwrap_or_default();
    let pattern = Regex::new(&format!(
        r"(?s)\n?{}.*?{}\n?",
        regex::escape(BACKDROP_SHADOW_OVERRIDE_START),
        regex::escape(BACKDROP_SHADOW_OVERRIDE_END)
    ))?;
    let mut next = pattern.replace_all(&content, "\n").trim_end().to_owned();
    if mode == "on" {
        let block = format!(
            "{BACKDROP_SHADOW_OVERRIDE_START}\noverview {{\n    workspace-shadow {{\n        off\n    }}\n}}\n{BACKDROP_SHADOW_OVERRIDE_END}"
        );
        if next.is_empty() {
            next = format!("{block}\n");
        } else {
            next = format!("{next}\n\n{block}\n");
        }
    } else if !next.is_empty() {
        next.push('\n');
    }
    if next == content {
        return Ok(Outcome::ok(
            json!({"success": true, "file": path.to_string_lossy(), "changed": false}),
        ));
    }
    write_validated(&path, &next)
}

fn sync_cursor_env(theme: Option<&str>, size: Option<&str>) -> Result<()> {
    let env_dir = home_dir().join(".config/environment.d");
    fs::create_dir_all(&env_dir)?;
    let mut target = None;
    for candidate in ["inir.conf", "cursor.conf"] {
        let path = env_dir.join(candidate);
        if let Ok(content) = fs::read_to_string(&path)
            && (content.contains("XCURSOR_THEME=") || content.contains("XCURSOR_SIZE="))
        {
            target = Some(path);
            break;
        }
    }
    let target = target.unwrap_or_else(|| env_dir.join("cursor.conf"));
    let mut lines = fs::read_to_string(&target)
        .unwrap_or_default()
        .lines()
        .map(str::to_owned)
        .collect::<Vec<_>>();
    let mut found_theme = false;
    let mut found_size = false;
    for line in &mut lines {
        if let Some(theme) = theme
            && line.trim_start().starts_with("XCURSOR_THEME=")
        {
            *line = format!("XCURSOR_THEME={theme}");
            found_theme = true;
        }
        if let Some(size) = size
            && line.trim_start().starts_with("XCURSOR_SIZE=")
        {
            *line = format!("XCURSOR_SIZE={size}");
            found_size = true;
        }
    }
    if let Some(theme) = theme {
        if !found_theme {
            lines.push(format!("XCURSOR_THEME={theme}"));
        }
        let _ = Command::new("gsettings")
            .args(["set", "org.gnome.desktop.interface", "cursor-theme", theme])
            .status();
        if theme != "default" && !theme.is_empty() {
            let default_dir = home_dir().join(".local/share/icons/default");
            fs::create_dir_all(&default_dir)?;
            fs::write(
                default_dir.join("index.theme"),
                format!(
                    "[Icon Theme]\nName=Default\nComment=Default cursor theme\nInherits={theme}\n"
                ),
            )?;
        }
    }
    if let Some(size) = size {
        if !found_size {
            lines.push(format!("XCURSOR_SIZE={size}"));
        }
        let _ = Command::new("gsettings")
            .args(["set", "org.gnome.desktop.interface", "cursor-size", size])
            .status();
    }
    fs::write(&target, format!("{}\n", lines.join("\n")))?;
    let mut env = Vec::new();
    if let Some(theme) = theme {
        env.push(format!("XCURSOR_THEME={theme}"));
    }
    if let Some(size) = size {
        env.push(format!("XCURSOR_SIZE={size}"));
    }
    if !env.is_empty() {
        let _ = Command::new("systemctl")
            .args(["--user", "set-environment"])
            .args(env)
            .status();
    }
    Ok(())
}

fn sync_cursor() -> Result<Outcome> {
    let path = resolve_section_file("config.d/10-input-and-cursor.kdl");
    let content = fs::read_to_string(path).unwrap_or_default();
    let cursor = extract_block(&content, "cursor", true).unwrap_or_default();
    let theme = quoted_value(&cursor, "xcursor-theme");
    let size = numeric_value(&cursor, "xcursor-size").map(|value| (value as i64).to_string());
    if theme.is_none() && size.is_none() {
        bail!("no_cursor_theme_or_size");
    }
    sync_cursor_env(theme.as_deref(), size.as_deref())?;
    Ok(Outcome::ok(
        json!({"synced": true, "theme": theme, "size": size.and_then(|value| value.parse::<i64>().ok())}),
    ))
}

fn set_input(key: &str, value: &str) -> Result<Outcome> {
    let path = resolve_section_file("config.d/10-input-and-cursor.kdl");
    let mut content = fs::read_to_string(&path).context("input config file not found")?;
    let mut cursor_sync_theme = None;
    let mut cursor_sync_size = None;

    if !key.contains('.') {
        content = match key {
            "disable-power-key-handling" | "workspace-auto-back-and-forth" => {
                toggle_flag(&content, "input", key, value == "on", true)?
            }
            "warp-mouse-to-focus" if value == "off" => {
                remove_line_in_block(&content, "input", key, true)?
            }
            "warp-mouse-to-focus" => set_line_in_block(
                &content,
                "input",
                key,
                if value == "center-xy" {
                    "mode=\"center-xy\""
                } else if value == "center-xy-always" {
                    "mode=\"center-xy-always\""
                } else {
                    ""
                },
                true,
            )?,
            "focus-follows-mouse" if value == "off" => {
                remove_line_in_block(&content, "input", key, true)?
            }
            "focus-follows-mouse" => set_line_in_block(&content, "input", key, value, true)?,
            "mod-key" | "mod-key-nested" => {
                set_line_in_block(&content, "input", key, &format!("\"{value}\""), true)?
            }
            _ => bail!("unknown_input_key:{key}"),
        };
    } else {
        let (section, property) = key.split_once('.').unwrap();
        match section {
            "keyboard" if ["layout", "variant", "options"].contains(&property) => {
                content = ensure_subsection(&content, "input", "keyboard", true)?;
                let (_, input_start, input_end, _) =
                    find_block_bounds(&content, "input", true).unwrap();
                let input_inner = &content[input_start..input_end];
                let keyboard_with_xkb = ensure_subsection(input_inner, "keyboard", "xkb", true)?;
                let (_, kb_start, kb_end, _) =
                    find_block_bounds(&keyboard_with_xkb, "keyboard", true).unwrap();
                let kb_inner = &keyboard_with_xkb[kb_start..kb_end];
                let next_kb =
                    set_line_in_block(kb_inner, "xkb", property, &format!("\"{value}\""), true)?;
                let next_input = format!(
                    "{}{}{}",
                    &keyboard_with_xkb[..kb_start],
                    next_kb,
                    &keyboard_with_xkb[kb_end..]
                );
                content = format!(
                    "{}{}{}",
                    &content[..input_start],
                    next_input,
                    &content[input_end..]
                );
            }
            "keyboard" if property == "repeat-delay" || property == "repeat-rate" => {
                content = set_nested_line(&content, "input", "keyboard", property, value, true)?;
            }
            "keyboard" if property == "track-layout" => {
                content = set_nested_line(
                    &content,
                    "input",
                    "keyboard",
                    property,
                    &format!("\"{value}\""),
                    true,
                )?;
            }
            "keyboard" if property == "numlock" => {
                content = toggle_nested_flag(
                    &content,
                    "input",
                    "keyboard",
                    "numlock",
                    value == "on",
                    true,
                )?;
            }
            "touchpad" | "mouse" | "trackpoint" => {
                let flag = [
                    "tap",
                    "natural-scroll",
                    "dwt",
                    "dwtp",
                    "drag-lock",
                    "disabled-on-external-mouse",
                    "left-handed",
                    "middle-emulation",
                    "scroll-button-lock",
                ]
                .contains(&property);
                if flag {
                    content = toggle_nested_flag(
                        &content,
                        "input",
                        section,
                        property,
                        value == "on",
                        true,
                    )?;
                } else if [
                    "accel-profile",
                    "tap-button-map",
                    "click-method",
                    "scroll-method",
                ]
                .contains(&property)
                {
                    content = set_nested_line(
                        &content,
                        "input",
                        section,
                        property,
                        &format!("\"{value}\""),
                        true,
                    )?;
                } else if property == "accel-speed" {
                    content = set_nested_line(&content, "input", section, property, value, true)?;
                } else {
                    bail!("unknown_{section}_prop:{property}");
                }
            }
            "cursor" => {
                content = match property {
                    "xcursor-theme" => {
                        cursor_sync_theme = Some(value.to_owned());
                        set_line_in_block(
                            &content,
                            "cursor",
                            property,
                            &format!("\"{value}\""),
                            true,
                        )?
                    }
                    "xcursor-size" => {
                        cursor_sync_size = Some(value.to_owned());
                        set_line_in_block(&content, "cursor", property, value, true)?
                    }
                    "hide-when-typing" => {
                        toggle_flag(&content, "cursor", property, value == "on", true)?
                    }
                    _ => bail!("unknown_cursor_prop:{property}"),
                };
            }
            _ => bail!("unknown_input_subsection:{section}"),
        }
    }
    let outcome = write_validated(&path, &content)?;
    if outcome.code == 0 && (cursor_sync_theme.is_some() || cursor_sync_size.is_some()) {
        sync_cursor_env(cursor_sync_theme.as_deref(), cursor_sync_size.as_deref())?;
    }
    Ok(outcome)
}

fn set_layout(key: &str, value: &str) -> Result<Outcome> {
    let path = resolve_section_file("config.d/20-layout-and-overview.kdl");
    let mut content = fs::read_to_string(&path).context("layout config file not found")?;
    content = match key {
        "gaps" => set_line_in_block(&content, "layout", "gaps", value, true)?,
        "center-focused-column" => {
            set_line_in_block(&content, "layout", key, &format!("\"{value}\""), true)?
        }
        "always-center-single-column" | "empty-workspace-above-first" => {
            toggle_flag(&content, "layout", key, value == "on", true)?
        }
        "default-column-display" => {
            set_line_in_block(&content, "layout", key, &format!("\"{value}\""), true)?
        }
        "overview.zoom" | "overview-zoom" => {
            set_line_in_block(&content, "overview", "zoom", value, true)?
        }
        _ if key.contains('.') => {
            let (section, property) = key.split_once('.').unwrap();
            if property == "enabled" {
                toggle_nested_flag(&content, "layout", section, "off", value != "on", true)?
            } else if ["active-color", "inactive-color", "urgent-color", "color"]
                .contains(&property)
            {
                set_nested_line(
                    &content,
                    "layout",
                    section,
                    property,
                    &format!("\"{value}\""),
                    true,
                )?
            } else if ["width", "softness", "spread"].contains(&property) {
                set_nested_line(&content, "layout", section, property, value, true)?
            } else if section == "shadow" && property == "offset" {
                let rendered = if let Some((x, y)) = value.split_once(',') {
                    format!("x={x} y={y}")
                } else {
                    value.to_owned()
                };
                set_nested_line(&content, "layout", section, property, &rendered, true)?
            } else if section == "struts" && ["left", "right", "top", "bottom"].contains(&property)
            {
                set_nested_line(&content, "layout", section, property, value, true)?
            } else {
                bail!("unknown_layout_sub_prop:{key}");
            }
        }
        _ => bail!("unknown_layout_key:{key}"),
    };
    write_validated(&path, &content)
}

fn set_animations(key: &str, value: &str) -> Result<Outcome> {
    let path = resolve_section_file("config.d/60-animations.kdl");
    let mut content = fs::read_to_string(&path).context("animations config file not found")?;
    if key == "enabled" {
        content = toggle_flag(&content, "animations", "off", value != "on", true)?;
    } else if key == "slowdown" {
        content = set_line_in_block(&content, "animations", "slowdown", value, true)?;
    } else {
        let (kind, property) = key
            .split_once('.')
            .ok_or_else(|| anyhow!("unknown_animations_key:{key}"))?;
        if !ANIMATION_TYPES.contains(&kind) {
            bail!("unknown_animation_type:{kind}");
        }
        if property == "enabled" {
            content = toggle_nested_flag(&content, "animations", kind, "off", value != "on", true)?;
        } else if ["damping-ratio", "stiffness", "epsilon"].contains(&property) {
            content = ensure_subsection(&content, "animations", kind, true)?;
            let (_, anim_start, anim_end, _) =
                find_block_bounds(&content, "animations", true).unwrap();
            let anim_inner = &content[anim_start..anim_end];
            let (_, type_start, type_end, _) = find_block_bounds(anim_inner, kind, true).unwrap();
            let type_inner = &anim_inner[type_start..type_end];
            let spring_re = Regex::new(r"(?m)^([ \t]*)spring(?:[ \t]+([^\n]*))?$")?;
            let next_type = if let Some(caps) = spring_re.captures(type_inner) {
                let indent = caps.get(1).map(|value| value.as_str()).unwrap_or("");
                let params = caps.get(2).map(|value| value.as_str()).unwrap_or("");
                let param_re = Regex::new(&format!(r"{}=[0-9.]+", regex::escape(property)))?;
                let next_params = if param_re.is_match(params) {
                    param_re
                        .replace(params, format!("{property}={value}"))
                        .into_owned()
                } else if params.trim().is_empty() {
                    format!("{property}={value}")
                } else {
                    format!("{} {property}={value}", params.trim())
                };
                spring_re
                    .replace(type_inner, format!("{indent}spring {next_params}"))
                    .into_owned()
            } else {
                set_line_in_inner(
                    type_inner,
                    "spring",
                    &format!("{property}={value}"),
                    "        ",
                )?
            };
            let next_anim = format!(
                "{}{}{}",
                &anim_inner[..type_start],
                next_type,
                &anim_inner[type_end..]
            );
            content = format!(
                "{}{}{}",
                &content[..anim_start],
                next_anim,
                &content[anim_end..]
            );
        } else {
            bail!("unknown_spring_param:{property}");
        }
    }
    write_validated(&path, &content)
}

fn set_window_rules(key: &str, value: &str) -> Result<Outcome> {
    let path = resolve_section_file("config.d/30-window-rules.kdl");
    let mut content = fs::read_to_string(&path).context("window rules config file not found")?;
    match key {
        "corner-radius" => {
            let re = Regex::new(r"geometry-corner-radius[ \t]+[0-9]+")?;
            if re.is_match(&content) {
                content = re
                    .replacen(&content, 1, format!("geometry-corner-radius {value}"))
                    .into_owned();
            } else if let Some((_, start, end, _)) =
                find_block_bounds(&content, "window-rule", true)
            {
                let next = set_line_in_inner(
                    &content[start..end],
                    "geometry-corner-radius",
                    value,
                    "    ",
                )?;
                content = format!("{}{}{}", &content[..start], next, &content[end..]);
            }
        }
        "clip-to-geometry" => {
            let re = Regex::new(r"clip-to-geometry[ \t]+(?:true|false)")?;
            if re.is_match(&content) {
                content = re
                    .replacen(&content, 1, format!("clip-to-geometry {value}"))
                    .into_owned();
            } else if let Some((_, start, end, _)) =
                find_block_bounds(&content, "window-rule", true)
            {
                let next =
                    set_line_in_inner(&content[start..end], "clip-to-geometry", value, "    ")?;
                content = format!("{}{}{}", &content[..start], next, &content[end..]);
            }
        }
        "inactive-opacity" => {
            let rule_re = Regex::new(r"(?m)^[ \t]*window-rule[ \t]*\{")?;
            let mut replaced = false;
            for matched in rule_re.find_iter(&content).collect::<Vec<_>>() {
                let opening =
                    content[matched.start()..matched.end()].rfind('{').unwrap() + matched.start();
                let Some(closing) = matching_brace(&content, opening) else {
                    continue;
                };
                let block = &content[opening + 1..closing];
                if block.contains("is-active=false") || block.contains("is-active = false") {
                    let next = set_line_in_inner(block, "opacity", value, "    ")?;
                    content = format!("{}{}{}", &content[..opening + 1], next, &content[closing..]);
                    replaced = true;
                    break;
                }
            }
            if !replaced {
                content = format!(
                    "{}\n\nwindow-rule {{\n    match is-active=false\n    opacity {value}\n}}\n",
                    content.trim_end()
                );
            }
        }
        _ => bail!("unknown_window_rules_key:{key}"),
    }
    write_validated(&path, &content)
}

fn set_value(section: &str, key: &str, value: &str) -> Result<Outcome> {
    match section {
        "input" => set_input(key, value),
        "layout" => set_layout(key, value),
        "animations" => set_animations(key, value),
        "window-rules" => set_window_rules(key, value),
        "output" => {
            let (name, property) = key
                .split_once('.')
                .ok_or_else(|| anyhow!("output_key_must_be_name_prop"))?;
            persist_output(name, &[format!("{property}={value}")])
        }
        _ => bail!("unknown_section:{section}"),
    }
}

#[path = "keybind_labels.rs"]
mod keybind_labels;
use keybind_labels::{action_category, action_description};

fn get_binds() -> Result<Outcome> {
    let path = resolve_section_file("config.d/70-binds.kdl");
    let content = fs::read_to_string(&path).context("binds file not found")?;
    let (_, inner_start, inner_end, _) = find_block_bounds(&content, "binds", true)
        .ok_or_else(|| anyhow!("binds_block_not_found"))?;
    let block = &content[inner_start..inner_end];
    let base_line = content[..inner_start]
        .bytes()
        .filter(|byte| *byte == b'\n')
        .count()
        + 1;
    let lines = block.lines().collect::<Vec<_>>();
    let bind_re = Regex::new(r"^([A-Za-z0-9_][A-Za-z0-9+_]*)\s*(.*?)\{(.*)$")?;
    let title_re = Regex::new(r#"\s*hotkey-overlay-title="[^"]+""#)?;
    let mut binds = Vec::new();
    let mut i = 0usize;

    while i < lines.len() {
        let raw = lines[i];
        let stripped = raw.trim();
        let (commented, candidate) = if let Some(rest) = stripped.strip_prefix("//") {
            let candidate = rest.trim_start();
            if bind_re.is_match(candidate) {
                (true, candidate)
            } else {
                i += 1;
                continue;
            }
        } else {
            (false, stripped)
        };
        let Some(caps) = bind_re.captures(candidate) else {
            i += 1;
            continue;
        };
        let key_combo = caps[1].to_owned();
        let options_raw = caps[2].trim().to_owned();
        let options = title_re.replace_all(&options_raw, "").trim().to_owned();
        let rest = caps[3].to_owned();
        let line_number = base_line + i;
        let (action_raw, action) = if let Some(close) = rest.find('}') {
            let raw = rest[..close].trim().to_owned();
            let action = raw.trim_end_matches(';').to_owned();
            (raw, action)
        } else {
            i += 1;
            let mut action_lines = Vec::new();
            while i < lines.len() {
                let line = lines[i].trim();
                if line == "}" {
                    break;
                }
                if !line.is_empty() && !line.starts_with("//") {
                    action_lines.push(line);
                }
                i += 1;
            }
            let raw = action_lines.join(" ");
            let action = action_lines
                .iter()
                .map(|line| line.trim_end_matches(';'))
                .collect::<Vec<_>>()
                .join(" ");
            (raw, action)
        };
        let description = action_description(&action);
        let category = action_category(&description, &action);
        binds.push(json!({
            "key_combo": key_combo,
            "options": options,
            "action": action,
            "action_raw": action_raw,
            "category": category,
            "description": description,
            "line_number": line_number,
            "commented": commented
        }));
        i += 1;
    }

    let category_order = [
        "System",
        "iNiR Shell",
        "Window Switcher",
        "Screenshots",
        "Applications",
        "Window Management",
        "Layout",
        "Resize",
        "Focus",
        "Move Windows",
        "Monitors",
        "Workspaces",
        "Media",
        "Brightness",
        "Other",
    ];
    let mut map: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for (index, bind) in binds.iter().enumerate() {
        if let Some(category) = bind.get("category").and_then(Value::as_str) {
            map.entry(category.to_owned()).or_default().push(index);
        }
    }
    let mut categories = Vec::new();
    for category in category_order {
        if let Some(indices) = map.remove(category) {
            categories.push(json!({"name": category, "binds": indices}));
        }
    }
    for (category, indices) in map {
        categories.push(json!({"name": category, "binds": indices}));
    }
    Ok(Outcome::ok(json!({
        "binds": binds,
        "categories": categories,
        "config_file": path.to_string_lossy()
    })))
}

fn find_bind_span(lines: &[String], key_combo: &str, commented: bool) -> Option<(usize, usize)> {
    for (index, raw) in lines.iter().enumerate() {
        let stripped = raw.trim();
        let candidate = if commented {
            stripped.strip_prefix("//")?.trim_start()
        } else {
            if stripped.starts_with("//") {
                continue;
            }
            stripped
        };
        let first = candidate
            .split_whitespace()
            .next()
            .unwrap_or_default()
            .split('{')
            .next()
            .unwrap_or_default();
        if first != key_combo {
            continue;
        }
        let mut depth =
            candidate.matches('{').count() as i32 - candidate.matches('}').count() as i32;
        if depth <= 0 {
            return Some((index, index + 1));
        }
        let mut end = index + 1;
        while end < lines.len() && depth > 0 {
            depth +=
                lines[end].matches('{').count() as i32 - lines[end].matches('}').count() as i32;
            end += 1;
        }
        return Some((index, end));
    }
    None
}

fn set_bind(key_combo: &str, action: &str, options: &str) -> Result<Outcome> {
    let path = resolve_section_file("config.d/70-binds.kdl");
    let content = fs::read_to_string(&path).context("binds file not found")?;
    let (_, inner_start, inner_end, _) = find_block_bounds(&content, "binds", true)
        .ok_or_else(|| anyhow!("binds_block_not_found"))?;
    let block = &content[inner_start..inner_end];
    // Python uses split("\n"), not splitlines()/str::lines(), so the trailing
    // empty element before the closing brace is part of the surgical-edit
    // contract and must be preserved.
    let mut lines = block.split('\n').map(str::to_owned).collect::<Vec<_>>();
    let span = find_bind_span(&lines, key_combo, false)
        .or_else(|| find_bind_span(&lines, key_combo, true));
    let rendered = if options.trim().is_empty() {
        format!("{key_combo} {{ {action}; }}")
    } else {
        format!("{key_combo} {} {{ {action}; }}", options.trim())
    };
    if let Some((start, end)) = span {
        let indent = lines[start]
            .chars()
            .take_while(|value| value.is_whitespace())
            .collect::<String>();
        lines.splice(start..end, [format!("{indent}{rendered}")]);
    } else {
        let insert = lines
            .iter()
            .rposition(|line| !line.trim().is_empty())
            .map_or(0, |index| index + 1);
        lines.insert(insert, format!("    {rendered}"));
        // Match Python: a newly appended bind gets a blank separator before
        // the original trailing blank lines / closing brace.
        lines.insert(insert + 1, String::new());
    }
    let next = format!(
        "{}{}{}",
        &content[..inner_start],
        lines.join("\n"),
        &content[inner_end..]
    );
    write_validated(&path, &next)
}

fn remove_bind(key_combo: &str) -> Result<Outcome> {
    let path = resolve_section_file("config.d/70-binds.kdl");
    let content = fs::read_to_string(&path).context("binds file not found")?;
    let (_, inner_start, inner_end, _) = find_block_bounds(&content, "binds", true)
        .ok_or_else(|| anyhow!("binds_block_not_found"))?;
    let block = &content[inner_start..inner_end];
    let mut lines = block.split('\n').map(str::to_owned).collect::<Vec<_>>();
    let (start, end) = find_bind_span(&lines, key_combo, false)
        .ok_or_else(|| anyhow!("active_bind_not_found:{key_combo}"))?;

    let commented = lines[start..end]
        .iter()
        .map(|line| {
            if line.trim().is_empty() {
                return line.clone();
            }
            let indent = line
                .chars()
                .take_while(|value| value.is_whitespace())
                .collect::<String>();
            format!("{indent}// {}", &line[indent.len()..])
        })
        .collect::<Vec<_>>();

    let mut previous = start.checked_sub(1);
    while let Some(index) = previous {
        if !lines[index].trim().is_empty() {
            break;
        }
        previous = index.checked_sub(1);
    }

    if let Some(index) = previous {
        let trimmed = lines[index].trim();
        if trimmed.starts_with("//") && !trimmed.contains('═') {
            let indent = lines[index]
                .chars()
                .take_while(|value| value.is_whitespace())
                .collect::<String>();
            let doubled = format!("{indent}// {}", &lines[index][indent.len()..]);
            lines.splice(index..end, std::iter::once(doubled).chain(commented));
        } else {
            lines.splice(start..end, commented);
        }
    } else {
        lines.splice(start..end, commented);
    }

    let next = format!(
        "{}{}{}",
        &content[..inner_start],
        lines.join("\n"),
        &content[inner_end..]
    );
    write_validated(&path, &next)
}

#[cfg(test)]
mod tests {
    use super::{extract_block, find_block_bounds, parse_hot_corners, set_line_in_block};

    #[test]
    fn brace_scanner_ignores_comments_and_strings() {
        let text = "layout {\n    // } ignored\n    border { active-color \"#{x}\" }\n}\n";
        let bounds = find_block_bounds(text, "layout", true).unwrap();
        assert_eq!(
            &text[bounds.1..bounds.2],
            "\n    // } ignored\n    border { active-color \"#{x}\" }\n"
        );
    }

    #[test]
    fn surgical_set_preserves_unknown_lines() {
        let text = "layout {\\n    gaps 10\\n    unknown-setting 42\\n}\\n";
        let next = set_line_in_block(text, "layout", "gaps", "25", true).unwrap();
        assert!(next.contains("gaps 25"));
        assert!(next.contains("unknown-setting 42"));
    }

    #[test]
    fn nested_extract_works() {
        let text = "input {\n keyboard { xkb { layout \"us\" } }\n}\n";
        let input = extract_block(text, "input", true).unwrap();
        let keyboard = extract_block(&input, "keyboard", true).unwrap();
        assert!(
            extract_block(&keyboard, "xkb", true)
                .unwrap()
                .contains("layout")
        );
    }

    #[test]
    fn hot_corner_off_is_empty() {
        assert_eq!(parse_hot_corners(Some("\n off\n".into())), Some(Vec::new()));
    }
}
