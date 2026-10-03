import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;

import '../../controller/index.dart';

/// Asks for a name (tab or snapshot), prefilled with [initial]. Null when
/// cancelled.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required String action,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial, action: action),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.action,
  });

  final String title;
  final String initial;
  final String action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('name-dialog-field'),
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

/// Lists saved snapshots of one profile at a time (starting with
/// [initialProfileId]) and returns the one to open.
Future<SessionSnapshot?> showSessionSnapshotsDialog(
  BuildContext context, {
  required SessionSnapshotStore store,
  required List<domain.SshProfile> profiles,
  required String? initialProfileId,
}) {
  return showDialog<SessionSnapshot>(
    context: context,
    builder: (_) => SessionSnapshotsDialog(
      store: store,
      profiles: profiles,
      initialProfileId: initialProfileId,
    ),
  );
}

class SessionSnapshotsDialog extends StatefulWidget {
  const SessionSnapshotsDialog({
    required this.store,
    required this.profiles,
    required this.initialProfileId,
    super.key,
  });

  final SessionSnapshotStore store;
  final List<domain.SshProfile> profiles;
  final String? initialProfileId;

  @override
  State<SessionSnapshotsDialog> createState() => _SessionSnapshotsDialogState();
}

class _SessionSnapshotsDialogState extends State<SessionSnapshotsDialog> {
  List<SessionSnapshot>? _snapshots;
  String? _profileId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profileId = widget.initialProfileId;
    _reload();
  }

  Future<void> _reload() async {
    try {
      final snapshots = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _snapshots = snapshots;
        final ids = _profileIds(snapshots);
        if (!ids.contains(_profileId)) _profileId = ids.firstOrNull;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Failed to load snapshots: $error');
    }
  }

  /// Profiles that still exist and have at least one snapshot.
  List<String> _profileIds(List<SessionSnapshot> snapshots) {
    final withSnapshots = snapshots.map((s) => s.profileId).toSet();
    return [
      for (final profile in widget.profiles)
        if (withSnapshots.contains(profile.id)) profile.id,
    ];
  }

  Future<void> _delete(SessionSnapshot snapshot) async {
    try {
      await widget.store.delete(snapshot.id);
    } catch (error) {
      if (mounted) setState(() => _error = 'Failed to delete: $error');
      return;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final snapshots = _snapshots;
    final profileIds = snapshots == null
        ? const <String>[]
        : _profileIds(snapshots);
    final shown = [
      for (final snapshot in snapshots ?? const <SessionSnapshot>[])
        if (snapshot.profileId == _profileId) snapshot,
    ];
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Saved sessions',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (profileIds.isNotEmpty)
                    DropdownButton<String>(
                      key: const ValueKey('snapshot-profile'),
                      value: _profileId,
                      dropdownColor: AppColors.surface,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final profile in widget.profiles)
                          if (profileIds.contains(profile.id))
                            DropdownMenuItem(
                              value: profile.id,
                              child: Text(profile.name),
                            ),
                      ],
                      onChanged: (id) => setState(() => _profileId = id),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.muted,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Text(_error!, style: TextStyle(color: AppColors.danger))
              else if (snapshots == null)
                const Center(child: CircularProgressIndicator())
              else if (shown.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No saved sessions yet. Use "Save session state" in the '
                    'terminal tools to save one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _snapshotTile(shown[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _snapshotTile(SessionSnapshot snapshot) {
    final lines = snapshot.output.split('\n');
    final tail = lines.skip(lines.length > 3 ? lines.length - 3 : 0).join('\n');
    return Material(
      color: AppColors.terminal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('snapshot-${snapshot.id}'),
        onTap: () => Navigator.of(context).pop(snapshot),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snapshot.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    _formatTime(snapshot.savedAt),
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    iconSize: 18,
                    color: AppColors.muted,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _delete(snapshot),
                  ),
                ],
              ),
              Text(
                tail,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.muted,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
