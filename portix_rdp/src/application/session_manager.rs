use std::collections::HashMap;
use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

use tokio::sync::{Mutex, broadcast, mpsc};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::domain::errors::{RdpError, Result};
use crate::domain::events::{RdpErrorEvent, RdpFrameEvent, RdpStatusEvent};
use crate::domain::profile::{RdpProfile, parse_rdp_file};
use crate::domain::session::{RdpConnectionStatus, RdpSessionInfo};
use crate::infrastructure::rdp_client::{RdpCommand, RdpRuntime};

struct SessionHandle {
    info: RdpSessionInfo,
    command_tx: mpsc::Sender<RdpCommand>,
    cancel_token: CancellationToken,
}

pub struct RdpSessionManager {
    sessions: Arc<Mutex<HashMap<String, SessionHandle>>>,

    profile_index: Arc<Mutex<HashMap<String, String>>>,

    frame_tx: broadcast::Sender<RdpFrameEvent>,
    status_tx: broadcast::Sender<RdpStatusEvent>,
    error_tx: broadcast::Sender<RdpErrorEvent>,

    global_cancel: CancellationToken,

    /// Counter global untuk frame.
    ///
    /// Setiap frame baru mendapatkan ID unik.
    next_frame_id: Arc<AtomicU64>,
}

impl RdpSessionManager {
    pub fn new() -> Self {
        // Frame channel: buffer besar agar burst dirty rect di awal koneksi
        // tidak ter-drop saat Dart subscriber belum ready.
        // xRDP login screen bisa mengirim 20+ dirty rect sekaligus.
        let (frame_tx, _) = broadcast::channel(8192);
        let (status_tx, _) = broadcast::channel(256);
        let (error_tx, _) = broadcast::channel(128);

        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            profile_index: Arc::new(Mutex::new(HashMap::new())),

            frame_tx,
            status_tx,
            error_tx,

            global_cancel: CancellationToken::new(),

            next_frame_id: Arc::new(AtomicU64::new(0)),
        }
    }

    /// Mendapatkan ID frame baru.
    ///
    /// ID dimulai dari 1.
    pub fn next_frame_id(&self) -> u64 {
        self.next_frame_id.fetch_add(1, Ordering::SeqCst) + 1
    }

    pub async fn parse_rdp_file_content(
        &self,
        rdp_content: String,
        profile_name: Option<String>,
    ) -> Result<RdpSessionInfo> {
        let profile_id = Uuid::new_v4().to_string();
        let session_id = profile_id.clone();

        let _profile = parse_rdp_file(&rdp_content, &profile_id, profile_name.as_deref())?;

        Ok(RdpSessionInfo {
            id: session_id,
            profile_id,
            status: RdpConnectionStatus::Disconnected,
        })
    }

    pub async fn get_active_session_for_profile(&self, profile_id: &str) -> Option<String> {
        let index = self.profile_index.lock().await;

        index.get(profile_id).cloned()
    }

    pub async fn is_session_active(&self, session_id: &str) -> bool {
        let sessions = self.sessions.lock().await;

        sessions.contains_key(session_id)
    }

    pub async fn connect(&self, profile: RdpProfile) -> Result<RdpSessionInfo> {
        profile.validate()?;

        let profile_id = profile.id.clone();

        // ==========================================================
        // CHECK EXISTING SESSION
        // ==========================================================

        {
            let profile_index = self.profile_index.lock().await;

            if let Some(existing_session_id) = profile_index.get(&profile_id) {
                let existing_id = existing_session_id.clone();

                drop(profile_index);

                let sessions = self.sessions.lock().await;

                if let Some(handle) = sessions.get(&existing_id) {
                    println!(
                        "[portix_rdp] profile {} already has active session {}, returning existing",
                        profile_id, existing_id
                    );

                    return Ok(handle.info.clone());
                }
            }
        }

        // ==========================================================
        // CREATE SESSION
        // ==========================================================

        let session_id = Uuid::new_v4().to_string();

        let (command_tx, command_rx) = mpsc::channel::<RdpCommand>(32);

        let cancel_token = CancellationToken::new();

        let info = RdpSessionInfo {
            id: session_id.clone(),
            profile_id: profile_id.clone(),
            status: RdpConnectionStatus::Connecting,
        };

        println!(
            "[portix_rdp] creating runtime session={} profile={}",
            session_id, profile_id
        );

        // ==========================================================
        // IMPORTANT
        //
        // Jangan memberikan "frame id" yang sama untuk seluruh
        // lifetime runtime.
        //
        // Runtime harus meminta ID baru setiap kali menghasilkan
        // frame.
        // ==========================================================

        let runtime = RdpRuntime::new(
            profile,
            session_id.clone(),
            self.frame_tx.clone(),
            self.status_tx.clone(),
            self.error_tx.clone(),
            Arc::clone(&self.next_frame_id),
        );

        // ==========================================================
        // CLONES FOR TASK
        // ==========================================================

        let sessions = Arc::clone(&self.sessions);

        let profile_index = Arc::clone(&self.profile_index);

        let session_id_task = session_id.clone();

        let profile_id_task = profile_id.clone();

        let status_tx = self.status_tx.clone();

        let error_tx = self.error_tx.clone();

        let child_cancel = cancel_token.clone();

        let global_cancel = self.global_cancel.clone();

        println!(
            "[portix_rdp] spawning runtime for session {} profile={}",
            session_id, profile_id,
        );

        // ==========================================================
        // RUNTIME TASK
        // ==========================================================

        tokio::spawn(async move {
            let result = tokio::select! {
                result = runtime.run(
                    command_rx,
                    child_cancel.clone(),
                ) => result,

                _ = child_cancel.cancelled() => {
                    println!(
                        "[portix_rdp] session {} cancelled via token",
                        session_id_task
                    );

                    Ok(())
                }

                _ = global_cancel.cancelled() => {
                    println!(
                        "[portix_rdp] session {} cancelled via global shutdown",
                        session_id_task
                    );

                    Ok(())
                }
            };

            // ======================================================
            // RUNTIME RESULT
            // ======================================================

            match result {
                Ok(()) => {
                    println!(
                        "[portix_rdp] runtime finished normally: {}",
                        session_id_task
                    );

                    let _ = status_tx.send(RdpStatusEvent {
                        session_id: session_id_task.clone(),

                        status: RdpConnectionStatus::Disconnected,

                        message: Some("disconnected normally".to_owned()),
                    });
                }

                Err(e) => {
                    println!(
                        "[portix_rdp] runtime error session={}: {}",
                        session_id_task, e
                    );

                    let _ = error_tx.send(RdpErrorEvent {
                        session_id: Some(session_id_task.clone()),

                        message: e.to_string(),

                        code: "UNKNOWN".to_owned(),
                    });

                    let _ = status_tx.send(RdpStatusEvent {
                        session_id: session_id_task.clone(),

                        status: RdpConnectionStatus::Error,

                        message: Some(e.to_string()),
                    });
                }
            }

            // ======================================================
            // CLEANUP
            // ======================================================

            sessions.lock().await.remove(&session_id_task);

            profile_index.lock().await.remove(&profile_id_task);

            println!(
                "[portix_rdp] cleaned up session {} profile {}",
                session_id_task, profile_id_task
            );
        });

        // ==========================================================
        // REGISTER SESSION
        // ==========================================================

        self.sessions.lock().await.insert(
            session_id.clone(),
            SessionHandle {
                info: info.clone(),
                command_tx,
                cancel_token,
            },
        );

        self.profile_index
            .lock()
            .await
            .insert(profile_id, session_id.clone());

        Ok(info)
    }

    // ==============================================================
    // DISCONNECT
    // ==============================================================

    pub async fn disconnect(&self, session_id: String) -> Result<()> {
        let handle = {
            let mut sessions = self.sessions.lock().await;

            sessions.remove(&session_id)
        };

        if let Some(handle) = handle {
            handle.cancel_token.cancel();

            let _ = handle.command_tx.send(RdpCommand::Disconnect).await;

            self.profile_index
                .lock()
                .await
                .remove(&handle.info.profile_id);

            println!(
                "[portix_rdp] disconnect requested for session {}",
                session_id
            );
        } else {
            println!(
                "[portix_rdp] session {} not found for disconnect (may already be disconnected)",
                session_id
            );
        }

        Ok(())
    }

    // ==============================================================
    // DISCONNECT ALL
    // ==============================================================

    pub async fn disconnect_all(&self) {
        let handles: Vec<(String, SessionHandle)> = {
            let mut sessions = self.sessions.lock().await;

            sessions.drain().collect()
        };

        for (session_id, handle) in handles {
            handle.cancel_token.cancel();

            let _ = handle.command_tx.send(RdpCommand::Disconnect).await;

            println!("[portix_rdp] disconnect all: session {}", session_id);
        }

        self.profile_index.lock().await.clear();
    }

    // ==============================================================
    // MOUSE MOVE
    // ==============================================================

    pub async fn send_mouse_move(&self, session_id: String, x: u16, y: u16) -> Result<()> {
        let sessions = self.sessions.lock().await;

        if let Some(handle) = sessions.get(&session_id) {
            handle
                .command_tx
                .send(RdpCommand::MouseMove { x, y })
                .await
                .map_err(|_| RdpError::Disconnected)?;
        }

        Ok(())
    }

    // ==============================================================
    // MOUSE BUTTON
    // ==============================================================

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
        }

        Ok(())
    }

    // ==============================================================
    // MOUSE WHEEL
    // ==============================================================

    pub async fn send_mouse_wheel(
        &self,
        session_id: String,
        x: u16,
        y: u16,
        delta: i16,
        is_vertical: bool,
    ) -> Result<()> {
        let sessions = self.sessions.lock().await;

        if let Some(handle) = sessions.get(&session_id) {
            handle
                .command_tx
                .send(RdpCommand::MouseWheel {
                    x,
                    y,
                    delta,
                    is_vertical,
                })
                .await
                .map_err(|_| RdpError::Disconnected)?;
        }

        Ok(())
    }

    // ==============================================================
    // KEYBOARD
    // ==============================================================

    pub async fn send_keyboard_input(
        &self,
        session_id: String,
        hid_usage: u16,
        down: bool,
    ) -> Result<()> {
        let sessions = self.sessions.lock().await;

        if let Some(handle) = sessions.get(&session_id) {
            handle
                .command_tx
                .send(RdpCommand::KeyboardInput { hid_usage, down })
                .await
                .map_err(|_| RdpError::Disconnected)?;
        }

        Ok(())
    }

    // ==============================================================
    // FRAME STREAM
    // ==============================================================

    pub fn frame_stream(&self) -> broadcast::Receiver<RdpFrameEvent> {
        self.frame_tx.subscribe()
    }

    // ==============================================================
    // STATUS STREAM
    // ==============================================================

    pub fn status_stream(&self) -> broadcast::Receiver<RdpStatusEvent> {
        self.status_tx.subscribe()
    }

    // ==============================================================
    // ERROR STREAM
    // ==============================================================

    pub fn error_stream(&self) -> broadcast::Receiver<RdpErrorEvent> {
        self.error_tx.subscribe()
    }

    // ==============================================================
    // ERROR STREAM SENDER
    // ==============================================================

    pub fn error_stream_sender(&self) -> broadcast::Sender<RdpErrorEvent> {
        self.error_tx.clone()
    }
}

impl Drop for RdpSessionManager {
    fn drop(&mut self) {
        println!("[portix_rdp] RdpSessionManager dropped, cancelling all sessions");

        self.global_cancel.cancel();
    }
}

impl Default for RdpSessionManager {
    fn default() -> Self {
        Self::new()
    }
}
