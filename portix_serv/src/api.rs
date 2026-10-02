use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::broadcast;

use crate::application::autocomplete_service::AutocompleteService;
use crate::application::session_manager::SessionManager;
use crate::domain::autocomplete::TerminalCompleteRequest;
use crate::domain::errors::PortixError;
use crate::domain::profile::SshProfile;
use crate::domain::session::{RemoteFileEntry, RemoteSystemSnapshot, SessionInfo};
use crate::infrastructure::{host_keys, port_forward, ssh_client};
use crate::frb_generated::StreamSink;

static SESSION_MANAGER: Lazy<SessionManager> = Lazy::new(SessionManager::new);
static AUTOCOMPLETE_SERVICE: Lazy<AutocompleteService> = Lazy::new(AutocompleteService::new);

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

pub async fn command_help_suggestions(
    session_id: String,
    input: String,
) -> anyhow::Result<Vec<String>> {
    Ok(SESSION_MANAGER
        .command_help_suggestions(session_id, input)
        .await?)
}

pub async fn terminal_complete(req_json: String) -> anyhow::Result<String> {
    let request = serde_json::from_str::<TerminalCompleteRequest>(&req_json)
        .map_err(|error| PortixError::InvalidRequest(error.to_string()))?;
    if request.session_id.is_some() {
        let mut response = SESSION_MANAGER.terminal_complete(request.clone()).await?;
        // Always merge local static completions (options, paths, etc.)
        let local = AUTOCOMPLETE_SERVICE.complete(request).await?;
        if response.suggestion.is_none() {
            response.suggestion = local.suggestion;
        }
        // Merge: local static options first (more concise descriptions),
        // then remote completions fill remaining slots.
        let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
        let mut merged = Vec::new();
        for item in local.items {
            if merged.len() >= 24 {
                break;
            }
            if seen.insert(item.insert_text.clone()) {
                merged.push(item);
            }
        }
        for item in response.items {
            if merged.len() >= 24 {
                break;
            }
            if seen.insert(item.insert_text.clone()) {
                merged.push(item);
            }
        }
        response.items = merged;
        return Ok(serde_json::to_string(&response)?);
    }
    Ok(AUTOCOMPLETE_SERVICE
        .complete(request)
        .await
        .and_then(|response| {
            serde_json::to_string(&response)
                .map_err(|error| PortixError::InvalidRequest(error.to_string()))
        })?)
}

pub async fn list_remote_directory(
    session_id: String,
    path: String,
) -> anyhow::Result<Vec<RemoteFileEntry>> {
    Ok(SESSION_MANAGER
        .list_remote_directory(session_id, path)
        .await?)
}

pub async fn resolve_remote_directory(session_id: String, path: String) -> anyhow::Result<String> {
    Ok(SESSION_MANAGER
        .resolve_remote_directory(session_id, path)
        .await?)
}

pub async fn read_remote_file(session_id: String, path: String) -> anyhow::Result<String> {
    Ok(SESSION_MANAGER.read_remote_file(session_id, path).await?)
}

pub async fn read_remote_file_bytes(session_id: String, path: String) -> anyhow::Result<Vec<u8>> {
    Ok(SESSION_MANAGER
        .read_remote_file_bytes(session_id, path)
        .await?)
}

pub async fn write_remote_file(
    session_id: String,
    path: String,
    content: String,
) -> anyhow::Result<()> {
    Ok(SESSION_MANAGER
        .write_remote_file(session_id, path, content)
        .await?)
}

pub async fn upload_remote_file(
    session_id: String,
    path: String,
    data: Vec<u8>,
) -> anyhow::Result<()> {
    Ok(SESSION_MANAGER
        .upload_remote_file(session_id, path, data)
        .await?)
}

pub async fn create_remote_directory(session_id: String, path: String) -> anyhow::Result<()> {
    Ok(SESSION_MANAGER
        .create_remote_directory(session_id, path)
        .await?)
}

pub async fn create_remote_file(session_id: String, path: String) -> anyhow::Result<()> {
    Ok(SESSION_MANAGER.create_remote_file(session_id, path).await?)
}

pub async fn chmod_remote_path(
    session_id: String,
    path: String,
    mode: String,
) -> anyhow::Result<()> {
    Ok(SESSION_MANAGER
        .chmod_remote_path(session_id, path, mode)
        .await?)
}

/// Run an arbitrary remote command on the session's *dedicated exec channel*.
///
/// This is intentionally separate from `send_terminal_input` (the interactive
/// shell channel). File-management operations performed by the SFTP/file
/// manager (rename, move, delete, duplicate) used to be sent through the
/// interactive shell, which caused them to be recorded in the remote user's
/// shell history (`HISTFILE`) and to echo marker/printf noise into the visible
/// terminal. Running them through here opens a fresh SSH `exec` channel, so the
/// command never touches the user's interactive shell, its history, or the
/// terminal UI — the captured output (and exit status) is returned directly.
pub async fn exec_remote_command(session_id: String, command: String) -> anyhow::Result<String> {
    Ok(SESSION_MANAGER
        .exec_remote_command(session_id, command)
        .await?)
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
    Ok(host_keys::trust_pending_host_key(&host, port, &fingerprint, &path)?)
}

/// An active local port forward (`ssh -L local_port:remote_host:remote_port`).
pub struct ForwardInfo {
    pub id: String,
    pub profile_id: String,
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
}

impl From<port_forward::LocalForward> for ForwardInfo {
    fn from(forward: port_forward::LocalForward) -> Self {
        Self {
            id: forward.id,
            profile_id: forward.profile_id,
            local_port: forward.local_port,
            remote_host: forward.remote_host,
            remote_port: forward.remote_port,
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
    Ok(port_forward::start_local_forward(profile, local_port, remote_host, remote_port)
        .await?
        .into())
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
            std::fs::read_to_string(format!("{path}.pub")).unwrap().trim(),
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
