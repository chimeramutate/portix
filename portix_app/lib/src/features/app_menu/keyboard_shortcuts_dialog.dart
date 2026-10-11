import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/repositories/settings/index.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_shortcuts.dart';

import 'app_menu.dart';

Future<void> showKeyboardShortcutsDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => const KeyboardShortcutsDialog(),
    );

final _modifierKeys = {
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

/// VS Code-style editor: click a shortcut, press the new keys, it is saved.
class KeyboardShortcutsDialog extends StatefulWidget {
  const KeyboardShortcutsDialog({super.key});

  @override
  State<KeyboardShortcutsDialog> createState() =>
      _KeyboardShortcutsDialogState();
}

class _KeyboardShortcutsDialogState extends State<KeyboardShortcutsDialog> {
  TerminalBindings _bindings = terminalBindingsFrom(const {});
  TerminalCommand? _recording;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final values = await sl<SettingsRepository>().loadSettings();
      if (mounted) setState(() => _bindings = terminalBindingsFrom(values));
    } catch (_) {
      // Unreadable settings: the defaults are shown.
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final command = _recording;
    if (command == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _recording = null);
      return KeyEventResult.handled;
    }
    if (_modifierKeys.contains(key)) return KeyEventResult.handled;
    final keyboard = HardwareKeyboard.instance;
    final binding = SingleActivator(
      key,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
    final error = keyError(command, binding, _bindings);
    if (error != null) {
      setState(() => _error = error);
      return KeyEventResult.handled;
    }
    _set(command, binding);
    return KeyEventResult.handled;
  }

  void _set(TerminalCommand command, SingleActivator binding) {
    final isDefault = sameBinding(binding, command.defaultBinding);
    setState(() {
      _bindings = {..._bindings, command: binding};
      _recording = null;
      _error = '';
    });
    unawaited(
      saveTerminalSetting(
        command.settingKey,
        isDefault ? null : formatBinding(binding),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Keyboard Shortcuts', style: portixTitle(15)),
                const SizedBox(height: 4),
                Text(
                  'Click a shortcut, then press the new keys. Esc cancels.',
                  style: portixMuted(),
                ),
                const SizedBox(height: 12),
                for (final command in TerminalCommand.editable) _row(command),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_error, style: TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(TerminalCommand command) {
    final binding = _bindings[command]!;
    final recording = _recording == command;
    final customized = !sameBinding(binding, command.defaultBinding);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(command.label, style: TextStyle(color: AppColors.text)),
          ),
          OutlinedButton(
            key: ValueKey('shortcut-${command.name}'),
            onPressed: () => setState(() {
              _recording = recording ? null : command;
              _error = '';
            }),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(150, 32),
              foregroundColor: recording ? AppColors.cyan : AppColors.text,
            ),
            child: Text(recording ? 'Press keys…' : formatBinding(binding)),
          ),
          SizedBox(
            width: 36,
            child: customized
                ? IconButton(
                    tooltip:
                        'Reset to ${formatBinding(command.defaultBinding)}',
                    iconSize: 16,
                    onPressed: () => _set(command, command.defaultBinding),
                    icon: Icon(Icons.undo_rounded, color: AppColors.muted),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

bool sameBinding(SingleActivator a, SingleActivator b) => bindingMatches(
  a,
  b.trigger,
  control: b.control,
  shift: b.shift,
  alt: b.alt,
  meta: b.meta,
);

/// Why [binding] can't be used for [command], or null when it can.
String? keyError(
  TerminalCommand command,
  SingleActivator binding,
  TerminalBindings current,
) {
  if (!binding.control && !binding.alt && !binding.meta) {
    return 'Add Ctrl, Alt or Cmd so the key still types in the terminal.';
  }
  for (final other in TerminalCommand.editable) {
    if (other != command && sameBinding(current[other]!, binding)) {
      return '${formatBinding(binding)} is already used by ${other.label}.';
    }
  }
  return null;
}
