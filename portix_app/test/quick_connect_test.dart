import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/ssh_sessions/controller/quick_connect.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_profile_picker_dialog.dart';

QuickConnectTarget? parse(String input) =>
    parseQuickConnect(input, defaultUser: 'me');

void main() {
  test('parses what one would type after ssh', () {
    expect(parse('deploy@10.0.0.5'), (
      user: 'deploy',
      host: '10.0.0.5',
      port: 22,
    ));
    expect(parse('deploy@web.example.com:2222'), (
      user: 'deploy',
      host: 'web.example.com',
      port: 2222,
    ));
    expect(parse('ssh root@box -p 2200'), (
      user: 'root',
      host: 'box',
      port: 2200,
    ));
    expect(parse('10.0.0.5'), (user: 'me', host: '10.0.0.5', port: 22));
    expect(parse('u@[fe80::1]:22'), (user: 'u', host: 'fe80::1', port: 22));
    expect(parse('localhost'), (user: 'me', host: 'localhost', port: 22));
  });

  test('profile searches and invalid input are not addresses', () {
    expect(parse('prod'), isNull); // bare word: a search
    expect(parse('prod api'), isNull);
    expect(parse(''), isNull);
    expect(parse('u@host:70000'), isNull);
    expect(parse('u@host:0'), isNull);
  });

  test('label and profile', () {
    final target = parse('u@[fe80::1]:2222')!;
    expect(quickConnectLabel(target), 'u@[fe80::1]:2222');
    expect(quickConnectLabel(parse('u@h.io')!), 'u@h.io');
    final profile = quickConnectProfile(target);
    expect(profile.authMethod, AuthMethod.password);
    expect(profile.credentialLabel, isEmpty);
    expect(profile.group, 'Quick connect');
    expect(
      (profile.host, profile.port, profile.username),
      ('fe80::1', 2222, 'u'),
    );
  });

  Future<Object?> pickWith(
    WidgetTester tester,
    List<SshProfile> profiles,
    String typed,
  ) async {
    Object? picked = 'nothing';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showDialog<SshProfile>(
                context: context,
                builder: (_) => SessionProfilePickerDialog(
                  profiles: profiles,
                  activeProfileId: null,
                  localUser: 'me',
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-session-search')),
      typed,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('quick-connect-option')), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('Enter on an address picks a new quick connect profile', (
    tester,
  ) async {
    final picked = await pickWith(tester, const [], 'ops@db.internal:2200');
    expect(picked, isA<SshProfile>());
    final profile = picked! as SshProfile;
    expect(profile.id, 'quick-ops@db.internal:2200');
    expect(profile.port, 2200);
  });

  testWidgets('an address of a saved profile opens that profile', (
    tester,
  ) async {
    final saved = quickConnectProfile((
      user: 'ops',
      host: 'db.internal',
      port: 22,
    )).copyWith(id: 'saved-db', name: 'Database');
    final picked = await pickWith(tester, [saved], 'ops@db.internal');
    expect((picked! as SshProfile).id, 'saved-db');
  });
}
