use anyhow::Result;
use clap::Args;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Args)]
pub struct TranslateArgs {
    /// Print supported language codes (`auto` first), one per line.
    #[arg(long)]
    pub list_languages: bool,

    /// Source language code (default: `auto`).
    #[arg(short = 's', long, default_value = "auto")]
    pub source: String,

    /// Target language code (default: `en`).
    #[arg(short = 't', long, default_value = "en")]
    pub target: String,

    /// Text to translate.
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub text: Vec<String>,
}

const LANGUAGES: &[&str] = &[
    "auto", "af", "am", "ar", "az", "be", "bg", "bn", "bs", "ca", "ceb", "co", "cs", "cy", "da",
    "de", "el", "en", "eo", "es", "et", "eu", "fa", "fi", "fr", "fy", "ga", "gd", "gl", "gu",
    "ha", "haw", "he", "hi", "hmn", "hr", "ht", "hu", "hy", "id", "ig", "is", "it", "ja", "jv",
    "ka", "kk", "km", "kn", "ko", "ku", "ky", "la", "lb", "lo", "lt", "lv", "mg", "mi", "mk",
    "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl", "no", "ny", "or", "pa", "pl", "ps", "pt",
    "ro", "ru", "rw", "sd", "si", "sk", "sl", "sm", "sn", "so", "sq", "sr", "st", "su", "sv",
    "sw", "ta", "te", "tg", "th", "tk", "tl", "tr", "tt", "ug", "uk", "ur", "uz", "vi", "xh",
    "yi", "yo", "zh-CN", "zh-TW", "zu",
];

const PYTHON_TRANSLATE_SCRIPT: &str = r#"
import json
import sys
import urllib.parse
import urllib.request

src, dst, text = sys.argv[1], sys.argv[2], sys.argv[3]
if not text.strip():
    sys.exit(0)

headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AlisTranslate/1.0"}

try:
    params = urllib.parse.urlencode({
        "client": "gtx",
        "sl": src or "auto",
        "tl": dst or "en",
        "dt": "t",
        "q": text,
    })
    req = urllib.request.Request(
        f"https://translate.googleapis.com/translate_a/single?{params}",
        headers=headers,
    )
    with urllib.request.urlopen(req, timeout=6.0) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))
    if isinstance(data, list) and data and isinstance(data[0], list):
        out = "".join(seg[0] for seg in data[0] if isinstance(seg, list) and seg and isinstance(seg[0], str))
        if out.strip():
            sys.stdout.write(out)
            sys.exit(0)
except Exception:
    pass

try:
    pair_src = "en" if (not src or src == "auto") else src
    params = urllib.parse.urlencode({"q": text, "langpair": f"{pair_src}|{dst or 'en'}"})
    req = urllib.request.Request(
        f"https://api.mymemory.translated.net/get?{params}",
        headers=headers,
    )
    with urllib.request.urlopen(req, timeout=6.0) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))
    out = str((data.get("responseData") or {}).get("translatedText") or "").strip()
    if out:
        sys.stdout.write(out)
        sys.exit(0)
except Exception:
    pass

sys.exit(1)
"#;

pub fn run(args: TranslateArgs) -> Result<i32> {
    if args.list_languages {
        for lang in LANGUAGES {
            println!("{lang}");
        }
        return Ok(0);
    }

    let query = args.text.join(" ");
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Ok(0);
    }

    if let Ok(output) = Command::new("/usr/bin/python3")
        .args([
            "-c",
            PYTHON_TRANSLATE_SCRIPT,
            args.source.trim(),
            args.target.trim(),
            trimmed,
        ])
        .output()
        && output.status.success()
    {
        let translated = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !translated.is_empty() {
            println!("{translated}");
            return Ok(0);
        }
    }

    // Optional fallback to translate-shell (`trans`) if installed
    if Path::new("/usr/bin/trans").exists() {
        if let Ok(output) = Command::new("/usr/bin/trans")
            .args([
                "-b",
                "-no-theme",
                "-no-bidi",
                "-no-ansi",
                "-source",
                args.source.trim(),
                "-target",
                args.target.trim(),
                trimmed,
            ])
            .output()
            && output.status.success()
        {
            let translated = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !translated.is_empty() {
                println!("{translated}");
                return Ok(0);
            }
        }
    }

    Ok(1)
}
