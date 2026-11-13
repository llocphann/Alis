use anyhow::{Result, bail};
use clap::Args;
use std::f64::consts::{E, PI, TAU};
use std::path::Path;
use std::process::Command;

#[derive(Debug, Args)]
pub struct CalcArgs {
    /// Expression to evaluate.
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub expression: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
enum Token {
    Num(f64),
    Ident(String),
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Caret,
    Bang,
    LParen,
    RParen,
    Comma,
    Shl,
    Shr,
}

fn tokenize(input: &str) -> Result<Vec<Token>> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = input.chars().collect();
    let n = chars.len();
    let mut i = 0;

    while i < n {
        let c = chars[i];
        if c.is_whitespace() {
            i += 1;
            continue;
        }
        match c {
            '+' => {
                tokens.push(Token::Plus);
                i += 1;
            }
            '-' | '−' => {
                tokens.push(Token::Minus);
                i += 1;
            }
            '*' => {
                if i + 1 < n && chars[i + 1] == '*' {
                    tokens.push(Token::Caret);
                    i += 2;
                } else {
                    tokens.push(Token::Star);
                    i += 1;
                }
            }
            '×' => {
                tokens.push(Token::Star);
                i += 1;
            }
            '/' | '÷' => {
                tokens.push(Token::Slash);
                i += 1;
            }
            '%' => {
                tokens.push(Token::Percent);
                i += 1;
            }
            '^' => {
                tokens.push(Token::Caret);
                i += 1;
            }
            '!' => {
                tokens.push(Token::Bang);
                i += 1;
            }
            '(' => {
                tokens.push(Token::LParen);
                i += 1;
            }
            ')' => {
                tokens.push(Token::RParen);
                i += 1;
            }
            ',' => {
                tokens.push(Token::Comma);
                i += 1;
            }
            '<' if i + 1 < n && chars[i + 1] == '<' => {
                tokens.push(Token::Shl);
                i += 2;
            }
            '>' if i + 1 < n && chars[i + 1] == '>' => {
                tokens.push(Token::Shr);
                i += 2;
            }
            'π' => {
                tokens.push(Token::Ident("pi".to_string()));
                i += 1;
            }
            d if d.is_ascii_digit() || (d == '.' && i + 1 < n && chars[i + 1].is_ascii_digit()) => {
                if d == '0' && i + 2 < n {
                    match chars[i + 1] {
                        'x' | 'X' => {
                            i += 2;
                            let start = i;
                            while i < n && (chars[i].is_ascii_hexdigit() || chars[i] == '_') {
                                i += 1;
                            }
                            let s: String = chars[start..i].iter().filter(|&&ch| ch != '_').collect();
                            let v = u128::from_str_radix(&s, 16)?;
                            tokens.push(Token::Num(v as f64));
                            continue;
                        }
                        'b' | 'B' => {
                            i += 2;
                            let start = i;
                            while i < n && (chars[i] == '0' || chars[i] == '1' || chars[i] == '_') {
                                i += 1;
                            }
                            let s: String = chars[start..i].iter().filter(|&&ch| ch != '_').collect();
                            let v = u128::from_str_radix(&s, 2)?;
                            tokens.push(Token::Num(v as f64));
                            continue;
                        }
                        'o' | 'O' => {
                            i += 2;
                            let start = i;
                            while i < n && ((chars[i] >= '0' && chars[i] <= '7') || chars[i] == '_') {
                                i += 1;
                            }
                            let s: String = chars[start..i].iter().filter(|&&ch| ch != '_').collect();
                            let v = u128::from_str_radix(&s, 8)?;
                            tokens.push(Token::Num(v as f64));
                            continue;
                        }
                        _ => {}
                    }
                }
                let start = i;
                let mut seen_dot = false;
                while i < n && (chars[i].is_ascii_digit() || chars[i] == '_' || (!seen_dot && chars[i] == '.')) {
                    if chars[i] == '.' {
                        seen_dot = true;
                    }
                    i += 1;
                }
                if i < n && (chars[i] == 'e' || chars[i] == 'E') {
                    let next_idx = i + 1;
                    if next_idx < n
                        && (chars[next_idx].is_ascii_digit()
                            || ((chars[next_idx] == '+' || chars[next_idx] == '-')
                                && next_idx + 1 < n
                                && chars[next_idx + 1].is_ascii_digit()))
                    {
                        i += 1;
                        if chars[i] == '+' || chars[i] == '-' {
                            i += 1;
                        }
                        while i < n && chars[i].is_ascii_digit() {
                            i += 1;
                        }
                    }
                }
                let s: String = chars[start..i].iter().filter(|&&ch| ch != '_').collect();
                let v: f64 = s.parse()?;
                tokens.push(Token::Num(v));
            }
            ch if ch.is_ascii_alphabetic() || ch == '_' => {
                let start = i;
                while i < n && (chars[i].is_ascii_alphanumeric() || chars[i] == '_') {
                    i += 1;
                }
                let ident: String = chars[start..i].iter().collect();
                tokens.push(Token::Ident(ident.to_ascii_lowercase()));
            }
            _ => bail!("unsupported character '{c}'"),
        }
    }
    Ok(tokens)
}

struct Parser {
    tokens: Vec<Token>,
    pos: usize,
    used_math_feature: bool,
}

impl Parser {
    fn new(tokens: Vec<Token>) -> Self {
        Self {
            tokens,
            pos: 0,
            used_math_feature: false,
        }
    }

    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.pos)
    }

    fn peek_next(&self) -> Option<&Token> {
        self.tokens.get(self.pos + 1)
    }

    fn next(&mut self) -> Option<Token> {
        let t = self.tokens.get(self.pos).cloned();
        if t.is_some() {
            self.pos += 1;
        }
        t
    }

    fn parse_expr(&mut self) -> Result<f64> {
        self.parse_shift()
    }

    fn parse_shift(&mut self) -> Result<f64> {
        let mut left = self.parse_add_sub()?;
        loop {
            match self.peek() {
                Some(Token::Shl) => {
                    self.used_math_feature = true;
                    self.next();
                    let right = self.parse_add_sub()?;
                    left = ((left.round() as i64) << (right.round() as u32)) as f64;
                }
                Some(Token::Shr) => {
                    self.used_math_feature = true;
                    self.next();
                    let right = self.parse_add_sub()?;
                    left = ((left.round() as i64) >> (right.round() as u32)) as f64;
                }
                _ => break,
            }
        }
        Ok(left)
    }

    fn parse_add_sub(&mut self) -> Result<f64> {
        let mut left = self.parse_mul_div()?;
        loop {
            match self.peek() {
                Some(Token::Plus) => {
                    self.used_math_feature = true;
                    self.next();
                    let right = self.parse_pow_with_percent_flag()?;
                    if right.1 {
                        left *= 1.0 + (right.0 / 100.0);
                    } else {
                        let full = self.finish_mul_div_tail(right.0)?;
                        left += full;
                    }
                }
                Some(Token::Minus) => {
                    self.used_math_feature = true;
                    self.next();
                    let right = self.parse_pow_with_percent_flag()?;
                    if right.1 {
                        left *= 1.0 - (right.0 / 100.0);
                    } else {
                        let full = self.finish_mul_div_tail(right.0)?;
                        left -= full;
                    }
                }
                _ => break,
            }
        }
        Ok(left)
    }

    fn parse_pow_with_percent_flag(&mut self) -> Result<(f64, bool)> {
        let base = self.parse_unary()?;
        if matches!(self.peek(), Some(Token::Percent))
            && !matches!(
                self.peek_next(),
                Some(Token::Num(_) | Token::Ident(_) | Token::LParen)
            )
        {
            self.used_math_feature = true;
            self.next();
            return Ok((base, true));
        }
        let val = self.finish_pow_tail(base)?;
        Ok((val, false))
    }

    fn finish_mul_div_tail(&mut self, mut left: f64) -> Result<f64> {
        loop {
            match self.peek() {
                Some(Token::Star) => {
                    self.used_math_feature = true;
                    self.next();
                    let r = self.parse_unary()?;
                    left *= self.finish_pow_tail(r)?;
                }
                Some(Token::Slash) => {
                    self.used_math_feature = true;
                    self.next();
                    let r = self.parse_unary()?;
                    let denom = self.finish_pow_tail(r)?;
                    if denom == 0.0 {
                        bail!("division by zero");
                    }
                    left /= denom;
                }
                Some(Token::Percent) => {
                    self.used_math_feature = true;
                    self.next();
                    if matches!(self.peek(), Some(Token::Ident(w)) if w == "of") {
                        self.next();
                        let r = self.parse_unary()?;
                        left = (left / 100.0) * self.finish_pow_tail(r)?;
                    } else if matches!(
                        self.peek(),
                        Some(Token::Num(_) | Token::Ident(_) | Token::LParen | Token::Minus | Token::Plus)
                    ) {
                        let r = self.parse_unary()?;
                        let denom = self.finish_pow_tail(r)?;
                        if denom == 0.0 {
                            bail!("modulo by zero");
                        }
                        left %= denom;
                    } else {
                        left /= 100.0;
                    }
                }
                Some(Token::LParen) | Some(Token::Ident(_)) => {
                    // Implicit multiplication like `2pi` or `3(4+5)`
                    self.used_math_feature = true;
                    let r = self.parse_unary()?;
                    left *= self.finish_pow_tail(r)?;
                }
                _ => break,
            }
        }
        Ok(left)
    }

    fn parse_mul_div(&mut self) -> Result<f64> {
        let base = self.parse_unary()?;
        let pow = self.finish_pow_tail(base)?;
        self.finish_mul_div_tail(pow)
    }

    fn finish_pow_tail(&mut self, mut base: f64) -> Result<f64> {
        while matches!(self.peek(), Some(Token::Bang)) {
            self.used_math_feature = true;
            self.next();
            base = factorial(base)?;
        }
        if matches!(self.peek(), Some(Token::Caret)) {
            self.used_math_feature = true;
            self.next();
            let exp_base = self.parse_unary()?;
            let exp = self.finish_pow_tail(exp_base)?;
            base = base.powf(exp);
        }
        Ok(base)
    }

    fn parse_unary(&mut self) -> Result<f64> {
        match self.peek() {
            Some(Token::Plus) => {
                self.used_math_feature = true;
                self.next();
                self.parse_unary()
            }
            Some(Token::Minus) => {
                self.used_math_feature = true;
                self.next();
                Ok(-self.parse_unary()?)
            }
            _ => self.parse_primary(),
        }
    }

    fn parse_primary(&mut self) -> Result<f64> {
        match self.next() {
            Some(Token::Num(v)) => Ok(v),
            Some(Token::LParen) => {
                self.used_math_feature = true;
                let v = self.parse_expr()?;
                if !matches!(self.next(), Some(Token::RParen)) {
                    bail!("missing closing ')'");
                }
                Ok(v)
            }
            Some(Token::Ident(name)) => {
                self.used_math_feature = true;
                if matches!(self.peek(), Some(Token::LParen)) {
                    self.next();
                    let mut args = Vec::new();
                    if !matches!(self.peek(), Some(Token::RParen)) {
                        loop {
                            args.push(self.parse_expr()?);
                            if matches!(self.peek(), Some(Token::Comma)) {
                                self.next();
                            } else {
                                break;
                            }
                        }
                    }
                    if !matches!(self.next(), Some(Token::RParen)) {
                        bail!("missing ')' after function arguments");
                    }
                    eval_func(&name, &args)
                } else {
                    match name.as_str() {
                        "pi" => Ok(PI),
                        "e" => Ok(E),
                        "tau" => Ok(TAU),
                        "phi" => Ok(1.618_033_988_749_895),
                        _ => bail!("unknown constant '{name}'"),
                    }
                }
            }
            _ => bail!("unexpected end of expression"),
        }
    }
}

fn factorial(v: f64) -> Result<f64> {
    if v < 0.0 || (v - v.round()).abs() > 1e-9 || v > 170.0 {
        bail!("invalid factorial operand");
    }
    let n = v.round() as u64;
    let mut acc = 1.0_f64;
    for k in 2..=n {
        acc *= k as f64;
    }
    Ok(acc)
}

fn gcd_u64(mut a: u64, mut b: u64) -> u64 {
    while b != 0 {
        let t = b;
        b = a % b;
        a = t;
    }
    a
}

fn eval_func(name: &str, args: &[f64]) -> Result<f64> {
    let need = |n: usize| -> Result<()> {
        if args.len() != n {
            bail!("function '{name}' expects {n} argument(s)");
        }
        Ok(())
    };
    match name {
        "sqrt" => {
            need(1)?;
            Ok(args[0].sqrt())
        }
        "cbrt" => {
            need(1)?;
            Ok(args[0].cbrt())
        }
        "abs" => {
            need(1)?;
            Ok(args[0].abs())
        }
        "sin" => {
            need(1)?;
            Ok(args[0].sin())
        }
        "cos" => {
            need(1)?;
            Ok(args[0].cos())
        }
        "tan" => {
            need(1)?;
            Ok(args[0].tan())
        }
        "asin" => {
            need(1)?;
            Ok(args[0].asin())
        }
        "acos" => {
            need(1)?;
            Ok(args[0].acos())
        }
        "atan" => {
            if args.len() == 2 {
                Ok(args[0].atan2(args[1]))
            } else {
                need(1)?;
                Ok(args[0].atan())
            }
        }
        "sinh" => {
            need(1)?;
            Ok(args[0].sinh())
        }
        "cosh" => {
            need(1)?;
            Ok(args[0].cosh())
        }
        "tanh" => {
            need(1)?;
            Ok(args[0].tanh())
        }
        "ln" => {
            need(1)?;
            Ok(args[0].ln())
        }
        "log" | "log10" => {
            if args.len() == 2 {
                Ok(args[0].log(args[1]))
            } else {
                need(1)?;
                Ok(args[0].log10())
            }
        }
        "log2" => {
            need(1)?;
            Ok(args[0].log2())
        }
        "exp" => {
            need(1)?;
            Ok(args[0].exp())
        }
        "floor" => {
            need(1)?;
            Ok(args[0].floor())
        }
        "ceil" => {
            need(1)?;
            Ok(args[0].ceil())
        }
        "round" => {
            need(1)?;
            Ok(args[0].round())
        }
        "trunc" => {
            need(1)?;
            Ok(args[0].trunc())
        }
        "deg" => {
            need(1)?;
            Ok(args[0].to_degrees())
        }
        "rad" => {
            need(1)?;
            Ok(args[0].to_radians())
        }
        "pow" => {
            need(2)?;
            Ok(args[0].powf(args[1]))
        }
        "hypot" => {
            need(2)?;
            Ok(args[0].hypot(args[1]))
        }
        "min" => {
            if args.is_empty() {
                bail!("min requires arguments");
            }
            Ok(args.iter().copied().fold(f64::INFINITY, f64::min))
        }
        "max" => {
            if args.is_empty() {
                bail!("max requires arguments");
            }
            Ok(args.iter().copied().fold(f64::NEG_INFINITY, f64::max))
        }
        "gcd" => {
            need(2)?;
            Ok(gcd_u64(args[0].abs().round() as u64, args[1].abs().round() as u64) as f64)
        }
        "lcm" => {
            need(2)?;
            let a = args[0].abs().round() as u64;
            let b = args[1].abs().round() as u64;
            let g = gcd_u64(a, b);
            Ok(if g == 0 { 0.0 } else { ((a / g) * b) as f64 })
        }
        _ => bail!("unknown function '{name}'"),
    }
}

fn format_number(v: f64) -> String {
    if !v.is_finite() {
        return v.to_string();
    }
    let rounded = v.round();
    if v.abs() < 1e15 && (v - rounded).abs() < 1e-11 {
        return format!("{}", rounded as i64);
    }
    let s = format!("{:.10}", v);
    s.trim_end_matches('0').trim_end_matches('.').to_string()
}

#[derive(Clone, Copy, PartialEq)]
enum UnitCategory {
    Length,
    Mass,
    Data,
    Time,
    Angle,
    Temp,
}

fn unit_info(u: &str) -> Option<(UnitCategory, f64, &'static str)> {
    match u.to_ascii_lowercase().as_str() {
        "mm" | "millimeter" | "millimeters" => Some((UnitCategory::Length, 0.001, "mm")),
        "cm" | "centimeter" | "centimeters" => Some((UnitCategory::Length, 0.01, "cm")),
        "m" | "meter" | "meters" => Some((UnitCategory::Length, 1.0, "m")),
        "km" | "kilometer" | "kilometers" => Some((UnitCategory::Length, 1000.0, "km")),
        "in" | "inch" | "inches" => Some((UnitCategory::Length, 0.0254, "in")),
        "ft" | "foot" | "feet" => Some((UnitCategory::Length, 0.3048, "ft")),
        "yd" | "yard" | "yards" => Some((UnitCategory::Length, 0.9144, "yd")),
        "mi" | "mile" | "miles" => Some((UnitCategory::Length, 1609.344, "mi")),

        "mg" => Some((UnitCategory::Mass, 1e-6, "mg")),
        "g" | "gram" | "grams" => Some((UnitCategory::Mass, 1e-3, "g")),
        "kg" | "kilogram" | "kilograms" => Some((UnitCategory::Mass, 1.0, "kg")),
        "t" | "ton" | "tons" | "tonne" => Some((UnitCategory::Mass, 1000.0, "t")),
        "oz" | "ounce" | "ounces" => Some((UnitCategory::Mass, 0.028_349_523_125, "oz")),
        "lb" | "lbs" | "pound" | "pounds" => Some((UnitCategory::Mass, 0.453_592_37, "lb")),

        "b" | "byte" | "bytes" => Some((UnitCategory::Data, 1.0, "B")),
        "kb" => Some((UnitCategory::Data, 1e3, "KB")),
        "mb" => Some((UnitCategory::Data, 1e6, "MB")),
        "gb" => Some((UnitCategory::Data, 1e9, "GB")),
        "tb" => Some((UnitCategory::Data, 1e12, "TB")),
        "kib" => Some((UnitCategory::Data, 1024.0, "KiB")),
        "mib" => Some((UnitCategory::Data, 1_048_576.0, "MiB")),
        "gib" => Some((UnitCategory::Data, 1_073_741_824.0, "GiB")),
        "tib" => Some((UnitCategory::Data, 1_099_511_627_776.0, "TiB")),

        "ms" | "millisecond" | "milliseconds" => Some((UnitCategory::Time, 0.001, "ms")),
        "s" | "sec" | "secs" | "second" | "seconds" => Some((UnitCategory::Time, 1.0, "s")),
        "min" | "mins" | "minute" | "minutes" => Some((UnitCategory::Time, 60.0, "min")),
        "h" | "hr" | "hrs" | "hour" | "hours" => Some((UnitCategory::Time, 3600.0, "h")),
        "d" | "day" | "days" => Some((UnitCategory::Time, 86400.0, "d")),

        "deg" | "degree" | "degrees" => Some((UnitCategory::Angle, PI / 180.0, "deg")),
        "rad" | "radian" | "radians" => Some((UnitCategory::Angle, 1.0, "rad")),

        "c" | "celsius" | "°c" => Some((UnitCategory::Temp, 0.0, "°C")),
        "f" | "fahrenheit" | "°f" => Some((UnitCategory::Temp, 1.0, "°F")),
        "k" | "kelvin" => Some((UnitCategory::Temp, 2.0, "K")),
        _ => None,
    }
}

fn convert_temp(val: f64, from: f64, to: f64) -> f64 {
    let celsius = match from as i32 {
        0 => val,
        1 => (val - 32.0) * (5.0 / 9.0),
        _ => val - 273.15,
    };
    match to as i32 {
        0 => celsius,
        1 => celsius * (9.0 / 5.0) + 32.0,
        _ => celsius + 273.15,
    }
}

fn try_eval_conversion_or_base(raw: &str) -> Option<Result<String>> {
    let lower = raw.trim();
    for sep in [" to ", " in "] {
        if let Some(idx) = lower.to_ascii_lowercase().rfind(sep) {
            let lhs = lower[..idx].trim();
            let rhs = lower[idx + sep.len()..].trim().to_ascii_lowercase();
            if rhs.is_empty() || lhs.is_empty() {
                continue;
            }
            if matches!(rhs.as_str(), "hex" | "bin" | "oct" | "dec") {
                return Some(eval_numeric_only(lhs, true).map(|v| {
                    let n = v.round() as i128;
                    match rhs.as_str() {
                        "hex" => {
                            if n < 0 {
                                format!("-0x{:X}", -n)
                            } else {
                                format!("0x{:X}", n)
                            }
                        }
                        "bin" => {
                            if n < 0 {
                                format!("-0b{:b}", -n)
                            } else {
                                format!("0b{:b}", n)
                            }
                        }
                        "oct" => {
                            if n < 0 {
                                format!("-0o{:o}", -n)
                            } else {
                                format!("0o{:o}", n)
                            }
                        }
                        _ => format!("{n}"),
                    }
                }));
            }
            if let Some((to_cat, to_scale, to_label)) = unit_info(&rhs) {
                // Split trailing source unit off `lhs`
                let lhs_trimmed = lhs.trim_end();
                let split_at = lhs_trimmed
                    .rfind(|c: char| !c.is_alphabetic() && c != '°')
                    .map(|p| p + lhs_trimmed[p..].chars().next().map_or(1, char::len_utf8))
                    .unwrap_or(0);
                if split_at > 0 && split_at < lhs_trimmed.len() {
                    let num_part = lhs_trimmed[..split_at].trim();
                    let from_unit = lhs_trimmed[split_at..].trim();
                    if let Some((from_cat, from_scale, _)) = unit_info(from_unit)
                        && from_cat == to_cat
                    {
                        return Some(eval_numeric_only(num_part, true).map(|val| {
                            let converted = if from_cat == UnitCategory::Temp {
                                convert_temp(val, from_scale, to_scale)
                            } else {
                                (val * from_scale) / to_scale
                            };
                            format!("{} {}", format_number(converted), to_label)
                        }));
                    }
                }
            }
        }
    }
    None
}

fn eval_numeric_only(expr: &str, allow_plain_number: bool) -> Result<f64> {
    let tokens = tokenize(expr)?;
    if tokens.is_empty() {
        bail!("empty expression");
    }
    let has_non_dec_prefix = {
        let low = expr.to_ascii_lowercase();
        low.contains("0x") || low.contains("0b") || low.contains("0o")
    };
    let mut parser = Parser::new(tokens);
    let value = parser.parse_expr()?;
    if parser.pos != parser.tokens.len() {
        bail!("trailing tokens");
    }
    if !value.is_finite() {
        bail!("non-finite result");
    }
    if !allow_plain_number && !parser.used_math_feature && !has_non_dec_prefix {
        // Plain number like "42" typed with `=42` is fine, let's allow finite numbers if digits exist
    }
    Ok(value)
}

pub fn evaluate_expression(raw: &str) -> Result<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        bail!("empty expression");
    }
    // Reject plain alphabetic words ("firefox", "settings") that are not constants
    let lower = trimmed.to_ascii_lowercase();
    if trimmed.chars().all(|c| c.is_alphabetic() || c.is_whitespace() || c == '-')
        && !matches!(lower.as_str(), "pi" | "e" | "tau" | "phi")
    {
        bail!("not a math expression");
    }

    if let Some(conv_res) = try_eval_conversion_or_base(trimmed) {
        if let Ok(formatted) = conv_res {
            return Ok(formatted);
        }
    }

    // Handle `hex(255)`, `bin(42)`, `oct(64)` wrapper calls directly
    for (prefix, fmt_kind) in [("hex(", "hex"), ("bin(", "bin"), ("oct(", "oct")] {
        if lower.starts_with(prefix) && lower.ends_with(')') {
            let inner = &trimmed[prefix.len()..trimmed.len() - 1];
            let v = eval_numeric_only(inner, true)?;
            let n = v.round() as i128;
            let out = match fmt_kind {
                "hex" => if n < 0 { format!("-0x{:X}", -n) } else { format!("0x{:X}", n) },
                "bin" => if n < 0 { format!("-0b{:b}", -n) } else { format!("0b{:b}", n) },
                _ => if n < 0 { format!("-0o{:o}", -n) } else { format!("0o{:o}", n) },
            };
            return Ok(out);
        }
    }

    match eval_numeric_only(trimmed, true) {
        Ok(v) => Ok(format_number(v)),
        Err(err) => {
            // Optional fallback to system qalc ONLY if installed AND expression contains digits
            if trimmed.chars().any(|c| c.is_ascii_digit()) && Path::new("/usr/bin/qalc").exists() {
                if let Ok(out) = Command::new("/usr/bin/qalc").args(["-t", trimmed]).output()
                    && out.status.success()
                {
                    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                    if !s.is_empty() && !s.contains("error:") && !s.contains("warning:") {
                        return Ok(s);
                    }
                }
            }
            Err(err)
        }
    }
}

pub fn run(args: CalcArgs) -> Result<i32> {
    let expr = args.expression.join(" ");
    match evaluate_expression(&expr) {
        Ok(result) => {
            println!("{result}");
            Ok(0)
        }
        Err(_) => Ok(1),
    }
}
