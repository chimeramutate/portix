import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/sftp/bloc/index.dart';
import 'package:portix/src/features/sftp/page/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';

import 'sftp_window_arguments.dart';

/// Home widget for a detached SFTP child-window.
///
/// Bootstraps a fresh [SftpWorkspaceBloc], loads the profiles from the
/// repository, and renders a full [SftpWorkspacePage] that auto-connects
/// to the profile and opens at the remote path captured at duplication
/// time (see [SftpWindowArguments]).
class SftpSessionWindow extends StatefulWidget {
  const SftpSessionWindow({super.key, required this.arguments});

  final SftpWindowArguments arguments;

  @override
  State<SftpSessionWindow> createState() => _SftpSessionWindowState();
}

class _SftpSessionWindowState extends State<SftpSessionWindow> {
  late final SftpWorkspaceBloc _sftpWorkspaceBloc;

  @override
  void initState() {
    super.initState();
    _sftpWorkspaceBloc = sl<SftpWorkspaceBloc>()
      ..add(const SftpProfilesRequested())
      ..add(SftpProfileSelected(widget.arguments.profile));
  }

  @override
  void dispose() {
    _sftpWorkspaceBloc.close();
    super.dispose();
  }

  Future<void> _closeThisWindow() async {
    try {
      final controller = await WindowController.fromCurrentEngine();
      await controller.invokeMethod('window_close');
    } catch (_) {
      try {
        final controller = await WindowController.fromCurrentEngine();
        await controller.hide();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
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
    return MaterialApp(
      title: 'Portix SFTP - ${arguments.profile.name}',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = media.textScaler.scale(1).clamp(0.85, 1.05);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: SftpSessionWindow(arguments: arguments),
    );
  }
}
