import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';

import 'sftp_window_arguments.dart';

/// Opens SFTP sessions in detached child windows.
///
/// Mirrors [RdpWindowService] — the parent process serialises the profile
/// plus the current remote path into JSON arguments; the child engine reads
/// them via [MainWindowBootstrap.runPortixWindowIfNeeded] and renders an
/// [SftpSessionWindow].
class SftpWindowService {
  const SftpWindowService._();

  static const String windowType = 'portix_sftp_session';

  static Future<WindowController> openSession({
    required SshProfile profile,
    required String remotePath,
  }) async {
    final arguments = jsonEncode(
      SftpWindowArguments(profile: profile, remotePath: remotePath).toJson(),
    );

    final controller = await WindowController.create(
      WindowConfiguration(hiddenAtLaunch: true, arguments: arguments),
    );

    await controller.show();
    return controller;
  }
}
