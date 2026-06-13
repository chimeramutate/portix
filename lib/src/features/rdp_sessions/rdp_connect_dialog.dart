import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../connection_manager/rdp_profile.dart';

/// Dialog for creating/editing an RDP connection profile.
///
/// When importing a .rdp file the dialog returns the parsed profile directly
/// without showing the form (fast path for CyberArk / corporate .rdp files).
class RdpConnectDialog extends StatefulWidget {
  const RdpConnectDialog({
    super.key,
    this.existingProfile,
    this.initialWidth,
    this.initialHeight,
  });

  final RdpProfile? existingProfile;
  final int? initialWidth;
  final int? initialHeight;

  @override
  State<RdpConnectDialog> createState() => _RdpConnectDialogState();
}

class _RdpConnectDialogState extends State<RdpConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _domainController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _drivePathController;
  late final TextEditingController _driveNameController;
  late final TextEditingController _altShellController;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    _nameController = TextEditingController(text: p?.name ?? '');
    _hostController = TextEditingController(text: p?.host ?? '');
    _portController = TextEditingController(text: '${p?.port ?? 3389}');
    _usernameController = TextEditingController(text: p?.username ?? '');
    _passwordController = TextEditingController(text: p?.password ?? '');
    _domainController = TextEditingController(text: p?.domain ?? '');
    _widthController = TextEditingController(
      text: '${p?.width ?? widget.initialWidth ?? 1280}',
    );
    _heightController = TextEditingController(
      text: '${p?.height ?? widget.initialHeight ?? 720}',
    );
    _drivePathController = TextEditingController(
      text: p?.extra['portix_drive_path'] ?? '',
    );
    _driveNameController = TextEditingController(
      text: p?.extra['portix_drive_name'] ?? 'PORTIX',
    );
    _altShellController = TextEditingController(
      text: p?.extra['alternate shell'] ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _drivePathController.dispose();
    _driveNameController.dispose();
    _altShellController.dispose();
    super.dispose();
  }

  Future<void> _pickDriveFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select local folder to map into the RDP session',
    );
    if (path != null && mounted) {
      setState(() => _drivePathController.text = path);
    }
  }

  /// Pick a .rdp file and return the parsed profile immediately —
  /// no form fill needed (handles CyberArk / corporate files cleanly).
  Future<void> _importRdpFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['rdp'],
      dialogTitle: 'Select .rdp file',
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final content = await File(file.path!).readAsString();
    final fileName = file.name.replaceAll(RegExp(r'\.rdp$', caseSensitive: false), '');

    final profile = RdpProfile.fromRdpFile(
      id: const Uuid().v4(),
      name: fileName,
      content: content,
    );

    if (mounted) Navigator.of(context).pop(profile);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final width = _normalizeDimension(_widthController.text, fallback: 1280);
    final height = _normalizeDimension(_heightController.text, fallback: 720);
    final extra = Map<String, String>.from(
      widget.existingProfile?.extra ?? const {},
    );

    // Drive mapping
    final drivePath = _drivePathController.text.trim();
    if (drivePath.isEmpty) {
      extra.remove('portix_drive_path');
      extra.remove('portix_drive_name');
    } else {
      extra['portix_drive_path'] = drivePath;
      extra['portix_drive_name'] = _normalizedDriveName(_driveNameController.text);
    }

    // Alternate shell (RemoteApp / PSM)
    final altShell = _altShellController.text.trim();
    if (altShell.isEmpty) {
      extra.remove('alternate shell');
    } else {
      extra['alternate shell'] = altShell;
    }

    final profile = RdpProfile(
      id: widget.existingProfile?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text) ?? 3389,
      username: _usernameController.text.trim(),
      password: _passwordController.text.isNotEmpty
          ? _passwordController.text
          : null,
      hasPassword: _passwordController.text.isNotEmpty,
      domain: _domainController.text.isNotEmpty
          ? _domainController.text.trim()
          : null,
      width: width,
      height: height,
      extra: extra,
    );

    Navigator.of(context).pop(profile);
  }

  int _normalizeDimension(String value, {required int fallback}) {
    final parsed = int.tryParse(value.trim()) ?? fallback;
    return ((parsed.clamp(320, 3840)) ~/ 4) * 4;
  }

  String _normalizedDriveName(String value) {
    final candidate = value.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9_]'),
      '',
    );
    final normalized = candidate.length > 7
        ? candidate.substring(0, 7)
        : candidate;
    return normalized.isEmpty ? 'PORTIX' : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingProfile != null;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.desktop_windows, size: 20),
          const SizedBox(width: 8),
          Text(isEditing ? 'Edit RDP Connection' : 'New RDP Connection'),
          const Spacer(),
          // Import .rdp → directly returns profile, no form fill
          FilledButton.icon(
            onPressed: _importRdpFile,
            icon: const Icon(Icons.file_open, size: 16),
            label: const Text('Open .rdp file'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Connection Name',
                    hintText: 'My Server',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: 'Host *',
                          hintText: '192.168.1.100',
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _portController,
                        decoration: const InputDecoration(labelText: 'Port'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(labelText: 'Username'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _domainController,
                        decoration: const InputDecoration(
                          labelText: 'Domain',
                          hintText: 'optional',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                // Alternate Shell — needed for PSM / RemoteApp
                TextFormField(
                  controller: _altShellController,
                  decoration: const InputDecoration(
                    labelText: 'Alternate Shell',
                    hintText: 'e.g. PSM@session-id (CyberArk / RemoteApp)',
                    helperText: 'Leave empty for a standard desktop session.',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _widthController,
                        decoration: const InputDecoration(labelText: 'Width'),
                        keyboardType: TextInputType.number,
                        validator: _dimensionValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _heightController,
                        decoration: const InputDecoration(labelText: 'Height'),
                        keyboardType: TextInputType.number,
                        validator: _dimensionValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Local Drive Mapping',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _drivePathController,
                        decoration: const InputDecoration(
                          labelText: 'Local folder',
                          hintText: 'Leave empty to disable',
                        ),
                        validator: (value) {
                          final path = value?.trim() ?? '';
                          if (path.isNotEmpty && !Directory(path).existsSync()) {
                            return 'Folder does not exist';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Choose folder',
                      onPressed: _pickDriveFolder,
                      icon: const Icon(Icons.folder_open),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _driveNameController,
                  decoration: const InputDecoration(
                    labelText: 'Remote drive name',
                    hintText: 'PORTIX',
                    helperText: 'Up to 7 letters, numbers, or underscores.',
                  ),
                  maxLength: 7,
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Note: NLA must be disabled on the RDP server.',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Save' : 'Connect'),
        ),
      ],
    );
  }

  String? _dimensionValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Required';
    if (parsed < 320 || parsed > 3840) return '320–3840';
    return null;
  }
}
