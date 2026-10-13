use std::io::{self, Read, Write};
use std::process::{Command as ProcessCommand, Stdio};
use std::sync::LazyLock;

use anyhow::{Context, Result};
use regex::Regex;

const HTML_PAYLOAD_PREFIX: &[u8] = b"<meta http-equiv=\"content-type\" content=\"text/html";
const HTML_FRAGMENT_MARKER: &[u8] = b"<!--StartFragment-->";

fn is_browser_markup(payload: &[u8]) -> bool {
    payload.starts_with(HTML_PAYLOAD_PREFIX)
        || payload
            .windows(HTML_FRAGMENT_MARKER.len())
            .any(|window| window == HTML_FRAGMENT_MARKER)
}

static META_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^<meta[^>]*>").expect("clipboard meta regex"));
static SCRIPT_STYLE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?is)<(script|style)\b.*?</(?:script|style)>")
        .expect("clipboard script/style regex")
});
static COMMENT_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?s)<!--.*?-->").expect("clipboard comment regex"));
static BR_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)<br\s*/?>").expect("clipboard br regex"));
static BLOCK_END_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)</(?:p|div|li|tr|h[1-6]|blockquote|pre)>").expect("clipboard block-end regex")
});
static IMG_SRC_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"(?i)<img[^>]*\bsrc=["']([^"']+)["'][^>]*>"#).expect("clipboard image regex")
});
static TAG_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"<[^>]+>").expect("clipboard tag regex"));
static TRAILING_SPACE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"[ \t]+\n").expect("clipboard whitespace regex"));
static EXTRA_NEWLINE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\n{3,}").expect("clipboard newline regex"));

fn replace(regex: &Regex, input: &str, replacement: &str) -> String {
    regex.replace_all(input, replacement).into_owned()
}

fn strip_browser_markup(markup: &str) -> String {
    let text = replace(&META_RE, markup, "");
    let text = replace(&SCRIPT_STYLE_RE, &text, "");
    let text = replace(&COMMENT_RE, &text, "");
    let text = replace(&BR_RE, &text, "\n");
    let text = replace(&BLOCK_END_RE, &text, "\n");
    let text = replace(&IMG_SRC_RE, &text, "$1");
    let text = replace(&TAG_RE, &text, "");
    let text = html_escape::decode_html_entities(&text).into_owned();
    let text = replace(&TRAILING_SPACE_RE, &text, "\n");
    replace(&EXTRA_NEWLINE_RE, &text, "\n\n").trim().to_owned()
}

fn sanitize_payload(payload: Vec<u8>) -> Vec<u8> {
    if !is_browser_markup(&payload) {
        return payload;
    }
    strip_browser_markup(&String::from_utf8_lossy(&payload)).into_bytes()
}

fn store_with_cliphist(payload: &[u8]) -> Result<i32> {
    let mut child = ProcessCommand::new("cliphist")
        .arg("store")
        .stdin(Stdio::piped())
        .spawn()
        .context("failed to start cliphist store")?;

    child
        .stdin
        .take()
        .context("cliphist stdin was not piped")?
        .write_all(payload)
        .context("failed to write clipboard payload to cliphist")?;

    let status = child.wait().context("failed to wait for cliphist store")?;
    Ok(status.code().unwrap_or(1))
}

pub fn run(filter: bool) -> Result<i32> {
    let mut payload = Vec::new();
    io::stdin()
        .read_to_end(&mut payload)
        .context("failed to read clipboard payload")?;
    let payload = sanitize_payload(payload);

    if payload.is_empty() {
        return Ok(0);
    }

    if filter {
        io::stdout()
            .write_all(&payload)
            .context("failed to write filtered clipboard payload")?;
        return Ok(0);
    }

    store_with_cliphist(&payload)
}

#[cfg(test)]
mod tests {
    use super::{is_browser_markup, sanitize_payload, strip_browser_markup};

    #[test]
    fn plain_text_is_byte_for_byte_passthrough() {
        let input = b"alpha <div>literal source</div>\n".to_vec();
        assert!(!is_browser_markup(&input));
        assert_eq!(sanitize_payload(input.clone()), input);
    }

    #[test]
    fn firefox_html_payload_is_sanitized() {
        let input = r#"<meta http-equiv="content-type" content="text/html; charset=utf-8"><div>Hello&nbsp;world</div><div>Next</div>"#;
        assert_eq!(strip_browser_markup(input), "Hello\u{00a0}world\nNext");
    }

    #[test]
    fn chromium_fragment_removes_wrapper_and_preserves_lines() {
        let input =
            r#"<!--StartFragment--><p>One<br>Two</p><script>bad()</script><!--EndFragment-->"#;
        assert_eq!(strip_browser_markup(input), "One\nTwo");
    }

    #[test]
    fn image_only_markup_keeps_source() {
        let input = r#"<!--StartFragment--><img alt="x" src="https://example.test/a.png"><!--EndFragment-->"#;
        assert_eq!(strip_browser_markup(input), "https://example.test/a.png");
    }
}
