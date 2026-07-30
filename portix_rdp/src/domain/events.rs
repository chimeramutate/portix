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
    /// Pixel data dikodekan sebagai base64 string (BGRA8888, row-major, no padding).
    /// Menggunakan base64 agar transfer melalui JSON jauh lebih efisien dibanding
    /// array of integers (base64 ~1.33x ukuran data mentah, vs JSON int array ~4x).
    pub data: String,
    pub width: u32,
    pub height: u32,
    pub x: u32,
    pub y: u32,
}
