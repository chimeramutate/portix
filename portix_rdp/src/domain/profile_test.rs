/// Comprehensive unit tests for RDP domain profile parsing and validation.
///
/// These tests cover:
/// - `.rdp` file parsing (CyberArk PSM, standard, edge cases)
/// - `RdpProfile` validation
/// - `connection_key` deduplication logic
/// - `is_cyberark_psm` detection
/// - `socket_addr` formatting
#[cfg(test)]
mod tests {
    use crate::domain::profile::{RdpProfile, parse_rdp_file};

    // =========================================================
    // HELPERS
    // =========================================================

    fn minimal_valid_profile() -> RdpProfile {
        RdpProfile {
            id: "test-id".into(),
            name: "Test RDP".into(),
            host: "192.168.1.100".into(),
            port: 3389,
            username: "administrator".into(),
            password: Some("P@ssword1".into()),
            ..Default::default()
        }
    }

    // =========================================================
    // VALIDATION — valid cases
    // =========================================================

    #[test]
    fn validate_accepts_minimal_valid_profile() {
        assert!(minimal_valid_profile().validate().is_ok());
    }

    #[test]
    fn validate_accepts_profile_with_domain() {
        let profile = RdpProfile {
            id: "id".into(),
            host: "10.0.0.1".into(),
            port: 3389,
            username: "user".into(),
            domain: Some("CORP".into()),
            ..Default::default()
        };
        assert!(profile.validate().is_ok());
    }

    #[test]
    fn validate_accepts_non_standard_port() {
        let profile = RdpProfile {
            id: "id".into(),
            host: "10.0.0.1".into(),
            port: 3390,
            username: "user".into(),
            ..Default::default()
        };
        assert!(profile.validate().is_ok());
    }

    // =========================================================
    // VALIDATION — invalid cases
    // =========================================================

    #[test]
    fn validate_rejects_empty_id() {
        let mut p = minimal_valid_profile();
        p.id = "".into();
        assert!(p.validate().is_err());
    }

    #[test]
    fn validate_rejects_whitespace_only_id() {
        let mut p = minimal_valid_profile();
        p.id = "   ".into();
        assert!(p.validate().is_err());
    }

    #[test]
    fn validate_rejects_empty_host() {
        let mut p = minimal_valid_profile();
        p.host = "".into();
        assert!(p.validate().is_err());
    }

    #[test]
    fn validate_rejects_whitespace_only_host() {
        let mut p = minimal_valid_profile();
        p.host = "  ".into();
        assert!(p.validate().is_err());
    }

    #[test]
    fn validate_rejects_port_zero() {
        let mut p = minimal_valid_profile();
        p.port = 0;
        assert!(p.validate().is_err());
    }

    #[test]
    fn validate_rejects_empty_username() {
        let mut p = minimal_valid_profile();
        p.username = "".into();
        assert!(p.validate().is_err());
    }

    #[test]
    fn validate_rejects_whitespace_only_username() {
        let mut p = minimal_valid_profile();
        p.username = "   ".into();
        assert!(p.validate().is_err());
    }

    // =========================================================
    // SOCKET ADDRESS
    // =========================================================

    #[test]
    fn socket_addr_formats_host_and_port() {
        let p = RdpProfile {
            host: "192.168.0.5".into(),
            port: 3389,
            ..Default::default()
        };
        assert_eq!(p.socket_addr(), "192.168.0.5:3389");
    }

    #[test]
    fn socket_addr_uses_non_standard_port() {
        let p = RdpProfile {
            host: "rdp.example.com".into(),
            port: 3390,
            ..Default::default()
        };
        assert_eq!(p.socket_addr(), "rdp.example.com:3390");
    }

    // =========================================================
    // IS CYBERARK PSM
    // =========================================================

    #[test]
    fn is_cyberark_psm_returns_true_when_alternate_shell_contains_psm() {
        let p = RdpProfile {
            alternate_shell: Some("PSM@vault-01".into()),
            ..Default::default()
        };
        assert!(p.is_cyberark_psm());
    }

    #[test]
    fn is_cyberark_psm_is_case_insensitive() {
        let p = RdpProfile {
            alternate_shell: Some("pSm@vault".into()),
            ..Default::default()
        };
        assert!(p.is_cyberark_psm());
    }

    #[test]
    fn is_cyberark_psm_returns_false_when_no_alternate_shell() {
        let p = RdpProfile {
            alternate_shell: None,
            ..Default::default()
        };
        assert!(!p.is_cyberark_psm());
    }

    #[test]
    fn is_cyberark_psm_returns_false_for_unrelated_shell() {
        let p = RdpProfile {
            alternate_shell: Some("cmd.exe".into()),
            ..Default::default()
        };
        assert!(!p.is_cyberark_psm());
    }

    // =========================================================
    // CONNECTION KEY — deduplication
    // =========================================================

    #[test]
    fn connection_key_same_for_different_profile_ids() {
        let make = |id: &str| RdpProfile {
            id: id.into(),
            host: "10.0.0.1".into(),
            port: 3389,
            username: "admin".into(),
            domain: None,
            ..Default::default()
        };
        assert_eq!(make("uuid-1").connection_key(), make("uuid-2").connection_key());
    }

    #[test]
    fn connection_key_differs_for_different_hosts() {
        let p1 = RdpProfile {
            host: "10.0.0.1".into(),
            port: 3389,
            username: "admin".into(),
            ..Default::default()
        };
        let p2 = RdpProfile {
            host: "10.0.0.2".into(),
            port: 3389,
            username: "admin".into(),
            ..Default::default()
        };
        assert_ne!(p1.connection_key(), p2.connection_key());
    }

    #[test]
    fn connection_key_differs_for_different_ports() {
        let p1 = RdpProfile {
            host: "10.0.0.1".into(),
            port: 3389,
            username: "admin".into(),
            ..Default::default()
        };
        let p2 = RdpProfile {
            host: "10.0.0.1".into(),
            port: 3390,
            username: "admin".into(),
            ..Default::default()
        };
        assert_ne!(p1.connection_key(), p2.connection_key());
    }

    #[test]
    fn connection_key_differs_for_different_usernames() {
        let p1 = RdpProfile {
            host: "10.0.0.1".into(),
            port: 3389,
            username: "admin".into(),
            ..Default::default()
        };
        let p2 = RdpProfile {
            host: "10.0.0.1".into(),
            port: 3389,
            username: "user".into(),
            ..Default::default()
        };
        assert_ne!(p1.connection_key(), p2.connection_key());
    }

    // =========================================================
    // PARSE RDP FILE — standard cases
    // =========================================================

    #[test]
    fn parse_standard_rdp_uses_default_port_when_not_specified() {
        let content = "full address:s:myserver.example.com\nusername:s:john\n";
        let profile = parse_rdp_file(content, "id-1", None).unwrap();
        assert_eq!(profile.host, "myserver.example.com");
        assert_eq!(profile.port, 3389);
        assert_eq!(profile.username, "john");
    }

    #[test]
    fn parse_rdp_extracts_port_from_full_address_field() {
        let content = "full address:s:myserver.example.com:3390\nusername:s:alice\n";
        let profile = parse_rdp_file(content, "id-2", None).unwrap();
        assert_eq!(profile.host, "myserver.example.com");
        assert_eq!(profile.port, 3390);
    }

    #[test]
    fn parse_rdp_uses_server_port_field_over_full_address_port() {
        let content =
            "full address:s:myserver.example.com:9999\nserver port:i:3391\nusername:s:bob\n";
        let profile = parse_rdp_file(content, "id-3", None).unwrap();
        assert_eq!(profile.port, 3391);
    }

    #[test]
    fn parse_rdp_splits_domain_backslash_username() {
        let content = "full address:s:10.0.0.1\nusername:s:CORP\\jdoe\n";
        let profile = parse_rdp_file(content, "id-4", None).unwrap();
        assert_eq!(profile.username, "jdoe");
        assert_eq!(profile.domain.as_deref(), Some("CORP"));
    }

    #[test]
    fn parse_rdp_no_domain_when_no_backslash() {
        let content = "full address:s:10.0.0.1\nusername:s:jdoe\n";
        let profile = parse_rdp_file(content, "id-5", None).unwrap();
        assert_eq!(profile.username, "jdoe");
        assert!(profile.domain.is_none());
    }

    #[test]
    fn parse_rdp_fullscreen_when_screen_mode_id_is_2() {
        let content = "full address:s:10.0.0.1\nusername:s:user\nscreen mode id:i:2\n";
        let profile = parse_rdp_file(content, "id-6", None).unwrap();
        assert!(profile.full_screen);
    }

    #[test]
    fn parse_rdp_not_fullscreen_when_screen_mode_id_is_1() {
        let content = "full address:s:10.0.0.1\nusername:s:user\nscreen mode id:i:1\n";
        let profile = parse_rdp_file(content, "id-7", None).unwrap();
        assert!(!profile.full_screen);
    }

    #[test]
    fn parse_rdp_custom_desktop_resolution() {
        let content = "full address:s:10.0.0.1\nusername:s:user\ndesktopwidth:i:1920\ndesktopheight:i:1080\n";
        let profile = parse_rdp_file(content, "id-8", None).unwrap();
        assert_eq!(profile.desktop_width, 1920);
        assert_eq!(profile.desktop_height, 1080);
    }

    #[test]
    fn parse_rdp_defaults_to_1280x800_when_resolution_missing() {
        let content = "full address:s:10.0.0.1\nusername:s:user\n";
        let profile = parse_rdp_file(content, "id-9", None).unwrap();
        assert_eq!(profile.desktop_width, 1280);
        assert_eq!(profile.desktop_height, 800);
    }

    #[test]
    fn parse_rdp_enable_cred_ssp_defaults_to_true() {
        let content = "full address:s:10.0.0.1\nusername:s:user\n";
        let profile = parse_rdp_file(content, "id-10", None).unwrap();
        assert!(profile.enable_cred_ssp);
    }

    #[test]
    fn parse_rdp_cred_ssp_disabled_when_zero() {
        let content = "full address:s:10.0.0.1\nusername:s:user\nenablecredsspsupport:i:0\n";
        let profile = parse_rdp_file(content, "id-11", None).unwrap();
        assert!(!profile.enable_cred_ssp);
    }

    #[test]
    fn parse_rdp_preserves_source_content() {
        let content = "full address:s:10.0.0.1\nusername:s:user\n";
        let profile = parse_rdp_file(content, "id-12", None).unwrap();
        assert_eq!(profile.source_rdp_content.as_deref(), Some(content));
    }

    #[test]
    fn parse_rdp_uses_provided_profile_name() {
        let content = "full address:s:10.0.0.1\nusername:s:user\n";
        let profile = parse_rdp_file(content, "id-13", Some("My Custom Name")).unwrap();
        assert_eq!(profile.name, "My Custom Name");
    }

    #[test]
    fn parse_rdp_generates_rdp_name_when_no_name_and_no_alternate_shell() {
        let content = "full address:s:rdpserver.local\nusername:s:user\n";
        let profile = parse_rdp_file(content, "id-14", None).unwrap();
        assert_eq!(profile.name, "RDP – rdpserver.local");
    }

    #[test]
    fn parse_rdp_generates_cyberark_name_when_alternate_shell_present() {
        let content = "full address:s:vault.corp.com\nusername:s:user\nalternate shell:s:PSM@target\n";
        let profile = parse_rdp_file(content, "id-15", None).unwrap();
        assert_eq!(profile.name, "CyberArk – vault.corp.com");
    }

    #[test]
    fn parse_rdp_assigns_given_profile_id() {
        let content = "full address:s:10.0.0.1\nusername:s:user\n";
        let profile = parse_rdp_file(content, "my-custom-id", None).unwrap();
        assert_eq!(profile.id, "my-custom-id");
    }

    #[test]
    fn parse_rdp_keys_are_case_insensitive() {
        let content = "FULL ADDRESS:s:10.0.0.1\nUSERNAME:s:admin\nDESKTOPWIDTH:i:1920\n";
        let profile = parse_rdp_file(content, "id-16", None).unwrap();
        assert_eq!(profile.host, "10.0.0.1");
        assert_eq!(profile.username, "admin");
        assert_eq!(profile.desktop_width, 1920);
    }

    #[test]
    fn parse_rdp_handles_malformed_port_gracefully() {
        let content = "full address:s:10.0.0.1\nusername:s:user\nserver port:i:not_a_number\n";
        let profile = parse_rdp_file(content, "id-17", None).unwrap();
        // Should fall back to default port 3389
        assert_eq!(profile.port, 3389);
    }

    #[test]
    fn parse_rdp_handles_empty_content_gracefully() {
        let profile = parse_rdp_file("", "id-18", None).unwrap();
        assert_eq!(profile.host, "");
        assert_eq!(profile.port, 3389);
    }

    #[test]
    fn parse_rdp_trims_whitespace_from_values() {
        let content = "full address:s:  10.0.0.1  \nusername:s:  admin  \n";
        let profile = parse_rdp_file(content, "id-19", None).unwrap();
        assert_eq!(profile.host, "10.0.0.1");
        assert_eq!(profile.username, "admin");
    }

    // =========================================================
    // PARSE RDP FILE — CyberArk PSM (full scenario)
    // =========================================================

    #[test]
    fn parse_cyberark_full_scenario() {
        let content = r#"full address:s:172.20.35.10
server port:i:3389
username:s:localhost\PSM@abc123
alternate shell:s:PSM@abc123
desktopwidth:i:1920
desktopheight:i:1080
EnableCredSspSupport:i:1"#;

        let profile = parse_rdp_file(content, "psm-id", None).unwrap();

        assert_eq!(profile.id, "psm-id");
        assert_eq!(profile.host, "172.20.35.10");
        assert_eq!(profile.port, 3389);
        assert_eq!(profile.username, "PSM@abc123");
        assert_eq!(profile.domain.as_deref(), Some("localhost"));
        assert!(profile.is_cyberark_psm());
        assert_eq!(profile.alternate_shell.as_deref(), Some("PSM@abc123"));
        assert_eq!(profile.desktop_width, 1920);
        assert_eq!(profile.desktop_height, 1080);
        assert!(profile.enable_cred_ssp);
        assert!(!profile.full_screen); // screen mode id not set → default false
    }

    // =========================================================
    // DEFAULT VALUES
    // =========================================================

    #[test]
    fn default_profile_has_port_3389() {
        assert_eq!(RdpProfile::default().port, 3389);
    }

    #[test]
    fn default_profile_has_1280x800_resolution() {
        let p = RdpProfile::default();
        assert_eq!(p.desktop_width, 1280);
        assert_eq!(p.desktop_height, 800);
    }

    #[test]
    fn default_profile_has_cred_ssp_enabled() {
        assert!(RdpProfile::default().enable_cred_ssp);
    }

    #[test]
    fn default_profile_is_not_fullscreen() {
        assert!(!RdpProfile::default().full_screen);
    }
}
