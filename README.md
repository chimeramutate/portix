# Portix UI

[![portix](https://snapcraft.io/portix/badge.svg)](https://snapcraft.io/portix)

Portix is a modern SSH client built with Flutter UI and Rust SSH core.
Features include multi-tab terminal sessions, split workspace, SFTP file
manager, remote file browsing, command autocomplete, and cross-platform
support for Linux, macOS, and Windows.

## Running

Run the UI with the mock backend:

```sh
flutter run -d macos
```

Build the Rust core and run the UI against real SSH:

```sh
cd /Users/asepimam/Documents/project/portix-serv
cargo build --release

cd /Users/asepimam/Documents/project/portix_ui
flutter run -d macos --dart-define=PORTIX_BACKEND=rust
```

The generated FRB loader currently expects the Rust dynamic library in:

```text
/Users/asepimam/Documents/project/portix-serv/target/release/libportix_serv.dylib
```

## Bridge Wiring

Regenerate bindings after changing public Rust API in `/Users/asepimam/Documents/project/portix-serv/src/api.rs`:

```sh
cargo install flutter_rust_bridge_codegen --version 2.11.1

flutter_rust_bridge_codegen generate \
  --rust-root /Users/asepimam/Documents/project/portix-serv \
  --rust-input crate::api \
  --dart-output lib/src/rust \
  --rust-output /Users/asepimam/Documents/project/portix-serv/src/frb_generated.rs \
  --no-web
```

## Rust Core

The Rust core opens a session channel, requests an `xterm-256color` PTY, starts a shell, streams `ChannelMsg::Data` and `ExtendedData` to Flutter, and forwards input bytes from Flutter back to the SSH channel.
