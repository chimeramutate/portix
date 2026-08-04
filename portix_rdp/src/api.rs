use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;

use crate::application::session_manager::RdpSessionManager;
use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use crate::domain::profile::RdpProfile;
use crate::domain::session::RdpSessionInfo;
use crate::frb_generated::StreamSink;

static RDP_MANAGER: Lazy<RdpSessionManager> = Lazy::new(RdpSessionManager::new);

#[frb(init)]
pub fn init_rdp_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub async fn rdp_parse_file(
    rdp_content: String,
    profile_name: Option<String>,
) -> anyhow::Result<RdpSessionInfo> {
    Ok(RDP_MANAGER
        .parse_rdp_file_content(rdp_content, profile_name)
        .await?)
}

pub async fn rdp_connect(profile: RdpProfile) -> anyhow::Result<RdpSessionInfo> {
    println!(
        "[portix_rdp] rdp_connect called: profile_id={}, host={}, port={}",
        profile.id, profile.host, profile.port,
    );
    Ok(RDP_MANAGER.connect(profile).await?)
}

pub async fn rdp_disconnect(session_id: String) -> anyhow::Result<()> {
    Ok(RDP_MANAGER.disconnect(session_id).await?)
}

pub async fn rdp_send_mouse_move(session_id: String, x: u16, y: u16) -> anyhow::Result<()> {
    Ok(RDP_MANAGER.send_mouse_move(session_id, x, y).await?)
}

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

pub async fn rdp_send_keyboard_input(
    session_id: String,
    scancode: u16,
    down: bool,
) -> anyhow::Result<()> {
    Ok(RDP_MANAGER
        .send_keyboard_input(session_id, scancode, down)
        .await?)
}

pub async fn rdp_frame_stream(sink: StreamSink<RdpFrameEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp] rdp_frame_stream subscription started");
    let mut rx = RDP_MANAGER.frame_stream();
    let error_tx = RDP_MANAGER.error_stream_sender();

    tokio::spawn(async move {
        let mut frame_count = 0u32;
        loop {
            match rx.recv().await {
                Ok(event) => {
                    frame_count += 1;
                    println!("[rdp_frame_stream] received frame #{} id={}", frame_count, event.frame_id);
                    
                    if let Err(e) = sink.add(event) {
                        eprintln!("[rdp_frame_stream CRITICAL] sink error on frame #{}: {}", frame_count, e);
                        let _ = error_tx.send(RdpErrorEvent {
                            session_id: None,
                            message: format!("Frame stream sink closed after {} frames: {}", frame_count, e),
                            code: "FRAME_SINK_ERROR".to_string(),
                        });
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    eprintln!("[rdp_frame_stream] WARNING: lagged {} frames (buffer too small?)", n);
                    continue;
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    println!("[rdp_frame_stream] broadcast closed");
                    break;
                }
            }
        }
        println!("[rdp_frame_stream] handler terminated after {} frames", frame_count);
    });
    Ok(())
}

pub async fn rdp_status_stream(sink: StreamSink<RdpStatusEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp] rdp_status_stream subscription started");
    let mut rx = RDP_MANAGER.status_stream();
    let error_tx = RDP_MANAGER.error_stream_sender();

    tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(event) => {
                    if let Err(e) = sink.add(event) {
                        eprintln!("[portix_rdp] status_stream sink error: {}", e);
                        let _ = error_tx.send(RdpErrorEvent {
                            session_id: None,
                            message: format!("Status stream sink closed: {}", e),
                            code: "STATUS_SINK_CLOSED".to_string(),
                        });
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    eprintln!("[portix_rdp] status_stream lagged {} events", n);
                    continue;
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    eprintln!("[portix_rdp] status_stream closed");
                    break;
                }
            }
        }
        println!("[portix_rdp] status_stream handler terminated");
    });
    Ok(())
}

pub async fn rdp_error_stream(sink: StreamSink<RdpErrorEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp] rdp_error_stream subscription started");
    let mut rx = RDP_MANAGER.error_stream();

    tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(event) => {
                    if let Err(e) = sink.add(event) {
                        eprintln!("[portix_rdp] error_stream sink error (critical): {}", e);
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    eprintln!("[portix_rdp] error_stream lagged {} events", n);
                    continue;
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    eprintln!("[portix_rdp] error_stream closed");
                    break;
                }
            }
        }
        println!("[portix_rdp] error_stream handler terminated");
    });
    Ok(())
}

