.pragma library

// Lightweight pure-JS syntax highlighter replacing KF6 org.kde.syntaxhighlighting.
// Emits safe HTML suitable for QtQuick TextEdit/TextArea with Text.RichText.

const LANGUAGE_LABELS = {
    "": "Plain Text",
    "txt": "Plain Text",
    "text": "Plain Text",
    "plain": "Plain Text",
    "plaintext": "Plain Text",
    "js": "JavaScript",
    "javascript": "JavaScript",
    "mjs": "JavaScript",
    "cjs": "JavaScript",
    "jsx": "JSX",
    "ts": "TypeScript",
    "typescript": "TypeScript",
    "tsx": "TSX",
    "qml": "QML",
    "py": "Python",
    "python": "Python",
    "python3": "Python",
    "rs": "Rust",
    "rust": "Rust",
    "c": "C",
    "h": "C",
    "cpp": "C++",
    "cxx": "C++",
    "cc": "C++",
    "hpp": "C++",
    "cs": "C#",
    "csharp": "C#",
    "go": "Go",
    "golang": "Go",
    "java": "Java",
    "kt": "Kotlin",
    "kotlin": "Kotlin",
    "swift": "Swift",
    "sh": "Shell",
    "bash": "Bash",
    "zsh": "Zsh",
    "fish": "Fish",
    "shell": "Shell",
    "json": "JSON",
    "jsonc": "JSONC",
    "yaml": "YAML",
    "yml": "YAML",
    "toml": "TOML",
    "ini": "INI",
    "kdl": "KDL",
    "nix": "Nix",
    "html": "HTML",
    "xml": "XML",
    "svg": "SVG",
    "css": "CSS",
    "scss": "SCSS",
    "sql": "SQL",
    "md": "Markdown",
    "markdown": "Markdown",
    "diff": "Diff",
    "patch": "Diff",
    "dockerfile": "Dockerfile",
    "docker": "Dockerfile",
    "makefile": "Makefile",
    "make": "Makefile",
    "glsl": "GLSL",
    "frag": "GLSL",
    "vert": "GLSL",
    "lua": "Lua",
    "rb": "Ruby",
    "ruby": "Ruby",
    "php": "PHP",
    "zig": "Zig"
};

const KEYWORDS_BY_FAMILY = {
    c_like: new Set([
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "debugger", "default", "delete", "do", "else", "enum", "export", "extends",
        "false", "finally", "fn", "for", "from", "func", "function", "goto", "if",
        "impl", "import", "in", "instanceof", "interface", "let", "loop", "match",
        "mod", "mut", "namespace", "new", "null", "nullptr", "override", "package",
        "pragma", "private", "property", "protected", "pub", "public", "readonly",
        "ref", "required", "return", "self", "Self", "signal", "sizeof", "static",
        "struct", "super", "switch", "template", "this", "throw", "trait", "true",
        "try", "type", "typedef", "typeof", "undefined", "unsafe", "use", "using",
        "var", "virtual", "void", "where", "while", "yield", "alias", "component",
        "on", "readonly", "bool", "int", "real", "string", "double", "float", "char",
        "u8", "u16", "u32", "u64", "usize", "i8", "i16", "i32", "i64", "isize", "f32", "f64",
        "vec2", "vec3", "vec4", "mat4", "uniform", "layout", "out", "sampler2D"
    ]),
    python: new Set([
        "False", "None", "True", "and", "as", "assert", "async", "await", "break",
        "class", "continue", "def", "del", "elif", "else", "except", "finally",
        "for", "from", "global", "if", "import", "in", "is", "lambda", "match",
        "case", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
        "with", "yield", "self", "cls"
    ]),
    shell: new Set([
        "if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until",
        "do", "done", "in", "function", "local", "export", "readonly", "return",
        "exit", "break", "continue", "set", "unset", "shift", "source", "exec",
        "eval", "true", "false", "declare", "typeset", "trap"
    ]),
    sql: new Set([
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "CREATE", "TABLE", "INDEX", "VIEW", "DROP", "ALTER", "JOIN",
        "LEFT", "RIGHT", "INNER", "OUTER", "ON", "GROUP", "BY", "ORDER", "ASC",
        "DESC", "LIMIT", "OFFSET", "AS", "AND", "OR", "NOT", "NULL", "IS", "IN",
        "DISTINCT", "HAVING", "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END"
    ]),
    nix: new Set([
        "let", "in", "with", "rec", "inherit", "if", "then", "else", "assert",
        "or", "true", "false", "null", "import", "builtins"
    ])
};

function languageDisplayName(rawLang) {
    const key = String(rawLang || "").trim().toLowerCase();
    if (LANGUAGE_LABELS[key])
        return LANGUAGE_LABELS[key];
    return key.length > 0 ? key : "Plain Text";
}

function escapeHtml(text) {
    return String(text || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

function familyFor(rawLang) {
    const l = String(rawLang || "").trim().toLowerCase();
    if (l === "py" || l === "python" || l === "python3") return "python";
    if (l === "sh" || l === "bash" || l === "zsh" || l === "fish" || l === "shell") return "shell";
    if (l === "json" || l === "jsonc") return "json";
    if (l === "yaml" || l === "yml" || l === "toml" || l === "ini") return "config";
    if (l === "html" || l === "xml" || l === "svg") return "markup";
    if (l === "diff" || l === "patch") return "diff";
    if (l === "sql") return "sql";
    if (l === "nix") return "nix";
    if (l === "" || l === "txt" || l === "text" || l === "plain" || l === "plaintext" || l === "md" || l === "markdown")
        return "plain";
    return "c_like";
}

function span(color, text) {
    return `<span style="color:${color};">${escapeHtml(text)}</span>`;
}

function highlightLineDiff(line, palette) {
    if (line.startsWith("+++") || line.startsWith("---"))
        return span(palette.keyword, line);
    if (line.startsWith("+"))
        return span(palette.string, line);
    if (line.startsWith("-"))
        return span(palette.error, line);
    if (line.startsWith("@@"))
        return span(palette.number, line);
    return escapeHtml(line);
}

function highlightMarkup(code, palette) {
    const re = /(<!--[\s\S]*?-->|<\/?[A-Za-z_][\w:-]*|\s+[A-Za-z_][\w:-]*(?==)|"[^"]*"|'[^']*'|\/>|>)/g;
    let out = "";
    let last = 0;
    let m;
    while ((m = re.exec(code)) !== null) {
        if (m.index > last)
            out += escapeHtml(code.slice(last, m.index));
        const tok = m[0];
        if (tok.startsWith("<!--"))
            out += span(palette.comment, tok);
        else if (tok.startsWith("<") || tok === ">" || tok === "/>")
            out += span(palette.keyword, tok);
        else if (tok.startsWith('"') || tok.startsWith("'"))
            out += span(palette.string, tok);
        else
            out += span(palette.number, tok);
        last = re.lastIndex;
    }
    if (last < code.length)
        out += escapeHtml(code.slice(last));
    return out;
}

function highlightCode(source, rawLang, palette) {
    const text = String(source ?? "");
    const colors = {
        keyword: String(palette?.keyword || "#8ab4f8"),
        string: String(palette?.string || "#81c995"),
        number: String(palette?.number || "#f6aea9"),
        comment: String(palette?.comment || "#9aa0a6"),
        type: String(palette?.type || "#c58af9"),
        error: String(palette?.error || "#f28b82"),
        normal: String(palette?.normal || "#e8eaed")
    };

    const fam = familyFor(rawLang);
    if (fam === "plain") {
        return `<pre style="margin:0;white-space:pre;">${escapeHtml(text)}</pre>`;
    }
    if (fam === "diff") {
        const lines = text.split("\n").map(line => highlightLineDiff(line, colors));
        return `<pre style="margin:0;white-space:pre;">${lines.join("\n")}</pre>`;
    }
    if (fam === "markup") {
        return `<pre style="margin:0;white-space:pre;">${highlightMarkup(text, colors)}</pre>`;
    }

    const hashComment = fam === "python" || fam === "shell" || fam === "config" || fam === "nix";
    const slashComment = fam === "c_like" || fam === "json";
    const sqlComment = fam === "sql";

    const keywords = KEYWORDS_BY_FAMILY[fam] || null;
    const parts = [];
    if (slashComment) parts.push("\\/\\*[^*]*\\*+(?:[^/*][^*]*\\*+)*\\/|\\/\\/[^\\n]*");
    if (hashComment) parts.push("#[^\\n]*");
    if (sqlComment) parts.push("--[^\\n]*");
    parts.push('"(?:\\\\.|[^"\\\\])*"');
    parts.push("'(?:\\\\.|[^'\\\\\\n])*'");
    if (fam === "c_like" || fam === "shell") parts.push("`(?:\\\\.|[^`\\\\])*`");
    if (fam === "shell") parts.push("\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?");
    parts.push("\\b0x[0-9a-fA-F_]+\\b|\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b");
    parts.push("\\b[A-Za-z_][A-Za-z0-9_]*\\b");

    const tokenRe = new RegExp(parts.join("|"), "g");
    let out = "";
    let last = 0;
    let m;
    while ((m = tokenRe.exec(text)) !== null) {
        if (m.index > last)
            out += escapeHtml(text.slice(last, m.index));
        const tok = m[0];
        const ch = tok.charAt(0);
        if ((slashComment && (tok.startsWith("//") || tok.startsWith("/*")))
                || (hashComment && ch === "#")
                || (sqlComment && tok.startsWith("--"))) {
            out += span(colors.comment, tok);
        } else if (ch === '"' || ch === "'" || ch === "`") {
            if (fam === "json") {
                const rest = text.slice(tokenRe.lastIndex);
                if (/^\s*:/.test(rest))
                    out += span(colors.keyword, tok);
                else
                    out += span(colors.string, tok);
            } else {
                out += span(colors.string, tok);
            }
        } else if (ch === "$") {
            out += span(colors.type, tok);
        } else if (ch >= "0" && ch <= "9") {
            out += span(colors.number, tok);
        } else if (fam === "json" && (tok === "true" || tok === "false" || tok === "null")) {
            out += span(colors.keyword, tok);
        } else if (fam === "sql" && keywords && keywords.has(tok.toUpperCase())) {
            out += span(colors.keyword, tok);
        } else if (keywords && keywords.has(tok)) {
            out += span(colors.keyword, tok);
        } else if (fam === "config" && /^\s*[=:]/.test(text.slice(tokenRe.lastIndex))) {
            out += span(colors.keyword, tok);
        } else if (ch >= "A" && ch <= "Z" && tok.length > 1) {
            out += span(colors.type, tok);
        } else {
            out += escapeHtml(tok);
        }
        last = tokenRe.lastIndex;
    }
    if (last < text.length)
        out += escapeHtml(text.slice(last));
    return `<pre style="margin:0;white-space:pre;">${out}</pre>`;
}
