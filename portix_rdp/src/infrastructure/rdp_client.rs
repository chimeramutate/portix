use ironrdp_connector::{ClientConnector, Config, Credentials, DesktopSize, ServerName};
use ironrdp_session::{ActiveStageBuilder, ActiveStageOutput};
use ironrdp_session::image::DecodedImage;
use ironrdp_tokio::{Framed, MovableTokioStream, connect_begin, connect_finalize, mark_as_upgraded};
use ironrdp_pdu::input::fast_path::{FastPathInputEvent, KeyboardFlags};
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

        // ── 2. Build Config ────────────────────────────────────────────────
        let credentials = Credentials::UsernamePassword {
            username: self.profile.username.clone(),
            password: self.profile.password.clone().unwrap_or_default(),
        };
        let config = Config {
            desktop_size: DesktopSize {
                width: self.profile.desktop_width,
                height: self.profile.desktop_height,
            },
            credentials,
            domain: self.profile.domain.clone(),
            server_name: ServerName::new(self.profile.host.clone()),
            enable_credssp: self.profile.enable_cred_ssp,
            ..Config::default()
        };

        // ── 3. Pre-TLS connection sequence ─────────────────────────────────
        let connector = ClientConnector::new(config);
        let mut framed = Framed::new(MovableTokioStream::new(tcp));

        let should_upgrade =
            timeout(CONNECT_TIMEOUT, connect_begin(&mut framed, connector))
                .await
                .map_err(|_| RdpError::ConnectionTimeout)?
                .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;

        // ── 4. TLS upgrade ─────────────────────────────────────────────────
        let (upgraded_stream, server_cert_der) = timeout(
            CONNECT_TIMEOUT,
            ironrdp_tls::upgrade(
                framed.into_inner().into_inner(),
                self.profile.host.as_str(),
            ),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;

        let server_public_key =
            ironrdp_tls::extract_tls_server_public_key(&server_cert_der).unwrap_or_default();

        let tls_framed = Framed::new(MovableTokioStream::new(upgraded_stream));
        let (mut tls_framed, connection_result) = timeout(
            CONNECT_TIMEOUT,
            connect_finalize(
                mark_as_upgraded(should_upgrade, tls_framed),
                server_public_key,
            ),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;

        // ── 5. Active session ──────────────────────────────────────────────
        self.emit_status(RdpConnectionStatus::Connected, Some("connected"));

        let mut image = DecodedImage::new(
            ironrdp_pdu::geometry::InclusiveRectangle {
                left: 0,
                top: 0,
                right: self.profile.desktop_width.saturating_sub(1),
                bottom: self.profile.desktop_height.saturating_sub(1),
            },
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
                            ActiveStageOutput::GraphicsUpdate(region) => {
                                self.emit_frame(&image, region);
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

    fn emit_frame(
        &self,
        image: &DecodedImage,
        region: ironrdp_pdu::geometry::InclusiveRectangle,
    ) {
        let w = region.width() as u32;
        let h = region.height() as u32;
        let x = region.left as u32;
        let y = region.top as u32;

        // Extract RGBA slice for the updated region
        if let Some(rgba) = image.get_region_rgba(region) {
            let _ = self.frame_tx.send(RdpFrameEvent {
                session_id: self.session_id.clone(),
                data: rgba.to_vec(),
                width: w,
                height: h,
                x,
                y,
            });
        }
    }
}
