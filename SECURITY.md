# Security Policy

Portix handles SSH keys, passwords and live connections to your servers, so we take security reports seriously. Thank you for helping keep Portix and its users safe.

## Supported versions

Security fixes go into the latest release. Please update to it before reporting, and check whether the issue still happens.

| Version | Supported |
| --- | --- |
| Latest release ([see Releases](https://github.com/chimeramutate/portix/releases/latest)) | Yes |
| Older releases and pre-releases (`-beta`) | No |

## Reporting a vulnerability

**Please do not open a public issue, discussion or pull request for a security problem.**

Report it privately through GitHub:

1. Go to [Report a vulnerability](https://github.com/chimeramutate/portix/security/advisories/new) (the repository's **Security** tab).
2. Describe the problem and send the report. Only the maintainers can see it.

A useful report includes:

- The Portix version and how you installed it (Snap, release download, built from source).
- Your operating system and version.
- What an attacker can do, and what they need first (for example: a malicious server, a crafted file, local access).
- Steps to reproduce, or a proof of concept.
- Any logs or screenshots, with your own hosts, usernames and secrets removed.

## What happens next

- We aim to acknowledge your report within 7 days.
- We will confirm whether it is a vulnerability, tell you how we plan to fix it, and keep you updated.
- Once a fix is released, we publish a GitHub security advisory. We credit you in it unless you ask us not to.

Please give us reasonable time to release a fix before sharing details publicly.

## Scope

In scope:

- The Portix desktop app (`portix_app`) and its Rust backend (`portix_serv`, `portix_rdp`).
- SSH connections, including host key verification (`known_hosts`) and authentication.
- SFTP file transfer and remote file editing.
- RDP sessions and drive or clipboard redirection.
- Kubernetes log viewing through a saved SSH server.
- How saved profiles, passwords and keys are stored. Secrets are kept in the operating system's secure storage (Keychain on macOS, protected user storage on Windows, libsecret on Linux). On Linux systems without libsecret, Portix falls back to a file that only your user can read; this is weaker than a keyring, and we know about it.
- The release packages built from this repository (Snap and others under `packaging/` and `snap/`).

Out of scope:

- Vulnerabilities in the servers you connect to, or in OpenSSH, RDP servers or `kubectl` themselves.
- Attacks that require an already compromised machine or user account.
- Missing hardening with no clear security impact.
- Issues only in versions that are no longer supported.

If you are unsure whether something is in scope, report it anyway.
