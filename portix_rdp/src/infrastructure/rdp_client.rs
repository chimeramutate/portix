use ironrdp_connector::{ClientConnector, Config, Credentials, DesktopSize, ServerName};
use ironrdp_graphics::image_processing::PixelFormat;
use ironrdp_pdu::geometry::InclusiveRectangle;
use ironrdp_pdu::input::fast_path::{FastPathInputEvent, KeyboardFlags};
use ironrdp_session::image::DecodedImage;
use ironrdp_session::{ActiveStageBuilder, ActiveStageOutput};
use ironrdp_tokio::reqwest::ReqwestNetworkClient;
use ironrdp_tokio::{TokioFramed, connect_begin, connect_finalize, mark_as_upgraded};
use ironrdp_input::MouseButton;
use tokio::net::TcpStream;
use tokio::sync::{broadcast, mpsc};
use tokio::time::{Duration, timeout};

use crate::domain::errors::{RdpError, Result};
use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use crate::domain::profile::RdpProfile;
use crate::domain::session::RdpConnectionStatus;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);

/// Commands sent from Flutter to an active RDP session.
pub enum RdpCommand {
    MouseMove { x: u16, y: u16 },
    MouseButton { x: u16, y: u16, button: u8, down: bool },
    KeyboardInput { scancode: u16, down: bool },
    Disconnect,
}

pub struct RdpRuntime {
    profile: RdpProfile,
    session_id: String,
    frame_tx: broadcast::Sender<RdpFrameEvent>,
    status_tx: broadcast::Sender<RdpStatusEvent>,
    #[allow(dead_code)]
    error_tx: broadcast::Sender<RdpErrorEvent>,
}

impl RdpRuntime {
    pub fn new(
        profile: RdpProfile,
        session_id: String,
        frame_tx: broadcast::Sender<RdpFrameEvent>,
        status_tx: broadcast::Sender<RdpStatusEvent>,
        error_tx: broadcast::Sender<RdpErrorEvent>,
    ) -> Self {
        Self { profile, session_id, frame_tx, status_tx, error_tx }
    }

    pub async fn run(self, mut command_rx: mpsc::Receiver<RdpCommand>) -> Result<()> {
        // ── 1. TCP connect ─────────────────────────────────────────────────
        let tcp = timeout(CONNECT_TIMEOUT, TcpStream::connect(self.profile.socket_addr()))
            .await
            .map_err(|_| RdpError::ConnectionTimeout)?
            .map_err(RdpError::Io)?;
        tcp.set_nodelay(true)?;

        // The real, resolved peer address — `ClientConnector::new` needs a
        // concrete `SocketAddr`, not a hostname string. Reading it back off
        // the already-connected socket is more reliable than re-resolving
        // `self.profile.socket_addr()` (which may be a hostname/string and
        // isn't guaranteed to be the same type `ClientConnector` expects).
        let client_addr = tcp.peer_addr().map_err(RdpError::Io)?;

        // ── 2. Build Config ────────────────────────────────────────────────
        // `Config` has NO `Default` impl in this version and NO `server_name`
        // field at all (`ServerName` is passed separately to
        // `connect_finalize`, not stored in `Config`). Every field below is
        // therefore required — values follow the defaults used by IronRDP's
        // own `ironrdp-client` reference implementation.
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
            enable_credssp: self.profile.enable_cred_ssp,
            credentials,
            domain: self.profile.domain.clone(),
            client_build: 0,
            client_name: "Portix".to_owned(),
            keyboard_type: ironrdp_pdu::gcc::KeyboardType::IbmEnhanced,
            keyboard_subtype: 0,
            keyboard_functional_keys_count: 12,
            keyboard_layout: 0,
            ime_file_name: String::new(),
            bitmap: None,
            dig_product_id: String::new(),
            client_dir: String::new(),
            alternate_shell: String::new(),
            work_dir: String::new(),
            platform: ironrdp_pdu::rdp::capability_sets::MajorPlatformType::UNSPECIFIED,
            hardware_id: None,
            request_data: None,
            autologon: false,
            enable_audio_playback: true,
            performance_flags: ironrdp_pdu::rdp::client_info::PerformanceFlags::default(),
            license_cache: None,
            timezone_info: ironrdp_pdu::rdp::client_info::TimezoneInfo::default(),
            compression_type: Some(ironrdp_pdu::rdp::client_info::CompressionType::K64),
            enable_server_pointer: true,
            pointer_software_rendering: true,
            multitransport_flags: None,
        };

        // ── 3. Pre-TLS connection sequence ─────────────────────────────────
        // `connector` stays owned + `mut`: it is borrowed by `connect_begin`
        // and `mark_as_upgraded`, then consumed (moved) by `connect_finalize`.
        // It must NOT be moved into `connect_begin` directly.
        let mut connector = ClientConnector::new(config, client_addr);

        // `MovableTokioStream` does not exist in this crate version.
        // `TokioFramed<S>` (= `Framed<TokioStream<S>>`) takes the raw stream
        // directly — no manual wrapping needed.
        let mut framed = TokioFramed::new(tcp);

        let should_upgrade = timeout(
            CONNECT_TIMEOUT,
            connect_begin(&mut framed, &mut connector),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;

        // ── 4. TLS upgrade ─────────────────────────────────────────────────
        // `into_inner()` returns (stream, leftover). The leftover bytes may
        // already contain buffered server data from the pre-TLS phase and
        // must be carried over into the post-TLS Framed, not discarded.
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

        // `mark_as_upgraded` takes the connector, not the framed stream.
        let upgraded = mark_as_upgraded(should_upgrade, &mut connector);

        // Required by `connect_finalize` for CredSSP (NLA). `ironrdp-tokio`
        // ships a ready-made implementation behind the "reqwest" feature —
        // enable it in Cargo.toml:
        //   ironrdp-tokio = { version = "0.10", features = ["reqwest"] }
        // and add `reqwest` + `url` as direct dependencies.
        // This handles TCP/UDP/HTTP(S) KDC requests for Kerberos; if you
        // only ever use NTLM, it's still safe to use (it just never gets
        // called since NTLM doesn't need network round-trips).
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

        // ── 5. Active session ──────────────────────────────────────────────
        self.emit_status(RdpConnectionStatus::Connected, Some("connected"));

        // `DecodedImage::new` takes (PixelFormat, width, height) — not an
        // InclusiveRectangle. `PixelFormat` comes from `ironrdp-graphics`,
        // which needs to be added as a direct dependency (it's only a
        // transitive one via `ironrdp-session` today).
        let mut image = DecodedImage::new(
            PixelFormat::RgbA32,
            self.profile.desktop_width,
            self.profile.desktop_height,
        );

        let mut active_stage = ActiveStageBuilder {
            static_channels: connection_result.static_channels,
            user_channel_id: connection_result.user_channel_id,
            io_channel_id: connection_result.io_channel_id,
            message_channel_id: connection_result.message_channel_id,
            share_id: connection_result.share_id,
            compression_type: connection_result.compression_type,
            enable_server_pointer: true,
            pointer_software_rendering: true,
        }
        .build();

        loop {
            tokio::select! {
                // Incoming PDUs from the RDP server
                pdu_result = tls_framed.read_pdu() => {
                    let (action, pdu_bytes) = pdu_result
                        .map_err(|e| RdpError::Protocol(e.to_string()))?;

                    let outputs = active_stage
                        .process(&mut image, action, &pdu_bytes)
                        .map_err(|e| RdpError::Protocol(e.to_string()))?;

                    for output in outputs {
                        match output {
                            ActiveStageOutput::ResponseFrame(frame) => {
                                tls_framed
                                    .write_all(&frame)
                                    .await
                                    .map_err(RdpError::Io)?;
                            }
                            // `GraphicsUpdate` DOES carry the changed
                            // rectangle in this version — your original
                            // pattern was correct here.
                            ActiveStageOutput::GraphicsUpdate(region) => {
                                self.emit_frame(&image, &region);
                            }
                            ActiveStageOutput::Terminate(_) => {
                                return Ok(());
                            }
                            _ => {}
                        }
                    }
                }

                // Commands from Flutter layer
                cmd = command_rx.recv() => {
                    match cmd {
                        Some(RdpCommand::Disconnect) | None => {
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
                            active_stage.update_mouse_pos(x, y);
                            // For MVP, just send mouse move to keep session alive
                            // Full input handling will be added post-MVP
                        }

                        Some(RdpCommand::MouseButton { x, y, button, down }) => {
                            // For MVP, mouse button input is placeholder
                            // Full input handling will be added post-MVP
                            let _ = (x, y, button, down);
                        }

                        Some(RdpCommand::KeyboardInput { scancode, down }) => {
                            // For MVP, keyboard input is placeholder
                            // Full input handling will be added post-MVP
                            let _ = (scancode, down);
                        }
                    }
                }
            }
        }
    }

    fn emit_status(&self, status: RdpConnectionStatus, message: Option<&str>) {
        let _ = self.status_tx.send(RdpStatusEvent {
            session_id: self.session_id.clone(),
            status,
            message: message.map(str::to_owned),
        });
    }

    /// Sends only the changed region to the Flutter side, as a tightly
    /// packed (width * height * bytes_per_pixel) buffer.
    ///
    /// NOTE: `DecodedImage::data_for_rect` exists in this version but
    /// returns a slice spanning full image rows (not tightly packed) when
    /// `region` doesn't cover the full image width, so it can't be sent
    /// as-is with just `region`'s width/height. This copies row-by-row
    /// using the image's real stride instead.
    fn emit_frame(&self, image: &DecodedImage, region: &InclusiveRectangle) {
        let bpp = image.bytes_per_pixel();
        let stride = image.stride();
        let full_data = image.data();

        let x = usize::from(region.left);
        let y = usize::from(region.top);
        let w = usize::from(region.width());
        let h = usize::from(region.height());

        if w == 0 || h == 0 {
            return;
        }

        let mut packed = Vec::with_capacity(w * h * bpp);
        for row in 0..h {
            let row_start = (y + row) * stride + x * bpp;
            let row_end = row_start + w * bpp;
            packed.extend_from_slice(&full_data[row_start..row_end]);
        }

        let _ = self.frame_tx.send(RdpFrameEvent {
            session_id: self.session_id.clone(),
            data: packed,
            width: w as u32,
            height: h as u32,
            x: x as u32,
            y: y as u32,
        });
    }
}