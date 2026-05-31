import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/widgets/index.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import '../bloc/index.dart';

class WorkspaceTopBar extends StatelessWidget {
  const WorkspaceTopBar({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: switch (state.activeView) {
        WorkspaceView.form => const _FormTopBar(),
        WorkspaceView.sftp => _SftpTopBar(state: state),
        WorkspaceView.remoteFolder => _RemoteTopBar(state: state),
        WorkspaceView.settings => const _SimpleTopBar(title: 'Settings'),
        _ => _GalleryTopBar(state: state),
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
    return Row(
      children: [
        const Text(
          'Portix',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: AppTextField(
                controller: _search,
                label: '',
                hint: 'Search profile, host, tag, or group',
                icon: Icons.search_rounded,
                onChanged: (value) =>
                    context.read<SshWorkspaceBloc>().add(SearchChanged(value)),
              ),
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
        AppButton(
          icon: Icons.add_rounded,
          label: 'New SSH Profile',
          primary: true,
          onPressed: () =>
              context.read<SshWorkspaceBloc>().add(const NewProfileRequested()),
        ),
      ],
    );
  }
}

class _FormTopBar extends StatelessWidget {
  const _FormTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Portix',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 28),
        Container(
          height: 38,
          width: 440,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.format_list_bulleted_rounded,
                color: AppColors.muted,
                size: 18,
              ),
              SizedBox(width: 10),
              Text(
                'List SSH Profiles',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 12),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 18,
              ),
              SizedBox(width: 12),
              Text(
                'New SSH Profile',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        const AppPill(
          label: 'Unsaved draft',
          color: AppColors.amber,
          background: Color(0xFF3C2B10),
        ),
        const SizedBox(width: 10),
        AppButton(
          icon: Icons.monitor_heart_outlined,
          label: 'Test Connection',
          onPressed: () => context.read<SshWorkspaceBloc>().add(
            const ProfileTestRequested(),
          ),
        ),
        const SizedBox(width: 10),
        AppButton(
          icon: Icons.save_outlined,
          label: 'Save Profile',
          primary: true,
          onPressed: () =>
              context.read<SshWorkspaceBloc>().add(const ProfileSaved()),
        ),
      ],
    );
  }
}

class _SftpTopBar extends StatelessWidget {
  const _SftpTopBar({required this.state});
  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final profile = state.activeTerminalProfile;
    final hasSession = state.hasActiveTerminalSession && profile != null;
    final address = profile?.address;

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
                  ? '$address · ${state.activeTerminalDefaultPath}'
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
        AppButton(
          icon: Icons.add_rounded,
          label: 'New Tab',
          onPressed: hasSession ? () {} : null,
        ),
        const SizedBox(width: 10),
        AppButton(
          icon: Icons.logout_rounded,
          label: 'Logout',
          onPressed: () => context.read<SshWorkspaceBloc>().add(
            const NavigationChanged(WorkspaceView.gallery),
          ),
        ),
      ],
    );
  }
}

class _RemoteTopBar extends StatelessWidget {
  const _RemoteTopBar({required this.state});
  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final profile = state.activeTerminalProfile;
    final hasSession = state.hasActiveTerminalSession && profile != null;
    final address = profile?.address;

    return Row(
      children: [
        const _Brand(),
        const SizedBox(width: 18),
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: _ConnectionBadge(
              icon: Icons.dns_rounded,
              iconColor: hasSession ? AppColors.green : AppColors.muted,
              title: profile?.name ?? 'Remote Folder',
              subtitle: hasSession
                  ? '$address · ${state.activeTerminalDefaultPath}'
                  : 'No active terminal session',
              trailing: AppPill(
                label: hasSession ? 'Connected' : 'Offline',
                color: hasSession ? AppColors.green : AppColors.muted,
                background: hasSession
                    ? const Color(0xFF0B3A27)
                    : AppColors.surface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
      ],
    );
  }
}

class _SimpleTopBar extends StatelessWidget {
  const _SimpleTopBar({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _Brand(),
        const SizedBox(width: 28),
        Text(title, style: portixTitle(16)),
      ],
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
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Flexible(
              flex: 2,
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(13),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 3,
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: portixMuted(),
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
        fontSize: 22,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
