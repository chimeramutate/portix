use serde::{Deserialize, Serialize};

use super::errors::{RdpError, Result};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RdpProfile {
    pub id: String,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: Option<String>,
    pub domain: Option<String>,
    pub desktop_width: u16,
    pub desktop_height: u16,
    pub enable_cred_ssp: bool,
}

impl RdpProfile {
    pub fn socket_addr(&self) -> String {
        format!("{}:{}", self.host, self.port)
    }

    pub fn validate(&self) -> Result<()> {
        if self.id.trim().is_empty() {
            return Err(RdpError::InvalidProfile("profile id is required".into()));
        }
        if self.host.trim().is_empty() {
            return Err(RdpError::InvalidProfile("host is required".into()));
        }
        if self.port == 0 {
            return Err(RdpError::InvalidProfile("port must be > 0".into()));
        }
        if self.username.trim().is_empty() {
            return Err(RdpError::InvalidProfile("username is required".into()));
        }
        Ok(())
    }
}
