//! Text clipboard sync over the RDP cliprdr channel.
//!
//! cliprdr backend callbacks cannot send PDUs, so [`ClipboardBackend`] only
//! queues what the server did; the session loop drains the queue (via
//! `Cliprdr::downcast_backend_mut`) and answers through [`ClipboardSync`].
//!
//! ponytail: plain text only; images and files stay on their own side.

use ironrdp_cliprdr::backend::CliprdrBackend;
use ironrdp_cliprdr::pdu::{
    ClipboardFormat, ClipboardFormatId, ClipboardGeneralCapabilityFlags, FileContentsRequest,
    FileContentsResponse, FormatDataRequest, FormatDataResponse, LockDataId,
};
use ironrdp_core::impl_as_any;

/// Something the server did on the clipboard channel.
#[derive(Debug, PartialEq)]
pub enum RemoteClipboardEvent {
    /// Channel initialised; the server wants our current format list.
    FormatListRequested,
    /// The remote copied something.
    Copied { has_text: bool },
    /// The remote is pasting and wants our clipboard in `format`.
    DataRequested(ClipboardFormatId),
    /// Text we asked for after [`RemoteClipboardEvent::Copied`].
    Text(String),
}

#[derive(Debug)]
pub struct ClipboardBackend {
    events: Vec<RemoteClipboardEvent>,
    temp_dir: String,
}

impl_as_any!(ClipboardBackend);

impl ClipboardBackend {
    pub fn new() -> Self {
        Self {
            events: Vec::new(),
            temp_dir: std::env::temp_dir().to_string_lossy().into_owned(),
        }
    }

    pub fn take_events(&mut self) -> Vec<RemoteClipboardEvent> {
        std::mem::take(&mut self.events)
    }
}

impl CliprdrBackend for ClipboardBackend {
    fn temporary_directory(&self) -> &str {
        &self.temp_dir
    }

    fn client_capabilities(&self) -> ClipboardGeneralCapabilityFlags {
        ClipboardGeneralCapabilityFlags::USE_LONG_FORMAT_NAMES
    }

    fn on_ready(&mut self) {}

    fn on_request_format_list(&mut self) {
        self.events.push(RemoteClipboardEvent::FormatListRequested);
    }

    fn on_process_negotiated_capabilities(&mut self, _: ClipboardGeneralCapabilityFlags) {}

    fn on_remote_copy(&mut self, available_formats: &[ClipboardFormat]) {
        let has_text = available_formats
            .iter()
            .any(|format| format.id == ClipboardFormatId::CF_UNICODETEXT);
        self.events.push(RemoteClipboardEvent::Copied { has_text });
    }

    fn on_format_data_request(&mut self, request: FormatDataRequest) {
        self.events
            .push(RemoteClipboardEvent::DataRequested(request.format));
    }

    fn on_format_data_response(&mut self, response: FormatDataResponse<'_>) {
        if response.is_error() {
            return;
        }
        if let Ok(text) = response.to_unicode_string() {
            self.events.push(RemoteClipboardEvent::Text(text));
        }
    }

    fn on_file_contents_request(&mut self, _: FileContentsRequest) {}

    fn on_file_contents_response(&mut self, _: FileContentsResponse<'_>) {}

    fn on_lock(&mut self, _: LockDataId) {}

    fn on_unlock(&mut self, _: LockDataId) {}
}

/// What the session loop should do: send on the clipboard channel, or put
/// remote text on the local clipboard.
#[derive(Debug, PartialEq)]
pub enum ClipboardAction {
    /// Advertise our clipboard: text, or nothing (`initiate_copy`).
    Announce { has_text: bool },
    /// Ask for the remote's text (`initiate_paste`).
    RequestText,
    /// Answer a paste request; `None` is an error response.
    SendText(Option<String>),
    /// Put the remote's text on the local clipboard.
    WriteLocal(String),
}

/// Two-way text sync. Remembers the last text that crossed the channel, in
/// either direction, so a value never bounces back to where it came from.
#[derive(Debug, Default)]
pub struct ClipboardSync {
    last_text: Option<String>,
}

impl ClipboardSync {
    /// Local clipboard as read by the periodic poll. Announces it when it
    /// changed since the last sync.
    pub fn on_local_text(&mut self, text: Option<String>) -> Option<ClipboardAction> {
        let text = text.filter(|text| !text.is_empty())?;
        if self.last_text.as_ref() == Some(&text) {
            return None;
        }
        self.last_text = Some(text);
        Some(ClipboardAction::Announce { has_text: true })
    }

    /// Handles a server event; `local_text` reads the local clipboard now.
    pub fn on_remote_event(
        &mut self,
        event: RemoteClipboardEvent,
        local_text: impl FnOnce() -> Option<String>,
    ) -> Option<ClipboardAction> {
        match event {
            RemoteClipboardEvent::FormatListRequested => {
                let text = local_text().filter(|text| !text.is_empty());
                let has_text = text.is_some();
                self.last_text = text;
                Some(ClipboardAction::Announce { has_text })
            }
            RemoteClipboardEvent::Copied { has_text } => {
                has_text.then_some(ClipboardAction::RequestText)
            }
            RemoteClipboardEvent::DataRequested(format) => Some(ClipboardAction::SendText(
                (format == ClipboardFormatId::CF_UNICODETEXT)
                    .then(local_text)
                    .flatten(),
            )),
            RemoteClipboardEvent::Text(text) => {
                // Windows text is NUL-terminated.
                let text = text.trim_end_matches('\0').to_owned();
                if self.last_text.as_ref() == Some(&text) {
                    return None;
                }
                self.last_text = Some(text.clone());
                Some(ClipboardAction::WriteLocal(text))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_changes_are_announced_once() {
        let mut sync = ClipboardSync::default();
        assert_eq!(
            sync.on_local_text(Some("a".into())),
            Some(ClipboardAction::Announce { has_text: true })
        );
        assert_eq!(sync.on_local_text(Some("a".into())), None);
        assert_eq!(sync.on_local_text(None), None);
        assert_eq!(sync.on_local_text(Some(String::new())), None);
    }

    #[test]
    fn remote_copy_fetches_text_and_writes_it_locally_without_echo() {
        let mut sync = ClipboardSync::default();
        let no_local = || None;
        assert_eq!(
            sync.on_remote_event(RemoteClipboardEvent::Copied { has_text: true }, no_local),
            Some(ClipboardAction::RequestText)
        );
        assert_eq!(
            sync.on_remote_event(RemoteClipboardEvent::Copied { has_text: false }, no_local),
            None
        );

        assert_eq!(
            sync.on_remote_event(RemoteClipboardEvent::Text("hi\0".into()), no_local),
            Some(ClipboardAction::WriteLocal("hi".into()))
        );
        // The poll now sees "hi" locally; it came from the remote, so no echo.
        assert_eq!(sync.on_local_text(Some("hi".into())), None);
    }

    #[test]
    fn paste_requests_get_local_text_or_an_error() {
        let mut sync = ClipboardSync::default();
        assert_eq!(
            sync.on_remote_event(
                RemoteClipboardEvent::DataRequested(ClipboardFormatId::CF_UNICODETEXT),
                || Some("x".into())
            ),
            Some(ClipboardAction::SendText(Some("x".into())))
        );
        assert_eq!(
            sync.on_remote_event(
                RemoteClipboardEvent::DataRequested(ClipboardFormatId::new(2)),
                || Some("x".into())
            ),
            Some(ClipboardAction::SendText(None))
        );
    }

    #[test]
    fn initial_format_list_reflects_the_local_clipboard() {
        let mut sync = ClipboardSync::default();
        assert_eq!(
            sync.on_remote_event(RemoteClipboardEvent::FormatListRequested, || None),
            Some(ClipboardAction::Announce { has_text: false })
        );
        assert_eq!(
            sync.on_remote_event(
                RemoteClipboardEvent::FormatListRequested,
                || Some("t".into())
            ),
            Some(ClipboardAction::Announce { has_text: true })
        );
        assert_eq!(sync.on_local_text(Some("t".into())), None, "already announced");
    }
}
