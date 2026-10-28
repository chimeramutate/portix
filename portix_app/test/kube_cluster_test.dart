import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/kubernetes/kube_logs.dart';
import 'package:portix/src/features/kubernetes/kube_resources.dart';
import 'package:portix/src/features/kubernetes/kubernetes_page.dart'
    show parseOverview;

Json _json(String text) => jsonDecode(text) as Json;

final _pod = _json('''{
  "metadata": {"name": "api-7d9f8c6b5d-x2x9z", "namespace": "prod",
               "creationTimestamp": "2026-10-20T00:00:00Z"},
  "spec": {"nodeName": "w-1", "containers": [{"name": "api"}, {"name": "proxy"}]},
  "status": {"phase": "Running", "podIP": "10.0.0.7",
    "containerStatuses": [
      {"name": "api", "ready": true, "restartCount": 2, "state": {"running": {}}},
      {"name": "proxy", "ready": false, "restartCount": 1,
       "state": {"waiting": {"reason": "CrashLoopBackOff"}}}
    ]}
}''');

final _node = _json('''{
  "metadata": {"name": "w-1", "labels": {"node-role.kubernetes.io/worker": ""}},
  "spec": {"unschedulable": true},
  "status": {"conditions": [{"type": "Ready", "status": "True"}],
             "allocatable": {"cpu": "3800m", "memory": "16Gi"}}
}''');

void main() {
  test('pod status, readiness and health read like kubectl', () {
    expect(podStatus(_pod), 'CrashLoopBackOff');
    expect(podRestarts(_pod), 3);
    expect(podContainers(_pod), ['api', 'proxy']);
    expect(podHealthOf(_pod), PodHealth.failing);
    final ready = kubeKinds['pods']!.columns.firstWhere(
      (c) => c.header == 'Ready',
    );
    expect(ready.cell(_pod), '1/2');
  });

  test('a cordoned node offers uncordon and drain', () {
    final nodes = kubeKinds['nodes']!;
    expect(nodes.columns[1].cell(_node), 'Ready,SchedulingDisabled');
    expect(nodes.columns[2].cell(_node), 'worker');
    expect(nodes.health!(_node), PodHealth.pending);
    expect(nodes.actions(_node), [KubeAction.uncordon, KubeAction.drain]);
  });

  test('commands quote names and scope namespaces', () {
    final deployments = kubeKinds['deployments']!;
    final item = _json('{"metadata": {"name": "api", "namespace": "prod"}}');
    expect(
      listCommand(deployments, null),
      'kubectl get deployments -A -o json',
    );
    expect(
      listCommand(deployments, 'prod'),
      "kubectl get deployments -n 'prod' -o json",
    );
    expect(
      listCommand(kubeKinds['nodes']!, 'prod'),
      'kubectl get nodes -o json',
    );
    expect(
      actionCommand(KubeAction.restart, deployments, item),
      "kubectl rollout restart 'deployments/api' -n 'prod'",
    );
    expect(
      scaleCommand(deployments, item, 3),
      "kubectl scale deployments 'api' -n 'prod' --replicas=3",
    );
    expect(
      deleteCommand(deployments, item),
      "kubectl delete deployments 'api' -n 'prod' --wait=false",
    );
    expect(
      actionCommand(KubeAction.drain, kubeKinds['nodes']!, _node),
      "kubectl drain 'w-1' --ignore-daemonsets --delete-emptydir-data "
      '--timeout=5m',
    );
  });

  test('apply sends the YAML as base64', () {
    const yaml = "kind: ConfigMap\ndata:\n  a: \"it's\"\n";
    final command = applyCommand(yaml, 'prod');
    expect(command, contains(base64.encode(utf8.encode(yaml))));
    expect(command, endsWith("kubectl apply -n 'prod' -f -"));
  });

  test('manual cronjob runs stay within 63 characters', () {
    final now = DateTime.utc(2026, 10, 27);
    expect(manualJobName('backup', now), 'backup-manual-1793059200');
    expect(manualJobName('x' * 80, now).length, 63);
  });

  test('parseContexts splits current from names', () {
    final (:current, :names) = parseContexts('prod\nprod\nstaging\n');
    expect(current, 'prod');
    expect(names, ['prod', 'staging']);
    expect(parseContexts('\nstaging\n').current, isNull);
  });

  test('quantities and ages', () {
    expect(parseCpu('3800m'), 3.8);
    expect(parseBytes('16Gi'), 16 * 1024 * 1024 * 1024);
    expect(formatBytes(1536 * 1024 * 1024), '1.5 GiB');
    final now = DateTime.utc(2026, 10, 27, 12);
    expect(formatAge('2026-10-27T11:59:30Z', now), '30s');
    expect(formatAge('2026-10-26T12:00:00Z', now), '24h');
    expect(formatAge('2026-10-20T12:00:00Z', now), '7d');
    expect(parseTopNodes('a 250m 6% 2Gi 13%\nb 750m 20% 1Gi 7%\n'), (
      cpu: 1.0,
      memory: 3.0 * 1024 * 1024 * 1024,
    ));
    expect(parseTopNodes(''), isNull);
  });

  test('overview tolerates missing metrics and version', () {
    const sep = '---portix---\n';
    final output = [
      jsonEncode({
        'items': [_node],
      }),
      'Running\nRunning\nPending\n',
      '3   3\n2   <none>\n',
      '{"items": []}',
      '',
      '',
    ].join('\n$sep');
    final data = parseOverview(output);
    expect(data.nodes, 1);
    expect(data.readyNodes, 1);
    expect(data.podPhases, {'Running': 2, 'Pending': 1});
    expect((data.deployments, data.availableDeployments), (2, 1));
    expect(data.used, isNull);
    expect(data.version, '');
  });

  group('workload detail', () {
    final deployment = _json('''{
      "metadata": {"name": "api", "namespace": "prod"},
      "spec": {"replicas": 3,
               "selector": {"matchLabels": {"app": "api", "tier": "web"}}},
      "status": {"readyReplicas": 2, "conditions": [
        {"type": "Available", "status": "True", "reason": "MinimumReplicasAvailable"},
        {"type": "Progressing", "status": "False", "reason": "ProgressDeadlineExceeded",
         "message": "timed out"}
      ]}
    }''');

    test('pods are picked by the matchLabels selector', () {
      expect(podSelector(deployment), 'app=api,tier=web');
      expect(podSelector(_node), isNull);
      final command = detailCommand(kubeKinds['deployments']!, deployment);
      expect(
        command,
        contains("kubectl get deployments 'api' -n 'prod' -o json"),
      );
      expect(
        command,
        contains("kubectl get pods -n 'prod' -l 'app=api,tier=web'"),
      );
      expect(command, contains("--field-selector 'involvedObject.name=api'"));
    });

    test('parseDetail splits item, pods and newest-first events', () {
      final output = [
        jsonEncode(deployment),
        jsonEncode({
          'items': [
            {
              'metadata': {'name': 'api-b'},
            },
            {
              'metadata': {'name': 'api-a'},
            },
          ],
        }),
        jsonEncode({
          'items': [
            {'lastTimestamp': '2026-10-27T10:00:00Z', 'reason': 'old'},
            {'lastTimestamp': '2026-10-27T11:00:00Z', 'reason': 'new'},
          ],
        }),
      ].join('\n$kubeSeparator\n');
      final detail = parseDetail(output);
      expect(nameOf(detail.item), 'api');
      expect(detail.pods.map(nameOf), ['api-a', 'api-b']);
      expect(detail.events.map((e) => e['reason']), ['new', 'old']);
      expect(conditionsOf(detail.item).map((c) => (c.type, c.ok)), [
        ('Available', true),
        ('Progressing', false),
      ]);
    });

    test('only workloads open a detail', () {
      expect(
        [
          for (final kind in kubeKinds.values)
            if (kind.ownsPods) kind.type,
        ],
        ['deployments', 'statefulsets', 'daemonsets', 'jobs'],
      );
    });
  });
}
