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
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpFrameEvent {
    pub session_id: String,
    /// RGBA pixel data
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub x: u32,
    pub y: u32,
}
