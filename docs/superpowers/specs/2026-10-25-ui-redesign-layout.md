# UI redesign: rail + side panel layout

Date: 2026-10-25
Status: draft, pending owner review
Branch: `feat/ui-redesign`

## Goal

Every main view uses one shell: icon rail, a collapsible side panel owned by the shell, then the content. Visual tokens follow `DESIGN.md` (slate + green, Swiss, density 8); the palette and type weights already landed in `54b9a29`.

**Success:** each rail view shows its own panel in the same place, with the same width, header and collapse behavior; no feature loses a capability; `flutter analyze` and `flutter test` stay clean.

## Shell

```
┌──────────────────────────────────────────────┐
│ top bar / title bar (view title, actions)    │
├──┬────────────┬──────────────────────────────┤
│▣ │ PANEL TITLE│                              │
│⇄ │ list       │                              │
│▢ │            │ content                      │
│☸ │            │                              │
│  │            │                              │
│  │            │                              │
└──┴────────────┴──────────────────────────────┘
 48     240              rest
```

- **Rail (48 px)**, unchanged position. Items: Profiles, Terminals (new), RDP, SFTP, Kubernetes. Settings stay in the menu bar. Terminals is disabled while no SSH session is open, because showing the terminal view with nothing open connects to the selected profile.
- Clicking the active rail item collapses or expands the panel. One collapsed flag for the whole shell, kept in memory (not persisted). No shortcut yet: Cmd/Ctrl+B (with or without Shift) already toggles broadcast typing in the terminal; a panel shortcut, if wanted, joins the rebindable `TerminalCommand` set.
- **Panel (240 px)**: `SidePanel` widget in `core/widgets` with a header (title + optional action icon), an optional filter field, and a scrolling body. Hidden below 760 px window width, as the group sidebar is today.
- `WorkspaceShell` takes the panel for the active view; views no longer lay out their own sidebars.
- The top bar stays full width above rail and panel: it is the window title bar, and the macOS traffic lights sit at its left edge.

## Panel per view

| View | Panel content | Source |
|---|---|---|
| Profiles | Groups and tags | existing `GroupSidebar`, moved out of `GalleryShell` |
| Terminals | Open SSH sessions; click shows that session's tab (through `terminalFocusRequests`), status dot + label per session | `ConnectionManager` sessions, active id from `SshSessionBloc` |
| SFTP | Saved servers; click shows the server's tab or opens it in one (through `sftpOpenRequests`) | `SftpWorkspaceBloc` profiles |
| RDP | Profile groups with counts, filtering the profile grid (the grid already lists the profiles) | `RdpWorkspaceBloc` group filter |
| Kubernetes | Server → namespace → pods tree with health dots; replaces the server/namespace/pod pickers in the log toolbar | existing `kubectl get` calls in `kubernetes_page.dart` |

## Components restyled to DESIGN.md

Shared widgets first, so pages inherit them: `AppButton`, `AppPanel`, `AppPill`, inputs (theme), tabs (`tab_option_section`, `sftp_tabs_section`, Kubernetes `_TabChip`), popups/menus, dialogs. Control height 32 px, radius 8, borders over shadows.

## Phases (one commit or PR each, app runs after every phase)

1. **Shell:** `SidePanel`, panel slot in `WorkspaceShell`, collapse on rail reselect, Profiles panel moved from `GalleryShell`.
2. **Shared components:** buttons, inputs, tabs, pills, menus, dialogs at density 8.
3. **Terminals view + panel:** rail item, session list.
4. **SFTP and RDP panels.**
5. **Kubernetes panel:** resource tree replaces the pickers.
6. **Page pass:** each page's own spacing and hierarchy against DESIGN.md; contrast script re-run on both themes.

## Out of scope

- Resizable panel width (add when 240 px proves too narrow).
- Persisting panel collapsed state across launches.
- Terminal ANSI themes.
- New features (Kubernetes exec, describe, etc.).
