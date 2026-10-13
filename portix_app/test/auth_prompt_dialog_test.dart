import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/auth_prompt_dialog.dart';

class _PromptBackend extends MockConnectionBackend {
  AuthPromptRound? pending;
  final List<List<List<String>>> answered = [];

  @override
  Future<AuthPromptRound?> pendingAuthPrompts(String host, int port) async =>
      pending;

  @override
  Future<void> answerAuthPrompts(
    String host,
    int port,
    List<List<String>> rounds,
  ) async => answered.add(rounds);
}

const _profile = SshProfile(
  id: 'p',
  name: 'p',
  host: 'otp.example.com',
  port: 22,
  username: 'u',
);

AuthPromptRound _round(int round, String prompt) => AuthPromptRound(
  round: round,
  name: '',
  instructions: '',
  prompts: [(prompt: prompt, echo: false)],
);

/// Runs [resolveAuthPrompts] from a button so dialogs have a Navigator, then
/// types [code] (when given) and taps [tapLabel].
Future<bool?> _resolve(
  WidgetTester tester,
  ConnectionManager manager, {
  String? code,
  String tapLabel = '',
}) async {
  bool? result;
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await resolveAuthPrompts(context, manager, _profile);
            done = true;
          },
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  if (code != null) await tester.enterText(find.byType(TextField), code);
  if (tapLabel.isNotEmpty) {
    await tester.tap(find.text(tapLabel));
    await tester.pumpAndSettle();
  }
  expect(done, isTrue);
  return result;
}

void main() {
  testWidgets('no pending prompts: returns null without a dialog', (
    tester,
  ) async {
    final manager = ConnectionManager(backend: _PromptBackend());
    expect(await _resolve(tester, manager), isNull);
    manager.dispose();
  });

  testWidgets('answers accumulate per round and reset on round 0', (
    tester,
  ) async {
    final backend = _PromptBackend()..pending = _round(0, 'Code 1:');
    final manager = ConnectionManager(backend: backend);

    expect(
      await _resolve(tester, manager, code: '111', tapLabel: 'Continue'),
      isTrue,
    );
    backend.pending = _round(1, 'Code 2:');
    expect(
      await _resolve(tester, manager, code: '222', tapLabel: 'Continue'),
      isTrue,
    );
    backend.pending = _round(0, 'Code 1:');
    expect(
      await _resolve(tester, manager, code: '333', tapLabel: 'Continue'),
      isTrue,
    );

    expect(backend.answered, [
      [
        ['111'],
      ],
      [
        ['111'],
        ['222'],
      ],
      [
        ['333'],
      ],
    ]);
    manager.dispose();
  });

  testWidgets('cancel returns false and sends nothing', (tester) async {
    final backend = _PromptBackend()..pending = _round(0, 'Code:');
    final manager = ConnectionManager(backend: backend);
    expect(await _resolve(tester, manager, tapLabel: 'Cancel'), isFalse);
    expect(backend.answered, isEmpty);
    manager.dispose();
  });
}
