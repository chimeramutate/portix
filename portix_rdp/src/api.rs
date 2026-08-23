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
static FRAME_STREAM_CANCEL: Lazy<Mutex<Option<CancellationToken>>> = Lazy::new(|| Mutex::new(None));
static STATUS_STREAM_CANCEL: Lazy<Mutex<Option<CancellationToken>>> =
    Lazy::new(|| Mutex::new(None));
static ERROR_STREAM_CANCEL: Lazy<Mutex<Option<CancellationToken>>> = Lazy::new(|| Mutex::new(None));

#[frb(init)]
pub fn init_rdp_app() {
    flutter_rust_bridge::setup_default_user_utils();
    crate::init_tracing();
    println!("[portix_rdp][DEBUG] init_rdp_app called, tracing initialized");
}

pub async fn rdp_parse_file(
    rdp_content: String,
    profile_name: Option<String>,
) -> anyhow::Result<RdpSessionInfo> {
    println!(
        "[portix_rdp][DEBUG] rdp_parse_file called: content_len={} profile_name={:?}",
        rdp_content.len(),
        profile_name
    );
    Ok(RDP_MANAGER
        .parse_rdp_file_content(rdp_content, profile_name)
        .await?)
}

pub async fn rdp_connect(profile: RdpProfile) -> anyhow::Result<RdpSessionInfo> {
    println!(
        "[portix_rdp] rdp_connect called: profile_id={}, host={}, port={}",
        profile.id, profile.host, profile.port,
    );
    let result = RDP_MANAGER.connect(profile).await;
    println!("[portix_rdp][DEBUG] rdp_connect result: {:?}", result);
    Ok(result?)
}

pub async fn rdp_disconnect(session_id: String) -> anyhow::Result<()> {
    println!(
        "[portix_rdp][DEBUG] rdp_disconnect called: session_id={}",
        session_id
    );
    Ok(RDP_MANAGER.disconnect(session_id).await?)
}

pub async fn rdp_send_mouse_move(session_id: String, x: u16, y: u16) -> anyhow::Result<()> {
    println!(
        "[portix_rdp][DEBUG] rdp_send_mouse_move: session_id={} x={} y={}",
        session_id, x, y
    );
    Ok(RDP_MANAGER.send_mouse_move(session_id, x, y).await?)
}

pub async fn rdp_send_mouse_button(
    session_id: String,
    x: u16,
    y: u16,
    button: u8,
    down: bool,
) -> anyhow::Result<()> {
    println!(
        "[portix_rdp][DEBUG] rdp_send_mouse_button: session_id={} x={} y={} button={} down={}",
        session_id, x, y, button, down
    );
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
    println!(
        "[portix_rdp][DEBUG] rdp_send_mouse_wheel: session_id={} x={} y={} delta={} is_vertical={}",
        session_id, x, y, delta, is_vertical
    );
    Ok(RDP_MANAGER
        .send_mouse_wheel(session_id, x, y, delta, is_vertical)
        .await?)
}

pub async fn rdp_send_keyboard_input(
    session_id: String,
    scancode: u16,
    down: bool,
) -> anyhow::Result<()> {
    println!(
        "[portix_rdp][DEBUG] rdp_send_keyboard_input: session_id={} scancode=0x{:04X} down={}",
        session_id, scancode, down
    );
    Ok(RDP_MANAGER
        .send_keyboard_input(session_id, scancode, down)
        .await?)
}

// ffib.rs / lib.rs
pub async fn rdp_frame_stream(sink: StreamSink<RdpFrameEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp][DEBUG] rdp_frame_stream subscribed");
    let mut rx = RDP_MANAGER.frame_stream();

    tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(event) => {
                    if sink.add(event).is_err() {
                        println!("[portix_rdp][DEBUG] rdp_frame_stream sink closed, exiting");
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    eprintln!("[portix_rdp] frame subscriber lagged {} events", n);
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    println!("[portix_rdp][DEBUG] rdp_frame_stream channel closed, exiting");
                    break;
                }
            }
        }
    });

    Ok(())
}

pub async fn rdp_status_stream(sink: StreamSink<RdpStatusEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp][DEBUG] rdp_status_stream subscribed");
    let mut rx = RDP_MANAGER.status_stream();

    tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(event) => {
                    if sink.add(event).is_err() {
                        println!("[portix_rdp][DEBUG] rdp_status_stream sink closed, exiting");
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    eprintln!("[portix_rdp] status subscriber lagged {} events", n);
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    println!("[portix_rdp][DEBUG] rdp_status_stream channel closed, exiting");
                    break;
                }
            }
        }
    });

    Ok(())
}

pub async fn rdp_error_stream(sink: StreamSink<RdpErrorEvent>) -> anyhow::Result<()> {
    println!("[portix_rdp][DEBUG] rdp_error_stream subscribed");
    let mut rx = RDP_MANAGER.error_stream();

    tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(event) => {
                    if sink.add(event).is_err() {
                        println!("[portix_rdp][DEBUG] rdp_error_stream sink closed, exiting");
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    eprintln!("[portix_rdp] error subscriber lagged {} events", n);
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    println!("[portix_rdp][DEBUG] rdp_error_stream channel closed, exiting");
                    break;
                }
            }
        }
    });

    Ok(())
}
