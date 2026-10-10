import 'dart:io';

import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;

import '../../controller/quick_connect.dart';
import 'terminal_workspace_view.dart';

/// Searchable profile picker used by the terminal's "new tab" button.
class SessionProfilePickerDialog extends StatefulWidget {
  const SessionProfilePickerDialog({
    required this.profiles,
    super.key,
    required this.activeProfileId,
    this.localUser,
  });

  final List<domain.SshProfile> profiles;
  final String? activeProfileId;

  /// User for a quick connect typed without `user@`; defaults to the local
  /// login, as OpenSSH does.
  final String? localUser;

  @override
  State<SessionProfilePickerDialog> createState() =>
      _SessionProfilePickerDialogState();
}

class _SessionProfilePickerDialogState
    extends State<SessionProfilePickerDialog> {
  late final TextEditingController _searchController;
  late final ScrollController _listController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _listController = ScrollController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  List<domain.SshProfile> get _filteredProfiles {
    final normalized = _searchController.text.trim().toLowerCase();
    if (normalized.isEmpty) return widget.profiles;
    return widget.profiles
        .where((profile) {
          final text = [
            profile.name,
            profile.host,
            profile.username,
            profile.group,
            ...profile.tags,
          ].join(' ').toLowerCase();
          return text.contains(normalized);
        })
        .toList(growable: false);
  }

  QuickConnectTarget? get _quickTarget => parseQuickConnect(
    _searchController.text,
    defaultUser:
        widget.localUser ??
        Platform.environment['USER'] ??
        Platform.environment['USERNAME'] ??
        'root',
  );

  /// The profile to open for [target]: an existing one with the same
  /// user, host and port, or a new quick connect profile.
  domain.SshProfile _quickProfile(QuickConnectTarget target) =>
      widget.profiles
          .where(
            (p) =>
                p.host == target.host &&
                p.port == target.port &&
                p.username == target.user,
          )
          .firstOrNull ??
      quickConnectProfile(target);

  void _submitSearch() {
    final target = _quickTarget;
    final profile = target != null
        ? _quickProfile(target)
        : _filteredProfiles.firstOrNull;
    if (profile != null) Navigator.of(context).pop(profile);
  }

  Widget _quickConnectOption(QuickConnectTarget target) {
    final profile = _quickProfile(target);
    final existing = widget.profiles.any((p) => p.id == profile.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.cyan),
        ),
        child: ListTile(
          key: const ValueKey('quick-connect-option'),
          dense: true,
          leading: Icon(Icons.bolt_rounded, color: AppColors.cyan),
          title: Text(
            'Connect to ${quickConnectLabel(target)}',
            style: portixTitle(13),
          ),
          subtitle: Text(
            existing
                ? 'Opens saved profile "${profile.name}"'
                : 'Press Enter. Saved under "Quick connect"; the password '
                      'is asked once and kept in the keychain.',
            style: portixMuted(11),
          ),
          onTap: () => Navigator.of(context).pop(profile),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickTarget = _quickTarget;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxListHeight = (screenHeight * 0.55).clamp(260.0, 520.0);
    final filteredProfiles = _filteredProfiles;
    final hasSearch = _searchController.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.add_rounded, color: AppColors.cyan),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New SSH session', style: portixTitle(18)),
                        const SizedBox(height: 2),
                        Text(
                          hasSearch
                              ? '${filteredProfiles.length} of ${widget.profiles.length} profiles match your search'
                              : '${widget.profiles.length} connectable profiles available',
                          style: portixMuted(11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: TextField(
                  key: const ValueKey('new-session-search'),
                  controller: _searchController,
                  autofocus: true,
                  onSubmitted: (_) => _submitSearch(),
                  onChanged: (_) {
                    if (_listController.hasClients) {
                      _listController.jumpTo(0);
                    }
                    setState(() {});
                  },
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search profiles or type user@host[:port]',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: AppColors.muted,
                      size: 19,
                    ),
                    suffixIcon: hasSearch
                        ? IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              if (_listController.hasClients) {
                                _listController.jumpTo(0);
                              }
                              setState(() {});
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: AppColors.muted,
                              size: 18,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (quickTarget != null) _quickConnectOption(quickTarget),
              if (widget.activeProfileId != null && !hasSearch)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppPill(
                    label: 'Current session profile highlighted below',
                    color: AppColors.cyan,
                    icon: Icons.radio_button_checked_rounded,
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListHeight),
                child: filteredProfiles.isEmpty && quickTarget != null
                    ? const SizedBox.shrink()
                    : filteredProfiles.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              color: AppColors.muted,
                              size: 22,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No matching profiles found',
                              style: portixTitle(13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Try another keyword for host, username, group, or tag.',
                              textAlign: TextAlign.center,
                              style: portixMuted(11),
                            ),
                          ],
                        ),
                      )
                    : Scrollbar(
                        controller: _listController,
                        interactive: false,
                        thumbVisibility: filteredProfiles.length > 5,
                        child: ListView.separated(
                          controller: _listController,
                          shrinkWrap: true,
                          itemCount: filteredProfiles.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final profile = filteredProfiles[index];
                            final isActiveProfile =
                                profile.id == widget.activeProfileId;
                            return SessionProfileOption(
                              profile: profile,
                              highlighted: isActiveProfile,
                              subtitleLabel: isActiveProfile
                                  ? 'Current profile'
                                  : null,
                              onSelected: () =>
                                  Navigator.of(context).pop(profile),
                            );
                          },
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
