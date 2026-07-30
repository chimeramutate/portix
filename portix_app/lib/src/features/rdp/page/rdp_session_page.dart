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
            onPressed: () {
              Navigator.of(context).pop();
            },
            tooltip: 'Close session',
          ),
        ],
      ),
      backgroundColor: AppColors.bg,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Host: ${profile.address}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Username: ${profile.username}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Resolution: ${profile.desktopWidth}×${profile.desktopHeight}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: RdpFrameViewer(sessionId: sessionId)),
          ],
        ),
      ),
    );
  }
}
