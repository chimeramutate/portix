import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';

import '../../bloc/index.dart';
import '../../controller/index.dart';
import 'profile_card.dart';

enum _GalleryFilter { all, production, keyAuth, recent }

enum _ProfileViewMode { gallery, list }

enum _ProfileFileAction { importProfiles, exportProfiles }

class ProfileGallery extends StatefulWidget {
  const ProfileGallery({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  State<ProfileGallery> createState() => _ProfileGalleryState();
}

class _ProfileGalleryState extends State<ProfileGallery> {
  final ProfileFileController _profileFiles = const ProfileFileController();
  _GalleryFilter _filter = _GalleryFilter.all;
  _ProfileViewMode _viewMode = _ProfileViewMode.gallery;

  @override
  Widget build(BuildContext context) {
    final profiles = _visibleProfiles(widget.state);
    final session = context.watch<SshSessionBloc>().state;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final viewMode = mobile ? _ProfileViewMode.list : _viewMode;
        return Container(
          color: AppColors.bg,
          padding: EdgeInsets.all(mobile ? 12 : 20),
          child: Column(
            children: [
              _GalleryToolbar(
                filter: _filter,
                viewMode: viewMode,
                visibleCount: profiles.length,
                tags: widget.state.tags,
                selectedTag: widget.state.tagFilter,
                onFilterChanged: (filter) => setState(() => _filter = filter),
                onViewModeChanged: (mode) => setState(() => _viewMode = mode),
                onTagChanged: (tag) =>
                    context.read<SshWorkspaceBloc>().add(TagFilterChanged(tag)),
                onFileAction: (action) => _handleFileAction(action, profiles),
                showBackToSsh: session.canReturnToSsh,
                onBackToSsh: () => context.read<SshWorkspaceBloc>().add(
                  const NavigationChanged(WorkspaceView.remoteFolder),
                ),
              ),
              SizedBox(height: mobile ? 12 : 18),
              Expanded(
                child: profiles.isEmpty
                    ? const _EmptyProfileGallery()
                    : switch (viewMode) {
                        _ProfileViewMode.gallery => _ProfileGrid(
                          profiles: profiles,
                          selectedId: widget.state.selectedProfile?.id,
                        ),
                        _ProfileViewMode.list => _ProfileList(
                          profiles: profiles,
                          selectedId: widget.state.selectedProfile?.id,
                        ),
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  List<SshProfile> _visibleProfiles(SshWorkspaceState state) {
    final profiles = switch (_filter) {
      _GalleryFilter.all => state.filteredProfiles,
      _GalleryFilter.production =>
        state.filteredProfiles
            .where((profile) => profile.group.toLowerCase() == 'production')
            .toList(),
      _GalleryFilter.keyAuth =>
        state.filteredProfiles
            .where((profile) => profile.authMethod == AuthMethod.sshKey)
            .toList(),
      _GalleryFilter.recent =>
        state.filteredProfiles
            .where((profile) => profile.lastUsedLabel.trim().isNotEmpty)
            .toList(),
    };
    return profiles;
  }

  Future<void> _handleFileAction(
    _ProfileFileAction action,
    List<SshProfile> visibleProfiles,
  ) async {
    switch (action) {
      case _ProfileFileAction.importProfiles:
        await _importProfiles();
      case _ProfileFileAction.exportProfiles:
        await _exportProfiles(visibleProfiles);
    }
  }

  Future<void> _importProfiles() async {
    final pickResult = await _profileFiles.pickImportPath();
    if (!mounted) return;
    final path = switch (pickResult.status) {
      ProfilePathPickStatus.selected => pickResult.path,
      ProfilePathPickStatus.canceled => null,
      ProfilePathPickStatus.unavailable => await _showPathDialog(
        title: 'Import profiles',
        label: 'Profile file path',
        initialValue: _defaultImportPath(),
      ),
    };
    if (path == null || path.trim().isEmpty || !mounted) return;

    try {
      final profiles = await _profileFiles.importProfiles(
        path,
        existingIds: widget.state.profiles.map((profile) => profile.id).toSet(),
      );
      if (!mounted) return;
      if (profiles.isEmpty) {
        _showSnack('No profiles found in that file.');
        return;
      }

      // Filter out profiles that are already present by fingerprint
      // (username@host:port) to prevent duplicates even when IDs differ.
      final existingFingerprints = widget.state.profiles
          .map((p) => '${p.username}@${p.host}:${p.port}')
          .toSet();
      final newProfiles = profiles
          .where(
            (p) =>
                !existingFingerprints.contains('${p.username}@${p.host}:${p.port}'),
          )
          .toList();

      if (newProfiles.isEmpty) {
        _showSnack('All profiles already exist — nothing to import.');
        return;
      }
      final skipped = profiles.length - newProfiles.length;
      context.read<SshWorkspaceBloc>().add(ProfilesImported(newProfiles));
      final skippedNote = skipped > 0 ? ' ($skipped duplicate${skipped == 1 ? '' : 's'} skipped)' : '';
      _showSnack('Importing ${newProfiles.length} profile${newProfiles.length == 1 ? '' : 's'}$skippedNote...');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Import failed: $error');
    }
  }

  Future<void> _exportProfiles(List<SshProfile> visibleProfiles) async {
    final profiles = visibleProfiles.isEmpty
        ? widget.state.profiles
        : visibleProfiles;
    if (profiles.isEmpty) {
      _showSnack('No profiles to export.');
      return;
    }

    final pickResult = await _profileFiles.pickExportPath();
    if (!mounted) return;
    final path = switch (pickResult.status) {
      ProfilePathPickStatus.selected => pickResult.path,
      ProfilePathPickStatus.canceled => null,
      ProfilePathPickStatus.unavailable => await _showPathDialog(
        title: 'Export profiles',
        label: 'Export file path',
        initialValue: _defaultExportPath(),
      ),
    };
    if (path == null || path.trim().isEmpty || !mounted) return;

    try {
      await _profileFiles.exportProfiles(path, profiles);
      if (!mounted) return;
      _showSnack(
        'Exported ${profiles.length} profile${profiles.length == 1 ? '' : 's'} to local file.',
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('Export failed: $error');
    }
  }

  Future<String?> _showPathDialog({
    required String title,
    required String label,
    required String initialValue,
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: portixTitle(12),
            decoration: InputDecoration(labelText: label),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Use path'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.surfaceCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _defaultImportPath() {
    return _defaultExportPath();
  }

  String _defaultExportPath() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}${ProfileFileController.defaultFileName}';
  }
}

class _GalleryToolbar extends StatelessWidget {
  const _GalleryToolbar({
    required this.filter,
    required this.viewMode,
    required this.visibleCount,
    required this.tags,
    required this.selectedTag,
    required this.onFilterChanged,
    required this.onViewModeChanged,
    required this.onTagChanged,
    required this.onFileAction,
    required this.showBackToSsh,
    required this.onBackToSsh,
  });

  final _GalleryFilter filter;
  final _ProfileViewMode viewMode;
  final int visibleCount;
  final List<String> tags;
  final String selectedTag;
  final ValueChanged<_GalleryFilter> onFilterChanged;
  final ValueChanged<_ProfileViewMode> onViewModeChanged;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<_ProfileFileAction> onFileAction;
  final bool showBackToSsh;
  final VoidCallback onBackToSsh;

  @override
  Widget build(BuildContext context) {
    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterPill(
          label: 'All',
          selected: filter == _GalleryFilter.all,
          onTap: () => onFilterChanged(_GalleryFilter.all),
        ),
        _FilterPill(
          label: 'Production',
          selected: filter == _GalleryFilter.production,
          onTap: () => onFilterChanged(_GalleryFilter.production),
        ),
        _FilterPill(
          label: 'Key auth',
          selected: filter == _GalleryFilter.keyAuth,
          onTap: () => onFilterChanged(_GalleryFilter.keyAuth),
        ),
        _FilterPill(
          label: 'Recently used',
          selected: filter == _GalleryFilter.recent,
          onTap: () => onFilterChanged(_GalleryFilter.recent),
        ),
        AppPill(
          label: '$visibleCount shown',
          color: AppColors.muted,
          icon: Icons.circle,
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showBackToSsh) ...[
          AppButton(
            icon: Icons.terminal_rounded,
            label: 'Back to SSH',
            primary: true,
            onPressed: onBackToSsh,
          ),
        ],
        _TagFilterMenuButton(
          tags: tags,
          selectedTag: selectedTag,
          onChanged: onTagChanged,
        ),
        PopupMenuButton<_ProfileViewMode>(
          tooltip: 'Change profile view',
          color: AppColors.surfaceCard,
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          constraints: const BoxConstraints(minWidth: 150, maxWidth: 180),
          onSelected: onViewModeChanged,
          itemBuilder: (context) => const [
            PopupMenuItem(
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: 12),
              value: _ProfileViewMode.gallery,
              child: _MenuItem(icon: Icons.grid_view_rounded, label: 'Gallery'),
            ),
            PopupMenuItem(
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: 12),
              value: _ProfileViewMode.list,
              child: _MenuItem(icon: Icons.view_list_rounded, label: 'List'),
            ),
          ],
          child: _ToolbarMenuButton(
            icon: viewMode == _ProfileViewMode.gallery
                ? Icons.grid_view_rounded
                : Icons.view_list_rounded,
            label: viewMode == _ProfileViewMode.gallery ? 'Gallery' : 'List',
            iconOnly: true,
          ),
        ),
        PopupMenuButton<_ProfileFileAction>(
          tooltip: 'Import or export profiles',
          color: AppColors.surfaceCard,
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 210),
          onSelected: onFileAction,
          itemBuilder: (context) => const [
            PopupMenuItem(
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: 12),
              value: _ProfileFileAction.importProfiles,
              child: _MenuItem(
                icon: Icons.upload_file_rounded,
                label: 'Import profiles',
              ),
            ),
            PopupMenuItem(
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: 12),
              value: _ProfileFileAction.exportProfiles,
              child: _MenuItem(
                icon: Icons.file_download_outlined,
                label: 'Export profiles',
              ),
            ),
          ],
          child: const _ToolbarMenuButton(
            icon: Icons.upload_file_rounded,
            label: 'Import',
            iconOnly: true,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              filters,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: filters),
            const SizedBox(width: 12),
            actions,
          ],
        );
      },
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.cyan : AppColors.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AppPill(
          label: label,
          color: color,
          background: selected ? AppColors.cyan.withValues(alpha: .11) : null,
        ),
      ),
    );
  }
}

class _ToolbarMenuButton extends StatelessWidget {
  const _ToolbarMenuButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.cyan : AppColors.text;
    return Container(
      height: 34,
      width: iconOnly ? 42 : null,
      padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 14),
      decoration: BoxDecoration(
        color: active
            ? AppColors.cyan.withValues(alpha: .12)
            : AppColors.surfaceCard.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? AppColors.cyan : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          if (!iconOnly) ...[
            const SizedBox(width: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(13),
              ),
            ),
            const SizedBox(width: 7),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: active ? AppColors.cyan : AppColors.muted,
              size: 16,
            ),
          ],
        ],
      ),
    );
  }
}

class _TagFilterMenuButton extends StatelessWidget {
  const _TagFilterMenuButton({
    required this.tags,
    required this.selectedTag,
    required this.onChanged,
  });

  final List<String> tags;
  final String selectedTag;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = selectedTag.trim().isNotEmpty;
    return PopupMenuButton<String>(
      tooltip: active ? 'Filtered by #$selectedTag' : 'Filter by tag',
      enabled: tags.isNotEmpty || active,
      color: AppColors.surfaceCard,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(minWidth: 190, maxWidth: 260),
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          value: '',
          child: _MenuItem(
            icon: Icons.filter_alt_off_rounded,
            label: 'All tags',
            color: active ? AppColors.cyan : AppColors.muted,
          ),
        ),
        if (tags.isNotEmpty) const PopupMenuDivider(),
        for (final tag in tags)
          PopupMenuItem(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            value: tag,
            child: Row(
              children: [
                Icon(
                  tag == selectedTag
                      ? Icons.check_circle_rounded
                      : Icons.sell_outlined,
                  color: tag == selectedTag ? AppColors.green : AppColors.muted,
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '#$tag',
                    overflow: TextOverflow.ellipsis,
                    style: portixTitle(12),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: _ToolbarMenuButton(
        icon: Icons.sell_outlined,
        label: active ? '#$selectedTag' : 'Tags',
        active: active,
        iconOnly: true,
      ),
    );
  }
}

class _ProfileGrid extends StatelessWidget {
  const _ProfileGrid({required this.profiles, required this.selectedId});

  final List<SshProfile> profiles;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = _columnCount(constraints.maxWidth);
        return GridView.builder(
          itemCount: profiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            mainAxisExtent: 230,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final profile = profiles[index];
            return ProfileCard(
              profile: profile,
              selected: profile.id == selectedId,
            );
          },
        );
      },
    );
  }

  int _columnCount(double width) {
    if (width >= 1400) return 4;
    if (width >= 1000) return 3;
    if (width >= 700) return 2;
    return 1;
  }
}

class _ProfileList extends StatelessWidget {
  const _ProfileList({required this.profiles, required this.selectedId});

  final List<SshProfile> profiles;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: profiles.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final selected = profile.id == selectedId;
        final status = effectiveProfileStatus(profile);
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.read<SshWorkspaceBloc>().add(
                  ProfileSelected(profile.id),
                ),
                borderRadius: BorderRadius.circular(8),
                child: AppPanel(
                  padding: const EdgeInsets.all(12),
                  color: selected ? const Color(0xFF123455) : AppColors.surface,
                  borderColor: selected
                      ? AppColors.primaryBlue
                      : AppColors.border,
                  child: compact
                      ? _CompactProfileListRow(profile: profile, status: status)
                      : Row(
                          children: [
                            ProfileOsIcon(profile: profile, size: 34),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: _ListText(
                                title: profile.name.isEmpty
                                    ? 'new profile'
                                    : profile.name,
                                subtitle: profile.address,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: _ListText(
                                title: profile.group,
                                subtitle: profile.tags.take(2).join(', '),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: _ListText(
                                title: profile.authMethod == AuthMethod.sshKey
                                    ? 'Key auth'
                                    : 'Password',
                                subtitle: profile.credentialLabel.isEmpty
                                    ? 'No credential'
                                    : profile.credentialLabel,
                              ),
                            ),
                            AppPill(
                              label: statusLabelFor(status),
                              color: statusColorFor(status),
                            ),
                            const SizedBox(width: 10),
                            AppIconButton(
                              icon: Icons.terminal_rounded,
                              onPressed: () =>
                                  context.read<SshSessionBloc>().add(
                                    SshSessionOpenRequested(
                                      profile: profile,
                                      target: SshSessionTarget.remoteFolder,
                                    ),
                                  ),
                            ),
                            const SizedBox(width: 8),
                            AppIconButton(
                              icon: Icons.folder_copy_outlined,
                              onPressed: () =>
                                  context.read<SshSessionBloc>().add(
                                    SshSessionOpenRequested(
                                      profile: profile,
                                      target: SshSessionTarget.sftp,
                                    ),
                                  ),
                            ),
                            const SizedBox(width: 4),
                            _ListProfileMenu(profile: profile),
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CompactProfileListRow extends StatelessWidget {
  const _CompactProfileListRow({required this.profile, required this.status});

  final SshProfile profile;
  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProfileOsIcon(profile: profile, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: _ListText(
                title: profile.name.isEmpty ? 'new profile' : profile.name,
                subtitle: profile.address,
              ),
            ),
            AppPill(
              label: statusLabelFor(status),
              color: statusColorFor(status),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppPill(label: profile.group, color: AppColors.cyan),
            AppPill(
              label: profile.authMethod == AuthMethod.sshKey
                  ? 'Key auth'
                  : 'Password',
              color: AppColors.muted,
            ),
            AppButton(
              icon: Icons.terminal_rounded,
              label: 'SSH',
              onPressed: () => context.read<SshSessionBloc>().add(
                SshSessionOpenRequested(
                  profile: profile,
                  target: SshSessionTarget.remoteFolder,
                ),
              ),
            ),
            AppButton(
              icon: Icons.folder_copy_outlined,
              label: 'SFTP',
              onPressed: () => context.read<SshSessionBloc>().add(
                SshSessionOpenRequested(
                  profile: profile,
                  target: SshSessionTarget.sftp,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ListText extends StatelessWidget {
  const _ListText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, overflow: TextOverflow.ellipsis, style: portixTitle(13)),
          const SizedBox(height: 3),
          Text(
            subtitle.isEmpty ? '-' : subtitle,
            overflow: TextOverflow.ellipsis,
            style: portixMuted(11),
          ),
        ],
      ),
    );
  }
}

class _EmptyProfileGallery extends StatelessWidget {
  const _EmptyProfileGallery();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPanel(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, color: AppColors.muted, size: 24),
            const SizedBox(height: 10),
            Text('No profiles found', style: portixTitle(15)),
            const SizedBox(height: 4),
            Text(
              'Adjust the filters or import a Portix profile file.',
              textAlign: TextAlign.center,
              style: portixMuted(12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three-dot menu for the list-view row (same actions as the gallery card).
enum _ProfileAction { edit, duplicate, delete }

class _ListProfileMenu extends StatelessWidget {
  const _ListProfileMenu({required this.profile});
  final SshProfile profile;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ProfileAction>(
      tooltip: 'Profile actions',
      color: AppColors.surfaceCard,
      icon: const Icon(
        Icons.more_horiz_rounded,
        color: AppColors.muted,
        size: 20,
      ),
      onSelected: (action) {
        switch (action) {
          case _ProfileAction.edit:
            context.read<SshWorkspaceBloc>().add(
              ProfileEditRequested(profile.id),
            );
          case _ProfileAction.duplicate:
            context.read<SshWorkspaceBloc>().add(
              ProfileDuplicateRequested(profile.id),
            );
          case _ProfileAction.delete:
            context.read<SshWorkspaceBloc>().add(
              ProfileDeleted(profile.id),
            );
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _ProfileAction.edit,
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 17),
              SizedBox(width: 10),
              Text('Edit'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _ProfileAction.duplicate,
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 17),
              SizedBox(width: 10),
              Text('Duplicate'),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _ProfileAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 17),
              SizedBox(width: 10),
              Text('Delete'),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    this.color = AppColors.muted,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
