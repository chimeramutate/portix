use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use std::sync::Mutex;
use tokio_util::sync::CancellationToken;

use crate::application::session_manager::RdpSessionManager;
use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use crate::domain::profile::RdpProfile;
use crate::domain::session::RdpSessionInfo;
use crate::frb_generated::StreamSink;

static RDP_MANAGER: Lazy<RdpSessionManager> = Lazy::new(RdpSessionManager::new);

// Token untuk membatalkan handler stream sebelumnya saat subscriber baru didaftarkan.
// Ini menangani kasus hot restart Flutter di mana .so tidak di-reload tapi Dart
// memanggil rdp_frame_stream() lagi → handler lama di-cancel sebelum handler baru mulai.
static FRAME_STREAM_CANCEL: Lazy<Mutex<Option<CancellationToken>>> =
    Lazy::new(|| Mutex::new(None));
static STATUS_STREAM_CANCEL: Lazy<Mutex<Option<CancellationToken>>> =
    Lazy::new(|| Mutex::new(None));
static ERROR_STREAM_CANCEL: Lazy<Mutex<Option<CancellationToken>>> =
    Lazy::new(|| Mutex::new(None));

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

pub async fn rdp_send_mouse_wheel(
    session_id: String,
    x: u16,
    y: u16,
    delta: i16,
    is_vertical: bool,
) -> anyhow::Result<()> {
    Ok(RDP_MANAGER
        .send_mouse_wheel(session_id, x, y, delta, is_vertical)
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

// ffib.rs / lib.rs
pub async fn rdp_frame_stream(sink: StreamSink<RdpFrameEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp] rdp_frame_stream subscription started");

    // Batalkan handler frame stream sebelumnya (hot restart handling)
    let new_cancel = CancellationToken::new();
    let old_cancel = {
        let mut guard = FRAME_STREAM_CANCEL.lock().unwrap();
        guard.replace(new_cancel.clone())
    };
    if let Some(old) = old_cancel {
        println!("[portix_rdp] rdp_frame_stream cancelling previous handler");
        old.cancel();
    }

    let mut rx = RDP_MANAGER.frame_stream();
    let error_tx = RDP_MANAGER.error_stream_sender();

    tokio::spawn(async move {
        let mut frame_count = 0u32;
        let mut last_frame_id = 0u64;
        let mut lagged_chunks = 0u32;
        
        loop {
            tokio::select! {
                _ = new_cancel.cancelled() => {
                    println!("[portix_rdp] rdp_frame_stream handler cancelled (new subscriber registered)");
                    break;
                }
                result = rx.recv() => {
                    match result {
                        Ok(event) => {
                            frame_count += 1;
                            
                            // ✅ Detect frame_id jump = missing chunks dari frame sebelumnya
                            if event.frame_id != last_frame_id && last_frame_id > 0 {
                                eprintln!(
                                    "[rdp_frame_stream CRITICAL] frame {} → {} (jumped!), lagged_chunks so far: {}",
                                    last_frame_id, event.frame_id, lagged_chunks
                                );
                                last_frame_id = event.frame_id;
                            }
                            
                            println!(
                                "[rdp_frame_stream] received frame #{} id={} ",
                                frame_count, event.frame_id
                            );
                            
                            if let Err(e) = sink.add(event) {
                                eprintln!(
                                    "[rdp_frame_stream CRITICAL] sink error on frame #{}: {} (lagged: {})",
                                    frame_count, e, lagged_chunks
                                );
                                let _ = error_tx.send(RdpErrorEvent {
                                    session_id: None,
                                    message: format!(
                                        "Frame stream sink closed after {} frames ({} lagged chunks): {}",
                                        frame_count, lagged_chunks, e
                                    ),
                                    code: "FRAME_SINK_ERROR".to_string(),
                                });
                                break;
                            }
                        }
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                            lagged_chunks += n as u32;
                            eprintln!(
                                "[rdp_frame_stream] WARNING: lagged {} chunks (total lagged: {})",
                                n, lagged_chunks
                            );
                            continue;
                        }
                        Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                            println!(
                                "[rdp_frame_stream] broadcast closed after {} frames ({} lagged chunks)",
                                frame_count, lagged_chunks
                            );
                            break;
                        }
                    }
                }
            }
        }
        println!("[rdp_frame_stream] handler terminated after {} frames", frame_count);
    });
    Ok(())
}

pub async fn rdp_status_stream(sink: StreamSink<RdpStatusEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp] rdp_status_stream subscription started");

    // Batalkan handler status stream sebelumnya (hot restart handling)
    let new_cancel = CancellationToken::new();
    let old_cancel = {
        let mut guard = STATUS_STREAM_CANCEL.lock().unwrap();
        guard.replace(new_cancel.clone())
    };
    if let Some(old) = old_cancel {
        println!("[portix_rdp] rdp_status_stream cancelling previous handler");
        old.cancel();
    }

    let mut rx = RDP_MANAGER.status_stream();
    let error_tx = RDP_MANAGER.error_stream_sender();

    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = new_cancel.cancelled() => {
                    println!("[portix_rdp] rdp_status_stream handler cancelled (new subscriber registered)");
                    break;
                }
                result = rx.recv() => {
                    match result {
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
            }
        }
        println!("[portix_rdp] status_stream handler terminated");
    });
    Ok(())
}

pub async fn rdp_error_stream(sink: StreamSink<RdpErrorEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp] rdp_error_stream subscription started");

    // Batalkan handler error stream sebelumnya (hot restart handling)
    let new_cancel = CancellationToken::new();
    let old_cancel = {
        let mut guard = ERROR_STREAM_CANCEL.lock().unwrap();
        guard.replace(new_cancel.clone())
    };
    if let Some(old) = old_cancel {
        println!("[portix_rdp] rdp_error_stream cancelling previous handler");
        old.cancel();
    }

    let mut rx = RDP_MANAGER.error_stream();

    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = new_cancel.cancelled() => {
                    println!("[portix_rdp] rdp_error_stream handler cancelled (new subscriber registered)");
                    break;
                }
                result = rx.recv() => {
                    match result {
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
            }
        }
        println!("[portix_rdp] error_stream handler terminated");
    });
    Ok(())
}

