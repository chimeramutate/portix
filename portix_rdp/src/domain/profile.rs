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
    pub full_screen: bool,
    pub enable_cred_ssp: bool,
    /// Alternate shell (used by CyberArk PSM)
    pub alternate_shell: Option<String>,
    /// Original .rdp file content (for CyberArk PSM pass-through)
    pub source_rdp_content: Option<String>,
}

impl RdpProfile {
    pub fn socket_addr(&self) -> String {
        format!("{}:{}", self.host, self.port)
    }

    /// True if this profile came from a CyberArk PSM .rdp file.
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
        Ok(())
    }
}

/// Parses a .rdp file content string into an [RdpProfile].
/// Handles CyberArk PSM format: key:type:value per line.
pub fn parse_rdp_file(content: &str, profile_id: &str, profile_name: Option<&str>) -> Result<RdpProfile> {
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

    // Parse host and port from full address
    let (host, port) = if let Some(port_str) = server_port_str {
        let port = port_str.trim().parse::<u16>().unwrap_or(3389);
        (full_address.trim().to_owned(), port)
    } else {
        let parts: Vec<&str> = full_address.splitn(2, ':').collect();
        let host = parts.first().map(|s| s.trim().to_owned()).unwrap_or_default();
        let port = parts
            .get(1)
            .and_then(|s| s.trim().parse::<u16>().ok())
            .unwrap_or(3389);
        (host, port)
    };
    // Parse domain\username format (CyberArk format: localhost\PSM@sessionid)
    let (parsed_domain, parsed_username) = if username.contains('\\') {
        let mut parts = username.splitn(2, '\\');
        let domain = parts.next().map(|s| s.trim().to_owned());
        let user = parts.next().map(|s| s.trim().to_owned()).unwrap_or_default();
        (domain, user)
    } else {
        (None, username.clone())
    };

    // Derive profile name
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
    })
}

fn parse_rdp_lines(content: &str) -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        // Format: key:type:value
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
username:s:localhost\PSM@abc123
alternate shell:s:PSM@abc123
desktopwidth:i:1920
desktopheight:i:1080
EnableCredSspSupport:i:1"#;

    #[test]
    fn parse_cyberark_rdp_file() {
        let profile = parse_rdp_file(CYBERARK_RDP, "test-id", None).unwrap();
        assert_eq!(profile.host, "172.20.35.10");
        assert_eq!(profile.port, 3389);
        assert_eq!(profile.username, "PSM@abc123");
        assert_eq!(profile.domain.as_deref(), Some("localhost"));
        assert!(profile.is_cyberark_psm());
        assert_eq!(profile.alternate_shell.as_deref(), Some("PSM@abc123"));
    }
}


#[cfg(test)]
mod profile_tests {
    use super::*;

    // Sample file dari user (sudah diformat ulang dengan line breaks yang benar)
    const USER_SAMPLE_RDP: &str = r#"full address:s:172.20.250.testserver
server port:i:3389
username:s:localhost\PSM@bf36d862-034b-4dc4-b152-54595752979b
alternate shell:s:PSM@bf36d862-034b-4dc4-b152-54595752979b
desktopwidth:i:1024
desktopheight:i:768
screen mode id:i:2
redirectdrives:i:1
drivestoredirect:s:*
redirectsmartcards:i:0
EnableCredSspSupport:i:0
redirectcomports:i:0
remoteapplicationmode:i:0
use multimon:i:0
span monitors:i:0"#;

    #[test]
    fn test_parse_user_sample_rdp() {
        let profile = parse_rdp_file(USER_SAMPLE_RDP, "test-id", None).unwrap();
        
        // Validasi parsing
        assert_eq!(profile.id, "test-id");
        assert_eq!(profile.host, "172.20.250.testserver");
        assert_eq!(profile.port, 3389);
        assert_eq!(profile.username, "PSM@bf36d862-034b-4dc4-b152-54595752979b");
        assert_eq!(profile.domain.as_deref(), Some("localhost"));
        
        // Resolution
        assert_eq!(profile.desktop_width, 1024);
        assert_eq!(profile.desktop_height, 768);
        
        // Full screen (screen mode id:i:2)
        assert!(profile.full_screen);
        
        // CyberArk PSM detection
        assert!(profile.is_cyberark_psm());
        assert_eq!(
            profile.alternate_shell.as_deref(),
            Some("PSM@bf36d862-034b-4dc4-b152-54595752979b")
        );
        
        // CredSSP disabled
        assert!(!profile.enable_cred_ssp);
        
        // Name should include CyberArk
        assert!(profile.name.contains("CyberArk"));
    }

    #[test]
    fn test_parse_malformed_port() {
        // Simulasi port yang salah seperti "33test"
        let bad_port_rdp = r#"full address:s:192.168.1.1
server port:i:33test
username:s:admin"#;
        
        let profile = parse_rdp_file(bad_port_rdp, "id", None).unwrap();
        // Should fallback to default port 3389
        assert_eq!(profile.port, 3389);
    }

    #[test]
    fn test_case_insensitive_field_names() {
        // Test dengan berbagai kapitalisasi
        let mixed = r#"Full Address:s:test.com
SERVER PORT:i:3389
Username:s:user
DESKTOPWIDTH:i:1920
enablecredsspsupport:i:1"#;
        
        let profile = parse_rdp_file(mixed, "id", None).unwrap();
        assert_eq!(profile.host, "test.com");
        assert_eq!(profile.port, 3389);
        assert_eq!(profile.username, "user");
        assert_eq!(profile.desktop_width, 1920);
        assert!(profile.enable_cred_ssp);
    }
}
