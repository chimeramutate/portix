import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../connection_manager/rdp_profile.dart';

/// Dialog for creating/editing an RDP connection profile.
class RdpConnectDialog extends StatefulWidget {
  const RdpConnectDialog({super.key, this.existingProfile});

  /// If provided, dialog will be in "edit" mode.
  final RdpProfile? existingProfile;

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
    _widthController = TextEditingController(text: '${p?.width ?? 1920}');
    _heightController = TextEditingController(text: '${p?.height ?? 1080}');
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
    super.dispose();
  }

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
    final fileName = file.name.replaceAll('.rdp', '');

    final profile = RdpProfile.fromRdpFile(
      id: const Uuid().v4(),
      name: fileName,
      content: content,
    );

    setState(() {
      _nameController.text = profile.name;
      _hostController.text = profile.host;
      _portController.text = '${profile.port}';
      _usernameController.text = profile.username;
      _domainController.text = profile.domain ?? '';
      _widthController.text = '${profile.width}';
      _heightController.text = '${profile.height}';
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

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
      width: int.tryParse(_widthController.text) ?? 1920,
      height: int.tryParse(_heightController.text) ?? 1080,
    );

    Navigator.of(context).pop(profile);
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
          TextButton.icon(
            onPressed: _importRdpFile,
            icon: const Icon(Icons.file_open, size: 16),
            label: const Text('Import .rdp'),
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
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _widthController,
                        decoration: const InputDecoration(labelText: 'Width'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _heightController,
                        decoration: const InputDecoration(labelText: 'Height'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
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
}
