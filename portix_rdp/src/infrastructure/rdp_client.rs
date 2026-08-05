use ironrdp_connector::{ClientConnector, Config, Credentials, DesktopSize, ServerName};
use ironrdp_graphics::image_processing::PixelFormat;
use ironrdp_input::{Database, MouseButton, MousePosition, Operation, Scancode, WheelRotations};
use ironrdp_pdu::Encode;
use ironrdp_pdu::cursor::WriteCursor;
use ironrdp_pdu::geometry::InclusiveRectangle;
use ironrdp_pdu::input::fast_path::FastPathInput;
use ironrdp_session::image::DecodedImage;
use ironrdp_session::{ActiveStageBuilder, ActiveStageOutput};
use ironrdp_tokio::reqwest::ReqwestNetworkClient;
use ironrdp_tokio::{FramedWrite, TokioFramed, connect_begin, connect_finalize, mark_as_upgraded};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::net::TcpStream;
use tokio::sync::{broadcast, mpsc};
use tokio::time::{Duration, timeout};
use tokio_util::sync::CancellationToken;

use crate::domain::errors::{RdpError, Result};
use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use crate::domain::profile::RdpProfile;
use crate::domain::session::RdpConnectionStatus;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);
const FRAME_CHUNK_SIZE: usize = 256 * 1024;
#[derive(Debug)]
pub enum RdpCommand {
    MouseMove {
        x: u16,
        y: u16,
    },
    MouseButton {
        x: u16,
        y: u16,
        button: u8,
        down: bool,
    },
    MouseWheel {
        x: u16,
        y: u16,
        delta: i16,
        is_vertical: bool,
    },
    KeyboardInput {
        scancode: u16,
        down: bool,
    },
    Disconnect,
}

// RgbaFrame was previously used for a now-removed code path that
// incorrectly hardcoded x: 0, y: 0 in as_event().  It has been
// removed.  The correct path is emit_frame() which extracts the
// dirty rectangle with proper coordinates directly from DecodedImage.

pub struct RdpRuntime {
    profile: RdpProfile,
    session_id: String,
    frame_tx: broadcast::Sender<RdpFrameEvent>,
    status_tx: broadcast::Sender<RdpStatusEvent>,
    #[allow(dead_code)]
    error_tx: broadcast::Sender<RdpErrorEvent>,
    next_frame_id: Arc<AtomicU64>,
}

impl RdpRuntime {
    pub fn new(
        profile: RdpProfile,
        session_id: String,
        frame_tx: broadcast::Sender<RdpFrameEvent>,
        status_tx: broadcast::Sender<RdpStatusEvent>,
        error_tx: broadcast::Sender<RdpErrorEvent>,
        next_frame_id: Arc<AtomicU64>,
    ) -> Self {
        Self {
            profile,
            session_id,
            frame_tx,
            status_tx,
            error_tx,
            next_frame_id,
        }
    }

    fn next_frame_id(&self) -> u64 {
        self.next_frame_id.fetch_add(1, Ordering::Relaxed)
    }

    pub async fn run(
        self,
        mut command_rx: mpsc::Receiver<RdpCommand>,
        cancel_token: CancellationToken,
    ) -> Result<()> {
        if cancel_token.is_cancelled() {
            return Err(RdpError::Cancelled);
        }

        // ── Attempt 1: connect dengan setting CredSSP dari profile ────────────
        // Jika NegotiationFailed DAN profile mengaktifkan CredSSP, lakukan
        // fallback otomatis ke TLS-only (tanpa NLA).  Ini menangani server
        // Windows yang hanya support PROTOCOL_SSL tanpa PROTOCOL_HYBRID.
        let connection_result = match self.try_connect(self.profile.enable_cred_ssp, &cancel_token).await {
            Ok(result) => result,
            Err(RdpError::NegotiationFailed(ref msg)) if self.profile.enable_cred_ssp => {
                println!(
                    "[portix_rdp] NLA negotiation failed ({}), retrying without CredSSP …",
                    msg
                );
                self.emit_status(
                    RdpConnectionStatus::Connecting,
                    Some("NLA failed, retrying with TLS-only"),
                );
                self.try_connect(false, &cancel_token).await?
            }
            Err(e) => return Err(e),
        };

        let (mut tls_framed, connection_result) = connection_result;

        self.emit_status(RdpConnectionStatus::Connected, Some("connected"));

        let desktop_width = connection_result.desktop_size.width;
        let desktop_height = connection_result.desktop_size.height;

        println!(
            "[portix_rdp] negotiated desktop size: {}x{} (credssp={})",
            desktop_width, desktop_height, self.profile.enable_cred_ssp
        );

        // RgbA32: byte order R,G,B,A — sesuai dengan Flutter rgba8888
        // BgrX32 TIDAK digunakan karena menghasilkan channel-swap artifact
        let mut image = DecodedImage::new(PixelFormat::RgbA32, desktop_width, desktop_height);

        let mut active_stage = ActiveStageBuilder {
            static_channels: connection_result.static_channels,
            user_channel_id: connection_result.user_channel_id,
            io_channel_id: connection_result.io_channel_id,
            message_channel_id: connection_result.message_channel_id,
            share_id: connection_result.share_id,
            compression_type: connection_result.compression_type,
            enable_server_pointer: false,
            pointer_software_rendering: false,
        }
        .build();

        let mut input_db = Database::new();

        loop {
            tokio::select! {
                _ = cancel_token.cancelled() => {
                    println!("[portix_rdp] session {} cancelled, initiating graceful shutdown", self.session_id);
                    let _ = active_stage.graceful_shutdown();
                    return Err(RdpError::Cancelled);
                }

                pdu_result = tls_framed.read_pdu() => {
                    let (action, pdu_bytes) = pdu_result
                        .map_err(|e| RdpError::Protocol(e.to_string()))?;

                    let outputs = active_stage
                        .process(&mut image, action, &pdu_bytes)
                        .map_err(|e| RdpError::Protocol(e.to_string()))?;

                    for output in outputs {
                        match output {
                            ActiveStageOutput::ResponseFrame(frame) => {

                                tls_framed.write_all(&frame).await.map_err(RdpError::Io)?;
                            }
                            ActiveStageOutput::GraphicsUpdate(region) => {
                                println!("[run] GraphicsUpdate received: region=({},{}) to ({},{})",region.left, region.top, region.right, region.bottom);
                                self.emit_frame(&image, &region);
                            }
                            ActiveStageOutput::Terminate(_) => {
                                println!("[portix_rdp] session {} terminated by server", self.session_id);
                                return Ok(());
                            }
                            _ => {}
                        }
                    }
                }

                cmd = command_rx.recv() => {
                    match cmd {
                        Some(RdpCommand::Disconnect) | None => {
                            println!("[portix_rdp] session {} disconnect requested", self.session_id);

                            let shutdown_outputs = active_stage
                                .graceful_shutdown()
                                .map_err(|e| RdpError::Protocol(e.to_string()))?;
                            for output in shutdown_outputs {
                                if let ActiveStageOutput::ResponseFrame(frame) = output {

                                    tls_framed.write_all(&frame).await.map_err(RdpError::Io)?;
                                }
                            }
                            return Ok(());
                        }

                        Some(RdpCommand::MouseMove { x, y }) => {
                            let events = input_db.apply([Operation::MouseMove(MousePosition { x, y })]);
                            if events.is_empty() {
                                continue;
                            }

                            self.send_fast_path(&mut tls_framed, events.into_vec()).await?;
                        }

                        Some(RdpCommand::MouseButton { x, y, button, down }) => {
                            let mouse_button = match button {
                                0 => MouseButton::Left,
                                1 => MouseButton::Middle,
                                2 => MouseButton::Right,
                                _ => continue,
                            };

                            let op = if down {
                                Operation::MouseButtonPressed(mouse_button)
                            } else {
                                Operation::MouseButtonReleased(mouse_button)
                            };

                            let mut events = input_db.apply([Operation::MouseMove(MousePosition { x, y })]);
                            events.extend(input_db.apply([op]));

                            if events.is_empty() {
                                continue;
                            }

                            self.send_fast_path(&mut tls_framed, events.into_vec()).await?;
                        }

                        Some(RdpCommand::MouseWheel { x, y, delta, is_vertical }) => {
                            let mut events = input_db.apply([Operation::MouseMove(MousePosition { x, y })]);
                            events.extend(input_db.apply([Operation::WheelRotations(WheelRotations {
                                is_vertical,
                                rotation_units: delta,
                            })]));

                            if events.is_empty() {
                                continue;
                            }

                            self.send_fast_path(&mut tls_framed, events.into_vec()).await?;
                        }

                        Some(RdpCommand::KeyboardInput { scancode, down }) => {
                            let code = Scancode::from_u16(scancode);

                            let op = if down {
                                Operation::KeyPressed(code)
                            } else {
                                Operation::KeyReleased(code)
                            };

                            let events = input_db.apply([op]);
                            if events.is_empty() {
                                continue;
                            }

                            self.send_fast_path(&mut tls_framed, events.into_vec()).await?;
                        }
                    }
                }
            }
        }
    }

    /// Buka koneksi TCP + TLS + RDP negotiation dengan satu attempt.
    ///
    /// Dipanggil oleh `run()` dua kali jika diperlukan:
    ///   1. Dengan `enable_credssp = profile.enable_cred_ssp`
    ///   2. Fallback dengan `enable_credssp = false` jika attempt 1 gagal NegotiationFailed
    async fn try_connect(
        &self,
        enable_credssp: bool,
        cancel_token: &CancellationToken,
    ) -> Result<(ironrdp_tokio::TokioFramed<ironrdp_tls::TlsStream<TcpStream>>, ironrdp_connector::ConnectionResult)> {
        if cancel_token.is_cancelled() {
            return Err(RdpError::Cancelled);
        }

        println!(
            "[portix_rdp] try_connect host={} credssp={}",
            self.profile.host, enable_credssp
        );

        let tcp = timeout(
            CONNECT_TIMEOUT,
            TcpStream::connect(self.profile.socket_addr()),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(RdpError::Io)?;
        tcp.set_nodelay(true)?;

        let client_addr = tcp.peer_addr().map_err(RdpError::Io)?;

        let credentials = Credentials::UsernamePassword {
            username: self.profile.username.clone(),
            password: self.profile.password.clone().unwrap_or_default(),
        };

        let config = Config {
            desktop_size: DesktopSize {
                width: self.profile.desktop_width,
                height: self.profile.desktop_height,
            },
            desktop_scale_factor: 0,
            enable_tls: true,
            enable_credssp,
            credentials,
            domain: self.profile.domain.clone(),
            client_build: 7601, // Gunakan build standar yang kompatibel universal
            client_name: "Portix-Universal".to_owned(),
            keyboard_type: ironrdp_pdu::gcc::KeyboardType::IbmEnhanced,
            keyboard_subtype: 0,
            keyboard_functional_keys_count: 12,
            keyboard_layout: 0x0409, // Standar English (US) untuk menghindari mismatch scancode
            ime_file_name: String::new(),
            bitmap: None,
            dig_product_id: String::new(),
            client_dir: String::new(),
            alternate_shell: self.profile.alternate_shell.clone().unwrap_or_default(),
            work_dir: String::new(),
            platform: ironrdp_pdu::rdp::capability_sets::MajorPlatformType::UNSPECIFIED,
            hardware_id: None,
            request_data: None,
            autologon: false,
            enable_audio_playback: false, // Nonaktifkan fitur opsional untuk stabilitas universal
            
            // [UNIVERSAL FIX]: Kosongkan performance flags agar server mengirim bitmap mentah/standar
            performance_flags: ironrdp_pdu::rdp::client_info::PerformanceFlags::empty(), 
            
            license_cache: None,
            timezone_info: ironrdp_pdu::rdp::client_info::TimezoneInfo::default(),
            
            // [UNIVERSAL FIX]: Paksa nonaktifkan kompresi agresif untuk mencegah salah dekompresi tile ganjil
            compression_type: None, 
            
            enable_server_pointer: true, // Biarkan server handle pointer agar tidak glitch
            pointer_software_rendering: true,
            multitransport_flags: None,
        };

        let mut connector = ClientConnector::new(config, client_addr);
        let mut framed = TokioFramed::new(tcp);

        let should_upgrade = timeout(CONNECT_TIMEOUT, connect_begin(&mut framed, &mut connector))
            .await
            .map_err(|_| RdpError::ConnectionTimeout)?
            .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;

        let (raw_stream, leftover) = framed.into_inner();

        let (upgraded_stream, server_cert_der) = timeout(
            CONNECT_TIMEOUT,
            ironrdp_tls::upgrade(raw_stream, self.profile.host.as_str()),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;

        let server_public_key =
            ironrdp_tls::extract_tls_server_public_key(&server_cert_der).unwrap_or_default();

        let mut tls_framed = TokioFramed::new_with_leftover(upgraded_stream, leftover);
        let upgraded = mark_as_upgraded(should_upgrade, &mut connector);

        let mut network_client = ReqwestNetworkClient::new();

        let connection_result = timeout(
            CONNECT_TIMEOUT,
            connect_finalize(
                upgraded,
                connector,
                &mut tls_framed,
                &mut network_client,
                ServerName::new(self.profile.host.clone()),
                server_public_key.to_vec(),
                None,
            ),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;

        Ok((tls_framed, connection_result))
    }

    async fn send_fast_path<W: FramedWrite + Unpin>(
        &self,
        framed: &mut W,
        events: Vec<ironrdp_pdu::input::fast_path::FastPathInputEvent>,
    ) -> Result<()> {
        let fast_path_input =
            FastPathInput::new(events).map_err(|e| RdpError::Protocol(e.to_string()))?;

        let mut buf = vec![0u8; fast_path_input.size()];
        let mut cursor = WriteCursor::new(&mut buf);
        fast_path_input
            .encode(&mut cursor)
            .map_err(|e| RdpError::Protocol(e.to_string()))?;

        framed.write_all(&buf).await.map_err(RdpError::Io)?;
        Ok(())
    }

    fn emit_status(&self, status: RdpConnectionStatus, message: Option<&str>) {
        let _ = self.status_tx.send(RdpStatusEvent {
            session_id: self.session_id.clone(),
            status,
            message: message.map(str::to_owned),
        });
    }
    fn emit_frame(&self, image: &DecodedImage, region: &InclusiveRectangle) {
        let image_width = usize::from(image.width());
        let image_height = usize::from(image.height());

        if image_width == 0 || image_height == 0 {
            return;
        }

        let left = region.left as usize;
        let top = region.top as usize;
        let right = region.right as usize;
        let bottom = region.bottom as usize;

        if left >= image_width || top >= image_height {
            return;
        }

        let right = right.min(image_width - 1);
        let bottom = bottom.min(image_height - 1);

        let width = right - left + 1;
        let height = bottom - top + 1;

        let bpp = image.bytes_per_pixel();
        let raw_stride = image.stride();
        let source = image.data();

        if bpp != 4 {
            eprintln!("[emit_frame] ERROR: bytes_per_pixel={}, expected 4", bpp);
            return;
        }

        // ============================================================
        // FIX #1: Use raw_stride (with padding) from image, not tight_stride
        // ============================================================

        // ============================================================
        // Packing: tight-packed RGBA (no row padding in packed buffer)
        // ============================================================
        let mut packed = vec![0u8; width * height * 4];
        let target_row_stride = width * 4;

        for (row_idx, y) in (top..=bottom).enumerate() {
            let src_row_start = y * raw_stride + left * bpp;
            let src_row_len = width * bpp;
            let src_row_end = src_row_start + src_row_len;

            let dst_row_start = row_idx * target_row_stride;
            let dst_row_end = dst_row_start + src_row_len;

            if dst_row_end > packed.len() {
                eprintln!("[emit_frame] ERROR row {}: dst out of bounds", y);
                continue;
            }

            if src_row_end <= source.len() {
                if let Some(src_slice) = source.get(src_row_start..src_row_end) {
                    packed[dst_row_start..dst_row_end].copy_from_slice(src_slice);
                }
            } else {
                eprintln!(
                    "[emit_frame] ERROR row {}: src out of bounds ({}..{} > {})",
                    y, src_row_start, src_row_end, source.len()
                );
                // Fill with black
                for chunk in packed[dst_row_start..dst_row_end].chunks_exact_mut(4) {
                    chunk[0] = 0x00; chunk[1] = 0x00; chunk[2] = 0x00; chunk[3] = 0xFF;
                }
            }
        }

        // Force alpha = 0xFF (RgbA32 may produce alpha=0 → transparent)
        for pixel in packed.chunks_exact_mut(4) {
            pixel[3] = 0xFF;
        }

        let frame_id = self.next_frame_id();
        let chunk_count = packed.len().div_ceil(FRAME_CHUNK_SIZE);

        for chunk_index in 0..chunk_count {
            let start = chunk_index * FRAME_CHUNK_SIZE;
            let end = (start + FRAME_CHUNK_SIZE).min(packed.len());

            let _ = self.frame_tx.send(RdpFrameEvent {
                session_id: self.session_id.clone(),
                data: packed[start..end].to_vec(),
                width: width as u32,
                height: height as u32,
                x: left as u32,
                y: top as u32,
                frame_id,
                chunk_index: chunk_index as u32,
                chunk_count: chunk_count as u32,
            });
        }
    }
}
