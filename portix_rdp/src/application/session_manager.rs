/// Application-layer RDP session manager.
///
/// Manages active RDP sessions, coordinates with the infrastructure layer,
/// and provides the operations called by the Flutter bridge.
use std::collections::HashMap;
use std::sync::Arc;

use tokio::sync::{broadcast, mpsc, Mutex};
use uuid::Uuid;

use crate::domain::errors::{RdpError, Result};
use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use crate::domain::profile::{parse_rdp_file, RdpProfile};
use crate::domain::session::{RdpConnectionStatus, RdpSessionInfo};
use crate::infrastructure::rdp_client_mvp::{RdpCommand, RdpRuntime};

struct SessionHandle {
    info: RdpSessionInfo,
    command_tx: mpsc::Sender<RdpCommand>,
}

pub struct RdpSessionManager {
    sessions: Arc<Mutex<HashMap<String, SessionHandle>>>,
    frame_tx: broadcast::Sender<RdpFrameEvent>,
    status_tx: broadcast::Sender<RdpStatusEvent>,
    error_tx: broadcast::Sender<RdpErrorEvent>,
}

impl RdpSessionManager {
    pub fn new() -> Self {
        let (frame_tx, _) = broadcast::channel(128);
        let (status_tx, _) = broadcast::channel(64);
        let (error_tx, _) = broadcast::channel(64);

        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            frame_tx,
            status_tx,
            error_tx,
        }
    }

    /// Parse a .rdp file content and return session info (profile not yet connected).
    pub async fn parse_rdp_file_content(
        &self,
        rdp_content: String,
        profile_name: Option<String>,
    ) -> Result<RdpSessionInfo> {
        let profile_id = Uuid::new_v4().to_string();
        let session_id = profile_id.clone();
        
        let _profile = parse_rdp_file(
            &rdp_content,
            &profile_id,
            profile_name.as_deref(),
        )?;

        // Return session info with "disconnected" status
        // Flutter can display profile details before user clicks Connect
        Ok(RdpSessionInfo {
            id: session_id,
            profile_id,
            status: RdpConnectionStatus::Disconnected,
        })
    }

    /// Connect to RDP using a profile, spawn runtime, and return session info.
    pub async fn connect(&self, profile: RdpProfile) -> Result<RdpSessionInfo> {
        profile.validate()?;

        let session_id = Uuid::new_v4().to_string();
        let (command_tx, command_rx) = mpsc::channel::<RdpCommand>(32);

        let info = RdpSessionInfo {
            id: session_id.clone(),
            profile_id: profile.id.clone(),
            status: RdpConnectionStatus::Connecting,
        };

        // Spawn the RDP runtime task
        let runtime = RdpRuntime::new(
            profile,
            session_id.clone(),
            self.frame_tx.clone(),
            self.status_tx.clone(),
            self.error_tx.clone(),
        );

        let sessions = Arc::clone(&self.sessions);
        let session_id_task = session_id.clone();
        let status_tx = self.status_tx.clone();
        let error_tx = self.error_tx.clone();

        tokio::spawn(async move {
            let result = runtime.run(command_rx).await;

            // Emit final status event
            match result {
                Ok(()) => {
                    let _ = status_tx.send(RdpStatusEvent {
                        session_id: session_id_task.clone(),
                        status: RdpConnectionStatus::Disconnected,
                        message: Some("disconnected normally".to_owned()),
                    });
                }
                Err(e) => {
                    let _ = error_tx.send(RdpErrorEvent {
                        session_id: Some(session_id_task.clone()),
                        message: e.to_string(),
                    });
                    let _ = status_tx.send(RdpStatusEvent {
                        session_id: session_id_task.clone(),
                        status: RdpConnectionStatus::Error,
                        message: Some(e.to_string()),
                    });
                }
            }

            // Remove session from the map
            sessions.lock().await.remove(&session_id_task);
        });

        // Store session handle
        self.sessions.lock().await.insert(
            session_id.clone(),
            SessionHandle {
                info: info.clone(),
                command_tx,
            },
        );

        Ok(info)
    }

    /// Disconnect a session by id.
    pub async fn disconnect(&self, session_id: String) -> Result<()> {
        let mut sessions = self.sessions.lock().await;
        
        if let Some(handle) = sessions.remove(&session_id) {
            let _ = handle.command_tx.send(RdpCommand::Disconnect).await;
            Ok(())
        } else {
            Err(RdpError::SessionNotFound(session_id))
        }
    }

    /// Send mouse move input to a session.
    pub async fn send_mouse_move(&self, session_id: String, x: u16, y: u16) -> Result<()> {
        let sessions = self.sessions.lock().await;
        if let Some(handle) = sessions.get(&session_id) {
            handle
                .command_tx
                .send(RdpCommand::MouseMove { x, y })
                .await
                .map_err(|_| RdpError::Disconnected)?;
            Ok(())
        } else {
            Err(RdpError::SessionNotFound(session_id))
        }
    }

    /// Send mouse button input to a session.
    pub async fn send_mouse_button(
        &self,
        session_id: String,
        x: u16,
        y: u16,
        button: u8,
        down: bool,
    ) -> Result<()> {
        let sessions = self.sessions.lock().await;
        if let Some(handle) = sessions.get(&session_id) {
            handle
                .command_tx
                .send(RdpCommand::MouseButton { x, y, button, down })
                .await
                .map_err(|_| RdpError::Disconnected)?;
            Ok(())
        } else {
            Err(RdpError::SessionNotFound(session_id))
        }
    }

    /// Send keyboard input to a session.
    pub async fn send_keyboard_input(
        &self,
        session_id: String,
        scancode: u16,
        down: bool,
    ) -> Result<()> {
        let sessions = self.sessions.lock().await;
        if let Some(handle) = sessions.get(&session_id) {
            handle
                .command_tx
                .send(RdpCommand::KeyboardInput { scancode, down })
                .await
                .map_err(|_| RdpError::Disconnected)?;
            Ok(())
        } else {
            Err(RdpError::SessionNotFound(session_id))
        }
    }

    // ── Event streams ───────────────────────────────────────────────────────

    pub fn frame_stream(&self) -> broadcast::Receiver<RdpFrameEvent> {
        self.frame_tx.subscribe()
    }

    pub fn status_stream(&self) -> broadcast::Receiver<RdpStatusEvent> {
        self.status_tx.subscribe()
    }

    pub fn error_stream(&self) -> broadcast::Receiver<RdpErrorEvent> {
        self.error_tx.subscribe()
    }
}

impl Default for RdpSessionManager {
    fn default() -> Self {
        Self::new()
    }
}
