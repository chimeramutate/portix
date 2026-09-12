use serde::{Deserialize, Serialize};

use super::session::RdpConnectionStatus;

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpStatusEvent {
    pub session_id: String,
    pub status: RdpConnectionStatus,
    pub message: Option<String>,
}

/// Event for debugging logs to be displayed in Flutter app
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpLogEvent {
    /// Timestamp of the log (Unix timestamp in seconds)
    pub timestamp: i64,
    /// Log level: INFO, WARN, ERROR, DEBUG
    pub level: String,
    /// Log message
    pub message: String,
    /// Optional session ID if related to a specific session
    pub session_id: Option<String>,
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
}

/// Event for clipboard data received from remote session
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpClipboardEvent {
    pub session_id: String,
    pub data: String,
}

fn default_error_code() -> String {
    "UNKNOWN".to_string()
}
