use ironrdp_connector::{ClientConnector, Config, Credentials, DesktopSize, ServerName};
use ironrdp_graphics::image_processing::PixelFormat;
use ironrdp_input::{Database, MouseButton, MousePosition, Operation, Scancode};
use ironrdp_pdu::Encode;
use ironrdp_pdu::cursor::WriteCursor;
use ironrdp_pdu::geometry::{InclusiveRectangle, Rectangle};
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
    KeyboardInput {
        scancode: u16,
        down: bool,
    },
    Disconnect,
}

#[derive(Debug)]
struct RgbaFrame {
    width: u32,
    height: u32,
    data: Vec<u8>,
}

impl RgbaFrame {
    fn new(width: u32, height: u32) -> Self {
        let len = width as usize * height as usize * 4;

        Self {
            width,
            height,
            data: vec![0; len],
        }
    }

    fn as_event(
        &self,
        session_id: &str,
        frame_id: u64,
        chunk_index: u32,
        chunk_count: u32,
    ) -> RdpFrameEvent {
        RdpFrameEvent {
            session_id: session_id.to_owned(),
            data: self.data.clone(),
            width: self.width,
            height: self.height,
            x: 0,
            y: 0,
            frame_id,
            chunk_index,
            chunk_count,
        }
    }
}

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
            alternate_shell: self.profile.alternate_shell.clone().unwrap_or_default(),
            work_dir: String::new(),
            platform: ironrdp_pdu::rdp::capability_sets::MajorPlatformType::UNSPECIFIED,
            hardware_id: None,
            request_data: None,
            autologon: false,
            enable_audio_playback: true,
            performance_flags: ironrdp_pdu::rdp::client_info::PerformanceFlags::default(),
            license_cache: None,
            timezone_info: ironrdp_pdu::rdp::client_info::TimezoneInfo::default(),
            compression_type: None,
            enable_server_pointer: false,
            pointer_software_rendering: false,
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

        self.emit_status(RdpConnectionStatus::Connected, Some("connected"));

        let desktop_width = connection_result.desktop_size.width;
        let desktop_height = connection_result.desktop_size.height;

        println!(
            "[portix_rdp] negotiated desktop size: {}x{}",
            desktop_width, desktop_height
        );

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
        let stride = image.stride();
        let source = image.data();

        let row_bytes = width * bpp;

        let mut packed = Vec::with_capacity(row_bytes * height);

        for y in top..=bottom {
            let start = y * stride + left * bpp;
            let end = start + row_bytes;

            if end > source.len() {
                return;
            }

            packed.extend_from_slice(&source[start..end]);
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
