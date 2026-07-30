/// Flutter Rust Bridge API for RDP functionality.
///
/// This is the FRB entry point for `portix_rdp` — a separate cdylib from
/// `portix_serv`. Flutter loads both libraries independently:
///   - libportix_serv.so  → SSH features
///   - libportix_rdp.so   → RDP features
///
/// Keeping RDP in its own crate avoids the curve25519-dalek version conflict
/// between russh (=5.0.0-rc.0) and IronRDP/picky (=5.0.0-rc.1).
/// These two pre-release versions cannot be unified in a single Cargo
/// dependency tree, so each crate ships as its own cdylib.
use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;

use crate::application::session_manager::RdpSessionManager;
use crate::domain::profile::RdpProfile;
use crate::domain::session::RdpSessionInfo;
use crate::frb_generated::StreamSink;

static RDP_MANAGER: Lazy<RdpSessionManager> = Lazy::new(RdpSessionManager::new);

#[frb(init)]
pub fn init_rdp_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

// ── RDP Connection Management ──────────────────────────────────────────────

/// Parse a .rdp file content string and return session info (not connected yet).
pub async fn rdp_parse_file(
    rdp_content: String,
    profile_name: Option<String>,
) -> anyhow::Result<RdpSessionInfo> {
    Ok(RDP_MANAGER
        .parse_rdp_file_content(rdp_content, profile_name)
        .await?)
}

/// Connect to an RDP server using the provided profile.
pub async fn rdp_connect(profile: RdpProfile) -> anyhow::Result<RdpSessionInfo> {
    Ok(RDP_MANAGER.connect(profile).await?)
}

/// Disconnect an active RDP session.
pub async fn rdp_disconnect(session_id: String) -> anyhow::Result<()> {
    Ok(RDP_MANAGER.disconnect(session_id).await?)
}

// ── Input Forwarding ───────────────────────────────────────────────────────

/// Send mouse move event to an active RDP session.
pub async fn rdp_send_mouse_move(session_id: String, x: u16, y: u16) -> anyhow::Result<()> {
    Ok(RDP_MANAGER.send_mouse_move(session_id, x, y).await?)
}

/// Send mouse button event to an active RDP session.
/// button: 1=left, 2=right, 3=middle
pub async fn rdp_send_mouse_button(
    session_id: String,
    x: u16,
    y: u16,
    button: u8,
    down: bool,
) -> anyhow::Result<()> {
    Ok(RDP_MANAGER
        .send_mouse_button(session_id, x, y, button, down)
        .await?)
}

/// Send keyboard input to an active RDP session.
pub async fn rdp_send_keyboard_input(
    session_id: String,
    scancode: u16,
    down: bool,
) -> anyhow::Result<()> {
    Ok(RDP_MANAGER
        .send_keyboard_input(session_id, scancode, down)
        .await?)
}

// ── Event Streams ──────────────────────────────────────────────────────────

/// Stream of bitmap frame updates from all RDP sessions (JSON-serialised RdpFrameEvent).
pub async fn rdp_frame_stream(sink: StreamSink<String>) -> anyhow::Result<()> {
    let mut rx = RDP_MANAGER.frame_stream();
    tokio::spawn(async move {
        forward_json_stream(&mut rx, sink).await;
    });
    Ok(())
}

/// Stream of connection status updates from all RDP sessions.
pub async fn rdp_status_stream(sink: StreamSink<String>) -> anyhow::Result<()> {
    let mut rx = RDP_MANAGER.status_stream();
    tokio::spawn(async move {
        forward_json_stream(&mut rx, sink).await;
    });
    Ok(())
}

/// Stream of error events from all RDP sessions.
pub async fn rdp_error_stream(sink: StreamSink<String>) -> anyhow::Result<()> {
    let mut rx = RDP_MANAGER.error_stream();
    tokio::spawn(async move {
        forward_json_stream(&mut rx, sink).await;
    });
    Ok(())
}

// ── Internal helper ────────────────────────────────────────────────────────

async fn forward_json_stream<T>(
    rx: &mut tokio::sync::broadcast::Receiver<T>,
    sink: StreamSink<String>,
) where
    T: Clone + serde::Serialize,
{
    loop {
        match rx.recv().await {
            Ok(event) => {
                let Ok(json) = serde_json::to_string(&event) else {
                    continue;
                };
                if sink.add(json).is_err() {
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
        }
    }
}
