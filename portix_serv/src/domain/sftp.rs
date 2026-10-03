use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct RemoteFileEntry {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size_bytes: u64,
    pub modified_unix_seconds: i64,
    /// Permission bits (e.g. 0o755); 0 when the server did not report them.
    pub mode: u32,
}

/// Bytes moved so far out of `total`; a resumed transfer starts above 0.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TransferProgress {
    pub done: u64,
    pub total: u64,
}
