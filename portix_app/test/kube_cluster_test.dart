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
  group('edit form', () {
    final deployment = _json('''{
      "apiVersion": "apps/v1", "kind": "Deployment",
      "metadata": {"name": "api", "namespace": "prod", "resourceVersion": "42"},
      "spec": {"replicas": 2, "selector": {"matchLabels": {"app": "api"}},
        "template": {"spec": {"nodeSelector": {"zone": "a"},
          "containers": [
            {"name": "api", "image": "api:1", "ports": [{"containerPort": 80}],
             "resources": {"requests": {"cpu": "100m", "ephemeral-storage": "1Gi"},
                           "limits": {"memory": "1Gi"}},
             "env": [
               {"name": "MODE", "value": "prod"},
               {"name": "OLD", "value": "x"},
               {"name": "PASSWORD", "valueFrom": {
                 "secretKeyRef": {"name": "db", "key": "password"}}}
             ]},
            {"name": "proxy", "image": "proxy:1"}
          ]}}}
    }''');
    final kind = kubeKinds['deployments']!;

    test('reads containers, showing secrets by source only', () {
      final [api, proxy] = containerEdits(kind, deployment);
      expect(api.image, 'api:1');
      expect(api.cpuRequest, '100m');
      expect(api.memoryLimit, '1Gi');
      expect(api.env.last, (
        name: 'PASSWORD',
        value: '',
        source: 'secret db/password',
      ));
      expect(proxy.env, isEmpty);
    });

    test('edits only what the form shows', () {
      final [api, proxy] = containerEdits(kind, deployment);
      final edited = withFormEdits(
        kind,
        deployment,
        replicas: 3,
        containers: [
          (
            name: 'api',
            image: 'api:2',
            env: [api.env.last, (name: 'NEW', value: 'y', source: null)],
            cpuRequest: '',
            memoryRequest: '64Mi',
            cpuLimit: '',
            memoryLimit: '',
          ),
          proxy,
        ],
      );
      final containers = field(edited, 'spec.template.spec.containers') as List;
      final c = (containers.first as Map).cast<String, dynamic>();
      expect(c['image'], 'api:2');
      expect(c['env'], [
        {
          'name': 'PASSWORD',
          'valueFrom': {
            'secretKeyRef': {'name': 'db', 'key': 'password'},
          },
        },
        {'name': 'NEW', 'value': 'y'},
      ]);
      expect(c['resources'], {
        'requests': {'ephemeral-storage': '1Gi', 'memory': '64Mi'},
      });
      expect(c['ports'], [
        {'containerPort': 80},
      ]);
      expect(containers.last, {'name': 'proxy', 'image': 'proxy:1'});
      expect(field(edited, 'spec.replicas'), 3);
      expect(field(edited, 'metadata.resourceVersion'), '42');
      expect(field(edited, 'spec.template.spec.nodeSelector.zone'), 'a');
      expect(
        field(deployment, 'spec.replicas'),
        2,
        reason: 'the original is left alone',
      );
    });

    test('a pod takes a new image and nothing else', () {
      final pods = kubeKinds['pods']!;
      final pod = _json('''{"metadata": {"name": "p"}, "spec": {"containers": [
        {"name": "a", "image": "a:1", "env": [{"name": "X", "value": "1"}]}
      ]}}''');
      final [edit] = containerEdits(pods, pod);
      final edited = withFormEdits(
        pods,
        pod,
        containers: [
          (
            name: 'a',
            image: 'a:2',
            env: const [],
            cpuRequest: '1',
            memoryRequest: '',
            cpuLimit: '',
            memoryLimit: '',
          ),
        ],
      );
      expect(edit.image, 'a:1');
      expect(field(edited, 'spec.containers'), [
        {
          'name': 'a',
          'image': 'a:2',
          'env': [
            {'name': 'X', 'value': '1'},
          ],
        },
      ]);
    });

    test('which kinds get a form', () {
      for (final type in ['deployments', 'statefulsets', 'daemonsets']) {
        expect(kubeFormSpec(kubeKinds[type]!), 'spec.template.spec');
      }
      expect(
        kubeFormSpec(kubeKinds['cronjobs']!),
        'spec.jobTemplate.spec.template.spec',
      );
      expect(kubeFormSpec(kubeKinds['pods']!), 'spec');
      expect(kubeFormSpec(kubeKinds['jobs']!), isNull, reason: 'immutable');
      expect(kubeFormSpec(kubeKinds['services']!), isNull);
    });

    test('replace carries the whole item', () {
      final command = replaceCommand({'kind': 'Pod'});
      expect(command, endsWith('| base64 -d | kubectl replace -f -'));
      expect(command, contains(base64.encode(utf8.encode('{"kind":"Pod"}'))));
    });
  });

  test('connect steps say what they found', () {
    expect(kubeConnectSteps.map((s) => s.label), [
      'Server',
      'kubectl',
      'Cluster',
    ]);
    expect(describeConnectStep(0, 'portix-connected\n'), 'SSH session open');
    expect(
      describeConnectStep(1, '{"clientVersion": {"gitVersion": "v1.29.3"}}'),
      'kubectl v1.29.3',
    );
    expect(
      describeConnectStep(
        2,
        'rke2-sit\n{"clientVersion": {"gitVersion": "v1.29.3"}, '
        '"serverVersion": {"gitVersion": "v1.28.9+rke2r1"}}',
      ),
      'context rke2-sit · server v1.28.9+rke2r1',
    );
    expect(describeConnectStep(1, 'not json'), 'kubectl found');
  });

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

  test('all namespaces group by namespace, keeping the sort', () {
    Json item(String ns, String name) => {
      'metadata': {'name': name, 'namespace': ns},
    };
    final groups = groupByNamespace([
      item('prod', 'b'),
      item('dev', 'z'),
      item('prod', 'a'),
    ]);
    expect(groups.keys, ['dev', 'prod']);
    expect(groups['prod']!.map(nameOf), ['b', 'a']);
  });

  group('workload detail', () {
    final deployment = _json('''{
      "metadata": {"name": "api", "namespace": "prod"},
      "spec": {"replicas": 3,
               "selector": {"matchLabels": {"app": "api", "tier": "web"}},
               "template": {"metadata": {"labels": {"app": "api", "tier": "web"}},
                 "spec": {"containers": [{"name": "api", "image": "api:1",
                   "ports": [{"name": "http", "containerPort": 8080}]}]}}},
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
      expect(command, endsWith("kubectl get services -n 'prod' -o json"));
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
        jsonEncode({
          'items': [
            {
              'metadata': {'name': 'api-svc'},
              'spec': {
                'selector': {'app': 'api'},
                'type': 'NodePort',
                'ports': [
                  {'port': 80, 'nodePort': 18000},
                ],
              },
            },
            {
              'metadata': {'name': 'other'},
              'spec': {
                'selector': {'app': 'web'},
              },
            },
          ],
        }),
      ].join('\n$kubeSeparator\n');
      final detail = parseDetail(output);
      expect(nameOf(detail.item), 'api');
      expect(detail.pods.map(nameOf), ['api-a', 'api-b']);
      expect(detail.events.map((e) => e['reason']), ['new', 'old']);
      expect(detail.services.map(nameOf), ['api-svc']);
      expect(serviceEndpoints(detail.services.single), ['[Any Node]:18000']);
      expect(
        workloadPorts(kubeKinds['deployments']!, detail.item),
        'http 8080/TCP',
      );
      expect(conditionsOf(detail.item).map((c) => (c.type, c.ok)), [
        ('Available', true),
        ('Progressing', false),
      ]);
    });

    test("Rancher's publicEndpoints become endpoints, not annotations", () {
      final item = {
        'metadata': {
          'name': 'core',
          'annotations': {
            'field.cattle.io/publicEndpoints':
                '[{"port":19001,"protocol":"TCP","allNodes":true},'
                '{"port":443,"addresses":["10.0.0.1"]},'
                '{"hostname":"api.example.com","path":"/v1","port":80}]',
            'a': 'b',
          },
        },
      };
      expect(publicEndpoints(item), [
        '[Any Node]:19001',
        '10.0.0.1:443',
        'api.example.com/v1',
      ]);
      expect(detailSections(kubeKinds['deployments']!, item).last.rows, [
        ('a', 'b'),
      ]);
      expect(publicEndpoints({'metadata': {}}), isEmpty);
    });

    test('a service and a node list their pods too', () {
      final service = _json('''{
        "metadata": {"name": "api", "namespace": "prod"},
        "spec": {"selector": {"app": "api"}, "ports": [
          {"name": "http", "port": 80, "targetPort": 8080, "protocol": "TCP"}]}
      }''');
      expect(podSelector(service), 'app=api');
      expect(
        detailCommand(kubeKinds['services']!, service),
        contains("kubectl get pods -n 'prod' -l 'app=api'"),
      );
      final node = detailCommand(kubeKinds['nodes']!, _node);
      expect(
        node,
        contains("get pods -A --field-selector 'spec.nodeName=w-1'"),
      );
      expect(node, contains("get events -A --field-selector"));
      expect(
        detailCommand(kubeKinds['configmaps']!, _pod),
        contains("echo '{\"items\":[]}'"),
      );
      expect(
        detailSections(
          kubeKinds['services']!,
          service,
        ).firstWhere((s) => s.title == 'Ports').rows,
        [('http', '80 → 8080/TCP')],
      );
    });

    test('detail sections per kind skip empty ones', () {
      final pod = detailSections(kubeKinds['pods']!, _pod);
      expect(pod.map((s) => s.title), ['Pod', 'Containers']);
      expect(pod.first.rows, [('Node', 'w-1'), ('Pod IP', '10.0.0.7')]);
      expect(pod.last.rows.last, (
        'proxy',
        'waiting (CrashLoopBackOff) · not ready · restarts 1',
      ));
      final node = detailSections(kubeKinds['nodes']!, _node);
      expect(node.map((s) => s.title), ['Allocatable of capacity', 'Labels']);
      final secret = detailSections(
        kubeKinds['secrets']!,
        _json('{"metadata": {"name": "s"}, "data": {"pw": "aHVudGVyMg=="}}'),
      ).single;
      expect(secret.secret, isTrue);
      expect(secret.rows, [('pw', 'hunter2')]);
    });

    test('only workloads own pods', () {
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
