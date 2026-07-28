import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('CtrlInputHandler Tests', () {
    late CtrlInputHandler handler;
    late Terminal terminal;

    TerminalKeyboardEvent createEvent({
      required TerminalKey key,
      bool ctrl = true,
      bool shift = false,
      bool alt = false,
    }) {
      return TerminalKeyboardEvent(
        key: key,
        shift: shift,
        ctrl: ctrl,
        alt: alt,
        state: terminal,
        altBuffer: false,
        platform: TerminalTargetPlatform.linux,
      );
    }

    setUp(() {
      handler = const CtrlInputHandler();
      terminal = Terminal();
    });

    group('Standard Ctrl+A through Ctrl+Z', () {
      test('Ctrl+A produces character 1', () {
        final event = createEvent(key: TerminalKey.keyA);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(1)));
      });

      test('Ctrl+B produces character 2', () {
        final event = createEvent(key: TerminalKey.keyB);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(2)));
      });

      test('Ctrl+Z produces character 26', () {
        final event = createEvent(key: TerminalKey.keyZ);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(26)));
      });

      test('Ctrl+C produces ETX (interrupt)', () {
        final event = createEvent(key: TerminalKey.keyC);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(3)));
        expect(result, equals('\x03')); // ETX
      });

      test('Ctrl+D produces EOT (logout)', () {
        final event = createEvent(key: TerminalKey.keyD);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(4)));
        expect(result, equals('\x04')); // EOT
      });

      test('Ctrl+G produces BEL (bell)', () {
        final event = createEvent(key: TerminalKey.keyG);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(7)));
        expect(result, equals('\x07')); // BEL
      });

      test('Ctrl+U produces NAK (line kill)', () {
        final event = createEvent(key: TerminalKey.keyU);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(21)));
        expect(result, equals('\x15')); // NAK
      });

      test('Ctrl+W produces ETB (word erase)', () {
        final event = createEvent(key: TerminalKey.keyW);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(23)));
        expect(result, equals('\x17')); // ETB
      });
    });

    group('Ctrl with special keys', () {
      test(
        'Ctrl+] produces GS (Group Separator) - critical for telnet exit',
        () {
          final event = createEvent(key: TerminalKey.bracketRight);
          final result = handler(event);
          expect(result, equals(String.fromCharCode(0x1d)));
          expect(result, equals('\x1d')); // GS
        },
      );

      test('Ctrl+[ produces ESC', () {
        final event = createEvent(key: TerminalKey.bracketLeft);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(0x1b)));
        expect(result, equals('\x1b')); // ESC
      });

      test('Ctrl+\\ produces FS (File Separator)', () {
        final event = createEvent(key: TerminalKey.backslash);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(0x1c)));
        expect(result, equals('\x1c')); // FS
      });

      test('Ctrl+; produces US (Unit Separator)', () {
        final event = createEvent(key: TerminalKey.semicolon);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(0x1f)));
        expect(result, equals('\x1f')); // US
      });

      test('Ctrl+/ produces US (Unit Separator) - for telnet interrupt', () {
        final event = createEvent(key: TerminalKey.slash);
        final result = handler(event);
        expect(result, equals(String.fromCharCode(0x1f)));
        expect(result, equals('\x1f')); // US
      });
    });

    group('Non-control events return null', () {
      test('Plain key without Ctrl returns null', () {
        final event = createEvent(key: TerminalKey.keyA, ctrl: false);
        final result = handler(event);
        expect(result, isNull);
      });

      test('Ctrl+Shift returns null', () {
        final event = createEvent(key: TerminalKey.keyA, shift: true);
        final result = handler(event);
        expect(result, isNull);
      });

      test('Ctrl+Alt returns null', () {
        final event = createEvent(key: TerminalKey.keyA, alt: true);
        final result = handler(event);
        expect(result, isNull);
      });
    });
  });
}
