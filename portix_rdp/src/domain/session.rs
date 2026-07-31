use serde::{Deserialize, Serialize};
use std::fmt;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub enum RdpConnectionStatus {
    Disconnected,
    Connecting,
    Connected,
    Error,
}


impl fmt::Display for RdpConnectionStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Disconnected => write!(f, "disconnected"),
            Self::Connecting => write!(f, "connecting"),
            Self::Connected => write!(f, "connected"),
            Self::Error => write!(f, "error"),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpSessionInfo {
    pub id: String,
    pub profile_id: String,
    pub status: RdpConnectionStatus,
}

impl RdpSessionInfo {
    
    pub fn is_active(&self) -> bool {
        matches!(self.status, RdpConnectionStatus::Connecting | RdpConnectionStatus::Connected)
    }
}

#[allow(dead_code)]
#[deprecated(
    note = "Use RdpFrameEvent from events.rs instead. Raw Vec<u8> is inefficient for JSON transfer."
)]
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpBitmapFrame {
    pub session_id: String,
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub x: u32,
    pub y: u32,
}


