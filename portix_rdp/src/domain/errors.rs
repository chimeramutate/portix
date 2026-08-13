use thiserror::Error;

#[derive(Debug, Error)]
pub enum RdpError {
    #[error("invalid profile: {0}")]
    InvalidProfile(String),
    
    #[error("session not found: {0}")]
    SessionNotFound(String),
    
    
    #[error("session already exists: {0}")]
    SessionAlreadyExists(String),
    
    
    #[error("operation cancelled")]
    Cancelled,
    
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
    
    
    #[error("bridge error: {0}")]
    Bridge(String),
    
    #[error(transparent)]
    Io(#[from] std::io::Error),
    
    #[error(transparent)]
    Anyhow(#[from] anyhow::Error),
}



impl Clone for RdpError {
    fn clone(&self) -> Self {
        match self {
            Self::InvalidProfile(s) => Self::InvalidProfile(s.clone()),
            Self::SessionNotFound(s) => Self::SessionNotFound(s.clone()),
            Self::SessionAlreadyExists(s) => Self::SessionAlreadyExists(s.clone()),
            Self::Cancelled => Self::Cancelled,
            Self::ConnectionTimeout => Self::ConnectionTimeout,
            Self::AuthenticationFailed => Self::AuthenticationFailed,
            Self::NegotiationFailed(s) => Self::NegotiationFailed(s.clone()),
            Self::Protocol(s) => Self::Protocol(s.clone()),
            Self::Disconnected => Self::Disconnected,
            Self::Bridge(s) => Self::Bridge(s.clone()),
            Self::Io(e) => Self::Io(std::io::Error::new(e.kind(), e.to_string())),
            Self::Anyhow(e) => Self::Bridge(e.to_string()), 
        }
    }
}

pub type Result<T> = std::result::Result<T, RdpError>;


impl RdpError {
    
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidProfile(_) => "INVALID_PROFILE",
            Self::SessionNotFound(_) => "SESSION_NOT_FOUND",
            Self::SessionAlreadyExists(_) => "SESSION_ALREADY_EXISTS",
            Self::Cancelled => "CANCELLED",
            Self::ConnectionTimeout => "CONNECTION_TIMEOUT",
            Self::AuthenticationFailed => "AUTH_FAILED",
            Self::NegotiationFailed(_) => "NEGOTIATION_FAILED",
            Self::Protocol(_) => "PROTOCOL_ERROR",
            Self::Disconnected => "DISCONNECTED",
            Self::Bridge(_) => "BRIDGE_ERROR",
            Self::Io(_) => "IO_ERROR",
            Self::Anyhow(_) => "UNKNOWN_ERROR",
        }
    }

    
    pub fn is_user_visible(&self) -> bool {
        matches!(
            self,
            Self::InvalidProfile(_)
                | Self::ConnectionTimeout
                | Self::AuthenticationFailed
                | Self::NegotiationFailed(_)
                | Self::Protocol(_)
        )
    }

    
    pub fn is_transient(&self) -> bool {
        matches!(
            self,
            Self::SessionNotFound(_) | Self::Cancelled | Self::Disconnected
        )
    }
}