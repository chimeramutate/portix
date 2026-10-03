import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_shortcuts.dart';

double? zoom(
  LogicalKeyboardKey key, {
  double current = 13,
  bool meta = false,
  bool control = false,
  bool shift = false,
  bool isMacOS = true,
}) => terminalZoomFontSize(
  key,
  current: current,
  base: 13,
  meta: meta,
  control: control,
  shift: shift,
  isMacOS: isMacOS,
);

void main() {
  test('macOS zooms with Cmd', () {
    expect(zoom(LogicalKeyboardKey.equal, meta: true), 14);
    expect(zoom(LogicalKeyboardKey.minus, meta: true), 12);
    expect(zoom(LogicalKeyboardKey.digit0, meta: true, current: 20), 13);
    expect(zoom(LogicalKeyboardKey.equal), isNull);
    expect(zoom(LogicalKeyboardKey.equal, control: true), isNull);
  });

  test('elsewhere zooms with Ctrl+Shift and leaves Ctrl+- to the shell', () {
    final plain = (bool shift) => zoom(
      LogicalKeyboardKey.minus,
      control: true,
      shift: shift,
      isMacOS: false,
    );
    expect(plain(false), isNull);
    expect(plain(true), 12);
    expect(
      zoom(LogicalKeyboardKey.add, control: true, shift: true, isMacOS: false),
      14,
    );
  });

  test('stays within limits and ignores other keys', () {
    expect(zoom(LogicalKeyboardKey.equal, meta: true, current: 32), 32);
    expect(zoom(LogicalKeyboardKey.minus, meta: true, current: 8), 8);
    expect(zoom(LogicalKeyboardKey.keyA, meta: true), isNull);
  });
}
