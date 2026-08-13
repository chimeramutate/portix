import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/features/rdp/page/rdp_session_page.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';

import 'rdp_window_arguments.dart';

class RdpSessionWindow extends StatefulWidget {
  const RdpSessionWindow({super.key, required this.arguments});

  final RdpWindowArguments arguments;

  @override
  State<RdpSessionWindow> createState() => _RdpSessionWindowState();
}

class _RdpSessionWindowState extends State<RdpSessionWindow> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Child window has its own Flutter engine.
      await RdpBackendService.initDev();
      sl<RdpBackendService>().attachExistingSession(
        profileId: widget.arguments.profileId,
        sessionId: widget.arguments.sessionId,
      );

      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);

      // Auto-close window after showing the error briefly.
      await Future<void>.delayed(const Duration(seconds: 3));
      await _closeThisWindow();
    }
  }

  /// Closes this OS-level window via desktop_multi_window.
  Future<void> _closeThisWindow() async {
    try {
      final controller = await WindowController.fromCurrentEngine();
      await controller.invokeMethod('window_close');
    } catch (_) {
      // Fallback: hide the window if close is not available.
      try {
        final controller = await WindowController.fromCurrentEngine();
        await controller.hide();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'RDP window initialization failed:\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    if (!_ready) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return RdpSessionPage(
      sessionId: widget.arguments.sessionId,
      profile: widget.arguments.profile,
      // In a child window there is no Navigator route to pop.
      // Close the OS window directly instead.
      onClose: _closeThisWindow,
    );
  }
}
