use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use anyhow::{Context, Result};
use material_color_utils::utils::color_utils::Argb;
use regex::{Captures, Regex};
use serde_json::Value;

use crate::palette::{Palette, build_app_palette, palette_contract, raw_material_palette};

#[derive(Debug, Clone)]
struct TemplateEntry {
    name: String,
    template_path: PathBuf,
    output_path: PathBuf,
}

#[derive(Debug, Clone)]
struct TokenValue {
    dark: String,
    light: String,
    default: String,
}

fn expand_user(path: &str) -> PathBuf {
    if path == "~" {
        return env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(path));
    }
    if let Some(rest) = path.strip_prefix("~/")
        && let Some(home) = env::var_os("HOME")
    {
        return PathBuf::from(home).join(rest);
    }
    PathBuf::from(path)
}

fn absolute_path(path: &Path) -> Result<PathBuf> {
    if path.is_absolute() {
        Ok(path.to_path_buf())
    } else {
        Ok(env::current_dir()?.join(path))
    }
}

fn managed_path(path: &Path) -> Result<PathBuf> {
    let absolute = absolute_path(path)?;
    let text = absolute.to_string_lossy();
    if let Some(stripped) = text.strip_suffix(".tmp") {
        Ok(PathBuf::from(stripped))
    } else {
        Ok(absolute)
    }
}

fn collect_managed_outputs(paths: &[Option<PathBuf>]) -> Result<BTreeSet<PathBuf>> {
    paths
        .iter()
        .filter_map(Option::as_deref)
        .map(managed_path)
        .collect()
}

fn manifest_entries(
    template_dir: &Path,
    managed_outputs: &BTreeSet<PathBuf>,
) -> Result<Vec<TemplateEntry>> {
    let manifest_path = template_dir.join("templates.json");
    let legacy_path = template_dir.join("config.toml");

    if manifest_path.is_file() {
        let value: Value = serde_json::from_str(&fs::read_to_string(&manifest_path)?)?;
        let base = template_dir.join("templates");
        let entries = value
            .get("templates")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|entry| {
                let input = entry.get("input")?.as_str()?;
                let output = entry.get("output")?.as_str()?;
                let output_path = absolute_path(&expand_user(output)).ok()?;
                if managed_outputs.contains(&output_path) {
                    return None;
                }
                Some(TemplateEntry {
                    name: entry
                        .get("name")
                        .and_then(Value::as_str)
                        .unwrap_or("template")
                        .to_owned(),
                    template_path: base.join(input),
                    output_path,
                })
            })
            .collect();
        return Ok(entries);
    }

    if legacy_path.is_file() {
        let value: toml::Value = toml::from_str(&fs::read_to_string(&legacy_path)?)?;
        let mut entries = Vec::new();
        if let Some(templates) = value.get("templates").and_then(toml::Value::as_table) {
            for (name, entry) in templates {
                let Some(table) = entry.as_table() else {
                    continue;
                };
                let Some(input) = table.get("input_path").and_then(toml::Value::as_str) else {
                    continue;
                };
                let Some(output) = table.get("output_path").and_then(toml::Value::as_str) else {
                    continue;
                };
                if input == "/dev/null" || output == "/dev/null" {
                    continue;
                }

                let mut template_path = expand_user(input);
                if !template_path.is_file()
                    && let Some((_, relative)) = input.split_once("/templates/")
                {
                    let candidate = template_dir
                        .join("templates")
                        .join(relative.trim_start_matches('/'));
                    if candidate.is_file() {
                        template_path = candidate;
                    }
                }
                let output_path = absolute_path(&expand_user(output))?;
                if managed_outputs.contains(&output_path) {
                    continue;
                }
                entries.push(TemplateEntry {
                    name: name.clone(),
                    template_path,
                    output_path,
                });
            }
        }
        return Ok(entries);
    }

    eprintln!(
        "[render-templates] Missing {} and {}, skipping template rendering",
        manifest_path.display(),
        legacy_path.display()
    );
    Ok(Vec::new())
}

fn template_palette(
    scheme_seed: Argb,
    source_seed: Argb,
    scheme: &str,
    dark: bool,
    soften: bool,
) -> Palette {
    let mut material = raw_material_palette(scheme_seed, scheme, dark, soften, 1.0);
    material.insert("source_color".into(), source_seed.to_hex());

    let mut contract = palette_contract(&material);
    contract.retain(|key, _| {
        matches!(
            key.as_str(),
            "primary"
                | "on_primary"
                | "primary_container"
                | "on_primary_container"
                | "background"
                | "on_background"
                | "surface"
                | "on_surface"
                | "surface_dim"
                | "surface_bright"
                | "surface_container_lowest"
                | "surface_container_low"
                | "surface_container"
                | "surface_container_high"
                | "surface_container_highest"
                | "on_surface_variant"
                | "outline"
                | "outline_variant"
        )
    });
    material.extend(build_app_palette(&contract));
    material
}

fn camel_to_snake(value: &str) -> String {
    let mut result = String::with_capacity(value.len() + 4);
    let mut previous_lower_or_digit = false;
    for ch in value.chars() {
        if ch.is_ascii_uppercase() {
            if previous_lower_or_digit {
                result.push('_');
            }
            result.push(ch.to_ascii_lowercase());
            previous_lower_or_digit = false;
        } else {
            previous_lower_or_digit = ch.is_ascii_lowercase() || ch.is_ascii_digit();
            result.push(ch);
        }
    }
    result
}

fn token_namespace_from_palettes(
    dark: &Palette,
    light: &Palette,
    dark_mode: bool,
) -> BTreeMap<String, TokenValue> {
    let default = if dark_mode { dark } else { light };
    let mut names = BTreeSet::new();
    names.extend(dark.keys().cloned());
    names.extend(light.keys().cloned());

    let mut result = BTreeMap::new();
    for name in &names {
        let value = TokenValue {
            dark: dark.get(name).cloned().unwrap_or_else(|| "#000000".into()),
            light: light.get(name).cloned().unwrap_or_else(|| "#000000".into()),
            default: default
                .get(name)
                .cloned()
                .unwrap_or_else(|| "#000000".into()),
        };
        result.insert(name.clone(), value);
    }

    // Compatibility templates use snake_case Material role names. Build those
    // aliases after exact app-contract keys so raw camelCase Material roles
    // deterministically win collisions such as onSurface -> on_surface.
    for name in &names {
        let snake = camel_to_snake(name);
        if snake.as_str() != name.as_str() {
            let value = result
                .get(name)
                .cloned()
                .expect("exact template token must exist before aliasing");
            result.insert(snake, value);
        }
    }
    result
}

fn token_namespace(
    scheme_seed: Argb,
    source_seed: Argb,
    scheme: &str,
    dark_mode: bool,
    soften: bool,
    current_material: &Palette,
    current_app_palette: &Palette,
) -> BTreeMap<String, TokenValue> {
    let mut dark = template_palette(scheme_seed, source_seed, scheme, true, soften);
    let mut light = template_palette(scheme_seed, source_seed, scheme, false, soften);

    // Python builds both raw mode palettes, then replaces only the active side
    // with the exact corrected palette exposed by the shell. Mirror that here
    // so opposite-mode template tokens are stable while default/current tokens
    // remain identical to the runtime palette.
    let current = if dark_mode { &mut dark } else { &mut light };
    current.extend(current_material.clone());
    current.insert("source_color".into(), source_seed.to_hex());
    current.extend(current_app_palette.clone());

    token_namespace_from_palettes(&dark, &light, dark_mode)
}

fn rgb_triplet(value: &str) -> Option<String> {
    let value = value.strip_prefix('#')?;
    if value.len() != 6 {
        return None;
    }
    let red = u8::from_str_radix(&value[0..2], 16).ok()?;
    let green = u8::from_str_radix(&value[2..4], 16).ok()?;
    let blue = u8::from_str_radix(&value[4..6], 16).ok()?;
    Some(format!("{red}, {green}, {blue}"))
}

fn resolve_expression(
    whole: &str,
    expression: &str,
    colors: &BTreeMap<String, TokenValue>,
    image: Option<&Path>,
) -> String {
    if expression == "image" {
        return image
            .map(|path| path.to_string_lossy().into_owned())
            .unwrap_or_default();
    }

    let parts: Vec<_> = expression.split('.').collect();
    if parts.len() != 4 || parts[0] != "colors" {
        return whole.to_owned();
    }
    let token = parts[1];
    let mode = parts[2];
    let property = parts[3];

    let Some(token_value) = colors.get(token) else {
        eprintln!("[render-templates] WARNING: unresolved token '{token}' in {whole}");
        return whole.to_owned();
    };
    let hex = match mode {
        "dark" => &token_value.dark,
        "light" => &token_value.light,
        "default" => &token_value.default,
        _ => {
            eprintln!(
                "[render-templates] WARNING: unresolved mode '{mode}' for token '{token}' in {whole}"
            );
            return whole.to_owned();
        }
    };

    match property {
        "hex" => hex.clone(),
        "hex_stripped" => hex.trim_start_matches('#').to_owned(),
        "rgb" => rgb_triplet(hex).unwrap_or_else(|| whole.to_owned()),
        _ => {
            eprintln!(
                "[render-templates] WARNING: unresolved prop '{property}' for token '{token}.{mode}' in {whole}"
            );
            whole.to_owned()
        }
    }
}

static TEMPLATE_TOKEN_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\{\{\s*(.*?)\s*\}\}").expect("template token regex"));

fn render_content(
    content: &str,
    colors: &BTreeMap<String, TokenValue>,
    image: Option<&Path>,
) -> Result<String> {
    Ok(TEMPLATE_TOKEN_RE
        .replace_all(content, |captures: &Captures<'_>| {
            resolve_expression(
                captures.get(0).map_or("", |value| value.as_str()),
                captures.get(1).map_or("", |value| value.as_str()),
                colors,
                image,
            )
        })
        .into_owned())
}

pub struct RenderRequest<'a> {
    pub template_dir: &'a Path,
    pub managed_outputs: &'a [Option<PathBuf>],
    pub scheme_seed: Argb,
    pub source_seed: Argb,
    pub scheme: &'a str,
    pub dark_mode: bool,
    pub soften: bool,
    pub current_material: &'a Palette,
    pub current_app_palette: &'a Palette,
    pub image: Option<&'a Path>,
}

pub fn render_templates(request: RenderRequest<'_>) -> Result<usize> {
    let managed_outputs = collect_managed_outputs(request.managed_outputs)?;
    let entries = manifest_entries(request.template_dir, &managed_outputs)?;
    if entries.is_empty() {
        return Ok(0);
    }

    let colors = token_namespace(
        request.scheme_seed,
        request.source_seed,
        request.scheme,
        request.dark_mode,
        request.soften,
        request.current_material,
        request.current_app_palette,
    );
    let mut rendered_count = 0;

    for entry in entries {
        if !entry.template_path.is_file() {
            eprintln!(
                "[render-templates] Skipping missing template '{}': {}",
                entry.name,
                entry.template_path.display()
            );
            continue;
        }

        let content = fs::read_to_string(&entry.template_path)
            .with_context(|| format!("read template {}", entry.template_path.display()))?;
        let rendered = render_content(&content, &colors, request.image)?;

        if let Some(parent) = entry.output_path.parent() {
            fs::create_dir_all(parent)?;
        }
        if fs::symlink_metadata(&entry.output_path)
            .is_ok_and(|metadata| metadata.file_type().is_symlink())
        {
            eprintln!(
                "[render-templates] Replacing symlink with regular file: {}",
                entry.output_path.display()
            );
            fs::remove_file(&entry.output_path)?;
        }
        let unchanged = fs::read(&entry.output_path)
            .ok()
            .is_some_and(|existing| existing == rendered.as_bytes());
        if !unchanged {
            fs::write(&entry.output_path, rendered).with_context(|| {
                format!("write rendered template {}", entry.output_path.display())
            })?;
        }
        rendered_count += 1;
    }

    if rendered_count > 0 {
        eprintln!("[render-templates] Rendered {rendered_count} template(s)");
    }
    Ok(rendered_count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn camel_case_aliases_match_compatibility_templates() {
        assert_eq!(camel_to_snake("onPrimaryContainer"), "on_primary_container");
        assert_eq!(camel_to_snake("primary"), "primary");
    }

    #[test]
    fn material_snake_aliases_win_app_contract_name_collisions() {
        let dark: Palette = [
            ("onSurface".into(), "#101112".into()),
            ("on_surface".into(), "#303132".into()),
            ("app_on_surface".into(), "#505152".into()),
        ]
        .into_iter()
        .collect();
        let light: Palette = [
            ("onSurface".into(), "#202122".into()),
            ("on_surface".into(), "#404142".into()),
            ("app_on_surface".into(), "#606162".into()),
        ]
        .into_iter()
        .collect();

        let colors = token_namespace_from_palettes(&dark, &light, true);
        let alias = colors.get("on_surface").expect("snake Material alias");
        assert_eq!(alias.dark, "#101112");
        assert_eq!(alias.light, "#202122");
        assert_eq!(alias.default, "#101112");
        assert_eq!(
            colors.get("onSurface").expect("camel Material role").light,
            "#202122"
        );
        assert_eq!(
            colors
                .get("app_on_surface")
                .expect("app-prefixed contract remains distinct")
                .light,
            "#606162"
        );
    }

    #[test]
    fn template_resolver_supports_hex_stripped_rgb_and_image() {
        let colors = [(
            "primary".into(),
            TokenValue {
                dark: "#102030".into(),
                light: "#A0B0C0".into(),
                default: "#102030".into(),
            },
        )]
        .into_iter()
        .collect();
        let rendered = render_content(
            "{{colors.primary.dark.hex}}|{{ colors.primary.light.hex_stripped }}|{{colors.primary.default.rgb}}|{{image}}",
            &colors,
            Some(Path::new("/wall/paper.png")),
        )
        .unwrap();
        assert_eq!(rendered, "#102030|A0B0C0|16, 32, 48|/wall/paper.png");
    }
}
