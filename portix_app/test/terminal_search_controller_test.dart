import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_search_controller.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_themes.dart';
import 'package:xterm/xterm.dart';

void main() {
  Terminal terminalWith(String output) =>
      Terminal(maxLines: 1000)..write(output);

  test('finds every case-insensitive match, scrollback included', () {
    final terminal = terminalWith(
      [for (var i = 0; i < 60; i++) 'line $i'].join('\r\n') +
          '\r\nError: disk full\r\nok\r\nerror again, ERROR',
    );

    final matches = findInTerminal(terminal, 'error');

    expect(matches, hasLength(3));
    expect(matches.first, (line: 60, start: 0, end: 5));
    expect(matches[1], (line: 62, start: 0, end: 5));
    expect(matches[2], (line: 62, start: 13, end: 18));
    expect(findInTerminal(terminal, ''), isEmpty);
  });

  test('stops at the match cap', () {
    final terminal = terminalWith(List.filled(30, 'a' * 70).join('\r\n'));
    expect(findInTerminal(terminal, 'a'), hasLength(maxTerminalMatches));
  });

  test('highlights all matches and cycles through them from the newest', () {
    final terminal = terminalWith('foo\r\nbar\r\nfoo foo');
    final controller = TerminalController();
    final revealed = <int>[];
    final search = TerminalSearchController(
      terminal: terminal,
      controller: controller,
      theme: portixBuiltinTheme,
      reveal: revealed.add,
    );

    search.search('FOO');
    expect(search.matchCount, 3);
    expect(search.current, 2, reason: 'newest match first');
    expect(controller.highlights, hasLength(3));
    expect(
      controller.highlights
          .where(
            (h) => h.color == portixBuiltinTheme.searchHitBackgroundCurrent,
          )
          .single
          .range!
          .begin,
      const CellOffset(4, 2),
    );

    search.next();
    expect(search.current, 0, reason: 'wraps around');
    search.previous();
    search.previous();
    expect(search.current, 1);
    expect(revealed, [2, 0, 2, 2]);

    search.dispose();
    expect(controller.highlights, isEmpty);
  });
}
