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
            Text('Open with local editor', style: portixTitle(16)),
            const SizedBox(height: 10),
            for (final editor in editors)
              ListTile(
                dense: true,
                leading: _buildEditorIcon(editor),
                title: Text(editor.name, style: portixTitle(13)),
                subtitle: Text(
                  [editor.command, ...editor.arguments].join(' '),
                  style: portixMuted(11),
                ),
                onTap: () => Navigator.of(context).pop(editor),
              ),
          ],
        ),
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
