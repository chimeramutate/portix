import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/features/rdp/widget/rdp_frame_viewer.dart';

class RdpSessionPage extends StatelessWidget {
  const RdpSessionPage({
    super.key,
    required this.profile,
    required this.sessionId,
  });

  final RdpProfile profile;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('RDP: ${profile.name}'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: RdpFrameViewer(
        sessionId: sessionId,
        desktopWidth: profile.desktopWidth > 0 ? profile.desktopWidth : 1280,
        desktopHeight: profile.desktopHeight > 0 ? profile.desktopHeight : 800,
      ),
    );
  }
}
