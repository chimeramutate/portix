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
      'profile': _profileToMap(profile),
    });

    final controller = await WindowController.create(
      WindowConfiguration(hiddenAtLaunch: true, arguments: arguments),
    );

    await controller.show();
    return controller;
  }

  static Future<void> closeAllSessions() async {
    // Only windows that still exist: one the user already closed makes the
    // plugin throw "failed to find target window".
    final controllers = await WindowController.getAll();

    for (final controller in controllers.where(_isRdpSessionWindow)) {
      try {
        await controller.close();
      } catch (_) {
        try {
          await controller.hide();
        } catch (_) {
          // Window went away between getAll() and now.
        }
      }
    }
  }

  static bool _isRdpSessionWindow(WindowController controller) {
    try {
      final payload = jsonDecode(controller.arguments);
      return payload is Map<String, dynamic> && payload['type'] == windowType;
    } catch (_) {
      return false;
    }
  }

  static Map<String, Object?> _profileToMap(RdpProfile profile) {
    return {
      'id': profile.id,
      'name': profile.name,
      'host': profile.host,
      'port': profile.port,
      'username': profile.username,
      'password': profile.password,
      'domain': profile.domain,
      'group': profile.group,
      'tags': profile.tags,
      'color': profile.color.name,
      'desktopWidth': profile.desktopWidth,
      'desktopHeight': profile.desktopHeight,
      'fullScreen': profile.fullScreen,
      'redirectDrives': profile.redirectDrives,
      'redirectClipboard': profile.redirectClipboard,
      'localSharePath': profile.localSharePath,
      'localShareName': profile.localShareName,
      'alternateShell': profile.alternateShell,
      'enableCredSsp': profile.enableCredSsp,
      'sourceRdpFilePath': profile.sourceRdpFilePath,
      'status': profile.status.name,
      'lastUsedLabel': profile.lastUsedLabel,
    };
  }
}

extension on WindowController {
  Future<void> close() {
    return invokeMethod('window_close');
  }
}
