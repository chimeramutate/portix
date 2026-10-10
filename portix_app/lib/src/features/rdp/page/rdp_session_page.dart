import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';
import 'package:portix/src/features/rdp/widget/rdp_frame_viewer.dart';

class RdpSessionPage extends StatefulWidget {
  const RdpSessionPage({
    super.key,
    required this.profile,
    required this.sessionId,
    this.onClose,
  });

  final RdpProfile profile;
  final String sessionId;

  final Future<void> Function()? onClose;

  @override
  State<RdpSessionPage> createState() => _RdpSessionPageState();
}

class _RdpSessionPageState extends State<RdpSessionPage> {
  bool _isFullScreen = false;

  /// Fullscreen toolbar visibility. It only appears while the pointer is at
  /// the top edge, so clicks always reach the remote desktop.
  bool _showOverlayToolbar = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    sl<RdpBackendService>().disconnect(widget.sessionId);
    super.dispose();
  }

  Future<void> _closePage() async {
    _exitFullScreen();
    if (widget.onClose != null) {
      await widget.onClose!();
    } else if (context.mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Show the toolbar briefly so the user sees where it lives.
    setState(() {
      _isFullScreen = true;
      _showOverlayToolbar = true;
    });
    _scheduleHide(const Duration(seconds: 2));
  }

  void _exitFullScreen() {
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) {
      setState(() {
        _isFullScreen = false;
        _showOverlayToolbar = false;
      });
    }
  }

  void _showToolbar() {
    _hideTimer?.cancel();
    if (!_showOverlayToolbar) setState(() => _showOverlayToolbar = true);
  }

  void _scheduleHide([Duration delay = const Duration(milliseconds: 400)]) {
    _hideTimer?.cancel();
    _hideTimer = Timer(delay, () {
      if (mounted) setState(() => _showOverlayToolbar = false);
    });
  }

  int get _desktopWidth =>
      widget.profile.desktopWidth > 0 ? widget.profile.desktopWidth : 1280;
  int get _desktopHeight =>
      widget.profile.desktopHeight > 0 ? widget.profile.desktopHeight : 800;

  @override
  Widget build(BuildContext context) {
    final viewer = RdpFrameViewer(
      sessionId: widget.sessionId,
      desktopWidth: _desktopWidth,
      desktopHeight: _desktopHeight,
      onDisconnect: _closePage,
    );

    if (_isFullScreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            viewer,

            // Hover strip along the top edge. Translucent, so clicks there
            // still go to the remote desktop.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 4,
              child: MouseRegion(
                hitTestBehavior: HitTestBehavior.translucent,
                onEnter: (_) => _showToolbar(),
                onExit: (_) => _scheduleHide(),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              top: _showOverlayToolbar ? 0 : -48,
              left: 0,
              right: 0,
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => _showToolbar(),
                  onExit: (_) => _scheduleHide(),
                  child: _FullscreenToolbar(
                    profileName: widget.profile.name,
                    resolution: '${_desktopWidth}×$_desktopHeight',
                    onExitFullscreen: _exitFullScreen,
                    onDisconnect: _closePage,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'RDP: ${widget.profile.name}',
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 1,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                '${_desktopWidth}×$_desktopHeight',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Enter fullscreen',
            onPressed: _enterFullScreen,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Disconnect',
            onPressed: _closePage,
          ),
        ],
      ),
      body: viewer,
    );
  }
}

/// Compact pill shown at the top center in fullscreen.
class _FullscreenToolbar extends StatelessWidget {
  const _FullscreenToolbar({
    required this.profileName,
    required this.resolution,
    required this.onExitFullscreen,
    required this.onDisconnect,
  });

  final String profileName;
  final String resolution;
  final VoidCallback onExitFullscreen;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: const BoxDecoration(
        color: Color.fromRGBO(24, 24, 27, 0.92),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.desktop_windows, color: Colors.white70, size: 14),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              profileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            resolution,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.fullscreen_exit, size: 18),
            tooltip: 'Exit fullscreen',
            color: Colors.white70,
            visualDensity: VisualDensity.compact,
            onPressed: onExitFullscreen,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Disconnect',
            color: Colors.redAccent,
            visualDensity: VisualDensity.compact,
            onPressed: onDisconnect,
          ),
        ],
      ),
    );
  }
}
