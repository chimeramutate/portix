import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_panel.dart';

/// A centered overlay shown when a remote connection is lost.
/// Provides a reconnect button to re-establish the session.
class DisconnectedOverlay extends StatelessWidget {
  const DisconnectedOverlay({
    super.key,
    this.title = 'Connection lost',
    this.message =
        'Remote session disconnected. Reconnect to continue browsing.',
    this.onReconnect,
  });

  final String title;
  final String message;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.danger,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: portixTitle(16).copyWith(color: AppColors.danger),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: portixMuted(12),
            ),
            const SizedBox(height: 20),
            if (onReconnect != null)
              FilledButton.icon(
                onPressed: onReconnect,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reconnect'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.text,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
