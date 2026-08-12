import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'package:portix/src/domain/entities/rdp/index.dart';

class RdpWindowService {
  const RdpWindowService._();

  static const String windowType = 'portix_rdp_session';

  static Future<WindowController> openSession({
    required RdpProfile profile,
    required String sessionId,
  }) async {
    final arguments = jsonEncode({
      'type': windowType,
      'sessionId': sessionId,
      'profileId': profile.id,
      'profileName': profile.name,
      'host': profile.host,
      'port': profile.port,
      'desktopWidth': profile.desktopWidth,
      'desktopHeight': profile.desktopHeight,
    });

    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: arguments,
      ),
    );

    await controller.show();
    return controller;
  }
}
