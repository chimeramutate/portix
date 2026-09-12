// Full IronRDP implementation
pub mod rdp_client;

// Minimal no-op rdpsnd virtual channel (required companion for rdpdr).
pub mod rdpsnd;

// Native clipboard backend for macOS and Linux
#[cfg(any(target_os = "macos", target_os = "linux"))]
pub mod clipboard;

// Windows clipboard backend
#[cfg(target_os = "windows")]
pub mod windows;

// MVP fallback implementation kept for reference.
// pub mod rdp_client_mvp;
