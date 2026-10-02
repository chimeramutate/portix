//! Local port forwarding (`ssh -L`). Each tunnel owns a dedicated SSH
//! connection, so it keeps running when the terminal tab is closed.

use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;

use tokio::net::TcpListener;
use tokio::task::{AbortHandle, JoinSet};
use uuid::Uuid;

use crate::domain::errors::{PortixError, Result};
use crate::domain::profile::SshProfile;
use crate::infrastructure::ssh_client::connect_and_authenticate_profile;

/// An active `127.0.0.1:local_port -> remote_host:remote_port` tunnel.
#[derive(Clone, Debug)]
pub struct LocalForward {
    pub id: String,
    pub profile_id: String,
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
}

static ACTIVE: LazyLock<Mutex<HashMap<String, (LocalForward, AbortHandle)>>> =
    LazyLock::new(Default::default);

/// How often an idle tunnel checks that its SSH connection is still alive.
const LIVENESS_INTERVAL: Duration = Duration::from_secs(5);

/// Binds 127.0.0.1:`local_port` (0 = any free port), connects to `profile`,
/// and serves until [`stop_local_forward`] or the SSH connection drops.
/// Returns once the tunnel is ready, or the bind/connect error.
pub async fn start_local_forward(
    profile: SshProfile,
    local_port: u16,
    remote_host: String,
    remote_port: u16,
) -> Result<LocalForward> {
    // Bind first: a busy port should fail before spending an SSH handshake.
    let listener = TcpListener::bind(("127.0.0.1", local_port))
        .await
        .map_err(|e| PortixError::InvalidRequest(format!("cannot listen on port {local_port}: {e}")))?;
    let local_port = listener.local_addr()?.port();
    let handle = Arc::new(connect_and_authenticate_profile(&profile).await?);

    let forward = LocalForward {
        id: Uuid::new_v4().to_string(),
        profile_id: profile.id.clone(),
        local_port,
        remote_host: remote_host.clone(),
        remote_port,
    };
    let id = forward.id.clone();
    // Hold the lock across spawn so the task can't remove itself before it
    // is registered.
    let mut active = ACTIVE.lock().unwrap();
    let task = tokio::spawn(async move {
        // Dropping the set (when this task ends or is aborted) aborts every
        // open connection of the tunnel.
        let mut connections = JoinSet::new();
        let mut liveness = tokio::time::interval(LIVENESS_INTERVAL);
        loop {
            tokio::select! {
                accepted = listener.accept() => {
                    let Ok((mut socket, peer)) = accepted else { continue };
                    let handle = handle.clone();
                    let remote_host = remote_host.clone();
                    connections.spawn(async move {
                        let Ok(channel) = handle
                            .channel_open_direct_tcpip(
                                remote_host,
                                remote_port.into(),
                                peer.ip().to_string(),
                                peer.port().into(),
                            )
                            .await
                        else {
                            return;
                        };
                        let mut stream = channel.into_stream();
                        let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
                    });
                }
                _ = liveness.tick() => {
                    if handle.is_closed() { break; }
                }
                // Reap finished connections so the set doesn't grow forever.
                Some(_) = connections.join_next(), if !connections.is_empty() => {}
            }
        }
        ACTIVE.lock().unwrap().remove(&id);
    });
    active.insert(forward.id.clone(), (forward.clone(), task.abort_handle()));
    Ok(forward)
}

/// Stops a tunnel and closes its listener and connections. Unknown ids are
/// ignored (the tunnel may already have ended on its own).
pub fn stop_local_forward(id: &str) {
    if let Some((_, task)) = ACTIVE.lock().unwrap().remove(id) {
        task.abort();
    }
}

/// Tunnels that are still running.
pub fn active_local_forwards() -> Vec<LocalForward> {
    ACTIVE
        .lock()
        .unwrap()
        .values()
        .map(|(forward, _)| forward.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn profile() -> SshProfile {
        SshProfile {
            id: "p".into(),
            name: "p".into(),
            // Never reached: the bind must fail first.
            host: "203.0.113.1".into(),
            port: 22,
            username: "u".into(),
            password: Some("x".into()),
            private_key_path: None,
            key_passphrase: None,
            jump_host: None,
        }
    }

    #[tokio::test]
    async fn busy_local_port_fails_before_connecting() {
        let taken = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let port = taken.local_addr().unwrap().port();
        let err = start_local_forward(profile(), port, "db".into(), 5432)
            .await
            .unwrap_err();
        assert!(err.to_string().contains(&format!("port {port}")), "{err}");
        assert!(active_local_forwards().is_empty());
    }

    #[test]
    fn stopping_an_unknown_tunnel_is_a_no_op() {
        stop_local_forward("missing");
    }
}
