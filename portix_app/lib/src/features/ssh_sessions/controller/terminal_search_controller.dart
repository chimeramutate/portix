import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// A match of the search query: buffer [line], columns [start] to [end].
typedef TerminalMatch = ({int line, int start, int end});

/// Most matches highlighted at once; a short query in a long scrollback
/// could otherwise create tens of thousands of anchors.
const maxTerminalMatches = 1000;

/// Case-insensitive matches of [query] in the terminal's active buffer
/// (scrollback included), top to bottom.
///
/// ponytail: a match broken across a soft-wrapped line is not found, and
/// wide (CJK) characters shift the columns; handle when someone needs it.
List<TerminalMatch> findInTerminal(Terminal terminal, String query) {
  final needle = query.toLowerCase();
  if (needle.isEmpty) return const [];
  final lines = terminal.buffer.lines;
  final matches = <TerminalMatch>[];
  for (var line = 0; line < lines.length; line++) {
    final text = lines[line].getText().toLowerCase();
    var from = 0;
    while (true) {
      final start = text.indexOf(needle, from);
      if (start == -1) break;
      matches.add((line: line, start: start, end: start + needle.length));
      if (matches.length >= maxTerminalMatches) return matches;
      from = start + needle.length;
    }
  }
  return matches;
}

/// Find-in-terminal for one session: highlights every match, marks the
/// current one, and asks the view to [reveal] its line.
class TerminalSearchController extends ChangeNotifier {
  TerminalSearchController({
    required this.terminal,
    required this.controller,
    required this.theme,
    required this.reveal,
  });

  final Terminal terminal;
  final TerminalController controller;
  final TerminalTheme theme;
  final void Function(int line) reveal;

  String _query = '';
  List<TerminalMatch> _matches = const [];
  int _current = -1;
  final List<TerminalHighlight> _highlights = [];

  String get query => _query;
  int get matchCount => _matches.length;

  /// Index of the current match, or -1 when there is none.
  int get current => _current;

  /// Searches from scratch; the current match is the last (most recent).
  void search(String query) {
    _query = query;
    _matches = findInTerminal(terminal, query);
    _current = _matches.length - 1;
    _show();
  }

  void next() => _step(1);

  void previous() => _step(-1);

  void _step(int delta) {
    if (_matches.isEmpty) return search(_query);
    _current = (_current + delta) % _matches.length;
    _show();
  }

  void _show() {
    _clearHighlights();
    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      _highlights.add(
        controller.highlight(
          p1: terminal.buffer.createAnchor(match.start, match.line),
          p2: terminal.buffer.createAnchor(match.end, match.line),
          color: i == _current
              ? theme.searchHitBackgroundCurrent
              : theme.searchHitBackground,
        ),
      );
    }
    if (_current >= 0) reveal(_matches[_current].line);
    notifyListeners();
  }

  void _clearHighlights() {
    for (final highlight in _highlights) {
      highlight.dispose();
    }
    _highlights.clear();
  }

  @override
  void dispose() {
    _clearHighlights();
    super.dispose();
  }
}
