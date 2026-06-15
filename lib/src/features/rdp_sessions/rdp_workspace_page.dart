import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:uuid/uuid.dart';

import '../../connection_manager/rdp_backend.dart';
import '../../connection_manager/rdp_profile.dart';
import 'rdp_connect_dialog.dart';
import 'rdp_session_page.dart';

/// Workspace page for RDP connections and importing .rdp files.
class RdpWorkspacePage extends StatefulWidget {
  const RdpWorkspacePage({super.key});

  @override
  State<RdpWorkspacePage> createState() => _RdpWorkspacePageState();
}

class _RdpWorkspacePageState extends State<RdpWorkspacePage> {
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
              OutlinedButton.icon(
                onPressed: () => _openRdpFile(context),
                icon: const Icon(Icons.file_open, size: 16),
                label: const Text('Open .rdp'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _showConnectDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New RDP Connection'),
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

  /// Pick a .rdp file and connect immediately without showing the form.
  Future<void> _openRdpFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['rdp'],
      dialogTitle: 'Select .rdp file',
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final content = await File(file.path!).readAsString();
    final fileName = file.name.replaceAll(
      RegExp(r'\.rdp$', caseSensitive: false),
      '',
    );
    final profile = RdpProfile.fromRdpFile(
      id: const Uuid().v4(),
      name: fileName,
      content: content,
    );

    if (!context.mounted) return;
    if (!sl.isRegistered<RdpBackend>()) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RdpSessionPage(profile: profile, backend: sl<RdpBackend>()),
      ),
    );
  }

  void _showConnectDialog(BuildContext context) async {
    final windowSize = MediaQuery.of(context).size;
    final profile = await showDialog<RdpProfile>(
      context: context,
      builder: (_) => RdpConnectDialog(
        initialWidth: windowSize.width.toInt(),
        initialHeight: windowSize.height.toInt(),
      ),
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
}
