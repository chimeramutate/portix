use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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
    pub full_screen: bool,

    pub enable_cred_ssp: bool,
    pub alternate_shell: Option<String>,
    pub source_rdp_content: Option<String>,

    // ─────────────────────────────────────────────────────────────
    // RDP redirection
    // ─────────────────────────────────────────────────────────────
    /// Enable RDP drive redirection.
    pub redirect_drives: bool,

    /// Enable clipboard redirection.
    pub redirect_clipboard: bool,

    /// Local directory exposed to the remote Windows session.
    ///
    /// Example:
    /// /Users/user/Documents/PortixShare
    pub local_share_path: Option<String>,

    /// Name exposed through RDPDR.
    ///
    /// Remote Windows will normally access it through:
    /// \\tsclient\Portix
    pub local_share_name: String,
}

impl RdpProfile {
    pub fn socket_addr(&self) -> String {
        format!("{}:{}", self.host, self.port)
    }

    pub fn is_cyberark_psm(&self) -> bool {
        self.alternate_shell
            .as_ref()
            .map(|s| s.to_lowercase().contains("psm"))
            .unwrap_or(false)
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

        // Drive sharing validation.
        if self.redirect_drives {
            let path = self.local_share_path.as_deref().unwrap_or("").trim();

            if path.is_empty() {
                return Err(RdpError::InvalidProfile(
                    "local share path is required when drive redirection is enabled".into(),
                ));
            }

            if self.local_share_name.trim().is_empty() {
                return Err(RdpError::InvalidProfile(
                    "local share name is required when drive redirection is enabled".into(),
                ));
            }
        }

        Ok(())
    }

    pub fn connection_key(&self) -> String {
        format!(
            "{}:{}@{}:{}",
            self.host,
            self.port,
            self.username,
            self.domain.as_deref().unwrap_or("")
        )
    }

    /// Returns whether local drive sharing is actually configured.
    pub fn has_local_share(&self) -> bool {
        self.redirect_drives
            && self
                .local_share_path
                .as_deref()
                .map(|p| !p.trim().is_empty())
                .unwrap_or(false)
    }

    /// Returns the configured local share path.
    pub fn local_share_path(&self) -> Option<&str> {
        if !self.redirect_drives {
            return None;
        }

        self.local_share_path.as_deref()
    }

    /// Returns the RDPDR share name.
    pub fn local_share_name(&self) -> &str {
        if self.local_share_name.trim().is_empty() {
            "Portix"
        } else {
            self.local_share_name.trim()
        }
    }
}

impl Default for RdpProfile {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: String::new(),
            host: String::new(),
            port: 3389,

            username: String::new(),
            password: None,
            domain: None,

            desktop_width: 1280,
            desktop_height: 800,
            full_screen: false,

            enable_cred_ssp: true,
            alternate_shell: None,
            source_rdp_content: None,

            // RDP redirection defaults.
            redirect_drives: false,
            redirect_clipboard: true,

            local_share_path: None,
            local_share_name: "Portix".into(),
        }
    }
}

pub fn parse_rdp_file(
    content: &str,
    profile_id: &str,
    profile_name: Option<&str>,
) -> Result<RdpProfile> {
    let settings = parse_rdp_lines(content);

    let full_address = settings.get("full address").cloned().unwrap_or_default();

    let server_port_str = settings.get("server port").cloned();

    let username = settings.get("username").cloned().unwrap_or_default();

    let alternate_shell = settings.get("alternate shell").cloned();

    let desktop_width: u16 = settings
        .get("desktopwidth")
        .and_then(|v| v.parse().ok())
        .unwrap_or(1280);

    let desktop_height: u16 = settings
        .get("desktopheight")
        .and_then(|v| v.parse().ok())
        .unwrap_or(800);

    let screen_mode_id: i32 = settings
        .get("screen mode id")
        .and_then(|v| v.parse().ok())
        .unwrap_or(1);

    let enable_cred_ssp = settings
        .get("enablecredsspsupport")
        .and_then(|v| v.parse::<i32>().ok())
        .unwrap_or(1)
        == 1;

    // ─────────────────────────────────────────────────────────────
    // Parse host / port
    // ─────────────────────────────────────────────────────────────

    let (host, port) = if let Some(port_str) = server_port_str {
        let port = port_str.trim().parse::<u16>().unwrap_or(3389);

        (full_address.trim().to_owned(), port)
    } else {
        let parts: Vec<&str> = full_address.splitn(2, ':').collect();

        let host = parts
            .first()
            .map(|s| s.trim().to_owned())
            .unwrap_or_default();

        let port = parts
            .get(1)
            .and_then(|s| s.trim().parse::<u16>().ok())
            .unwrap_or(3389);

        (host, port)
    };

    // ─────────────────────────────────────────────────────────────
    // Parse DOMAIN\USERNAME
    // ─────────────────────────────────────────────────────────────

    let (parsed_domain, parsed_username) = if username.contains('\\') {
        let mut parts = username.splitn(2, '\\');

        let domain = parts.next().map(|s| s.trim().to_owned());

        let user = parts
            .next()
            .map(|s| s.trim().to_owned())
            .unwrap_or_default();

        (domain, user)
    } else {
        (None, username.clone())
    };

    // ─────────────────────────────────────────────────────────────
    // Profile name
    // ─────────────────────────────────────────────────────────────

    let name = if let Some(name) = profile_name {
        name.to_owned()
    } else if alternate_shell.is_some() {
        format!("CyberArk – {}", host)
    } else {
        format!("RDP – {}", host)
    };

    Ok(RdpProfile {
        id: profile_id.to_owned(),

        name,
        host,
        port,

        username: parsed_username,
        password: None,
        domain: parsed_domain,

        desktop_width,
        desktop_height,
        full_screen: screen_mode_id == 2,

        enable_cred_ssp,
        alternate_shell,

        source_rdp_content: Some(content.to_owned()),

        // Local drive sharing is deliberately NOT enabled
        // just because an .rdp file was imported.
        redirect_drives: false,
        redirect_clipboard: true,

        local_share_path: None,
        local_share_name: "Portix".into(),
    })
}

fn parse_rdp_lines(content: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();

    for line in content.lines() {
        let trimmed = line.trim();

        if trimmed.is_empty() {
            continue;
        }

        let Some(colon_pos) = trimmed.find(':') else {
            continue;
        };

        let key = trimmed[..colon_pos].trim().to_lowercase();

        let rest = &trimmed[colon_pos + 1..];

        let value = if let Some(second_colon) = rest.find(':') {
            rest[second_colon + 1..].trim().to_owned()
        } else {
            rest.trim().to_owned()
        };

        map.insert(key, value);
    }

    map
}

#[cfg(test)]
mod tests {
    use super::*;

    const CYBERARK_RDP: &str = r#"full address:s:172.20.35.10
server port:i:3389
username:s:localhost\PSM\@abc123
alternate shell:s:PSM\@abc123
desktopwidth:i:1920
desktopheight:i:1080
EnableCredSspSupport:i:1"#;

    #[test]
    fn parse_cyberark_rdp_file() {
        let profile = parse_rdp_file(CYBERARK_RDP, "test-id", None).unwrap();

        assert_eq!(profile.host, "172.20.35.10");
        assert_eq!(profile.port, 3389);
        assert_eq!(profile.username, "PSM\\@abc123");
        assert_eq!(profile.domain.as_deref(), Some("localhost"));

        assert!(profile.is_cyberark_psm());

        assert_eq!(profile.alternate_shell.as_deref(), Some("PSM\\@abc123"));

        assert!(!profile.redirect_drives);
        assert_eq!(profile.local_share_path, None);
        assert_eq!(profile.local_share_name, "Portix");
    }

    #[test]
    fn test_connection_key() {
        let p1 = RdpProfile {
            id: "uuid-1".into(),
            host: "10.0.0.1".into(),
            port: 3389,
            username: "admin".into(),
            domain: None,
            ..Default::default()
        };

        let p2 = RdpProfile {
            id: "uuid-2".into(),
            host: "10.0.0.1".into(),
            port: 3389,
            username: "admin".into(),
            domain: None,
            ..Default::default()
        };

        assert_eq!(p1.connection_key(), p2.connection_key());
    }

    #[test]
    fn local_share_requires_path() {
        let profile = RdpProfile {
            redirect_drives: true,
            local_share_path: None,
            ..Default::default()
        };

        assert!(profile.validate().is_err());
    }

    #[test]
    fn local_share_is_valid() {
        let profile = RdpProfile {
            redirect_drives: true,
            local_share_path: Some("/tmp/PortixShare".into()),
            local_share_name: "Portix".into(),
            ..Default::default()
        };

        assert!(profile.validate().is_ok());
        assert!(profile.has_local_share());
        assert_eq!(profile.local_share_name(), "Portix");
    }

    #[test]
    fn local_share_disabled_without_redirect() {
        let profile = RdpProfile {
            redirect_drives: false,
            local_share_path: Some("/tmp/PortixShare".into()),
            ..Default::default()
        };

        assert!(!profile.has_local_share());
        assert_eq!(profile.local_share_path(), None);
    }
}
