import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/repositories/ssh/ssh_profile_repository.dart';
import 'package:portix/src/features/kubernetes/kubernetes_page.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';

void main() {
  setUp(() {
    sl.registerSingleton(ConnectionManager(backend: MockConnectionBackend()));
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
    kubeTabs.current.pickServer('missing');
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
}
