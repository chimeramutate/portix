/// Unit tests for RDP event structs: serialization round-trip,
/// default field values, and correct data layout.
#[cfg(test)]
mod tests {
    use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
    use crate::domain::session::RdpConnectionStatus;

    // =========================================================
    // RdpStatusEvent
    // =========================================================

    #[test]
    fn status_event_serializes_and_deserializes() {
        let event = RdpStatusEvent {
            session_id: "sess-1".into(),
            status: RdpConnectionStatus::Connected,
            message: Some("connected".into()),
        };
        let json = serde_json::to_string(&event).unwrap();
        let decoded: RdpStatusEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.session_id, "sess-1");
        assert_eq!(decoded.status, RdpConnectionStatus::Connected);
        assert_eq!(decoded.message.as_deref(), Some("connected"));
    }

    #[test]
    fn status_event_none_message_serializes_as_null() {
        let event = RdpStatusEvent {
            session_id: "s".into(),
            status: RdpConnectionStatus::Disconnected,
            message: None,
        };
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("\"message\":null"));
    }

    #[test]
    fn status_event_clone_is_independent() {
        let event = RdpStatusEvent {
            session_id: "original".into(),
            status: RdpConnectionStatus::Error,
            message: None,
        };
        let mut cloned = event.clone();
        cloned.session_id = "cloned".into();
        assert_eq!(event.session_id, "original");
    }

    // =========================================================
    // RdpErrorEvent
    // =========================================================

    #[test]
    fn error_event_deserializes_default_code_when_missing() {
        let json = r#"{"session_id":"s1","message":"boom"}"#;
        let event: RdpErrorEvent = serde_json::from_str(json).unwrap();
        assert_eq!(event.code, "UNKNOWN");
    }

    #[test]
    fn error_event_preserves_explicit_code() {
        let json = r#"{"session_id":null,"message":"timeout","code":"CONNECTION_TIMEOUT"}"#;
        let event: RdpErrorEvent = serde_json::from_str(json).unwrap();
        assert_eq!(event.code, "CONNECTION_TIMEOUT");
        assert!(event.session_id.is_none());
    }

    #[test]
    fn error_event_serializes_and_deserializes_roundtrip() {
        let event = RdpErrorEvent {
            session_id: Some("sess-err".into()),
            message: "protocol error".into(),
            code: "PROTOCOL_ERROR".into(),
        };
        let json = serde_json::to_string(&event).unwrap();
        let decoded: RdpErrorEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.session_id.as_deref(), Some("sess-err"));
        assert_eq!(decoded.message, "protocol error");
        assert_eq!(decoded.code, "PROTOCOL_ERROR");
    }

    // =========================================================
    // RdpFrameEvent
    // =========================================================

    #[test]
    fn frame_event_single_chunk_fields() {
        let data = vec![0u8; 4 * 10 * 8]; // 10x8 RGBA pixels
        let event = RdpFrameEvent {
            session_id: "sess-frame".into(),
            data: data.clone(),
            width: 10,
            height: 8,
            x: 0,
            y: 0,
            frame_id: 42,
        };
        assert_eq!(event.data.len(), 320);
        assert_eq!(event.width, 10);
        assert_eq!(event.height, 8);
        assert_eq!(event.frame_id, 42);
    }

    #[test]
    fn frame_event_serializes_and_deserializes() {
        let event = RdpFrameEvent {
            session_id: "s".into(),
            data: vec![255u8; 4],
            width: 1,
            height: 1,
            x: 0,
            y: 0,
            frame_id: 1,
        };
        let json = serde_json::to_string(&event).unwrap();
        let decoded: RdpFrameEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.data, vec![255u8; 4]);
        assert_eq!(decoded.frame_id, 1);
    }

    #[test]
    fn frame_event_multi_chunk_metadata() {
        let event = RdpFrameEvent {
            session_id: "s".into(),
            data: vec![0u8; 100],
            width: 1920,
            height: 1080,
            x: 100,
            y: 200,
            frame_id: 99,

        };
        assert_eq!(event.x, 100);
        assert_eq!(event.y, 200);
    }

    #[test]
    fn frame_event_clone_data_is_independent() {
        let original = RdpFrameEvent {
            session_id: "s".into(),
            data: vec![1u8, 2, 3, 4],
            width: 1,
            height: 1,
            x: 0,
            y: 0,
            frame_id: 0,

        };
        let mut cloned = original.clone();
        cloned.data[0] = 99;
        assert_eq!(original.data[0], 1);
    }
}
