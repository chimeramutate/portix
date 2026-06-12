import 'dart:io';

import 'package:flutter/material.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:uuid/uuid.dart';

import '../../connection_manager/rdp_backend.dart';
import '../../connection_manager/rdp_profile.dart';
import 'rdp_session_page.dart';

/// Workspace page for RDP connections — shows quick connect button
/// and allows importing .rdp files.
class RdpWorkspacePage extends StatefulWidget {
  const RdpWorkspacePage({super.key});

  static const bool _localBypassEnabled = bool.fromEnvironment(
    'PORTIX_RDP_LOCAL_BYPASS',
    defaultValue: true,
  );

  @override
  State<RdpWorkspacePage> createState() => _RdpWorkspacePageState();
}

class _RdpWorkspacePageState extends State<RdpWorkspacePage> {
  bool _autoConnectStarted = false;

  @override
  void initState() {
    super.initState();
    if (RdpWorkspacePage._localBypassEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _autoConnectStarted) return;
        _autoConnectStarted = true;
        _connectLocalBypass(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.desktop_windows_rounded,
                color: AppColors.cyan,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'Remote Desktop (RDP)',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => RdpWorkspacePage._localBypassEnabled
                    ? _connectLocalBypass(context)
                    : _showConnectDialog(context),
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text('Local RDP'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _showConnectDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Manual'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.desktop_windows_outlined,
                    size: 64,
                    color: AppColors.muted.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No active RDP sessions',
                    style: TextStyle(color: AppColors.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Click "New RDP Connection" to connect to a remote desktop.\n'
                    'You can also import .rdp files.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Note: The RDP server must have NLA disabled (use TLS security).',
                    style: TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectDialog(BuildContext context) async {
    final windowSize = MediaQuery.of(context).size;
    // Round down to multiple of 4 (xrdp requirement for bitmap padding)
    final rdpWidth = ((windowSize.width.toInt()) ~/ 4) * 4;
    final rdpHeight = ((windowSize.height.toInt()) ~/ 4) * 4;

    final profile = RdpProfile(
      id: 'test-rdp-1',
      name: 'Local xrdp',
      host: 'test.host',
      port: 3389,
      username: 'testuser',
      password: r'test123',
      width: rdpWidth.clamp(640, 1920),
      height: rdpHeight.clamp(480, 1080),
    );

    if (profile == null) return;
    if (!sl.isRegistered<RdpBackend>()) return;
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RdpSessionPage(profile: profile, backend: sl<RdpBackend>()),
      ),
    );
  }

  void _connectLocalBypass(BuildContext context) {
    if (!sl.isRegistered<RdpBackend>()) return;
    _autoConnectStarted = true;

    final windowSize = MediaQuery.of(context).size;
    final width = _normalizeDimension(windowSize.width.toInt(), 1280);
    final height = _normalizeDimension(windowSize.height.toInt(), 720);
    final extra = <String, String>{
      'portix_debug': '1',
      'portix_stream_pixels': '0',
      'portix_keep_awake': '1',
      'portix_keep_awake_interval_seconds': '15',
      'portix_auto_unlock': '1',
    };
    final home = Platform.environment['HOME'];
    if (home != null && Directory('$home/Downloads').existsSync()) {
      extra['portix_drive_path'] = '$home/Downloads';
      extra['portix_drive_name'] = 'PORTIX';
    }
    final profile = RdpProfile(
      id: const Uuid().v4(),
      name: 'Local RDP',
      host: 'test.host',
      port: 3389,
      username: 'testuser',
      password: r'test123',
      hasPassword: true,
      width: width.clamp(640, 1920).toInt(),
      height: height.clamp(480, 1080).toInt(),
      extra: extra,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RdpSessionPage(profile: profile, backend: sl<RdpBackend>()),
      ),
    );
  }

  int _normalizeDimension(int value, int fallback) {
    final normalized = value <= 0 ? fallback : value;
    return (normalized ~/ 4) * 4;
  }
}
