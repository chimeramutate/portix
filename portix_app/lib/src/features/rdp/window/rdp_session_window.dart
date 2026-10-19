import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

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

class _RdpSessionWindowState extends State<RdpSessionWindow>
    with WindowListener {
  bool _ready = false;
  bool _closed = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initialize();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // Title-bar close (Linux only; elsewhere the plugin never emits it here).
  @override
  void onWindowClose() => _closeThisWindow();

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

  /// Ends the session and hides this window. The window is never destroyed:
  /// tearing down a child engine can crash Flutter's Linux task runner.
  // ponytail: hidden windows keep their idle engine until the app quits;
  // reuse them for new sessions if that memory starts to matter.
  Future<void> _closeThisWindow() async {
    if (_closed || !mounted) return;
    // Dropping RdpSessionPage runs its dispose, which disconnects the session.
    setState(() => _closed = true);
    try {
      final controller = await WindowController.fromCurrentEngine();
      await controller.hide();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();

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
