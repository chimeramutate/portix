import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';

import 'sftp_window_arguments.dart';

/// Opens SFTP sessions in detached child windows, like [RdpWindowService]:
/// the profile and remote path travel as JSON window arguments.
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
