import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
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

  @override
  void dispose() {
    // Restore system UI tanpa memanggil setState — widget sudah disposing.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _isFullScreen = true);
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Hanya setState jika widget masih aktif di tree.
    if (mounted) setState(() => _isFullScreen = false);
  }

  void _toggleFullScreen() {
    if (_isFullScreen) {
      _exitFullScreen();
    } else {
      _enterFullScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _isFullScreen
          ? null
          : AppBar(
              title: Text('RDP: ${widget.profile.name}'),
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.text,
              elevation: 1,
              actions: [
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'Fullscreen',
                  onPressed: _toggleFullScreen,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
      body: RdpFrameViewer(
        sessionId: widget.sessionId,
        desktopWidth: widget.profile.desktopWidth > 0
            ? widget.profile.desktopWidth
            : 1280,
        desktopHeight: widget.profile.desktopHeight > 0
            ? widget.profile.desktopHeight
            : 800,
        onDoubleTap: _isFullScreen ? _exitFullScreen : null,
        onDisconnect: () {
          _exitFullScreen();
          if (context.mounted) {
            Navigator.of(context).maybePop();
          }
        },
      ),
    );
  }
}
