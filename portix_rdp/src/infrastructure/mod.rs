// Full IronRDP implementation
pub mod rdp_client;

// License cache implementations (stub + file-based) for RDP license-exchange
// fallback handling, e.g. when connecting through CyberArk PAS/PSM.
pub mod license_cache;

// Minimal no-op rdpsnd virtual channel (required companion for rdpdr).
pub mod rdpsnd;

// Text clipboard sync over cliprdr (all platforms, via arboard).
pub mod clipboard;

// MVP fallback implementation kept for reference.
// pub mod rdp_client_mvp;
