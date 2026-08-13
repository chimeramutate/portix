import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:uuid/uuid.dart';

class RdpManualFormDialog extends StatefulWidget {
  const RdpManualFormDialog({super.key, this.initialProfile});

  final RdpProfile? initialProfile;

  @override
  State<RdpManualFormDialog> createState() => _RdpManualFormDialogState();

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
  final _localSharePathController = TextEditingController(
    text: RdpProfile.defaultLocalSharePath,
  );
  final _localShareNameController = TextEditingController(
    text: RdpProfile.defaultLocalShareName,
  );

  bool _fullScreen = false;
  bool _redirectDrives = false;
  bool _redirectClipboard = true;
  bool _enableCredSsp = false;

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
    _localSharePathController.dispose();
    _localShareNameController.dispose();
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
    _localSharePathController.text = profile.localSharePath?.isNotEmpty == true
        ? profile.localSharePath!
        : RdpProfile.defaultLocalSharePath;
    _localShareNameController.text = profile.localShareName.isNotEmpty == true
        ? profile.localShareName
        : RdpProfile.defaultLocalShareName;
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

                TextFormField(
                  controller: _domainController,
                  decoration: const InputDecoration(
                    labelText: 'Domain',
                    hintText: 'CORP (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

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

                CheckboxListTile(
                  value: _fullScreen,
                  onChanged: (value) =>
                      setState(() => _fullScreen = value ?? false),
                  title: const Text('Full Screen'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                CheckboxListTile(
                  value: _redirectDrives,
                  onChanged: (value) {
                    setState(() {
                      _redirectDrives = value ?? false;
                      if (_redirectDrives &&
                          _localSharePathController.text.trim().isEmpty) {
                        _localSharePathController.text =
                            RdpProfile.defaultLocalSharePath;
                      }
                    });
                  },
                  title: const Text('Redirect Drives'),
                  subtitle: const Text('Share a local folder as PORTIX.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                if (_redirectDrives) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _localSharePathController,
                    decoration: InputDecoration(
                      labelText: 'Local shared folder *',
                      hintText: RdpProfile.defaultLocalSharePath,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.folder_shared_outlined),
                      suffixIcon: IconButton(
                        tooltip: 'Choose folder',
                        onPressed: _pickLocalShareFolder,
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    ),
                    validator: (value) {
                      if (!_redirectDrives) return null;
                      if (value == null || value.trim().isEmpty) {
                        return 'Folder lokal harus diisi jika Redirect Drives aktif';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _localShareNameController,
                    decoration: InputDecoration(
                      labelText: 'Share name (tampil di Windows)',
                      hintText: RdpProfile.defaultLocalShareName,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.drive_file_rename_outline),
                      helperText:
                          'Akses dari Windows: \\\\tsclient\\${_localShareNameController.text.trim().isEmpty ? RdpProfile.defaultLocalShareName : _localShareNameController.text.trim()}',
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9_\-]'),
                      ),
                    ],
                    validator: (value) {
                      if (!_redirectDrives) return null;
                      if (value == null || value.trim().isEmpty) {
                        return 'Share name harus diisi';
                      }
                      return null;
                    },
                  ),
                ],

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
                      setState(() => _enableCredSsp = value ?? false),
                  title: const Text('Enable CredSSP (NLA)'),
                  subtitle: const Text(
                    'Aktifkan hanya jika server support NLA (Windows Server 2012+)',
                    style: TextStyle(fontSize: 11),
                  ),
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
      localSharePath: _redirectDrives
          ? _localSharePathController.text.trim()
          : null,
      localShareName: _localShareNameController.text.trim().isEmpty
          ? RdpProfile.defaultLocalShareName
          : _localShareNameController.text.trim(),
      alternateShell: '',
      enableCredSsp: _enableCredSsp,
    );

    Navigator.of(context).pop(profile);
  }

  Future<void> _pickLocalShareFolder() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select local folder to share',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _localSharePathController.text = selected;
    });
  }
}
