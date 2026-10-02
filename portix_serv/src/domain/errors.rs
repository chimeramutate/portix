use thiserror::Error;

#[derive(Debug, Error)]
pub enum PortixError {
    #[error("invalid profile: {0}")]
    InvalidProfile(String),
    #[error("invalid request: {0}")]
    InvalidRequest(String),
    #[error("session not found: {0}")]
    SessionNotFound(String),
    #[error("authentication failed")]
    AuthenticationFailed,
    #[error("SFTP: {0}")]
    Sftp(String),
    #[error("transfer cancelled")]
    TransferCancelled,
    #[error("SSH agent: {0}")]
    SshAgent(String),
    #[error("SSH key {0} is encrypted; a passphrase is required")]
    KeyPassphraseRequired(String),
    #[error("wrong passphrase for SSH key {0}")]
    KeyPassphraseIncorrect(String),
    #[error("connection timed out")]
    ConnectionTimeout,
    #[error("authentication timed out")]
    AuthenticationTimeout,
    #[error("remote command timed out")]
    CommandTimeout,
    #[error(
        "host key for {host}:{port} does not match known_hosts line {line} ({fingerprint}); \
         possible man-in-the-middle attack. If the server key changed legitimately, \
         remove the old entry with `ssh-keygen -R {host}`"
    )]
    HostKeyChanged {
        host: String,
        port: u16,
        line: usize,
        fingerprint: String,
    },
    #[error("host key for {host}:{port} is not in known_hosts ({fingerprint})")]
    HostKeyUnknown {
        host: String,
        port: u16,
        fingerprint: String,
    },
    #[error("cannot use known_hosts file: {0}")]
    KnownHosts(String),
    #[error(transparent)]
    Russh(#[from] russh::Error),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Anyhow(#[from] anyhow::Error),
}

pub type Result<T> = std::result::Result<T, PortixError>;
