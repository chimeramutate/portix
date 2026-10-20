import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:portix/src/core/theme/app_theme.dart';

import 'package:portix/src/features/rdp/service/rdp_window_service.dart';
import 'package:portix/src/features/rdp/window/rdp_session_window.dart';
import 'package:portix/src/features/rdp/window/rdp_window_arguments.dart';
import 'package:portix/src/features/sftp/window/sftp_session_window.dart';
import 'package:portix/src/features/sftp/window/sftp_window_arguments.dart';
import 'package:portix/src/features/sftp/window/sftp_window_service.dart';

/// If this engine was launched as a child window (RDP or SFTP session),
/// parse the arguments and bootstrap the appropriate app.  Returns `true`
/// when a child window was recognised so [main] can short-circuit.
Future<bool> runPortixWindowIfNeeded() async {
  final controller = await WindowController.fromCurrentEngine();

  if (controller.arguments.isEmpty) {
    return false;
  }

  // Linux: never let GTK destroy a child window. Tearing down its engine can
  // crash Flutter's task runner, so the windows hide themselves instead
  // (window_manager is registered for child windows in my_application.cc).
  if (Platform.isLinux) {
    await windowManager.setPreventClose(true);
  }

  final payload = jsonDecode(controller.arguments) as Map<String, dynamic>?;
  final windowType = payload?['type'] as String?;

  switch (windowType) {
    case RdpWindowService.windowType:
      final arguments = RdpWindowArguments.fromJsonString(controller.arguments);
      runApp(PortixRdpWindowApp(arguments: arguments));
      return true;

    case SftpWindowService.windowType:
      final arguments = SftpWindowArguments.fromJsonString(
        controller.arguments,
      );
      runApp(PortixSftpWindowApp(arguments: arguments));
      return true;

    default:
      return false;
  }
}

class PortixRdpWindowApp extends StatelessWidget {
  const PortixRdpWindowApp({super.key, required this.arguments});

  final RdpWindowArguments arguments;

  @override
  Widget build(BuildContext context) {
    return FollowSystemBrightness(
      child: MaterialApp(
        title: 'Portix RDP - ${arguments.profileName}',
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
        home: RdpSessionWindow(arguments: arguments),
      ),
    );
  }
}
