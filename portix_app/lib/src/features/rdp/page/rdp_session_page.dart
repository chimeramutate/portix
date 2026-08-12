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
  });

  final RdpProfile profile;
  final String sessionId;

  @override
  State<RdpSessionPage> createState() => _RdpSessionPageState();
}

class _RdpSessionPageState extends State<RdpSessionPage> {
  bool _isFullScreen = false;

  /// Toolbar overlay visibility (fullscreen mode only)
  bool _showOverlayToolbar = false;

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Disconnect session saat halaman di-close
    sl<RdpBackendService>().disconnect(widget.sessionId);
    super.dispose();
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() {
      _isFullScreen = true;
      _showOverlayToolbar = false;
    });
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) {
      setState(() {
        _isFullScreen = false;
        _showOverlayToolbar = false;
      });
    }
  }

  void _toggleFullScreen() {
    if (_isFullScreen) {
      _exitFullScreen();
    } else {
      _enterFullScreen();
    }
  }

  void _toggleOverlayToolbar() {
    setState(() => _showOverlayToolbar = !_showOverlayToolbar);
  }

  Future<void> _pasteLocalClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    await sl<RdpBackendService>().pasteTextAsKeystrokes(
      widget.sessionId,
      text,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pasted local clipboard to remote session.'),
        duration: Duration(seconds: 2),
      ),
    );
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
      // Single-tap di fullscreen → tampilkan/sembunyikan toolbar overlay
      onSingleTapUp: _isFullScreen ? _toggleOverlayToolbar : null,
      onDoubleTap: _isFullScreen ? _exitFullScreen : null,
      onDisconnect: () {
        _exitFullScreen();
        if (context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
    );

    if (_isFullScreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            viewer,
            // Overlay toolbar — muncul saat user tap sekali
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              top: _showOverlayToolbar ? 0 : -72,
              left: 0,
              right: 0,
              child: _FullscreenToolbar(
                profileName: widget.profile.name,
                resolution: '${_desktopWidth}×$_desktopHeight',
                onPasteClipboard: _pasteLocalClipboard,
                onExitFullscreen: _exitFullScreen,
                onDisconnect: () {
                  _exitFullScreen();
                  if (context.mounted) Navigator.of(context).maybePop();
                },
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
          // Resolusi info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                '${_desktopWidth}×$_desktopHeight',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_paste_go_outlined),
            tooltip: 'Paste local clipboard to remote',
            onPressed: _pasteLocalClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Enter fullscreen (or double-tap)',
            onPressed: _toggleFullScreen,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Disconnect',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: viewer,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FULLSCREEN OVERLAY TOOLBAR
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenToolbar extends StatelessWidget {
  const _FullscreenToolbar({
    required this.profileName,
    required this.resolution,
    required this.onPasteClipboard,
    required this.onExitFullscreen,
    required this.onDisconnect,
  });

  final String profileName;
  final String resolution;
  final VoidCallback onPasteClipboard;
  final VoidCallback onExitFullscreen;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: const Color.fromRGBO(0, 0, 0, 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.desktop_windows, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              profileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            resolution,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.content_paste_go_outlined, size: 18),
            tooltip: 'Paste local clipboard to remote',
            color: Colors.white70,
            onPressed: onPasteClipboard,
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: onExitFullscreen,
            icon: const Icon(Icons.fullscreen_exit, size: 18),
            label: const Text('Exit Fullscreen'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Disconnect',
            color: Colors.redAccent,
            onPressed: onDisconnect,
          ),
        ],
      ),
    );
  }
}
