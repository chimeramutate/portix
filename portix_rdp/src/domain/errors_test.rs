/// Unit tests for RdpError — code classification, visibility,
/// transience, and Clone behaviour.
#[cfg(test)]
mod tests {
    use crate::domain::errors::RdpError;

    // =========================================================
    // ERROR CODES
    // =========================================================

    #[test]
    fn invalid_profile_has_correct_code() {
        assert_eq!(
            RdpError::InvalidProfile("bad".into()).code(),
            "INVALID_PROFILE"
        );
    }

    #[test]
    fn session_not_found_has_correct_code() {
        assert_eq!(
            RdpError::SessionNotFound("s1".into()).code(),
            "SESSION_NOT_FOUND"
        );
    }

    #[test]
    fn session_already_exists_has_correct_code() {
        assert_eq!(
            RdpError::SessionAlreadyExists("s1".into()).code(),
            "SESSION_ALREADY_EXISTS"
        );
    }

    #[test]
    fn cancelled_has_correct_code() {
        assert_eq!(RdpError::Cancelled.code(), "CANCELLED");
    }

    #[test]
    fn connection_timeout_has_correct_code() {
        assert_eq!(RdpError::ConnectionTimeout.code(), "CONNECTION_TIMEOUT");
    }

    #[test]
    fn auth_failed_has_correct_code() {
        assert_eq!(RdpError::AuthenticationFailed.code(), "AUTH_FAILED");
    }

    #[test]
    fn negotiation_failed_has_correct_code() {
        assert_eq!(
            RdpError::NegotiationFailed("tls".into()).code(),
            "NEGOTIATION_FAILED"
        );
    }

    #[test]
    fn protocol_error_has_correct_code() {
        assert_eq!(RdpError::Protocol("pdu".into()).code(), "PROTOCOL_ERROR");
    }

    #[test]
    fn disconnected_has_correct_code() {
        assert_eq!(RdpError::Disconnected.code(), "DISCONNECTED");
    }

    #[test]
    fn bridge_error_has_correct_code() {
        assert_eq!(RdpError::Bridge("ffmpeg".into()).code(), "BRIDGE_ERROR");
    }

    #[test]
    fn io_error_has_correct_code() {
        let err = RdpError::Io(std::io::Error::new(std::io::ErrorKind::Other, "disk full"));
        assert_eq!(err.code(), "IO_ERROR");
    }

    // =========================================================
    // USER VISIBILITY
    // =========================================================

    #[test]
    fn invalid_profile_is_user_visible() {
        assert!(RdpError::InvalidProfile("x".into()).is_user_visible());
    }

    #[test]
    fn connection_timeout_is_user_visible() {
        assert!(RdpError::ConnectionTimeout.is_user_visible());
    }

    #[test]
    fn authentication_failed_is_user_visible() {
        assert!(RdpError::AuthenticationFailed.is_user_visible());
    }

    #[test]
    fn negotiation_failed_is_user_visible() {
        assert!(RdpError::NegotiationFailed("x".into()).is_user_visible());
    }

    #[test]
    fn protocol_error_is_user_visible() {
        assert!(RdpError::Protocol("x".into()).is_user_visible());
    }

    #[test]
    fn cancelled_is_not_user_visible() {
        assert!(!RdpError::Cancelled.is_user_visible());
    }

    #[test]
    fn disconnected_is_not_user_visible() {
        assert!(!RdpError::Disconnected.is_user_visible());
    }

    #[test]
    fn session_not_found_is_not_user_visible() {
        assert!(!RdpError::SessionNotFound("s".into()).is_user_visible());
    }

    // =========================================================
    // TRANSIENCE
    // =========================================================

    #[test]
    fn session_not_found_is_transient() {
        assert!(RdpError::SessionNotFound("s".into()).is_transient());
    }

    #[test]
    fn cancelled_is_transient() {
        assert!(RdpError::Cancelled.is_transient());
    }

    #[test]
    fn disconnected_is_transient() {
        assert!(RdpError::Disconnected.is_transient());
    }

    #[test]
    fn connection_timeout_is_not_transient() {
        assert!(!RdpError::ConnectionTimeout.is_transient());
    }

    #[test]
    fn invalid_profile_is_not_transient() {
        assert!(!RdpError::InvalidProfile("x".into()).is_transient());
    }

    // =========================================================
    // CLONE
    // =========================================================

    #[test]
    fn clone_preserves_message_for_string_variants() {
        let original = RdpError::InvalidProfile("bad host".into());
        let cloned = original.clone();
        assert_eq!(cloned.to_string(), original.to_string());
    }

    #[test]
    fn clone_works_for_io_error() {
        let original = RdpError::Io(std::io::Error::new(std::io::ErrorKind::TimedOut, "timeout"));
        let cloned = original.clone();
        // The clone maps to a new Io error — just verify it doesn't panic and code matches.
        assert_eq!(original.code(), cloned.code());
    }

    #[test]
    fn clone_works_for_unit_variants() {
        let variants = [
            RdpError::Cancelled,
            RdpError::ConnectionTimeout,
            RdpError::AuthenticationFailed,
            RdpError::Disconnected,
        ];
        for v in &variants {
            let cloned = v.clone();
            assert_eq!(v.code(), cloned.code());
        }
    }

    // =========================================================
    // DISPLAY
    // =========================================================

    #[test]
    fn display_includes_message_for_invalid_profile() {
        let err = RdpError::InvalidProfile("host is required".into());
        assert!(err.to_string().contains("host is required"));
    }

    #[test]
    fn display_includes_session_id_for_session_not_found() {
        let err = RdpError::SessionNotFound("sess-xyz".into());
        assert!(err.to_string().contains("sess-xyz"));
    }

    #[test]
    fn display_mentions_timeout_for_connection_timeout() {
        assert!(RdpError::ConnectionTimeout.to_string().contains("timed out"));
    }
}
