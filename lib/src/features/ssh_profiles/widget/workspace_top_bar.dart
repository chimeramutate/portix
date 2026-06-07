import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/features/sftp/bloc/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import '../bloc/index.dart';

class WorkspaceTopBar extends StatelessWidget {
  const WorkspaceTopBar({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactForm =
            state.activeView == WorkspaceView.form &&
            constraints.maxWidth < 1240;
        final mobile = constraints.maxWidth < 720;
        return Container(
          height: mobile
              ? state.activeView == WorkspaceView.gallery
                    ? 112
                    : state.activeView == WorkspaceView.form
                    ? 128
                    : 86
              : compactForm
              ? 100
              : 64,
          padding: EdgeInsets.symmetric(
            horizontal: mobile || compactForm ? 12 : 16,
            vertical: mobile || compactForm ? 8 : 0,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surfaceDark,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: switch (state.activeView) {
            WorkspaceView.form => const _FormTopBar(),
            WorkspaceView.sftp => _SftpTopBar(state: state),
            WorkspaceView.remoteFolder => const _RemoteTopBar(),
            WorkspaceView.settings => const _SimpleTopBar(title: 'Settings'),
            _ => _GalleryTopBar(state: state),
          },
        );
      },
    );
  }
}

class _GalleryTopBar extends StatefulWidget {
  const _GalleryTopBar({required this.state});
  final SshWorkspaceState state;

  @override
  State<_GalleryTopBar> createState() => _GalleryTopBarState();
}

class _GalleryTopBarState extends State<_GalleryTopBar> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.state.searchQuery);
  }

  @override
  void didUpdateWidget(covariant _GalleryTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_search.text != widget.state.searchQuery) {
      _search.text = widget.state.searchQuery;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 720;
        final brand = const Text(
          'Portix',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        );
        final search = SizedBox(
          height: 40,
          child: AppTextField(
            controller: _search,
            label: '',
            hint: 'Search profile, host, tag, or group',
            icon: Icons.search_rounded,
            onChanged: (value) =>
                context.read<SshWorkspaceBloc>().add(SearchChanged(value)),
          ),
        );
        final newButton = mobile
            ? AppIconButton(
                icon: Icons.add_rounded,
                onPressed: () => context.read<SshWorkspaceBloc>().add(
                  const NewProfileRequested(),
                ),
              )
            : AppButton(
                icon: Icons.add_rounded,
                label: 'New SSH Profile',
                primary: true,
                onPressed: () => context.read<SshWorkspaceBloc>().add(
                  const NewProfileRequested(),
                ),
              );

        if (mobile) {
          return Column(
            children: [
              Row(
                children: [
                  brand,
                  const Spacer(),
                  const AppPill(
                    label: 'Vault unlocked',
                    color: AppColors.green,
                    background: Color(0xFF0B3A27),
                  ),
                  const SizedBox(width: 8),
                  newButton,
                ],
              ),
              const SizedBox(height: 8),
              search,
            ],
          );
        }

        return Row(
          children: [
            brand,
            const SizedBox(width: 24),
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: search,
                ),
              ),
            ),
            if (MediaQuery.sizeOf(context).width > 980) ...[
              const SizedBox(width: 12),
              const AppPill(
                label: 'Vault unlocked',
                color: AppColors.green,
                background: Color(0xFF0B3A27),
              ),
            ],
            const SizedBox(width: 12),
            newButton,
          ],
        );
      },
    );
  }
}

class _MobilePageTopBar extends StatelessWidget {
  const _MobilePageTopBar({
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.cyan, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(15),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(11),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

class _FormTopBar extends StatelessWidget {
  const _FormTopBar();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1240;
        final veryCompact = constraints.maxWidth < 760;
        final breadcrumb = _FormBreadcrumb(compact: veryCompact);
        final status = const AppPill(
          label: 'Unsaved draft',
          color: AppColors.amber,
          background: Color(0xFF3C2B10),
        );
        final actions = Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            AppButton(
              icon: Icons.monitor_heart_outlined,
              label: veryCompact ? 'Test' : 'Test Connection',
              onPressed: () => context.read<SshWorkspaceBloc>().add(
                const ProfileTestRequested(),
              ),
            ),
            AppButton(
              icon: Icons.save_outlined,
              label: veryCompact ? 'Save' : 'Save Profile',
              primary: true,
              onPressed: () =>
                  context.read<SshWorkspaceBloc>().add(const ProfileSaved()),
            ),
          ],
        );

        if (compact) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const _Brand(),
                  SizedBox(width: veryCompact ? 12 : 20),
                  Expanded(child: breadcrumb),
                  if (!veryCompact) ...[const SizedBox(width: 10), status],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (veryCompact) status,
                  if (veryCompact) const SizedBox(width: 10),
                  const Spacer(),
                  actions,
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            const _Brand(),
            const SizedBox(width: 28),
            Expanded(child: breadcrumb),
            const SizedBox(width: 12),
            status,
            const SizedBox(width: 10),
            actions,
          ],
        );
      },
    );
  }
}

class _FormBreadcrumb extends StatelessWidget {
  const _FormBreadcrumb({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      constraints: const BoxConstraints(maxWidth: 760),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.format_list_bulleted_rounded,
            color: AppColors.muted,
            size: 16,
          ),
          const SizedBox(width: 10),
          if (!compact)
            Flexible(
              child: Text(
                'List SSH Profiles',
                overflow: TextOverflow.ellipsis,
                style: portixMuted().copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          if (!compact) ...[
            const SizedBox(width: 12),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 18,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              'New SSH Profile',
              overflow: TextOverflow.ellipsis,
              style: portixTitle(14),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SftpTopBar extends StatelessWidget {
  const _SftpTopBar({required this.state});
  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SshSessionBloc>().state;
    final sftpState = context.watch<SftpWorkspaceBloc>().state;
    final profile =
        sftpState.selectedProfile ?? session.profileFrom(state.profiles);
    final hasSession =
        sftpState.selectedProfile != null ||
        (session.hasActiveSession && profile != null);
    final address = profile?.address;
    final remotePath = sftpState.selectedProfile == null
        ? session.defaultPathFor(state.profiles)
        : sftpState.selectedRemotePath;

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 720;
        final clearProfile = sftpState.selectedProfile != null
            ? () => context.read<SftpWorkspaceBloc>().add(
                const SftpProfileCleared(),
              )
            : null;
        if (mobile) {
          return _MobilePageTopBar(
            icon: Icons.folder_open_rounded,
            title: profile?.name ?? 'SFTP Workspace',
            subtitle: hasSession
                ? '$address · $remotePath'
                : 'Select or activate a terminal session',
            trailing: clearProfile == null
                ? null
                : AppIconButton(
                    icon: Icons.swap_horiz_rounded,
                    onPressed: clearProfile,
                  ),
          );
        }

        return Row(
          children: [
            const _Brand(),
            const SizedBox(width: 18),
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: _ConnectionBadge(
                  icon: Icons.folder_open_rounded,
                  iconColor: hasSession ? AppColors.green : AppColors.muted,
                  title: profile?.name ?? 'SFTP Workspace',
                  subtitle: hasSession
                      ? '$address · $remotePath'
                      : 'Select or activate a terminal session',
                  trailing: AppPill(
                    label: hasSession ? 'Ready' : 'No session',
                    color: hasSession ? AppColors.green : AppColors.muted,
                    background: hasSession
                        ? const Color(0xFF0B3A27)
                        : AppColors.surface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            if (clearProfile != null)
              AppButton(
                icon: Icons.swap_horiz_rounded,
                label: 'Change profile',
                onPressed: clearProfile,
              )
            else
              AppButton(
                icon: Icons.list_alt_rounded,
                label: 'SSH profiles',
                onPressed: () => context.read<SshWorkspaceBloc>().add(
                  const NavigationChanged(WorkspaceView.gallery),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RemoteTopBar extends StatelessWidget {
  const _RemoteTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(children: [const _Brand(), const Spacer()]);
  }
}

class _SimpleTopBar extends StatelessWidget {
  const _SimpleTopBar({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return _MobilePageTopBar(
            icon: Icons.settings_outlined,
            title: title,
            subtitle: 'Portix preferences',
          );
        }
        return Row(
          children: [
            const _Brand(),
            const SizedBox(width: 28),
            Text(title, style: portixTitle(16)),
          ],
        );
      },
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.iconColor = AppColors.green,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, minHeight: 38),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(12),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 3,
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: portixMuted(11),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Portix',
      style: TextStyle(
        color: AppColors.text,
        fontSize: 19,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
