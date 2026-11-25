use std::path::{Component, Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use alis_dbus::{DBusConnection, DBusMessage, DBusValue, MSG_METHOD_CALL};
use anyhow::Result;
use serde_json::Value;

use crate::{
    MpdManager, expand_home, file_url, home_dir, resolve_current_mpd_art,
    status_payload_mode_with_art,
};

const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const IFACE_ROOT: &str = "org.mpris.MediaPlayer2";
const IFACE_PLAYER: &str = "org.mpris.MediaPlayer2.Player";
const IFACE_PROPS: &str = "org.freedesktop.DBus.Properties";
const IFACE_INTROSPECT: &str = "org.freedesktop.DBus.Introspectable";
const IFACE_PEER: &str = "org.freedesktop.DBus.Peer";

const INTROSPECT_XML: &str = r#"<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node name="/org/mpris/MediaPlayer2">
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect">
      <arg name="xml_data" type="s" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.DBus.Peer">
    <method name="Ping"/>
    <method name="GetMachineId">
      <arg name="machine_uuid" type="s" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get">
      <arg name="interface_name" type="s" direction="in"/>
      <arg name="property_name" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="GetAll">
      <arg name="interface_name" type="s" direction="in"/>
      <arg name="properties" type="a{sv}" direction="out"/>
    </method>
    <method name="Set">
      <arg name="interface_name" type="s" direction="in"/>
      <arg name="property_name" type="s" direction="in"/>
      <arg name="value" type="v" direction="in"/>
    </method>
    <signal name="PropertiesChanged">
      <arg name="interface_name" type="s"/>
      <arg name="changed_properties" type="a{sv}"/>
      <arg name="invalidated_properties" type="as"/>
    </signal>
  </interface>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
    <method name="SetPosition">
      <arg name="TrackId" type="o" direction="in"/>
      <arg name="Position" type="x" direction="in"/>
    </method>
    <method name="OpenUri"><arg name="Uri" type="s" direction="in"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"#;

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct MprisState {
    pub playback_status: String,
    pub loop_status: String,
    pub shuffle: bool,
    pub volume: f64,
    pub position_us: i64,
    pub length_us: i64,
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub album_artist: String,
    pub art_url: String,
    pub url: String,
    pub track_number: i32,
}

impl Default for MprisState {
    fn default() -> Self {
        Self {
            playback_status: "Stopped".to_string(),
            loop_status: "None".to_string(),
            shuffle: false,
            volume: 1.0,
            position_us: 0,
            length_us: 0,
            track_id: "/org/mpris/MediaPlayer2/TrackList/NoTrack".to_string(),
            title: String::new(),
            artist: String::new(),
            album: String::new(),
            album_artist: String::new(),
            art_url: String::new(),
            url: String::new(),
            track_number: 0,
        }
    }
}

pub(crate) fn resolve_xdg_music_dir() -> Option<PathBuf> {
    if let Ok(val) = std::env::var("XDG_MUSIC_DIR") {
        let trimmed = val.trim();
        if !trimmed.is_empty() {
            let p = expand_home(trimmed);
            if p.is_absolute() {
                return Some(p);
            }
        }
    }
    let config_home = std::env::var("XDG_CONFIG_HOME")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".config"));
    if let Ok(contents) = std::fs::read_to_string(config_home.join("user-dirs.dirs")) {
        for line in contents.lines() {
            let trimmed = line.trim();
            if let Some(rest) = trimmed.strip_prefix("XDG_MUSIC_DIR=") {
                let unquoted = rest.trim().trim_matches('"').trim_matches('\'');
                let expanded = if let Some(suffix) = unquoted.strip_prefix("$HOME/") {
                    home_dir().join(suffix)
                } else if let Some(suffix) = unquoted.strip_prefix("${HOME}/") {
                    home_dir().join(suffix)
                } else if unquoted == "$HOME" || unquoted == "${HOME}" {
                    home_dir()
                } else {
                    expand_home(unquoted)
                };
                if expanded.is_absolute() {
                    return Some(expanded);
                }
            }
        }
    }
    let default_music = home_dir().join("Music");
    if default_music.is_dir() {
        return Some(default_music);
    }
    None
}

fn split_valid_uri_scheme(value: &str) -> Option<(&str, &str)> {
    let (scheme, rest) = value.split_once("://")?;
    let mut bytes = scheme.bytes();
    let first = bytes.next()?;
    if !first.is_ascii_alphabetic() {
        return None;
    }
    if !bytes.all(|b| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'-' | b'.')) {
        return None;
    }
    Some((scheme, rest))
}

pub(crate) fn resolve_xesam_url(
    raw_path: &str,
    music_root: Option<&str>,
    xdg_music_dir: Option<&Path>,
) -> Option<String> {
    let trimmed = raw_path.trim();
    if trimmed.is_empty() {
        return None;
    }
    if let Some((scheme, after_scheme)) = split_valid_uri_scheme(trimmed) {
        if scheme.eq_ignore_ascii_case("file") {
            if after_scheme.starts_with('/') || after_scheme.starts_with("localhost/") {
                return Some(trimmed.to_string());
            }
            return None;
        }
        return Some(trimmed.to_string());
    }
    let candidate = expand_home(trimmed);
    if candidate.is_absolute() {
        return Some(file_url(&candidate));
    }
    if let Some(root) = music_root.map(str::trim).filter(|s| !s.is_empty()) {
        let base = expand_home(root);
        if base.is_absolute() {
            return Some(file_url(&base.join(&candidate)));
        }
    }
    let has_parent_dir = candidate
        .components()
        .any(|c| matches!(c, Component::ParentDir));
    if !has_parent_dir
        && let Some(music_dir) = xdg_music_dir.filter(|d| d.is_absolute())
    {
        let joined = music_dir.join(&candidate);
        if joined.exists() {
            return Some(file_url(&joined));
        }
    }
    None
}

#[cfg(test)]
pub(crate) fn state_from_payload(payload: &Value) -> MprisState {
    state_from_payload_with_root(payload, None)
}

pub(crate) fn state_from_payload_with_root(
    payload: &Value,
    music_root: Option<&str>,
) -> MprisState {
    let has_root = music_root.is_some_and(|r| !r.trim().is_empty())
        || payload
            .get("musicRoot")
            .and_then(Value::as_str)
            .is_some_and(|r| !r.trim().is_empty());
    let raw_path = payload
        .get("current")
        .and_then(|c| c.get("path"))
        .and_then(Value::as_str)
        .map(str::trim)
        .unwrap_or("");
    let needs_xdg = !has_root
        && !raw_path.is_empty()
        && split_valid_uri_scheme(raw_path).is_none()
        && !expand_home(raw_path).is_absolute();
    let matched_dir = if needs_xdg {
        let has_parent_dir = Path::new(raw_path)
            .components()
            .any(|c| matches!(c, Component::ParentDir));
        if has_parent_dir {
            None
        } else {
            [crate::configured_mpd_music_dir(), resolve_xdg_music_dir()]
                .into_iter()
                .flatten()
                .find(|dir| dir.is_absolute() && dir.join(raw_path).exists())
        }
    } else {
        None
    };
    state_from_payload_with_dirs(payload, music_root, matched_dir.as_deref())
}

pub(crate) fn state_from_payload_with_dirs(
    payload: &Value,
    music_root: Option<&str>,
    xdg_music_dir: Option<&Path>,
) -> MprisState {
    let mut s = MprisState::default();
    let status = payload.get("status").and_then(Value::as_object);
    let current = payload.get("current").and_then(Value::as_object);
    let effective_root = music_root
        .map(str::trim)
        .filter(|r| !r.is_empty())
        .or_else(|| {
            payload
                .get("musicRoot")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|r| !r.is_empty())
        });

    if let Some(st) = status {
        s.playback_status = match st.get("state").and_then(Value::as_str).unwrap_or("stop") {
            "play" => "Playing".to_string(),
            "pause" => "Paused".to_string(),
            _ => "Stopped".to_string(),
        };
        let repeat = st.get("repeat").and_then(Value::as_str) == Some("1");
        let single = st.get("single").and_then(Value::as_str) == Some("1");
        s.loop_status = if repeat && single {
            "Track".to_string()
        } else if repeat {
            "Playlist".to_string()
        } else {
            "None".to_string()
        };
        s.shuffle = st.get("random").and_then(Value::as_str) == Some("1");
        if let Some(vol_s) = st.get("volume").and_then(Value::as_str)
            && let Ok(vol) = vol_s.parse::<f64>()
            && vol >= 0.0
        {
            s.volume = (vol / 100.0).clamp(0.0, 1.0);
        }
        let elapsed_s = st
            .get("elapsed")
            .and_then(Value::as_str)
            .and_then(|v| v.parse::<f64>().ok())
            .unwrap_or(0.0);
        s.position_us = (elapsed_s.max(0.0) * 1_000_000.0) as i64;
        let dur_s = st
            .get("duration")
            .and_then(Value::as_str)
            .and_then(|v| v.parse::<f64>().ok())
            .unwrap_or(0.0);
        s.length_us = (dur_s.max(0.0) * 1_000_000.0) as i64;
    }

    if let Some(cur) = current {
        let song_id_owned: String = cur
            .get("queueId")
            .and_then(|v| {
                v.as_i64()
                    .filter(|&n| n > 0)
                    .map(|n| n.to_string())
                    .or_else(|| v.as_str().filter(|s| !s.is_empty()).map(str::to_owned))
            })
            .or_else(|| {
                status
                    .and_then(|st| st.get("songid"))
                    .and_then(Value::as_str)
                    .filter(|s| !s.is_empty())
                    .map(str::to_owned)
            })
            .or_else(|| {
                cur.get("songId")
                    .or_else(|| cur.get("id"))
                    .and_then(|v| {
                        v.as_str()
                            .filter(|s| !s.is_empty())
                            .map(str::to_owned)
                            .or_else(|| v.as_i64().filter(|&n| n > 0).map(|n| n.to_string()))
                    })
            })
            .unwrap_or_else(|| "0".to_string());
        let clean_id: String = song_id_owned
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '_')
            .collect();
        s.track_id = format!(
            "/org/mpris/MediaPlayer2/Track/{}",
            if clean_id.is_empty() { "0" } else { &clean_id }
        );
        s.title = cur
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        s.artist = cur
            .get("artist")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        s.album = cur
            .get("album")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        s.album_artist = cur
            .get("albumArtist")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        if let Some(art) = cur
            .get("art")
            .or_else(|| cur.get("artUrl"))
            .or_else(|| cur.get("artwork"))
            .and_then(Value::as_str)
            && !art.is_empty()
        {
            s.art_url = resolve_xesam_url(art, None, None).unwrap_or_default();
        }
        if let Some(path) = cur.get("path").and_then(Value::as_str)
            && !path.is_empty()
        {
            s.url = resolve_xesam_url(path, effective_root, xdg_music_dir).unwrap_or_default();
        }
        if s.length_us <= 0
            && let Some(d) = cur.get("duration").and_then(Value::as_f64)
            && d > 0.0
        {
            s.length_us = (d * 1_000_000.0) as i64;
        }
        s.track_number = cur
            .get("track")
            .or_else(|| cur.get("trackNumber"))
            .and_then(Value::as_i64)
            .unwrap_or(0) as i32;
    }

    s
}

fn build_metadata(state: &MprisState) -> DBusValue {
    let mut entries: Vec<(DBusValue, DBusValue)> = vec![(
        DBusValue::String("mpris:trackid".into()),
        DBusValue::Variant("o".into(), Box::new(DBusValue::ObjectPath(state.track_id.clone()))),
    )];
    if state.length_us > 0 {
        entries.push((
            DBusValue::String("mpris:length".into()),
            DBusValue::Variant("x".into(), Box::new(DBusValue::Int64(state.length_us))),
        ));
    }
    if !state.art_url.is_empty() {
        entries.push((
            DBusValue::String("mpris:artUrl".into()),
            DBusValue::Variant("s".into(), Box::new(DBusValue::String(state.art_url.clone()))),
        ));
    }
    if !state.title.is_empty() {
        entries.push((
            DBusValue::String("xesam:title".into()),
            DBusValue::Variant("s".into(), Box::new(DBusValue::String(state.title.clone()))),
        ));
    }
    if !state.artist.is_empty() {
        entries.push((
            DBusValue::String("xesam:artist".into()),
            DBusValue::Variant(
                "as".into(),
                Box::new(DBusValue::Array(
                    "s".into(),
                    vec![DBusValue::String(state.artist.clone())],
                )),
            ),
        ));
    }
    if !state.album.is_empty() {
        entries.push((
            DBusValue::String("xesam:album".into()),
            DBusValue::Variant("s".into(), Box::new(DBusValue::String(state.album.clone()))),
        ));
    }
    if !state.album_artist.is_empty() {
        entries.push((
            DBusValue::String("xesam:albumArtist".into()),
            DBusValue::Variant(
                "as".into(),
                Box::new(DBusValue::Array(
                    "s".into(),
                    vec![DBusValue::String(state.album_artist.clone())],
                )),
            ),
        ));
    }
    if !state.url.is_empty() {
        entries.push((
            DBusValue::String("xesam:url".into()),
            DBusValue::Variant("s".into(), Box::new(DBusValue::String(state.url.clone()))),
        ));
    }
    if state.track_number > 0 {
        entries.push((
            DBusValue::String("xesam:trackNumber".into()),
            DBusValue::Variant("i".into(), Box::new(DBusValue::Int32(state.track_number))),
        ));
    }
    DBusValue::Dict("s".into(), "v".into(), entries)
}

fn root_props() -> Vec<(DBusValue, DBusValue)> {
    vec![
        (DBusValue::String("CanQuit".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(false)))),
        (DBusValue::String("CanRaise".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(true)))),
        (DBusValue::String("HasTrackList".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(false)))),
        (DBusValue::String("Identity".into()), DBusValue::Variant("s".into(), Box::new(DBusValue::String("Music Player Daemon".into())))),
        (DBusValue::String("DesktopEntry".into()), DBusValue::Variant("s".into(), Box::new(DBusValue::String("alis-local-music".into())))),
        (
            DBusValue::String("SupportedUriSchemes".into()),
            DBusValue::Variant("as".into(), Box::new(DBusValue::Array("s".into(), vec![DBusValue::String("file".into())]))),
        ),
        (
            DBusValue::String("SupportedMimeTypes".into()),
            DBusValue::Variant(
                "as".into(),
                Box::new(DBusValue::Array(
                    "s".into(),
                    vec![
                        DBusValue::String("audio/mpeg".into()),
                        DBusValue::String("audio/flac".into()),
                        DBusValue::String("audio/ogg".into()),
                        DBusValue::String("audio/mp4".into()),
                        DBusValue::String("audio/wav".into()),
                        DBusValue::String("audio/opus".into()),
                    ],
                )),
            ),
        ),
    ]
}

fn player_props(state: &MprisState, fetched_at: Instant) -> Vec<(DBusValue, DBusValue)> {
    let effective_pos = if state.playback_status == "Playing" {
        let extra = fetched_at.elapsed().as_micros() as i64;
        if state.length_us > 0 {
            (state.position_us + extra).min(state.length_us)
        } else {
            state.position_us + extra
        }
    } else {
        state.position_us
    };

    vec![
        (DBusValue::String("PlaybackStatus".into()), DBusValue::Variant("s".into(), Box::new(DBusValue::String(state.playback_status.clone())))),
        (DBusValue::String("LoopStatus".into()), DBusValue::Variant("s".into(), Box::new(DBusValue::String(state.loop_status.clone())))),
        (DBusValue::String("Rate".into()), DBusValue::Variant("d".into(), Box::new(DBusValue::Double(1.0)))),
        (DBusValue::String("Shuffle".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(state.shuffle)))),
        (DBusValue::String("Metadata".into()), DBusValue::Variant("a{sv}".into(), Box::new(build_metadata(state)))),
        (DBusValue::String("Volume".into()), DBusValue::Variant("d".into(), Box::new(DBusValue::Double(state.volume)))),
        (DBusValue::String("Position".into()), DBusValue::Variant("x".into(), Box::new(DBusValue::Int64(effective_pos)))),
        (DBusValue::String("MinimumRate".into()), DBusValue::Variant("d".into(), Box::new(DBusValue::Double(1.0)))),
        (DBusValue::String("MaximumRate".into()), DBusValue::Variant("d".into(), Box::new(DBusValue::Double(1.0)))),
        (DBusValue::String("CanGoNext".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(true)))),
        (DBusValue::String("CanGoPrevious".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(true)))),
        (DBusValue::String("CanPlay".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(true)))),
        (DBusValue::String("CanPause".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(true)))),
        (DBusValue::String("CanSeek".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(true)))),
        (DBusValue::String("CanControl".into()), DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(true)))),
    ]
}

fn fetch_state(manager: &MpdManager) -> Option<MprisState> {
    manager
        .with_client(|client, root, art| {
            let mut payload = status_payload_mode_with_art(client, root, false, art)?;
            if let Some(current) = payload.get_mut("current") {
                resolve_current_mpd_art(client, current, art);
            }
            Ok((payload, root.to_string()))
        })
        .ok()
        .map(|(payload, root)| state_from_payload_with_root(&payload, Some(&root)))
}

fn emit_changes(conn: &mut DBusConnection, prev: &MprisState, next: &MprisState) {
    let mut changed = Vec::new();
    if prev.playback_status != next.playback_status {
        changed.push((
            DBusValue::String("PlaybackStatus".into()),
            DBusValue::Variant("s".into(), Box::new(DBusValue::String(next.playback_status.clone()))),
        ));
    }
    if prev.loop_status != next.loop_status {
        changed.push((
            DBusValue::String("LoopStatus".into()),
            DBusValue::Variant("s".into(), Box::new(DBusValue::String(next.loop_status.clone()))),
        ));
    }
    if prev.shuffle != next.shuffle {
        changed.push((
            DBusValue::String("Shuffle".into()),
            DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(next.shuffle))),
        ));
    }
    if (prev.volume - next.volume).abs() > 0.004 {
        changed.push((
            DBusValue::String("Volume".into()),
            DBusValue::Variant("d".into(), Box::new(DBusValue::Double(next.volume))),
        ));
    }
    if prev.track_id != next.track_id
        || prev.title != next.title
        || prev.artist != next.artist
        || prev.album != next.album
        || prev.art_url != next.art_url
        || prev.url != next.url
        || prev.length_us != next.length_us
    {
        changed.push((
            DBusValue::String("Metadata".into()),
            DBusValue::Variant("a{sv}".into(), Box::new(build_metadata(next))),
        ));
    }
    if !changed.is_empty() {
        let _ = conn.send_signal(
            MPRIS_PATH,
            IFACE_PROPS,
            "PropertiesChanged",
            "sa{sv}as",
            &[
                DBusValue::String(IFACE_PLAYER.into()),
                DBusValue::Dict("s".into(), "v".into(), changed),
                DBusValue::Array("s".into(), vec![]),
            ],
        );
    }
}

fn handle_call(
    conn: &mut DBusConnection,
    msg: &DBusMessage,
    manager: &MpdManager,
    state: &mut MprisState,
    fetched_at: &mut Instant,
) {
    let sender = msg.sender.as_deref();
    let iface = msg.interface.as_deref().unwrap_or("");
    let member = msg.member.as_deref().unwrap_or("");
    let path = msg.path.as_deref().unwrap_or(MPRIS_PATH);

    match (iface, member) {
        (IFACE_INTROSPECT | "", "Introspect") => {
            let xml = match path {
                "/" => "<node><node name=\"org\"/></node>",
                "/org" => "<node><node name=\"mpris\"/></node>",
                "/org/mpris" => "<node><node name=\"MediaPlayer2\"/></node>",
                _ => INTROSPECT_XML,
            };
            let _ = conn.send_reply(
                msg.serial,
                sender,
                "s",
                &[DBusValue::String(xml.to_string())],
            );
        }
        (IFACE_PEER | "", "Ping") => {
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PEER | "", "GetMachineId") => {
            let id = std::fs::read_to_string("/etc/machine-id")
                .or_else(|_| std::fs::read_to_string("/var/lib/dbus/machine-id"))
                .unwrap_or_default()
                .trim()
                .to_string();
            let _ = conn.send_reply(msg.serial, sender, "s", &[DBusValue::String(id)]);
        }
        (IFACE_PROPS | "", "GetAll") => {
            let target = msg.body.first().and_then(DBusValue::as_str).unwrap_or("");
            let props = match target {
                IFACE_ROOT => root_props(),
                IFACE_PLAYER => player_props(state, *fetched_at),
                _ => Vec::new(),
            };
            let _ = conn.send_reply(
                msg.serial,
                sender,
                "a{sv}",
                &[DBusValue::Dict("s".into(), "v".into(), props)],
            );
        }
        (IFACE_PROPS | "", "Get") => {
            let target = msg.body.first().and_then(DBusValue::as_str).unwrap_or("");
            let prop = msg.body.get(1).and_then(DBusValue::as_str).unwrap_or("");
            let list = match target {
                IFACE_ROOT => root_props(),
                IFACE_PLAYER => player_props(state, *fetched_at),
                _ => Vec::new(),
            };
            if let Some((_, val)) = list.into_iter().find(|(k, _)| k.as_str() == Some(prop)) {
                let _ = conn.send_reply(msg.serial, sender, "v", &[val]);
            } else {
                let _ = conn.send_error(
                    msg.serial,
                    sender,
                    "org.freedesktop.DBus.Error.UnknownProperty",
                    &format!("Unknown property {target}.{prop}"),
                );
            }
        }
        (IFACE_PROPS | "", "Set") => {
            let prop = msg.body.get(1).and_then(DBusValue::as_str).unwrap_or("");
            if let Some(val) = msg.body.get(2) {
                match prop {
                    "Volume" => {
                        if let Some(v) = val.as_f64() {
                            let pct = (v.clamp(0.0, 1.0) * 100.0).round() as i32;
                            let _ = manager.with_client(|c, _, _| c.command("setvol", [pct.to_string()]));
                        }
                    }
                    "Shuffle" => {
                        if let Some(b) = val.as_bool() {
                            let _ = manager.with_client(|c, _, _| c.command("random", [if b { "1" } else { "0" }]));
                        }
                    }
                    "LoopStatus" => {
                        if let Some(ls) = val.as_str() {
                            let (rep, sin) = match ls {
                                "Track" => ("1", "1"),
                                "Playlist" => ("1", "0"),
                                _ => ("0", "0"),
                            };
                            let _ = manager.with_client(|c, _, _| {
                                let _ = c.command("repeat", [rep]);
                                c.command("single", [sin])
                            });
                        }
                    }
                    _ => {}
                }
            }
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_ROOT | "", "Raise") | (IFACE_ROOT | "", "Quit") => {
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "Play") => {
            let _ = manager.with_client(|c, _, _| c.command("play", std::iter::empty::<&str>()));
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "Pause") => {
            let _ = manager.with_client(|c, _, _| c.command("pause", ["1"]));
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "PlayPause") => {
            let next_cmd = if state.playback_status == "Playing" {
                ("pause", Some("1"))
            } else if state.playback_status == "Paused" {
                ("pause", Some("0"))
            } else {
                ("play", None)
            };
            let _ = manager.with_client(|c, _, _| {
                if let Some(arg) = next_cmd.1 {
                    c.command(next_cmd.0, [arg])
                } else {
                    c.command(next_cmd.0, std::iter::empty::<&str>())
                }
            });
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "Stop") => {
            let _ = manager.with_client(|c, _, _| c.command("stop", std::iter::empty::<&str>()));
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "Next") => {
            let _ = manager.with_client(|c, _, _| c.command("next", std::iter::empty::<&str>()));
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "Previous") => {
            let _ = manager.with_client(|c, _, _| c.command("previous", std::iter::empty::<&str>()));
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "Seek") => {
            if let Some(offset_us) = msg.body.first().and_then(DBusValue::as_i64) {
                let delta_s = offset_us as f64 / 1_000_000.0;
                let arg = if delta_s >= 0.0 {
                    format!("+{delta_s:.3}")
                } else {
                    format!("{delta_s:.3}")
                };
                let _ = manager.with_client(|c, _, _| c.command("seekcur", [arg.as_str()]));
                if let Some(refreshed) = fetch_state(manager) {
                    let _ = conn.send_signal(
                        MPRIS_PATH,
                        IFACE_PLAYER,
                        "Seeked",
                        "x",
                        &[DBusValue::Int64(refreshed.position_us)],
                    );
                    *state = refreshed;
                    *fetched_at = Instant::now();
                }
            }
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "SetPosition") => {
            if let Some(pos_us) = msg.body.get(1).and_then(DBusValue::as_i64) {
                let sec = (pos_us.max(0) as f64) / 1_000_000.0;
                let arg = format!("{sec:.3}");
                let _ = manager.with_client(|c, _, _| c.command("seekcur", [arg.as_str()]));
                let _ = conn.send_signal(
                    MPRIS_PATH,
                    IFACE_PLAYER,
                    "Seeked",
                    "x",
                    &[DBusValue::Int64(pos_us.max(0))],
                );
            }
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        (IFACE_PLAYER | "", "OpenUri") => {
            if let Some(uri) = msg.body.first().and_then(DBusValue::as_str) {
                let clean = uri.strip_prefix("file://").unwrap_or(uri);
                let _ = manager.with_client(|c, _, _| {
                    let _ = c.command("add", [clean]);
                    c.command("play", std::iter::empty::<&str>())
                });
            }
            let _ = conn.send_reply(msg.serial, sender, "", &[]);
        }
        _ => {
            let _ = conn.send_error(
                msg.serial,
                sender,
                "org.freedesktop.DBus.Error.UnknownMethod",
                &format!("Unknown method {iface}.{member}"),
            );
        }
    }
}

pub(crate) fn run_mpris_bridge(manager: Arc<MpdManager>, preferred_name: Option<&str>) -> Result<()> {
    let mut conn = DBusConnection::connect_session()?;
    let primary_name = preferred_name.unwrap_or("org.mpris.MediaPlayer2.mpd");
    // DBUS_NAME_FLAG_DO_NOT_QUEUE = 4; reply 1 = PRIMARY_OWNER, 4 = ALREADY_OWNER
    let res = conn.request_name(primary_name, 4)?;
    if res != 1 && res != 4 {
        // Another MPRIS bridge (e.g. embedded alis-mpdd or external mpd-mpris) already owns
        // this exact bus name. Exit cleanly rather than registering a duplicate player.
        return Ok(());
    }

    let mut state = fetch_state(&manager).unwrap_or_default();
    let mut fetched_at = Instant::now();
    let mut last_poll = Instant::now();

    loop {
        match conn.read_message_timeout(250)? {
            Some(msg) if msg.msg_type == MSG_METHOD_CALL => {
                handle_call(&mut conn, &msg, &manager, &mut state, &mut fetched_at);
                let next = fetch_state(&manager).unwrap_or_default();
                emit_changes(&mut conn, &state, &next);
                state = next;
                fetched_at = Instant::now();
                last_poll = Instant::now();
            }
            Some(_) => {}
            None => {}
        }

        if last_poll.elapsed() >= Duration::from_millis(800) {
            last_poll = Instant::now();
            let next = fetch_state(&manager).unwrap_or_default();
            emit_changes(&mut conn, &state, &next);
            state = next;
            fetched_at = Instant::now();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        build_metadata, resolve_xesam_url, state_from_payload, state_from_payload_with_dirs,
    };
    use serde_json::json;

    #[test]
    fn maps_mpd_status_payload_to_mpris_metadata() {
        let payload = json!({
            "connected": true,
            "status": {
                "state": "play",
                "repeat": "1",
                "single": "0",
                "random": "1",
                "volume": "75",
                "elapsed": "12.5",
                "duration": "240.0",
                "songid": "42"
            },
            "current": {
                "queueId": 42,
                "title": "Test Track",
                "artist": "Test Artist",
                "album": "Test Album",
                "art": "file:///tmp/cover.jpg",
                "path": "/music/test.flac",
                "track": 3
            }
        });
        let st = state_from_payload(&payload);
        assert_eq!(st.playback_status, "Playing");
        assert_eq!(st.loop_status, "Playlist");
        assert!(st.shuffle);
        assert!((st.volume - 0.75).abs() < 0.001);
        assert_eq!(st.position_us, 12_500_000);
        assert_eq!(st.length_us, 240_000_000);
        assert_eq!(st.track_id, "/org/mpris/MediaPlayer2/Track/42");
        assert_eq!(st.art_url, "file:///tmp/cover.jpg");
        assert_eq!(st.url, "file:///music/test.flac");
        assert_eq!(st.track_number, 3);
        let meta = build_metadata(&st);
        if let alis_dbus::DBusValue::Dict(_, _, entries) = meta {
            assert!(entries.iter().any(|(k, _)| k.as_str() == Some("xesam:title")));
            assert!(entries.iter().any(|(k, _)| k.as_str() == Some("mpris:artUrl")));
            assert!(entries.iter().any(|(k, _)| k.as_str() == Some("xesam:url")));
            assert!(entries.iter().any(|(k, _)| k.as_str() == Some("xesam:trackNumber")));
        } else {
            panic!("expected dict metadata");
        }
    }

    #[test]
    fn omits_invalid_relative_xesam_url_and_resolves_with_roots() {
        let payload = json!({
            "connected": true,
            "status": { "state": "play", "songid": "7" },
            "current": {
                "queueId": 7,
                "title": "Relative Song",
                "path": "MP3/song.mp3"
            }
        });

        // Without music_root or matching XDG_MUSIC_DIR file, xesam:url must be omitted
        let st_missing = state_from_payload_with_dirs(&payload, None, None);
        assert!(st_missing.url.is_empty());
        if let alis_dbus::DBusValue::Dict(_, _, entries) = build_metadata(&st_missing) {
            assert!(
                !entries.iter().any(|(k, _)| k.as_str() == Some("xesam:url")),
                "relative path without root must not emit invalid file://relative xesam:url"
            );
        } else {
            panic!("expected dict metadata");
        }

        // With explicit music_root, resolves to a valid absolute file:/// URI
        let st_with_root = state_from_payload_with_dirs(&payload, Some("/srv/music"), None);
        assert_eq!(st_with_root.url, "file:///srv/music/MP3/song.mp3");

        // With existing file under XDG_MUSIC_DIR fallback, resolves to file:/// URI
        let tmp_dir =
            std::env::temp_dir().join(format!("alis-mpris-music-{}", std::process::id()));
        let nested = tmp_dir.join("MP3");
        std::fs::create_dir_all(&nested).unwrap();
        let track_file = nested.join("song.mp3");
        std::fs::write(&track_file, b"id3").unwrap();
        let st_xdg = state_from_payload_with_dirs(&payload, None, Some(&tmp_dir));
        assert!(st_xdg.url.starts_with("file:///"));
        assert!(st_xdg.url.ends_with("/MP3/song.mp3"));
        let _ = std::fs::remove_dir_all(&tmp_dir);

        // Malformed relative file:// URI (any case) must be rejected; valid http/file:/// URIs preserved
        assert_eq!(resolve_xesam_url("file://MP3/song.mp3", None, None), None);
        assert_eq!(resolve_xesam_url("FILE://MP3/song.mp3", None, None), None);
        assert_eq!(
            resolve_xesam_url("file:///music/a.mp3", None, None).as_deref(),
            Some("file:///music/a.mp3")
        );
        assert_eq!(
            resolve_xesam_url("http://radio.example/stream.mp3", None, None).as_deref(),
            Some("http://radio.example/stream.mp3")
        );
        // Paths containing "://" without a valid URI scheme must not be mistaken for URIs
        assert_eq!(
            resolve_xesam_url("Artist/Weird :// Title.mp3", Some("/srv/music"), None).as_deref(),
            Some("file:///srv/music/Artist/Weird%20%3A//%20Title.mp3")
        );
        assert_eq!(
            resolve_xesam_url("Artist/Weird :// Title.mp3", None, None),
            None
        );
        // ParentDir traversal must not escape XDG_MUSIC_DIR fallback
        assert_eq!(
            resolve_xesam_url("../../etc/passwd", None, Some(std::path::Path::new("/tmp"))),
            None
        );
    }

    #[test]
    fn fetch_state_over_tcp_mpd_without_config_permission_omits_relative_url() {
        use std::io::{BufRead, BufReader, Write};
        use std::net::TcpListener;
        use std::thread;

        let listener = TcpListener::bind("127.0.0.1:0").expect("bind fake mpd");
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            for stream in listener.incoming().take(2) {
                let mut stream = stream.expect("accept");
                stream.write_all(b"OK MPD 0.23.0\n").unwrap();
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                while reader.read_line(&mut line).unwrap_or(0) > 0 {
                    let cmd = line.trim();
                    match cmd {
                        "config" => {
                            stream
                                .write_all(b"ACK [4@0] {config} you don't have permission for \"config\"\n")
                                .unwrap();
                        }
                        "status" => {
                            stream
                                .write_all(b"state: play\nvolume: 80\nsongid: 9\nelapsed: 5.0\nduration: 120.0\nOK\n")
                                .unwrap();
                        }
                        "currentsong" => {
                            stream
                                .write_all(b"file: __alis_nonexistent_dir__/track.mp3\nTitle: Rel Track\nId: 9\nOK\n")
                                .unwrap();
                        }
                        _ => {
                            stream.write_all(b"OK\n").unwrap();
                        }
                    }
                    line.clear();
                }
            }
        });

        let mgr_no_root = crate::MpdManager::new("127.0.0.1".into(), port, String::new());
        let st_no_root = super::fetch_state(&mgr_no_root).expect("fetch without root");
        assert_eq!(st_no_root.title, "Rel Track");
        assert!(
            st_no_root.url.is_empty(),
            "relative MPD track without music_root or local XDG match must omit xesam:url, got: {}",
            st_no_root.url
        );
        drop(mgr_no_root);

        let mgr_with_root =
            crate::MpdManager::new("127.0.0.1".into(), port, "/srv/library".into());
        let st_with_root = super::fetch_state(&mgr_with_root).expect("fetch with root");
        assert_eq!(
            st_with_root.url,
            "file:///srv/library/__alis_nonexistent_dir__/track.mp3"
        );
        drop(mgr_with_root);
        server.join().expect("join fake mpd server");
    }

    #[test]
    fn fetch_state_over_tcp_mpd_fetches_albumart_without_music_root() {
        use std::io::{BufRead, BufReader, Write};
        use std::net::TcpListener;
        use std::sync::Arc;
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::thread;

        let listener = TcpListener::bind("127.0.0.1:0").expect("bind fake albumart mpd");
        let port = listener.local_addr().unwrap().port();
        let albumart_calls = Arc::new(AtomicUsize::new(0));
        let calls_ref = albumart_calls.clone();

        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept");
            stream.write_all(b"OK MPD 0.24.0\n").unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut line = String::new();
            while reader.read_line(&mut line).unwrap_or(0) > 0 {
                let cmd = line.trim();
                if cmd == "config" {
                    stream
                        .write_all(b"ACK [4@0] {config} Command only permitted to local clients\n")
                        .unwrap();
                } else if cmd == "status" {
                    stream
                        .write_all(b"state: play\nvolume: 80\nsongid: 19\nelapsed: 5.0\nduration: 180.0\nOK\n")
                        .unwrap();
                } else if cmd == "currentsong" {
                    stream
                        .write_all(b"file: __alis_nonexistent_albumart__/track.flac\nArtist: ArtTestArtist\nAlbum: ArtTestAlbum\nTitle: ArtTestTitle\nId: 19\nOK\n")
                        .unwrap();
                } else if cmd.starts_with("albumart ") {
                    calls_ref.fetch_add(1, Ordering::SeqCst);
                    let jpeg_bytes: &[u8] = b"\xFF\xD8\xFF\xE0\x00\x10JFIF";
                    stream
                        .write_all(
                            format!("size: {}\ntype: image/jpeg\nbinary: {}\n", jpeg_bytes.len(), jpeg_bytes.len())
                                .as_bytes(),
                        )
                        .unwrap();
                    stream.write_all(jpeg_bytes).unwrap();
                    stream.write_all(b"\nOK\n").unwrap();
                } else {
                    stream.write_all(b"OK\n").unwrap();
                }
                stream.flush().unwrap();
                line.clear();
            }
        });

        let tmp_cache =
            std::env::temp_dir().join(format!("alis-mpris-art-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp_cache);
        std::fs::create_dir_all(&tmp_cache).unwrap();

        let mgr = crate::MpdManager::new("127.0.0.1".into(), port, String::new());
        mgr.art_lookup.lock().unwrap().cache = tmp_cache.clone();

        let st1 = super::fetch_state(&mgr).expect("first fetch_state");
        assert!(st1.art_url.starts_with("file:///"), "expected file:/// artUrl, got {}", st1.art_url);
        let art_path_str = st1.art_url.strip_prefix("file://").unwrap();
        let art_path = std::path::Path::new(art_path_str);
        assert!(art_path.starts_with(&tmp_cache));
        assert_eq!(std::fs::metadata(art_path).unwrap().len(), 10);
        assert_eq!(albumart_calls.load(Ordering::SeqCst), 1);

        let st2 = super::fetch_state(&mgr).expect("second fetch_state");
        assert_eq!(st2.art_url, st1.art_url);
        assert_eq!(
            albumart_calls.load(Ordering::SeqCst),
            1,
            "second fetch_state must reuse cached cover art without re-fetching from MPD"
        );

        drop(mgr);
        let _ = std::fs::remove_dir_all(&tmp_cache);
        server.join().expect("join fake albumart mpd server");
    }
}
