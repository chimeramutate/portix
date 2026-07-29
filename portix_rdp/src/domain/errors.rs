use thiserror::Error;

#[derive(Debug, Error)]
pub enum RdpError {
    #[error("invalid profile: {0}")]
    InvalidProfile(String),
    #[error("session not found: {0}")]
    SessionNotFound(String),
    #[error("connection timed out")]
    ConnectionTimeout,
    #[error("authentication failed")]
    AuthenticationFailed,
    #[error("RDP negotiation failed: {0}")]
    NegotiationFailed(String),
    #[error("RDP protocol error: {0}")]
    Protocol(String),
    #[error("disconnected")]
    Disconnected,
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Anyhow(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, RdpError>;
