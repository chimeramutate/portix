use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub enum RdpConnectionStatus {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpSessionInfo {
    pub id: String,
    pub profile_id: String,
    pub status: RdpConnectionStatus,
}

/// A raw bitmap frame delivered from the RDP server.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpBitmapFrame {
    pub session_id: String,
    /// RGBA pixel data, row-major, `width * height * 4` bytes.
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub x: u32,
    pub y: u32,
}
