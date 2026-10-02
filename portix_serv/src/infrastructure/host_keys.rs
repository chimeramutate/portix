use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};

use russh::keys::known_hosts::{known_host_keys_path, learn_known_hosts_path};
use russh::keys::{HashAlg, PublicKey};

use crate::domain::errors::{PortixError, Result};

/// Default known_hosts location, shared with the user's OpenSSH setup.
pub fn default_known_hosts_path(home: Option<PathBuf>) -> Result<PathBuf> {
    home.map(|home| home.join(".ssh").join("known_hosts"))
        .ok_or_else(|| PortixError::KnownHosts("home directory not found".to_owned()))
}

/// Checks `key` against the known_hosts file at `path`. Only recorded keys are
/// accepted: an unknown host must first be confirmed by the user (see
/// [`trust_pending_host_key`]), so nothing is ever trusted silently.
///
/// Any recorded key for the host that differs from `key` (including one of a
/// different algorithm) is treated as a mismatch, so an attacker cannot get a
/// new key accepted just by offering a different key type.
pub fn verify_host_key(host: &str, port: u16, key: &PublicKey, path: &Path) -> Result<()> {
    let recorded = known_host_keys_path(host, port, path)
        .map_err(|e| PortixError::KnownHosts(e.to_string()))?;

    if recorded
        .iter()
        .any(|(_, known)| known.key_data() == key.key_data())
    {
        return Ok(());
    }

    let fingerprint = key.fingerprint(HashAlg::Sha256).to_string();
    let changed_line = recorded.first().map(|(line, _)| *line);
    remember_offered_key(host, port, key, changed_line);
    Err(match changed_line {
        Some(line) => PortixError::HostKeyChanged {
            host: host.to_owned(),
            port,
            line,
            fingerprint,
        },
        None => PortixError::HostKeyUnknown {
            host: host.to_owned(),
            port,
            fingerprint,
        },
    })
}

/// A server key that was refused, kept so the UI can show it and, for an
/// unknown host, trust exactly the key the user saw.
#[derive(Clone, Debug)]
pub struct PendingHostKey {
    pub algorithm: String,
    pub fingerprint: String,
    /// known_hosts line of the recorded key when the key *changed*.
    pub changed_line: Option<usize>,
    key: PublicKey,
}

// ponytail: in-memory only; a refused key must be re-offered after a restart.
static PENDING: LazyLock<Mutex<HashMap<(String, u16), PendingHostKey>>> =
    LazyLock::new(Default::default);

fn remember_offered_key(host: &str, port: u16, key: &PublicKey, changed_line: Option<usize>) {
    let pending = PendingHostKey {
        algorithm: key.algorithm().to_string(),
        fingerprint: key.fingerprint(HashAlg::Sha256).to_string(),
        changed_line,
        key: key.clone(),
    };
    PENDING
        .lock()
        .unwrap()
        .insert((host.to_owned(), port), pending);
}

/// Called at the start of every connect so a pending key always describes the
/// most recent attempt, never a stale refusal from an earlier one.
pub fn forget_pending_host_key(host: &str, port: u16) {
    PENDING.lock().unwrap().remove(&(host.to_owned(), port));
}

/// The key last refused for `host:port`, if any.
pub fn pending_host_key(host: &str, port: u16) -> Option<PendingHostKey> {
    PENDING
        .lock()
        .unwrap()
        .get(&(host.to_owned(), port))
        .cloned()
}

/// Records the refused key for an unknown host in known_hosts. `fingerprint`
/// must match the key the user was shown. A *changed* key is never trusted
/// here: the old entry has to be removed deliberately (`ssh-keygen -R`).
pub fn trust_pending_host_key(host: &str, port: u16, fingerprint: &str, path: &Path) -> Result<()> {
    let mut pending = PENDING.lock().unwrap();
    let id = (host.to_owned(), port);
    let entry = pending
        .get(&id)
        .ok_or_else(|| PortixError::KnownHosts(format!("no pending host key for {host}:{port}")))?;
    if entry.changed_line.is_some() {
        return Err(PortixError::KnownHosts(format!(
            "host key for {host}:{port} changed; remove the old entry with `ssh-keygen -R {host}`"
        )));
    }
    if entry.fingerprint != fingerprint {
        return Err(PortixError::KnownHosts(format!(
            "fingerprint for {host}:{port} no longer matches the key that was shown"
        )));
    }
    learn_known_hosts_path(host, port, &entry.key, path)
        .map_err(|e| PortixError::KnownHosts(e.to_string()))?;
    pending.remove(&id);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use russh::keys::parse_public_key_base64;

    const KEY_A: &str = "AAAAC3NzaC1lZDI1NTE5AAAAIJdD7y3aLq454yWBdwLWbieU1ebz9/cu7/QEXn9OIeZJ";
    const KEY_B: &str = "AAAAC3NzaC1lZDI1NTE5AAAAILIG2T/B0l0gaqj3puu510tu9N1OkQ4znY3LYuEm5zCF";

    fn key(b64: &str) -> PublicKey {
        parse_public_key_base64(b64).unwrap()
    }

    fn known_hosts(contents: &str) -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".ssh").join("known_hosts");
        if !contents.is_empty() {
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, contents).unwrap();
        }
        (dir, path)
    }

    fn read(path: &Path) -> String {
        std::fs::read_to_string(path).unwrap_or_default()
    }

    #[test]
    fn matching_key_is_accepted_without_writing() {
        let contents = format!("example.com ssh-ed25519 {KEY_A}\n");
        let (_dir, path) = known_hosts(&contents);
        verify_host_key("example.com", 22, &key(KEY_A), &path).unwrap();
        assert_eq!(read(&path), contents);
    }

    #[test]
    fn unknown_host_is_rejected_until_the_shown_key_is_trusted() {
        let (_dir, path) = known_hosts("");
        let err = verify_host_key("unknown.test", 22, &key(KEY_A), &path).unwrap_err();
        let PortixError::HostKeyUnknown { fingerprint, .. } = err else {
            panic!("expected HostKeyUnknown, got {err:?}");
        };
        assert!(!path.exists(), "nothing is written before the user decides");

        let pending = pending_host_key("unknown.test", 22).unwrap();
        assert_eq!(pending.fingerprint, fingerprint);
        assert_eq!(pending.algorithm, "ssh-ed25519");
        assert!(pending.changed_line.is_none());

        assert!(trust_pending_host_key("unknown.test", 22, "SHA256:wrong", &path).is_err());
        trust_pending_host_key("unknown.test", 22, &fingerprint, &path).unwrap();
        assert!(read(&path).trim_start().starts_with("unknown.test ssh-ed25519 "));
        assert!(pending_host_key("unknown.test", 22).is_none());
        verify_host_key("unknown.test", 22, &key(KEY_A), &path).unwrap();
    }

    #[test]
    fn changed_key_is_rejected_and_cannot_be_trusted() {
        let contents = format!("# comment\nchanged.test ssh-ed25519 {KEY_A}\n");
        let (_dir, path) = known_hosts(&contents);
        let err = verify_host_key("changed.test", 22, &key(KEY_B), &path).unwrap_err();
        let PortixError::HostKeyChanged { fingerprint, line, .. } = err else {
            panic!("expected HostKeyChanged, got {err:?}");
        };
        assert!(fingerprint.starts_with("SHA256:"));
        assert_eq!(pending_host_key("changed.test", 22).unwrap().changed_line, Some(line));
        assert!(trust_pending_host_key("changed.test", 22, &fingerprint, &path).is_err());
        assert_eq!(read(&path), contents);
    }

    #[test]
    fn non_default_port_is_stored_in_bracket_form() {
        let (_dir, path) = known_hosts("");
        let _ = verify_host_key("port.test", 2222, &key(KEY_A), &path);
        let fingerprint = pending_host_key("port.test", 2222).unwrap().fingerprint;
        trust_pending_host_key("port.test", 2222, &fingerprint, &path).unwrap();
        assert!(read(&path).trim_start().starts_with("[port.test]:2222 ssh-ed25519 "));
        // Same host on port 22 is a different entry.
        let err = verify_host_key("port.test", 22, &key(KEY_A), &path).unwrap_err();
        assert!(matches!(err, PortixError::HostKeyUnknown { .. }));
    }

    #[test]
    fn default_path_requires_home() {
        assert!(default_known_hosts_path(None).is_err());
        assert_eq!(
            default_known_hosts_path(Some(PathBuf::from("/home/u"))).unwrap(),
            PathBuf::from("/home/u/.ssh/known_hosts")
        );
    }
}
