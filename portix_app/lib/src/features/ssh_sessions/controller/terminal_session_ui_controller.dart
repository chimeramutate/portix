import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

typedef TerminalInputHandler = void Function(String data, String? sessionId);
typedef TerminalResizeHandler =
    void Function(int cols, int rows, String? sessionId);
typedef TerminalDirectoryHandler = void Function(String path, String sessionId);

/// Shell working directory from OSC 7 (`file://host/path`) or the
/// `user@host: path` title default bash/zsh prompts set; null if neither.
String? terminalDirectoryFrom({String? title, String? osc7}) {
  if (osc7 != null) {
    final uri = Uri.tryParse(osc7);
    return uri != null && uri.scheme == 'file' && uri.path.isNotEmpty
        ? Uri.decodeComponent(uri.path)
        : null;
  }
  final match = RegExp(
    r'^[^@\s]+@[^:\s]+:\s*([~/].*?)\s*$',
  ).firstMatch(title ?? '');
  return match?.group(1);
}

/// [path] as a POSIX shell word: single-quoted, but a leading `~` stays
/// unquoted so the shell still expands it to the home directory.
String shellQuotePath(String path) {
  String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
  if (path == '~') return '~';
  if (path.startsWith('~/')) return '~/${quote(path.substring(2))}';
  return quote(path);
}

class TerminalSessionUiController {
  TerminalSessionUiController({
    required TerminalInputHandler onInput,
    required TerminalResizeHandler onResize,
    TerminalDirectoryHandler? onDirectoryChanged,
  }) : _onInput = onInput,
       _onResize = onResize,
       _onDirectoryChanged = onDirectoryChanged {
    idleTerminal = _createTerminal();
    idleController = TerminalController();
    idleScrollController = ScrollController();
    idleFocusNode = FocusNode(debugLabel: 'terminal-idle');
    idleViewKey = GlobalKey<TerminalViewState>();
  }

  final TerminalInputHandler _onInput;
  final TerminalResizeHandler _onResize;
  final TerminalDirectoryHandler? _onDirectoryChanged;
  final Map<String, Terminal> _terminals = {};
  final Map<String, TerminalController> _controllers = {};
  final Map<String, ScrollController> _scrollControllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, GlobalKey<TerminalViewState>> _viewKeys = {};

  late final Terminal idleTerminal;
  late final TerminalController idleController;
  late final ScrollController idleScrollController;
  late final FocusNode idleFocusNode;
  late final GlobalKey<TerminalViewState> idleViewKey;

  Terminal terminalForSession(String sessionId) {
    return _terminals.putIfAbsent(
      sessionId,
      () => _createTerminal(sessionId: sessionId),
    );
  }

  TerminalController controllerForSession(String sessionId) {
    return _controllers.putIfAbsent(sessionId, TerminalController.new);
  }

  ScrollController scrollControllerForSession(String sessionId) {
    return _scrollControllers.putIfAbsent(sessionId, ScrollController.new);
  }

  FocusNode focusNodeForSession(String sessionId) {
    return _focusNodes.putIfAbsent(
      sessionId,
      () => FocusNode(debugLabel: 'terminal-$sessionId'),
    );
  }

  GlobalKey<TerminalViewState> viewKeyForSession(String sessionId) {
    return _viewKeys.putIfAbsent(sessionId, GlobalKey<TerminalViewState>.new);
  }

  void disposeSession(String sessionId) {
    _terminals.remove(sessionId);
    _controllers.remove(sessionId)?.dispose();
    _scrollControllers.remove(sessionId)?.dispose();
    _focusNodes.remove(sessionId)?.dispose();
    _viewKeys.remove(sessionId);
  }

  void dispose() {
    idleController.dispose();
    idleScrollController.dispose();
    idleFocusNode.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
  }

  Terminal _createTerminal({String? sessionId}) {
    return Terminal(
      maxLines: 5000,
      onOutput: (data) => _onInput(data, sessionId),
      onResize: (cols, rows, _, _) => _onResize(cols, rows, sessionId),
      onTitleChange: (title) => _reportDirectory(sessionId, title: title),
      onPrivateOSC: (code, args) {
        if (code == '7' && args.isNotEmpty) {
          _reportDirectory(sessionId, osc7: args.first);
        }
      },
    );
  }

  void _reportDirectory(String? sessionId, {String? title, String? osc7}) {
    if (sessionId == null) return;
    final path = terminalDirectoryFrom(title: title, osc7: osc7);
    if (path != null) _onDirectoryChanged?.call(path, sessionId);
  }
}
