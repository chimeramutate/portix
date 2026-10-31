import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/profile_secret_store.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart' as manager;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/domain/repositories/ssh/ssh_profile_repository.dart';
import 'package:portix/src/features/kubernetes/kubernetes_page.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';

/// Lists deployments `api`, `web` (in `prod`) and `db` (in `data`);
/// deleting [refused] fails.
class _FakeKube extends MockConnectionBackend {
  final commands = <String>[];
  String? refused;

  @override
  Future<String> execOnProfile(
    manager.SshProfile profile,
    String command,
  ) async {
    commands.add(command);
    if (command == "kubectl get deployments 'api' -n 'prod' -o json") {
      return jsonEncode({
        'kind': 'Deployment',
        'metadata': {'name': 'api', 'namespace': 'prod'},
        'spec': {
          'replicas': 2,
          'template': {
            'spec': {
              'containers': [
                {'name': 'api', 'image': 'api:1'},
              ],
            },
          },
        },
      });
    }
    if (command.startsWith('kubectl get deployments')) {
      Map<String, Object> item(String name, String ns) => {
        'metadata': {'name': name, 'namespace': ns},
      };
      return jsonEncode({
        'items': [item('api', 'prod'), item('web', 'prod'), item('db', 'data')],
      });
    }
    if (refused != null && command.contains("'$refused'")) {
      throw StateError('forbidden');
    }
    return '';
  }
}

class _NoSecrets extends ProfileSecretStore {
  @override
  Future<String?> readPassword(String profileId) async => 'pw';
}

const _box = SshProfile(
  id: 'box',
  name: 'box',
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
  runsKubernetes: true,
);

void main() {
  late _FakeKube backend;
  setUp(() {
    backend = _FakeKube();
    sl.registerSingleton(
      ConnectionManager(
        backend: backend,
        credentials: ProfileCredentials(secretStore: _NoSecrets()),
      ),
    );
  });
  tearDown(() async {
    while (kubeTabs.tabs.length > 1) {
      kubeTabs.close(1);
    }
    kubeTabs.close(0); // closing the last tab leaves a fresh one
    await sl.reset();
  });

  test('several namespaces can be picked; null goes back to all', () {
    final kube = kubeTabs.current
      ..toggleNamespace('prod')
      ..toggleNamespace('dev');
    expect(kube.picked, {'prod', 'dev'});
    expect(kube.namespace, isNull, reason: 'several: no single -n');
    kube.toggleNamespace('dev');
    expect(kube.namespace, 'prod');
    kube.setNamespaces(['dev']);
    expect(kube.picked, isEmpty, reason: 'gone namespaces drop out');
    kube
      ..toggleNamespace('dev')
      ..toggleNamespace(null);
    expect(kube.picked, isEmpty);
  });

  testWidgets('every side panel section opens without a server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => SshWorkspaceBloc(repository: SshProfileRepository()),
            child: const Row(
              children: [
                SizedBox(width: 240, child: KubeSectionsPanel()),
                Expanded(child: KubernetesPage()),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Open a cluster'), findsOneWidget);
    // An id with no saved profile: sections render, kubectl never runs.
    kubeTabs.current
      ..pickServer('missing')
      ..markConnected();
    await tester.pump();
    for (final section in KubeSection.values) {
      kubeTabs.current.section = section;
      await tester.pump();
      expect(tester.takeException(), isNull, reason: section.label);
    }
  });

  testWidgets('each cluster tab keeps its own section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => SshWorkspaceBloc(repository: SshProfileRepository()),
            child: const KubernetesPage(),
          ),
        ),
      ),
    );
    kubeTabs.current.section = KubeSection.pods;
    await tester.tap(find.byTooltip('Open another cluster'));
    await tester.pump();
    expect(find.text('New cluster'), findsNWidgets(2));
    expect(kubeTabs.current.section, KubeSection.overview);

    kubeTabs.current.section = KubeSection.nodes;
    kubeTabs.select(0);
    await tester.pump();
    expect(kubeTabs.current.section, KubeSection.pods);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a server checks the connection before the '
      'sections', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => SshWorkspaceBloc(repository: SshProfileRepository()),
            child: const KubernetesPage(),
          ),
        ),
      ),
    );
    // No saved profile behind the id: the first step fails.
    kubeTabs.current.pickServer('missing');
    await tester.pump();
    await tester.pump();
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Cluster'), findsOneWidget);
    expect(find.text('Could not open the cluster'), findsOneWidget);
    expect(kubeTabs.current.connected, isFalse);
    expect(find.text('Overview'), findsNothing);

    await tester.tap(find.text('Choose another server'));
    await tester.pump();
    expect(kubeTabs.current.profileId, isNull);
    expect(find.text('Open a cluster'), findsOneWidget);
  });

  testWidgets('a group header folds its sections', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KubeSectionsPanel())),
    );
    expect(find.text('Nodes'), findsOneWidget);
    await tester.tap(find.text('Cluster'));
    await tester.pump();
    expect(find.text('Nodes'), findsNothing);
    expect(find.text('Overview'), findsOneWidget); // open section stays
    await tester.tap(find.text('Cluster'));
    await tester.pump();
    expect(find.text('Nodes'), findsOneWidget);
  });

  testWidgets('ticked rows redeploy or delete together after a confirm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('kube_bulk');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repository = SshProfileRepository(
      secretStore: _NoSecrets(),
      storeFile: File('${dir.path}/profiles.json'),
    );
    late SshWorkspaceBloc bloc;
    await tester.runAsync(() async {
      await repository.saveProfile(_box);
      bloc = SshWorkspaceBloc(repository: repository)
        ..add(const ProfilesRequested());
      await bloc.stream.firstWhere((s) => s.profiles.isNotEmpty);
      bloc.add(const NavigationChanged(WorkspaceView.kubernetes));
      await bloc.stream.firstWhere(
        (s) => s.activeView == WorkspaceView.kubernetes,
      );
    });
    Future<void> settle() async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(value: bloc, child: const KubernetesPage()),
        ),
      ),
    );
    kubeTabs.current
      ..pickServer('box')
      ..markConnected()
      ..section = KubeSection.deployments;
    await settle();
    await settle();
    expect(find.text('api'), findsOneWidget);
    expect(find.text('Redeploy'), findsNothing, reason: 'nothing ticked yet');

    Finder box(String name) => find.bySemanticsLabel('Select $name');
    await tester.tap(box('api'));
    await tester.tap(box('db'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    // Cancel runs nothing and keeps the ticks.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Redeploy'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Redeploy 2 Deployments?'), findsOneWidget);
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('api')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('data')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('web')),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(backend.commands.where((c) => c.contains('rollout')), isEmpty);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Redeploy'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Redeploy 2'));
    await settle();
    expect(backend.commands.where((c) => c.contains('rollout')), [
      "kubectl rollout restart 'deployments/api' -n 'prod'",
      "kubectl rollout restart 'deployments/db' -n 'data'",
    ]);
    expect(find.text('2 selected'), findsNothing);

    // Select all, then one delete fails: only that one stays ticked.
    backend.refused = 'web';
    await tester.tap(find.bySemanticsLabel('Select all'));
    await tester.pump();
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete 3'));
    await settle();
    expect(
      backend.commands.where((c) => c.startsWith('kubectl delete')),
      hasLength(3),
    );
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is SelectableText && w.data!.startsWith('web: '),
      ),
      findsOneWidget,
    );
    await tester.runAsync(bloc.close);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Edit config saves the form with kubectl replace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('kube_form');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repository = SshProfileRepository(
      secretStore: _NoSecrets(),
      storeFile: File('${dir.path}/profiles.json'),
    );
    late SshWorkspaceBloc bloc;
    await tester.runAsync(() async {
      await repository.saveProfile(_box);
      bloc = SshWorkspaceBloc(repository: repository)
        ..add(const ProfilesRequested());
      await bloc.stream.firstWhere((s) => s.profiles.isNotEmpty);
      bloc.add(const NavigationChanged(WorkspaceView.kubernetes));
      await bloc.stream.firstWhere(
        (s) => s.activeView == WorkspaceView.kubernetes,
      );
    });
    Future<void> settle() async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(value: bloc, child: const KubernetesPage()),
        ),
      ),
    );
    kubeTabs.current
      ..pickServer('box')
      ..markConnected()
      ..section = KubeSection.deployments;
    await settle();
    await settle();

    await tester.tap(find.byTooltip('Actions').at(1)); // api, after data/db
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Edit config'));
    await settle();
    await settle();
    expect(find.text('Edit api'), findsOneWidget);

    Finder input(String label) => find.descendant(
      of: find.widgetWithText(AppTextField, label),
      matching: find.byType(TextField),
    );
    await tester.enterText(input('Image'), 'api:2');
    await tester.enterText(input('Replicas'), '');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Save'),
              matching: find.byWidgetPredicate((w) => w is FilledButton),
            ),
          )
          .onPressed,
      isNull,
      reason: 'replicas are required',
    );
    await tester.enterText(input('Replicas'), '5');
    await tester.pump();
    await tester.tap(find.text('Add variable'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'NAME'), 'LOG_LEVEL');
    await tester.enterText(find.widgetWithText(TextField, 'value'), 'debug');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle();
    await settle();
    expect(find.text('Edit api'), findsNothing);

    final replace = backend.commands.singleWhere(
      (c) => c.contains('kubectl replace'),
    );
    final sent =
        jsonDecode(utf8.decode(base64.decode(replace.split(' ')[2])))
            as Map<String, dynamic>;
    expect(sent['spec']['replicas'], 5);
    expect(sent['spec']['template']['spec']['containers'], [
      {
        'name': 'api',
        'image': 'api:2',
        'env': [
          {'name': 'LOG_LEVEL', 'value': 'debug'},
        ],
      },
    ]);
    await tester.runAsync(bloc.close);
    await tester.pumpWidget(const SizedBox());
  });
}
