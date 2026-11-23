use std::collections::VecDeque;
use std::env;
use std::io::{Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::net::UnixStream;
use std::sync::Arc;

use anyhow::{Context, Result, anyhow, bail};

pub const MSG_METHOD_CALL: u8 = 1;
pub const MSG_METHOD_RETURN: u8 = 2;
pub const MSG_ERROR: u8 = 3;
pub const MSG_SIGNAL: u8 = 4;

pub const HDR_PATH: u8 = 1;
pub const HDR_INTERFACE: u8 = 2;
pub const HDR_MEMBER: u8 = 3;
pub const HDR_ERROR_NAME: u8 = 4;
pub const HDR_REPLY_SERIAL: u8 = 5;
pub const HDR_DESTINATION: u8 = 6;
pub const HDR_SENDER: u8 = 7;
pub const HDR_SIGNATURE: u8 = 8;
pub const HDR_UNIX_FDS: u8 = 9;

#[derive(Debug, Clone, PartialEq)]
pub enum DBusValue {
    Byte(u8),
    Bool(bool),
    Int16(i16),
    Uint16(u16),
    Int32(i32),
    Uint32(u32),
    Int64(i64),
    Uint64(u64),
    Double(f64),
    String(String),
    ObjectPath(String),
    Signature(String),
    Variant(String, Box<DBusValue>),
    Array(String, Vec<DBusValue>),
    Struct(Vec<DBusValue>),
    Dict(String, String, Vec<(DBusValue, DBusValue)>),
}

impl DBusValue {
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Self::String(s) | Self::ObjectPath(s) | Self::Signature(s) => Some(s),
            Self::Variant(_, inner) => inner.as_str(),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Self::Bool(b) => Some(*b),
            Self::Variant(_, inner) => inner.as_bool(),
            _ => None,
        }
    }

    pub fn as_u32(&self) -> Option<u32> {
        match self {
            Self::Uint32(v) => Some(*v),
            Self::Variant(_, inner) => inner.as_u32(),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Self::Int64(v) => Some(*v),
            Self::Int32(v) => Some(*v as i64),
            Self::Variant(_, inner) => inner.as_i64(),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Self::Double(v) => Some(*v),
            Self::Variant(_, inner) => inner.as_f64(),
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct DBusMessage {
    pub msg_type: u8,
    pub flags: u8,
    pub serial: u32,
    pub path: Option<String>,
    pub interface: Option<String>,
    pub member: Option<String>,
    pub error_name: Option<String>,
    pub reply_serial: Option<u32>,
    pub destination: Option<String>,
    pub sender: Option<String>,
    pub signature: String,
    pub body: Vec<DBusValue>,
    pub fds: Vec<Arc<OwnedFd>>,
}

fn align_up(pos: usize, align: usize) -> usize {
    if align <= 1 {
        return pos;
    }
    (pos + align - 1) & !(align - 1)
}

fn sig_alignment(sig: &str) -> usize {
    match sig.as_bytes().first().copied() {
        Some(b'y') | Some(b'g') | Some(b'v') => 1,
        Some(b'n') | Some(b'q') => 2,
        Some(b'b') | Some(b'i') | Some(b'u') | Some(b's') | Some(b'o') | Some(b'a') | Some(b'h') => 4,
        Some(b'x') | Some(b't') | Some(b'd') | Some(b'(') | Some(b'{') => 8,
        _ => 1,
    }
}

fn split_one_type(sig: &str) -> Result<(&str, &str)> {
    let bytes = sig.as_bytes();
    if bytes.is_empty() {
        bail!("empty D-Bus signature");
    }
    match bytes[0] {
        b'y' | b'b' | b'n' | b'q' | b'i' | b'u' | b'x' | b't' | b'd' | b's' | b'o' | b'g'
        | b'v' | b'h' => Ok((&sig[..1], &sig[1..])),
        b'a' => {
            let (elem, rest) = split_one_type(&sig[1..])?;
            let total = 1 + elem.len();
            Ok((&sig[..total], rest))
        }
        b'(' | b'{' => {
            let open = bytes[0];
            let close = if open == b'(' { b')' } else { b'}' };
            let mut depth = 0usize;
            for (idx, &b) in bytes.iter().enumerate() {
                if b == open {
                    depth += 1;
                } else if b == close {
                    depth -= 1;
                    if depth == 0 {
                        return Ok((&sig[..=idx], &sig[idx + 1..]));
                    }
                }
            }
            bail!("unterminated container in D-Bus signature: {sig}");
        }
        other => bail!("unsupported D-Bus signature byte: {}", other as char),
    }
}

fn pad(buf: &mut Vec<u8>, align: usize) {
    let target = align_up(buf.len(), align);
    buf.resize(target, 0);
}

pub fn marshal_value(buf: &mut Vec<u8>, val: &DBusValue) -> Result<()> {
    match val {
        DBusValue::Byte(v) => buf.push(*v),
        DBusValue::Bool(v) => {
            pad(buf, 4);
            buf.extend_from_slice(&(if *v { 1u32 } else { 0u32 }).to_le_bytes());
        }
        DBusValue::Int16(v) => {
            pad(buf, 2);
            buf.extend_from_slice(&v.to_le_bytes());
        }
        DBusValue::Uint16(v) => {
            pad(buf, 2);
            buf.extend_from_slice(&v.to_le_bytes());
        }
        DBusValue::Int32(v) => {
            pad(buf, 4);
            buf.extend_from_slice(&v.to_le_bytes());
        }
        DBusValue::Uint32(v) => {
            pad(buf, 4);
            buf.extend_from_slice(&v.to_le_bytes());
        }
        DBusValue::Int64(v) => {
            pad(buf, 8);
            buf.extend_from_slice(&v.to_le_bytes());
        }
        DBusValue::Uint64(v) => {
            pad(buf, 8);
            buf.extend_from_slice(&v.to_le_bytes());
        }
        DBusValue::Double(v) => {
            pad(buf, 8);
            buf.extend_from_slice(&v.to_le_bytes());
        }
        DBusValue::String(s) | DBusValue::ObjectPath(s) => {
            pad(buf, 4);
            let bytes = s.as_bytes();
            buf.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
            buf.extend_from_slice(bytes);
            buf.push(0);
        }
        DBusValue::Signature(s) => {
            let bytes = s.as_bytes();
            buf.push(bytes.len() as u8);
            buf.extend_from_slice(bytes);
            buf.push(0);
        }
        DBusValue::Variant(sig, inner) => {
            let sig_bytes = sig.as_bytes();
            buf.push(sig_bytes.len() as u8);
            buf.extend_from_slice(sig_bytes);
            buf.push(0);
            marshal_value(buf, inner)?;
        }
        DBusValue::Array(elem_sig, items) => {
            pad(buf, 4);
            let len_pos = buf.len();
            buf.extend_from_slice(&0u32.to_le_bytes());
            pad(buf, sig_alignment(elem_sig));
            let start = buf.len();
            for item in items {
                marshal_value(buf, item)?;
            }
            let byte_len = (buf.len() - start) as u32;
            buf[len_pos..len_pos + 4].copy_from_slice(&byte_len.to_le_bytes());
        }
        DBusValue::Struct(fields) => {
            pad(buf, 8);
            for f in fields {
                marshal_value(buf, f)?;
            }
        }
        DBusValue::Dict(_, _, entries) => {
            pad(buf, 4);
            let len_pos = buf.len();
            buf.extend_from_slice(&0u32.to_le_bytes());
            pad(buf, 8);
            let start = buf.len();
            for (k, v) in entries {
                pad(buf, 8);
                marshal_value(buf, k)?;
                marshal_value(buf, v)?;
            }
            let byte_len = (buf.len() - start) as u32;
            buf[len_pos..len_pos + 4].copy_from_slice(&byte_len.to_le_bytes());
        }
    }
    Ok(())
}

struct Unmarshaller<'a> {
    data: &'a [u8],
    pos: usize,
    le: bool,
}

impl<'a> Unmarshaller<'a> {
    fn new(data: &'a [u8], le: bool) -> Self {
        Self { data, pos: 0, le }
    }

    fn align(&mut self, a: usize) -> Result<()> {
        let next = align_up(self.pos, a);
        if next > self.data.len() {
            bail!("D-Bus align underflow");
        }
        self.pos = next;
        Ok(())
    }

    fn read_bytes(&mut self, n: usize) -> Result<&'a [u8]> {
        if self.pos + n > self.data.len() {
            bail!("D-Bus underflow reading {n} bytes at {}", self.pos);
        }
        let s = &self.data[self.pos..self.pos + n];
        self.pos += n;
        Ok(s)
    }

    fn read_u16(&mut self) -> Result<u16> {
        self.align(2)?;
        let b: [u8; 2] = self.read_bytes(2)?.try_into().unwrap();
        Ok(if self.le {
            u16::from_le_bytes(b)
        } else {
            u16::from_be_bytes(b)
        })
    }

    fn read_u32(&mut self) -> Result<u32> {
        self.align(4)?;
        let b: [u8; 4] = self.read_bytes(4)?.try_into().unwrap();
        Ok(if self.le {
            u32::from_le_bytes(b)
        } else {
            u32::from_be_bytes(b)
        })
    }

    fn read_u64(&mut self) -> Result<u64> {
        self.align(8)?;
        let b: [u8; 8] = self.read_bytes(8)?.try_into().unwrap();
        Ok(if self.le {
            u64::from_le_bytes(b)
        } else {
            u64::from_be_bytes(b)
        })
    }

    fn read_string(&mut self) -> Result<String> {
        let len = self.read_u32()? as usize;
        let bytes = self.read_bytes(len)?;
        let _nul = self.read_bytes(1)?;
        Ok(String::from_utf8_lossy(bytes).into_owned())
    }

    fn read_signature(&mut self) -> Result<String> {
        let len = self.read_bytes(1)?[0] as usize;
        let bytes = self.read_bytes(len)?;
        let _nul = self.read_bytes(1)?;
        Ok(String::from_utf8_lossy(bytes).into_owned())
    }

    fn read_value(&mut self, sig: &str) -> Result<DBusValue> {
        match sig.as_bytes().first().copied() {
            Some(b'y') => Ok(DBusValue::Byte(self.read_bytes(1)?[0])),
            Some(b'b') => Ok(DBusValue::Bool(self.read_u32()? != 0)),
            Some(b'n') => Ok(DBusValue::Int16(self.read_u16()? as i16)),
            Some(b'q') => Ok(DBusValue::Uint16(self.read_u16()?)),
            Some(b'i') => Ok(DBusValue::Int32(self.read_u32()? as i32)),
            Some(b'u') | Some(b'h') => Ok(DBusValue::Uint32(self.read_u32()?)),
            Some(b'x') => Ok(DBusValue::Int64(self.read_u64()? as i64)),
            Some(b't') => Ok(DBusValue::Uint64(self.read_u64()?)),
            Some(b'd') => Ok(DBusValue::Double(f64::from_bits(self.read_u64()?))),
            Some(b's') => Ok(DBusValue::String(self.read_string()?)),
            Some(b'o') => Ok(DBusValue::ObjectPath(self.read_string()?)),
            Some(b'g') => Ok(DBusValue::Signature(self.read_signature()?)),
            Some(b'v') => {
                let inner_sig = self.read_signature()?;
                let val = self.read_value(&inner_sig)?;
                Ok(DBusValue::Variant(inner_sig, Box::new(val)))
            }
            Some(b'a') => {
                let elem_sig = &sig[1..];
                let byte_len = self.read_u32()? as usize;
                self.align(sig_alignment(elem_sig))?;
                let end = self.pos + byte_len;
                if end > self.data.len() {
                    bail!("D-Bus array exceeds message length");
                }
                if elem_sig.starts_with('{') && elem_sig.ends_with('}') {
                    let inner = &elem_sig[1..elem_sig.len() - 1];
                    let (k_sig, v_sig) = split_one_type(inner)?;
                    let mut entries = Vec::new();
                    while self.pos < end {
                        self.align(8)?;
                        let k = self.read_value(k_sig)?;
                        let v = self.read_value(v_sig)?;
                        entries.push((k, v));
                    }
                    Ok(DBusValue::Dict(k_sig.to_string(), v_sig.to_string(), entries))
                } else {
                    let mut items = Vec::new();
                    while self.pos < end {
                        items.push(self.read_value(elem_sig)?);
                    }
                    Ok(DBusValue::Array(elem_sig.to_string(), items))
                }
            }
            Some(b'(') => {
                self.align(8)?;
                let mut inner = &sig[1..sig.len() - 1];
                let mut fields = Vec::new();
                while !inner.is_empty() {
                    let (one, rest) = split_one_type(inner)?;
                    fields.push(self.read_value(one)?);
                    inner = rest;
                }
                Ok(DBusValue::Struct(fields))
            }
            _ => bail!("unsupported D-Bus type signature: {sig}"),
        }
    }

    fn read_signature_list(&mut self, mut sig: &str) -> Result<Vec<DBusValue>> {
        let mut out = Vec::new();
        while !sig.is_empty() {
            let (one, rest) = split_one_type(sig)?;
            out.push(self.read_value(one)?);
            sig = rest;
        }
        Ok(out)
    }
}

pub fn encode_message(
    msg_type: u8,
    flags: u8,
    serial: u32,
    headers: &[(u8, DBusValue)],
    body_sig: &str,
    body_args: &[DBusValue],
) -> Result<Vec<u8>> {
    let mut body = Vec::new();
    for arg in body_args {
        marshal_value(&mut body, arg)?;
    }

    let mut hdr_fields = Vec::new();
    for (code, val) in headers {
        let sig = match val {
            DBusValue::ObjectPath(_) => "o",
            DBusValue::String(_) => "s",
            DBusValue::Signature(_) => "g",
            DBusValue::Uint32(_) => "u",
            _ => bail!("unsupported D-Bus header value"),
        };
        hdr_fields.push(DBusValue::Struct(vec![
            DBusValue::Byte(*code),
            DBusValue::Variant(sig.to_string(), Box::new(val.clone())),
        ]));
    }
    if !body_sig.is_empty() {
        hdr_fields.push(DBusValue::Struct(vec![
            DBusValue::Byte(HDR_SIGNATURE),
            DBusValue::Variant(
                "g".to_string(),
                Box::new(DBusValue::Signature(body_sig.to_string())),
            ),
        ]));
    }

    let mut msg = Vec::with_capacity(128 + body.len());
    msg.push(b'l'); // little-endian
    msg.push(msg_type);
    msg.push(flags);
    msg.push(1); // protocol version
    msg.extend_from_slice(&(body.len() as u32).to_le_bytes());
    msg.extend_from_slice(&serial.to_le_bytes());
    marshal_value(&mut msg, &DBusValue::Array("(yv)".to_string(), hdr_fields))?;
    pad(&mut msg, 8);
    msg.extend_from_slice(&body);
    Ok(msg)
}

pub fn decode_message(bytes: &[u8]) -> Result<DBusMessage> {
    decode_message_inner(bytes).map(|(msg, _)| msg)
}

fn decode_message_inner(bytes: &[u8]) -> Result<(DBusMessage, usize)> {
    if bytes.len() < 16 {
        bail!("D-Bus message too short");
    }
    let le = match bytes[0] {
        b'l' => true,
        b'B' => false,
        other => bail!("invalid D-Bus endian byte: {other}"),
    };
    let msg_type = bytes[1];
    let flags = bytes[2];
    let body_len = if le {
        u32::from_le_bytes(bytes[4..8].try_into().unwrap())
    } else {
        u32::from_be_bytes(bytes[4..8].try_into().unwrap())
    } as usize;
    let serial = if le {
        u32::from_le_bytes(bytes[8..12].try_into().unwrap())
    } else {
        u32::from_be_bytes(bytes[8..12].try_into().unwrap())
    };
    let fields_len = if le {
        u32::from_le_bytes(bytes[12..16].try_into().unwrap())
    } else {
        u32::from_be_bytes(bytes[12..16].try_into().unwrap())
    } as usize;

    if 16usize.saturating_add(fields_len) > bytes.len() {
        bail!("D-Bus header fields exceed packet size");
    }

    let mut hdr_unm = Unmarshaller {
        data: &bytes[..16 + fields_len],
        pos: 12,
        le,
    };
    let fields_val = hdr_unm.read_value("a(yv)")?;

    let mut path = None;
    let mut interface = None;
    let mut member = None;
    let mut error_name = None;
    let mut reply_serial = None;
    let mut destination = None;
    let mut sender = None;
    let mut signature = String::new();
    let mut unix_fds = 0usize;

    if let DBusValue::Array(_, items) = fields_val {
        for item in items {
            if let DBusValue::Struct(parts) = item
                && parts.len() == 2
                && let DBusValue::Byte(code) = parts[0]
            {
                match code {
                    HDR_PATH => path = parts[1].as_str().map(str::to_owned),
                    HDR_INTERFACE => interface = parts[1].as_str().map(str::to_owned),
                    HDR_MEMBER => member = parts[1].as_str().map(str::to_owned),
                    HDR_ERROR_NAME => error_name = parts[1].as_str().map(str::to_owned),
                    HDR_REPLY_SERIAL => reply_serial = parts[1].as_u32(),
                    HDR_DESTINATION => destination = parts[1].as_str().map(str::to_owned),
                    HDR_SENDER => sender = parts[1].as_str().map(str::to_owned),
                    HDR_SIGNATURE => {
                        signature = parts[1].as_str().unwrap_or_default().to_string();
                    }
                    HDR_UNIX_FDS => {
                        unix_fds = parts[1].as_u32().unwrap_or(0) as usize;
                    }
                    _ => {}
                }
            }
        }
    }

    let body_start = align_up(16 + fields_len, 8);
    if body_start + body_len > bytes.len() {
        bail!("D-Bus body exceeds packet size");
    }
    let body = if signature.is_empty() || body_len == 0 {
        Vec::new()
    } else {
        let mut body_unm = Unmarshaller::new(&bytes[body_start..body_start + body_len], le);
        body_unm.read_signature_list(&signature)?
    };

    Ok((
        DBusMessage {
            msg_type,
            flags,
            serial,
            path,
            interface,
            member,
            error_name,
            reply_serial,
            destination,
            sender,
            signature,
            body,
            fds: Vec::new(),
        },
        unix_fds,
    ))
}

fn connect_unix_address(addr: &str) -> Result<UnixStream> {
    let mut last_err: Option<anyhow::Error> = None;
    for part in addr.split(';') {
        if let Some(rest) = part.strip_prefix("unix:") {
            for kv in rest.split(',') {
                if let Some(path) = kv.strip_prefix("path=") {
                    let decoded = percent_decode(path);
                    match UnixStream::connect(&decoded)
                        .with_context(|| format!("connect D-Bus unix path {decoded}"))
                    {
                        Ok(stream) => return Ok(stream),
                        Err(err) => last_err = Some(err),
                    }
                }
                if let Some(abstract_name) = kv.strip_prefix("abstract=") {
                    let decoded = percent_decode(abstract_name);
                    match connect_abstract_unix(&decoded) {
                        Ok(stream) => return Ok(stream),
                        Err(err) => last_err = Some(err),
                    }
                }
            }
        }
    }
    if let Some(err) = last_err {
        return Err(err);
    }
    bail!("unsupported D-Bus address: {addr}");
}

fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Ok(hex) = std::str::from_utf8(&bytes[i + 1..i + 3])
            && let Ok(val) = u8::from_str_radix(hex, 16)
        {
            out.push(val);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn connect_abstract_unix(name: &str) -> Result<UnixStream> {
    use std::os::fd::FromRawFd;
    let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_STREAM | libc::SOCK_CLOEXEC, 0) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error()).context("socket AF_UNIX");
    }
    let mut addr: libc::sockaddr_un = unsafe { std::mem::zeroed() };
    addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
    let bytes = name.as_bytes();
    if bytes.len() + 1 > addr.sun_path.len() {
        unsafe { libc::close(fd) };
        bail!("abstract unix socket name too long");
    }
    addr.sun_path[0] = 0;
    for (idx, &b) in bytes.iter().enumerate() {
        addr.sun_path[1 + idx] = b as libc::c_char;
    }
    let len = std::mem::offset_of!(libc::sockaddr_un, sun_path) + 1 + bytes.len();
    let rc = unsafe {
        libc::connect(
            fd,
            (&addr as *const libc::sockaddr_un) as *const libc::sockaddr,
            len as libc::socklen_t,
        )
    };
    if rc < 0 {
        let err = std::io::Error::last_os_error();
        unsafe { libc::close(fd) };
        return Err(err).context("connect abstract D-Bus socket");
    }
    Ok(unsafe { UnixStream::from_raw_fd(fd) })
}

fn hex_uid() -> String {
    let uid = unsafe { libc::geteuid() }.to_string();
    let mut out = String::with_capacity(uid.len() * 2);
    for b in uid.as_bytes() {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

pub struct DBusConnection {
    stream: UnixStream,
    next_serial: u32,
    unique_name: String,
    read_buf: Vec<u8>,
    queued: VecDeque<DBusMessage>,
    pending_fds: VecDeque<OwnedFd>,
}

impl DBusConnection {
    pub fn connect_session() -> Result<Self> {
        let addr = env::var("DBUS_SESSION_BUS_ADDRESS")
            .ok()
            .filter(|v| !v.is_empty())
            .or_else(|| {
                env::var("XDG_RUNTIME_DIR")
                    .ok()
                    .filter(|v| !v.is_empty())
                    .map(|dir| format!("unix:path={dir}/bus"))
            })
            .ok_or_else(|| anyhow!("DBUS_SESSION_BUS_ADDRESS not set"))?;
        Self::connect_address(&addr)
    }

    pub fn connect_system() -> Result<Self> {
        let addr = env::var("DBUS_SYSTEM_BUS_ADDRESS")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "unix:path=/run/dbus/system_bus_socket".to_string());
        Self::connect_address(&addr)
    }

    pub fn connect_address(addr: &str) -> Result<Self> {
        let mut stream = connect_unix_address(addr)?;
        let auth = format!("\0AUTH EXTERNAL {}\r\n", hex_uid());
        stream.write_all(auth.as_bytes()).context("D-Bus SASL AUTH")?;
        let mut line = Vec::new();
        let mut byte = [0u8; 1];
        loop {
            stream.read_exact(&mut byte).context("D-Bus SASL reply")?;
            line.push(byte[0]);
            if line.ends_with(b"\r\n") {
                break;
            }
            if line.len() > 4096 {
                bail!("D-Bus SASL reply too long");
            }
        }
        let reply = String::from_utf8_lossy(&line);
        if !reply.starts_with("OK ") {
            bail!("D-Bus SASL EXTERNAL auth rejected: {}", reply.trim());
        }
        stream
            .write_all(b"NEGOTIATE_UNIX_FD\r\n")
            .context("D-Bus SASL NEGOTIATE_UNIX_FD")?;
        line.clear();
        loop {
            stream
                .read_exact(&mut byte)
                .context("D-Bus SASL UNIX_FD reply")?;
            line.push(byte[0]);
            if line.ends_with(b"\r\n") {
                break;
            }
            if line.len() > 4096 {
                bail!("D-Bus SASL reply too long");
            }
        }
        stream.write_all(b"BEGIN\r\n").context("D-Bus SASL BEGIN")?;

        let mut conn = Self {
            stream,
            next_serial: 1,
            unique_name: String::new(),
            read_buf: Vec::with_capacity(4096),
            queued: VecDeque::new(),
            pending_fds: VecDeque::new(),
        };
        let hello = conn.call(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "Hello",
            "",
            &[],
        )?;
        conn.unique_name = hello
            .body
            .first()
            .and_then(DBusValue::as_str)
            .unwrap_or_default()
            .to_string();
        Ok(conn)
    }

    pub fn unique_name(&self) -> &str {
        &self.unique_name
    }

    pub fn as_raw_fd(&self) -> RawFd {
        self.stream.as_raw_fd()
    }

    fn alloc_serial(&mut self) -> u32 {
        let s = self.next_serial;
        self.next_serial = self.next_serial.wrapping_add(1).max(1);
        s
    }

    fn send_bytes(&mut self, bytes: &[u8]) -> Result<()> {
        self.stream.write_all(bytes).context("write D-Bus message")
    }

    fn try_pop_buffered(&mut self) -> Result<Option<DBusMessage>> {
        if self.read_buf.len() < 16 {
            return Ok(None);
        }
        let le = self.read_buf[0] == b'l';
        let body_len = if le {
            u32::from_le_bytes(self.read_buf[4..8].try_into().unwrap())
        } else {
            u32::from_be_bytes(self.read_buf[4..8].try_into().unwrap())
        } as usize;
        let fields_len = if le {
            u32::from_le_bytes(self.read_buf[12..16].try_into().unwrap())
        } else {
            u32::from_be_bytes(self.read_buf[12..16].try_into().unwrap())
        } as usize;
        let total = align_up(16 + fields_len, 8) + body_len;
        if self.read_buf.len() < total {
            return Ok(None);
        }
        let packet = self.read_buf[..total].to_vec();
        self.read_buf.drain(..total);
        let (mut msg, unix_fds) = decode_message_inner(&packet)?;
        for _ in 0..unix_fds {
            if let Some(fd) = self.pending_fds.pop_front() {
                msg.fds.push(Arc::new(fd));
            }
        }
        Ok(Some(msg))
    }

    fn read_socket_chunk(&mut self) -> Result<()> {
        let mut data = [0u8; 4096];
        let mut iov = libc::iovec {
            iov_base: data.as_mut_ptr() as *mut libc::c_void,
            iov_len: data.len(),
        };
        let mut cmsg_buf = [0u8; 512];
        let mut msg: libc::msghdr = unsafe { std::mem::zeroed() };
        msg.msg_iov = &mut iov;
        msg.msg_iovlen = 1;
        msg.msg_control = cmsg_buf.as_mut_ptr() as *mut libc::c_void;
        msg.msg_controllen = cmsg_buf.len() as _;

        let rc = loop {
            let n = unsafe {
                libc::recvmsg(self.stream.as_raw_fd(), &mut msg, libc::MSG_CMSG_CLOEXEC)
            };
            if n < 0 {
                let err = std::io::Error::last_os_error();
                if err.kind() == std::io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(err).context("read D-Bus socket");
            }
            break n;
        };
        if rc == 0 {
            bail!("D-Bus bus closed connection");
        }
        self.read_buf.extend_from_slice(&data[..rc as usize]);

        unsafe {
            let mut cmsg = libc::CMSG_FIRSTHDR(&msg);
            while !cmsg.is_null() {
                if (*cmsg).cmsg_level == libc::SOL_SOCKET
                    && (*cmsg).cmsg_type == libc::SCM_RIGHTS
                {
                    let data_ptr = libc::CMSG_DATA(cmsg);
                    let header_len = data_ptr as usize - cmsg as usize;
                    let total_len = (*cmsg).cmsg_len as usize;
                    if total_len > header_len {
                        let count = (total_len - header_len) / std::mem::size_of::<RawFd>();
                        for i in 0..count {
                            let mut raw_fd: RawFd = -1;
                            std::ptr::copy_nonoverlapping(
                                data_ptr.add(i * std::mem::size_of::<RawFd>()),
                                (&mut raw_fd as *mut RawFd) as *mut u8,
                                std::mem::size_of::<RawFd>(),
                            );
                            if raw_fd >= 0 {
                                self.pending_fds.push_back(OwnedFd::from_raw_fd(raw_fd));
                            }
                        }
                    }
                }
                cmsg = libc::CMSG_NXTHDR(&msg, cmsg);
            }
        }
        Ok(())
    }

    fn read_wire_message(&mut self) -> Result<DBusMessage> {
        loop {
            if let Some(msg) = self.try_pop_buffered()? {
                return Ok(msg);
            }
            self.read_socket_chunk()?;
        }
    }

    pub fn read_message(&mut self) -> Result<DBusMessage> {
        if let Some(msg) = self.queued.pop_front() {
            return Ok(msg);
        }
        self.read_wire_message()
    }

    pub fn read_message_timeout(&mut self, timeout_ms: i32) -> Result<Option<DBusMessage>> {
        if let Some(msg) = self.queued.pop_front() {
            return Ok(Some(msg));
        }
        if let Some(msg) = self.try_pop_buffered()? {
            return Ok(Some(msg));
        }
        let mut pfd = libc::pollfd {
            fd: self.stream.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let rc = unsafe { libc::poll(&mut pfd, 1, timeout_ms) };
        if rc < 0 {
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::Interrupted {
                return Ok(None);
            }
            return Err(err).context("poll D-Bus socket");
        }
        if rc == 0 {
            return Ok(None);
        }
        if (pfd.revents & (libc::POLLERR | libc::POLLNVAL)) != 0 {
            bail!("D-Bus socket error");
        }
        if (pfd.revents & libc::POLLHUP) != 0 && (pfd.revents & libc::POLLIN) == 0 {
            bail!("D-Bus bus closed connection");
        }
        self.read_socket_chunk()?;
        self.try_pop_buffered()
    }

    pub fn call(
        &mut self,
        dest: &str,
        path: &str,
        interface: &str,
        member: &str,
        body_sig: &str,
        args: &[DBusValue],
    ) -> Result<DBusMessage> {
        let serial = self.alloc_serial();
        let headers = vec![
            (HDR_PATH, DBusValue::ObjectPath(path.to_string())),
            (HDR_INTERFACE, DBusValue::String(interface.to_string())),
            (HDR_MEMBER, DBusValue::String(member.to_string())),
            (HDR_DESTINATION, DBusValue::String(dest.to_string())),
        ];
        let bytes = encode_message(MSG_METHOD_CALL, 0, serial, &headers, body_sig, args)?;
        self.send_bytes(&bytes)?;
        loop {
            let msg = self.read_wire_message()?;
            if msg.reply_serial == Some(serial) {
                if msg.msg_type == MSG_ERROR {
                    let err_name = msg.error_name.as_deref().unwrap_or("org.freedesktop.DBus.Error");
                    let detail = msg
                        .body
                        .first()
                        .and_then(DBusValue::as_str)
                        .unwrap_or_default();
                    bail!("D-Bus error {err_name}: {detail}");
                }
                return Ok(msg);
            }
            self.queued.push_back(msg);
        }
    }

    pub fn send_reply(
        &mut self,
        reply_serial: u32,
        dest: Option<&str>,
        body_sig: &str,
        args: &[DBusValue],
    ) -> Result<()> {
        let serial = self.alloc_serial();
        let mut headers = vec![(HDR_REPLY_SERIAL, DBusValue::Uint32(reply_serial))];
        if let Some(d) = dest {
            headers.push((HDR_DESTINATION, DBusValue::String(d.to_string())));
        }
        let bytes = encode_message(MSG_METHOD_RETURN, 0, serial, &headers, body_sig, args)?;
        self.send_bytes(&bytes)
    }

    pub fn send_error(
        &mut self,
        reply_serial: u32,
        dest: Option<&str>,
        error_name: &str,
        message: &str,
    ) -> Result<()> {
        let serial = self.alloc_serial();
        let mut headers = vec![
            (HDR_ERROR_NAME, DBusValue::String(error_name.to_string())),
            (HDR_REPLY_SERIAL, DBusValue::Uint32(reply_serial)),
        ];
        if let Some(d) = dest {
            headers.push((HDR_DESTINATION, DBusValue::String(d.to_string())));
        }
        let bytes = encode_message(
            MSG_ERROR,
            0,
            serial,
            &headers,
            "s",
            &[DBusValue::String(message.to_string())],
        )?;
        self.send_bytes(&bytes)
    }

    pub fn send_signal(
        &mut self,
        path: &str,
        interface: &str,
        member: &str,
        body_sig: &str,
        args: &[DBusValue],
    ) -> Result<()> {
        let serial = self.alloc_serial();
        let headers = vec![
            (HDR_PATH, DBusValue::ObjectPath(path.to_string())),
            (HDR_INTERFACE, DBusValue::String(interface.to_string())),
            (HDR_MEMBER, DBusValue::String(member.to_string())),
        ];
        let bytes = encode_message(MSG_SIGNAL, 0, serial, &headers, body_sig, args)?;
        self.send_bytes(&bytes)
    }

    pub fn request_name(&mut self, name: &str, flags: u32) -> Result<u32> {
        let reply = self.call(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "RequestName",
            "su",
            &[DBusValue::String(name.to_string()), DBusValue::Uint32(flags)],
        )?;
        Ok(reply.body.first().and_then(DBusValue::as_u32).unwrap_or(0))
    }

    pub fn add_match(&mut self, rule: &str) -> Result<()> {
        let _ = self.call(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "AddMatch",
            "s",
            &[DBusValue::String(rule.to_string())],
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        DBusValue, HDR_DESTINATION, HDR_INTERFACE, HDR_MEMBER, HDR_PATH, MSG_METHOD_CALL,
        decode_message, encode_message,
    };

    #[test]
    fn roundtrip_complex_dict_variant_message() {
        let dict = DBusValue::Dict(
            "s".to_string(),
            "v".to_string(),
            vec![
                (
                    DBusValue::String("PlaybackStatus".to_string()),
                    DBusValue::Variant(
                        "s".to_string(),
                        Box::new(DBusValue::String("Playing".to_string())),
                    ),
                ),
                (
                    DBusValue::String("Volume".to_string()),
                    DBusValue::Variant("d".to_string(), Box::new(DBusValue::Double(0.75))),
                ),
                (
                    DBusValue::String("Position".to_string()),
                    DBusValue::Variant("x".to_string(), Box::new(DBusValue::Int64(12_345_678))),
                ),
            ],
        );
        let bytes = encode_message(
            MSG_METHOD_CALL,
            0,
            7,
            &[
                (HDR_PATH, DBusValue::ObjectPath("/org/mpris/MediaPlayer2".into())),
                (HDR_INTERFACE, DBusValue::String("org.freedesktop.DBus.Properties".into())),
                (HDR_MEMBER, DBusValue::String("PropertiesChanged".into())),
                (HDR_DESTINATION, DBusValue::String(":1.42".into())),
            ],
            "sa{sv}as",
            &[
                DBusValue::String("org.mpris.MediaPlayer2.Player".into()),
                dict.clone(),
                DBusValue::Array("s".into(), vec![]),
            ],
        )
        .unwrap();

        let decoded = decode_message(&bytes).unwrap();
        assert_eq!(decoded.serial, 7);
        assert_eq!(decoded.path.as_deref(), Some("/org/mpris/MediaPlayer2"));
        assert_eq!(decoded.member.as_deref(), Some("PropertiesChanged"));
        assert_eq!(decoded.body.len(), 3);
        assert_eq!(decoded.body[1], dict);
    }

    #[test]
    fn recvmsg_extracts_scm_rights_unix_fds_for_dbus_message() {
        use std::collections::VecDeque;
        use std::io::{Read, Write};
        use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
        use std::os::unix::net::UnixStream;

        let (writer_sock, reader_sock) = UnixStream::pair().unwrap();

        let mut pipe_fds = [0 as libc::c_int; 2];
        assert_eq!(unsafe { libc::pipe2(pipe_fds.as_mut_ptr(), libc::O_CLOEXEC) }, 0);
        let pipe_read = unsafe { OwnedFd::from_raw_fd(pipe_fds[0]) };
        let mut pipe_write = std::fs::File::from(unsafe { OwnedFd::from_raw_fd(pipe_fds[1]) });

        let packet = encode_message(
            super::MSG_METHOD_RETURN,
            0,
            42,
            &[
                (super::HDR_REPLY_SERIAL, DBusValue::Uint32(1)),
                (super::HDR_UNIX_FDS, DBusValue::Uint32(1)),
            ],
            "h",
            &[DBusValue::Uint32(0)],
        )
        .unwrap();

        let send_fd: RawFd = pipe_read.as_raw_fd();
        let mut iov = libc::iovec {
            iov_base: packet.as_ptr() as *mut libc::c_void,
            iov_len: packet.len(),
        };
        let fds_bytes = std::mem::size_of::<RawFd>();
        let space = unsafe { libc::CMSG_SPACE(fds_bytes as u32) } as usize;
        let mut cmsg_buf = vec![0u8; space];
        let mut msg: libc::msghdr = unsafe { std::mem::zeroed() };
        msg.msg_iov = &mut iov;
        msg.msg_iovlen = 1;
        msg.msg_control = cmsg_buf.as_mut_ptr() as *mut libc::c_void;
        msg.msg_controllen = space as _;
        unsafe {
            let cmsg = libc::CMSG_FIRSTHDR(&msg);
            (*cmsg).cmsg_level = libc::SOL_SOCKET;
            (*cmsg).cmsg_type = libc::SCM_RIGHTS;
            (*cmsg).cmsg_len = libc::CMSG_LEN(fds_bytes as u32) as _;
            std::ptr::copy_nonoverlapping(
                (&send_fd as *const RawFd) as *const u8,
                libc::CMSG_DATA(cmsg),
                fds_bytes,
            );
        }
        let sent = unsafe { libc::sendmsg(writer_sock.as_raw_fd(), &msg, 0) };
        assert_eq!(sent as usize, packet.len());
        drop(pipe_read);

        let mut conn = super::DBusConnection {
            stream: reader_sock,
            next_serial: 2,
            unique_name: ":1.9".to_string(),
            read_buf: Vec::with_capacity(4096),
            queued: VecDeque::new(),
            pending_fds: VecDeque::new(),
        };
        let reply = conn.read_message().unwrap();
        assert_eq!(reply.fds.len(), 1);
        assert_eq!(reply.body[0].as_u32(), Some(0));

        pipe_write.write_all(b"inhibitor-ok").unwrap();
        drop(pipe_write);
        let received_fd = unsafe { OwnedFd::from_raw_fd(libc::dup(reply.fds[0].as_raw_fd())) };
        let mut file = std::fs::File::from(received_fd);
        let mut buf = String::new();
        file.read_to_string(&mut buf).unwrap();
        assert_eq!(buf, "inhibitor-ok");
    }
}
