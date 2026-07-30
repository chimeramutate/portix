#[cfg(test)]
mod tests {
    use super::super::profile::{parse_rdp_file, RdpProfile};

    // Sample CyberArk RDP yang valid
    const VALID_CYBERARK_RDP: &str = r#"full address:s:172.20.250.10
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

    // Sample dengan format hostname + port di full address
    const RDP_WITH_HOSTNAME: &str = r#"full address:s:testserver.example.com
server port:i:3389
username:s:DOMAIN\Administrator
desktopwidth:i:1920
desktopheight:i:1080
screen mode id:i:1
EnableCredSspSupport:i:1"#;

    // Sample dengan port di full address (bukan server port terpisah)
    const RDP_WITH_PORT_IN_ADDRESS: &str = r#"full address:s:192.168.1.100:3390
username:s:administrator
desktopwidth:i:1280
desktopheight:i:800
screen mode id:i:1"#;

    // Sample minimal
    const RDP_MINIMAL: &str = r#"full address:s:192.168.1.50
username:s:admin"#;

    #[test]
    fn test_parse_valid_cyberark_rdp() {
        let profile = parse_rdp_file(VALID_CYBERARK_RDP, "test-id", None).unwrap();
        
        assert_eq!(profile.id, "test-id");
        assert_eq!(profile.host, "172.20.250.10");
        assert_eq!(profile.port, 3389);
        assert_eq!(profile.username, "PSM@bf36d862-034b-4dc4-b152-54595752979b");
        assert_eq!(profile.domain.as_deref(), Some("localhost"));
        assert_eq!(profile.desktop_width, 1024);
        assert_eq!(profile.desktop_height, 768);
        assert!(profile.is_cyberark_psm());
        assert_eq!(
            profile.alternate_shell.as_deref(),
            Some("PSM@bf36d862-034b-4dc4-b152-54595752979b")
        );
        assert!(!profile.enable_cred_ssp); // EnableCredSspSupport:i:0
    }

    #[test]
    fn test_parse_with_hostname() {
        let profile = parse_rdp_file(RDP_WITH_HOSTNAME, "test-id", None).unwrap();
        
        assert_eq!(profile.host, "testserver.example.com");
        assert_eq!(profile.port, 3389);
        assert_eq!(profile.username, "Administrator");
        assert_eq!(profile.domain.as_deref(), Some("DOMAIN"));
        assert!(profile.enable_cred_ssp);
    }

    #[test]
    fn test_parse_with_port_in_address() {
        let profile = parse_rdp_file(RDP_WITH_PORT_IN_ADDRESS, "test-id", None).unwrap();
        
        assert_eq!(profile.host, "192.168.1.100");
        assert_eq!(profile.port, 3390); // Non-standard port
        assert_eq!(profile.username, "administrator");
        assert!(profile.domain.is_none());
    }

    #[test]
    fn test_parse_minimal_rdp() {
        let profile = parse_rdp_file(RDP_MINIMAL, "test-id", None).unwrap();
        
        assert_eq!(profile.host, "192.168.1.50");
        assert_eq!(profile.port, 3389); // Default
        assert_eq!(profile.username, "admin");
        assert_eq!(profile.desktop_width, 1280); // Default
        assert_eq!(profile.desktop_height, 800); // Default
    }

    #[test]
    fn test_profile_name_generation() {
        // CyberArk should use "CyberArk - host" format
        let profile1 = parse_rdp_file(VALID_CYBERARK_RDP, "id1", None).unwrap();
        assert!(profile1.name.contains("CyberArk"));
        assert!(profile1.name.contains("172.20.250.10"));

        // Custom name
        let profile2 = parse_rdp_file(VALID_CYBERARK_RDP, "id2", Some("My Server")).unwrap();
        assert_eq!(profile2.name, "My Server");

        // Regular RDP (no alternate shell)
        let profile3 = parse_rdp_file(RDP_MINIMAL, "id3", None).unwrap();
        assert!(profile3.name.contains("RDP"));
    }

    #[test]
    fn test_is_cyberark_psm_detection() {
        let cyberark = parse_rdp_file(VALID_CYBERARK_RDP, "id", None).unwrap();
        assert!(cyberark.is_cyberark_psm());

        let regular = parse_rdp_file(RDP_MINIMAL, "id", None).unwrap();
        assert!(!regular.is_cyberark_psm());
    }

    #[test]
    fn test_validate_profile() {
        let valid = parse_rdp_file(VALID_CYBERARK_RDP, "id", None).unwrap();
        assert!(valid.validate().is_ok());

        // Test invalid profile (empty host)
        let mut invalid = valid.clone();
        invalid.host = "".to_string();
        assert!(invalid.validate().is_err());

        // Test invalid profile (port 0)
        let mut invalid2 = valid.clone();
        invalid2.port = 0;
        assert!(invalid2.validate().is_err());
    }

    #[test]
    fn test_screen_mode_fullscreen() {
        // screen mode id:i:2 = fullscreen
        let fullscreen_rdp = r#"full address:s:192.168.1.1
username:s:user
screen mode id:i:2"#;
        let profile = parse_rdp_file(fullscreen_rdp, "id", None).unwrap();
        assert!(profile.full_screen);

        // screen mode id:i:1 = windowed
        let windowed_rdp = r#"full address:s:192.168.1.1
username:s:user
screen mode id:i:1"#;
        let profile = parse_rdp_file(windowed_rdp, "id", None).unwrap();
        assert!(!profile.full_screen);
    }

    #[test]
    fn test_case_insensitive_keys() {
        // RDP files sometimes have different casing
        let mixed_case = r#"Full Address:s:192.168.1.1
UserName:s:admin
DesktopWidth:i:1920
EnableCredSspSupport:i:1"#;
        
        let profile = parse_rdp_file(mixed_case, "id", None).unwrap();
        assert_eq!(profile.host, "192.168.1.1");
        assert_eq!(profile.username, "admin");
        assert_eq!(profile.desktop_width, 1920);
        assert!(profile.enable_cred_ssp);
    }

    #[test]
    fn test_malformed_port_fallback() {
        // Port dengan format salah harus fallback ke default 3389
        let bad_port = r#"full address:s:192.168.1.1
server port:i:invalid
username:s:admin"#;
        
        let profile = parse_rdp_file(bad_port, "id", None).unwrap();
        assert_eq!(profile.port, 3389); // Should fallback to default
    }

    #[test]
    fn test_empty_lines_and_whitespace() {
        let with_whitespace = r#"
        
full address:s:192.168.1.1
    
username:s:admin
        
desktopwidth:i:1024
    
"#;
        let profile = parse_rdp_file(with_whitespace, "id", None).unwrap();
        assert_eq!(profile.host, "192.168.1.1");
        assert_eq!(profile.username, "admin");
        assert_eq!(profile.desktop_width, 1024);
    }

    #[test]
    fn test_source_rdp_content_preserved() {
        let profile = parse_rdp_file(VALID_CYBERARK_RDP, "id", None).unwrap();
        assert!(profile.source_rdp_content.is_some());
        assert_eq!(profile.source_rdp_content.unwrap(), VALID_CYBERARK_RDP);
    }
}
