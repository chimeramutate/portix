# Command palette

Date: 2026-10-09
Status: approved design, pending spec review

## Goal

A keyboard-first way to reach anything in the main window: type part of a name, press Enter, and you are there. Covers profiles, open sessions, snippets, terminal actions, and app navigation.

**Success:** from any view in the main window, one shortcut opens a search box; Enter on a result performs the same action as the existing button or menu, with no new behavior in the underlying features.

## Shortcut

- macOS: Cmd+Shift+P and Cmd+K.
- Linux / Windows: Ctrl+Shift+P. Ctrl+K is not used: it is readline's kill-to-end-of-line inside the terminal.
- Ctrl/Cmd+Shift+P currently opens the snippet palette (`terminal_panel.dart`, `_handlePanelShortcut`). That binding moves to the command palette; snippets become a group inside it. The toolbar "Snippets" button keeps opening the existing snippet palette (for editing), and its tooltip drops the shortcut hint.

## Architecture

New folder `lib/src/features/command_palette/`:

| File | Responsibility |
|---|---|
| `palette_command.dart` | `PaletteCommand` data type, `CommandRegistry`, `filterCommands` |
| `command_palette_dialog.dart` | Search field + grouped result list, keyboard navigation |
| `command_palette_host.dart` | Provides the registry, owns the shortcut, registers global commands, runs commands |

### `PaletteCommand`

Immutable: `id`, `title`, `group` (enum: sessions, profiles, terminal, snippets, app), optional `subtitle`, `keywords` (list of strings), and `run` (`FutureOr<void> Function()`).

### `CommandRegistry`

- Holds a set of sources, each `List<PaletteCommand> Function()`.
- `VoidCallback register(source)` adds a source and returns its unregister function.
- `List<PaletteCommand> get commands` calls every source and concatenates. Sources are evaluated when the palette opens, so profiles and sessions are always current without syncing.
- Provided to the tree with `RepositoryProvider<CommandRegistry>` (flutter_bloc is already a dependency).

### `filterCommands(commands, query)`

Pure function. Case-insensitive match against `title` and `keywords`:
1. Empty query: all commands, ordered by group (sessions, profiles, terminal, snippets, app), then title.
2. Otherwise: title prefix matches, then title word-prefix matches, then substring matches in title or keywords. Ties keep group order. Non-matching commands are dropped.

No fuzzy-matching dependency.

### `CommandPaletteHost`

Wraps `PortixWorkspacePage` inside the existing `MultiBlocProvider` in `main.dart`.

- Creates the `CommandRegistry` and registers the **global source** (profiles from `SshWorkspaceBloc` state, app navigation).
- Adds a `HardwareKeyboard` handler (same mechanism as `TerminalPanel`, so the focused xterm view cannot swallow the keys).
- On the shortcut: ignores it if the palette is already open or if another route is on top (`ModalRoute.of(context)?.isCurrent == false`); otherwise snapshots `registry.commands` and shows the dialog.
- When the dialog returns a command, the dialog is already closed; the host then awaits `command.run()`. Commands that open their own dialog (port forward, theme, snippet variables) therefore never stack on the palette.
- If `run()` throws, the host shows a SnackBar: `Couldn't run "<title>": <message>`.

### `TerminalPanel` changes

- In `initState`, registers a **terminal source**; the returned unregister callback runs in `dispose`.
- Removes the Ctrl/Cmd+Shift+P branch from `_handlePanelShortcut`.
- Each command calls an existing method; no new logic in the panel.
- Sources are synchronous but snippets live in settings, so the panel keeps a `List<TerminalSnippet>` cache: filled with `loadTerminalSnippets` in `initState` and reloaded after the snippet palette closes (where snippets are edited).

`TerminalPanel` stays mounted when hidden (the workspace uses an `IndexedStack`), so the source decides availability from `widget.keyboardEnabled` (terminal visible) and `_sessionId` (session open).

## Commands

| Group | Title | Action | Source | Shown when |
|---|---|---|---|---|
| Profiles | Connect: `<name>` (subtitle `user@host`) | `SshSessionOpenRequested(target: remoteFolder, preferExistingSession: true)` | global | always |
| Profiles | Open SFTP: `<name>` | `SshSessionOpenRequested(target: sftp, preferExistingSession: true)` | global | always |
| Sessions | Switch to: `<tab title>` | `NavigationChanged(remoteFolder)`, then `_activateSession(id)` | terminal | a session exists |
| Snippets | `<snippet name>` (subtitle: command) | `resolveSnippetVariables`, then `sendTerminalInput(sessionId, '$command\r')` if the session is connected (same as `_openSnippetPalette`) | terminal | terminal visible and session open |
| Terminal | Split right, Split down | `_splitPane` | terminal | terminal visible and session open |
| Terminal | Toggle broadcast typing | `_toggleBroadcastTyping` | terminal | terminal visible and session open |
| Terminal | Port forwarding | `_openPortForwarding` | terminal | terminal visible |
| Terminal | Terminal theme | `_openThemePicker` | terminal | terminal visible |
| Terminal | Find in terminal | `_openSearch` | terminal | terminal visible and session open |
| Terminal | Start recording / Stop recording | `_toggleRecording` | terminal | terminal visible and session open |
| Terminal | Save session state | `_saveSnapshot` | terminal | terminal visible and session open |
| Terminal | Saved sessions | `_openSnapshots` | terminal | terminal visible |
| Terminal | Close tab | `_closeTab(activeId)` | terminal | terminal visible and session open |
| App | New profile | `NewProfileRequested` | global | always |
| App | Profiles gallery | `NavigationChanged(gallery)` | global | always |
| App | Settings | `NavigationChanged(settings)` | global | always |
| App | RDP | `NavigationChanged(rdp)` | global | always |

Commands that cannot run right now are hidden, not disabled, using the same conditions the toolbar uses for enabling its buttons.

## Dialog

- Search field focused on open. Up/Down move the highlight, Enter runs the highlighted command, Escape closes, clicking a row runs it.
- Rows show title, optional subtitle, and the group name. Group headers appear only when the query is empty.
- No match: `No commands match "<query>"`; Enter does nothing.
- Follows the existing `_SnippetPaletteDialog` styling (`AppColors`, `portixTitle`/`portixMuted`) and works in light and dark themes.
- Highlighted row and focus ring meet 3:1 contrast against the dialog background in both themes.

## Out of scope (v1)

- SFTP and RDP child windows (separate Flutter engines) do not get the palette.
- No recently-used ordering, no user-configurable shortcut, no fuzzy matching.

## Testing

- `test/command_palette_filter_test.dart`: `filterCommands` ordering (empty query grouping, prefix before substring, keyword match, no match).
- `test/command_registry_test.dart`: register/unregister, sources evaluated lazily, unregister is idempotent.
- `test/command_palette_dialog_test.dart` (widget): typing filters, Down + Enter returns the second command, Escape returns null, empty-state text shows.
- `test/command_palette_host_test.dart` (widget): Ctrl+Shift+P opens the palette; a second press while open does nothing; a throwing command shows the SnackBar; the dialog is closed before `run()` executes.
- Existing terminal tests keep passing; `flutter analyze` clean.
- Manual: on macOS, Cmd+Shift+P and Cmd+K open the palette from the gallery and from a focused terminal; Ctrl+K in the terminal still kills to end of line.
