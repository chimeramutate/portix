import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/features/sftp/page/index.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import '../bloc/index.dart';
import '../widget/form/index.dart';
import '../widget/gallery/index.dart';
import '../widget/remote/index.dart';
import '../widget/index.dart';

class PortixWorkspacePage extends StatefulWidget {
  const PortixWorkspacePage({super.key});

  @override
  State<PortixWorkspacePage> createState() => _PortixWorkspacePageState();
}

class _PortixWorkspacePageState extends State<PortixWorkspacePage> {
  final Set<WorkspaceView> _visitedViews = {WorkspaceView.gallery};

  int _viewIndex(WorkspaceView view) => WorkspaceView.values.indexOf(view);

  Widget _lazyView(WorkspaceView view, Widget child) {
    return _visitedViews.contains(view) ? child : const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SshWorkspaceBloc, SshWorkspaceState>(
      listener: (context, state) {
        if (state.message.isNotEmpty) {
          final notice = _WorkspaceNotice.fromMessage(state.message);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(notice.icon, color: notice.foreground, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.message,
                        style: TextStyle(
                          color: notice.foreground,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: notice.background,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: notice.border),
                ),
              ),
            );
        }
      },
      builder: (context, state) {
        _visitedViews.add(state.activeView);
        return WorkspaceShell(
          state: state,
          child: IndexedStack(
            index: _viewIndex(state.activeView),
            children: [
              _lazyView(WorkspaceView.gallery, const GalleryShell()),
              _lazyView(WorkspaceView.form, const ProfileFormView()),
              _lazyView(WorkspaceView.remoteFolder, const RemoteFolderView()),
              _lazyView(WorkspaceView.sftp, const SftpWorkspacePage()),
              _lazyView(WorkspaceView.settings, const _SettingsView()),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspaceNotice {
  const _WorkspaceNotice({
    required this.icon,
    required this.background,
    required this.border,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color border;
  final Color foreground;

  factory _WorkspaceNotice.fromMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('saved') || normalized.contains('verified')) {
      return const _WorkspaceNotice(
        icon: Icons.check_circle_outline_rounded,
        background: Color(0xFF0B3A27),
        border: AppColors.green,
        foreground: AppColors.green,
      );
    }
    if (normalized.contains('testing') || normalized.contains('saving')) {
      return const _WorkspaceNotice(
        icon: Icons.timelapse_rounded,
        background: Color(0xFF123455),
        border: AppColors.cyan,
        foreground: AppColors.cyan,
      );
    }
    return const _WorkspaceNotice(
      icon: Icons.error_outline_rounded,
      background: Color(0xFF3A1421),
      border: AppColors.danger,
      foreground: AppColors.danger,
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return const _UtilityView(
      icon: Icons.settings_outlined,
      title: 'Settings',
      subtitle:
          'Defaults for secure vault, terminal sessions, and desktop behaviour.',
      children: [
        _SettingsTile(
          title: 'Require vault unlock before connect',
          value: true,
        ),
        _SettingsTile(
          title: 'Mount remote folder after SSH opens',
          value: true,
        ),
        _SettingsTile(
          title: 'Keep terminal input direct by default',
          value: true,
        ),
        _SettingsTile(title: 'Use compact profile cards', value: true),
      ],
    );
  }
}

class _UtilityView extends StatelessWidget {
  const _UtilityView({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.cyan, size: 28),
              const SizedBox(height: 10),
              Text(title, style: portixTitle(28)),
              const SizedBox(height: 8),
              Text(subtitle, style: portixMuted(14)),
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.title, required this.value});
  final String title;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: Text(title, style: portixTitle(15))),
          Switch(value: value, onChanged: (_) {}),
        ],
      ),
    );
  }
}
