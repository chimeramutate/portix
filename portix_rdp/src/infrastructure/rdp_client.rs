use ironrdp_connector::{ClientConnector, Config, Credentials, DesktopSize, ServerName};
use ironrdp_graphics::image_processing::PixelFormat;
use ironrdp_input::{Database, MouseButton, MousePosition, Operation, Scancode, WheelRotations};
use ironrdp_pdu::Encode;
use ironrdp_pdu::cursor::WriteCursor;
use ironrdp_pdu::input::fast_path::FastPathInput;
use ironrdp_rdpdr::Rdpdr;
#[cfg(any(target_os = "macos", target_os = "linux"))]
use ironrdp_rdpdr_native::backend::NixRdpdrBackend;
use ironrdp_session::image::DecodedImage;
use ironrdp_session::{ActiveStageBuilder, ActiveStageOutput};
use ironrdp_tokio::reqwest::ReqwestNetworkClient;
use ironrdp_tokio::{FramedWrite, TokioFramed, connect_begin, connect_finalize, mark_as_upgraded};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::net::TcpStream;
use tokio::sync::{broadcast, mpsc};
use tokio::time::{Duration, MissedTickBehavior, interval, timeout};
use tokio_util::sync::CancellationToken;

use crate::domain::errors::{RdpError, Result};
use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use crate::domain::profile::RdpProfile;
use crate::domain::session::RdpConnectionStatus;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);

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
        hid_usage: u16,
        down: bool,
    },
    Disconnect,
}

fn hid_usage_to_set1(hid: u16) -> Option<u16> {
    Some(match hid {
        0x04 => 0x1E,
        0x05 => 0x30,
        0x06 => 0x2E,
        0x07 => 0x20,
        0x08 => 0x12,
        0x09 => 0x21,
        0x0A => 0x22,
        0x0B => 0x23,
        0x0C => 0x17,
        0x0D => 0x24,
        0x0E => 0x25,
        0x0F => 0x26,
        0x10 => 0x32,
        0x11 => 0x31,
        0x12 => 0x18,
        0x13 => 0x19,
        0x14 => 0x10,
        0x15 => 0x13,
        0x16 => 0x1F,
        0x17 => 0x14,
        0x18 => 0x16,
        0x19 => 0x2F,
        0x1A => 0x11,
        0x1B => 0x2D,
        0x1C => 0x15,
        0x1D => 0x2C,

        0x1E => 0x02,
        0x1F => 0x03,
        0x20 => 0x04,
        0x21 => 0x05,
        0x22 => 0x06,
        0x23 => 0x07,
        0x24 => 0x08,
        0x25 => 0x09,
        0x26 => 0x0A,
        0x27 => 0x0B,

        0x28 => 0x1C,
        0x29 => 0x01,
        0x2A => 0x0E,
        0x2B => 0x0F,
        0x2C => 0x39,
        0x2D => 0x0C,
        0x2E => 0x0D,
        0x2F => 0x1A,
        0x30 => 0x1B,
        0x31 => 0x2B,
        0x33 => 0x27,
        0x34 => 0x28,
        0x35 => 0x29,
        0x36 => 0x33,
        0x37 => 0x34,
        0x38 => 0x35,
        0x39 => 0x3A,

        0x3A => 0x3B,
        0x3B => 0x3C,
        0x3C => 0x3D,
        0x3D => 0x3E,
        0x3E => 0x3F,
        0x3F => 0x40,
        0x40 => 0x41,
        0x41 => 0x42,
        0x42 => 0x43,
        0x43 => 0x44,
        0x44 => 0x57,
        0x45 => 0x58,
        0x46 => 0xE037,
        0x47 => 0x46,
        0x48 => 0xE045,
        0x49 => 0xE052,
        0x4A => 0xE047,
        0x4B => 0xE049,
        0x4C => 0xE053,
        0x4D => 0xE04F,
        0x4E => 0xE051,
        0x4F => 0xE04D,
        0x50 => 0xE04B,
        0x51 => 0xE050,
        0x52 => 0xE048,
        0x53 => 0x45,

        0x54 => 0xE035,
        0x55 => 0x37,
        0x56 => 0x4A,
        0x57 => 0x4E,
        0x58 => 0xE01C,
        0x59 => 0x4F,
        0x5A => 0x50,
        0x5B => 0x51,
        0x5C => 0x4B,
        0x5D => 0x4C,
        0x5E => 0x4D,
        0x5F => 0x47,
        0x60 => 0x48,
        0x61 => 0x49,
        0x62 => 0x52,
        0x63 => 0x53,

        0xE0 => 0x1D,
        0xE1 => 0x2A,
        0xE2 => 0x38,
        0xE3 => 0xE05B,
        0xE4 => 0xE01D,
        0xE5 => 0x36,
        0xE6 => 0xE038,
        0xE7 => 0xE05C,

        _ => return None,
    })
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
        println!(
            "[portix_rdp][DEBUG] run() entered: session={} profile={} host={} port={} credssp={} redirect_drives={}",
            self.session_id,
            self.profile.id,
            self.profile.host,
            self.profile.port,
            self.profile.enable_cred_ssp,
            self.profile.redirect_drives,
        );

        if cancel_token.is_cancelled() {
            println!(
                "[portix_rdp][DEBUG] run() cancelled before connect: session={}",
                self.session_id
            );
            return Err(RdpError::Cancelled);
        }

        println!(
            "[portix_rdp][DEBUG] attempting try_connect with credssp={}",
            self.profile.enable_cred_ssp
        );

        let connection_result = match self
            .try_connect(self.profile.enable_cred_ssp, &cancel_token)
            .await
        {
            Ok(result) => {
                println!(
                    "[portix_rdp][DEBUG] try_connect succeeded: session={}",
                    self.session_id
                );
                result
            }
            Err(RdpError::NegotiationFailed(ref msg))
                if self.profile.enable_cred_ssp && !self.profile.is_cyberark_psm() =>
            {
                println!(
                    "[portix_rdp][DEBUG] NLA negotiation failed ({}), retrying without CredSSP …",
                    msg
                );
                self.emit_status(
                    RdpConnectionStatus::Connecting,
                    Some("NLA failed, retrying with TLS-only"),
                );
                self.try_connect(false, &cancel_token).await?
            }
            Err(RdpError::NegotiationFailed(ref msg))
                if !self.profile.is_cyberark_psm()
                    && self.profile.redirect_drives
                    && (msg.contains("LicenseExchangeState")
                        || msg.contains("UpgradeLicense")
                        || msg.contains("SERVER_NEW_LICENSE")) =>
            {
                // try_connect already attaches only RDPDR (no rdpsnd).
                // If the server still rejects the drive redirection channel,
                // fall back to a connection without any static channels.
                println!(
                    "[portix_rdp][DEBUG] license exchange failed during connection ({}), \
                     retrying without drive redirection",
                    msg
                );
                self.emit_status(
                    RdpConnectionStatus::Connecting,
                    Some("Drive redirection rejected by server, retrying without it"),
                );
                self.try_connect_without_redirect(self.profile.enable_cred_ssp, &cancel_token)
                    .await?
            }
            Err(e) => {
                println!(
                    "[portix_rdp][DEBUG] try_connect failed: session={} error={:?}",
                    self.session_id, e
                );
                return Err(e);
            }
        };

        let (mut tls_framed, connection_result) = connection_result;

        println!(
            "[portix_rdp][DEBUG] connection established, emitting Connected status: session={}",
            self.session_id
        );
        self.emit_status(RdpConnectionStatus::Connected, Some("connected"));

        let desktop_width = connection_result.desktop_size.width;
        let desktop_height = connection_result.desktop_size.height;

        println!(
            "[portix_rdp][DEBUG] negotiated desktop size: {}x{} (credssp={})",
            desktop_width, desktop_height, self.profile.enable_cred_ssp
        );

        println!(
            "[portix_rdp][DEBUG] static_channels={} user_channel_id={} io_channel_id={} message_channel_id={:?} share_id={} compression_type={:?}",
            connection_result.static_channels.iter().count(),
            connection_result.user_channel_id,
            connection_result.io_channel_id,
            connection_result.message_channel_id,
            connection_result.share_id,
            connection_result.compression_type,
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

        println!(
            "[portix_rdp][DEBUG] ActiveStage built, entering main loop: session={}",
            self.session_id
        );

        let mut input_db = Database::new();
        let mut frame_dirty = false;
        let mut frame_tick = interval(Duration::from_millis(33));
        frame_tick.set_missed_tick_behavior(MissedTickBehavior::Skip);

        loop {
            tokio::select! {
                _ = frame_tick.tick() => {
                    if frame_dirty {
                        println!(
                            "[portix_rdp][DEBUG] emitting full frame: session={} size={}x{}",
                            self.session_id, desktop_width, desktop_height
                        );
                        self.emit_full_frame(&image);
                        frame_dirty = false;
                    }
                }

                _ = cancel_token.cancelled() => {
                    println!("[portix_rdp][DEBUG] session {} cancelled, initiating graceful shutdown", self.session_id);
                    let _ = active_stage.graceful_shutdown();
                    return Err(RdpError::Cancelled);
                }

                pdu_result = tls_framed.read_pdu() => {
                    let (action, pdu_bytes) = match pdu_result {
                        Ok(v) => v,
                        Err(e) => {
                            println!(
                                "[portix_rdp][DEBUG] read_pdu error: session={} error={:?}",
                                self.session_id, e
                            );
                            return Err(RdpError::Protocol(e.to_string()));
                        }
                    };

                    println!(
                        "[portix_rdp][DEBUG] read_pdu: session={} action={:?} pdu_len={}",
                        self.session_id, action, pdu_bytes.len()
                    );

                    let outputs = match active_stage
                        .process(&mut image, action, &pdu_bytes)
                    {
                        Ok(v) => v,
                        Err(e) => {
                            println!(
                                "[portix_rdp][DEBUG] active_stage.process error: session={} error={:?}",
                                self.session_id, e
                            );
                            return Err(RdpError::Protocol(e.to_string()));
                        }
                    };

                    println!(
                        "[portix_rdp][DEBUG] active_stage.process returned {} outputs",
                        outputs.len()
                    );

                    for output in outputs {
                        match output {
                            ActiveStageOutput::ResponseFrame(frame) => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::ResponseFrame: session={} len={}",
                                    self.session_id,
                                    frame.len()
                                );
                                tls_framed.write_all(&frame).await.map_err(RdpError::Io)?;
                            }
                            ActiveStageOutput::GraphicsUpdate(region) => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::GraphicsUpdate: session={} region={:?}",
                                    self.session_id, region
                                );
                                frame_dirty = true;
                            }
                            ActiveStageOutput::Terminate(reason) => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::Terminate: session={} reason={:?} description={}",
                                    self.session_id, reason, reason.description()
                                );
                                println!(
                                    "[portix_rdp] session {} terminated by server: {}",
                                    self.session_id, reason.description()
                                );
                                return Ok(());
                            }
                            ActiveStageOutput::PointerDefault => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::PointerDefault: session={}",
                                    self.session_id
                                );
                            }
                            ActiveStageOutput::PointerHidden => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::PointerHidden: session={}",
                                    self.session_id
                                );
                            }
                            ActiveStageOutput::PointerPosition { x, y } => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::PointerPosition: session={} x={} y={}",
                                    self.session_id, x, y
                                );
                            }
                            ActiveStageOutput::PointerBitmap(_) => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::PointerBitmap: session={}",
                                    self.session_id
                                );
                            }
                            ActiveStageOutput::DeactivateAll => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::DeactivateAll: session={}",
                                    self.session_id
                                );
                            }
                            ActiveStageOutput::MultitransportRequest(_) => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::MultitransportRequest: session={}",
                                    self.session_id
                                );
                            }
                            ActiveStageOutput::AutoDetect(_) => {
                                println!(
                                    "[portix_rdp][DEBUG] ActiveStageOutput::AutoDetect: session={}",
                                    self.session_id
                                );
                            }
                        }
                    }
                }

                cmd = command_rx.recv() => {
                    match cmd {
                        Some(RdpCommand::Disconnect) | None => {
                            println!("[portix_rdp][DEBUG] session {} disconnect requested", self.session_id);

                            let shutdown_outputs = active_stage
                                .graceful_shutdown()
                                .map_err(|e| RdpError::Protocol(e.to_string()))?;
                            for output in shutdown_outputs {
                                if let ActiveStageOutput::ResponseFrame(frame) = output {
                                    println!(
                                        "[portix_rdp][DEBUG] sending graceful shutdown frame: session={} len={}",
                                        self.session_id,
                                        frame.len()
                                    );
                                    tls_framed.write_all(&frame).await.map_err(RdpError::Io)?;
                                }
                            }
                            return Ok(());
                        }

                        Some(RdpCommand::MouseMove { x, y }) => {
                            println!(
                                "[portix_rdp][DEBUG] MouseMove: session={} x={} y={}",
                                self.session_id, x, y
                            );
                            let events = input_db.apply([Operation::MouseMove(MousePosition { x, y })]);
                            if events.is_empty() {
                                continue;
                            }

                            self.send_fast_path(&mut tls_framed, events.into_vec()).await?;
                        }

                        Some(RdpCommand::MouseButton { x, y, button, down }) => {
                            println!(
                                "[portix_rdp][DEBUG] MouseButton: session={} x={} y={} button={} down={}",
                                self.session_id, x, y, button, down
                            );
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
                            println!(
                                "[portix_rdp][DEBUG] MouseWheel: session={} x={} y={} delta={} is_vertical={}",
                                self.session_id, x, y, delta, is_vertical
                            );
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

                        Some(RdpCommand::KeyboardInput { hid_usage, down }) => {
                            println!(
                                "[portix_rdp][DEBUG] KeyboardInput: session={} hid_usage=0x{:04X} down={}",
                                self.session_id, hid_usage, down
                            );
                            let Some(scancode) = hid_usage_to_set1(hid_usage) else {
                                println!(
                                    "[portix_rdp][DEBUG] KeyboardInput: unknown hid_usage=0x{:04X}, ignoring",
                                    hid_usage
                                );
                                continue;
                            };
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

    async fn try_connect(
        &self,
        enable_credssp: bool,
        cancel_token: &CancellationToken,
    ) -> Result<(
        ironrdp_tokio::TokioFramed<ironrdp_tls::TlsStream<TcpStream>>,
        ironrdp_connector::ConnectionResult,
    )> {
        if cancel_token.is_cancelled() {
            println!(
                "[portix_rdp][DEBUG] try_connect cancelled: session={}",
                self.session_id
            );
            return Err(RdpError::Cancelled);
        }

        println!(
            "[portix_rdp][DEBUG] try_connect: session={} host={} port={} credssp={} redirect_drives={}",
            self.session_id,
            self.profile.host,
            self.profile.port,
            enable_credssp,
            self.profile.redirect_drives
        );

        println!(
            "[portix_rdp][DEBUG] connecting TCP: {}:{}",
            self.profile.host, self.profile.port
        );
        let tcp = timeout(
            CONNECT_TIMEOUT,
            TcpStream::connect(self.profile.socket_addr()),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(RdpError::Io)?;
        tcp.set_nodelay(true)?;

        let local_addr = tcp.local_addr().map_err(RdpError::Io)?;
        let client_addr = tcp.peer_addr().map_err(RdpError::Io)?;
        println!(
            "[portix_rdp][DEBUG] TCP connected: local={} remote={}",
            local_addr, client_addr
        );

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
            client_build: 7601,
            client_name: "Portix".to_owned(),
            keyboard_type: ironrdp_pdu::gcc::KeyboardType::IbmEnhanced,
            keyboard_subtype: 0,
            keyboard_functional_keys_count: 12,
            keyboard_layout: 0x0409,
            ime_file_name: String::new(),
            bitmap: None,
            dig_product_id: String::new(),
            client_dir: "C:\\Windows\\System32\\mstscax.dll".to_owned(),
            alternate_shell: self.profile.alternate_shell.clone().unwrap_or_default(),
            work_dir: String::new(),
            platform: ironrdp_pdu::rdp::capability_sets::MajorPlatformType::WINDOWS,
            hardware_id: None,
            request_data: None,
            autologon: false,
            enable_audio_playback: false,

            performance_flags: ironrdp_pdu::rdp::client_info::PerformanceFlags::empty(),

            license_cache: None,
            timezone_info: ironrdp_pdu::rdp::client_info::TimezoneInfo::default(),

            compression_type: None,

            enable_server_pointer: true,
            pointer_software_rendering: true,
            multitransport_flags: None,
        };

        let mut connector = ClientConnector::new(config, client_addr);

        #[cfg(any(target_os = "macos", target_os = "linux"))]
        if self.profile.has_local_share() {
            let share_path = self.profile.local_share_path().unwrap_or("").to_owned();
            let share_name = self.profile.local_share_name().to_owned();

            println!(
                "[portix_rdp][DEBUG] setting up drive redirect: path={} name={}",
                share_path, share_name
            );

            if let Err(e) = std::fs::create_dir_all(&share_path) {
                println!(
                    "[portix_rdp] WARNING: cannot create share dir '{}': {}",
                    share_path, e
                );
            } else {
                println!(
                    "[portix_rdp] drive redirect: sharing '{}' as '{}' (\\\\tsclient\\{})",
                    share_path, share_name, share_name
                );
            }

            let backend = NixRdpdrBackend::new(share_path.clone());

            let computer_name = hostname::get()
                .ok()
                .and_then(|h| h.into_string().ok())
                .unwrap_or_else(|| "Portix".to_owned());

            let rdpdr = Rdpdr::new(Box::new(backend), computer_name.clone())
                .with_drives(Some(vec![(1u32, share_name.clone())]));

            println!(
                "[portix_rdp][DEBUG] attaching rdpdr channel (computer_name='{}', drive='{}')",
                computer_name, share_name
            );

            connector.attach_static_channel(rdpdr);

            // NOTE: we deliberately do NOT attach an rdpsnd (audio) channel.
            //
            // The RDP profile may have `enable_audio_playback: false`, and the
            // user never requested audio. Sending an rdpsnd channel request to
            // servers that reject it (e.g. CyberArk PSM) causes the connection
            // to fail during license exchange ("SERVER_NEW_LICENSE decode error").
            //
            // rdpdr (drive redirection) and rdpsnd (audio) are independent
            // static channels — RDPDR does NOT require rdpsnd as a companion.
            // Keeping only rdpdr preserves WinSCP file transfer via
            // \\tsclient\PORTIX without sending an unwanted audio channel.
        } else {
            println!(
                "[portix_rdp][DEBUG] no drive redirect configured (redirect_drives={} has_local_share={})",
                self.profile.redirect_drives,
                self.profile.has_local_share()
            );
        }

        let mut framed = TokioFramed::new(tcp);

        println!("[portix_rdp][DEBUG] calling connect_begin (X.224 negotiation)...");
        let should_upgrade = timeout(CONNECT_TIMEOUT, connect_begin(&mut framed, &mut connector))
            .await
            .map_err(|_| RdpError::ConnectionTimeout)?
            .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;
        println!(
            "[portix_rdp][DEBUG] connect_begin succeeded: should_upgrade=true (TLS upgrade required)"
        );

        let (raw_stream, leftover) = framed.into_inner();

        println!(
            "[portix_rdp][DEBUG] upgrading to TLS: host={} leftover_len={}",
            self.profile.host,
            leftover.len()
        );
        let (upgraded_stream, server_cert_der) = timeout(
            CONNECT_TIMEOUT,
            ironrdp_tls::upgrade(raw_stream, self.profile.host.as_str()),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;
        let server_public_key =
            ironrdp_tls::extract_tls_server_public_key(&server_cert_der).unwrap_or_default();
        println!(
            "[portix_rdp][DEBUG] TLS upgrade succeeded: server_public_key_len={}",
            server_public_key.len()
        );

        let mut tls_framed = TokioFramed::new_with_leftover(upgraded_stream, leftover);
        let upgraded = mark_as_upgraded(should_upgrade, &mut connector);

        let mut network_client = ReqwestNetworkClient::new();

        println!(
            "[portix_rdp][DEBUG] calling connect_finalize (capability exchange, license, etc.)..."
        );
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
        println!(
            "[portix_rdp][DEBUG] connect_finalize succeeded: desktop={}x{} static_channels={}",
            connection_result.desktop_size.width,
            connection_result.desktop_size.height,
            connection_result.static_channels.iter().count()
        );

        Ok((tls_framed, connection_result))
    }

    /// Connect without RDPDR/rdpsnd static channels.
    ///
    /// Used as a fallback when the server (e.g. CyberArk PSM) rejects
    /// drive redirection during the license exchange phase.
    async fn try_connect_without_redirect(
        &self,
        enable_credssp: bool,
        cancel_token: &CancellationToken,
    ) -> Result<(
        ironrdp_tokio::TokioFramed<ironrdp_tls::TlsStream<TcpStream>>,
        ironrdp_connector::ConnectionResult,
    )> {
        if cancel_token.is_cancelled() {
            println!(
                "[portix_rdp][DEBUG] try_connect_without_redirect cancelled: session={}",
                self.session_id
            );
            return Err(RdpError::Cancelled);
        }

        println!(
            "[portix_rdp][DEBUG] try_connect_without_redirect: session={} host={} port={} credssp={} (no RDPDR/rdpsnd)",
            self.session_id, self.profile.host, self.profile.port, enable_credssp
        );

        println!(
            "[portix_rdp][DEBUG] connecting TCP (no redirect): {}:{}",
            self.profile.host, self.profile.port
        );
        let tcp = timeout(
            CONNECT_TIMEOUT,
            TcpStream::connect(self.profile.socket_addr()),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(RdpError::Io)?;
        tcp.set_nodelay(true)?;

        let local_addr = tcp.local_addr().map_err(RdpError::Io)?;
        let client_addr = tcp.peer_addr().map_err(RdpError::Io)?;
        println!(
            "[portix_rdp][DEBUG] TCP connected (no redirect): local={} remote={}",
            local_addr, client_addr
        );

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
            client_build: 7601,
            client_name: "Portix".to_owned(),
            keyboard_type: ironrdp_pdu::gcc::KeyboardType::IbmEnhanced,
            keyboard_subtype: 0,
            keyboard_functional_keys_count: 12,
            keyboard_layout: 0x0409,
            ime_file_name: String::new(),
            bitmap: None,
            dig_product_id: String::new(),
            client_dir: "C:\\Windows\\System32\\mstscax.dll".to_owned(),
            alternate_shell: self.profile.alternate_shell.clone().unwrap_or_default(),
            work_dir: String::new(),
            platform: ironrdp_pdu::rdp::capability_sets::MajorPlatformType::WINDOWS,
            hardware_id: None,
            request_data: None,
            autologon: false,
            enable_audio_playback: false,

            performance_flags: ironrdp_pdu::rdp::client_info::PerformanceFlags::empty(),

            license_cache: None,
            timezone_info: ironrdp_pdu::rdp::client_info::TimezoneInfo::default(),

            compression_type: None,

            enable_server_pointer: true,
            pointer_software_rendering: true,
            multitransport_flags: None,
        };

        // NOTE: deliberately NOT attaching RDPDR or rdpsnd channels.
        let mut connector = ClientConnector::new(config, client_addr);

        let mut framed = TokioFramed::new(tcp);

        println!("[portix_rdp][DEBUG] calling connect_begin (no redirect)...");
        let should_upgrade = timeout(CONNECT_TIMEOUT, connect_begin(&mut framed, &mut connector))
            .await
            .map_err(|_| RdpError::ConnectionTimeout)?
            .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;
        println!(
            "[portix_rdp][DEBUG] connect_begin succeeded (no redirect): should_upgrade=true (TLS upgrade required)"
        );

        let (raw_stream, leftover) = framed.into_inner();

        println!(
            "[portix_rdp][DEBUG] upgrading to TLS (no redirect): host={} leftover_len={}",
            self.profile.host,
            leftover.len()
        );
        let (upgraded_stream, server_cert_der) = timeout(
            CONNECT_TIMEOUT,
            ironrdp_tls::upgrade(raw_stream, self.profile.host.as_str()),
        )
        .await
        .map_err(|_| RdpError::ConnectionTimeout)?
        .map_err(|e| RdpError::NegotiationFailed(e.to_string()))?;
        let server_public_key =
            ironrdp_tls::extract_tls_server_public_key(&server_cert_der).unwrap_or_default();
        println!(
            "[portix_rdp][DEBUG] TLS upgrade succeeded (no redirect): server_public_key_len={}",
            server_public_key.len()
        );

        let mut tls_framed = TokioFramed::new_with_leftover(upgraded_stream, leftover);
        let upgraded = mark_as_upgraded(should_upgrade, &mut connector);

        let mut network_client = ReqwestNetworkClient::new();

        println!("[portix_rdp][DEBUG] calling connect_finalize (no redirect)...");
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
        println!(
            "[portix_rdp][DEBUG] connect_finalize succeeded (no redirect): desktop={}x{} static_channels={}",
            connection_result.desktop_size.width,
            connection_result.desktop_size.height,
            connection_result.static_channels.iter().count()
        );

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

        println!(
            "[portix_rdp][DEBUG] sending fast_path input: session={} len={}",
            self.session_id,
            buf.len()
        );
        framed.write_all(&buf).await.map_err(RdpError::Io)?;
        Ok(())
    }

    fn emit_status(&self, status: RdpConnectionStatus, message: Option<&str>) {
        println!(
            "[portix_rdp][DEBUG] emit_status: session={} status={:?} message={:?}",
            self.session_id, status, message
        );
        let _ = self.status_tx.send(RdpStatusEvent {
            session_id: self.session_id.clone(),
            status,
            message: message.map(str::to_owned),
        });
    }
    fn emit_full_frame(&self, image: &DecodedImage) {
        let width = image.width() as usize;
        let height = image.height() as usize;
        let bpp = image.bytes_per_pixel();

        if width == 0 || height == 0 || bpp != 4 {
            println!(
                "[portix_rdp][DEBUG] emit_full_frame: invalid dimensions: width={} height={} bpp={}",
                width, height, bpp
            );
            return;
        }

        let source = image.data();
        let source_stride = image.stride();
        let row_bytes = width * 4;
        let expected = source_stride.saturating_mul(height);

        if source.len() < expected || source_stride < row_bytes {
            eprintln!(
                "[portix_rdp] invalid decoded framebuffer: len={} stride={} expected={} row_bytes={}",
                source.len(),
                source_stride,
                expected,
                row_bytes
            );
            return;
        }

        let mut data = vec![0u8; row_bytes * height];

        for row in 0..height {
            let src_start = row * source_stride;
            let src_end = src_start + row_bytes;
            let dst_start = row * row_bytes;
            let dst_end = dst_start + row_bytes;
            data[dst_start..dst_end].copy_from_slice(&source[src_start..src_end]);
        }

        for pixel in data.chunks_exact_mut(4) {
            pixel[3] = 0xFF;
        }

        let frame_id = self.next_frame_id();
        let event = RdpFrameEvent {
            session_id: self.session_id.clone(),
            data,
            width: width as u32,
            height: height as u32,
            x: 0,
            y: 0,
            frame_id,
        };

        println!(
            "[portix_rdp][DEBUG] emitting frame: session={} frame_id={} size={}x{} data_len={}",
            self.session_id,
            frame_id,
            width,
            height,
            event.data.len()
        );
        let _ = self.frame_tx.send(event);
    }
}
