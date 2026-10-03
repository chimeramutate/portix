use ironrdp_cliprdr::pdu::{ClipboardFormat, ClipboardFormatId, FormatDataResponse};
use ironrdp_cliprdr::{Cliprdr, CliprdrClient};
use ironrdp_connector::{
    ClientConnector, ClientConnectorState, Config, ConnectionResult, ConnectorError,
    ConnectorErrorExt as _, ConnectorResult, Credentials, DesktopSize, LicenseCache, Sequence,
    ServerName,
};
use ironrdp_core::WriteBuf;
use ironrdp_core::encode_vec;
use ironrdp_graphics::image_processing::PixelFormat;
use ironrdp_input::{Database, MouseButton, MousePosition, Operation, Scancode, WheelRotations};
use ironrdp_pdu::Encode;
use ironrdp_pdu::cursor::WriteCursor;
use ironrdp_pdu::input::fast_path::FastPathInput;
use ironrdp_rdpdr::Rdpdr;
#[cfg(any(target_os = "macos", target_os = "linux"))]
use ironrdp_rdpdr_native::backend::NixRdpdrBackend;

use ironrdp_session::image::DecodedImage;
use ironrdp_session::{ActiveStage, ActiveStageBuilder, ActiveStageOutput};
use ironrdp_tokio::reqwest::ReqwestNetworkClient;
use ironrdp_tokio::{
    FramedRead, FramedWrite, TokioFramed, connect_begin, connect_finalize, mark_as_upgraded,
};
use std::borrow::Cow;
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
use crate::infrastructure::clipboard::{ClipboardAction, ClipboardBackend, ClipboardSync};
use crate::infrastructure::license_cache::{StubLicenseCache, is_cyberark_pam, is_license_error};
use crate::infrastructure::rdpsnd::NoopRdpSnd;

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
        if cancel_token.is_cancelled() {
            return Err(RdpError::Cancelled);
        }

        // ── Pre-emptive licence cache for CyberArk PAM/PSM ──────────────
        // When the username matches the CyberArk pattern (PSM@… / PAM@…),
        // use StubLicenseCache from the very first attempt. This makes the
        // client send CLIENT_LICENSE_INFO instead of CLIENT_NEW_LICENSE_REQUEST,
        // which causes the PSM gateway to reply with LicensingErrorMessage(
        // StatusValidClient) — a well-formed PDU — instead of the malformed
        // ServerUpgradeLicense that triggers the decode error.
        let is_cyberark = is_cyberark_pam(&self.profile.username);
        if is_cyberark {
            println!(
                "[portix_rdp] CyberArk PAM/PSM detected (username={}), using stub license cache to skip license upgrade",
                self.profile.username
            );
        }
        let pre_emptive_cache: Option<Arc<dyn LicenseCache>> = if is_cyberark {
            Some(Arc::new(StubLicenseCache))
        } else {
            None
        };

        let connection_result = match self
            .try_connect(
                self.profile.enable_cred_ssp,
                pre_emptive_cache.clone(),
                false,
                &cancel_token,
            )
            .await
        {
            Ok(result) => {
                println!("[portix_rdp] connect_begin completed");
                result
            }
            // ── CredSSP enabled, license decode error → retry with stub cache,
            //    still with CredSSP ──
            Err(RdpError::NegotiationFailed(ref msg))
                if self.profile.enable_cred_ssp && is_license_error(msg) =>
            {
                println!(
                    "[portix_rdp] License exchange decode error ({}), retrying with stub license cache …",
                    msg
                );
                self.emit_status(
                    RdpConnectionStatus::Connecting,
                    Some("License exchange failed, retrying with fallback cache"),
                );
                self.try_connect(true, Some(Arc::new(StubLicenseCache)), true, &cancel_token)
                    .await?
            }
            // ── CredSSP enabled, any other negotiation failure → stop ──
            // No silent fallback to TLS-only: someone on the network could
            // break NLA on purpose to get the credentials sent without it
            // (and the server certificate is not pinned). The user can turn
            // NLA off for servers that really lack it.
            Err(RdpError::NegotiationFailed(msg)) if self.profile.enable_cred_ssp => {
                eprintln!("[portix_rdp] ERROR: NLA negotiation failed: {}", msg);
                return Err(RdpError::NegotiationFailed(format!(
                    "NLA failed: {msg}. If this server does not support NLA, turn off \"Enable CredSSP (NLA)\" in the profile."
                )));
            }
            // ── CredSSP disabled, license decode error → retry with stub cache ──
            Err(RdpError::NegotiationFailed(ref msg))
                if !self.profile.enable_cred_ssp && is_license_error(msg) =>
            {
                println!(
                    "[portix_rdp] License exchange decode error ({}), retrying with stub license cache …",
                    msg
                );
                self.emit_status(
                    RdpConnectionStatus::Connecting,
                    Some("License exchange failed, retrying with fallback cache"),
                );
                self.try_connect(
                    false,
                    Some(Arc::new(StubLicenseCache)),
                    true, // license_bypass: PDU repair mode
                    &cancel_token,
                )
                .await
                .map_err(|e| {
                    eprintln!(
                        "[portix_rdp] ERROR: All connection retries exhausted. Last error: {:?}",
                        e
                    );
                    e
                })?
            }
            Err(RdpError::ConnectionTimeout) => {
                eprintln!(
                    "[portix_rdp] ERROR: Connection timeout to {}",
                    self.profile.host
                );
                return Err(RdpError::ConnectionTimeout);
            }
            Err(RdpError::Io(e)) => {
                eprintln!("[portix_rdp] ERROR: IO error during connection: {}", e);
                return Err(RdpError::Io(e));
            }
            Err(e) => {
                eprintln!("[portix_rdp] ERROR: Connection failed: {:?}", e);
                return Err(e);
            }
        };

        let (mut tls_framed, connection_result) = connection_result;

        self.emit_status(RdpConnectionStatus::Connected, Some("connected"));

        let desktop_width = connection_result.desktop_size.width;
        let desktop_height = connection_result.desktop_size.height;

        println!(
            "[portix_rdp] negotiated desktop size: {}x{} (credssp={})",
            desktop_width, desktop_height, self.profile.enable_cred_ssp
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
        let mut frame_dirty = false;
        let mut frame_tick = interval(Duration::from_millis(33));
        frame_tick.set_missed_tick_behavior(MissedTickBehavior::Skip);

        // Kept open for the whole session: on Linux the copied text is only
        // served while the clipboard handle lives.
        let mut local_clipboard = self
            .profile
            .redirect_clipboard
            .then(|| arboard::Clipboard::new().ok())
            .flatten();
        let mut clipboard_sync = ClipboardSync::default();
        let mut clipboard_tick = interval(Duration::from_secs(1));
        clipboard_tick.set_missed_tick_behavior(MissedTickBehavior::Skip);

        loop {
            tokio::select! {
                _ = frame_tick.tick() => {
                    if frame_dirty {
                        self.emit_full_frame(&image);
                        frame_dirty = false;
                    }
                }

                _ = clipboard_tick.tick(), if local_clipboard.is_some() => {
                    let text = local_clipboard.as_mut().and_then(|c| c.get_text().ok());
                    if let Some(action) = clipboard_sync.on_local_text(text) {
                        self.apply_clipboard_action(&mut active_stage, &mut tls_framed, &mut local_clipboard, action).await?;
                    }
                }

                _ = cancel_token.cancelled() => {
                    println!("[portix_rdp] session {} cancelled, initiating graceful shutdown", self.session_id);
                    let _ = active_stage.graceful_shutdown();
                    return Err(RdpError::Cancelled);
                }

                pdu_result = tls_framed.read_pdu() => {
                    match pdu_result {
                        Ok((action, pdu_bytes)) => {
                            let outputs = match active_stage.process(&mut image, action, &pdu_bytes) {
                                Ok(o) => o,
                                Err(e) => {
                                    eprintln!("[portix_rdp] PROTOCOL ERROR in process(): {}", e);
                                    return Err(RdpError::Protocol(e.to_string()));
                                }
                            };

                            for output in outputs {
                                match output {
                                    ActiveStageOutput::ResponseFrame(frame) => {
                                        if let Err(e) = tls_framed.write_all(&frame).await {
                                            eprintln!("[portix_rdp] IO ERROR writing frame: {}", e);
                                            return Err(RdpError::Io(e));
                                        }
                                    }
                                    ActiveStageOutput::GraphicsUpdate(_region) => {
                                        frame_dirty = true;
                                    }
                                    ActiveStageOutput::Terminate(_) => {
                                        println!("[portix_rdp] session {} terminated by server", self.session_id);
                                        return Ok(());
                                    }
                                    _ => {}
                                }
                            }

                            let clipboard_events = active_stage
                                .get_svc_processor_mut::<CliprdrClient>()
                                .and_then(|cliprdr| cliprdr.downcast_backend_mut::<ClipboardBackend>())
                                .map(ClipboardBackend::take_events)
                                .unwrap_or_default();
                            for event in clipboard_events {
                                let action = clipboard_sync.on_remote_event(event, || {
                                    local_clipboard.as_mut().and_then(|c| c.get_text().ok())
                                });
                                if let Some(action) = action {
                                    self.apply_clipboard_action(&mut active_stage, &mut tls_framed, &mut local_clipboard, action).await?;
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("[portix_rdp] PROTOCOL ERROR reading PDU: {}", e);
                            return Err(RdpError::Protocol(e.to_string()));
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

                        Some(RdpCommand::KeyboardInput { hid_usage, down }) => {
                            let Some(scancode) = hid_usage_to_set1(hid_usage) else {
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

    /// Custom `connect_finalize` that pre-validates license-exchange PDUs before
    /// passing them to `ClientConnector::step()`.  When the connector is in the
    /// `LicensingExchange` state, each PDU read from the stream is first decoded
    /// as a `LicensePdu`.  If the decode fails (the server sent a malformed
    /// `ServerUpgradeLicense`, as CyberArk PAS/PSM does), the PDU is **repaired**
    /// in-place: a `LicensingErrorMessage(StatusValidClient)` is synthesised,
    /// wrapped in a `SendDataIndication` with the original channel info, re-encoded
    /// as an X.224 PDU, and handed to `step()` instead.  This prevents the
    /// `LicenseExchangeSequence` from consuming its state and lets the connector
    /// proceed to `LicenseExchanged` → `MultitransportBootstrapping` → … → `Connected`.
    ///
    /// This function assumes CredSSP is **disabled** (`enable_credssp = false`),
    /// which is always the case in the retry tiers that use it.
    async fn connect_finalize_with_license_bypass<S>(
        connector: ClientConnector,
        framed: &mut ironrdp_tokio::Framed<S>,
    ) -> ConnectorResult<ConnectionResult>
    where
        S: FramedRead + FramedWrite,
    {
        use ironrdp_connector::ConnectorErrorKind;
        use ironrdp_pdu::mcs::{McsMessage, SendDataIndication, decode_send_data_indication};
        use ironrdp_pdu::rdp::server_license::{LicensePdu, LicensingErrorMessage};
        use ironrdp_pdu::x224::X224;
        use std::mem;

        let mut connector = connector;
        let mut buf = WriteBuf::new();

        // CredSSP is disabled for this code path; skip perform_credssp_step entirely.
        // The connector should already be past EnhancedSecurityUpgrade (mark_as_upgraded
        // was called by the caller).

        loop {
            buf.clear();

            let next_pdu_hint = connector.next_pdu_hint();

            if let Some(hint) = next_pdu_hint {
                // Read PDU from the stream.
                let pdu = framed.read_by_hint(hint).await.map_err(|e| {
                    ConnectorError::new("read frame by hint", ConnectorErrorKind::General)
                        .with_source(e)
                })?;

                // Pre-validate: if in LicensingExchange state, try to decode as LicensePdu.
                let is_licensing = matches!(
                    &connector.state,
                    ClientConnectorState::LicensingExchange { .. }
                );

                let input: Vec<u8> = if is_licensing {
                    // Attempt to decode the PDU as a SendDataIndication + LicensePdu.
                    let pre_decode: std::result::Result<(), ironrdp_core::DecodeError> = (|| {
                        let sdi_ctx = decode_send_data_indication(&pdu)?;
                        let _: LicensePdu = sdi_ctx.decode_user_data()?;
                        Ok(())
                    })(
                    );

                    if pre_decode.is_ok() {
                        // PDU decodes fine — use as-is.
                        pdu.to_vec()
                    } else {
                        // Malformed license PDU — attempt repair.
                        eprintln!(
                            "[portix_rdp] License PDU decode failed, attempting in-place repair..."
                        );

                        match decode_send_data_indication(&pdu) {
                            Ok(sdi_ctx) => {
                                // Build a LicensingErrorMessage(StatusValidClient).
                                let err_msg = LicensingErrorMessage::new_valid_client()
                                    .map_err(ConnectorError::encode)?;
                                let license_pdu_bytes =
                                    encode_vec(&LicensePdu::LicensingErrorMessage(err_msg))
                                        .map_err(ConnectorError::encode)?;

                                // Wrap in a SendDataIndication with the original channel info.
                                let repaired = SendDataIndication {
                                    initiator_id: sdi_ctx.initiator_id,
                                    channel_id: sdi_ctx.channel_id,
                                    user_data: Cow::Owned(license_pdu_bytes),
                                };

                                let repaired_pdu = X224(McsMessage::SendDataIndication(repaired));
                                let repaired_bytes =
                                    encode_vec(&repaired_pdu).map_err(ConnectorError::encode)?;

                                eprintln!(
                                    "[portix_rdp] PDU repaired (channel_id={}, initiator_id={}), \
                                     injecting LicensingErrorMessage(StatusValidClient)",
                                    sdi_ctx.channel_id, sdi_ctx.initiator_id
                                );
                                repaired_bytes
                            }
                            Err(_) => {
                                eprintln!(
                                    "[portix_rdp] WARNING: Cannot decode as SendDataIndication, \
                                     passing original PDU to step()"
                                );
                                pdu.to_vec()
                            }
                        }
                    }
                } else {
                    // Not in licensing state — use original PDU.
                    pdu.to_vec()
                };

                // Call step() with the (possibly repaired) PDU.
                let written = connector.step(&input, &mut buf)?;

                if let Some(response_len) = written.size() {
                    framed.write_all(&buf[..response_len]).await.map_err(|e| {
                        ConnectorError::new("write all", ConnectorErrorKind::General).with_source(e)
                    })?;
                }

                // Check if connected.
                if let ClientConnectorState::Connected { result } = mem::take(&mut connector.state)
                {
                    return Ok(result);
                }
            } else {
                // No PDU expected — use step_no_input.
                let written = connector.step_no_input(&mut buf)?;

                if let Some(response_len) = written.size() {
                    framed.write_all(&buf[..response_len]).await.map_err(|e| {
                        ConnectorError::new("write all", ConnectorErrorKind::General).with_source(e)
                    })?;
                }

                // Check if connected.
                if let ClientConnectorState::Connected { result } = mem::take(&mut connector.state)
                {
                    return Ok(result);
                }
            }
        }
    }

    async fn try_connect(
        &self,
        enable_credssp: bool,
        license_cache: Option<Arc<dyn LicenseCache>>,
        license_bypass: bool,
        cancel_token: &CancellationToken,
    ) -> Result<(
        ironrdp_tokio::TokioFramed<ironrdp_tls::TlsStream<TcpStream>>,
        ironrdp_connector::ConnectionResult,
    )> {
        if cancel_token.is_cancelled() {
            return Err(RdpError::Cancelled);
        }

        println!(
            "[portix_rdp] try_connect host={} credssp={} redirect_drives={} license_cache={} license_bypass={}",
            self.profile.host,
            enable_credssp,
            self.profile.redirect_drives,
            if license_cache.is_some() {
                "enabled"
            } else {
                "disabled"
            },
            if license_bypass { "true" } else { "false" },
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

            license_cache,
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
                "[portix_rdp] attaching rdpdr channel (computer_name='{}', drive='{}')",
                computer_name, share_name
            );

            connector.attach_static_channel(rdpdr);

            connector.attach_static_channel(NoopRdpSnd::default());

            println!("[portix_rdp] attaching rdpsnd companion channel");
        }

        // Clipboard redirection
        if self.profile.redirect_clipboard {
            println!("[portix_rdp] attaching cliprdr channel (text clipboard sync)");
            connector.attach_static_channel(Cliprdr::new(Box::new(ClipboardBackend::new())));
        }

        let mut framed = TokioFramed::new(tcp);

        println!(
            "[portix_rdp] starting connect_begin (credssp={})",
            enable_credssp
        );
        let begin_result =
            timeout(CONNECT_TIMEOUT, connect_begin(&mut framed, &mut connector)).await;

        let should_upgrade = match begin_result {
            Ok(Ok(result)) => {
                println!("[portix_rdp] connect_begin completed");
                result
            }
            Ok(Err(e)) => {
                eprintln!("[portix_rdp] ERROR: connect_begin FAILED: {}", e);
                eprintln!(
                    "[portix_rdp] connection details: host={}, credssp={}, user={}",
                    self.profile.host, enable_credssp, self.profile.username
                );
                return Err(RdpError::NegotiationFailed(e.to_string()));
            }
            Err(_) => {
                eprintln!(
                    "[portix_rdp] ERROR: connect_begin TIMEOUT after {:?}",
                    CONNECT_TIMEOUT
                );
                return Err(RdpError::ConnectionTimeout);
            }
        };

        let (raw_stream, leftover) = framed.into_inner();

        println!(
            "[portix_rdp] starting TLS upgrade for host={}",
            self.profile.host
        );
        let tls_result = timeout(
            CONNECT_TIMEOUT,
            ironrdp_tls::upgrade(raw_stream, self.profile.host.as_str()),
        )
        .await;

        let (upgraded_stream, server_cert_der) = match tls_result {
            Ok(Ok(result)) => {
                println!("[portix_rdp] TLS upgrade SUCCESS");
                result
            }
            Ok(Err(e)) => {
                eprintln!("[portix_rdp] ERROR: TLS upgrade FAILED: {}", e);
                eprintln!("[portix_rdp] This usually indicates NLA/CredSSP authentication failure");
                return Err(RdpError::NegotiationFailed(e.to_string()));
            }
            Err(_) => {
                eprintln!(
                    "[portix_rdp] ERROR: TLS upgrade TIMEOUT after {:?}",
                    CONNECT_TIMEOUT
                );
                return Err(RdpError::ConnectionTimeout);
            }
        };

        let server_public_key =
            ironrdp_tls::extract_tls_server_public_key(&server_cert_der).unwrap_or_default();

        let mut tls_framed = TokioFramed::new_with_leftover(upgraded_stream, leftover);
        let upgraded = mark_as_upgraded(should_upgrade, &mut connector);

        println!("[portix_rdp] starting connect_finalize");
        let mut network_client = ReqwestNetworkClient::new();

        let finalize_result = if license_bypass && !enable_credssp {
            // Use custom connect_finalize with license PDU bypass for
            // servers (e.g. CyberArk PAS/PSM) that send malformed
            // ServerUpgradeLicense PDUs.
            timeout(
                CONNECT_TIMEOUT,
                Self::connect_finalize_with_license_bypass(connector, &mut tls_framed),
            )
            .await
        } else {
            timeout(
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
        };

        let connection_result = match finalize_result {
            Ok(Ok(result)) => {
                println!(
                    "[portix_rdp] connect_finalize SUCCESS, desktop={}x{}",
                    result.desktop_size.width, result.desktop_size.height
                );
                result
            }
            Ok(Err(e)) => {
                eprintln!("[portix_rdp] ERROR: connect_finalize FAILED: {}", e);

                // Provide targeted diagnostics for license-exchange decode errors,
                // which are common with CyberArk PAS/PSM gateways.
                if is_license_error(&e.to_string()) {
                    eprintln!(
                        "[portix_rdp] This is the 'privileged session could not be established securely' error from CyberArk"
                    );
                    eprintln!("[portix_rdp] License exchange decode error details:");
                    eprintln!(
                        "[portix_rdp]   - The server sent a PDU during license-exchange that could not be decoded."
                    );
                    eprintln!(
                        "[portix_rdp]   - This commonly happens with CyberArk PAS/PSM when the client requests"
                    );
                    eprintln!(
                        "[portix_rdp]     a new license (CLIENT_NEW_LICENSE_REQUEST) instead of reporting a cached one."
                    );
                    eprintln!(
                        "[portix_rdp]   - A retry with a stub license cache (CLIENT_LICENSE_INFO) will be attempted."
                    );
                    eprintln!("[portix_rdp] Root causes:");
                    eprintln!(
                        "[portix_rdp]   1. CredSSP not enabled (check enable_credssp parameter)"
                    );
                    eprintln!("[portix_rdp]   2. PAS/PSM configuration issue");
                    eprintln!("[portix_rdp]   3. Network/TLS handshake failure");
                } else {
                    eprintln!(
                        "[portix_rdp] This is the 'privileged session could not be established securely' error from CyberArk"
                    );
                    eprintln!("[portix_rdp] Root causes:");
                    eprintln!(
                        "[portix_rdp]   1. CredSSP not enabled (check enable_credssp parameter)"
                    );
                    eprintln!("[portix_rdp]   2. PAS/PSM configuration issue");
                    eprintln!("[portix_rdp]   3. Network/TLS handshake failure");
                }
                return Err(RdpError::NegotiationFailed(e.to_string()));
            }
            Err(_) => {
                eprintln!(
                    "[portix_rdp] ERROR: connect_finalize TIMEOUT after {:?}",
                    CONNECT_TIMEOUT
                );
                return Err(RdpError::ConnectionTimeout);
            }
        };

        println!("[portix_rdp] connection established");

        Ok((tls_framed, connection_result))
    }

    /// Performs a clipboard step. Clipboard failures are logged, never fatal
    /// to the session; only a broken connection is.
    async fn apply_clipboard_action<W: FramedWrite + Unpin>(
        &self,
        active_stage: &mut ActiveStage,
        framed: &mut W,
        local_clipboard: &mut Option<arboard::Clipboard>,
        action: ClipboardAction,
    ) -> Result<()> {
        let Some(cliprdr) = active_stage.get_svc_processor_mut::<CliprdrClient>() else {
            return Ok(());
        };
        let messages = match action {
            ClipboardAction::WriteLocal(text) => {
                if let Some(Err(e)) = local_clipboard.as_mut().map(|c| c.set_text(text)) {
                    eprintln!("[portix_rdp] cannot write local clipboard: {e}");
                }
                return Ok(());
            }
            ClipboardAction::Announce { has_text } => {
                let text = [ClipboardFormat::new(ClipboardFormatId::CF_UNICODETEXT)];
                cliprdr.initiate_copy(if has_text { &text } else { &[] })
            }
            ClipboardAction::RequestText => {
                cliprdr.initiate_paste(ClipboardFormatId::CF_UNICODETEXT)
            }
            ClipboardAction::SendText(text) => cliprdr.submit_format_data(match text {
                Some(text) => FormatDataResponse::new_unicode_string(&text),
                None => FormatDataResponse::new_error(),
            }),
        };
        let frame = match messages.map_err(|e| e.to_string()).and_then(|messages| {
            active_stage
                .process_svc_processor_messages(messages)
                .map_err(|e| e.to_string())
        }) {
            Ok(frame) => frame,
            Err(e) => {
                eprintln!("[portix_rdp] clipboard: {e}");
                return Ok(());
            }
        };
        framed.write_all(&frame).await.map_err(RdpError::Io)
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
    fn emit_full_frame(&self, image: &DecodedImage) {
        let width = image.width() as usize;
        let height = image.height() as usize;
        let bpp = image.bytes_per_pixel();

        if width == 0 || height == 0 || bpp != 4 {
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

        let _ = self.frame_tx.send(event);
    }
}
