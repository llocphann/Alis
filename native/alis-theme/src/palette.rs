use std::collections::BTreeMap;

use anyhow::{Result, anyhow};
use material_color_utils::dynamic::color_spec::SpecVersion;
use material_color_utils::dynamic::dynamic_scheme::DynamicScheme;
use material_color_utils::dynamic::material_dynamic_colors::MaterialDynamicColors;
use material_color_utils::dynamic::variant::Variant;
use material_color_utils::hct::Hct;
use material_color_utils::scheme::{
    SchemeContent, SchemeExpressive, SchemeFidelity, SchemeFruitSalad, SchemeMonochrome,
    SchemeNeutral, SchemeRainbow, SchemeTonalSpot, SchemeVibrant,
};
use material_color_utils::utils::color_utils::Argb;
use serde_json::{Map, Value, json};

pub type Palette = BTreeMap<String, String>;

// Hosted Python/Rust parity currently matches materialyoucolor's 2025 dynamic-color
// outputs. Keep this explicit: changing the spec is a user-visible theme migration.
pub const MATERIAL_SPEC: SpecVersion = SpecVersion::Spec2025;

const PALETTE_KEYS: &[(&str, &str)] = &[
    ("primary", "primary"),
    ("on_primary", "onPrimary"),
    ("primary_container", "primaryContainer"),
    ("on_primary_container", "onPrimaryContainer"),
    ("primary_fixed", "primaryFixed"),
    ("primary_fixed_dim", "primaryFixedDim"),
    ("on_primary_fixed", "onPrimaryFixed"),
    ("on_primary_fixed_variant", "onPrimaryFixedVariant"),
    ("secondary", "secondary"),
    ("on_secondary", "onSecondary"),
    ("secondary_container", "secondaryContainer"),
    ("on_secondary_container", "onSecondaryContainer"),
    ("secondary_fixed", "secondaryFixed"),
    ("secondary_fixed_dim", "secondaryFixedDim"),
    ("on_secondary_fixed", "onSecondaryFixed"),
    ("on_secondary_fixed_variant", "onSecondaryFixedVariant"),
    ("tertiary", "tertiary"),
    ("on_tertiary", "onTertiary"),
    ("tertiary_container", "tertiaryContainer"),
    ("on_tertiary_container", "onTertiaryContainer"),
    ("tertiary_fixed", "tertiaryFixed"),
    ("tertiary_fixed_dim", "tertiaryFixedDim"),
    ("on_tertiary_fixed", "onTertiaryFixed"),
    ("on_tertiary_fixed_variant", "onTertiaryFixedVariant"),
    ("error", "error"),
    ("on_error", "onError"),
    ("error_container", "errorContainer"),
    ("on_error_container", "onErrorContainer"),
    ("background", "background"),
    ("on_background", "onBackground"),
    ("surface", "surface"),
    ("on_surface", "onSurface"),
    ("surface_dim", "surfaceDim"),
    ("surface_bright", "surfaceBright"),
    ("surface_variant", "surfaceVariant"),
    ("on_surface_variant", "onSurfaceVariant"),
    ("surface_container_lowest", "surfaceContainerLowest"),
    ("surface_container_low", "surfaceContainerLow"),
    ("surface_container", "surfaceContainer"),
    ("surface_container_high", "surfaceContainerHigh"),
    ("surface_container_highest", "surfaceContainerHighest"),
    ("outline", "outline"),
    ("outline_variant", "outlineVariant"),
    ("inverse_surface", "inverseSurface"),
    ("inverse_on_surface", "inverseOnSurface"),
    ("inverse_primary", "inversePrimary"),
    ("shadow", "shadow"),
    ("scrim", "scrim"),
    ("surface_tint", "surfaceTint"),
    ("success", "success"),
    ("on_success", "onSuccess"),
    ("success_container", "successContainer"),
    ("on_success_container", "onSuccessContainer"),
];

#[derive(Debug, Clone)]
pub struct TerminalSettings {
    pub harmony: f64,
    pub harmonize_threshold: f64,
    pub fg_boost: f64,
    pub saturation: f64,
    pub brightness: f64,
    pub bg_brightness: f64,
    pub soften: bool,
    pub scheme_name: String,
}

pub fn variant_from_name(name: &str) -> Variant {
    match name {
        "scheme-fruit-salad" => Variant::FruitSalad,
        "scheme-expressive" => Variant::Expressive,
        "scheme-monochrome" => Variant::Monochrome,
        "scheme-rainbow" => Variant::Rainbow,
        "scheme-neutral" => Variant::Neutral,
        "scheme-fidelity" => Variant::Fidelity,
        "scheme-content" => Variant::Content,
        "scheme-vibrant" => Variant::Vibrant,
        "scheme-tonal-spot" => Variant::TonalSpot,
        _ => Variant::TonalSpot,
    }
}

pub fn create_scheme(seed: Argb, variant: Variant, dark: bool) -> DynamicScheme {
    let hct = Hct::from_argb(seed);
    match variant {
        Variant::FruitSalad => SchemeFruitSalad::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
        Variant::Expressive => SchemeExpressive::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
        Variant::Monochrome => SchemeMonochrome::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
        Variant::Rainbow => SchemeRainbow::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
        Variant::Neutral => SchemeNeutral::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
        Variant::Fidelity => SchemeFidelity::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
        Variant::Content => SchemeContent::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
        Variant::Vibrant => SchemeVibrant::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
        Variant::TonalSpot | Variant::Cmf => SchemeTonalSpot::builder(hct, dark, 0.0)
            .spec_version(MATERIAL_SPEC)
            .build(),
    }
}

fn snake_to_camel(value: &str) -> String {
    let mut result = String::with_capacity(value.len());
    let mut upper = false;
    for ch in value.chars() {
        if ch == '_' {
            upper = true;
        } else if upper {
            result.extend(ch.to_uppercase());
            upper = false;
        } else {
            result.push(ch);
        }
    }
    result
}

fn adjust_material_color(argb: Argb, scheme_name: &str, soften: bool, color_strength: f64) -> Argb {
    let mut hct = Hct::from_argb(argb);
    if soften
        && !matches!(
            scheme_name,
            "scheme-tonal-spot" | "scheme-neutral" | "scheme-monochrome"
        )
    {
        hct = Hct::new(hct.hue(), hct.chroma() * 0.60, hct.tone());
    }
    if (color_strength - 1.0).abs() > 1e-6 && hct.chroma() > 2.0 {
        hct = Hct::new(
            hct.hue(),
            (hct.chroma() * color_strength).max(0.0),
            hct.tone(),
        );
    }
    hct.to_argb()
}

fn shortest_hue_delta(source: f64, target: f64) -> f64 {
    (target - source + 540.0).rem_euclid(360.0) - 180.0
}

fn surface_theme_anchor(
    palette: &Palette,
    scheme_name: &str,
    theme_seed: Argb,
) -> Option<(f64, f64)> {
    let primary_hex = palette
        .get("primary")
        .or_else(|| palette.get("surfaceTint"))
        .or_else(|| palette.get("primaryContainer"))?;
    let primary = Hct::from_argb(parse_hex(primary_hex).ok()?);
    let seed = Hct::from_argb(theme_seed);

    let (hue, source_chroma) = if seed.chroma() >= 8.0 {
        let shift = (shortest_hue_delta(seed.hue(), primary.hue()) * 0.18).clamp(-8.0, 8.0);
        ((seed.hue() + shift).rem_euclid(360.0), seed.chroma())
    } else {
        (primary.hue(), primary.chroma())
    };

    let chroma = if scheme_name == "scheme-neutral" {
        (source_chroma * 0.45)
            .max(primary.chroma() * 0.45)
            .clamp(14.0, 28.0)
    } else {
        (source_chroma * 0.72)
            .max(primary.chroma() * 0.62)
            .clamp(28.0, 52.0)
    };
    Some((hue, chroma))
}

fn tint_light_surfaces(palette: &mut Palette, scheme_name: &str, theme_seed: Argb) {
    if scheme_name == "scheme-monochrome" {
        return;
    }

    let Some((hue, surface_chroma)) = surface_theme_anchor(palette, scheme_name, theme_seed) else {
        return;
    };

    for (role, tone, scale) in [
        ("background", 77.0, 1.00),
        ("surface", 77.0, 1.00),
        ("surfaceDim", 60.0, 1.08),
        ("surfaceBright", 84.0, 0.90),
        ("surfaceContainerLowest", 81.0, 0.94),
        ("surfaceContainerLow", 73.0, 1.00),
        ("surfaceContainer", 69.0, 1.05),
        ("surfaceContainerHigh", 65.0, 1.10),
        ("surfaceContainerHighest", 61.0, 1.14),
        ("surfaceVariant", 64.0, 1.08),
    ] {
        let chroma = (surface_chroma * scale).clamp(18.0, 56.0);
        palette.insert(role.into(), Hct::new(hue, chroma, tone).to_argb().to_hex());
    }

    let ink_chroma = (surface_chroma * 0.48).clamp(10.0, 26.0);
    for (role, tone, scale) in [
        ("onBackground", 10.0, 0.80),
        ("onSurface", 10.0, 0.80),
        ("onSurfaceVariant", 24.0, 1.00),
        ("outline", 40.0, 0.85),
        ("outlineVariant", 54.0, 0.95),
        ("inverseSurface", 16.0, 0.95),
        ("inverseOnSurface", 88.0, 0.70),
    ] {
        let chroma = (ink_chroma * scale).clamp(6.0, 30.0);
        palette.insert(role.into(), Hct::new(hue, chroma, tone).to_argb().to_hex());
    }
}

pub fn material_palette(
    seed: Argb,
    scheme_name: &str,
    dark: bool,
    soften: bool,
    color_strength: f64,
) -> Palette {
    material_palette_with_policy(seed, scheme_name, dark, soften, color_strength, true)
}

// Compatibility templates need the raw opposite-mode Material palette, exactly
// like Python's _generate_palette(). The active mode is overlaid later with
// the corrected palette that the shell actually displays.
pub fn raw_material_palette(
    seed: Argb,
    scheme_name: &str,
    dark: bool,
    soften: bool,
    color_strength: f64,
) -> Palette {
    material_palette_with_policy(seed, scheme_name, dark, soften, color_strength, false)
}

fn material_palette_with_policy(
    seed: Argb,
    scheme_name: &str,
    dark: bool,
    soften: bool,
    color_strength: f64,
    normalize_accents: bool,
) -> Palette {
    let scheme = create_scheme(seed, variant_from_name(scheme_name), dark);
    let dynamic = MaterialDynamicColors::new_with_spec(MATERIAL_SPEC);
    let mut palette = Palette::new();

    for getter in dynamic.all_dynamic_colors() {
        let Some(color) = getter() else {
            continue;
        };
        let adjusted =
            adjust_material_color(color.get_argb(&scheme), scheme_name, soften, color_strength);
        palette.insert(snake_to_camel(&color.name), adjusted.to_hex());
    }

    // Keep wallpaper accents inside Material's readable tone/chroma band,
    // matching the Python fallback and upstream light-mode behavior.
    if normalize_accents && scheme_name != "scheme-monochrome" {
        for (key, container, on_container, tonal) in [
            (
                "primary",
                "primaryContainer",
                "onPrimaryContainer",
                &scheme.primary_palette,
            ),
            (
                "secondary",
                "secondaryContainer",
                "onSecondaryContainer",
                &scheme.secondary_palette,
            ),
            (
                "tertiary",
                "tertiaryContainer",
                "onTertiaryContainer",
                &scheme.tertiary_palette,
            ),
        ] {
            if let Some(value) = palette.get(key).cloned()
                && let Ok(argb) = parse_hex(&value)
            {
                let tone = Hct::from_argb(argb).tone();
                if dark && !(70.0..=85.0).contains(&tone) {
                    palette.insert(key.into(), tonal.tone(80).to_hex());
                } else if !dark && !(25.0..=50.0).contains(&tone) {
                    palette.insert(key.into(), tonal.tone(40).to_hex());
                }
            }

            if let Some(value) = palette.get(container).cloned()
                && let Ok(argb) = parse_hex(&value)
            {
                let tone = Hct::from_argb(argb).tone();
                if dark && !(20.0..=40.0).contains(&tone) {
                    palette.insert(container.into(), tonal.tone(30).to_hex());
                    palette.insert(on_container.into(), tonal.tone(90).to_hex());
                } else if !dark {
                    palette.insert(container.into(), tonal.tone(82).to_hex());
                    palette.insert(on_container.into(), tonal.tone(10).to_hex());
                }
            }

            if let Some(value) = palette.get(key).cloned()
                && let Ok(argb) = parse_hex(&value)
            {
                let hct = Hct::from_argb(argb);
                if hct.chroma() > 60.0 {
                    palette.insert(
                        key.into(),
                        Hct::new(hct.hue(), 60.0, hct.tone()).to_argb().to_hex(),
                    );
                }
            }

            if key == "primary" {
                for (role, floor) in [(key, 36.0), (container, 24.0)] {
                    if let Some(value) = palette.get(role).cloned()
                        && let Ok(argb) = parse_hex(&value)
                    {
                        let hct = Hct::from_argb(argb);
                        if (4.0..floor).contains(&hct.chroma()) {
                            palette.insert(
                                role.into(),
                                Hct::new(hct.hue(), floor, hct.tone()).to_argb().to_hex(),
                            );
                        }
                    }
                }
            }
        }
    }

    if !dark {
        tint_light_surfaces(&mut palette, scheme_name, seed);
    }

    if dark {
        palette.insert("success".into(), "#B5CCBA".into());
        palette.insert("onSuccess".into(), "#213528".into());
        palette.insert("successContainer".into(), "#374B3E".into());
        palette.insert("onSuccessContainer".into(), "#D1E9D6".into());
    } else {
        palette.insert("success".into(), "#4F6354".into());
        palette.insert("onSuccess".into(), "#FFFFFF".into());
        palette.insert("successContainer".into(), "#D1E8D5".into());
        palette.insert("onSuccessContainer".into(), "#0C1F13".into());
    }
    palette
}

fn get<'a>(palette: &'a Palette, key: &str, fallback: &'a str) -> &'a str {
    palette.get(key).map(String::as_str).unwrap_or(fallback)
}

pub fn palette_contract(material: &Palette) -> Palette {
    PALETTE_KEYS
        .iter()
        .map(|(target, source)| {
            (
                (*target).to_owned(),
                material.get(*source).cloned().unwrap_or_default(),
            )
        })
        .collect()
}

pub fn parse_hex(value: &str) -> Result<Argb> {
    Argb::from_hex(value).map_err(|error| anyhow!("invalid_hex:{value}:{error}"))
}

pub fn mix_hex(a: &str, b: &str, keep_a: f64) -> String {
    let Ok(a) = parse_hex(a) else {
        return a.to_owned();
    };
    let Ok(b) = parse_hex(b) else {
        return a.to_hex();
    };
    let mix = |left: u8, right: u8| -> u8 {
        (f64::from(left) * keep_a + f64::from(right) * (1.0 - keep_a))
            .round_ties_even()
            .clamp(0.0, 255.0) as u8
    };
    Argb::from_rgb(
        mix(a.red(), b.red()),
        mix(a.green(), b.green()),
        mix(a.blue(), b.blue()),
    )
    .to_hex()
}

fn relative_luminance(argb: Argb) -> f64 {
    let linearize = |channel: u8| {
        let value = f64::from(channel) / 255.0;
        if value <= 0.03928 {
            value / 12.92
        } else {
            ((value + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * linearize(argb.red())
        + 0.7152 * linearize(argb.green())
        + 0.0722 * linearize(argb.blue())
}

fn contrast_ratio(foreground: Argb, background: Argb) -> f64 {
    let first = relative_luminance(foreground);
    let second = relative_luminance(background);
    (first.max(second) + 0.05) / (first.min(second) + 0.05)
}

fn find_tone_for_contrast(
    hue: f64,
    chroma: f64,
    start_tone: f64,
    limit_tone: f64,
    background: Argb,
    min_ratio: f64,
    dark: bool,
) -> (Argb, f64, bool, f64) {
    let direction = if dark { 1.0 } else { -1.0 };
    let mut tone = start_tone;
    let max_steps = (((limit_tone - start_tone).abs() / 0.25).ceil() as usize + 2).max(1);
    let initial = Hct::new(hue, chroma, start_tone.clamp(0.0, 100.0)).to_argb();
    let mut best = initial;
    let mut best_tone = start_tone;
    let mut best_ratio = contrast_ratio(initial, background);

    for _ in 0..max_steps {
        let current_tone = tone.clamp(0.0, 100.0);
        let candidate = Hct::new(hue, chroma, current_tone).to_argb();
        let ratio = contrast_ratio(candidate, background);
        if ratio > best_ratio {
            best = candidate;
            best_tone = current_tone;
            best_ratio = ratio;
        }
        if ratio >= min_ratio {
            return (candidate, current_tone, true, ratio);
        }
        if (dark && current_tone >= limit_tone) || (!dark && current_tone <= limit_tone) {
            break;
        }
        tone += direction * 0.25;
        tone = if dark {
            tone.min(limit_tone)
        } else {
            tone.max(limit_tone)
        };
    }
    (best, best_tone, false, best_ratio)
}

pub fn ensure_contrast(foreground: Argb, background: Argb, min_ratio: f64, dark: bool) -> Argb {
    if contrast_ratio(foreground, background) >= min_ratio {
        return foreground;
    }

    let hct = Hct::from_argb(foreground);
    let original_tone = hct.tone();
    let original_chroma = hct.chroma();
    let limit = if dark { 88.0 } else { 20.0 };
    let (best, best_tone, met, best_ratio) = find_tone_for_contrast(
        hct.hue(),
        original_chroma,
        original_tone,
        limit,
        background,
        min_ratio,
        dark,
    );

    let tone_shift = (best_tone - original_tone).abs();
    if tone_shift > 10.0 {
        let boost = 1.0 + 0.4_f64.min((tone_shift - 10.0) / 50.0);
        let chroma = (original_chroma * boost).min(80.0);
        let boosted_same_tone = Hct::new(hct.hue(), chroma, best_tone).to_argb();
        let boosted_ratio = contrast_ratio(boosted_same_tone, background);
        if met && boosted_ratio >= min_ratio {
            return boosted_same_tone;
        }
        let (boosted_best, _, boosted_met, boosted_best_ratio) = find_tone_for_contrast(
            hct.hue(),
            chroma,
            best_tone,
            limit,
            background,
            min_ratio,
            dark,
        );
        if met {
            return if boosted_met { boosted_best } else { best };
        }
        if boosted_best_ratio > best_ratio {
            return boosted_best;
        }
    }
    best
}

pub fn readable_hex(foreground: &str, background: &str, min_ratio: f64) -> String {
    let Ok(foreground) = parse_hex(foreground) else {
        return foreground.to_owned();
    };
    let Ok(background) = parse_hex(background) else {
        return foreground.to_hex();
    };
    let dark = Hct::from_argb(background).tone() < 50.0;
    ensure_contrast(foreground, background, min_ratio, dark).to_hex()
}

pub fn build_app_palette(base: &Palette) -> Palette {
    let layer0 = get(
        base,
        "background",
        base.get("surface").map(String::as_str).unwrap_or("#000000"),
    )
    .to_owned();
    let layer1 = get(base, "surface_container_low", get(base, "surface", &layer0)).to_owned();
    let layer2 = get(base, "surface_container", &layer1).to_owned();
    let layer3 = get(base, "surface_container_high", &layer2).to_owned();
    let layer4 = get(base, "surface_container_highest", &layer3).to_owned();
    let on_surface = get(base, "on_surface", get(base, "on_background", "#FFFFFF")).to_owned();
    let on_surface_variant = get(base, "on_surface_variant", &on_surface).to_owned();
    let primary = get(base, "primary", "#6750A4").to_owned();
    let primary_container = get(base, "primary_container", &primary).to_owned();
    let on_primary = base
        .get("on_primary")
        .cloned()
        .unwrap_or_else(|| readable_hex(&on_surface, &primary, 4.5));
    let outline = get(base, "outline", &on_surface_variant).to_owned();
    let outline_variant = base
        .get("outline_variant")
        .cloned()
        .unwrap_or_else(|| mix_hex(&layer1, &outline, 0.72));

    let on_layer0 = readable_hex(&on_surface, &layer0, 4.5);
    let on_layer1 = readable_hex(&on_surface_variant, &layer1, 4.5);
    let on_layer2 = readable_hex(&on_surface, &layer2, 4.5);
    let on_layer3 = readable_hex(&on_surface, &layer3, 4.5);
    let on_layer4 = readable_hex(&on_surface, &layer4, 4.5);
    let layer1_hover = mix_hex(&layer1, &on_layer1, 0.92);
    let layer1_active = mix_hex(&layer1, &on_layer1, 0.85);
    let layer0_is_light = parse_hex(&layer0)
        .map(|argb| Hct::from_argb(argb).tone() >= 50.0)
        .unwrap_or(false);
    let subtext_seed = mix_hex(&on_layer1, &layer1, 0.75);
    let subtext = if layer0_is_light {
        readable_hex(&subtext_seed, &layer1_active, 4.5)
    } else {
        readable_hex(&subtext_seed, &layer1, 3.0)
    };
    let container_hct = parse_hex(&primary_container)
        .map(Hct::from_argb)
        .unwrap_or_else(|_| Hct::from_argb(parse_hex("#6750A4").expect("valid fallback")));
    let layer0_hct = parse_hex(&layer0)
        .map(Hct::from_argb)
        .unwrap_or_else(|_| Hct::from_argb(parse_hex("#000000").expect("valid fallback")));
    let selection_tone = if layer0_hct.tone() < 50.0 {
        container_hct.tone().max(layer0_hct.tone() + 12.0)
    } else {
        container_hct.tone().min(layer0_hct.tone() - 10.0)
    };
    let selection = Hct::new(
        container_hct.hue(),
        container_hct.chroma().min(20.0),
        selection_tone,
    )
    .to_argb()
    .to_hex();
    let selection_hover = Hct::new(
        container_hct.hue(),
        container_hct.chroma().min(26.0),
        selection_tone,
    )
    .to_argb()
    .to_hex();

    let is_dark = layer0_hct.tone() < 50.0;
    let accent_hue = parse_hex(&primary)
        .map(Hct::from_argb)
        .map(|hct| hct.hue())
        .unwrap_or(270.0);
    let layer0_argb =
        parse_hex(&layer0).unwrap_or_else(|_| parse_hex("#000000").expect("valid fallback"));
    let status = |hue: f64, chroma: f64| -> String {
        let delta = (accent_hue - hue + 180.0).rem_euclid(360.0) - 180.0;
        let shifted_hue = (hue + (delta * 0.25).clamp(-15.0, 15.0)).rem_euclid(360.0);
        let seed = Hct::new(shifted_hue, chroma, if is_dark { 80.0 } else { 40.0 }).to_argb();
        ensure_contrast(seed, layer0_argb, 4.5, is_dark).to_hex()
    };
    let success = status(145.0, 48.0);
    let warning = status(75.0, 56.0);
    let error = base
        .get("error")
        .map(|value| readable_hex(value, &layer0, 4.5))
        .unwrap_or_else(|| status(25.0, 60.0));
    let on_status = layer0.clone();

    let mut app = base.clone();
    let entries = [
        ("background", layer0.clone()),
        ("on_background", on_layer0.clone()),
        ("surface", layer0.clone()),
        ("on_surface", on_layer1.clone()),
        ("surface_dim", layer0.clone()),
        ("surface_bright", layer3.clone()),
        ("surface_container_lowest", layer0.clone()),
        ("surface_container_low", layer1.clone()),
        ("surface_container", layer2.clone()),
        ("surface_container_high", layer3.clone()),
        ("surface_container_highest", layer4.clone()),
        ("outline", outline.clone()),
        ("outline_variant", outline_variant.clone()),
        ("app_background", layer0.clone()),
        ("app_foreground", on_layer0),
        ("app_subtext", subtext),
        ("app_surface", layer1.clone()),
        ("app_surface_hover", layer1_hover),
        ("app_surface_active", layer1_active),
        ("app_surface_elevated", layer2.clone()),
        (
            "app_surface_elevated_hover",
            mix_hex(&layer2, &on_layer2, 0.90),
        ),
        (
            "app_surface_elevated_active",
            mix_hex(&layer2, &on_layer2, 0.80),
        ),
        ("app_surface_popup", layer3.clone()),
        (
            "app_surface_popup_hover",
            mix_hex(&layer3, &on_layer3, 0.90),
        ),
        (
            "app_surface_popup_active",
            mix_hex(&layer3, &on_layer3, 0.80),
        ),
        ("app_on_surface", on_layer1.clone()),
        ("app_on_surface_elevated", on_layer2),
        ("app_on_surface_popup", on_layer3.clone()),
        ("app_on_surface_highest", on_layer4),
        ("app_border", outline),
        ("app_border_subtle", outline_variant),
        ("app_accent", primary.clone()),
        ("app_on_accent", on_primary),
        ("app_accent_container", primary_container),
        ("app_selection", selection.clone()),
        ("app_selection_hover", selection_hover),
        (
            "app_on_selection",
            readable_hex(&on_layer3, &selection, 4.5),
        ),
        ("app_success", success),
        ("app_warning", warning),
        ("app_error", error),
        ("app_on_status", on_status),
        ("app_window_bg", layer0.clone()),
        ("app_view_bg", layer0.clone()),
        ("app_headerbar_bg", layer0.clone()),
        ("app_sidebar_bg", layer0),
        ("app_card_bg", layer1),
        ("app_popover_bg", layer2),
        ("app_dialog_bg", layer3),
        ("app_thumbnail_bg", layer4),
    ];
    for (key, value) in entries {
        app.insert(key.to_owned(), value);
    }
    app
}

fn hue_difference(first: f64, second: f64) -> f64 {
    180.0 - ((first - second).abs() - 180.0).abs()
}

fn rotation_direction(from: f64, to: f64) -> f64 {
    if (to - from).rem_euclid(360.0) <= 180.0 {
        1.0
    } else {
        -1.0
    }
}

fn harmonize(design: Argb, source: Argb, threshold: f64, harmony: f64) -> Argb {
    let design_hct = Hct::from_argb(design);
    let source_hct = Hct::from_argb(source);
    let rotation = (hue_difference(design_hct.hue(), source_hct.hue()) * harmony).min(threshold);
    Hct::new(
        (design_hct.hue() + rotation * rotation_direction(design_hct.hue(), source_hct.hue()))
            .rem_euclid(360.0),
        design_hct.chroma(),
        design_hct.tone(),
    )
    .to_argb()
}

fn boost_chroma_tone(argb: Argb, chroma: f64, tone: f64) -> Argb {
    let hct = Hct::from_argb(argb);
    Hct::new(
        hct.hue(),
        hct.chroma() * chroma,
        (hct.tone() * tone).min(95.0),
    )
    .to_argb()
}

fn ensure_min_chroma(argb: Argb, minimum: f64) -> Argb {
    let hct = Hct::from_argb(argb);
    if hct.chroma() < minimum {
        Hct::new(hct.hue(), minimum, hct.tone()).to_argb()
    } else {
        argb
    }
}

fn interpolate_surface(material: &Palette, brightness: f64) -> String {
    let levels = [
        ("background", 0.0),
        ("surfaceContainerLowest", 0.2),
        ("surfaceContainerLow", 0.4),
        ("surfaceContainer", 0.6),
        ("surfaceContainerHigh", 0.8),
        ("surfaceContainerHighest", 1.0),
    ];
    for (index, (name, level)) in levels.iter().enumerate() {
        if brightness <= *level || index == levels.len() - 1 {
            if index == 0 {
                return get(material, name, "#1A1A1A").to_owned();
            }
            let (previous_name, previous_level) = levels[index - 1];
            let t = if (*level - previous_level).abs() > f64::EPSILON {
                (brightness - previous_level) / (*level - previous_level)
            } else {
                0.0
            };
            let first = parse_hex(get(material, previous_name, "#1A1A1A"))
                .unwrap_or_else(|_| Argb::from_rgb(26, 26, 26));
            let second = parse_hex(get(material, name, "#2A2A2A"))
                .unwrap_or_else(|_| Argb::from_rgb(42, 42, 42));
            let channel = |a: u8, b: u8| {
                (f64::from(a) + (f64::from(b) - f64::from(a)) * t).clamp(0.0, 255.0) as u8
            };
            return Argb::from_rgb(
                channel(first.red(), second.red()),
                channel(first.green(), second.green()),
                channel(first.blue(), second.blue()),
            )
            .to_hex();
        }
    }
    get(material, "surfaceContainerLow", "#1A1A1A").to_owned()
}

pub fn terminal_palette(
    material: &Palette,
    source: Option<&Palette>,
    dark: bool,
    settings: &TerminalSettings,
) -> Palette {
    let Some(source) = source else {
        let mapping = [
            ("term0", "surfaceVariant", "#282828"),
            ("term1", "error", "#CC241D"),
            ("term2", "secondary", "#98971A"),
            ("term3", "tertiary", "#D79921"),
            ("term4", "primary", "#458588"),
            ("term5", "tertiary", "#B16286"),
            ("term6", "secondary", "#689D6A"),
            ("term7", "onSurfaceVariant", "#A89984"),
            ("term8", "outline", "#928374"),
            ("term9", "error", "#FB4934"),
            ("term10", "secondary", "#B8BB26"),
            ("term11", "tertiary", "#FABD2F"),
            ("term12", "primary", "#83A598"),
            ("term13", "tertiary", "#D3869B"),
            ("term14", "secondary", "#8EC07C"),
            ("term15", "onSurface", "#EBDBB2"),
        ];
        return mapping
            .iter()
            .map(|(target, key, fallback)| {
                (
                    (*target).to_owned(),
                    get(material, key, fallback).to_owned(),
                )
            })
            .collect();
    };

    let primary = parse_hex(get(
        material,
        "primaryPaletteKeyColor",
        get(material, "primary", "#6750A4"),
    ))
    .unwrap_or_else(|_| Argb::from_rgb(103, 80, 164));
    let mut result = Palette::new();

    for (name, raw) in source {
        if settings.scheme_name == "monochrome" {
            result.insert(name.clone(), raw.clone());
            continue;
        }
        if name == "term0" {
            result.insert(
                name.clone(),
                interpolate_surface(material, settings.bg_brightness),
            );
            continue;
        }
        if name == "term15" {
            result.insert(
                name.clone(),
                get(material, "onSurface", "#E0E0E0").to_owned(),
            );
            continue;
        }
        if name == "term8" {
            let fallback = if dark {
                interpolate_surface(material, (settings.bg_brightness + 0.45).min(1.0))
            } else {
                interpolate_surface(material, (settings.bg_brightness - 0.45).max(0.0))
            };
            let value = if dark {
                get(material, "outline", &fallback)
            } else {
                get(material, "outlineVariant", &fallback)
            };
            result.insert(name.clone(), value.to_owned());
            continue;
        }

        let Ok(mut color) = parse_hex(raw) else {
            result.insert(name.clone(), raw.clone());
            continue;
        };
        if name == "term7" {
            color = harmonize(
                color,
                primary,
                settings.harmonize_threshold * 0.3,
                settings.harmony * 0.4,
            );
            color = boost_chroma_tone(color, settings.saturation * 1.2, 1.0);
        } else {
            color = harmonize(
                color,
                primary,
                settings.harmonize_threshold * 0.12,
                settings.harmony,
            );
            let mut tone_multiplier =
                1.0 + ((settings.brightness - 0.5) * 0.8 * if dark { 1.0 } else { -1.0 });
            tone_multiplier = (tone_multiplier
                + settings.fg_boost * 0.25 * if dark { 1.0 } else { -1.0 })
            .clamp(0.60, 1.45);
            color = boost_chroma_tone(color, settings.saturation * 2.0, tone_multiplier);
            color = ensure_min_chroma(color, 40.0);
        }

        if settings.soften
            && !matches!(
                settings.scheme_name.as_str(),
                "scheme-tonal-spot" | "scheme-neutral" | "scheme-monochrome"
            )
        {
            color = boost_chroma_tone(color, 0.55, 1.0);
        }
        result.insert(name.clone(), color.to_hex());
    }

    if let Some(background) = result.get("term0").and_then(|value| parse_hex(value).ok()) {
        for name in ["term1", "term2", "term3", "term4", "term5", "term6"] {
            if let Some(value) = result.get(name).cloned()
                && let Ok(color) = parse_hex(&value)
            {
                result.insert(
                    name.into(),
                    ensure_contrast(color, background, 4.5, dark).to_hex(),
                );
            }
        }
        for name in ["term9", "term10", "term11", "term12", "term13", "term14"] {
            if let Some(value) = result.get(name).cloned()
                && let Ok(color) = parse_hex(&value)
            {
                result.insert(
                    name.into(),
                    ensure_contrast(color, background, 3.5, dark).to_hex(),
                );
            }
        }

        // Neutral terminal text follows the terminal background hue and is
        // contrast-checked, preventing faint suggestions/comments in light mode.
        let bg_hct = Hct::from_argb(background);
        let grey_chroma = bg_hct.chroma().min(10.0);
        for (name, start_tone, ratio) in [
            ("term7", if dark { 75.0 } else { 35.0 }, 4.5),
            ("term8", if dark { 60.0 } else { 50.0 }, 3.5),
        ] {
            if result.contains_key(name) {
                let grey = Hct::new(bg_hct.hue(), grey_chroma, start_tone).to_argb();
                result.insert(
                    name.into(),
                    ensure_contrast(grey, background, ratio, dark).to_hex(),
                );
            }
        }
    }
    result
}

pub fn colors_contract(palette: &Palette, terminal: &Palette) -> Palette {
    let mut result = palette.clone();
    result.extend(terminal.clone());
    result
}

pub fn scss_output(
    material: &Palette,
    terminal: &Palette,
    dark: bool,
    transparent: bool,
) -> String {
    let mut output = format!(
        "$darkmode: {};\n$transparent: {};\n",
        if dark { "True" } else { "False" },
        if transparent { "True" } else { "False" }
    );
    for (key, value) in material {
        output.push_str(&format!("${key}: {value};\n"));
    }
    for (key, value) in terminal {
        output.push_str(&format!("${key}: {value};\n"));
    }
    output
}

pub fn palette_to_value(palette: &Palette) -> Value {
    Value::Object(
        palette
            .iter()
            .map(|(key, value)| (key.clone(), json!(value)))
            .collect::<Map<_, _>>(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_scheme_matches_python_tonal_spot_fallback() {
        assert_eq!(variant_from_name("vibrant"), Variant::TonalSpot);
        assert_eq!(variant_from_name("scheme-vibrant"), Variant::Vibrant);
    }

    #[test]
    fn app_palette_keeps_required_surface_contract() {
        let base = [
            ("background", "#101010"),
            ("surface", "#101010"),
            ("surface_container_low", "#181818"),
            ("surface_container", "#202020"),
            ("surface_container_high", "#282828"),
            ("surface_container_highest", "#303030"),
            ("on_surface", "#F5F5F5"),
            ("on_surface_variant", "#D0D0D0"),
            ("primary", "#90CAF9"),
            ("on_primary", "#002A3A"),
            ("primary_container", "#164B60"),
            ("outline", "#909090"),
            ("outline_variant", "#505050"),
        ]
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value.to_owned()))
        .collect();
        let app = build_app_palette(&base);
        for key in [
            "app_background",
            "app_foreground",
            "app_surface",
            "app_surface_elevated",
            "app_surface_popup",
            "app_selection",
            "app_on_selection",
        ] {
            assert!(app.contains_key(key), "missing {key}");
        }
    }

    #[test]
    fn material_spec_matches_python_fallback() {
        assert_eq!(MATERIAL_SPEC, SpecVersion::Spec2025);
    }

    #[test]
    fn scss_boolean_spelling_matches_python_output() {
        let output = scss_output(&Palette::new(), &Palette::new(), true, false);
        assert_eq!(output, "$darkmode: True;\n$transparent: False;\n");
    }

    #[test]
    fn expressive_light_surface_stays_near_theme_seed_hue() {
        let seed = Argb::from_rgb(0x19, 0x8F, 0xA3);
        let material = material_palette(seed, "scheme-expressive", false, false, 1.0);
        let seed_hct = Hct::from_argb(seed);
        let background = Hct::from_argb(parse_hex(material.get("background").unwrap()).unwrap());

        let hue_delta = |a: f64, b: f64| {
            let d = (a - b).abs() % 360.0;
            d.min(360.0 - d)
        };
        assert!(
            hue_delta(seed_hct.hue(), background.hue()) <= 12.0,
            "expressive light surface drifted away from theme seed hue"
        );
    }

    #[test]
    fn light_palette_uses_theme_hue_instead_of_white_surfaces() {
        let material = material_palette(
            Argb::from_rgb(0xB0, 0x00, 0x20),
            "scheme-tonal-spot",
            false,
            false,
            1.0,
        );
        let seed_hct = Hct::from_argb(Argb::from_rgb(0xB0, 0x00, 0x20));
        let background = Hct::from_argb(parse_hex(material.get("background").unwrap()).unwrap());
        let container =
            Hct::from_argb(parse_hex(material.get("surfaceContainer").unwrap()).unwrap());

        assert!(
            background.tone() <= 79.0,
            "light background is still too close to white: {}",
            material.get("background").unwrap()
        );
        assert!(
            background.chroma() >= 28.0,
            "light background lost strong theme hue: {}",
            material.get("background").unwrap()
        );
        assert!(
            container.chroma() >= 28.0,
            "light container lost strong theme hue: {}",
            material.get("surfaceContainer").unwrap()
        );

        let hue_delta = |a: f64, b: f64| {
            let d = (a - b).abs() % 360.0;
            d.min(360.0 - d)
        };
        assert!(
            hue_delta(seed_hct.hue(), background.hue()) <= 12.0,
            "light background no longer follows theme seed hue"
        );

        let on_surface = parse_hex(material.get("onSurface").unwrap()).unwrap();
        let background_argb = parse_hex(material.get("background").unwrap()).unwrap();
        assert!(
            contrast_ratio(on_surface, background_argb) >= 4.5,
            "tinted light background lost readable foreground contrast"
        );
    }

    #[test]
    fn material_keeps_required_dynamic_roles() {
        let material = material_palette(
            Argb::from_rgb(0x41, 0x81, 0xEE),
            "scheme-tonal-spot",
            true,
            false,
            1.0,
        );
        for key in [
            "primary",
            "onPrimary",
            "surface",
            "surfaceContainerLow",
            "primaryPaletteKeyColor",
        ] {
            assert!(material.contains_key(key), "missing {key}");
        }
    }
}
