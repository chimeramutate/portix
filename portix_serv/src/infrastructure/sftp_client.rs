//! SFTP over its own SSH connection (the `sftp` subsystem), independent of
//! terminal sessions: a file browser never shares a channel with a shell.

use std::io::SeekFrom;
use std::path::{Path, PathBuf};

use russh::Disconnect;
use russh::client;
use russh_sftp::client::SftpSession;
use russh_sftp::protocol::{FileAttributes, OpenFlags};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncSeekExt, AsyncWrite, AsyncWriteExt};

use crate::domain::errors::{PortixError, Result};
use crate::domain::profile::SshProfile;
use crate::domain::sftp::{RemoteFileEntry, TransferProgress};
use crate::infrastructure::ssh_client::{Client, connect_and_authenticate_profile};

/// Suffix of a file that is still being transferred. Its presence means an
/// interrupted transfer, which the next attempt resumes.
pub const PART_SUFFIX: &str = ".portix-part";

const TRANSFER_BUFFER: usize = 256 * 1024;

fn sftp_error(error: russh_sftp::client::error::Error) -> PortixError {
    PortixError::Sftp(error.to_string())
}

/// SFTP resolves relative paths against the login directory, so `~` maps
/// to `.` and `~/x` to `x`.
pub fn remote_path(path: &str) -> String {
    let path = path.trim();
    match path {
        "" | "~" => ".".to_owned(),
        _ => path.strip_prefix("~/").unwrap_or(path).to_owned(),
    }
}

fn join(dir: &str, name: &str) -> String {
    if dir.ends_with('/') {
        format!("{dir}{name}")
    } else {
        format!("{dir}/{name}")
    }
}

pub struct SftpConnection {
    ssh: client::Handle<Client>,
    sftp: SftpSession,
}

impl SftpConnection {
    pub async fn open(profile: &SshProfile) -> Result<Self> {
        Self::over(connect_and_authenticate_profile(profile).await?).await
    }

    pub(crate) async fn over(ssh: client::Handle<Client>) -> Result<Self> {
        let channel = ssh.channel_open_session().await?;
        channel.request_subsystem(true, "sftp").await?;
        let sftp = SftpSession::new(channel.into_stream())
            .await
            .map_err(sftp_error)?;
        Ok(Self { ssh, sftp })
    }

    pub fn is_closed(&self) -> bool {
        self.ssh.is_closed()
    }

    pub async fn close(&self) {
        let _ = self.sftp.close().await;
        let _ = self
            .ssh
            .disconnect(Disconnect::ByApplication, "", "en")
            .await;
    }

    /// Absolute form of [path] (`~` expanded by the server).
    pub async fn resolve(&self, path: &str) -> Result<String> {
        self.sftp
            .canonicalize(remote_path(path))
            .await
            .map_err(sftp_error)
    }

    /// Folders first, then by name. Symlinks report their target's type.
    pub async fn list(&self, path: &str) -> Result<Vec<RemoteFileEntry>> {
        let dir = self.resolve(path).await?;
        let mut entries = Vec::new();
        for entry in self.sftp.read_dir(dir.clone()).await.map_err(sftp_error)? {
            let name = entry.file_name();
            if name == "." || name == ".." {
                continue;
            }
            let path = join(&dir, &name);
            let mut meta = entry.metadata();
            if meta.file_type().is_symlink() {
                if let Ok(target) = self.sftp.metadata(path.clone()).await {
                    meta = target;
                }
            }
            entries.push(RemoteFileEntry {
                name,
                path,
                is_directory: meta.is_dir(),
                size_bytes: meta.size.unwrap_or(0),
                modified_unix_seconds: meta.mtime.map_or(0, i64::from),
                mode: meta.permissions.unwrap_or(0) & 0o7777,
            });
        }
        entries.sort_by(|a, b| {
            b.is_directory
                .cmp(&a.is_directory)
                .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });
        Ok(entries)
    }

    pub async fn read(&self, path: &str) -> Result<Vec<u8>> {
        self.sftp.read(remote_path(path)).await.map_err(sftp_error)
    }

    /// Overwrites in place, so the file keeps its permissions and owner.
    pub async fn write(&self, path: &str, data: &[u8]) -> Result<()> {
        let flags = OpenFlags::WRITE | OpenFlags::CREATE | OpenFlags::TRUNCATE;
        let mut file = self
            .sftp
            .open_with_flags(remote_path(path), flags)
            .await
            .map_err(sftp_error)?;
        file.write_all(data).await?;
        file.shutdown().await?;
        Ok(())
    }

    pub async fn create_dir(&self, path: &str) -> Result<()> {
        self.sftp
            .create_dir(remote_path(path))
            .await
            .map_err(sftp_error)
    }

    /// Creates an empty file; fails if something already exists there.
    pub async fn create_file(&self, path: &str) -> Result<()> {
        let flags = OpenFlags::WRITE | OpenFlags::CREATE | OpenFlags::EXCLUDE;
        let mut file = self
            .sftp
            .open_with_flags(remote_path(path), flags)
            .await
            .map_err(sftp_error)?;
        file.shutdown().await?;
        Ok(())
    }

    pub async fn chmod(&self, path: &str, mode: u32) -> Result<()> {
        let attrs = FileAttributes {
            permissions: Some(mode & 0o7777),
            ..FileAttributes::empty()
        };
        self.sftp
            .set_metadata(remote_path(path), attrs)
            .await
            .map_err(sftp_error)
    }

    pub async fn rename(&self, from: &str, to: &str) -> Result<()> {
        self.sftp
            .rename(remote_path(from), remote_path(to))
            .await
            .map_err(sftp_error)
    }

    /// Deletes a file, or a folder with everything in it. Symlinks are
    /// removed themselves, never followed.
    pub async fn remove(&self, path: &str) -> Result<()> {
        let path = self.resolve(path).await?;
        if path == "/" {
            return Err(PortixError::InvalidRequest(
                "refusing to delete /".to_owned(),
            ));
        }
        self.remove_resolved(&path).await
    }

    async fn remove_resolved(&self, path: &str) -> Result<()> {
        let meta = self
            .sftp
            .symlink_metadata(path.to_owned())
            .await
            .map_err(sftp_error)?;
        if !meta.is_dir() {
            return self
                .sftp
                .remove_file(path.to_owned())
                .await
                .map_err(sftp_error);
        }
        for entry in self
            .sftp
            .read_dir(path.to_owned())
            .await
            .map_err(sftp_error)?
        {
            let name = entry.file_name();
            if name != "." && name != ".." {
                Box::pin(self.remove_resolved(&join(path, &name))).await?;
            }
        }
        self.sftp
            .remove_dir(path.to_owned())
            .await
            .map_err(sftp_error)
    }

    /// Copies a file or folder on the server. SFTP has no server-side copy,
    /// so the bytes make a round trip through this machine.
    pub async fn copy(&self, from: &str, to: &str) -> Result<()> {
        let (from, to) = (remote_path(from), remote_path(to));
        let meta = self.sftp.metadata(from.clone()).await.map_err(sftp_error)?;
        if meta.is_dir() {
            self.sftp.create_dir(to.clone()).await.map_err(sftp_error)?;
            for entry in self.sftp.read_dir(from.clone()).await.map_err(sftp_error)? {
                let name = entry.file_name();
                if name != "." && name != ".." {
                    Box::pin(self.copy(&join(&from, &name), &join(&to, &name))).await?;
                }
            }
            return self.keep_mode(&to, meta.permissions).await;
        }
        let mut src = self.sftp.open(from).await.map_err(sftp_error)?;
        let flags = OpenFlags::WRITE | OpenFlags::CREATE | OpenFlags::EXCLUDE;
        let mut dst = self
            .sftp
            .open_with_flags(to.clone(), flags)
            .await
            .map_err(sftp_error)?;
        tokio::io::copy(&mut src, &mut dst).await?;
        dst.shutdown().await?;
        self.keep_mode(&to, meta.permissions).await
    }

    async fn keep_mode(&self, path: &str, mode: Option<u32>) -> Result<()> {
        match mode {
            Some(mode) => self.chmod(path, mode).await,
            None => Ok(()),
        }
    }

    /// Downloads into `<local>.portix-part`, resuming from its size, then
    /// renames it to [local]. [progress] returning false cancels.
    pub async fn download(
        &self,
        remote: &str,
        local: &Path,
        mut progress: impl FnMut(TransferProgress) -> bool,
    ) -> Result<()> {
        let remote = remote_path(remote);
        let total = self
            .sftp
            .metadata(remote.clone())
            .await
            .map_err(sftp_error)?
            .size
            .unwrap_or(0);
        let part = part_path(local);
        let done = resume_offset(
            tokio::fs::metadata(&part).await.ok().map(|m| m.len()),
            total,
        );

        let mut src = self.sftp.open(remote).await.map_err(sftp_error)?;
        src.seek(SeekFrom::Start(done)).await?;
        let mut dst = tokio::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .append(done > 0)
            .truncate(done == 0)
            .open(&part)
            .await?;
        copy_with_progress(&mut src, &mut dst, done, total, &mut progress).await?;
        dst.flush().await?;
        drop(dst);
        tokio::fs::rename(&part, local).await?;
        Ok(())
    }

    /// Uploads into `<remote>.portix-part`, resuming from its size, then
    /// replaces [remote], keeping the replaced file's permissions.
    /// [progress] returning false cancels.
    pub async fn upload(
        &self,
        local: &Path,
        remote: &str,
        mut progress: impl FnMut(TransferProgress) -> bool,
    ) -> Result<()> {
        let remote = remote_path(remote);
        let total = tokio::fs::metadata(local).await?.len();
        let part = format!("{remote}{PART_SUFFIX}");
        let existing_part = self.sftp.metadata(part.clone()).await.ok();
        let done = resume_offset(existing_part.and_then(|m| m.size), total);

        let mut flags = OpenFlags::WRITE | OpenFlags::CREATE;
        if done == 0 {
            flags |= OpenFlags::TRUNCATE;
        }
        let mut dst = self
            .sftp
            .open_with_flags(part.clone(), flags)
            .await
            .map_err(sftp_error)?;
        dst.seek(SeekFrom::Start(done)).await?;
        let mut src = tokio::fs::File::open(local).await?;
        src.seek(SeekFrom::Start(done)).await?;
        copy_with_progress(&mut src, &mut dst, done, total, &mut progress).await?;
        dst.shutdown().await?;

        // SFTP v3 rename refuses to overwrite, so the old file goes first.
        if let Ok(old) = self.sftp.metadata(remote.clone()).await {
            self.keep_mode(&part, old.permissions).await?;
            self.sftp
                .remove_file(remote.clone())
                .await
                .map_err(sftp_error)?;
        }
        self.sftp.rename(part, remote).await.map_err(sftp_error)
    }
}

fn part_path(local: &Path) -> PathBuf {
    let mut name = local.as_os_str().to_owned();
    name.push(PART_SUFFIX);
    PathBuf::from(name)
}

/// Where a transfer restarts given an existing part file of [part_len]
/// bytes. A part larger than the source cannot belong to it, so start over.
///
/// ponytail: a part is trusted by size alone; if the source changed between
/// attempts the result is corrupt. Compare a checksum if that matters.
fn resume_offset(part_len: Option<u64>, total: u64) -> u64 {
    part_len.filter(|&len| len <= total).unwrap_or(0)
}

async fn copy_with_progress<R, W>(
    src: &mut R,
    dst: &mut W,
    mut done: u64,
    total: u64,
    progress: &mut impl FnMut(TransferProgress) -> bool,
) -> Result<()>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut buf = vec![0u8; TRANSFER_BUFFER];
    while progress(TransferProgress { done, total }) {
        let n = src.read(&mut buf).await?;
        if n == 0 {
            return Ok(());
        }
        dst.write_all(&buf[..n]).await?;
        done += n as u64;
    }
    // Land the buffered writes so the part file holds exactly what was
    // reported, ready to resume from.
    dst.flush().await?;
    Err(PortixError::TransferCancelled)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn home_relative_paths_map_to_sftp_relative_paths() {
        assert_eq!(remote_path("~"), ".");
        assert_eq!(remote_path(" "), ".");
        assert_eq!(remote_path("~/a/b"), "a/b");
        assert_eq!(remote_path("/etc"), "/etc");
        assert_eq!(remote_path("~user"), "~user");
    }

    #[test]
    fn resume_only_from_a_part_that_fits_the_source() {
        assert_eq!(resume_offset(None, 10), 0);
        assert_eq!(resume_offset(Some(4), 10), 4);
        assert_eq!(resume_offset(Some(10), 10), 10);
        assert_eq!(resume_offset(Some(11), 10), 0);
    }
}
