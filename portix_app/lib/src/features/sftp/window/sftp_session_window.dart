import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/sftp/bloc/sftp_workspace_bloc.dart';
import 'package:portix/src/features/sftp/page/sftp_workspace_page.dart';
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';
import 'package:window_manager/window_manager.dart';

import 'sftp_window_arguments.dart';

/// Home widget for a detached SFTP child window: loads the profiles and
/// auto-connects at the remote path captured when it was duplicated.
class SftpSessionWindow extends StatefulWidget {
  const SftpSessionWindow({super.key, required this.arguments});

  final SftpWindowArguments arguments;

  @override
  State<SftpSessionWindow> createState() => _SftpSessionWindowState();
}

class _SftpSessionWindowState extends State<SftpSessionWindow>
    with WindowListener {
  late final SftpWorkspaceBloc _sftpWorkspaceBloc;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _sftpWorkspaceBloc = sl<SftpWorkspaceBloc>()
      ..add(const SftpProfilesRequested())
      ..add(SftpProfileSelected(widget.arguments.profile));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _sftpWorkspaceBloc.close();
    super.dispose();
  }

  // Title-bar close (Linux only; elsewhere the plugin never emits it here).
  @override
  void onWindowClose() => _closeThisWindow();

  /// Drops the workspace (its dispose ends the SFTP connections) and hides
  /// the window rather than destroying it; see RdpSessionWindow.
  Future<void> _closeThisWindow() async {
    if (_closed || !mounted) return;
    setState(() => _closed = true);
    try {
      final controller = await WindowController.fromCurrentEngine();
      await controller.hide();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();

    return PopScope(
      onPopInvokedWithResult: (_, __) => _closeThisWindow(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _sftpWorkspaceBloc),
          BlocProvider(create: (_) => sl<SshSessionBloc>()),
        ],
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: SftpWorkspacePage(
            initialProfile: widget.arguments.profile,
            initialRemotePath: widget.arguments.remotePath,
          ),
        ),
      ),
    );
  }
}

/// Stateless MaterialApp wrapper for the SFTP child-window, mirroring
/// [PortixRdpWindowApp].
class PortixSftpWindowApp extends StatelessWidget {
  const PortixSftpWindowApp({super.key, required this.arguments});

  final SftpWindowArguments arguments;

  @override
  Widget build(BuildContext context) {
    return FollowSystemBrightness(
      child: MaterialApp(
        title: 'Portix SFTP - ${arguments.profile.name}',
        debugShowCheckedModeBanner: false,
        // Light or dark as the OS is set; there is no in-app switch.
        theme: appLightTheme,
        darkTheme: appTheme,
        themeMode: ThemeMode.system,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final scale = media.textScaler.scale(1).clamp(0.85, 1.05);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: SftpSessionWindow(arguments: arguments),
      ),
    );
  }
}
