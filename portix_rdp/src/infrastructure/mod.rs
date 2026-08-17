// Full IronRDP implementation
pub mod rdp_client;

// Minimal no-op rdpsnd virtual channel (kept for reference, not attached
// to the connection — rdpsnd (audio) is NOT a companion of rdpdr (drives).
// Attaching an unwanted audio channel breaks servers that reject it,
// e.g. CyberArk PSM during license exchange).
pub mod rdpsnd;
