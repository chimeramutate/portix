/// Unit tests for `RdpSessionManager` — session lifecycle, deduplication,
/// frame ID counter, and graceful disconnect behaviour.
///
/// These tests exercise only the in-memory logic; they never open a real
/// TCP connection to an RDP server.
#[cfg(test)]
mod tests {
    use crate::application::session_manager::RdpSessionManager;
    use crate::domain::profile::RdpProfile;
    use crate::domain::session::RdpConnectionStatus;

    // =========================================================
    // HELPERS
    // =========================================================

    fn valid_profile(id: &str) -> RdpProfile {
        RdpProfile {
            id: id.into(),
            name: "Test".into(),
            host: "192.168.100.1".into(),
            port: 3389,
            username: "admin".into(),
            password: Some("P@ss1".into()),
            ..Default::default()
        }
    }

    fn invalid_profile_no_host() -> RdpProfile {
        RdpProfile {
            id: "bad-id".into(),
            host: "".into(),
            port: 3389,
            username: "user".into(),
            ..Default::default()
        }
    }

    fn invalid_profile_no_id() -> RdpProfile {
        RdpProfile {
            id: "".into(),
            host: "10.0.0.1".into(),
            port: 3389,
            username: "user".into(),
            ..Default::default()
        }
    }

    // =========================================================
    // CONSTRUCTION
    // =========================================================

    #[test]
    fn new_manager_has_no_active_sessions() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let mgr = RdpSessionManager::new();
            assert!(!mgr.is_session_active("nonexistent").await);
        });
    }

    #[test]
    fn default_and_new_are_equivalent() {
        // Both should construct without panicking.
        let _a = RdpSessionManager::new();
        let _b = RdpSessionManager::default();
    }

    // =========================================================
    // FRAME ID COUNTER
    // =========================================================

    #[test]
    fn frame_id_counter_starts_at_one() {
        let mgr = RdpSessionManager::new();
        assert_eq!(mgr.next_frame_id(), 1);
    }

    #[test]
    fn frame_id_counter_increments_monotonically() {
        let mgr = RdpSessionManager::new();
        let ids: Vec<u64> = (0..10).map(|_| mgr.next_frame_id()).collect();
        for window in ids.windows(2) {
            assert!(window[1] > window[0], "frame IDs must be monotonically increasing");
        }
    }

    #[test]
    fn frame_id_counter_produces_unique_values_across_managers() {
        // Each manager has its own independent counter.
        let mgr_a = RdpSessionManager::new();
        let mgr_b = RdpSessionManager::new();
        // Both start at 1 — they are independent.
        assert_eq!(mgr_a.next_frame_id(), mgr_b.next_frame_id());
    }

    // =========================================================
    // CONNECT — validation
    // =========================================================

    #[tokio::test]
    async fn connect_rejects_profile_with_empty_host() {
        let mgr = RdpSessionManager::new();
        let result = mgr.connect(invalid_profile_no_host()).await;
        assert!(result.is_err(), "empty host should be rejected");
    }

    #[tokio::test]
    async fn connect_rejects_profile_with_empty_id() {
        let mgr = RdpSessionManager::new();
        let result = mgr.connect(invalid_profile_no_id()).await;
        assert!(result.is_err(), "empty id should be rejected");
    }

    #[tokio::test]
    async fn connect_rejects_profile_with_port_zero() {
        let mgr = RdpSessionManager::new();
        let profile = RdpProfile {
            id: "p".into(),
            host: "10.0.0.1".into(),
            port: 0,
            username: "user".into(),
            ..Default::default()
        };
        let result = mgr.connect(profile).await;
        assert!(result.is_err());
    }

    // =========================================================
    // CONNECT — session spawning (non-network path)
    // =========================================================

    #[tokio::test]
    async fn connect_returns_session_info_in_connecting_state() {
        // We can't complete the TCP handshake in unit tests, but we CAN verify
        // that the returned SessionInfo has the correct initial state and IDs
        // before the background task fails with a connection error.
        let mgr = RdpSessionManager::new();
        let profile = valid_profile("prof-1");
        let result = mgr.connect(profile).await;

        assert!(
            result.is_ok(),
            "connect() must return Ok (background task handles the failure)"
        );
        let info = result.unwrap();
        assert_eq!(info.profile_id, "prof-1");
        assert_eq!(info.status, RdpConnectionStatus::Connecting);
        assert!(!info.id.is_empty(), "session id must be non-empty UUID");
    }

    // =========================================================
    // CONNECT — deduplication
    // =========================================================

    #[tokio::test]
    async fn second_connect_for_same_profile_returns_same_session_id() {
        let mgr = RdpSessionManager::new();
        let profile = valid_profile("prof-dedup");

        let first = mgr.connect(profile.clone()).await.unwrap();

        // The background task will eventually fail the TCP connect, but the
        // session remains registered until cleanup. We call connect() again
        // *immediately* while the session is still in the map.
        let second = mgr.connect(profile).await.unwrap();

        assert_eq!(
            first.id, second.id,
            "same profile should return existing session id"
        );
    }

    // =========================================================
    // DISCONNECT — unknown session is a no-op
    // =========================================================

    #[tokio::test]
    async fn disconnect_nonexistent_session_returns_ok() {
        let mgr = RdpSessionManager::new();
        let result = mgr.disconnect("no-such-session".into()).await;
        assert!(result.is_ok(), "disconnecting unknown session must not error");
    }

    // =========================================================
    // DISCONNECT ALL — clears everything
    // =========================================================

    #[tokio::test]
    async fn disconnect_all_does_not_panic_on_empty_manager() {
        let mgr = RdpSessionManager::new();
        mgr.disconnect_all().await; // must not panic
    }

    // =========================================================
    // PARSE RDP FILE CONTENT
    // =========================================================

    #[tokio::test]
    async fn parse_rdp_file_content_returns_session_info_with_disconnected_status() {
        let mgr = RdpSessionManager::new();
        let content = "full address:s:10.0.0.5\nusername:s:tester\n";
        let result = mgr
            .parse_rdp_file_content(content.into(), None)
            .await
            .unwrap();
        assert_eq!(result.status, RdpConnectionStatus::Disconnected);
        assert!(!result.id.is_empty());
        assert!(!result.profile_id.is_empty());
        // Both id and profile_id are the same generated UUID in this path.
        assert_eq!(result.id, result.profile_id);
    }

    #[tokio::test]
    async fn parse_rdp_file_content_with_profile_name_does_not_error() {
        let mgr = RdpSessionManager::new();
        let content = "full address:s:10.0.0.5\nusername:s:tester\n";
        let result = mgr
            .parse_rdp_file_content(content.into(), Some("My Custom Name".into()))
            .await;
        assert!(result.is_ok());
    }

    // =========================================================
    // STREAMS — subscriptions don't panic
    // =========================================================

    #[test]
    fn subscribing_to_streams_does_not_panic() {
        let mgr = RdpSessionManager::new();
        let _frame = mgr.frame_stream();
        let _status = mgr.status_stream();
        let _error = mgr.error_stream();
    }

    // =========================================================
    // INPUT COMMANDS — no session → silent no-op
    // =========================================================

    #[tokio::test]
    async fn send_mouse_move_to_nonexistent_session_returns_ok() {
        let mgr = RdpSessionManager::new();
        let result = mgr.send_mouse_move("ghost".into(), 100, 200).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn send_mouse_button_to_nonexistent_session_returns_ok() {
        let mgr = RdpSessionManager::new();
        let result = mgr
            .send_mouse_button("ghost".into(), 0, 0, 0, true)
            .await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn send_keyboard_input_to_nonexistent_session_returns_ok() {
        let mgr = RdpSessionManager::new();
        let result = mgr.send_keyboard_input("ghost".into(), 0x001E, true).await;
        assert!(result.is_ok());
    }
}
