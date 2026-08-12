import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';

import 'rdp_session_window.dart';
import 'rdp_window_arguments.dart';

Future<bool> runPortixWindowIfNeeded() async {
  final controller = await WindowController.fromCurrentEngine();

  if (controller.arguments.isEmpty) {
    return false;
  }

  try {
    final arguments = RdpWindowArguments.fromJsonString(controller.arguments);

    runApp(PortixRdpWindowApp(arguments: arguments));
    return true;
  } on FormatException {
    return false;
  }
}

class PortixRdpWindowApp extends StatelessWidget {
  const PortixRdpWindowApp({super.key, required this.arguments});

  final RdpWindowArguments arguments;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portix RDP - ${arguments.profileName}',
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
      home: RdpSessionWindow(arguments: arguments),
    );
  }
}
