import '../../../connection_manager/session_models.dart';

class TerminalSuggestion {
  const TerminalSuggestion({
    required this.command,
    required this.source,
    String? display,
    this.description = '',
  }) : display = display ?? command;

  final String command;
  final String display;
  final String description;
  final TerminalSuggestionSource source;

  @override
  bool operator ==(Object other) {
    return other is TerminalSuggestion && other.command == command;
  }

  @override
  int get hashCode => command.hashCode;
}

enum TerminalSuggestionSource { history, remoteHelp }

class TerminalSuggestionController {
  static const settingsKey = 'general.terminal_suggestions';
  static const _maxCommandLength = 240;
  static const _maxHistoryItems = 80;

  final Map<String, String> _buffers = {};
  final Map<String, List<String>> _historyBySession = {};
  final Map<String, List<TerminalSuggestion>> _remoteHelpBySession = {};
  final Map<String, List<TerminalSuggestion>> _candidatesBySession = {};
  final Map<String, TerminalSuggestion> _suggestions = {};
  final Map<String, int> _selectedIndexBySession = {};
  bool _enabled = true;

  bool get enabled => _enabled;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) clear();
  }

  TerminalSuggestion? suggestionFor(String sessionId) {
    if (!_enabled) return null;
    return _suggestions[sessionId];
  }

  List<TerminalSuggestion> candidatesFor(String sessionId) {
    if (!_enabled) return const [];
    return _candidatesBySession[sessionId] ?? const [];
  }

  bool canAcceptSuggestionWithEnter(String sessionId) {
    if (!_enabled) return false;
    if (candidatesFor(sessionId).isEmpty) return false;
    return _suggestions[sessionId]?.source == TerminalSuggestionSource.history;
  }

  bool handleInput(String sessionId, String data) {
    if (!_enabled) return false;
    if (data.isEmpty) return false;

    var changed = false;
    final units = data.codeUnits;
    var i = 0;
    while (i < units.length) {
      final unit = units[i];

      // Skip ANSI escape sequences in their entirety.  Their printable body
      // (e.g. the `[A`/`[D` of arrow keys, or `3~` of Delete) used to be
      // buffered as typed text, which polluted the suggestion input with
      // `[D[D…[A[A` garbage and surfaced bogus suggestions.  The full
      // sequence is still forwarded to the SSH session by the panel, so
      // shell-side handling (cursor movement, up-history on Enter, etc.) is
      // unaffected.
      if (unit == 0x1b /* ESC */) {
        i = _skipAnsiEscapeSequence(units, i + 1);
        continue;
      }

      changed = _handleCodeUnit(sessionId, unit) || changed;
      i++;
    }
    return changed;
  }

  /// Returns the index in [units] to resume scanning from, having skipped the
  /// ANSI escape sequence that began at `start` (i.e. the byte right after the
  /// introducing `ESC`).  Handles the common CSI / OSC / SS3 families produced
  /// by cursor/home/end/delete keys.  A lone `ESC` or an unrecognised payload
  /// skips only the introducing byte so a following normal character is still
  /// processed as ordinary input.
  static int _skipAnsiEscapeSequence(List<int> units, int start) {
    if (start >= units.length) return start;
    final c1 = units[start];

    // OSC: ESC ] ... ST (ESC \)  or  BEL-terminated.
    if (c1 == 0x5d /* ] */) {
      var i = start + 1;
      while (i < units.length) {
        final u = units[i];
        if (u == 0x07 /* BEL */) return i + 1;
        if (u == 0x1b /* ESC */ &&
            i + 1 < units.length &&
            units[i + 1] == 0x5c /* \ */) {
          return i + 2;
        }
        i++;
      }
      return i;
    }

    // CSI: ESC [ [params] [intermediates] final.  Arrow keys and the
    // home/end/delete family all take this form.
    if (c1 == 0x5b /* [ */) {
      var i = start + 1;
      while (i < units.length) {
        final u = units[i];
        if ((u >= 0x30 && u <= 0x3f) || (u >= 0x20 && u <= 0x2f)) {
          i++;
          continue;
        }
        if (u >= 0x40 && u <= 0x7e) return i + 1; // final byte consumed
        i++;
      }
      return i;
    }

    // SS3 / other ESC-led two-char sequences: ESC O <final>.
    if (c1 == 0x4f /* O */) {
      return (start + 1 < units.length) ? start + 2 : start + 1;
    }

    // Unrecognised ESC payload: don't swallow any more bytes.
    return start;
  }

  String inputFor(String sessionId) => (_buffers[sessionId] ?? '').trimLeft();

  String? completionSuffixFor(String sessionId) {
    if (!_enabled) return null;
    final suggestion = _suggestions[sessionId];
    if (suggestion == null) return null;
    final input = inputFor(sessionId);
    if (input.isEmpty || !suggestion.command.startsWith(input)) return null;
    final suffix = suggestion.command.substring(input.length);
    return suffix.isEmpty ? null : suffix;
  }

  /// Returns the completion suffix for display purposes.
  /// This is the part of the suggestion that will be shown highlighted.
  String? completionDisplaySuffixFor(String sessionId) {
    if (!_enabled) return null;
    final suggestion = _suggestions[sessionId];
    if (suggestion == null) return null;
    final input = inputFor(sessionId);
    if (input.isEmpty || !suggestion.command.startsWith(input)) return null;
    final suffix = suggestion.command.substring(input.length);
    return suffix.isEmpty ? null : suffix;
  }

  String? acceptSuggestion(String sessionId) {
    final suggestion = _suggestions[sessionId];
    final suffix = completionSuffixFor(sessionId);
    if (suggestion == null || suffix == null) return null;
    _buffers[sessionId] = suggestion.command;
    _refreshSuggestion(sessionId);
    return suffix;
  }

  /// Accepts a specific suggestion by command and returns the suffix.
  /// This is useful when the suggestion is selected from the UI.
  String? acceptSpecificSuggestion(
    String sessionId,
    TerminalSuggestion suggestion,
  ) {
    final input = inputFor(sessionId);
    if (input.isEmpty || !suggestion.command.startsWith(input)) return null;
    final suffix = suggestion.command.substring(input.length);
    _buffers[sessionId] = suggestion.command;
    _refreshSuggestion(sessionId);
    return suffix.isEmpty ? null : suffix;
  }

  bool moveSelection(String sessionId, int delta) {
    final candidates = _candidatesBySession[sessionId] ?? const [];
    if (candidates.length < 2) return false;
    final current = _selectedIndexBySession[sessionId] ?? 0;
    final next = (current + delta).clamp(0, candidates.length - 1);
    if (next == current) return false;
    _selectedIndexBySession[sessionId] = next;
    _suggestions[sessionId] = candidates[next];
    return true;
  }

  bool setRemoteHelpSuggestions(String sessionId, List<String> suggestions) {
    return setRemoteCompletions(
      sessionId,
      suggestions.map(TerminalCompletionCandidate.fromWire).toList(),
    );
  }

  bool setRemoteCompletions(
    String sessionId,
    List<TerminalCompletionCandidate> completions,
  ) {
    if (!_enabled) return false;
    final sanitized = completions
        .where((completion) => completion.replacement.trim().length >= 2)
        .where(
          (completion) => completion.replacement.length <= _maxCommandLength,
        )
        .where((completion) => !_isSensitiveCommand(completion.replacement))
        .map(
          (completion) => TerminalSuggestion(
            command: completion.replacement.trim(),
            display: completion.display.trim().isEmpty
                ? completion.replacement.trim()
                : completion.display.trim(),
            description: completion.description.trim(),
            source: TerminalSuggestionSource.remoteHelp,
          ),
        )
        .toSet()
        .take(12)
        .toList(growable: false);
    if (sanitized.isEmpty) {
      _remoteHelpBySession.remove(sessionId);
    } else {
      _remoteHelpBySession[sessionId] = sanitized;
    }
    return _refreshSuggestion(sessionId);
  }

  void clearSession(String sessionId) {
    _buffers.remove(sessionId);
    _historyBySession.remove(sessionId);
    _remoteHelpBySession.remove(sessionId);
    _candidatesBySession.remove(sessionId);
    _suggestions.remove(sessionId);
    _selectedIndexBySession.remove(sessionId);
  }

  void clear() {
    _buffers.clear();
    _historyBySession.clear();
    _remoteHelpBySession.clear();
    _candidatesBySession.clear();
    _suggestions.clear();
    _selectedIndexBySession.clear();
  }

  bool _handleCodeUnit(String sessionId, int codeUnit) {
    if (codeUnit == 13 || codeUnit == 10) {
      _commitBuffer(sessionId);
      return _refreshSuggestion(sessionId);
    }

    if (codeUnit == 3 || codeUnit == 4 || codeUnit == 21) {
      _buffers.remove(sessionId);
      return _refreshSuggestion(sessionId);
    }

    if (codeUnit == 8 || codeUnit == 127) {
      final buffer = _buffers[sessionId] ?? '';
      if (buffer.isNotEmpty) {
        _buffers[sessionId] = buffer.substring(0, buffer.length - 1);
      }
      return _refreshSuggestion(sessionId);
    }

    if (codeUnit < 32 || codeUnit > 126) return false;

    final buffer = _buffers[sessionId] ?? '';
    if (buffer.length >= _maxCommandLength) return false;
    _buffers[sessionId] = '$buffer${String.fromCharCode(codeUnit)}';
    return _refreshSuggestion(sessionId);
  }

  void _commitBuffer(String sessionId) {
    final command = (_buffers.remove(sessionId) ?? '').trim();
    if (command.length < 2) return;
    if (command.length > _maxCommandLength) return;
    if (_isSensitiveCommand(command)) return;

    final history = _historyBySession.putIfAbsent(sessionId, () => []);
    history.remove(command);
    history.add(command);
    if (history.length > _maxHistoryItems) {
      history.removeRange(0, history.length - _maxHistoryItems);
    }
  }

  bool _refreshSuggestion(String sessionId) {
    final previous = _suggestions[sessionId]?.command;
    final previousCandidates = (_candidatesBySession[sessionId] ?? const [])
        .map((suggestion) => suggestion.command)
        .join('\n');
    final prefix = (_buffers[sessionId] ?? '').trimLeft();
    final candidates = <TerminalSuggestion>[];

    if (prefix.length >= 2 && !_isSensitiveCommand(prefix)) {
      final history = _historyBySession[sessionId] ?? const <String>[];
      for (final command in history.reversed) {
        if (command == prefix) continue;
        if (command.startsWith(prefix) && !_isSensitiveCommand(command)) {
          _addCandidate(
            candidates,
            TerminalSuggestion(
              command: command,
              source: TerminalSuggestionSource.history,
            ),
          );
        }
        if (candidates.length >= 4) break;
      }

      for (final suggestion in _remoteHelpSuggestions(sessionId, prefix)) {
        _addCandidate(candidates, suggestion);
      }
    }

    if (candidates.isEmpty) {
      _candidatesBySession.remove(sessionId);
      _suggestions.remove(sessionId);
      _selectedIndexBySession.remove(sessionId);
    } else {
      if (candidates.length > 8) {
        candidates.removeRange(8, candidates.length);
      }
      final selected = (_selectedIndexBySession[sessionId] ?? 0).clamp(
        0,
        candidates.length - 1,
      );
      _selectedIndexBySession[sessionId] = selected;
      _candidatesBySession[sessionId] = List.unmodifiable(candidates);
      final next = candidates[selected];
      _suggestions[sessionId] = next;
    }
    final nextCandidates = (_candidatesBySession[sessionId] ?? const [])
        .map((suggestion) => suggestion.command)
        .join('\n');
    return previous != _suggestions[sessionId]?.command ||
        previousCandidates != nextCandidates;
  }

  void _addCandidate(
    List<TerminalSuggestion> candidates,
    TerminalSuggestion suggestion,
  ) {
    if (candidates.any((item) => item.command == suggestion.command)) return;
    candidates.add(suggestion);
  }

  Iterable<TerminalSuggestion> _remoteHelpSuggestions(
    String sessionId,
    String prefix,
  ) sync* {
    final suggestions =
        _remoteHelpBySession[sessionId] ?? const <TerminalSuggestion>[];
    final currentToken = _currentToken(prefix).toLowerCase();
    for (final suggestion in suggestions) {
      if (suggestion.command == prefix) continue;
      if (_matchesSuggestion(suggestion, prefix, currentToken) &&
          !_isSensitiveCommand(suggestion.command)) {
        yield suggestion;
      }
    }
  }

  bool _matchesSuggestion(
    TerminalSuggestion suggestion,
    String prefix,
    String currentToken,
  ) {
    final command = suggestion.command.toLowerCase();
    final display = suggestion.display.toLowerCase();
    final normalizedPrefix = prefix.toLowerCase();

    // Check if the suggestion command starts with the prefix
    // This ensures we only show relevant completions
    if (command.startsWith(normalizedPrefix)) {
      return true;
    }

    // Also check display for the current token
    // This helps with remote help suggestions
    if (currentToken.isNotEmpty && display.startsWith(currentToken)) {
      return true;
    }

    return false;
  }

  String _currentToken(String input) {
    if (input.isNotEmpty && input.codeUnitAt(input.length - 1) <= 32) {
      return '';
    }
    final parts = input.trimRight().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last;
  }

  /// Gets the current word/token being typed, for suggestion matching.
  /// This is the part after the last space.
  String getCurrentWord(String input) {
    if (input.isEmpty) return '';
    final trimmed = input.trimRight();
    final lastSpace = trimmed.lastIndexOf(' ');
    return lastSpace >= 0 ? trimmed.substring(lastSpace + 1) : trimmed;
  }

  /// Handles when a suggestion is selected from the UI.
  /// Returns the suffix that was added to the buffer.
  String? selectSuggestionFromUI(
    String sessionId,
    TerminalSuggestion suggestion,
  ) {
    return acceptSpecificSuggestion(sessionId, suggestion);
  }

  bool _isSensitiveCommand(String command) {
    final normalized = command.trim();
    if (normalized.isEmpty) return false;
    return _sensitivePatterns.any((pattern) => pattern.hasMatch(normalized));
  }

  static final List<RegExp> _sensitivePatterns = [
    RegExp(
      r'password|passphrase|passwd|secret|token|api[_-]?key|private[_-]?key',
      caseSensitive: false,
    ),
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----', caseSensitive: false),
    RegExp(r'\bsshpass\b', caseSensitive: false),
    RegExp(r'\bsudo\s+-S\b', caseSensitive: false),
    RegExp(r'\b(mysql|mariadb)\b.*\s-p\S*', caseSensitive: false),
    RegExp(r'\bpsql\b.*postgres(?:ql)?:\/\/', caseSensitive: false),
    RegExp(
      r'\bexport\s+[A-Z0-9_]*(PASS|TOKEN|SECRET|KEY)[A-Z0-9_]*=',
      caseSensitive: false,
    ),
    RegExp(
      r'\b[A-Z0-9_]*(PASS|TOKEN|SECRET|KEY)[A-Z0-9_]*=',
      caseSensitive: false,
    ),
    RegExp(
      r'(--password|--pass|--token|--secret|--api-key)(=|\s+)',
      caseSensitive: false,
    ),
  ];
}
