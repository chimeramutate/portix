import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/repositories/settings/index.dart';

const terminalSnippetsSettingKey = 'terminal.snippets';

typedef TerminalSnippet = ({String name, String command});

Future<List<TerminalSnippet>> loadTerminalSnippets(
  SettingsRepository repository,
) async {
  final raw = (await repository.loadSettings())[terminalSnippetsSettingKey];
  if (raw == null || raw.isEmpty) return [];
  try {
    return [
      for (final item in jsonDecode(raw) as List)
        (name: item['name'] as String, command: item['command'] as String),
    ];
  } catch (_) {
    return [];
  }
}

Future<void> saveTerminalSnippets(
  SettingsRepository repository,
  List<TerminalSnippet> snippets,
) async {
  // saveSettings replaces the whole file, so merge into the current values.
  final values = Map<String, String>.of(await repository.loadSettings());
  values[terminalSnippetsSettingKey] = jsonEncode([
    for (final s in snippets) {'name': s.name, 'command': s.command},
  ]);
  await repository.saveSettings(values);
}

final _variablePattern = RegExp(r'\{\{\s*([A-Za-z_][\w-]*)\s*\}\}');

/// Distinct `{{name}}` placeholders in [command], in order of appearance.
List<String> snippetVariables(String command) => _variablePattern
    .allMatches(command)
    .map((match) => match.group(1)!)
    .toSet()
    .toList(growable: false);

/// Replaces every `{{name}}` in [command] with `values[name]`.
String fillSnippet(String command, Map<String, String> values) =>
    command.replaceAllMapped(
      _variablePattern,
      (match) => values[match.group(1)] ?? match.group(0)!,
    );

/// Asks for each placeholder of [command] and returns the filled command,
/// [command] itself when it has none, or null when cancelled.
Future<String?> resolveSnippetVariables(
  BuildContext context,
  String command,
) async {
  final names = snippetVariables(command);
  if (names.isEmpty) return command;
  final controllers = {for (final name in names) name: TextEditingController()};
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceCard,
      title: Text('Fill in snippet', style: portixTitle(16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              command,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppColors.muted,
              ),
            ),
            for (final (index, name) in names.indexed) ...[
              const SizedBox(height: 12),
              TextField(
                controller: controllers[name],
                autofocus: index == 0,
                decoration: InputDecoration(labelText: name),
                onSubmitted: (_) => Navigator.of(context).pop(true),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Run'),
        ),
      ],
    ),
  );
  final values = {
    for (final entry in controllers.entries) entry.key: entry.value.text,
  };
  for (final controller in controllers.values) {
    controller.dispose();
  }
  return confirmed == true ? fillSnippet(command, values) : null;
}

/// Searchable snippet palette. Returns the command to send, or null.
Future<String?> showTerminalSnippetPalette(
  BuildContext context,
  SettingsRepository repository,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SnippetPaletteDialog(repository: repository),
  );
}

class _SnippetPaletteDialog extends StatefulWidget {
  const _SnippetPaletteDialog({required this.repository});

  final SettingsRepository repository;

  @override
  State<_SnippetPaletteDialog> createState() => _SnippetPaletteDialogState();
}

class _SnippetPaletteDialogState extends State<_SnippetPaletteDialog> {
  final _search = TextEditingController();
  List<TerminalSnippet> _snippets = [];

  @override
  void initState() {
    super.initState();
    loadTerminalSnippets(widget.repository).then((snippets) {
      if (mounted) setState(() => _snippets = snippets);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TerminalSnippet> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _snippets;
    return _snippets
        .where((s) => '${s.name} ${s.command}'.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Future<void> _update(List<TerminalSnippet> snippets) async {
    setState(() => _snippets = snippets);
    await saveTerminalSnippets(widget.repository, snippets);
  }

  Future<void> _edit([int? index]) async {
    final existing = index == null ? null : _snippets[index];
    final name = TextEditingController(text: existing?.name);
    final command = TextEditingController(text: existing?.command);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text(
          existing == null ? 'New snippet' : 'Edit snippet',
          style: portixTitle(16),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(controller: name, label: 'Name'),
              const SizedBox(height: 12),
              AppTextField(
                controller: command,
                label: 'Command',
                hint: 'e.g. tail -f {{logfile}} (asked when run)',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final snippet = (name: name.text.trim(), command: command.text.trim());
    name.dispose();
    command.dispose();
    if (saved != true || snippet.command.isEmpty) return;
    final next = [..._snippets];
    final named = snippet.name.isEmpty
        ? (name: snippet.command, command: snippet.command)
        : snippet;
    index == null ? next.add(named) : next[index] = named;
    await _update(next);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: AppPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: AppColors.cyan),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Snippets', style: portixTitle(18))),
                  IconButton(
                    tooltip: 'New snippet',
                    onPressed: () => _edit(),
                    icon: Icon(Icons.add_rounded, color: AppColors.cyan),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (filtered.isNotEmpty) {
                    Navigator.of(context).pop(filtered.first.command);
                  }
                },
                style: TextStyle(color: AppColors.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search snippets. Enter runs the first match',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.muted,
                    size: 19,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    _snippets.isEmpty
                        ? 'No snippets yet. Add one with +.'
                        : 'No matching snippets.',
                    style: portixMuted(12),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final snippet = filtered[i];
                      final index = _snippets.indexOf(snippet);
                      return ListTile(
                        dense: true,
                        title: Text(snippet.name, style: portixTitle(13)),
                        subtitle: Text(
                          snippet.command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(snippet.command),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () => _edit(index),
                              icon: Icon(
                                Icons.edit_rounded,
                                color: AppColors.muted,
                                size: 16,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () =>
                                  _update([..._snippets]..removeAt(index)),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.muted,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
