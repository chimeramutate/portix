# Portix

[![Snap](https://snapcraft.io/portix/badge.svg)](https://snapcraft.io/portix)

**Portix** is a modern, cross-platform SSH client built with a Flutter desktop application and a high-performance Rust backend.

The project is organized as a **monorepo**, containing the application, backend, and packaging resources in a single repository.

## Features

- Multi-tab terminal sessions
- Split workspace
- Built-in SFTP file manager
- Remote file browsing
- Command autocomplete
- Native Rust SSH engine
- Cross-platform support (Linux, macOS, Windows)

---

# Repository Structure

```text
.
├── portix_app/      # Flutter desktop application
├── portix_serv/     # Rust SSH backend
├── flatpak/         # Flatpak packaging
├── snap/            # Snapcraft packaging
├── packaging/       # Additional packaging resources
└── README.md
```

### `portix_app`

The Flutter application provides the desktop user interface, terminal rendering, workspace management, and communicates with the Rust backend using Flutter Rust Bridge (FRB).

### `portix_serv`

The Rust backend is responsible for:

- SSH connections
- PTY allocation (`xterm-256color`)
- Interactive shell sessions
- Terminal data streaming
- SFTP operations
- Communication with Flutter through FRB

### Packaging

The repository includes packaging configurations for multiple platforms:

- **Flatpak**
- **Snap**
- Additional packaging assets

---

# Getting Started

## Run the Flutter UI

```bash
cd portix_app

flutter run -d macos
```

The generated FRB loader expects the Rust dynamic library to be located at:

```text
portix_serv/target/release/libportix_serv.dylib
```

---

# Flutter Rust Bridge

Whenever the public Rust API changes (`portix_serv/src/api.rs`), regenerate the bindings.

Install the generator:

```bash
cargo install flutter_rust_bridge_codegen --version 2.11.1
```

Generate bindings:

```bash
flutter_rust_bridge_codegen generate \
  --rust-root ../portix_serv \
  --rust-input crate::api \
  --dart-output lib/src/rust \
  --rust-output ../portix_serv/src/frb_generated.rs \
  --no-web
```

Run the command from inside the `portix_app` directory.

---

# Architecture

```text
┌──────────────────────────────┐
│        Flutter UI            │
│                              │
│ • Terminal                   │
│ • Workspace                  │
│ • File Manager               │
└──────────────┬───────────────┘
               │
       Flutter Rust Bridge
               │
┌──────────────▼───────────────┐
│         Rust Backend         │
│                              │
│ • SSH                        │
│ • SFTP                       │
│ • PTY                        │
│ • Shell                      │
└──────────────────────────────┘
```

---

# Development Workflow

1. Develop the Flutter UI inside `portix_app`.
2. Develop the Rust backend inside `portix_serv`.
3. If the Rust public API changes, regenerate the FRB bindings.
4. Build the Rust library.
5. Run the Flutter application.

---

# Platform Support

| Platform | Status |
| -------- | ------ |
| macOS    | ✅     |
| Linux    | ✅     |
| Windows  | ✅     |

---

# License

See the project's license file for details.
