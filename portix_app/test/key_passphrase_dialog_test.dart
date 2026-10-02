import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/key_passphrase_dialog.dart';

void main() {
  // Messages produced by Rust PortixError (see ssh_client.rs key_loading_tests).
  test('recognizes the backend passphrase errors', () {
    expect(
      keyPassphraseProblemOf(
        'Failed to connect: SSH key /k is encrypted; a passphrase is required',
      ),
      KeyPassphraseProblem.required,
    );
    expect(
      keyPassphraseProblemOf('Failed: wrong passphrase for SSH key /k'),
      KeyPassphraseProblem.incorrect,
    );
    expect(keyPassphraseProblemOf('connection timed out'), isNull);
  });
}
