import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import 'package:portix/src/domain/entities/rdp/index.dart';

class RdpWindowService {
  const RdpWindowService._();

  static const String windowType = 'portix_rdp_session';
  static final List<WindowController> _openControllers = <WindowController>[];

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
    _openControllers.add(controller);
    return controller;
  }

  static Future<void> closeAllSessions() async {
    final controllers = await WindowController.getAll();
    final targets = <String, WindowController>{
      for (final controller in _openControllers) controller.windowId: controller,
      for (final controller in controllers.where(_isRdpSessionWindow))
        controller.windowId: controller,
    }.values;

    for (final controller in targets) {
      try {
        await controller.close();
      } on MissingPluginException {
        await controller.hide();
      } catch (_) {
        await controller.hide();
      }
    }

    _openControllers.clear();
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
