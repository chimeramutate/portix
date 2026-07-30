import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';

/// Dialog untuk import file .rdp dari CyberArk atau sumber lain.
///
/// Features:
/// - File picker untuk memilih file .rdp
/// - Preview profile yang di-parse
/// - Opsi untuk save profile atau langsung connect
class RdpFileImportDialog extends StatefulWidget {
  const RdpFileImportDialog({super.key});

  @override
  State<RdpFileImportDialog> createState() => _RdpFileImportDialogState();

  /// Show dialog dan return [RdpProfile] jika user confirm.
  static Future<RdpProfile?> show(BuildContext context) {
    return showDialog<RdpProfile>(
      context: context,
      builder: (context) => const RdpFileImportDialog(),
    );
  }
}

class _RdpFileImportDialogState extends State<RdpFileImportDialog> {
  final _backendService = sl<RdpBackendService>();

  String? _selectedFilePath;
  RdpProfile? _parsedProfile;
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import File RDP'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File picker button
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _pickFile,
              icon: const Icon(Icons.folder_open),
              label: Text(
                _selectedFilePath != null
                    ? 'File: ${_getFileName(_selectedFilePath!)}'
                    : 'Pilih File .rdp',
              ),
            ),

            const SizedBox(height: 16),

            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),

            // Loading indicator
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),

            // Profile preview
            if (_parsedProfile != null) ...[
              const Divider(height: 32),
              Text(
                'Preview Profile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _buildProfileInfo('Nama', _parsedProfile!.name),
              _buildProfileInfo('Host', _parsedProfile!.host),
              _buildProfileInfo('Port', _parsedProfile!.port.toString()),
              _buildProfileInfo('Username', _parsedProfile!.username),
              if (_parsedProfile!.domain != null)
                _buildProfileInfo('Domain', _parsedProfile!.domain!),
              if (_parsedProfile!.isCyberArkPsm)
                _buildProfileInfo('Type', 'CyberArk PSM', color: Colors.blue),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        if (_parsedProfile != null)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_parsedProfile),
            icon: const Icon(Icons.check),
            label: const Text('Import'),
          ),
      ],
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['rdp'],
        dialogTitle: 'Pilih File RDP',
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        setState(() {
          _error = 'Path file tidak valid';
          _isLoading = false;
        });
        return;
      }

      // Parse file menggunakan backend service
      final parseResult = await _backendService.parseRdpFile(filePath);

      parseResult.fold(
        (failure) {
          setState(() {
            _error = failure.message;
            _isLoading = false;
            _parsedProfile = null;
          });
        },
        (profile) {
          setState(() {
            _selectedFilePath = filePath;
            _parsedProfile = profile;
            _isLoading = false;
            _error = null;
          });
        },
      );
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Widget _buildProfileInfo(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  String _getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}
