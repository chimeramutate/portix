import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

/// Commands the user can rebind from Terminal > Keyboard Shortcuts.
/// [settingKey]s for copy/paste are the old Settings keys, so values saved
/// there ("Shift+Ctrl+C") still load.
enum TerminalCommand {
  copy('Copy', 'general.terminal_copy_shortcut'),
  paste('Paste', 'general.terminal_paste_shortcut'),
  find('Find in terminal', 'keybinding.find'),
  snippets('Snippets', 'keybinding.snippets'),
  zoomIn('Zoom in', 'keybinding.zoom_in'),
  zoomOut('Zoom out', 'keybinding.zoom_out'),
  zoomReset('Reset zoom', 'keybinding.zoom_reset');

  const TerminalCommand(this.label, this.settingKey);

  final String label;
  final String settingKey;

  /// macOS: Cmd. Elsewhere Ctrl+Shift, because plain Ctrl+F / Ctrl+- belong
  /// to the shell (readline). Copy/paste are only rebindable on Linux; macOS
  /// keeps the native Cmd+C / Cmd+V.
  SingleActivator get defaultBinding {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) => mac
        ? SingleActivator(key, meta: true, shift: shift)
        : SingleActivator(key, control: true, shift: true);
    return switch (this) {
      copy => terminalDefaultCopyBinding,
      paste => terminalDefaultPasteBinding,
      find => cmd(LogicalKeyboardKey.keyF),
      snippets => cmd(LogicalKeyboardKey.keyP, shift: true),
      zoomIn => cmd(LogicalKeyboardKey.equal),
      zoomOut => cmd(LogicalKeyboardKey.minus),
      zoomReset => cmd(LogicalKeyboardKey.digit0),
    };
  }

  /// Commands shown in the shortcut editor on this platform.
  static List<TerminalCommand> get editable =>
      defaultTargetPlatform == TargetPlatform.linux
      ? values
      : values.where((c) => c != copy && c != paste).toList();
}

const terminalDefaultCopyBinding = SingleActivator(
  LogicalKeyboardKey.keyC,
  control: true,
  shift: true,
);
const terminalDefaultPasteBinding = SingleActivator(
  LogicalKeyboardKey.keyV,
  control: true,
);

typedef TerminalBindings = Map<TerminalCommand, SingleActivator>;

TerminalBindings terminalBindingsFrom(Map<String, String> values) => {
  for (final command in TerminalCommand.values)
    command: parseBinding(values[command.settingKey]) ?? command.defaultBinding,
};

/// "Ctrl+Shift+C". The key comes last, so "Ctrl++" is Ctrl and the + key.
String formatBinding(SingleActivator binding) => [
  if (binding.control) 'Ctrl',
  if (binding.shift) 'Shift',
  if (binding.alt) 'Alt',
  if (binding.meta) 'Cmd',
  binding.trigger.keyLabel,
].join('+');

SingleActivator? parseBinding(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final plusKey = text.endsWith('+');
  final parts = (plusKey ? text.substring(0, text.length - 1) : text)
      .split('+')
      .where((part) => part.isNotEmpty)
      .toList();
  final label = (plusKey ? '+' : parts.removeLast()).toLowerCase();
  final mods = {for (final part in parts) part.toLowerCase()};
  if (!mods.every({'ctrl', 'shift', 'alt', 'cmd'}.contains)) return null;
  for (final key in LogicalKeyboardKey.knownLogicalKeys) {
    if (key.keyLabel.toLowerCase() != label) continue;
    return SingleActivator(
      key,
      control: mods.contains('ctrl'),
      shift: mods.contains('shift'),
      alt: mods.contains('alt'),
      meta: mods.contains('cmd'),
    );
  }
  return null;
}

/// Shift turns = into + (and so on) on some layouts; treat them as one key.
LogicalKeyboardKey _canonicalKey(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.add ||
  LogicalKeyboardKey.numpadAdd => LogicalKeyboardKey.equal,
  LogicalKeyboardKey.underscore ||
  LogicalKeyboardKey.numpadSubtract => LogicalKeyboardKey.minus,
  LogicalKeyboardKey.parenthesisRight ||
  LogicalKeyboardKey.numpad0 => LogicalKeyboardKey.digit0,
  _ => key,
};

bool bindingMatches(
  SingleActivator binding,
  LogicalKeyboardKey key, {
  required bool control,
  required bool shift,
  required bool alt,
  required bool meta,
}) =>
    _canonicalKey(binding.trigger) == _canonicalKey(key) &&
    binding.control == control &&
    binding.shift == shift &&
    binding.alt == alt &&
    binding.meta == meta;

bool _isPlainCtrlC(SingleActivator binding) => bindingMatches(
  binding,
  LogicalKeyboardKey.keyC,
  control: true,
  shift: false,
  alt: false,
  meta: false,
);

Map<ShortcutActivator, Intent> terminalShortcutsFor({
  required SingleActivator copyShortcut,
  required SingleActivator pasteShortcut,
  required TerminalController controller,
  required Terminal terminal,
}) {
  // NOTE: Ctrl+A (SelectAll) is intentionally NOT registered here.
  // Many TUI apps (less, vim, emacs, tmux, readline) use Ctrl+A for
  // "go to beginning of line" or other navigation — intercepting it at the
  // Flutter level would break those apps silently.
  return {
    copyShortcut: CopySelectionTextIntent.copy,
    // Unless Ctrl+C itself is the copy key, it copies ONLY when text is
    // selected; with no selection it falls through so xterm sends \x03
    // (SIGINT) to the running process as normal.
    if (!_isPlainCtrlC(copyShortcut) && !_isPlainCtrlC(pasteShortcut))
      const SingleActivator(LogicalKeyboardKey.keyC, control: true):
          const _CtrlCConditionalCopyIntent(),
    pasteShortcut: const PasteTextIntent(SelectionChangedCause.keyboard),
  };
}

/// An intent that copies the current terminal selection when text is selected,
/// and explicitly does nothing (so the key falls through to xterm) when there
/// is no selection.
///
/// Used for Ctrl+C when another key copies, so the same
/// key can both interrupt processes (no selection → \x03 reaches the shell) and
/// copy highlighted text (selection present → clipboard copy fires).
class _CtrlCConditionalCopyIntent extends Intent {
  const _CtrlCConditionalCopyIntent();
}

/// Action that handles [_CtrlCConditionalCopyIntent].
///
/// * **Selection present** – copies text, returns true from [consumesKey] so
///   the Shortcuts widget marks the key event as handled and xterm does NOT
///   also receive \x03.
/// * **No selection** – does nothing, returns false from [consumesKey] so the
///   Shortcuts widget marks the event as ignored, allowing xterm to forward
///   the raw \x03 (SIGINT) to the running process.
class TerminalCtrlCCopyAction extends Action<_CtrlCConditionalCopyIntent> {
  TerminalCtrlCCopyAction({required this.controller});

  final TerminalController controller;

  bool get _hasSelection => controller.selection != null;

  @override
  Object? invoke(_CtrlCConditionalCopyIntent intent) {
    if (!_hasSelection) return null;
    Actions.maybeInvoke(primaryFocus!.context!, CopySelectionTextIntent.copy);
    return null;
  }

  @override
  bool isEnabled(_CtrlCConditionalCopyIntent intent) => true;

  /// Consume the key only when there is something to copy.  When false, the
  /// Shortcuts widget propagates the event as unhandled → xterm gets \x03.
  @override
  bool consumesKey(_CtrlCConditionalCopyIntent intent) => _hasSelection;
}

const minTerminalFontSize = 8.0;
const maxTerminalFontSize = 32.0;
