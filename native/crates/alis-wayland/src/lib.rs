use std::collections::VecDeque;
use std::env;
use std::ffi::CString;
use std::os::fd::{AsRawFd, OwnedFd, RawFd};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

use anyhow::{Context, Result, anyhow, bail};

pub const WL_DISPLAY_ID: u32 = 1;
pub const WL_DISPLAY_SYNC: u16 = 0;
pub const WL_DISPLAY_GET_REGISTRY: u16 = 1;
pub const WL_DISPLAY_EVENT_ERROR: u16 = 0;
pub const WL_DISPLAY_EVENT_DELETE_ID: u16 = 1;
pub const WL_REGISTRY_BIND: u16 = 0;
pub const WL_REGISTRY_EVENT_GLOBAL: u16 = 0;
pub const WL_CALLBACK_EVENT_DONE: u16 = 0;

pub const WL_SHM_CREATE_POOL: u16 = 0;
pub const WL_SHM_POOL_CREATE_BUFFER: u16 = 0;
pub const WL_SHM_POOL_DESTROY: u16 = 1;
pub const WL_BUFFER_DESTROY: u16 = 0;

pub const WL_SHM_FORMAT_ARGB8888: u32 = 0;
pub const WL_SHM_FORMAT_XRGB8888: u32 = 1;
pub const WL_SHM_FORMAT_RGB888: u32 = 0x34324752;
pub const WL_SHM_FORMAT_BGR888: u32 = 0x34324742;
pub const WL_SHM_FORMAT_XBGR8888: u32 = 0x34324258;
pub const WL_SHM_FORMAT_ABGR8888: u32 = 0x34324241;
pub const WL_SHM_FORMAT_XRGB2101010: u32 = 0x30335258;
pub const WL_SHM_FORMAT_XBGR2101010: u32 = 0x30334258;
pub const WL_SHM_FORMAT_ARGB2101010: u32 = 0x30335241;
pub const WL_SHM_FORMAT_ABGR2101010: u32 = 0x30334241;

#[derive(Debug, Clone)]
pub struct WlGlobal {
    pub name: u32,
    pub interface: String,
    pub version: u32,
}

#[derive(Debug)]
pub struct WlMessage {
    pub object_id: u32,
    pub opcode: u16,
    pub payload: Vec<u8>,
    pub fds: Vec<OwnedFd>,
}

#[derive(Debug, Default)]
pub struct WlWriter {
    buf: Vec<u8>,
    fds: Vec<RawFd>,
}

impl WlWriter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn u32(&mut self, value: u32) -> &mut Self {
        self.buf.extend_from_slice(&value.to_ne_bytes());
        self
    }

    pub fn i32(&mut self, value: i32) -> &mut Self {
        self.buf.extend_from_slice(&value.to_ne_bytes());
        self
    }

    pub fn string(&mut self, value: &str) -> &mut Self {
        let bytes = value.as_bytes();
        let len_with_nul = (bytes.len() + 1) as u32;
        self.u32(len_with_nul);
        self.buf.extend_from_slice(bytes);
        self.buf.push(0);
        while !self.buf.len().is_multiple_of(4) {
            self.buf.push(0);
        }
        self
    }

    pub fn array(&mut self, data: &[u8]) -> &mut Self {
        self.u32(data.len() as u32);
        self.buf.extend_from_slice(data);
        while !self.buf.len().is_multiple_of(4) {
            self.buf.push(0);
        }
        self
    }

    pub fn fd(&mut self, fd: RawFd) -> &mut Self {
        self.fds.push(fd);
        self
    }

    pub fn into_parts(self) -> (Vec<u8>, Vec<RawFd>) {
        (self.buf, self.fds)
    }
}

pub struct WlReader<'a> {
    data: &'a [u8],
    offset: usize,
}

impl<'a> WlReader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self { data, offset: 0 }
    }

    pub fn u32(&mut self) -> Result<u32> {
        if self.offset + 4 > self.data.len() {
            bail!("wayland wire underflow reading u32");
        }
        let val = u32::from_ne_bytes(self.data[self.offset..self.offset + 4].try_into().unwrap());
        self.offset += 4;
        Ok(val)
    }

    pub fn i32(&mut self) -> Result<i32> {
        Ok(self.u32()? as i32)
    }

    pub fn string(&mut self) -> Result<String> {
        let len = self.u32()? as usize;
        let padded = (len + 3) & !3;
        if self.offset + padded > self.data.len() {
            bail!("wayland wire underflow reading string");
        }
        let slice = &self.data[self.offset..self.offset + len];
        self.offset += padded;
        let without_nul = slice.strip_suffix(&[0]).unwrap_or(slice);
        Ok(String::from_utf8_lossy(without_nul).into_owned())
    }

    pub fn array(&mut self) -> Result<Vec<u8>> {
        let len = self.u32()? as usize;
        let padded = (len + 3) & !3;
        if self.offset + padded > self.data.len() {
            bail!("wayland wire underflow reading array");
        }
        let slice = self.data[self.offset..self.offset + len].to_vec();
        self.offset += padded;
        Ok(slice)
    }
}

pub struct WlConnection {
    stream: UnixStream,
    next_obj_id: u32,
    read_buf: Vec<u8>,
    fd_queue: VecDeque<OwnedFd>,
}

impl WlConnection {
    pub fn socket_path() -> Result<PathBuf> {
        let display = env::var("WAYLAND_DISPLAY")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "wayland-0".to_string());
        let p = PathBuf::from(&display);
        if p.is_absolute() {
            return Ok(p);
        }
        let runtime = env::var("XDG_RUNTIME_DIR")
            .ok()
            .filter(|v| !v.is_empty())
            .ok_or_else(|| anyhow!("XDG_RUNTIME_DIR is not set"))?;
        Ok(PathBuf::from(runtime).join(display))
    }

    pub fn connect() -> Result<Self> {
        let path = Self::socket_path()?;
        let stream = UnixStream::connect(&path)
            .with_context(|| format!("connect Wayland display {}", path.display()))?;
        Ok(Self {
            stream,
            next_obj_id: 2,
            read_buf: Vec::with_capacity(4096),
            fd_queue: VecDeque::new(),
        })
    }

    pub fn as_raw_fd(&self) -> RawFd {
        self.stream.as_raw_fd()
    }

    pub fn next_id(&mut self) -> u32 {
        let id = self.next_obj_id;
        self.next_obj_id += 1;
        id
    }

    pub fn send(&self, object_id: u32, opcode: u16, writer: WlWriter) -> Result<()> {
        let (payload, fds) = writer.into_parts();
        self.send_raw(object_id, opcode, &payload, &fds)
    }

    pub fn send_raw(
        &self,
        object_id: u32,
        opcode: u16,
        payload: &[u8],
        fds: &[RawFd],
    ) -> Result<()> {
        let total_len = 8 + payload.len();
        if total_len > u16::MAX as usize {
            bail!("wayland message too large: {total_len}");
        }
        let mut packet = Vec::with_capacity(total_len);
        packet.extend_from_slice(&object_id.to_ne_bytes());
        let word1 = ((total_len as u32) << 16) | (opcode as u32);
        packet.extend_from_slice(&word1.to_ne_bytes());
        packet.extend_from_slice(payload);

        let mut sent = 0usize;
        let mut fds_sent = false;
        while sent < packet.len() {
            let chunk = &packet[sent..];
            let mut iov = libc::iovec {
                iov_base: chunk.as_ptr() as *mut libc::c_void,
                iov_len: chunk.len(),
            };
            let mut msg: libc::msghdr = unsafe { std::mem::zeroed() };
            msg.msg_iov = &mut iov;
            msg.msg_iovlen = 1;

            let mut cmsg_buf = vec![0u8; 256];
            if !fds.is_empty() && !fds_sent {
                let fds_bytes = std::mem::size_of_val(fds);
                let space = unsafe { libc::CMSG_SPACE(fds_bytes as u32) } as usize;
                cmsg_buf.resize(space, 0);
                msg.msg_control = cmsg_buf.as_mut_ptr() as *mut libc::c_void;
                msg.msg_controllen = space as _;
                unsafe {
                    let cmsg = libc::CMSG_FIRSTHDR(&msg);
                    (*cmsg).cmsg_level = libc::SOL_SOCKET;
                    (*cmsg).cmsg_type = libc::SCM_RIGHTS;
                    (*cmsg).cmsg_len = libc::CMSG_LEN(fds_bytes as u32) as _;
                    std::ptr::copy_nonoverlapping(
                        fds.as_ptr() as *const u8,
                        libc::CMSG_DATA(cmsg),
                        fds_bytes,
                    );
                }
            }

            let rc = unsafe { libc::sendmsg(self.stream.as_raw_fd(), &msg, libc::MSG_NOSIGNAL) };
            if rc < 0 {
                let err = std::io::Error::last_os_error();
                if err.kind() == std::io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(err).context("sendmsg on Wayland socket");
            }
            if rc == 0 {
                bail!("Wayland socket closed while sending");
            }
            sent += rc as usize;
            fds_sent = true;
        }
        Ok(())
    }

    fn read_once(&mut self) -> Result<()> {
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

        loop {
            let rc = unsafe { libc::recvmsg(self.stream.as_raw_fd(), &mut msg, libc::MSG_CMSG_CLOEXEC) };
            if rc < 0 {
                let err = std::io::Error::last_os_error();
                if err.kind() == std::io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(err).context("recvmsg on Wayland socket");
            }
            if rc == 0 {
                bail!("Wayland compositor closed the connection");
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
                                    use std::os::fd::FromRawFd;
                                    self.fd_queue.push_back(OwnedFd::from_raw_fd(raw_fd));
                                }
                            }
                        }
                    }
                    cmsg = libc::CMSG_NXTHDR(&msg, cmsg);
                }
            }
            return Ok(());
        }
    }

    pub fn has_buffered_message(&self) -> bool {
        if self.read_buf.len() < 8 {
            return false;
        }
        let word1 = u32::from_ne_bytes(self.read_buf[4..8].try_into().unwrap());
        let size = (word1 >> 16) as usize;
        size >= 8 && self.read_buf.len() >= size
    }

    pub fn take_fd(&mut self) -> Option<OwnedFd> {
        self.fd_queue.pop_front()
    }

    pub fn pop_message(&mut self) -> Result<Option<WlMessage>> {
        if self.read_buf.len() < 8 {
            return Ok(None);
        }
        let object_id = u32::from_ne_bytes(self.read_buf[0..4].try_into().unwrap());
        let word1 = u32::from_ne_bytes(self.read_buf[4..8].try_into().unwrap());
        let size = (word1 >> 16) as usize;
        let opcode = (word1 & 0xffff) as u16;
        if size < 8 {
            bail!("invalid Wayland message size {size}");
        }
        if self.read_buf.len() < size {
            return Ok(None);
        }
        let payload = self.read_buf[8..size].to_vec();
        self.read_buf.drain(..size);
        Ok(Some(WlMessage {
            object_id,
            opcode,
            payload,
            fds: Vec::new(),
        }))
    }

    pub fn recv_message(&mut self) -> Result<WlMessage> {
        loop {
            if let Some(msg) = self.pop_message()? {
                return Ok(msg);
            }
            self.read_once()?;
        }
    }

    pub fn recv_message_timeout(&mut self, timeout_ms: i32) -> Result<Option<WlMessage>> {
        if let Some(msg) = self.pop_message()? {
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
            return Err(err).context("poll on Wayland socket");
        }
        if rc == 0 {
            return Ok(None);
        }
        if (pfd.revents & (libc::POLLERR | libc::POLLNVAL)) != 0 {
            bail!("Wayland socket error");
        }
        if (pfd.revents & libc::POLLHUP) != 0 && (pfd.revents & libc::POLLIN) == 0 {
            bail!("Wayland compositor closed the connection");
        }
        self.read_once()?;
        self.pop_message()
    }

    pub fn check_display_error(msg: &WlMessage) -> Result<()> {
        if msg.object_id == WL_DISPLAY_ID && msg.opcode == WL_DISPLAY_EVENT_ERROR {
            let mut r = WlReader::new(&msg.payload);
            let target = r.u32().unwrap_or(0);
            let code = r.u32().unwrap_or(0);
            let text = r.string().unwrap_or_default();
            bail!("Wayland protocol error on object {target} (code {code}): {text}");
        }
        Ok(())
    }

    pub fn roundtrip(&mut self) -> Result<Vec<WlMessage>> {
        let cb_id = self.next_id();
        let mut w = WlWriter::new();
        w.u32(cb_id);
        self.send(WL_DISPLAY_ID, WL_DISPLAY_SYNC, w)?;
        let mut events = Vec::new();
        loop {
            let msg = self.recv_message()?;
            Self::check_display_error(&msg)?;
            if msg.object_id == cb_id && msg.opcode == WL_CALLBACK_EVENT_DONE {
                return Ok(events);
            }
            events.push(msg);
        }
    }

    pub fn get_globals(&mut self) -> Result<(u32, Vec<WlGlobal>)> {
        let registry_id = self.next_id();
        let mut w = WlWriter::new();
        w.u32(registry_id);
        self.send(WL_DISPLAY_ID, WL_DISPLAY_GET_REGISTRY, w)?;
        let events = self.roundtrip()?;
        let mut globals = Vec::new();
        for ev in events {
            if ev.object_id == registry_id && ev.opcode == WL_REGISTRY_EVENT_GLOBAL {
                let mut r = WlReader::new(&ev.payload);
                let name = r.u32()?;
                let interface = r.string()?;
                let version = r.u32()?;
                globals.push(WlGlobal {
                    name,
                    interface,
                    version,
                });
            }
        }
        Ok((registry_id, globals))
    }

    pub fn bind_global(
        &mut self,
        registry_id: u32,
        name: u32,
        interface: &str,
        version: u32,
    ) -> Result<u32> {
        let new_id = self.next_id();
        let mut w = WlWriter::new();
        w.u32(name).string(interface).u32(version).u32(new_id);
        self.send(registry_id, WL_REGISTRY_BIND, w)?;
        Ok(new_id)
    }
}

pub fn create_memfd(name: &str, size: usize) -> Result<OwnedFd> {
    let cname = CString::new(name).unwrap_or_else(|_| CString::new("alis-shm").unwrap());
    let fd = unsafe { libc::memfd_create(cname.as_ptr(), libc::MFD_CLOEXEC) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error()).context("memfd_create");
    }
    let owned = unsafe {
        use std::os::fd::FromRawFd;
        OwnedFd::from_raw_fd(fd)
    };
    let rc = unsafe { libc::ftruncate(owned.as_raw_fd(), size as libc::off_t) };
    if rc < 0 {
        return Err(std::io::Error::last_os_error()).context("ftruncate memfd");
    }
    Ok(owned)
}

pub struct ShmBuffer {
    pub fd: OwnedFd,
    ptr: *mut u8,
    len: usize,
}

impl ShmBuffer {
    pub fn new(name: &str, size: usize) -> Result<Self> {
        let alloc_size = size.max(1);
        let fd = create_memfd(name, alloc_size)?;
        let ptr = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                alloc_size,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                fd.as_raw_fd(),
                0,
            )
        };
        if ptr == libc::MAP_FAILED {
            return Err(std::io::Error::last_os_error()).context("mmap memfd");
        }
        Ok(Self {
            fd,
            ptr: ptr as *mut u8,
            len: alloc_size,
        })
    }

    pub fn as_slice(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }

    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        unsafe { std::slice::from_raw_parts_mut(self.ptr, self.len) }
    }

    pub fn raw_fd(&self) -> RawFd {
        self.fd.as_raw_fd()
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
}

impl Drop for ShmBuffer {
    fn drop(&mut self) {
        if !self.ptr.is_null() && self.len > 0 {
            unsafe {
                libc::munmap(self.ptr as *mut libc::c_void, self.len);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{ShmBuffer, WlReader, WlWriter};

    #[test]
    fn wire_writer_reader_roundtrip_with_padding() {
        let mut w = WlWriter::new();
        w.u32(42)
            .i32(-7)
            .string("wl_shm")
            .string("a")
            .array(&[1, 2, 3]);
        let (bytes, fds) = w.into_parts();
        assert!(fds.is_empty());
        assert_eq!(bytes.len() % 4, 0);

        let mut r = WlReader::new(&bytes);
        assert_eq!(r.u32().unwrap(), 42);
        assert_eq!(r.i32().unwrap(), -7);
        assert_eq!(r.string().unwrap(), "wl_shm");
        assert_eq!(r.string().unwrap(), "a");
        assert_eq!(r.array().unwrap(), vec![1, 2, 3]);
    }

    #[test]
    fn shm_buffer_reads_and_writes_cleanly() {
        let mut buf = ShmBuffer::new("alis-test", 64).unwrap();
        buf.as_mut_slice()[..4].copy_from_slice(&[10, 20, 30, 40]);
        assert_eq!(&buf.as_slice()[..4], &[10, 20, 30, 40]);
    }
}
