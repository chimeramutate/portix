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
            client_build: 7601, 
            client_name: "Portix-Universal".to_owned(),
            keyboard_type: ironrdp_pdu::gcc::KeyboardType::IbmEnhanced,
            keyboard_subtype: 0,
            keyboard_functional_keys_count: 12,
            keyboard_layout: 0x0409, 
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
        let image_width = image.width() as usize;
        let image_height = image.height() as usize;

        if image_width == 0 || image_height == 0 {
            eprintln!("[emit_frame] skip: empty image");
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

        if right < left || bottom < top {
            return;
        }

        let width = right - left + 1;
        let height = bottom - top + 1;

        
        
        
        let bpp = image.bytes_per_pixel();
        let source = image.data();
        let source_stride = image_width * bpp;
    

        
        
        
        static IRONRDP_BUF_LOGGED: std::sync::Once = std::sync::Once::new();
        IRONRDP_BUF_LOGGED.call_once(|| {
            eprintln!(
                "[IRONRDP BUF] w={} h={} bpp={} \
                reported_stride={} calc_stride={} \
                actual_buf_len={} expected_tight_len={}",
                image_width, 
                image_height, 
                bpp, 
                image.stride(), 
                source_stride, 
                source.len(), 
                source_stride * image_height
            );
        });
        
        if bpp != 4 {
            eprintln!("[emit_frame] unsupported pixel format: bpp={} expected=4", bpp);
            return;
        }

        
        
        
        
        let source_stride = image_width * bpp;

        
        let reported_stride = image.stride();
        if reported_stride != source_stride {
            static mut STRIDE_WARNED: bool = false;
            unsafe {
                if !STRIDE_WARNED {
                    eprintln!(
                        "[emit_frame] STRIDE MISMATCH: reported={} calculated={} \
                        Using calculated stride to fix tilted rendering",
                        reported_stride, source_stride
                    );
                    STRIDE_WARNED = true;
                }
            }
        }

        let expected_source_len = source_stride * image_height;

        if source.len() < expected_source_len {
            eprintln!(
                "[emit_frame] invalid framebuffer: len={} expected_at_least={} stride={} height={}",
                source.len(), expected_source_len, source_stride, image_height
            );
            return;
        }

        
        
        
        let target_stride = width * 4;
        let target_len = target_stride * height;
        let mut packed = vec![0u8; target_len];
            
    
    
        if width >= 10 && height >= 2 {
            let y0_offset = top * source_stride + left * bpp;
            let y1_offset = (top + 1) * source_stride + left * bpp;
            
            let pattern_len = 40; 
            
            if y0_offset + pattern_len <= source.len() && y1_offset + source_stride + 100 <= source.len() {
                let pattern = &source[y0_offset..y0_offset + pattern_len];
                let mut found_offset: Option<usize> = None;
                
                
                for i in y1_offset..(y1_offset + source_stride + 100).min(source.len() - pattern_len) {
                    if &source[i..i + pattern_len] == pattern {
                        found_offset = Some(i);
                        break;
                    }
                }
                
                if let Some(offset) = found_offset {
                    let actual_dist = offset - y0_offset;
                    let delta = actual_dist as i64 - source_stride as i64;
                    if delta != 0 {
                        eprintln!("[STRIDE HUNTER] ⚠️ BINGO! Ada padding tersembunyi! Expected stride={}, Actual={}, Delta={} bytes ({} pixel)", 
                            source_stride, actual_dist, delta, delta / 4);
                    } else {
                        eprintln!("[STRIDE HUNTER] Stride sesungguhnya memang 100% rapat ({}). Bug BUKAN di stride.", source_stride);
                    }
                } else {
                    eprintln!("[STRIDE HUNTER] Pola baris tidak ditemukan di baris berikutnya. Data mungkin dienkripsi/dikompresi berbeda.");
                }
            }
        }    
        for row in 0..height {
            let y = top + row;

            
            let source_offset = y * source_stride + left * bpp;
            let source_end = source_offset + target_stride;

            
            let target_offset = row * target_stride;
            let target_end = target_offset + target_stride;

            if source_end > source.len() {
                eprintln!(
                    "[emit_frame] source OOB: row={} source={}..{} len={}",
                    y, source_offset, source_end, source.len()
                );
                return;
            }

            if target_end > packed.len() {
                eprintln!(
                    "[emit_frame] target OOB: row={} target={}..{} len={}",
                    row, target_offset, target_end, packed.len()
                );
                return;
            }

            packed[target_offset..target_end]
                .copy_from_slice(&source[source_offset..source_end]);
        }

        
        
        
        for pixel in packed.chunks_exact_mut(4) {
            pixel[3] = 0xFF;
        }

        
        
        
        let frame_id = self.next_frame_id();

        let event = RdpFrameEvent {
            session_id: self.session_id.clone(),
            data: packed,
            width: width as u32,
            height: height as u32,
            x: left as u32,
            y: top as u32,
            frame_id,
        };
            
    
    
    
    
    if frame_id >= 35 && frame_id <= 42 {
        static DUMPED: std::sync::Once = std::sync::Once::new();
        DUMPED.call_once(|| {
            use std::io::Write;
            if let Ok(mut f) = std::fs::File::create("/tmp/ironrdp_dump.ppm") {
                
                let _ = write!(f, "P6\n{} {}\n255\n", image_width, image_height);
                
                for i in (0..source.len()).step_by(4) {
                    let _ = f.write_all(&[source[i], source[i+1], source[i+2]]);
                }
                eprintln!("[DUMP] ✅ Framebuffer IronRDP berhasil disimpan ke: /tmp/ironrdp_dump.ppm");
                eprintln!("[DUMP] Buka file tersebut dengan aplikasi Gambar (Image Viewer) di Linuxmu.");
            }
        });
    }
    

    
    
    
        
        if width > 50 || height > 50 {
            println!(
                "[FRAME] id={} pos=({},{}) rect={}x{} bytes={}",
                frame_id, left, top, width, height, event.data.len()
            );
        }

        if let Err(e) = self.frame_tx.send(event) {
            eprintln!("[emit_frame] ERROR: failed to send frame {}: {}", frame_id, e);
        }
    }
}
