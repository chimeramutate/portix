part of '../../page/sftp_workspace_page.dart';

class _EditorPickerSheet extends StatelessWidget {
  const _EditorPickerSheet({required this.editors});

  final List<LocalEditor> editors;

  Widget _buildEditorIcon(LocalEditor editor) {
    final fallbackIcon = Icon(
      editor.icon ?? Icons.code_rounded,
      color: AppColors.cyan,
      size: 22,
    );

    if (editor.svgAsset == null || editor.svgAsset!.trim().isEmpty) {
      return fallbackIcon;
    }

    return SvgPicture.asset(
      editor.svgAsset!,
      width: 22,
      height: 22,
      fit: BoxFit.contain,

      // kalau sedang loading
      placeholderBuilder: (_) => fallbackIcon,

      // kalau asset tidak ada / gagal load
      errorBuilder: (_, __, ___) => fallbackIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Open with', style: portixTitle(16)),
            const SizedBox(height: 10),
            for (final editor in editors)
              ListTile(
                dense: true,
                leading: _buildEditorIcon(editor),
                title: Text(editor.name, style: portixTitle(13)),
                onTap: () => Navigator.of(context).pop(editor),
              ),
          ],
        ),
      ),
    );
  }
}

class _SftpPasswordDialog extends StatefulWidget {
  const _SftpPasswordDialog({required this.profile});

  final SshProfile profile;

  @override
  State<_SftpPasswordDialog> createState() => _SftpPasswordDialogState();
}

class _SftpPasswordDialogState extends State<_SftpPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_passwordController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Enter SFTP Password'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${profile.name}" belum memiliki secure password. '
                'Masukkan password untuk menyambung.',
                style: portixMuted(12),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter SFTP password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: AppColors.bg,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Password is required';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Text(
                'The password will be saved to local secure storage.',
                style: portixMuted(10),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.login_rounded, size: 16),
          label: const Text('Connect'),
        ),
      ],
    );
  }
}

class _SftpDisconnectedOverlay extends StatelessWidget {
  const _SftpDisconnectedOverlay({this.onReconnect, this.errorMessage});

  final VoidCallback? onReconnect;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    // Just the icon + a one-line title + reconnect button.
    // No container, no border, no description text — keeps it simple.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 32),
          const SizedBox(height: 12),
          Text(
            'Connection lost',
            style: portixTitle(16).copyWith(color: AppColors.danger),
          ),
          const SizedBox(height: 20),
          if (onReconnect != null)
            FilledButton.icon(
              onPressed: onReconnect,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reconnect'),
            ),
        ],
      ),
    );
  }
}

class _ChmodDialog extends StatefulWidget {
  const _ChmodDialog({required this.file});

  final SftpFileEntry file;

  @override
  State<_ChmodDialog> createState() => _ChmodDialogState();
}

class _ChmodDialogState extends State<_ChmodDialog> {
  late final TextEditingController _modeController;
  final _bits = List<bool>.filled(9, false);

  @override
  void initState() {
    super.initState();
    _setFromMode(widget.file.chmodMode ?? (widget.file.folder ? '755' : '644'));
    _modeController = TextEditingController(text: _modeString());
  }

  @override
  void dispose() {
    _modeController.dispose();
    super.dispose();
  }

  void _setFromMode(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^0-7]'), '');
    if (sanitized.length != 3) return;
    for (var group = 0; group < 3; group += 1) {
      final digit = int.parse(sanitized[group]);
      _bits[group * 3] = digit & 4 != 0;
      _bits[group * 3 + 1] = digit & 2 != 0;
      _bits[group * 3 + 2] = digit & 1 != 0;
    }
  }

  String _modeString() {
    final digits = <int>[];
    for (var group = 0; group < 3; group += 1) {
      var digit = 0;
      if (_bits[group * 3]) digit += 4;
      if (_bits[group * 3 + 1]) digit += 2;
      if (_bits[group * 3 + 2]) digit += 1;
      digits.add(digit);
    }
    return digits.join();
  }

  void _toggle(int index, bool value) {
    setState(() {
      _bits[index] = value;
      _modeController.text = _modeString();
    });
  }

  void _applyText(String value) {
    setState(() {
      _setFromMode(value);
      _modeController.text = _modeString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Permissions: ${widget.file.name}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _modeController,
              keyboardType: TextInputType.number,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'Numeric mode',
                hintText: '755',
                counterText: '',
              ),
              onChanged: _applyText,
            ),
            const SizedBox(height: 12),
            _PermissionRow(
              label: 'Owner',
              offset: 0,
              bits: _bits,
              onChanged: _toggle,
            ),
            _PermissionRow(
              label: 'Group',
              offset: 3,
              bits: _bits,
              onChanged: _toggle,
            ),
            _PermissionRow(
              label: 'Other',
              offset: 6,
              bits: _bits,
              onChanged: _toggle,
            ),
            const SizedBox(height: 8),
            Text(
              'Result: chmod ${_modeString()} ${widget.file.name}',
              style: portixMuted(11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(int.parse(_modeString())),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.offset,
    required this.bits,
    required this.onChanged,
  });

  final String label;
  final int offset;
  final List<bool> bits;
  final void Function(int index, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label, style: portixTitle(12))),
        _PermCheck(
          label: 'r',
          value: bits[offset],
          onChanged: (value) => onChanged(offset, value),
        ),
        _PermCheck(
          label: 'w',
          value: bits[offset + 1],
          onChanged: (value) => onChanged(offset + 1, value),
        ),
        _PermCheck(
          label: 'x',
          value: bits[offset + 2],
          onChanged: (value) => onChanged(offset + 2, value),
        ),
      ],
    );
  }
}

class _PermCheck extends StatelessWidget {
  const _PermCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label, style: portixTitle(12)),
        value: value,
        onChanged: (next) => onChanged(next ?? false),
      ),
    );
  }
}

class _RemoteFolderPickerDialog extends StatefulWidget {
  const _RemoteFolderPickerDialog({
    required this.title,
    required this.initialPath,
    required this.connectionManager,
  });

  final String title;
  final String initialPath;
  final SftpWorkspaceController connectionManager;

  @override
  State<_RemoteFolderPickerDialog> createState() =>
      _RemoteFolderPickerDialogState();
}

class _RemoteFolderPickerDialogState extends State<_RemoteFolderPickerDialog> {
  late String _currentPath;
  List<SftpFileEntry> _entries = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Use the controller's connection to list remote directories.
      final entries = await widget.connectionManager.listRemoteDirectoryRaw(
        _currentPath,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries.where((e) => e.name != '..').toList(growable: false)
          ..sort((a, b) {
            if (a.folder != b.folder) return a.folder ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _navigateInto(String folderName) {
    setState(() {
      _currentPath = _currentPath.endsWith('/')
          ? '$_currentPath$folderName'
          : '$_currentPath/$folderName';
    });
    _loadFolders();
  }

  void _navigateUp() {
    final parts = _currentPath.split('/')..removeWhere((p) => p.isEmpty);
    if (parts.length <= 1) {
      setState(() => _currentPath = '/');
    } else {
      parts.removeLast();
      setState(() => _currentPath = '/${parts.join('/')}');
    }
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.drive_file_move_rounded,
                    color: AppColors.cyan,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.title, style: portixTitle(16))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Current path bar
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_rounded, size: 16, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentPath,
                        overflow: TextOverflow.ellipsis,
                        style: portixTitle(12),
                      ),
                    ),
                    if (_currentPath != '/')
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        onPressed: _navigateUp,
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          size: 16,
                          color: AppColors.muted,
                        ),
                        tooltip: 'Go up',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Folder list
              Expanded(
                child: _loading
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: portixMuted(12),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _entries.isEmpty
                    ? Center(
                        child: Text('Empty directory', style: portixMuted(12)),
                      )
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final isFolder = entry.folder;
                          return InkWell(
                            onTap: isFolder
                                ? () => _navigateInto(entry.name)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isFolder
                                        ? Icons.folder_rounded
                                        : Icons.insert_drive_file_outlined,
                                    color: isFolder
                                        ? AppColors.amber
                                        : AppColors.muted,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      entry.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: isFolder
                                          ? portixTitle(13)
                                          : portixMuted(12),
                                    ),
                                  ),
                                  if (isFolder)
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.muted,
                                      size: 18,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 14),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_currentPath),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Move here'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
