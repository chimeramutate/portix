import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/side_panel.dart';
import 'package:portix/src/features/kubernetes/kubernetes_page.dart';
import 'package:portix/src/features/rdp/widget/rdp_groups_panel.dart';
import 'package:portix/src/features/rdp/widget/rdp_workspace_view.dart';
import 'package:portix/src/features/sftp/bloc/sftp_workspace_bloc.dart';
import 'package:portix/src/features/sftp/page/sftp_workspace_page.dart';
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';
import 'package:portix/src/features/ssh_sessions/page/remote_folder_page.dart';

import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
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
  final ConnectionManager _connectionManager = sl<ConnectionManager>();

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
    final sshSessionBloc = context.read<SshSessionBloc>();
    return BlocProvider.value(
      value: sshSessionBloc,
      child: MultiBlocListener(
        listeners: [
          BlocListener<SshWorkspaceBloc, SshWorkspaceState>(
            listenWhen: (previous, current) =>
                previous.message != current.message &&
                current.message.isNotEmpty,
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
            bloc: sshSessionBloc,
            listenWhen: (previous, current) =>
                previous.message != current.message &&
                current.message.isNotEmpty,
            listener: (context, state) => _showNotice(context, state.message),
          ),
          BlocListener<SshSessionBloc, SshSessionState>(
            bloc: sshSessionBloc,
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
              child: ListenableBuilder(
                listenable: Listenable.merge([_connectionManager, kubeTabs]),
                builder: (context, child) => WorkspaceShell(
                  state: state,
                  panel: _panelFor(state),
                  terminalsOpen: _connectionManager.sessions.isNotEmpty,
                  child: child!,
                ),
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
                    _lazyView(WorkspaceView.rdp, const RdpWorkspaceView()),
                    _lazyView(WorkspaceView.kubernetes, const KubernetesPage()),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The side panel next to the rail, or null for views without one.
  Widget? _panelFor(SshWorkspaceState state) => switch (state.activeView) {
    WorkspaceView.gallery => SidePanel(
      title: 'Groups',
      child: GroupSidebar(state: state),
    ),
    WorkspaceView.rdp => const SidePanel(
      title: 'Groups',
      child: RdpGroupsPanel(),
    ),
    // Sections mean nothing until the tab has connected to its cluster.
    WorkspaceView.kubernetes when kubeTabs.current.connected => const SidePanel(
      title: 'Kubernetes',
      child: KubeSectionsPanel(),
    ),
    _ => null,
  };

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
                    fontWeight: FontWeight.w600,
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
      return _WorkspaceNotice(
        icon: Icons.check_circle_outline_rounded,
        background: AppColors.greenTint,
        border: AppColors.green,
        foreground: AppColors.green,
      );
    }
    if (normalized.contains('testing') || normalized.contains('saving')) {
      return _WorkspaceNotice(
        icon: Icons.timelapse_rounded,
        background: AppColors.selectedSoft,
        border: AppColors.accent,
        foreground: AppColors.accent,
      );
    }
    return _WorkspaceNotice(
      icon: Icons.error_outline_rounded,
      background: AppColors.dangerTint,
      border: AppColors.danger,
      foreground: AppColors.danger,
    );
  }
}
