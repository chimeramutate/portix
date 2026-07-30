/// MVP RDP client implementation - parsing and basic structure only.
///
/// This is a simplified implementation for the MVP phase that focuses on:
/// 1. Parsing .rdp files from CyberArk
/// 2. Providing the API surface for Flutter integration
/// 3. Placeholder for actual IronRDP connection (to be implemented post-MVP)
///
/// Full IronRDP integration with bitmap streaming will be added after the MVP
/// when the IronRDP API stabilizes.

use tokio::sync::{broadcast, mpsc};

use crate::domain::errors::{RdpError, Result};
use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use crate::domain::profile::RdpProfile;
use crate::domain::session::RdpConnectionStatus;

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
        Self {
            profile,
            session_id,
            frame_tx,
            status_tx,
            error_tx,
        }
    }

    pub async fn run(self, mut command_rx: mpsc::Receiver<RdpCommand>) -> Result<()> {
        println!(
            "[portix_rdp] RdpRuntime starting for session={} profile={} host={} port={}",
            self.session_id, self.profile.id, self.profile.host, self.profile.port,
        );
        // MVP: Emit "connecting" status
        self.emit_status(
            RdpConnectionStatus::Connecting,
            Some("Connecting to RDP server..."),
        );

        // Validate profile
        self.profile.validate()?;

        // MVP: For now, just emit "connected" status and wait for disconnect
        // Full IronRDP integration will be added post-MVP
        self.emit_status(
            RdpConnectionStatus::Connected,
            Some("Connected (MVP mode - full implementation pending)"),
        );

        // Wait for disconnect command
        loop {
            match command_rx.recv().await {
                Some(RdpCommand::Disconnect) | None => {
                    println!(
                        "[portix_rdp] session {} received disconnect", self.session_id,
                    );
                    self.emit_status(
                        RdpConnectionStatus::Disconnected,
                        Some("Disconnected by user"),
                    );
                    return Ok(());
                }
                Some(RdpCommand::MouseMove { x, y }) => {
                    println!(
                        "[portix_rdp] session {} received MouseMove x={} y={}",
                        self.session_id, x, y,
                    );
                }
                Some(RdpCommand::MouseButton { x, y, button, down }) => {
                    println!(
                        "[portix_rdp] session {} received MouseButton x={} y={} button={} down={}",
                        self.session_id, x, y, button, down,
                    );
                }
                Some(RdpCommand::KeyboardInput { scancode, down }) => {
                    println!(
                        "[portix_rdp] session {} received KeyboardInput scancode={} down={}",
                        self.session_id, scancode, down,
                    );
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
}
