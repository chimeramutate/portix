import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Exact bytes `Terminal.keyInput` sends for cursor keys and Backspace in
/// a full-screen TUI (alt buffer, optionally DECCKM).
void main() {
  /// Drives the terminal into the alternate screen buffer (the mode vi/nano
  /// use) and optionally into application cursor-keys mode (`\x1b[?1h`, a.k.a.
  /// DECCKM), and returns the list of output chunks produced by subsequent
  /// [Terminal.keyInput] calls.
  List<String> captureKeyInput(
    TerminalKey key, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool appCursorKeys = false,
  }) {
    final output = <String>[];
    final terminal = Terminal(onOutput: (data) => output.add(data));

    // Enter the alternate screen buffer (vi/nano).
    terminal.write('\x1b[?1049h');
    // Optionally enable application cursor keys mode.
    if (appCursorKeys) {
      terminal.write('\x1b[?1h');
    }

    // Sanity check the mode we just requested is actually reflected by the
    // terminal state that the keytab handler reads.
    assert(terminal.isUsingAltBuffer, 'terminal should be in the alt buffer');
    assert(
      !appCursorKeys || terminal.cursorKeysMode,
      'cursorKeysMode should be enabled when appCursorKeys is requested',
    );

    output.clear();
    final handled = terminal.keyInput(key, ctrl: ctrl, alt: alt, shift: shift);

    // A false return means the key was not handled by any input handler, which
    // is a bug for the keys under test.
    assert(handled, 'keyInput should handle $key');

    return output;
  }

  group('cursor keys in application cursor keys mode (vi/vim)', () {
    // vi/vim enable `\x1b[?1h` (DEC private mode 1, DECCKM) so the terminal
    // must send the SS3 form (`ESC O A` / `ESC O B` / ...) for the plain arrow
    // keys.
    test('Up sends SS3 form', () {
      final output = captureKeyInput(TerminalKey.arrowUp, appCursorKeys: true);
      expect(output, ['\x1bOA']);
    });

    test('Down sends SS3 form', () {
      final output = captureKeyInput(
        TerminalKey.arrowDown,
        appCursorKeys: true,
      );
      expect(output, ['\x1bOB']);
    });

    test('Left sends SS3 form', () {
      final output = captureKeyInput(
        TerminalKey.arrowLeft,
        appCursorKeys: true,
      );
      expect(output, ['\x1bOD']);
    });

    test('Right sends SS3 form', () {
      final output = captureKeyInput(
        TerminalKey.arrowRight,
        appCursorKeys: true,
      );
      expect(output, ['\x1bOC']);
    });
  });

  group('cursor keys in normal cursor keys mode (shell/nano default)', () {
    // In the alt buffer but with normal cursor keys, the CSI form must be sent.
    test('Up/Down/Left/Right send the CSI form', () {
      expect(captureKeyInput(TerminalKey.arrowUp), ['\x1b[A']);
      expect(captureKeyInput(TerminalKey.arrowDown), ['\x1b[B']);
      expect(captureKeyInput(TerminalKey.arrowLeft), ['\x1b[D']);
      expect(captureKeyInput(TerminalKey.arrowRight), ['\x1b[C']);
    });
  });

  group('single emission per press', () {
    // One DEL per press, alt buffer or not; a double delivery was the
    // reported "backspace jumps" bug.
    test('Backspace emits exactly one DEL (\\x7f) in the alt buffer', () {
      final output = captureKeyInput(TerminalKey.backspace);
      expect(output, ['\x7f']);
    });

    test('Backspace emits exactly one DEL when app cursor keys is active', () {
      final output = captureKeyInput(
        TerminalKey.backspace,
        appCursorKeys: true,
      );
      expect(output, ['\x7f']);
    });

    test('Arrow Down emits exactly one sequence, not duplicated', () {
      final output = captureKeyInput(
        TerminalKey.arrowDown,
        appCursorKeys: true,
      );
      expect(output, hasLength(1));
      expect(output.single, '\x1bOB');
    });
  });
}
