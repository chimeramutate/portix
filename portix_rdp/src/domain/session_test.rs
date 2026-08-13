/// Unit tests for RDP session domain types:
/// `RdpConnectionStatus` display/equality, `RdpSessionInfo::is_active`.
#[cfg(test)]
mod tests {
    use crate::domain::session::{RdpConnectionStatus, RdpSessionInfo};

    // =========================================================
    // RdpConnectionStatus — Display
    // =========================================================

    #[test]
    fn status_display_disconnected() {
        assert_eq!(RdpConnectionStatus::Disconnected.to_string(), "disconnected");
    }

    #[test]
    fn status_display_connecting() {
        assert_eq!(RdpConnectionStatus::Connecting.to_string(), "connecting");
    }

    #[test]
    fn status_display_connected() {
        assert_eq!(RdpConnectionStatus::Connected.to_string(), "connected");
    }

    #[test]
    fn status_display_error() {
        assert_eq!(RdpConnectionStatus::Error.to_string(), "error");
    }

    // =========================================================
    // RdpConnectionStatus — Equality
    // =========================================================

    #[test]
    fn status_equality_same_variants_are_equal() {
        assert_eq!(RdpConnectionStatus::Connected, RdpConnectionStatus::Connected);
    }

    #[test]
    fn status_equality_different_variants_are_not_equal() {
        assert_ne!(
            RdpConnectionStatus::Connected,
            RdpConnectionStatus::Disconnected
        );
    }

    // =========================================================
    // RdpSessionInfo::is_active
    // =========================================================

    #[test]
    fn is_active_returns_true_when_connected() {
        let info = RdpSessionInfo {
            id: "s1".into(),
            profile_id: "p1".into(),
            status: RdpConnectionStatus::Connected,
        };
        assert!(info.is_active());
    }

    #[test]
    fn is_active_returns_true_when_connecting() {
        let info = RdpSessionInfo {
            id: "s1".into(),
            profile_id: "p1".into(),
            status: RdpConnectionStatus::Connecting,
        };
        assert!(info.is_active());
    }

    #[test]
    fn is_active_returns_false_when_disconnected() {
        let info = RdpSessionInfo {
            id: "s1".into(),
            profile_id: "p1".into(),
            status: RdpConnectionStatus::Disconnected,
        };
        assert!(!info.is_active());
    }

    #[test]
    fn is_active_returns_false_when_error() {
        let info = RdpSessionInfo {
            id: "s1".into(),
            profile_id: "p1".into(),
            status: RdpConnectionStatus::Error,
        };
        assert!(!info.is_active());
    }

    // =========================================================
    // RdpSessionInfo — Clone & Debug
    // =========================================================

    #[test]
    fn session_info_clone_is_independent() {
        let original = RdpSessionInfo {
            id: "orig".into(),
            profile_id: "p".into(),
            status: RdpConnectionStatus::Connected,
        };
        let mut cloned = original.clone();
        cloned.id = "clone".into();
        assert_eq!(original.id, "orig");
    }

    #[test]
    fn session_info_debug_contains_id() {
        let info = RdpSessionInfo {
            id: "debug-id".into(),
            profile_id: "p".into(),
            status: RdpConnectionStatus::Error,
        };
        assert!(format!("{:?}", info).contains("debug-id"));
    }
}
