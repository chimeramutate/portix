# Command Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Cmd/Ctrl+Shift+P (and Cmd+K on macOS) palette in the main window that finds and runs profiles, open sessions, snippets, terminal actions and app navigation.

**Architecture:** A `CommandRegistry` exposed through an `InheritedWidget` scope holds command *sources* (functions returning commands). `CommandPaletteHost` owns the shortcut and runs the chosen command after the dialog closes. Global commands (profiles, navigation) and terminal commands (built by a pure function, wired in `TerminalPanel`) register as sources. Filtering is a pure function.

**Tech Stack:** Flutter (Dart 3 records/patterns), flutter_bloc, flutter_test. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-09-command-palette-design.md`

## Global Constraints

- Shortcut: Cmd+Shift+P and Cmd+K on macOS; Ctrl+Shift+P on Linux/Windows. Ctrl+K is never intercepted (readline kill-to-end-of-line).
- Commands that cannot run right now are hidden, not disabled.
- The palette closes before a command runs; a throwing command shows a SnackBar `Couldn't run "<title>": <error>`.
- Main window only; SFTP/RDP child windows are out of scope.
- No new packages. Styling uses existing `AppColors`, `AppPanel`, `portixTitle`, `portixMuted` from `package:portix/src/core/widgets/index.dart` and `package:portix/src/core/theme/app_theme.dart`.
- UI copy has no em dashes.
- All commands run from `portix_app/`: `flutter test <file>`, `flutter analyze`.

## Deviations from the spec (decided while planning; Task 1 patches the spec)

1. **Split commands** target an existing tab: "Split right with: <tab>" / "Split down with: <tab>". `TerminalPanel` has no split-with-new-session; `_splitPane(target, dragged, direction)` only joins two existing tabs, and the spec forbids new panel logic.
2. **No group headers.** Every row shows its group label on the right; simpler list, same information.
3. **`CommandRegistry` is a plain class exposed through `CommandPaletteScope` (an `InheritedWidget`)**, not a `ChangeNotifier` in a `RepositoryProvider`. Nobody listens for changes (sources are evaluated when the palette opens), and `CommandPaletteScope.maybeOf` lets `TerminalPanel` work in existing tests that pump it without a host.
4. **Global commands** live in `global_palette_commands.dart` (pure builder + small registering widget) instead of inside the host, so the host is testable without blocs.
5. Broadcast typing is shown only when two or more panes are visible (the toggle is a no-op otherwise).

## Review Focus

- Ctrl+K inside the terminal on Linux/Windows must still reach the shell, not open the palette. Test: Task 3 `Ctrl+K does not open the palette off macOS`.
- Pressing the shortcut while another dialog (profile form, snippet palette) is open must not stack the palette on top. Test: Task 3 `ignored while another route is on top`.
- A command that opens its own dialog (port forward, theme, snippet variables) must not stack on the palette. Test: Task 3 `palette is closed before the command runs`.
- With the terminal hidden (gallery or settings view), terminal actions must not appear, since they would act on an invisible pane. Test: Task 5 `hidden terminal offers only session switching`.
- Enter with no matching results must do nothing and keep the dialog open. Test: Task 2 `Enter with no results keeps the dialog open`.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `lib/src/features/command_palette/palette_command.dart` | `PaletteGroup`, `PaletteCommand`, `CommandRegistry`, `filterCommands` |
| Create `lib/src/features/command_palette/command_palette_dialog.dart` | Search + result list dialog, `showCommandPalette` |
| Create `lib/src/features/command_palette/command_palette_host.dart` | `CommandPaletteScope`, `CommandPaletteHost` (shortcut, run, error SnackBar) |
| Create `lib/src/features/command_palette/global_palette_commands.dart` | `buildGlobalCommands`, `GlobalPaletteCommands` widget |
| Create `lib/src/features/command_palette/index.dart` | Barrel export |
| Create `lib/src/features/ssh_sessions/widget/remote/terminal_palette_commands.dart` | `TerminalCommandActions`, `buildTerminalCommands` |
| Modify `lib/main.dart` | Wrap `PortixWorkspacePage` with host + global commands |
| Modify `lib/src/features/ssh_sessions/widget/remote/terminal_panel.dart` | Register terminal source, snippet cache, drop old Ctrl/Cmd+Shift+P, tooltip |
| Tests in `test/` | `command_palette_filter_test.dart`, `command_registry_test.dart`, `command_palette_dialog_test.dart`, `command_palette_host_test.dart`, `global_palette_commands_test.dart`, `terminal_palette_commands_test.dart` |

---

### Task 1: Command model, registry and filter

**Files:**
- Create: `portix_app/lib/src/features/command_palette/palette_command.dart`
- Create: `portix_app/lib/src/features/command_palette/index.dart`
- Modify: `docs/superpowers/specs/2026-10-09-command-palette-design.md`
- Test: `portix_app/test/command_palette_filter_test.dart`, `portix_app/test/command_registry_test.dart`

**Interfaces:**
- Produces:
  - `enum PaletteGroup { sessions, profiles, terminal, snippets, app }` with `String label`
  - `class PaletteCommand({required String id, required String title, required PaletteGroup group, required FutureOr<void> Function() run, String? subtitle, List<String> keywords = const []})`
  - `typedef PaletteCommandSource = List<PaletteCommand> Function();`
  - `class CommandRegistry { VoidCallback register(PaletteCommandSource source); List<PaletteCommand> get commands; }`
  - `List<PaletteCommand> filterCommands(List<PaletteCommand> commands, String query)`

- [ ] **Step 1: Write the failing filter test**

`portix_app/test/command_palette_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/command_palette/palette_command.dart';

PaletteCommand _cmd(
  String title,
  PaletteGroup group, {
  List<String> keywords = const [],
}) => PaletteCommand(
  id: title,
  title: title,
  group: group,
  keywords: keywords,
  run: () {},
);

List<String> _titles(List<PaletteCommand> commands) =>
    [for (final c in commands) c.title];

void main() {
  final commands = [
    _cmd('Settings', PaletteGroup.app),
    _cmd('Asset sync', PaletteGroup.snippets),
    _cmd('Connect: settings-db', PaletteGroup.profiles),
    _cmd('Switch to: web', PaletteGroup.sessions),
    _cmd('Connect: web', PaletteGroup.profiles, keywords: ['10.0.0.5']),
    _cmd('Terminal theme', PaletteGroup.terminal),
  ];

  test('empty query lists everything by group, then title', () {
    expect(_titles(filterCommands(commands, '  ')), [
      'Switch to: web',
      'Connect: settings-db',
      'Connect: web',
      'Terminal theme',
      'Asset sync',
      'Settings',
    ]);
  });

  test('title prefix beats word prefix beats substring', () {
    expect(_titles(filterCommands(commands, 'set')), [
      'Settings',
      'Connect: settings-db',
      'Asset sync',
    ]);
  });

  test('matching is case-insensitive', () {
    expect(_titles(filterCommands(commands, 'SET')).first, 'Settings');
  });

  test('keywords match', () {
    expect(_titles(filterCommands(commands, '10.0')), ['Connect: web']);
  });

  test('no match returns an empty list', () {
    expect(filterCommands(commands, 'zzz'), isEmpty);
  });
}
```

- [ ] **Step 2: Write the failing registry test**

`portix_app/test/command_registry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/command_palette/palette_command.dart';

void main() {
  PaletteCommand cmd(String id) =>
      PaletteCommand(id: id, title: id, group: PaletteGroup.app, run: () {});

  test('concatenates sources in registration order', () {
    final registry = CommandRegistry()
      ..register(() => [cmd('a')])
      ..register(() => [cmd('b'), cmd('c')]);
    expect([for (final c in registry.commands) c.id], ['a', 'b', 'c']);
  });

  test('sources are evaluated only when commands are read', () {
    var calls = 0;
    final registry = CommandRegistry()
      ..register(() {
        calls++;
        return [cmd('a')];
      });
    expect(calls, 0);
    registry.commands;
    registry.commands;
    expect(calls, 2);
  });

  test('unregister removes the source and is safe to call twice', () {
    final registry = CommandRegistry();
    final unregister = registry.register(() => [cmd('a')]);
    unregister();
    unregister();
    expect(registry.commands, isEmpty);
  });
}
```

- [ ] **Step 3: Run both tests to verify they fail**

Run: `flutter test test/command_palette_filter_test.dart test/command_registry_test.dart`
Expected: FAIL, `palette_command.dart` does not exist.

- [ ] **Step 4: Implement**

`portix_app/lib/src/features/command_palette/palette_command.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

enum PaletteGroup {
  sessions('Sessions'),
  profiles('Profiles'),
  terminal('Terminal'),
  snippets('Snippets'),
  app('App');

  const PaletteGroup(this.label);
  final String label;
}

class PaletteCommand {
  const PaletteCommand({
    required this.id,
    required this.title,
    required this.group,
    required this.run,
    this.subtitle,
    this.keywords = const [],
  });

  final String id;
  final String title;
  final PaletteGroup group;
  final String? subtitle;
  final List<String> keywords;
  final FutureOr<void> Function() run;
}

typedef PaletteCommandSource = List<PaletteCommand> Function();

/// Sources are called each time [commands] is read, so the palette always
/// sees current profiles and sessions.
class CommandRegistry {
  final List<PaletteCommandSource> _sources = [];

  VoidCallback register(PaletteCommandSource source) {
    _sources.add(source);
    return () => _sources.remove(source);
  }

  List<PaletteCommand> get commands => [
    for (final source in List.of(_sources)) ...source(),
  ];
}

final _wordBreak = RegExp(r'[\s:/@._-]+');

List<PaletteCommand> filterCommands(
  List<PaletteCommand> commands,
  String query,
) {
  int byGroupThenTitle(PaletteCommand a, PaletteCommand b) {
    final group = a.group.index.compareTo(b.group.index);
    if (group != 0) return group;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [...commands]..sort(byGroupThenTitle);

  int? rank(PaletteCommand command) {
    final title = command.title.toLowerCase();
    if (title.startsWith(q)) return 0;
    if (title.split(_wordBreak).any((word) => word.startsWith(q))) return 1;
    if (title.contains(q) ||
        command.keywords.any((k) => k.toLowerCase().contains(q))) {
      return 2;
    }
    return null;
  }

  final ranked = [
    for (final command in commands)
      if (rank(command) case final r?) (r, command),
  ]..sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      return byRank != 0 ? byRank : byGroupThenTitle(a.$2, b.$2);
    });
  return [for (final (_, command) in ranked) command];
}
```

`portix_app/lib/src/features/command_palette/index.dart`:

```dart
export 'palette_command.dart';
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/command_palette_filter_test.dart test/command_registry_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 6: Patch the spec with the planning deviations**

In `docs/superpowers/specs/2026-10-09-command-palette-design.md`:
- In the Commands table, replace the row `| Terminal | Split right, Split down | \`_splitPane\` | terminal | terminal visible and session open |` with `| Terminal | Split right with: \`<tab>\`, Split down with: \`<tab>\` (one pair per other open tab) | \`_splitPane(activeId, otherId, right/bottom)\` | terminal | terminal visible, session open, another tab exists |`.
- Replace the row `| Terminal | Toggle broadcast typing | \`_toggleBroadcastTyping\` | terminal | terminal visible and session open |` with `| Terminal | Broadcast typing to all panes / Stop broadcast typing | \`_toggleBroadcastTyping\` | terminal | terminal visible, session open, two or more panes visible |`.
- In `### CommandRegistry`, replace "Provided to the tree with `RepositoryProvider<CommandRegistry>` (flutter_bloc is already a dependency)." with "A plain class (no listeners needed), provided by `CommandPaletteScope`, an `InheritedWidget` with `maybeOf(context)` so `TerminalPanel` still works where no host exists (tests)."
- In `## Dialog`, replace "Group headers appear only when the query is empty." with "Each row shows its group label on the right; there are no group headers."
- Under `## Architecture` table add the row `| \`global_palette_commands.dart\` | Global commands (profiles, navigation) as a pure builder plus a widget that registers them |`.

- [ ] **Step 7: Commit**

```bash
git add portix_app/lib/src/features/command_palette portix_app/test/command_palette_filter_test.dart portix_app/test/command_registry_test.dart docs/superpowers/specs/2026-10-09-command-palette-design.md
git commit -m "feat(palette): command model, registry and filter"
```

---

### Task 2: Palette dialog

**Files:**
- Create: `portix_app/lib/src/features/command_palette/command_palette_dialog.dart`
- Modify: `portix_app/lib/src/features/command_palette/index.dart`
- Test: `portix_app/test/command_palette_dialog_test.dart`

**Interfaces:**
- Consumes: `PaletteCommand`, `filterCommands` (Task 1)
- Produces:
  - `Future<PaletteCommand?> showCommandPalette(BuildContext context, List<PaletteCommand> commands)` (null when dismissed)
  - `class CommandPaletteDialog extends StatefulWidget` (used by tests with `find.byType`)
  - Search field key: `ValueKey('command-palette-query')`

- [ ] **Step 1: Write the failing widget test**

`portix_app/test/command_palette_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/command_palette/command_palette_dialog.dart';
import 'package:portix/src/features/command_palette/palette_command.dart';

const _query = ValueKey('command-palette-query');

PaletteCommand _cmd(String title) => PaletteCommand(
  id: title,
  title: title,
  group: PaletteGroup.app,
  run: () {},
);

/// Pumps an app with an "open" button and opens the palette.
Future<void> _openPalette(
  WidgetTester tester,
  List<PaletteCommand> commands,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCommandPalette(context, commands),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  final commands = [_cmd('Settings'), _cmd('Settings sync'), _cmd('RDP')];

  testWidgets('typing filters the list', (tester) async {
    await _openPalette(tester, commands);
    await tester.enterText(find.byKey(_query), 'rdp');
    await tester.pump();
    expect(find.text('RDP'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('Down then Enter returns the second result', (tester) async {
    PaletteCommand? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showCommandPalette(context, commands),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_query), 'settings');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result?.title, 'Settings sync');
    expect(find.byType(CommandPaletteDialog), findsNothing);
  });

  testWidgets('Escape closes with null', (tester) async {
    PaletteCommand? result = _cmd('sentinel');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showCommandPalette(context, commands),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('Enter with no results keeps the dialog open', (tester) async {
    await _openPalette(tester, commands);
    await tester.enterText(find.byKey(_query), 'zzz');
    await tester.pump();
    expect(find.text('No commands match "zzz"'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPaletteDialog), findsOneWidget);
  });

  testWidgets('tapping a row returns it', (tester) async {
    PaletteCommand? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showCommandPalette(context, commands),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RDP'));
    await tester.pumpAndSettle();
    expect(result?.title, 'RDP');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/command_palette_dialog_test.dart`
Expected: FAIL, `command_palette_dialog.dart` does not exist.

- [ ] **Step 3: Implement**

`portix_app/lib/src/features/command_palette/command_palette_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

import 'palette_command.dart';

Future<PaletteCommand?> showCommandPalette(
  BuildContext context,
  List<PaletteCommand> commands,
) {
  return showDialog<PaletteCommand>(
    context: context,
    builder: (_) => CommandPaletteDialog(commands: commands),
  );
}

class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({required this.commands, super.key});

  final List<PaletteCommand> commands;

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  static const _rowHeight = 52.0;

  final _query = TextEditingController();
  final _scroll = ScrollController();
  late List<PaletteCommand> _results = filterCommands(widget.commands, '');
  int _selected = 0;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    setState(() {
      _results = filterCommands(widget.commands, query);
      _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, _results.length - 1);
    });
    _reveal();
  }

  void _reveal() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = _selected * _rowHeight;
    final bottom = top + _rowHeight;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(bottom - position.viewportDimension);
    }
  }

  void _submit() {
    if (_results.isEmpty) return;
    Navigator.of(context).pop(_results[_selected]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 460),
        child: AppPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _move(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _move(-1),
                },
                child: TextField(
                  key: const ValueKey('command-palette-query'),
                  controller: _query,
                  autofocus: true,
                  onChanged: _onChanged,
                  // onEditingComplete (not onSubmitted) so Enter with no
                  // results keeps focus in the field.
                  onEditingComplete: _submit,
                  style: TextStyle(color: AppColors.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search profiles, sessions, snippets and actions',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: AppColors.muted,
                      size: 19,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No commands match "${_query.text.trim()}"',
                    style: portixMuted(12),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    itemExtent: _rowHeight,
                    itemCount: _results.length,
                    itemBuilder: (context, i) => _CommandRow(
                      command: _results[i],
                      selected: i == _selected,
                      onTap: () => Navigator.of(context).pop(_results[i]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.selected,
    required this.onTap,
  });

  final PaletteCommand command;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = command.subtitle;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: selected ? AppColors.cyan : Colors.transparent,
      ),
    );
    return Material(
      color: selected ? AppColors.selectedSoft : Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      command.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: portixTitle(13),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: portixMuted(11),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(command.group.label, style: portixMuted(11)),
            ],
          ),
        ),
      ),
    );
  }
}
```

Add to `portix_app/lib/src/features/command_palette/index.dart`:

```dart
export 'command_palette_dialog.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/command_palette_dialog_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Check selected-row contrast**

Read the light and dark `cyan`, `selectedSoft` and `surfaceCard` values from `portix_app/lib/src/core/theme/app_theme.dart`, then for each theme run:

```bash
python3 ~/.claude/plugins/cache/anti-slop/antislop/3.2.20/skills/antislop-human/contrast-check.py "<cyan hex>" "<surfaceCard hex>"
```

Expected: ratio ≥ 3.0 in both themes (the cyan border is the selection indicator). If one fails, use `AppColors.text` for the border in `_CommandRow` instead and re-run.

- [ ] **Step 6: Commit**

```bash
git add portix_app/lib/src/features/command_palette portix_app/test/command_palette_dialog_test.dart
git commit -m "feat(palette): searchable command dialog with keyboard navigation"
```

---

### Task 3: Host, scope and shortcut

**Files:**
- Create: `portix_app/lib/src/features/command_palette/command_palette_host.dart`
- Modify: `portix_app/lib/src/features/command_palette/index.dart`
- Test: `portix_app/test/command_palette_host_test.dart`

**Interfaces:**
- Consumes: `CommandRegistry` (Task 1), `showCommandPalette`, `CommandPaletteDialog` (Task 2)
- Produces:
  - `class CommandPaletteScope extends InheritedWidget { static CommandRegistry? maybeOf(BuildContext context); }`
  - `class CommandPaletteHost extends StatefulWidget({required Widget child, CommandRegistry? registry, bool? isMacOS})`

- [ ] **Step 1: Write the failing widget test**

`portix_app/test/command_palette_host_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/command_palette/index.dart';

Future<void> _pumpHost(
  WidgetTester tester,
  CommandRegistry registry, {
  bool isMacOS = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CommandPaletteHost(
        registry: registry,
        isMacOS: isMacOS,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('Other')),
              ),
              child: const Text('other dialog'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _chord(
  WidgetTester tester,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final m in modifiers) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in modifiers.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
}

const _ctrlShift = [
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.shiftLeft,
];

void main() {
  testWidgets('Ctrl+Shift+P opens the palette, a second press is ignored', (
    tester,
  ) async {
    final registry = CommandRegistry()
      ..register(
        () => [
          PaletteCommand(
            id: 'a',
            title: 'Alpha',
            group: PaletteGroup.app,
            run: () {},
          ),
        ],
      );
    await _pumpHost(tester, registry);
    await _chord(tester, _ctrlShift, LogicalKeyboardKey.keyP);
    expect(find.byType(CommandPaletteDialog), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    await _chord(tester, _ctrlShift, LogicalKeyboardKey.keyP);
    expect(find.byType(CommandPaletteDialog), findsOneWidget);
  });

  testWidgets('Cmd+K opens the palette on macOS', (tester) async {
    await _pumpHost(tester, CommandRegistry(), isMacOS: true);
    await _chord(tester, [
      LogicalKeyboardKey.metaLeft,
    ], LogicalKeyboardKey.keyK);
    expect(find.byType(CommandPaletteDialog), findsOneWidget);
  });

  testWidgets('Ctrl+K does not open the palette off macOS', (tester) async {
    await _pumpHost(tester, CommandRegistry());
    await _chord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.keyK);
    expect(find.byType(CommandPaletteDialog), findsNothing);
  });

  testWidgets('ignored while another route is on top', (tester) async {
    await _pumpHost(tester, CommandRegistry());
    await tester.tap(find.text('other dialog'));
    await tester.pumpAndSettle();
    await _chord(tester, _ctrlShift, LogicalKeyboardKey.keyP);
    expect(find.byType(CommandPaletteDialog), findsNothing);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('palette is closed before the command runs', (tester) async {
    late BuildContext hostContext;
    final registry = CommandRegistry()
      ..register(
        () => [
          PaletteCommand(
            id: 'inner',
            title: 'Open inner',
            group: PaletteGroup.app,
            run: () => showDialog<void>(
              context: hostContext,
              builder: (_) => const AlertDialog(content: Text('Inner')),
            ),
          ),
        ],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: CommandPaletteHost(
          registry: registry,
          isMacOS: false,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await _chord(tester, _ctrlShift, LogicalKeyboardKey.keyP);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPaletteDialog), findsNothing);
    expect(find.text('Inner'), findsOneWidget);
  });

  testWidgets('a throwing command shows a SnackBar', (tester) async {
    final registry = CommandRegistry()
      ..register(
        () => [
          PaletteCommand(
            id: 'boom',
            title: 'Explode',
            group: PaletteGroup.app,
            run: () => throw StateError('boom'),
          ),
        ],
      );
    await _pumpHost(tester, registry);
    await _chord(tester, _ctrlShift, LogicalKeyboardKey.keyP);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn\'t run "Explode"'), findsOneWidget);
  });

  testWidgets('maybeOf finds the registry below the host', (tester) async {
    final registry = CommandRegistry();
    CommandRegistry? found;
    await tester.pumpWidget(
      MaterialApp(
        home: CommandPaletteHost(
          registry: registry,
          child: Builder(
            builder: (context) {
              found = CommandPaletteScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(found, same(registry));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/command_palette_host_test.dart`
Expected: FAIL, `CommandPaletteHost` is not defined.

- [ ] **Step 3: Implement**

`portix_app/lib/src/features/command_palette/command_palette_host.dart`:

```dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_palette_dialog.dart';
import 'palette_command.dart';

class CommandPaletteScope extends InheritedWidget {
  const CommandPaletteScope({
    required this.registry,
    required super.child,
    super.key,
  });

  final CommandRegistry registry;

  /// Null when no [CommandPaletteHost] is above [context] (e.g. in tests).
  static CommandRegistry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CommandPaletteScope>()?.registry;

  @override
  bool updateShouldNotify(CommandPaletteScope oldWidget) =>
      registry != oldWidget.registry;
}

/// Opens the command palette on Cmd/Ctrl+Shift+P, or Cmd+K on macOS.
/// Ctrl+K is left alone: it is kill-to-end-of-line in the shell.
class CommandPaletteHost extends StatefulWidget {
  const CommandPaletteHost({
    required this.child,
    this.registry,
    this.isMacOS,
    super.key,
  });

  final Widget child;
  final CommandRegistry? registry;
  final bool? isMacOS;

  @override
  State<CommandPaletteHost> createState() => _CommandPaletteHostState();
}

class _CommandPaletteHostState extends State<CommandPaletteHost> {
  late final CommandRegistry _registry =
      widget.registry ?? CommandRegistry();
  bool _open = false;

  @override
  void initState() {
    super.initState();
    // On HardwareKeyboard so a focused xterm view cannot swallow the keys.
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final shift = keyboard.isShiftPressed;
    final isMacOS = widget.isMacOS ?? Platform.isMacOS;
    final shiftP =
        key == LogicalKeyboardKey.keyP &&
        shift &&
        (keyboard.isControlPressed || keyboard.isMetaPressed);
    final cmdK =
        isMacOS &&
        key == LogicalKeyboardKey.keyK &&
        keyboard.isMetaPressed &&
        !shift &&
        !keyboard.isControlPressed;
    if (!shiftP && !cmdK) return false;
    if (_open) return true;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    unawaited(_openPalette());
    return true;
  }

  Future<void> _openPalette() async {
    _open = true;
    final PaletteCommand? command;
    try {
      command = await showCommandPalette(context, _registry.commands);
    } finally {
      _open = false;
    }
    if (command == null || !mounted) return;
    try {
      await command.run();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Couldn\'t run "${command.title}": $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommandPaletteScope(registry: _registry, child: widget.child);
  }
}
```

Add to `portix_app/lib/src/features/command_palette/index.dart`:

```dart
export 'command_palette_host.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/command_palette_host_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add portix_app/lib/src/features/command_palette portix_app/test/command_palette_host_test.dart
git commit -m "feat(palette): host with Cmd/Ctrl+Shift+P and Cmd+K shortcut"
```

---

### Task 4: Global commands and app wiring

**Files:**
- Create: `portix_app/lib/src/features/command_palette/global_palette_commands.dart`
- Modify: `portix_app/lib/src/features/command_palette/index.dart`
- Modify: `portix_app/lib/main.dart:85-98`
- Test: `portix_app/test/global_palette_commands_test.dart`

**Interfaces:**
- Consumes: `PaletteCommand`, `PaletteGroup` (Task 1), `CommandPaletteHost`, `CommandPaletteScope` (Task 3); `SshProfile` (`package:portix/src/domain/entities/ssh/index.dart`, fields `id`, `name`, `host`, `username`, `group`, `tags`, getter `address`); `SshSessionTarget`, `SshSessionOpenRequested`, `SshSessionBloc` (`features/ssh_sessions/bloc/index.dart`); `WorkspaceView`, `NavigationChanged`, `NewProfileRequested`, `SshWorkspaceBloc` (`features/ssh_profiles/bloc/index.dart`)
- Produces:
  - `List<PaletteCommand> buildGlobalCommands({required List<SshProfile> profiles, required void Function(SshProfile profile, SshSessionTarget target) open, required void Function(WorkspaceView view) navigate, required VoidCallback newProfile})`
  - `class GlobalPaletteCommands extends StatefulWidget({required Widget child})`

- [ ] **Step 1: Write the failing test**

`portix_app/test/global_palette_commands_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/command_palette/index.dart';
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';

SshProfile _profile(String id) => SshProfile(
  id: id,
  name: 'srv-$id',
  host: '10.0.0.$id',
  port: 22,
  username: 'deploy',
  group: 'prod',
  tags: const ['db'],
  authMethod: AuthMethod.password,
  credentialLabel: 'pw-$id',
  defaultPath: '~',
  status: ConnectionStatus.offline,
  color: ProfileColor.cyan,
);

void main() {
  final opened = <(String, SshSessionTarget)>[];
  final views = <WorkspaceView>[];
  var newProfiles = 0;

  List<PaletteCommand> build(List<SshProfile> profiles) => buildGlobalCommands(
    profiles: profiles,
    open: (profile, target) => opened.add((profile.id, target)),
    navigate: views.add,
    newProfile: () => newProfiles++,
  );

  setUp(() {
    opened.clear();
    views.clear();
    newProfiles = 0;
  });

  test('each profile gets Connect and Open SFTP commands', () async {
    final commands = build([_profile('1')]);
    final connect = commands.firstWhere((c) => c.title == 'Connect: srv-1');
    final sftp = commands.firstWhere((c) => c.title == 'Open SFTP: srv-1');
    expect(connect.group, PaletteGroup.profiles);
    expect(connect.subtitle, 'deploy@10.0.0.1:22');
    await connect.run();
    await sftp.run();
    expect(opened, [
      ('1', SshSessionTarget.remoteFolder),
      ('1', SshSessionTarget.sftp),
    ]);
  });

  test('profiles are findable by host, user, group and tag', () {
    final commands = build([_profile('1')]);
    for (final query in ['10.0.0.1', 'deploy', 'prod', 'db']) {
      expect(
        filterCommands(commands, query).map((c) => c.title),
        contains('Connect: srv-1'),
        reason: query,
      );
    }
  });

  test('app commands navigate and create', () async {
    final commands = build(const []);
    Future<void> run(String title) =>
        Future.value(commands.firstWhere((c) => c.title == title).run());
    await run('Profiles gallery');
    await run('Settings');
    await run('RDP');
    await run('New profile');
    expect(views, [
      WorkspaceView.gallery,
      WorkspaceView.settings,
      WorkspaceView.rdp,
    ]);
    expect(newProfiles, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/global_palette_commands_test.dart`
Expected: FAIL, `buildGlobalCommands` is not defined.

- [ ] **Step 3: Implement**

`portix_app/lib/src/features/command_palette/global_palette_commands.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';

import 'command_palette_host.dart';
import 'palette_command.dart';

List<PaletteCommand> buildGlobalCommands({
  required List<SshProfile> profiles,
  required void Function(SshProfile profile, SshSessionTarget target) open,
  required void Function(WorkspaceView view) navigate,
  required VoidCallback newProfile,
}) {
  return [
    for (final profile in profiles) ...[
      PaletteCommand(
        id: 'connect:${profile.id}',
        title: 'Connect: ${profile.name}',
        subtitle: profile.address,
        group: PaletteGroup.profiles,
        keywords: _profileKeywords(profile),
        run: () => open(profile, SshSessionTarget.remoteFolder),
      ),
      PaletteCommand(
        id: 'sftp:${profile.id}',
        title: 'Open SFTP: ${profile.name}',
        subtitle: profile.address,
        group: PaletteGroup.profiles,
        keywords: _profileKeywords(profile),
        run: () => open(profile, SshSessionTarget.sftp),
      ),
    ],
    PaletteCommand(
      id: 'app:new-profile',
      title: 'New profile',
      group: PaletteGroup.app,
      keywords: const ['add', 'create', 'host'],
      run: newProfile,
    ),
    PaletteCommand(
      id: 'app:gallery',
      title: 'Profiles gallery',
      group: PaletteGroup.app,
      keywords: const ['list', 'ssh', 'home'],
      run: () => navigate(WorkspaceView.gallery),
    ),
    PaletteCommand(
      id: 'app:settings',
      title: 'Settings',
      group: PaletteGroup.app,
      keywords: const ['preferences', 'config'],
      run: () => navigate(WorkspaceView.settings),
    ),
    PaletteCommand(
      id: 'app:rdp',
      title: 'RDP',
      subtitle: 'Remote desktop connections',
      group: PaletteGroup.app,
      keywords: const ['remote desktop', 'windows'],
      run: () => navigate(WorkspaceView.rdp),
    ),
  ];
}

List<String> _profileKeywords(SshProfile profile) => [
  profile.host,
  profile.username,
  profile.group,
  ...profile.tags,
];

/// Registers [buildGlobalCommands] with the nearest [CommandPaletteScope],
/// reading the blocs each time the palette opens.
class GlobalPaletteCommands extends StatefulWidget {
  const GlobalPaletteCommands({required this.child, super.key});

  final Widget child;

  @override
  State<GlobalPaletteCommands> createState() => _GlobalPaletteCommandsState();
}

class _GlobalPaletteCommandsState extends State<GlobalPaletteCommands> {
  VoidCallback? _unregister;

  @override
  void initState() {
    super.initState();
    _unregister = CommandPaletteScope.maybeOf(context)?.register(_commands);
  }

  @override
  void dispose() {
    _unregister?.call();
    super.dispose();
  }

  List<PaletteCommand> _commands() {
    if (!mounted) return const [];
    final workspace = context.read<SshWorkspaceBloc>();
    final sessions = context.read<SshSessionBloc>();
    return buildGlobalCommands(
      profiles: workspace.state.profiles,
      open: (profile, target) => sessions.add(
        SshSessionOpenRequested(
          profile: profile,
          target: target,
          preferExistingSession: true,
        ),
      ),
      navigate: (view) => workspace.add(NavigationChanged(view)),
      newProfile: () => workspace.add(const NewProfileRequested()),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

Add to `portix_app/lib/src/features/command_palette/index.dart`:

```dart
export 'global_palette_commands.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/global_palette_commands_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire into the app**

In `portix_app/lib/main.dart`, add the import next to the other `src/features` imports:

```dart
import 'src/features/command_palette/index.dart';
```

and replace

```dart
          child: const PortixWorkspacePage(),
```

with

```dart
          child: const CommandPaletteHost(
            child: GlobalPaletteCommands(child: PortixWorkspacePage()),
          ),
```

- [ ] **Step 6: Analyze and run the whole suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add portix_app/lib/src/features/command_palette portix_app/lib/main.dart portix_app/test/global_palette_commands_test.dart
git commit -m "feat(palette): profile, SFTP and navigation commands in the main window"
```

---

### Task 5: Terminal commands

**Files:**
- Create: `portix_app/lib/src/features/ssh_sessions/widget/remote/terminal_palette_commands.dart`
- Modify: `portix_app/lib/src/features/ssh_sessions/widget/remote/terminal_panel.dart` (imports; state fields near line 92; `initState` near line 127; `dispose` near line 166; tooltip at line 251; `_handlePanelShortcut` at lines 1009-1026; `_openSnippetPalette` at line 1173)
- Test: `portix_app/test/terminal_palette_commands_test.dart`

**Interfaces:**
- Consumes: `PaletteCommand`, `PaletteGroup` (Task 1), `CommandPaletteScope.maybeOf` (Task 3); `TerminalSession({id, profileId, title, status})` and `ConnectionStatus { disconnected, connecting, connected, error }` from `package:portix/src/connection_manager/session_models.dart`; `SplitDirection { left, right, top, bottom }` from `features/ssh_sessions/controller/terminal_split_controller.dart` (exported by `controller/index.dart`); `TerminalSnippet = ({String name, String command})`, `loadTerminalSnippets`, `resolveSnippetVariables` from `terminal_snippets.dart`
- Produces:
  - `class TerminalCommandActions` (callbacks listed in Step 3)
  - `List<PaletteCommand> buildTerminalCommands({required bool terminalVisible, required String? activeSessionId, required List<TerminalSession> sessions, required List<TerminalSnippet> snippets, required bool canPortForward, required bool broadcastAvailable, required bool broadcasting, required bool recording, required TerminalCommandActions actions})`

- [ ] **Step 1: Write the failing test**

`portix_app/test/terminal_palette_commands_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/features/command_palette/palette_command.dart';
import 'package:portix/src/features/ssh_sessions/controller/index.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_palette_commands.dart';

TerminalSession _session(String id) => TerminalSession(
  id: id,
  profileId: 'p-$id',
  title: 'tab-$id',
  status: ConnectionStatus.connected,
);

void main() {
  final calls = <String>[];
  final actions = TerminalCommandActions(
    switchTo: (id) => calls.add('switch $id'),
    split: (id, direction) => calls.add('split $id ${direction.name}'),
    toggleBroadcast: () => calls.add('broadcast'),
    portForward: () => calls.add('port-forward'),
    theme: () => calls.add('theme'),
    find: () => calls.add('find'),
    toggleRecording: () => calls.add('record'),
    saveSnapshot: () => calls.add('save'),
    openSnapshots: () => calls.add('snapshots'),
    closeTab: (id) => calls.add('close $id'),
    runSnippet: (command) => calls.add('snippet $command'),
  );

  List<PaletteCommand> build({
    bool visible = true,
    String? active = 'a',
    List<TerminalSession>? sessions,
    bool canPortForward = true,
    bool broadcastAvailable = true,
    bool broadcasting = false,
    bool recording = false,
  }) => buildTerminalCommands(
    terminalVisible: visible,
    activeSessionId: active,
    sessions: sessions ?? [_session('a'), _session('b')],
    snippets: const [(name: 'Tail log', command: 'tail -f /var/log/syslog')],
    canPortForward: canPortForward,
    broadcastAvailable: broadcastAvailable,
    broadcasting: broadcasting,
    recording: recording,
    actions: actions,
  );

  List<String> titles(List<PaletteCommand> commands) =>
      [for (final c in commands) c.title];

  setUp(calls.clear);

  test('hidden terminal offers only session switching', () {
    expect(titles(build(visible: false)), ['Switch to: tab-a', 'Switch to: tab-b']);
  });

  test('split commands target the other tabs only', () async {
    final commands = build();
    expect(titles(commands), containsAll([
      'Split right with: tab-b',
      'Split down with: tab-b',
    ]));
    expect(titles(commands), isNot(contains('Split right with: tab-a')));
    await commands.firstWhere((c) => c.title == 'Split down with: tab-b').run();
    expect(calls, ['split b bottom']);
  });

  test('broadcast title follows state and needs two visible panes', () {
    expect(titles(build()), contains('Broadcast typing to all panes'));
    expect(titles(build(broadcasting: true)), contains('Stop broadcast typing'));
    expect(
      titles(build(broadcastAvailable: false)).where((t) => t.contains('roadcast')),
      isEmpty,
    );
  });

  test('without an active session only session-free actions remain', () {
    final t = titles(build(active: null));
    expect(t, containsAll(['Terminal theme', 'Saved sessions', 'Port forwarding']));
    for (final missing in [
      'Find in terminal',
      'Start recording',
      'Save session state',
      'Close tab',
      'Tail log',
    ]) {
      expect(t, isNot(contains(missing)));
    }
  });

  test('port forwarding is hidden without a profile to tunnel through', () {
    expect(titles(build(canPortForward: false)), isNot(contains('Port forwarding')));
  });

  test('recording title follows state', () {
    expect(titles(build(recording: true)), contains('Stop recording'));
  });

  test('snippets run their command', () async {
    final snippet = build().firstWhere((c) => c.title == 'Tail log');
    expect(snippet.group, PaletteGroup.snippets);
    expect(snippet.subtitle, 'tail -f /var/log/syslog');
    await snippet.run();
    expect(calls, ['snippet tail -f /var/log/syslog']);
  });

  test('close tab closes the active session', () async {
    await build().firstWhere((c) => c.title == 'Close tab').run();
    expect(calls, ['close a']);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/terminal_palette_commands_test.dart`
Expected: FAIL, `terminal_palette_commands.dart` does not exist.

- [ ] **Step 3: Implement the builder**

`portix_app/lib/src/features/ssh_sessions/widget/remote/terminal_palette_commands.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    show TerminalSession;
import 'package:portix/src/features/command_palette/palette_command.dart';

import '../../controller/index.dart';
import 'terminal_snippets.dart';

class TerminalCommandActions {
  const TerminalCommandActions({
    required this.switchTo,
    required this.split,
    required this.toggleBroadcast,
    required this.portForward,
    required this.theme,
    required this.find,
    required this.toggleRecording,
    required this.saveSnapshot,
    required this.openSnapshots,
    required this.closeTab,
    required this.runSnippet,
  });

  final void Function(String sessionId) switchTo;
  final void Function(String otherSessionId, SplitDirection direction) split;
  final VoidCallback toggleBroadcast;
  final FutureOr<void> Function() portForward;
  final VoidCallback theme;
  final VoidCallback find;
  final FutureOr<void> Function() toggleRecording;
  final FutureOr<void> Function() saveSnapshot;
  final FutureOr<void> Function() openSnapshots;
  final FutureOr<void> Function(String sessionId) closeTab;
  final FutureOr<void> Function(String command) runSnippet;
}

/// Commands that cannot run in the given state are left out, matching when
/// the terminal toolbar enables its buttons.
List<PaletteCommand> buildTerminalCommands({
  required bool terminalVisible,
  required String? activeSessionId,
  required List<TerminalSession> sessions,
  required List<TerminalSnippet> snippets,
  required bool canPortForward,
  required bool broadcastAvailable,
  required bool broadcasting,
  required bool recording,
  required TerminalCommandActions actions,
}) {
  final active = terminalVisible ? activeSessionId : null;
  const terminal = PaletteGroup.terminal;
  return [
    for (final session in sessions)
      PaletteCommand(
        id: 'session:${session.id}',
        title: 'Switch to: ${session.title}',
        group: PaletteGroup.sessions,
        keywords: const ['tab'],
        run: () => actions.switchTo(session.id),
      ),
    if (active != null)
      for (final other in sessions)
        if (other.id != active) ...[
          PaletteCommand(
            id: 'split-right:${other.id}',
            title: 'Split right with: ${other.title}',
            group: terminal,
            keywords: const ['pane', 'vertical'],
            run: () => actions.split(other.id, SplitDirection.right),
          ),
          PaletteCommand(
            id: 'split-down:${other.id}',
            title: 'Split down with: ${other.title}',
            group: terminal,
            keywords: const ['pane', 'horizontal'],
            run: () => actions.split(other.id, SplitDirection.bottom),
          ),
        ],
    if (active != null && broadcastAvailable)
      PaletteCommand(
        id: 'terminal:broadcast',
        title: broadcasting
            ? 'Stop broadcast typing'
            : 'Broadcast typing to all panes',
        group: terminal,
        keywords: const ['multi', 'sync', 'input'],
        run: actions.toggleBroadcast,
      ),
    if (terminalVisible && canPortForward)
      PaletteCommand(
        id: 'terminal:port-forward',
        title: 'Port forwarding',
        group: terminal,
        keywords: const ['tunnel', 'socks'],
        run: actions.portForward,
      ),
    if (terminalVisible)
      PaletteCommand(
        id: 'terminal:theme',
        title: 'Terminal theme',
        group: terminal,
        keywords: const ['colors', 'appearance'],
        run: actions.theme,
      ),
    if (active != null) ...[
      PaletteCommand(
        id: 'terminal:find',
        title: 'Find in terminal',
        group: terminal,
        keywords: const ['search'],
        run: actions.find,
      ),
      PaletteCommand(
        id: 'terminal:record',
        title: recording ? 'Stop recording' : 'Start recording',
        group: terminal,
        keywords: const ['log'],
        run: actions.toggleRecording,
      ),
      PaletteCommand(
        id: 'terminal:save-snapshot',
        title: 'Save session state',
        group: terminal,
        keywords: const ['snapshot', 'bookmark'],
        run: actions.saveSnapshot,
      ),
    ],
    if (terminalVisible)
      PaletteCommand(
        id: 'terminal:snapshots',
        title: 'Saved sessions',
        group: terminal,
        keywords: const ['snapshot', 'restore', 'history'],
        run: actions.openSnapshots,
      ),
    if (active != null) ...[
      PaletteCommand(
        id: 'terminal:close-tab',
        title: 'Close tab',
        group: terminal,
        keywords: const ['session', 'quit'],
        run: () => actions.closeTab(active),
      ),
      for (final (index, snippet) in snippets.indexed)
        PaletteCommand(
          id: 'snippet:$index',
          title: snippet.name,
          subtitle: snippet.command,
          group: PaletteGroup.snippets,
          keywords: [snippet.command],
          run: () => actions.runSnippet(snippet.command),
        ),
    ],
  ];
}
```

- [ ] **Step 4: Run the builder test to verify it passes**

Run: `flutter test test/terminal_palette_commands_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Wire it into `TerminalPanel`**

In `portix_app/lib/src/features/ssh_sessions/widget/remote/terminal_panel.dart`:

5a. Add imports next to the existing ones:

```dart
import 'package:portix/src/features/command_palette/index.dart';
import 'terminal_palette_commands.dart';
```

5b. Add state fields next to `bool _broadcastTyping = false;`:

```dart
  VoidCallback? _unregisterPaletteCommands;
  List<TerminalSnippet> _snippets = const [];
```

5c. In `initState`, directly after `_settingsRepository = sl<SettingsRepository>();`:

```dart
    _unregisterPaletteCommands = CommandPaletteScope.maybeOf(
      context,
    )?.register(_paletteCommands);
    unawaited(_reloadSnippets());
```

5d. In `dispose`, as the first line:

```dart
    _unregisterPaletteCommands?.call();
```

5e. Add these methods directly above `Future<void> _openSnippetPalette() async {`:

```dart
  Future<void> _reloadSnippets() async {
    final snippets = await loadTerminalSnippets(_settingsRepository);
    if (mounted) _snippets = snippets;
  }

  List<PaletteCommand> _paletteCommands() {
    if (!mounted) return const [];
    final active = _sessionId;
    final profileId = active == null
        ? widget.profile?.id
        : _sessionById(active)?.profileId;
    return buildTerminalCommands(
      terminalVisible: widget.keyboardEnabled,
      activeSessionId: active,
      sessions: _orderedSessions(_sshSessions),
      snippets: _snippets,
      canPortForward: widget.profiles.any((p) => p.id == profileId),
      broadcastAvailable: _visibleSessionIds.length >= 2,
      broadcasting: _broadcastTyping,
      recording:
          active != null && _connectionManager.recordingPath(active) != null,
      actions: TerminalCommandActions(
        switchTo: _switchToSessionFromPalette,
        split: (otherId, direction) {
          final target = _sessionId;
          if (target != null) _splitPane(target, otherId, direction);
        },
        toggleBroadcast: _toggleBroadcastTyping,
        portForward: _openPortForwarding,
        theme: _openThemePicker,
        find: _openSearch,
        toggleRecording: _toggleRecording,
        saveSnapshot: _saveSnapshot,
        openSnapshots: _openSnapshots,
        closeTab: _closeTab,
        runSnippet: _runSnippetFromPalette,
      ),
    );
  }

  void _switchToSessionFromPalette(String sessionId) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    context.read<SshWorkspaceBloc>().add(
      const NavigationChanged(WorkspaceView.remoteFolder),
    );
    _activateSession(session);
  }

  Future<void> _runSnippetFromPalette(String command) async {
    final filled = await resolveSnippetVariables(context, command);
    final sessionId = _sessionId;
    if (filled == null || sessionId == null || !mounted) return;
    if (!_isSessionConnected(sessionId)) return;
    unawaited(_connectionManager.sendTerminalInput(sessionId, '$filled\r'));
  }
```

5f. In `_openSnippetPalette`, directly after `command = await showTerminalSnippetPalette(context, _settingsRepository);` add:

```dart
      unawaited(_reloadSnippets());
```

5g. In `_handlePanelShortcut`, delete the snippet branch:

```dart
    if (key == LogicalKeyboardKey.keyP && shift && command) {
      if (_snippetPaletteOpen) return false;
      unawaited(_openSnippetPalette());
      return true;
    }
```

and, if `command` is now unused there, delete `final command = keyboard.isControlPressed || keyboard.isMetaPressed;` too. Change the doc comment above `_handlePanelShortcut` from `/// Ctrl/Cmd+Shift+P opens snippets; Cmd+F (macOS) or Ctrl+Shift+F finds` to `/// Cmd+F (macOS) or Ctrl+Shift+F finds`.

5h. Change the toolbar tooltip `'Snippets (Ctrl+Shift+P)'` to `'Snippets'`.

- [ ] **Step 6: Analyze and run the whole suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!` (existing terminal widget tests pump `TerminalPanel` without a host; `CommandPaletteScope.maybeOf` returns null there, so nothing registers).

- [ ] **Step 7: Commit**

```bash
git add portix_app/lib/src/features/ssh_sessions/widget/remote/terminal_palette_commands.dart portix_app/lib/src/features/ssh_sessions/widget/remote/terminal_panel.dart portix_app/test/terminal_palette_commands_test.dart
git commit -m "feat(palette): sessions, snippets and terminal actions"
```

---

### Task 6: Manual verification and README

**Files:**
- Modify: `README.md` (Features list)

- [ ] **Step 1: Build the Rust backend and run the app**

Run (from repo root): `cd portix_serv && cargo build --release && cd ../portix_app && flutter run -d macos`

- [ ] **Step 2: Click through and record the result of each line**

1. Gallery view, Cmd+Shift+P: palette opens; Profiles and App groups present, no Terminal group.
2. Same with Cmd+K.
3. Type part of a profile host, Enter on `Connect: <name>`: terminal tab opens.
4. In the focused terminal, Cmd+Shift+P opens the palette (xterm does not consume it); Escape returns focus to the terminal.
5. In the terminal, Ctrl+K still deletes to the end of the line (type `echo hello`, move cursor left 3, Ctrl+K, line shows `echo he`).
6. Open a second tab, palette `Split right with: <tab>`: panes split.
7. Palette `Broadcast typing to all panes`, type `date`: runs in both panes; palette now shows `Stop broadcast typing`.
8. Palette `Port forwarding`: palette closes, port forward dialog opens alone.
9. Palette a snippet with `{{var}}`: variable prompt appears, command runs in the active tab.
10. Go to Settings, palette `Switch to: <tab>`: returns to the terminal on that tab.
11. Open the profile form (New profile), press Cmd+Shift+P: nothing happens.
12. Toggle macOS appearance light/dark with the palette open: highlighted row border and text stay readable.

Any line that fails: fix, re-run the suite, repeat the line.

- [ ] **Step 3: Update README features**

In `README.md`, replace the line `- Command autocomplete` with `- Command palette (Cmd/Ctrl+Shift+P, Cmd+K on macOS)`. (The autocomplete pipeline was removed in `6f19092`.)

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: list the command palette in README features"
```
