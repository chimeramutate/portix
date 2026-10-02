use std::path::{Path, PathBuf};

use russh::keys::known_hosts::{known_host_keys_path, learn_known_hosts_path};
use russh::keys::{HashAlg, PublicKey};

use crate::domain::errors::{PortixError, Result};

/// What to do when the server's host has no entry in known_hosts yet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HostKeyPolicy {
    /// Record the key on first connect (OpenSSH `StrictHostKeyChecking=accept-new`).
    /// Used by the interactive session, which always connects first.
    AcceptNew,
    /// Only accept keys already recorded. Used by background connections that
    /// reconnect silently, where a key showing up unannounced must not be trusted.
    KnownOnly,
}

/// Default known_hosts location, shared with the user's OpenSSH setup.
pub fn default_known_hosts_path(home: Option<PathBuf>) -> Result<PathBuf> {
    home.map(|home| home.join(".ssh").join("known_hosts"))
        .ok_or_else(|| PortixError::KnownHosts("home directory not found".to_owned()))
}

/// Checks `key` against the known_hosts file at `path`.
///
/// Any recorded key for the host that differs from `key` (including one of a
/// different algorithm) is treated as a mismatch, so an attacker cannot get a
/// new key accepted just by offering a different key type.
pub fn verify_host_key(
    host: &str,
    port: u16,
    key: &PublicKey,
    path: &Path,
    policy: HostKeyPolicy,
) -> Result<()> {
    let recorded = known_host_keys_path(host, port, path)
        .map_err(|e| PortixError::KnownHosts(e.to_string()))?;

    if recorded
        .iter()
        .any(|(_, known)| known.key_data() == key.key_data())
    {
        return Ok(());
    }

    let fingerprint = key.fingerprint(HashAlg::Sha256).to_string();
    if let Some((line, _)) = recorded.first() {
        return Err(PortixError::HostKeyChanged {
            host: host.to_owned(),
            port,
            line: *line,
            fingerprint,
        });
    }

    match policy {
        HostKeyPolicy::AcceptNew => learn_known_hosts_path(host, port, key, path)
            .map_err(|e| PortixError::KnownHosts(e.to_string())),
        HostKeyPolicy::KnownOnly => Err(PortixError::HostKeyUnknown {
            host: host.to_owned(),
            port,
            fingerprint,
        }),
    }
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
        for policy in [HostKeyPolicy::AcceptNew, HostKeyPolicy::KnownOnly] {
            verify_host_key("example.com", 22, &key(KEY_A), &path, policy).unwrap();
        }
        assert_eq!(read(&path), contents);
    }

    #[test]
    fn unknown_host_is_learned_with_accept_new() {
        let (_dir, path) = known_hosts("");
        verify_host_key(
            "example.com",
            22,
            &key(KEY_A),
            &path,
            HostKeyPolicy::AcceptNew,
        )
        .unwrap();
        assert!(
            read(&path)
                .trim_start()
                .starts_with("example.com ssh-ed25519 ")
        );
        // Second connect now matches the recorded key.
        verify_host_key(
            "example.com",
            22,
            &key(KEY_A),
            &path,
            HostKeyPolicy::KnownOnly,
        )
        .unwrap();
    }

    #[test]
    fn unknown_host_is_rejected_with_known_only() {
        let (_dir, path) = known_hosts("");
        let err = verify_host_key(
            "example.com",
            22,
            &key(KEY_A),
            &path,
            HostKeyPolicy::KnownOnly,
        )
        .unwrap_err();
        assert!(matches!(err, PortixError::HostKeyUnknown { .. }));
        assert!(!path.exists());
    }

    #[test]
    fn changed_key_is_rejected_and_not_overwritten() {
        let contents = format!("# comment\nexample.com ssh-ed25519 {KEY_A}\n");
        let (_dir, path) = known_hosts(&contents);
        let err = verify_host_key(
            "example.com",
            22,
            &key(KEY_B),
            &path,
            HostKeyPolicy::AcceptNew,
        )
        .unwrap_err();
        match err {
            PortixError::HostKeyChanged { fingerprint, .. } => {
                assert!(fingerprint.starts_with("SHA256:"));
            }
            other => panic!("expected HostKeyChanged, got {other:?}"),
        }
        assert_eq!(read(&path), contents);
    }

    #[test]
    fn non_default_port_is_stored_in_bracket_form() {
        let (_dir, path) = known_hosts("");
        verify_host_key(
            "example.com",
            2222,
            &key(KEY_A),
            &path,
            HostKeyPolicy::AcceptNew,
        )
        .unwrap();
        assert!(
            read(&path)
                .trim_start()
                .starts_with("[example.com]:2222 ssh-ed25519 ")
        );
        // Same host on port 22 is a different entry.
        let err = verify_host_key(
            "example.com",
            22,
            &key(KEY_A),
            &path,
            HostKeyPolicy::KnownOnly,
        )
        .unwrap_err();
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
