import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/profile_secret_store.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart' as manager;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/domain/repositories/ssh/ssh_profile_repository.dart';
import 'package:portix/src/features/kibana/kibana_page.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';

/// Answers every search with one document and records the commands.
class _FakeEs extends MockConnectionBackend {
  final commands = <String>[];

  @override
  Future<String> execOnProfile(
    manager.SshProfile profile,
    String command,
  ) async {
    commands.add(command);
    return '{"took":3,"hits":{"total":{"value":1},"hits":[{"_source":'
        '{"@timestamp":"2026-10-29T10:00:00Z","message":"boom${'!' * commands.length}",'
        '"log":{"level":"error"},"service":"api",'
        '"stack":"${'at frame ' * 50}"}}]},'
        '"aggregations":{"histogram":{"buckets":[{"key":0,"doc_count":4},'
        '{"key":30000,"doc_count":1}]}}}';
  }
}

/// flutter_test answers every HttpClient request with an empty 400; this
/// puts the real one back for the local fake Kibana.
class _RealHttp extends HttpOverrides {}

class _MemorySecrets extends ProfileSecretStore {
  @override
  Future<String?> readPassword(String profileId) async => 'pw';
}

const _box = SshProfile(
  id: 'es',
  name: 'logs-box',
  host: 'example.test',
  port: 22,
  username: 'me',
  group: '',
  tags: [],
  authMethod: AuthMethod.password,
  credentialLabel: '',
  defaultPath: '~',
  status: ConnectionStatus.offline,
  color: ProfileColor.cyan,
);

void main() {
  late _FakeEs backend;
  setUp(() {
    backend = _FakeEs();
    sl.registerSingleton(
      ConnectionManager(
        backend: backend,
        credentials: ProfileCredentials(secretStore: _MemorySecrets()),
      ),
    );
  });
  tearDown(() => sl.reset());

  testWidgets('filter for a field value adds a pill and narrows the query', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('kibana_page');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repository = SshProfileRepository(
      secretStore: _MemorySecrets(),
      storeFile: File('${dir.path}/profiles.json'),
    );
    late SshWorkspaceBloc bloc;
    await tester.runAsync(() async {
      await repository.saveProfile(_box);
      bloc = SshWorkspaceBloc(repository: repository)
        ..add(const ProfilesRequested());
      await bloc.stream.firstWhere((s) => s.profiles.isNotEmpty);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(value: bloc, child: const KibanaPage()),
        ),
      ),
    );
    await tester.tap(find.text('Pick one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('logs-box').last);
    await tester.pumpAndSettle();
    final summary = find.textContaining('boom', findRichText: true);
    expect(summary, findsOneWidget);
    expect(find.text('Documents (1)'), findsOneWidget);
    expect(find.byTooltip(RegExp(r'· 4 documents$')), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );

    // A field opens its top values first; from there it becomes a column.
    await tester.tap(find.text('service'));
    await tester.pumpAndSettle();
    expect(find.text('Top values'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
    await tester.tap(find.text('Add as column'));
    await tester.pumpAndSettle();
    expect(find.text('Top values'), findsNothing, reason: 'popover closed');
    expect(find.text('Summary'), findsNothing);
    expect(find.text('Selected fields'), findsOneWidget);
    expect(find.text('api'), findsOneWidget, reason: 'the column value');
    await tester.tap(find.byTooltip('Copy service'));
    await tester.pumpAndSettle();
    expect(copied, 'api', reason: 'copy right after the cell value');

    // A second column: the first now has an edge to drag wider.
    await tester.tap(find.text('message').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add as column'));
    await tester.pumpAndSettle();
    final api = find.text('api');
    final before = tester
        .getSize(find.ancestor(of: api, matching: find.byType(SizedBox)).first)
        .width;
    await tester.drag(
      find.byKey(const ValueKey('resize service')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    final after = tester
        .getSize(find.ancestor(of: api, matching: find.byType(SizedBox)).first)
        .width;
    expect(after, before + 60);

    // Dragging the "message" header onto "service" swaps them.
    double x(String text) => tester
        .getTopLeft(
          find.descendant(
            of: find.byType(Draggable<String>),
            matching: find.text(text),
          ),
        )
        .dx;
    expect(x('service') < x('message'), isTrue);
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.descendant(
          of: find.byType(Draggable<String>),
          matching: find.text('message'),
        ),
      ),
    );
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(
        find.descendant(
          of: find.byType(Draggable<String>),
          matching: find.text('service'),
        ),
      ),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(x('message') < x('service'), isTrue);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Remove column').first);
      await tester.pumpAndSettle();
    }
    expect(find.text('Summary'), findsOneWidget);

    // Selecting text, short or long drag, or a plain click on it, leaves
    // the row as it is: only the chevron opens a document.
    for (final drag in [const Offset(6, 0), const Offset(120, 0)]) {
      final mouse = await tester.startGesture(
        tester.getTopLeft(summary) + const Offset(4, 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveBy(drag);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('Table'), findsNothing, reason: 'drag $drag');
    }
    await tester.tap(summary, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('Table'), findsNothing, reason: 'click on text');
    // Open with a selection standing: the rebuilt row must not trip
    // SelectionArea's layout assertion.
    await tester.tap(find.byTooltip('Expand document'));
    await tester.pumpAndSettle();
    expect(find.text('Table'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Future<void> selectThen(String step, Future<void> Function() action) async {
      final target = find.textContaining('boom', findRichText: true).first;
      final g = await tester.startGesture(
        tester.getTopLeft(target) + const Offset(4, 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await g.moveBy(const Offset(300, 40));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      await action();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: step);
    }

    await selectThen(
      'collapse',
      () => tester.tap(find.byTooltip('Collapse document')),
    );
    await selectThen(
      'expand',
      () => tester.tap(find.byTooltip('Expand document')),
    );
    await selectThen(
      'column',
      () => tester.tap(find.byTooltip('Add column').first),
    );
    await selectThen(
      'uncolumn',
      () => tester.tap(find.byTooltip('Remove column').first),
    );
    await selectThen('refresh', () => tester.tap(find.text('Refresh')));
    await selectThen(
      'expand2',
      () => tester.tap(find.byTooltip('Expand document')),
    );
    expect(find.byTooltip('Filter out value'), findsNWidgets(5));

    // A long value starts clamped; Show more opens it, Show less closes.
    expect(find.textContaining('Show more'), findsOneWidget);
    await tester.tap(find.textContaining('Show more'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();

    // Each value has its own copy button right after it.
    await tester.tap(find.byTooltip('Copy value').at(3)); // service
    await tester.pumpAndSettle();
    expect(copied, 'api');
    await tester.tap(
      find.byTooltip('Filter out value').at(3),
    ); // @timestamp, log.level, message, service
    await tester.pumpAndSettle();
    expect(find.text('Clear all'), findsOneWidget);
    expect(backend.commands.last, contains(r'(NOT service:\"api\")'));
    expect(tester.takeException(), isNull);
  });

  for (final width in [900.0, 1400.0]) {
    testWidgets('header lays out without a server at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider(
              create: (_) =>
                  SshWorkspaceBloc(repository: SshProfileRepository()),
              child: const KibanaPage(),
            ),
          ),
        ),
      );
      expect(find.text('Pick a server to search from'), findsOneWidget);
      await tester.tap(find.text('Pick one'));
      await tester.pumpAndSettle();
      expect(find.text('No saved servers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('add filter, copy the view and a relative range', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('kibana_tools');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repository = SshProfileRepository(
      secretStore: _MemorySecrets(),
      storeFile: File('${dir.path}/profiles.json'),
    );
    late SshWorkspaceBloc bloc;
    await tester.runAsync(() async {
      await repository.saveProfile(_box);
      bloc = SshWorkspaceBloc(repository: repository)
        ..add(const ProfilesRequested());
      await bloc.stream.firstWhere((s) => s.profiles.isNotEmpty);
    });
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(value: bloc, child: const KibanaPage()),
        ),
      ),
    );
    await tester.tap(find.text('Pick one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('logs-box').last);
    await tester.pumpAndSettle();

    // Add filter: service is one of api, web, with a label.
    await tester.tap(find.text('Add filter'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'service');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dialog, matching: find.text('is')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('is one of').last);
    await tester.pumpAndSettle();
    // Suggestions open on an empty "is one of" value (this used to
    // throw), show the bare value, and keep what came before the comma.
    await tester.tap(fields.at(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(fields.at(1), 'web, a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('api').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, 'web, api');
    await tester.enterText(fields.at(1), 'api, web');
    await tester.enterText(fields.at(2), 'Services');
    await tester.pumpAndSettle();
    expect(find.text('service:("api" OR "web")'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add filter'));
    await tester.pumpAndSettle();
    expect(find.text('Services', findRichText: true), findsOneWidget);
    expect(backend.commands.last, contains(r'(service:(\"api\" OR \"web\"))'));

    // Edit: the pill's menu reopens the filter, filled in.
    await tester.tap(find.text('Services', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit filter'));
    await tester.pumpAndSettle();
    final edit = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(edit.at(0)).controller!.text, 'service');
    expect(tester.widget<TextField>(edit.at(1)).controller!.text, 'api, web');
    expect(find.text('is one of'), findsOneWidget);
    await tester.enterText(edit.at(2), 'Svc');
    await tester.tap(find.text('Save filter'));
    await tester.pumpAndSettle();
    expect(find.text('Svc', findRichText: true), findsOneWidget);
    expect(find.text('Services', findRichText: true), findsNothing);

    // Disable keeps the pill but drops it from the query; re-enable.
    await tester.tap(find.text('Svc', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Temporarily disable'));
    await tester.pumpAndSettle();
    expect(backend.commands.last, isNot(contains('service:(')));
    expect(find.text('Svc', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Svc', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Re-enable'));
    await tester.pumpAndSettle();
    expect(backend.commands.last, contains('service:('));

    // Exclude flips it in place.
    await tester.tap(find.text('Svc', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exclude results'));
    await tester.pumpAndSettle();
    expect(backend.commands.last, contains('NOT service:('));

    // Copy view: the rows as tab-separated text.
    await tester.tap(find.text('Copy view'));
    await tester.pumpAndSettle();
    expect(copied, startsWith('@timestamp\tSummary\n2026-10-29T10:00:00Z\t'));

    // Quick select in the time panel: last 90 minutes.
    await tester.tap(find.text('Last 15 minutes'));
    await tester.pumpAndSettle();
    expect(find.text('Commonly used'.toUpperCase()), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '15'), '90');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Last 90 minutes'), findsOneWidget);
    expect(find.text('Commonly used'.toUpperCase()), findsNothing);

    // A commonly used range keeps Kibana's name.
    await tester.tap(find.text('Last 90 minutes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();
    expect(find.text('Last 24 hours'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'direct Kibana asks for a login on 401, then shows hits',
    (tester) => HttpOverrides.runWithHttpOverrides(() async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late HttpServer server;
      final auths = <String?>[];
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final auth = request.headers.value('authorization');
          auths.add(auth);
          request.response.write(
            auth == null
                ? '{"statusCode":401,"error":"Unauthorized","message":"no"}'
                : '{"took":2,"hits":{"total":{"value":1},"hits":[{"_source":'
                      '{"@timestamp":"2026-10-29T10:00:00Z","message":"hi"}}]}}',
          );
          await request.response.close();
        });
      });
      addTearDown(() => tester.runAsync(server.close));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider(
              create: (_) =>
                  SshWorkspaceBloc(repository: SshProfileRepository()),
              child: const KibanaPage(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Kibana'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'http://localhost:5601'),
        'http://127.0.0.1:${server.port}',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Refresh'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Kibana'), findsOneWidget);
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'elastic');
      await tester.enterText(fields.at(1), 'pw');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('hi', findRichText: true), findsOneWidget);
      expect(find.text('elastic'), findsOneWidget, reason: 'signed-in user');
      expect(auths, [null, startsWith('Basic ')]);
      expect(tester.takeException(), isNull);
    }, _RealHttp()),
  );
}
