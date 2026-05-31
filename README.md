# Portix UI

SSH client MVP with a Flutter UI and Rust SSH core.

## Stack

- Flutter desktop/mobile UI
- `xterm.dart` terminal emulator widget
- `flutter_rust_bridge` bridge boundary
- Rust `tokio` async runtime
- Rust `russh` SSH client
- `serde`, `anyhow`, and `thiserror` for models and errors

## Architecture

Flutter:

- `lib/core/theme`
- `lib/core/widgets`
- `lib/core/di`
- `lib/core/result`
- `lib/features/workspace/domain`
- `lib/features/workspace/presentation/cubit`
- `lib/features/workspace/presentation/pages`
- `lib/screens`
- `lib/widgets`
- `lib/terminal`
- `lib/connection_manager`
- `lib/settings`

Rust:

- `/Users/asepimam/Documents/project/portix-serv/src/domain`
- `/Users/asepimam/Documents/project/portix-serv/src/application`
- `/Users/asepimam/Documents/project/portix-serv/src/infrastructure`
- `/Users/asepimam/Documents/project/portix-serv/src/api.rs`

## Current MVP Surface

- Connection list
- Add, edit, and delete SSH profiles
- Terminal workspace with sidebar, toolbar, tabs, and dark theme
- Interactive `xterm.dart` input/output path
- `flutter_bloc` state management for workspace UI
- `get_it` dependency injection from `lib/core/di/injection_container.dart`
- `Either<AppFailure, T>` result type for explicit success/failure flows
- Reusable theme, button, icon button, panel, and dialog primitives
- Generated `flutter_rust_bridge` bindings under `lib/src/rust`
- Runtime-selectable backend: mock by default, Rust with `PORTIX_BACKEND=rust`
- Rust session manager with realtime output/status/error streams
- Rust `russh` PTY shell runtime with input, resize, and disconnect commands

The Flutter app uses `MockConnectionBackend` by default so UI work stays fast. Run with `PORTIX_BACKEND=rust` to use the real Rust SSH core.

## Dependency Injection

Flutter dependencies are registered in `lib/core/di/injection_container.dart`.

- `ConnectionBackend` is registered as `MockConnectionBackend` by default.
- `ConnectionBackend` is registered as `RustBridgeBackend` when `--dart-define=PORTIX_BACKEND=rust` is used.
- `WorkspaceSessionService` is registered as `ConnectionManager`.
- `WorkspaceCubit` receives `WorkspaceSessionService` through constructor injection.
- Workspace commands return `Either<AppFailure, T>` so failures are handled explicitly in Cubit instead of leaking exceptions into widgets.

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
