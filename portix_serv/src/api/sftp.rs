//! SFTP file access. Connections are separate from terminal sessions: each
//! one is its own SSH connection running the `sftp` subsystem.

use std::path::PathBuf;

use once_cell::sync::Lazy;

use crate::application::sftp_manager::SftpManager;
use crate::domain::profile::SshProfile;
use crate::domain::sftp::{RemoteFileEntry, TransferProgress};
use crate::frb_generated::StreamSink;

static SFTP_MANAGER: Lazy<SftpManager> = Lazy::new(SftpManager::default);

/// Opens an SFTP connection and returns its id.
pub async fn sftp_connect(profile: SshProfile) -> anyhow::Result<String> {
    Ok(SFTP_MANAGER.connect(profile).await?)
}

pub async fn sftp_disconnect(session_id: String) {
    SFTP_MANAGER.disconnect(&session_id).await;
}

/// False once the connection dropped (it is then forgotten).
pub async fn sftp_is_alive(session_id: String) -> bool {
    SFTP_MANAGER.is_alive(&session_id).await
}

/// Absolute path for [path]; `~` and `~/…` are relative to the login folder.
pub async fn sftp_resolve(session_id: String, path: String) -> anyhow::Result<String> {
    Ok(SFTP_MANAGER.get(&session_id).await?.resolve(&path).await?)
}

pub async fn sftp_list(session_id: String, path: String) -> anyhow::Result<Vec<RemoteFileEntry>> {
    Ok(SFTP_MANAGER.get(&session_id).await?.list(&path).await?)
}

pub async fn sftp_read(session_id: String, path: String) -> anyhow::Result<Vec<u8>> {
    Ok(SFTP_MANAGER.get(&session_id).await?.read(&path).await?)
}

/// Overwrites [path] in place (keeps its permissions); creates it if missing.
pub async fn sftp_write(session_id: String, path: String, data: Vec<u8>) -> anyhow::Result<()> {
    Ok(SFTP_MANAGER
        .get(&session_id)
        .await?
        .write(&path, &data)
        .await?)
}

pub async fn sftp_create_dir(session_id: String, path: String) -> anyhow::Result<()> {
    Ok(SFTP_MANAGER
        .get(&session_id)
        .await?
        .create_dir(&path)
        .await?)
}

pub async fn sftp_create_file(session_id: String, path: String) -> anyhow::Result<()> {
    Ok(SFTP_MANAGER
        .get(&session_id)
        .await?
        .create_file(&path)
        .await?)
}

/// [mode] is the permission bits, e.g. 0o755.
pub async fn sftp_chmod(session_id: String, path: String, mode: u32) -> anyhow::Result<()> {
    Ok(SFTP_MANAGER
        .get(&session_id)
        .await?
        .chmod(&path, mode)
        .await?)
}

pub async fn sftp_rename(session_id: String, from: String, to: String) -> anyhow::Result<()> {
    Ok(SFTP_MANAGER
        .get(&session_id)
        .await?
        .rename(&from, &to)
        .await?)
}

/// Deletes a file or a whole folder.
pub async fn sftp_remove(session_id: String, path: String) -> anyhow::Result<()> {
    Ok(SFTP_MANAGER.get(&session_id).await?.remove(&path).await?)
}

/// Copies a file or folder on the server.
pub async fn sftp_copy(session_id: String, from: String, to: String) -> anyhow::Result<()> {
    Ok(SFTP_MANAGER
        .get(&session_id)
        .await?
        .copy(&from, &to)
        .await?)
}

/// Downloads [remote_path] to [local_path], reporting progress on the
/// returned stream, which ends when done or carries the error. An earlier
/// interrupted download of the same file resumes. Cancelling the stream
/// subscription stops the transfer (the partial file is kept for resuming).
pub async fn sftp_download(
    session_id: String,
    remote_path: String,
    local_path: String,
    sink: StreamSink<TransferProgress>,
) {
    let result = async {
        let connection = SFTP_MANAGER.get(&session_id).await?;
        connection
            .download(&remote_path, &PathBuf::from(local_path), |progress| {
                sink.add(progress).is_ok()
            })
            .await
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(anyhow::Error::from(error));
    }
}

/// Uploads [local_path] to [remote_path]; same stream, resume and cancel
/// behaviour as [sftp_download]. A replaced file keeps its permissions.
pub async fn sftp_upload(
    session_id: String,
    local_path: String,
    remote_path: String,
    sink: StreamSink<TransferProgress>,
) {
    let result = async {
        let connection = SFTP_MANAGER.get(&session_id).await?;
        connection
            .upload(&PathBuf::from(local_path), &remote_path, |progress| {
                sink.add(progress).is_ok()
            })
            .await
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(anyhow::Error::from(error));
    }
}
