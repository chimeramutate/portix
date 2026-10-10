---
name: ssh-host-key-verification
description: Analysis and implementation guide for SSH host key verification (known_hosts, trust-on-first-use, fingerprint prompt, "host key changed" errors) in Portix's Rust backend (portix_serv) and Flutter app (portix_app). Use this skill whenever work touches `check_server_key`, `client::Handler`, `connect_and_authenticate_profile`, known_hosts, host fingerprints, MITM protection, or the SSH connect flow in Portix — including when the user asks to "fix host key checking", "add known_hosts support", "verify server fingerprint", harden SSH security, or review the security of SSH connections, even if they don't name host keys explicitly.
---

# SSH host key verification in Portix

## Finding (status as of 2026-10-01)

`portix_serv/src/infrastructure/ssh_client.rs` accepts **any** server key:

```rust
impl client::Handler for Client {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &russh::keys::ssh_key::PublicKey,
    ) -> std::result::Result<bool, Self::Error> {
        Ok(true)
    }
}
```

`Client` is a unit struct and the only `client::Handler` in `portix_serv`. Every
connection goes through `connect_and_authenticate_profile(profile)`, which calls
`client::connect(config, profile.socket_addr(), Client)`. That function is used by:

- `SshRuntime::run` — the interactive terminal session.
- `run_exec_worker` — a second, dedicated connection for SFTP / remote-file /
  autocomplete commands. It **reconnects silently** (on first use, on failure,
  and with a retry after 500 ms).

**Impact:** anyone on the network path (public Wi-Fi, DNS spoofing, a
compromised router) can impersonate the server, receive the password or key
authentication, and read/modify all terminal and SFTP traffic. The UI gives
no warning. This is the highest-value fix in the codebase for an SSH client.

## Progress

**Phase 1 + 2 — done (2026-10-02).** Implemented differently from the plan below:
no prompt inside the handshake (no event stream, oneshot or timeout juggling).

- `host_keys.rs`: `verify_host_key(host, port, key, path)` accepts **only** recorded keys
  (no policy enum any more). A refused key is cached in memory (`PENDING`) with its
  algorithm, SHA-256 fingerprint and, for a changed key, the known_hosts line.
- `connect_and_authenticate_profile` calls `forget_pending_host_key` first, so the cache
  only ever describes the latest attempt. Interactive and exec/SFTP connects both use it.
- `api.rs`: `pending_host_key(host, port) -> Option<HostKeyInfo>` and
  `trust_host_key(host, port, fingerprint)`, which records exactly the key the user saw
  and refuses changed keys or a stale fingerprint.
- Flutter: after a failed connect, `resolveRefusedHostKey`
  (`portix_app/lib/src/features/ssh_sessions/widget/remote/host_key_dialog.dart`) shows
  "Verify host key" (trust → reconnect) or a blocking "Host key changed" dialog with the
  `ssh-keygen -R` command.
- **Connect failures are asynchronous**: Rust `connect` returns the session id first and
  reports a refused key later via status + error events. So the terminal resolves it in
  `_resolveSessionFailure` (from `_handleBackendError`) and SFTP in
  `SftpWorkspaceController._resolveRefusedHostKey` (on session drop). Hooking the
  synchronous failure path does nothing; `test/widget_test.dart` covers the real flow.
- Tests: Rust `host_keys` tests; Dart `host_key_dialog_test.dart`, `sftp_host_key_test.dart`,
  and the async refusal test in `widget_test.dart`.

Still open: `portix_rdp` TLS certificate validation (see Out of scope).

Always re-read the current code before acting; this section may be out of date.

## Target behaviour (trust on first use, same model as OpenSSH)

| Lookup result | Behaviour |
|---|---|
| Key matches known_hosts | Connect normally. |
| Host not in known_hosts | Ask the user to confirm the SHA-256 fingerprint; on accept, record it; on reject, abort. |
| Key differs from recorded key | **Refuse.** Show a clear "host key changed" error with the fingerprint and known_hosts line. No one-click override. |

Use `~/.ssh/known_hosts` so Portix shares trust with the user's OpenSSH setup.

## russh 0.61.2 API (verified in the cargo registry)

```rust
use russh::keys::check_known_hosts;                    // re-exported
use russh::keys::known_hosts::learn_known_hosts;       // NOT re-exported; use the module path
// Path variants for tests: check_known_hosts_path / learn_known_hosts_path

check_known_hosts(host: &str, port: u16, pubkey: &PublicKey) -> Result<bool, russh::keys::Error>
// Ok(true)  -> matching key recorded
// Ok(false) -> host unknown (or only keys of other algorithms recorded)
// Err(russh::keys::Error::KeyChanged { line }) -> same algorithm, different key  => MITM risk

learn_known_hosts(host, port, pubkey) -> Result<(), russh::keys::Error>   // appends, creates ~/.ssh if needed
```

Fingerprint for display: `pubkey.fingerprint(russh::keys::HashAlg::Sha256).to_string()`
(gives `SHA256:...`, same format as `ssh-keygen -l`).

Hosts with a non-22 port are written as `[host]:port` by russh, matching OpenSSH.

## Implementation plan

### 1. Rust: give the handler context

Replace `struct Client;` with a struct holding what the check needs:

```rust
struct Client {
    host: String,
    port: u16,
    mode: HostKeyMode,
}

enum HostKeyMode {
    /// Interactive terminal connect: unknown hosts may be confirmed by the user.
    Interactive(HostKeyPrompt),   // e.g. a channel to the Dart side + oneshot for the answer
    /// Background exec/SFTP worker: only already-trusted keys are accepted.
    StrictKnownOnly,
}
```

In `check_server_key`:
1. `check_known_hosts(&self.host, self.port, key)`.
2. `Ok(true)` → return `Ok(true)`.
3. `Err(KeyChanged { line })` → record the details (see step 2) and return `Ok(false)`.
4. `Ok(false)` → in `Interactive`, send a prompt event with host, port, key algorithm and
   SHA-256 fingerprint, await the user's answer; on accept call `learn_known_hosts` and
   return `Ok(true)`, else `Ok(false)`. In `StrictKnownOnly`, return `Ok(false)`.
5. Any other `Err` (unreadable file, no home dir) → fail closed (`Ok(false)`) and surface
   the reason; do not silently fall back to accepting.

**Why the exec worker must be strict:** it reconnects in the background, often minutes
later. Prompting there would pop dialogs out of nowhere and, worse, a key change during a
silent reconnect is exactly the attack to catch. The interactive session always connects
first, so by the time the worker connects the key is already recorded.

### 2. Rust: surface a meaningful error

Returning `Ok(false)` makes russh fail with a generic `russh::Error::UnknownKey`. Add
specific variants to `PortixError` in `portix_serv/src/domain/errors.rs`, e.g.:

```rust
#[error("host key for {host} changed (known_hosts line {line}); possible man-in-the-middle")]
HostKeyChanged { host: String, line: usize, fingerprint: String },
#[error("host key for {host} was not accepted")]
HostKeyRejected { host: String, fingerprint: String },
```

The handler can't return these directly (its `Error` type is `russh::Error`), so stash
the outcome in the handler (e.g. an `Arc<Mutex<Option<..>>>` shared with the caller) and
map it in `connect_and_authenticate_profile` when `client::connect` fails.

### 3. Timeouts

`client::connect` runs under `CONNECT_TIMEOUT` (15 s). A user reading a fingerprint will
exceed that. Either wait for the prompt answer outside the timeout (e.g. a separate,
longer `HOST_KEY_PROMPT_TIMEOUT` of a few minutes inside the handler, with the outer timeout
covering only TCP + key exchange), or pause the timeout while the prompt is pending.
Treat a prompt timeout as rejection.

### 4. Flutter bridge (portix_app)

- Add an FRB event stream (alongside the existing `ErrorEvent` / `ConnectionStatusEvent`)
  carrying `{ request_id, session_id, host, port, algorithm, fingerprint }`, plus an
  `api.rs` function `answer_host_key(request_id, accept: bool)` that completes the oneshot.
- Regenerate bindings (`flutter_rust_bridge_codegen generate`, config in
  `portix_app/flutter_rust_bridge.yaml`); `frb_generated.*` files must not be hand-edited.
- UI: a dialog showing host:port, algorithm and fingerprint with "Trust and connect" /
  "Cancel". For `HostKeyChanged`, show a blocking error explaining the risk and how to
  remove the old line (`ssh-keygen -R host`) if the change is legitimate — not a button
  that overwrites the entry.
- `portix_app/lib/src/connection_manager/mock_backend.dart` needs a matching stub.

### 5. Tests (Rust)

Use `check_known_hosts_path` / `learn_known_hosts_path` against a temp file so tests never
touch the real `~/.ssh/known_hosts`. That means the handler should take the known_hosts path
as a field (defaulting to `~/.ssh/known_hosts`) so tests can inject one. Cover:

- matching key → accepted
- unknown host, prompt accepted → accepted and line appended
- unknown host, prompt rejected / timed out → rejected, file unchanged
- unknown host in `StrictKnownOnly` → rejected, no prompt sent
- changed key → rejected with `HostKeyChanged`, file unchanged
- non-22 port → stored as `[host]:port`

## Out of scope / follow-ups

- `portix_rdp` has not been reviewed for the equivalent issue (RDP/TLS certificate
  validation in `portix_rdp/src/infrastructure/rdp_client.rs`). Check it separately.
- Hashed known_hosts entries, `@cert-authority` and `@revoked` markers: russh handles
  hashed entries on read; markers are not supported. Mention this rather than reimplementing.
