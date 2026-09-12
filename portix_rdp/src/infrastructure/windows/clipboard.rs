//! Windows clipboard backend for RDP clipboard redirection.
//! Uses the native `ironrdp-cliprdr-native` Windows clipboard implementation.

#[cfg(target_os = "windows")]
use ironrdp_cliprdr::backend::CliprdrBackend;
#[cfg(target_os = "windows")]
use ironrdp_cliprdr::pdu::{
    ClipboardFormat, ClipboardFormatId, ClipboardGeneralCapabilityFlags, FileContentsRequest,
    FileContentsResponse, FileDescriptor, FormatDataRequest, FormatDataResponse, LockDataId,
};
#[cfg(target_os = "windows")]
use ironrdp_cliprdr_native::StubCliprdrBackend;
#[cfg(target_os = "windows")]
use ironrdp_core::impl_as_any;

/// Native clipboard backend for Windows using ironrdp-cliprdr-native
/// This is a wrapper around StubCliprdrBackend that provides additional logging.
#[cfg(target_os = "windows")]
#[derive(Debug)]
pub struct NativeClipboardBackend {
    inner: StubCliprdrBackend,
}

#[cfg(target_os = "windows")]
impl NativeClipboardBackend {
    pub fn new() -> Self {
        Self {
            inner: StubCliprdrBackend::new(),
        }
    }
}

#[cfg(target_os = "windows")]
impl Default for NativeClipboardBackend {
    fn default() -> Self {
        Self::new()
    }
}

impl_as_any!(NativeClipboardBackend);

#[cfg(target_os = "windows")]
impl CliprdrBackend for NativeClipboardBackend {
    fn temporary_directory(&self) -> &str {
        CliprdrBackend::temporary_directory(&self.inner)
    }

    fn client_capabilities(&self) -> ClipboardGeneralCapabilityFlags {
        CliprdrBackend::client_capabilities(&self.inner)
    }

    fn on_ready(&mut self) {
        CliprdrBackend::on_ready(&mut self.inner);
        println!("[portix_rdp] Windows clipboard channel is ready");
    }

    fn on_request_format_list(&mut self) {
        CliprdrBackend::on_request_format_list(&mut self.inner);
    }

    fn on_format_list_response(&mut self, ok: bool) {
        CliprdrBackend::on_format_list_response(&mut self.inner, ok);
    }

    fn on_process_negotiated_capabilities(
        &mut self,
        capabilities: ClipboardGeneralCapabilityFlags,
    ) {
        CliprdrBackend::on_process_negotiated_capabilities(&mut self.inner, capabilities);
    }

    fn on_remote_copy(&mut self, available_formats: &[ClipboardFormat]) {
        CliprdrBackend::on_remote_copy(&mut self.inner, available_formats);
    }

    fn on_format_data_request(&mut self, request: FormatDataRequest) {
        CliprdrBackend::on_format_data_request(&mut self.inner, request);
    }

    fn on_format_data_response(&mut self, response: FormatDataResponse<'_>) {
        CliprdrBackend::on_format_data_response(&mut self.inner, response);
    }

    fn on_lock(&mut self, data_id: LockDataId) {
        CliprdrBackend::on_lock(&mut self.inner, data_id);
    }

    fn on_unlock(&mut self, data_id: LockDataId) {
        CliprdrBackend::on_unlock(&mut self.inner, data_id);
    }

    fn on_remote_file_list(&mut self, files: &[FileDescriptor], clip_data_id: Option<u32>) {
        // StubCliprdrBackend uses default implementation which does nothing
        // Forwarding to inner for consistency
        CliprdrBackend::on_remote_file_list(&mut self.inner, files, clip_data_id);
    }

    fn on_file_contents_request(&mut self, request: FileContentsRequest) {
        CliprdrBackend::on_file_contents_request(&mut self.inner, request);
    }

    fn on_file_contents_response(&mut self, response: FileContentsResponse<'_>) {
        CliprdrBackend::on_file_contents_response(&mut self.inner, response);
    }
}

/// Alias for Windows implementation
#[cfg(target_os = "windows")]
pub use self::NativeClipboardBackend as ClipboardBackend;
