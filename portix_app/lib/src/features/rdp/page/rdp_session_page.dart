import 'package:flutter/material.dart';
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
  bool get _isFullScreen =>
      MediaQuery.of(context).size.height ==
      MediaQuery.of(context).size.width *
          (widget.profile.desktopHeight / widget.profile.desktopWidth);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullScreen
          ? null
          : AppBar(
              title: Text('RDP: ${widget.profile.name}'),
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.text,
              elevation: 1,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),

                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'Toggle Fullscreen',
                  onPressed: () {
                    if (!_isFullScreen) {
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
      backgroundColor: Colors.black,

      extendBodyBehindAppBar: _isFullScreen,
      body: RdpFrameViewer(
        sessionId: widget.sessionId,
        desktopWidth: widget.profile.desktopWidth > 0
            ? widget.profile.desktopWidth
            : 1280,
        desktopHeight: widget.profile.desktopHeight > 0
            ? widget.profile.desktopHeight
            : 800,
        onDisconnect: () {
          if (context.mounted) {
            Navigator.of(context).maybePop();
          }
        },
      ),
    );
  }
}
