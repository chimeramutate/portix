pub mod api;
pub mod application;
pub mod domain;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod infrastructure;

/// Initialize tracing for IronRDP internal logs.
///
/// This sets up a subscriber that prints `tracing` events (from IronRDP crates)
/// to stdout with the `[portix_rdp][TRACE]` prefix so they are easy to spot
/// alongside our own `println!` debug output.
pub fn init_tracing() {
    #[cfg(any(target_os = "macos", target_os = "linux"))]
    {
        use tracing_subscriber::EnvFilter;
        use tracing_subscriber::fmt::format::FmtSpan;

        let filter = EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| EnvFilter::new("ironrdp=debug,ironrdp_connector=debug,ironrdp_session=debug,ironrdp_tls=debug,ironrdp_pdu=debug,ironrdp_rdpdr=debug,ironrdp_svc=debug,ironrdp_tokio=debug,ironrdp_async=debug,ironrdp_graphics=debug,ironrdp_input=debug,ironrdp_core=debug"));

        let _ = tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_span_events(FmtSpan::NEW | FmtSpan::CLOSE)
            .with_target(true)
            .with_thread_ids(true)
            .with_thread_names(true)
            .with_file(true)
            .with_line_number(true)
            .with_max_level(tracing::Level::TRACE)
            .try_init();
    }
}
