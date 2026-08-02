use serde::{Deserialize, Serialize};

use super::session::RdpConnectionStatus;

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpStatusEvent {
    pub session_id: String,
    pub status: RdpConnectionStatus,
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpErrorEvent {
    pub session_id: Option<String>,
    pub message: String,

    #[serde(default = "default_error_code")]
    pub code: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpFrameEvent {
    pub session_id: String,

    pub data: Vec<u8>,

    pub width: u32,
    pub height: u32,

    pub x: u32,
    pub y: u32,

    pub frame_id: u64,
    pub chunk_index: u32,
    pub chunk_count: u32,
}

fn default_error_code() -> String {
    "UNKNOWN".to_string()
}
