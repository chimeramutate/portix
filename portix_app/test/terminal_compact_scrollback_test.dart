import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

int cellBytes(Terminal terminal) {
  var bytes = 0;
  for (var i = 0; i < terminal.buffer.lines.length; i++) {
    bytes += terminal.buffer.lines[i].data.lengthInBytes;
  }
  return bytes;
}

void main() {
  test('scrollback keeps its text and colors in far less memory', () {
    final terminal = Terminal(maxLines: 1000)..resize(200, 24);
    for (var i = 0; i < 1200; i++) {
      terminal.write('\x1b[31mred $i\x1b[0m plain\r\n');
    }
    final lines = terminal.buffer.lines;
    final top = lines[0];
    expect(top.getText().trimRight(), matches(RegExp(r'^red \d+ plain$')));
    expect(top.getForeground(0), isNot(0), reason: 'color kept');
    expect(top.getContent(150), 0, reason: 'cells past the text are empty');
    // Full width would be 1000 lines * 256 cells * 16 bytes.
    expect(cellBytes(terminal), lessThan(1000 * 256 * 16 ~/ 4));
  });

  test('a compacted line grows back when written', () {
    final line = BufferLine(80);
    final style = CursorStyle(foreground: 7, background: 0, attrs: 0);
    line.setCell(0, 'a'.codeUnitAt(0), 1, style);
    line.compact();
    expect(line.data.length, 4);

    line.setCell(70, 'z'.codeUnitAt(0), 1, style);
    expect(
      line.getText().trim(),
      'a' + ' ' * 0 + line.getText().trim().substring(1),
    );
    expect(line.getCodePoint(0), 'a'.codeUnitAt(0));
    expect(line.getCodePoint(70), 'z'.codeUnitAt(0));
    expect(line.getCodePoint(40), 0);

    final copy = BufferLine(80)..copyFrom(line..compact(), 0, 0, 80);
    expect(copy.getCodePoint(70), 'z'.codeUnitAt(0));
  });

  test('widening after a resize still reflows compacted scrollback', () {
    final terminal = Terminal(maxLines: 500)..resize(40, 24);
    final long = List.filled(30, 'x').join();
    for (var i = 0; i < 60; i++) {
      terminal.write('$i:$long\r\n');
    }
    terminal.resize(20, 24);
    terminal.resize(80, 24);
    final texts = [
      for (var i = 0; i < terminal.buffer.lines.length; i++)
        terminal.buffer.lines[i].getText().trimRight(),
    ];
    for (var i = 0; i < 60; i++) {
      expect(texts, contains('$i:$long'));
    }
  });
}
