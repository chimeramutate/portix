import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import 'rdp_session_window.dart';
import 'rdp_window_arguments.dart';

Future<bool> runPortixWindowIfNeeded() async {
  final controller = await WindowController.fromCurrentEngine();

  if (controller.arguments.isEmpty) {
    return false;
  }

  try {
    final arguments =
        RdpWindowArguments.fromJsonString(controller.arguments);

    runApp(RdpSessionWindow(arguments: arguments));
    return true;
  } on FormatException {
    return false;
  }
}
