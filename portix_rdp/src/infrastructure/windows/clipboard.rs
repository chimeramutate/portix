//! Windows clipboard backend for RDP clipboard redirection.
//! Uses the native `ironrdp-cliprdr-native` Windows clipboard implementation.

#[cfg(target_os = "windows")]
use ironrdp_cliprdr_native::backend::WindowsClipboardBackend as IronRDPWindowsClipboardBackend;

#[cfg(target_os = "windows")]
use ironrdp_cliprdr::backend::{
    CliprdrBackend, ClipboardFormat, ClipboardFormatId, ClipboardGeneralCapabilityFlags,
    FormatDataRequest, FormatDataResponse, FileContentsRequest, FileContentsResponse,
    LockDataId,
};
#[cfg(target_os = "windows")]
use ironrdp_core::impl_as_any;

/// Wrapper around the ironrdp-native Windows clipboard backend
#[cfg(target_os = "windows")]
#[derive(Debug)]
pub struct NativeClipboardBackend {
    inner: IronRDPWindowsClipboardBackend,
}

#[cfg(target_os = "windows")]
impl NativeClipboardBackend {
    pub fn new() -> Self {
        Self {
            inner: IronRDPWindowsClipboardBackend::new(),
        }
    }
}

#[cfg(target_os = "windows")]
impl Default for NativeClipboardBackend {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_os = "windows")]
impl CliprdrBackend for NativeClipboardBackend {
    fn temporary_directory(&self) -> &str {
        self.inner.temporary_directory()
    }

    fn client_capabilities(&self) -> ClipboardGeneralCapabilityFlags {
        self.inner.client_capabilities()
    }

    fn on_ready(&mut self) {
        self.inner.on_ready();
    }

    fn on_request_format_list(&mut self) {
        self.inner.on_request_format_list();
    }

    fn on_format_list_response(&mut self, ok: bool) {
        self.inner.on_format_list_response(ok);
    }

    fn on_process_negotiated_capabilities(&mut self, capabilities: ClipboardGeneralCapabilityFlags) {
        self.inner.on_process_negotiated_capabilities(capabilities);
    }

    fn on_remote_copy(&mut self, available_formats: &[ClipboardFormat]) {
        self.inner.on_remote_copy(available_formats);
    }

    fn on_format_data_request(&mut self, request: FormatDataRequest) {
        self.inner.on_format_data_request(request);
    }

    fn on_format_data_response(&mut self, response: FormatDataResponse<'_>) {
        self.inner.on_format_data_response(response);
    }

    fn on_lock(&mut self, data_id: LockDataId) {
        self.inner.on_lock(data_id);
    }

    fn on_unlock(&mut self, data_id: LockDataId) {
        self.inner.on_unlock(data_id);
    }

    fn on_remote_file_list(&mut self, files: &[FileDescriptor], clip_data_id: Option<u32>) {
        self.inner.on_remote_file_list(files, clip_data_id);
    }

    fn on_file_contents_request(&mut self, request: FileContentsRequest) {
        self.inner.on_file_contents_request(request);
    }

    fn on_file_contents_response(&mut self, response: FileContentsResponse<'_>) {
        self.inner.on_file_contents_response(response);
    }

    fn on_file_contents_close(&mut self, clip_data_id: u32) {
        self.inner.on_file_contents_close(clip_data_id);
    }
}

/// Alias for Windows implementation
#[cfg(target_os = "windows")]
pub use self::NativeClipboardBackend as ClipboardBackend;
