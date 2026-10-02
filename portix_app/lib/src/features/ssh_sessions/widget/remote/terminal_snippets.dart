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
        .where(
          (s) => '${s.name} ${s.command}'.toLowerCase().contains(query),
        )
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
              AppTextField(controller: command, label: 'Command'),
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
                  const Icon(Icons.bolt_rounded, color: AppColors.cyan),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Snippets', style: portixTitle(18))),
                  IconButton(
                    tooltip: 'New snippet',
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add_rounded, color: AppColors.cyan),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.muted,
                    ),
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
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Search snippets — Enter runs the first match',
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
                          style: const TextStyle(
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
                              icon: const Icon(
                                Icons.edit_rounded,
                                color: AppColors.muted,
                                size: 16,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () =>
                                  _update([..._snippets]..removeAt(index)),
                              icon: const Icon(
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
