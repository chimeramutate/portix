import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

typedef TerminalInputHandler = void Function(String data, String? sessionId);
typedef TerminalResizeHandler =
    void Function(int cols, int rows, String? sessionId);

class TerminalSessionUiController {
  TerminalSessionUiController({
    required TerminalInputHandler onInput,
    required TerminalResizeHandler onResize,
  }) : _onInput = onInput,
       _onResize = onResize {
    idleTerminal = _createTerminal();
    idleController = TerminalController();
    idleFocusNode = FocusNode(debugLabel: 'terminal-idle');
  }

  final TerminalInputHandler _onInput;
  final TerminalResizeHandler _onResize;
  final Map<String, Terminal> _terminals = {};
  final Map<String, TerminalController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  late final Terminal idleTerminal;
  late final TerminalController idleController;
  late final FocusNode idleFocusNode;

  Terminal terminalForSession(String sessionId) {
    return _terminals.putIfAbsent(
      sessionId,
      () => _createTerminal(sessionId: sessionId),
    );
  }

  TerminalController controllerForSession(String sessionId) {
    return _controllers.putIfAbsent(sessionId, TerminalController.new);
  }

  FocusNode focusNodeForSession(String sessionId) {
    return _focusNodes.putIfAbsent(
      sessionId,
      () => FocusNode(debugLabel: 'terminal-$sessionId'),
    );
  }

  void disposeSession(String sessionId) {
    _terminals.remove(sessionId);
    _controllers.remove(sessionId)?.dispose();
    _focusNodes.remove(sessionId)?.dispose();
  }

  void dispose() {
    idleController.dispose();
    idleFocusNode.dispose();
    for (final controller in _controllers.values) {
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
    );
  }
}
