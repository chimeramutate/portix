use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::broadcast;

use crate::application::session_manager::SessionManager;
use crate::domain::profile::SshProfile;
use crate::domain::session::{RemoteSystemSnapshot, SessionInfo};
use crate::frb_generated::StreamSink;
use crate::infrastructure::{host_keys, port_forward, ssh_client};

static SESSION_MANAGER: Lazy<SessionManager> = Lazy::new(SessionManager::new);

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub async fn connect(profile: SshProfile, cols: u32, rows: u32) -> anyhow::Result<SessionInfo> {
    Ok(SESSION_MANAGER.connect(profile, cols, rows).await?)
}

pub async fn disconnect(session_id: String) -> anyhow::Result<()> {
    Ok(SESSION_MANAGER.disconnect(session_id).await?)
}

pub async fn send_terminal_input(session_id: String, data: Vec<u8>) -> anyhow::Result<()> {
    Ok(SESSION_MANAGER
        .send_terminal_input(session_id, data)
        .await?)
}

pub async fn resize_terminal(session_id: String, cols: u32, rows: u32) -> anyhow::Result<()> {
    Ok(SESSION_MANAGER
        .resize_terminal(session_id, cols, rows)
        .await?)
}

pub async fn remote_system_snapshot(session_id: String) -> anyhow::Result<RemoteSystemSnapshot> {
    Ok(SESSION_MANAGER.remote_system_snapshot(session_id).await?)
}

/// Generates an unencrypted ed25519 keypair: the private key at `path` (0600
/// on unix) and the public key at `path.pub`. Refuses to overwrite either
/// file. Returns the OpenSSH public key line (for `authorized_keys`).
///
/// A non-empty `passphrase` encrypts the private key (the connect path asks
/// for it when needed).
pub fn generate_ed25519_key(
    path: String,
    comment: String,
    passphrase: Option<String>,
) -> anyhow::Result<String> {
    use russh::keys::ssh_key::{Algorithm, LineEnding, PrivateKey};

    let private_path = std::path::PathBuf::from(&path);
    let public_path = std::path::PathBuf::from(format!("{path}.pub"));
    for existing in [&private_path, &public_path] {
        if existing.exists() {
            anyhow::bail!("{} already exists", existing.display());
        }
    }
    if let Some(parent) = private_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519)?;
    key.set_comment(comment);
    if let Some(passphrase) = passphrase.filter(|p| !p.is_empty()) {
        key = key.encrypt(&mut rand::rng(), passphrase)?;
    }
    key.write_openssh_file(&private_path, LineEnding::LF)?;
    let public_key = key.public_key().to_openssh()?;
    std::fs::write(&public_path, format!("{public_key}\n"))?;
    Ok(public_key)
}

/// A server host key that was refused: unknown (`changed_line` is None) or
/// different from the key recorded on `changed_line` of known_hosts.
pub struct HostKeyInfo {
    pub algorithm: String,
    pub fingerprint: String,
    pub changed_line: Option<u32>,
}

/// The host key refused during the last connect to `host:port`, so the UI can
/// ask the user to confirm it (unknown host) or explain the risk (changed key).
pub fn pending_host_key(host: String, port: u16) -> Option<HostKeyInfo> {
    host_keys::pending_host_key(&host, port).map(|pending| HostKeyInfo {
        algorithm: pending.algorithm,
        fingerprint: pending.fingerprint,
        changed_line: pending.changed_line.map(|line| line as u32),
    })
}

/// Records the refused key of an unknown host in ~/.ssh/known_hosts after the
/// user confirmed `fingerprint`. Fails for a changed key or a stale fingerprint.
pub fn trust_host_key(host: String, port: u16, fingerprint: String) -> anyhow::Result<()> {
    let path = host_keys::default_known_hosts_path(ssh_client::home_dir())?;
    Ok(host_keys::trust_pending_host_key(
        &host,
        port,
        &fingerprint,
        &path,
    )?)
}

/// An active tunnel on 127.0.0.1:`local_port`: a local forward
/// (`ssh -L local_port:remote_host:remote_port`), or a SOCKS5 proxy
/// (`ssh -D local_port`) when `socks` is set. When `reverse` is set it is a
/// remote forward (`ssh -R remote_port:remote_host:local_port`): the server
/// listens on its localhost:`remote_port` and connections come back to
/// `remote_host:local_port` from this machine.
pub struct ForwardInfo {
    pub id: String,
    pub profile_id: String,
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
    pub socks: bool,
    pub reverse: bool,
}

impl From<port_forward::LocalForward> for ForwardInfo {
    fn from(forward: port_forward::LocalForward) -> Self {
        Self {
            id: forward.id,
            profile_id: forward.profile_id,
            local_port: forward.local_port,
            remote_host: forward.remote_host,
            remote_port: forward.remote_port,
            socks: forward.socks,
            reverse: forward.reverse,
        }
    }
}

/// Starts forwarding 127.0.0.1:`local_port` (0 = any free port) to
/// `remote_host:remote_port` as seen from the SSH server, over a dedicated
/// connection. Returns once listening and connected.
pub async fn start_local_forward(
    profile: SshProfile,
    local_port: u16,
    remote_host: String,
    remote_port: u16,
) -> anyhow::Result<ForwardInfo> {
    profile.validate()?;
    Ok(
        port_forward::start_local_forward(profile, local_port, remote_host, remote_port)
            .await?
            .into(),
    )
}

/// Starts a SOCKS5 proxy on 127.0.0.1:`local_port` (0 = any free port):
/// connections go wherever each client asks, from the SSH server.
pub async fn start_socks_proxy(profile: SshProfile, local_port: u16) -> anyhow::Result<ForwardInfo> {
    profile.validate()?;
    Ok(port_forward::start_socks_proxy(profile, local_port).await?.into())
}

/// Starts a remote forward: the SSH server listens on its
/// localhost:`remote_port` (0 = a port it picks) and connections come back
/// to `local_host:local_port` from this machine. Returns once listening.
pub async fn start_remote_forward(
    profile: SshProfile,
    remote_port: u16,
    local_host: String,
    local_port: u16,
) -> anyhow::Result<ForwardInfo> {
    profile.validate()?;
    Ok(
        port_forward::start_remote_forward(profile, remote_port, local_host, local_port)
            .await?
            .into(),
    )
}

pub fn stop_local_forward(id: String) {
    port_forward::stop_local_forward(&id);
}

/// Tunnels still running (one ends on its own when its SSH connection drops).
pub fn list_local_forwards() -> Vec<ForwardInfo> {
    port_forward::active_local_forwards()
        .into_iter()
        .map(Into::into)
        .collect()
}

pub async fn terminal_output_stream(sink: StreamSink<String>) -> anyhow::Result<()> {
    let mut rx = SESSION_MANAGER.terminal_output_stream();
    tokio::spawn(async move {
        forward_json_stream(&mut rx, sink).await;
    });
    Ok(())
}

pub async fn connection_status_stream(sink: StreamSink<String>) -> anyhow::Result<()> {
    let mut rx = SESSION_MANAGER.connection_status_stream();
    tokio::spawn(async move {
        forward_json_stream(&mut rx, sink).await;
    });
    Ok(())
}

pub async fn error_event_stream(sink: StreamSink<String>) -> anyhow::Result<()> {
    let mut rx = SESSION_MANAGER.error_event_stream();
    tokio::spawn(async move {
        forward_json_stream(&mut rx, sink).await;
    });
    Ok(())
}

async fn forward_json_stream<T>(rx: &mut broadcast::Receiver<T>, sink: StreamSink<String>)
where
    T: Clone + Serialize,
{
    loop {
        match rx.recv().await {
            Ok(event) => {
                let Ok(json) = serde_json::to_string(&event) else {
                    continue;
                };
                if sink.add(json).is_err() {
                    break;
                }
            }
            Err(broadcast::error::RecvError::Lagged(_)) => continue,
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_ed25519_key_writes_loadable_pair_and_refuses_overwrite() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("id_test").to_string_lossy().into_owned();

        let public_key = generate_ed25519_key(path.clone(), "me@portix".into(), None).unwrap();
        assert!(public_key.starts_with("ssh-ed25519 "));
        assert!(public_key.ends_with(" me@portix"));
        assert!(russh::keys::load_secret_key(&path, None).is_ok());
        assert_eq!(
            std::fs::read_to_string(format!("{path}.pub"))
                .unwrap()
                .trim(),
            public_key
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&path).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }

        assert!(generate_ed25519_key(path, String::new(), None).is_err());
    }

    #[test]
    fn generate_ed25519_key_with_passphrase_needs_it_to_load() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("id_enc").to_string_lossy().into_owned();
        generate_ed25519_key(path.clone(), String::new(), Some("s3cret".into())).unwrap();

        assert!(matches!(
            russh::keys::load_secret_key(&path, None),
            Err(russh::keys::Error::KeyIsEncrypted)
        ));
        assert!(russh::keys::load_secret_key(&path, Some("s3cret")).is_ok());
    }
}
