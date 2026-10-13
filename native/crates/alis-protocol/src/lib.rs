use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum InputMessage {
    State {
        caps: bool,
        num: bool,
        devices: usize,
    },
    Ready {
        devices: usize,
    },
    Key {
        code: u16,
        pressed: bool,
    },
    Error {
        message: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Envelope<T> {
    pub v: u32,
    #[serde(flatten)]
    pub payload: T,
}

impl<T> Envelope<T> {
    pub fn new(payload: T) -> Self {
        Self {
            v: PROTOCOL_VERSION,
            payload,
        }
    }
}
