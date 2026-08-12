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
    );
  }
}
