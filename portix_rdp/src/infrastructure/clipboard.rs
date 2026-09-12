use ironrdp_cliprdr::backend::CliprdrBackend;
use ironrdp_cliprdr::pdu::{
    ClipboardFormat, ClipboardFormatId, ClipboardGeneralCapabilityFlags,
    FormatDataRequest, FormatDataResponse, FileContentsRequest, FileContentsResponse,
    LockDataId,
};
use std::sync::{Arc, Mutex, RwLock};
use ironrdp_core::impl_as_any;

/// Global clipboard text storing data received from remote.
/// This data will be available to write to local clipboard when needed.
pub static REMOTE_CLIPBOARD_DATA: once_cell::sync::Lazy<Arc<RwLock<String>>> =
    once_cell::sync::Lazy::new(|| Arc::new(RwLock::new(String::new())));

/// Flag to indicate if clipboard data was updated
pub static CLIPBOARD_UPDATED: once_cell::sync::Lazy<Arc<Mutex<bool>>> =
    once_cell::sync::Lazy::new(|| Arc::new(Mutex::new(false)));

/// Native clipboard backend for macOS and Linux using arboard.
#[derive(Debug)]
pub struct NativeClipboardBackend {
    /// The last text from local clipboard that we know of
    local_text: Arc<Mutex<String>>,
    /// Encoded data to send when remote requests
    pending_data: Arc<Mutex<Vec<u8>>>,
}

impl_as_any!(NativeClipboardBackend);

impl NativeClipboardBackend {
    pub fn new() -> Self {
        Self {
            local_text: Arc::new(Mutex::new(String::new())),
            pending_data: Arc::new(Mutex::new(Vec::new())),
        }
    }

    /// Read current text from the OS clipboard (arboard).
    pub fn read_local_clipboard() -> Option<String> {
        arboard::Clipboard::new()
            .ok()
            .and_then(|mut clipboard| clipboard.get_text().ok())
    }

    /// Write text to the OS clipboard (arboard).
    pub fn write_local_clipboard(text: &str) -> bool {
        arboard::Clipboard::new()
            .ok()
            .and_then(|mut clipboard| clipboard.set_text(text).ok())
            .is_some()
    }

    /// Get text from UTF-16 LE encoded data (Windows clipboard format).
    fn decode_unicode_text(data: &[u8]) -> Option<String> {
        if data.len() < 2 {
            return None;
        }

        // Decode UTF-16 LE (little endian)
        let u16_count = data.len() / 2;
        let u16_vec: Vec<u16> = (0..u16_count)
            .map(|i| u16::from_le_bytes([data[i * 2], data[i * 2 + 1]]))
            .collect();

        String::from_utf16(&u16_vec).ok()
    }

    /// Encode text as UTF-16 LE (Windows clipboard format).
    fn encode_unicode_text(text: &str) -> Vec<u8> {
        let u16_vec: Vec<u16> = text.encode_utf16().collect();
        u16_vec.iter()
            .flat_map(|c| c.to_le_bytes())
            .collect()
    }

    /// Get pending data to send to remote
    pub fn take_pending_data(&self) -> Vec<u8> {
        self.pending_data.lock().unwrap().clone()
    }

    /// Take (clear and return) pending data to send to remote
    pub fn take_pending_data_and_clear(&self) -> Vec<u8> {
        let mut guard = self.pending_data.lock().unwrap();
        std::mem::take(&mut *guard)
    }

    /// Set pending data to send to remote
    pub fn set_pending_data(&self, data: Vec<u8>) {
        *self.pending_data.lock().unwrap() = data;
    }

    /// Set the local text from clipboard
    pub fn set_local_text(&self, text: String) {
        *self.local_text.lock().unwrap() = text;
    }

    /// Update the stored local clipboard text
    pub fn update_local_clipboard(&self) {
        if let Some(text) = Self::read_local_clipboard() {
            let mut stored = self.local_text.lock().unwrap();
            if *stored != text {
                *stored = text.clone();
            }
        }
    }

    /// Get the current local text
    pub fn get_local_text(&self) -> String {
        self.local_text.lock().unwrap().clone()
    }

    /// Update local clipboard from remote data when available.
    /// Call this from the RDP runtime after receiving clipboard data.
    pub fn sync_local_from_remote() {
        let remote_text = REMOTE_CLIPBOARD_DATA.read().unwrap().clone();
        if !remote_text.is_empty() {
            if Self::write_local_clipboard(&remote_text) {
                println!("[portix_rdp] synced local clipboard from remote");
                // Clear so we don't sync again
                let mut data = REMOTE_CLIPBOARD_DATA.write().unwrap();
                *data = String::new();
            }
        }
    }

    /// Update the stored remote clipboard data from local clipboard.
    /// Call this from the RDP runtime when local clipboard changes.
    pub fn sync_remote_from_local(&self) {
        if let Some(text) = Self::read_local_clipboard() {
            let mut stored = self.local_text.lock().unwrap();
            if *stored != text {
                *stored = text.clone();

                // Store encoded data for remote
                let encoded = Self::encode_unicode_text(&text);
                self.set_pending_data(encoded);

                let mut remote_data = REMOTE_CLIPBOARD_DATA.write().unwrap();
                *remote_data = text;
                drop(remote_data); // Release lock

                let mut updated = CLIPBOARD_UPDATED.lock().unwrap();
                *updated = true;
            }
        }
    }
}

impl Default for NativeClipboardBackend {
    fn default() -> Self {
        Self::new()
    }
}

impl CliprdrBackend for NativeClipboardBackend {
    fn temporary_directory(&self) -> &str {
        "/tmp/portix_clipboard"
    }

    fn client_capabilities(&self) -> ClipboardGeneralCapabilityFlags {
        // Request basic clipboard support
        ClipboardGeneralCapabilityFlags::USE_LONG_FORMAT_NAMES
            .union(ClipboardGeneralCapabilityFlags::STREAM_FILECLIP_ENABLED)
    }

    fn on_ready(&mut self) {
        println!("[portix_rdp] clipboard channel is ready");

        // Read current local clipboard content
        if let Some(text) = Self::read_local_clipboard() {
            println!("[portix_rdp] local clipboard: {}...",
                text.chars().take(20).collect::<String>());
            self.set_local_text(text);
        }
    }

    fn on_request_format_list(&mut self) {
        println!("[portix_rdp] format list requested by remote");
    }

    fn on_format_list_response(&mut self, _ok: bool) {
        println!("[portix_rdp] format list response received");
    }

    fn on_process_negotiated_capabilities(&mut self, _capabilities: ClipboardGeneralCapabilityFlags) {
        println!("[portix_rdp] negotiated clipboard capabilities");
    }

    fn on_remote_copy(&mut self, available_formats: &[ClipboardFormat]) {
        println!("[portix_rdp] remote copy requested, formats: {:?}",
            available_formats.iter().map(|f| f.id.value()).collect::<Vec<_>>());

        // Check if remote has text data available (CF_UNICODETEXT = 13)
        let has_unicode_text = available_formats.iter().any(|f| {
            f.id == ClipboardFormatId::CF_UNICODETEXT
        });

        if has_unicode_text {
            println!("[portix_rdp] remote has text clipboard");
        }
    }

    fn on_format_data_request(&mut self, request: FormatDataRequest) {
        println!("[portix_rdp] format data request for format: {:?}", request.format.value());

        match request.format {
            id if id == ClipboardFormatId::CF_UNICODETEXT => {
                // CF_UNICODETEXT - data is in pending_data, ready to be submitted
                let data = self.take_pending_data_and_clear();
                if data.is_empty() {
                    // Maybe we need to read from clipboard again
                    if let Some(text) = Self::read_local_clipboard() {
                        let encoded = Self::encode_unicode_text(&text);
                        self.set_local_text(text);
                        self.set_pending_data(encoded);
                    }
                }
                println!("[portix_rdp] preparing text data for remote");
            }
            _ => {
                println!("[portix_rdp] format data request for unsupported format: {:?}", request.format.value());
            }
        }
    }

    fn on_format_data_response(&mut self, response: FormatDataResponse<'_>) {
        println!("[portix_rdp] format data response received");

        // Response from remote clipboard - store for local use
        let data = response.data();
        if data.len() > 2 {
            if let Some(text) = Self::decode_unicode_text(data) {
                let mut remote_data = REMOTE_CLIPBOARD_DATA.write().unwrap();
                *remote_data = text.clone();
                drop(remote_data); // Release lock

                let mut updated = CLIPBOARD_UPDATED.lock().unwrap();
                *updated = true;

                println!("[portix_rdp] received remote clipboard: {}...",
                    text.chars().take(50).collect::<String>());
            }
        }
    }

    fn on_lock(&mut self, _data_id: LockDataId) {
        println!("[portix_rdp] clipboard lock {:?}", _data_id);
    }

    fn on_unlock(&mut self, _data_id: LockDataId) {
        println!("[portix_rdp] clipboard lock {:?} unlocked", _data_id);
    }

    fn on_file_contents_request(&mut self, _request: FileContentsRequest) {
        println!("[portix_rdp] file contents request");
    }

    fn on_file_contents_response(&mut self, _response: FileContentsResponse<'_>) {
        println!("[portix_rdp] file contents response");
    }
}

/// Get the encoded clipboard data from local clipboard.
/// This should be called by RDP runtime to get data to send to remote.
pub fn get_encoded_local_clipboard() -> Vec<u8> {
    NativeClipboardBackend::read_local_clipboard()
        .map(|t| t.encode_utf16().collect::<Vec<u16>>().into_iter())
        .map(|u16_vec| u16_vec.flat_map(|c| c.to_le_bytes()).collect())
        .unwrap_or_default()
}

/// Helper to check if clipboard data should be sent to remote
pub fn has_new_clipboard_data() -> bool {
    *CLIPBOARD_UPDATED.lock().unwrap()
}

/// Clear the clipboard updated flag
pub fn clear_clipboard_updated() {
    let mut updated = CLIPBOARD_UPDATED.lock().unwrap();
    *updated = false;
}

/// Decode UTF-16 LE to text - public version
pub fn decode_data(data: &[u8]) -> Option<String> {
    if data.len() < 2 {
        return None;
    }
    let u16_count = data.len() / 2;
    let u16_vec: Vec<u16> = (0..u16_count)
        .map(|i| u16::from_le_bytes([data[i * 2], data[i * 2 + 1]]))
        .collect();
    String::from_utf16(&u16_vec).ok()
}
