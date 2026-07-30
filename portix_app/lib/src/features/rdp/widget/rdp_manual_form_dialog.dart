import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:uuid/uuid.dart';

/// Dialog untuk membuat RDP profile secara manual (tanpa file .rdp).
class RdpManualFormDialog extends StatefulWidget {
  const RdpManualFormDialog({super.key, this.initialProfile});

  final RdpProfile? initialProfile;

  @override
  State<RdpManualFormDialog> createState() => _RdpManualFormDialogState();

  /// Show dialog dan return [RdpProfile] jika user confirm.
  static Future<RdpProfile?> show(
    BuildContext context, {
    RdpProfile? initialProfile,
  }) {
    return showDialog<RdpProfile>(
      context: context,
      builder: (context) => RdpManualFormDialog(initialProfile: initialProfile),
    );
  }
}

class _RdpManualFormDialogState extends State<RdpManualFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '3389');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _domainController = TextEditingController();
  final _widthController = TextEditingController(text: '1280');
  final _heightController = TextEditingController(text: '800');

  bool _fullScreen = false;
  bool _redirectDrives = false;
  bool _redirectClipboard = true;
  bool _enableCredSsp = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialProfile != null) {
      _loadProfile(widget.initialProfile!);
    }
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

  void _loadProfile(RdpProfile profile) {
    _nameController.text = profile.name;
    _hostController.text = profile.host;
    _portController.text = profile.port.toString();
    _usernameController.text = profile.username;
    _passwordController.text = profile.password ?? '';
    _domainController.text = profile.domain ?? '';
    _widthController.text = profile.desktopWidth.toString();
    _heightController.text = profile.desktopHeight.toString();
    _fullScreen = profile.fullScreen;
    _redirectDrives = profile.redirectDrives;
    _redirectClipboard = profile.redirectClipboard;
    _enableCredSsp = profile.enableCredSsp;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialProfile == null ? 'RDP Baru' : 'Edit RDP'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Nama
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama *',
                    hintText: 'Server Production',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nama harus diisi';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Host
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Host / IP Address *',
                    hintText: '192.168.1.10 atau server.example.com',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Host harus diisi';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Port
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '3389',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Port harus diisi';
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1 || port > 65535) {
                      return 'Port harus antara 1-65535';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Username
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username *',
                    hintText: 'administrator',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Username harus diisi';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Opsional',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),

                const SizedBox(height: 16),

                // Domain
                TextFormField(
                  controller: _domainController,
                  decoration: const InputDecoration(
                    labelText: 'Domain',
                    hintText: 'CORP (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // Resolution
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _widthController,
                        decoration: const InputDecoration(
                          labelText: 'Width',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _heightController,
                        decoration: const InputDecoration(
                          labelText: 'Height',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Checkboxes
                CheckboxListTile(
                  value: _fullScreen,
                  onChanged: (value) =>
                      setState(() => _fullScreen = value ?? false),
                  title: const Text('Full Screen'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                CheckboxListTile(
                  value: _redirectDrives,
                  onChanged: (value) =>
                      setState(() => _redirectDrives = value ?? false),
                  title: const Text('Redirect Drives'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                CheckboxListTile(
                  value: _redirectClipboard,
                  onChanged: (value) =>
                      setState(() => _redirectClipboard = value ?? true),
                  title: const Text('Redirect Clipboard'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                CheckboxListTile(
                  value: _enableCredSsp,
                  onChanged: (value) =>
                      setState(() => _enableCredSsp = value ?? true),
                  title: const Text('Enable CredSSP (NLA)'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _handleSave,
          icon: const Icon(Icons.check),
          label: const Text('Simpan'),
        ),
      ],
    );
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final profile = RdpProfile(
      id: widget.initialProfile?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim().isEmpty
          ? null
          : _passwordController.text.trim(),
      domain: _domainController.text.trim().isEmpty
          ? null
          : _domainController.text.trim(),
      group: 'RDP',
      tags: const [],
      color: RdpProfileColor.blue,
      desktopWidth: int.tryParse(_widthController.text.trim()) ?? 1280,
      desktopHeight: int.tryParse(_heightController.text.trim()) ?? 800,
      fullScreen: _fullScreen,
      redirectDrives: _redirectDrives,
      redirectClipboard: _redirectClipboard,
      alternateShell: '',
      enableCredSsp: _enableCredSsp,
    );

    Navigator.of(context).pop(profile);
  }
}
