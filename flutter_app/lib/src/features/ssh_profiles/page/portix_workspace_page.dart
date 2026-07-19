import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/features/sftp/bloc/index.dart';
import 'package:portix/src/features/settings/page/setting_page.dart';
import 'package:portix/src/features/sftp/page/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';
import 'package:portix/src/features/ssh_sessions/page/index.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import '../bloc/index.dart';
import '../widget/form/index.dart';
import '../widget/gallery/index.dart';
import '../widget/index.dart';

class PortixWorkspacePage extends StatefulWidget {
  const PortixWorkspacePage({super.key});

  @override
  State<PortixWorkspacePage> createState() => _PortixWorkspacePageState();
}

class _PortixWorkspacePageState extends State<PortixWorkspacePage> {
  final Set<WorkspaceView> _visitedViews = {WorkspaceView.gallery};
  late final SftpWorkspaceBloc _sftpWorkspaceBloc;

  @override
  void initState() {
    super.initState();
    _sftpWorkspaceBloc = sl<SftpWorkspaceBloc>()
      ..add(const SftpProfilesRequested());
  }

  @override
  void dispose() {
    _sftpWorkspaceBloc.close();
    super.dispose();
  }

  int _viewIndex(WorkspaceView view) => WorkspaceView.values.indexOf(view);

  Widget _lazyView(WorkspaceView view, Widget child) {
    return _visitedViews.contains(view) ? child : const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SshWorkspaceBloc, SshWorkspaceState>(
          listenWhen: (previous, current) =>
              previous.message != current.message && current.message.isNotEmpty,
          listener: (context, state) => _showNotice(context, state.message),
        ),
        BlocListener<SshWorkspaceBloc, SshWorkspaceState>(
          listenWhen: (previous, current) =>
              previous.activeView != current.activeView &&
              current.activeView != WorkspaceView.remoteFolder,
          listener: (context, state) {
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
        BlocListener<SshSessionBloc, SshSessionState>(
          listenWhen: (previous, current) =>
              previous.message != current.message && current.message.isNotEmpty,
          listener: (context, state) => _showNotice(context, state.message),
        ),
        BlocListener<SshSessionBloc, SshSessionState>(
          listenWhen: (previous, current) =>
              previous.pendingTarget != current.pendingTarget &&
              current.pendingTarget != null,
          listener: (context, state) {
            context.read<SshWorkspaceBloc>().add(
              NavigationChanged(_viewForSessionTarget(state.pendingTarget!)),
            );
            context.read<SshSessionBloc>().add(
              const SshSessionNavigationConsumed(),
            );
          },
        ),
      ],
      child: BlocConsumer<SshWorkspaceBloc, SshWorkspaceState>(
        listenWhen: (previous, current) =>
            previous.activeView != current.activeView &&
            current.activeView == WorkspaceView.sftp,
        listener: (context, state) {
          _sftpWorkspaceBloc.add(const SftpProfilesRequested());
        },
        builder: (context, state) {
          _visitedViews.add(state.activeView);
          return BlocProvider.value(
            value: _sftpWorkspaceBloc,
            child: WorkspaceShell(
              state: state,
              child: IndexedStack(
                index: _viewIndex(state.activeView),
                children: [
                  _lazyView(WorkspaceView.gallery, const GalleryShell()),
                  _lazyView(WorkspaceView.form, const ProfileFormView()),
                  _lazyView(
                    WorkspaceView.remoteFolder,
                    const RemoteFolderPage(),
                  ),
                  _lazyView(WorkspaceView.sftp, const SftpWorkspacePage()),
                  _lazyView(WorkspaceView.settings, const SettingsView()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  WorkspaceView _viewForSessionTarget(SshSessionTarget target) {
    return switch (target) {
      SshSessionTarget.remoteFolder => WorkspaceView.remoteFolder,
      SshSessionTarget.sftp => WorkspaceView.sftp,
    };
  }

  void _showNotice(BuildContext context, String message) {
    final notice = _WorkspaceNotice.fromMessage(message);
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
                  message,
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
