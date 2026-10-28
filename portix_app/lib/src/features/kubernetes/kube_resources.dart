import 'dart:convert';

import 'kube_logs.dart' show PodHealth, shellQuote;

typedef Json = Map<String, dynamic>;

/// Reads a nested value, e.g. `field(item, 'status.phase')`; null when any
/// step is missing.
Object? field(Json item, String path) {
  Object? value = item;
  for (final key in path.split('.')) {
    if (value is! Map) return null;
    value = value[key];
  }
  return value;
}

String _str(Json item, String path) => field(item, path)?.toString() ?? '';
int _int(Json item, String path) => (field(item, path) as num?)?.toInt() ?? 0;
List<Json> _list(Json item, String path) =>
    (field(item, path) as List?)?.cast<Json>() ?? const [];
Json _map(Json item, String path) => (field(item, path) as Map?)?.cast() ?? {};

String nameOf(Json item) => _str(item, 'metadata.name');
String? namespaceOf(Json item) => field(item, 'metadata.namespace') as String?;

/// kubectl-style age: `42s`, `5m`, `3h`, `12d`.
String formatAge(String? timestamp, [DateTime? now]) {
  final time = DateTime.tryParse(timestamp ?? '');
  if (time == null) return '—';
  final age = (now ?? DateTime.now()).difference(time);
  if (age.inSeconds < 60) return '${age.inSeconds.clamp(0, 59)}s';
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  if (age.inHours < 48) return '${age.inHours}h';
  return '${age.inDays}d';
}

String _age(Json item) => formatAge(_str(item, 'metadata.creationTimestamp'));

/// What `kubectl get pods` prints in STATUS.
String podStatus(Json pod) {
  if (field(pod, 'metadata.deletionTimestamp') != null) return 'Terminating';
  for (final c in _list(pod, 'status.initContainerStatuses')) {
    final reason =
        field(c, 'state.waiting.reason') ?? field(c, 'state.terminated.reason');
    if (reason != null && reason != 'Completed') return 'Init:$reason';
  }
  for (final c in _list(pod, 'status.containerStatuses')) {
    final reason =
        field(c, 'state.waiting.reason') ?? field(c, 'state.terminated.reason');
    if (reason != null) return '$reason';
  }
  return _str(pod, 'status.phase');
}

String _podReady(Json pod) {
  final statuses = _list(pod, 'status.containerStatuses');
  final ready = statuses.where((c) => c['ready'] == true).length;
  return '$ready/${_list(pod, 'spec.containers').length}';
}

int podRestarts(Json pod) => _list(
  pod,
  'status.containerStatuses',
).fold(0, (sum, c) => sum + ((c['restartCount'] as num?)?.toInt() ?? 0));

/// Containers of [pod], for `kubectl exec -c` and logs.
List<String> podContainers(Json pod) => [
  for (final c in _list(pod, 'spec.containers')) '${c['name']}',
];

String _images(Json item, String podSpec) => [
  for (final c in _list(item, '$podSpec.containers')) '${c['image']}',
].join(', ');

String _replicas(Json item) =>
    '${_int(item, 'status.readyReplicas')}/${_int(item, 'spec.replicas')}';

bool isUnschedulable(Json node) => field(node, 'spec.unschedulable') == true;

String _nodeStatus(Json node) {
  final ready = _list(
    node,
    'status.conditions',
  ).where((c) => c['type'] == 'Ready').firstOrNull;
  return [
    ready?['status'] == 'True' ? 'Ready' : 'NotReady',
    if (isUnschedulable(node)) 'SchedulingDisabled',
  ].join(',');
}

String _nodeRoles(Json node) {
  final roles = [
    for (final key in _map(node, 'metadata.labels').keys)
      if (key.startsWith('node-role.kubernetes.io/'))
        key.substring('node-role.kubernetes.io/'.length),
  ];
  return roles.isEmpty ? '<none>' : roles.join(',');
}

String _nodeAddress(Json node, String type) =>
    _list(
      node,
      'status.addresses',
    ).where((a) => a['type'] == type).firstOrNull?['address']?.toString() ??
    '';

String _servicePorts(Json svc) => [
  for (final p in _list(svc, 'spec.ports'))
    [
      '${p['port']}',
      if (p['nodePort'] != null) ':${p['nodePort']}',
      '/${p['protocol'] ?? 'TCP'}',
    ].join(),
].join(', ');

String _lbAddress(Json item) => [
  for (final i in _list(item, 'status.loadBalancer.ingress'))
    '${i['ip'] ?? i['hostname'] ?? ''}',
].join(', ');

String _jobStatus(Json job) {
  for (final c in _list(job, 'status.conditions')) {
    if (c['status'] == 'True' &&
        (c['type'] == 'Complete' || c['type'] == 'Failed')) {
      return '${c['type']}';
    }
  }
  return _int(job, 'status.active') > 0 ? 'Running' : 'Pending';
}

String _keys(Json item, String path) => '${_map(item, path).length}';

String _subjects(Json binding) => [
  for (final s in _list(binding, 'subjects')) '${s['kind']}/${s['name']}',
].join(', ');

String _selector(Json item, String path) => [
  for (final MapEntry(:key, :value) in _map(item, path).entries) '$key=$value',
].join(',');

typedef KubeColumn = ({String header, int flex, String Function(Json) cell});

KubeColumn _col(String header, String Function(Json) cell, {int flex = 2}) =>
    (header: header, flex: flex, cell: cell);

final KubeColumn _name = _col('Name', nameOf, flex: 4);
final KubeColumn _ageCol = _col('Age', _age, flex: 1);

enum KubeAction {
  scale('Scale'),
  restart('Redeploy'),
  rollback('Rollback'),
  runNow('Run now'),
  suspend('Suspend'),
  resume('Resume'),
  cordon('Cordon'),
  uncordon('Uncordon'),
  drain('Drain'),
  shell('Execute shell'),
  logs('View logs');

  const KubeAction(this.label);

  final String label;
}

/// One kind of resource, as listed by `kubectl get <type>`.
class KubeKind {
  const KubeKind({
    required this.type,
    required this.label,
    required this.columns,
    this.namespaced = true,
    this.health,
    this.actions = _noActions,
    this.ownsPods = false,
  });

  /// kubectl's resource name, e.g. `deployments`.
  final String type;
  final String label;
  final bool namespaced;
  final List<KubeColumn> columns;

  /// Colors the row's dot; null for kinds without a health.
  final PodHealth Function(Json item)? health;

  /// Extra actions beside Edit YAML, Describe and Delete.
  final List<KubeAction> Function(Json item) actions;

  /// Runs pods picked by `spec.selector`, so a click opens its detail
  /// with those pods instead of plain describe output.
  final bool ownsPods;
}

List<KubeAction> _noActions(Json _) => const [];

PodHealth _replicaHealth(Json item) {
  final want = _int(item, 'spec.replicas');
  final ready = _int(item, 'status.readyReplicas');
  return ready == want
      ? (want == 0 ? PodHealth.done : PodHealth.ok)
      : ready == 0
      ? PodHealth.failing
      : PodHealth.pending;
}

PodHealth podHealthOf(Json pod) {
  final status = podStatus(pod);
  if (status == 'Completed' || status == 'Succeeded') return PodHealth.done;
  if (status == 'Running') {
    final [ready, total] = _podReady(pod).split('/');
    return ready == total ? PodHealth.ok : PodHealth.pending;
  }
  if (const {
        'Pending',
        'ContainerCreating',
        'PodInitializing',
        'Terminating',
      }.contains(status) ||
      status.startsWith('Init:')) {
    return PodHealth.pending;
  }
  return PodHealth.failing;
}

final kubeKinds = <String, KubeKind>{
  for (final kind in <KubeKind>[
    KubeKind(
      type: 'nodes',
      label: 'Nodes',
      namespaced: false,
      columns: [
        _name,
        _col('Status', _nodeStatus),
        _col('Roles', _nodeRoles),
        _col('Version', (n) => _str(n, 'status.nodeInfo.kubeletVersion')),
        _col('Internal IP', (n) => _nodeAddress(n, 'InternalIP')),
        _col('CPU', (n) => _str(n, 'status.allocatable.cpu'), flex: 1),
        _col(
          'Memory',
          (n) => formatBytes(parseBytes(_str(n, 'status.allocatable.memory'))),
          flex: 1,
        ),
        _ageCol,
      ],
      health: (n) => !_nodeStatus(n).startsWith('Ready')
          ? PodHealth.failing
          : isUnschedulable(n)
          ? PodHealth.pending
          : PodHealth.ok,
      actions: (n) => [
        isUnschedulable(n) ? KubeAction.uncordon : KubeAction.cordon,
        KubeAction.drain,
      ],
    ),
    KubeKind(
      type: 'namespaces',
      label: 'Namespaces',
      namespaced: false,
      columns: [_name, _col('Status', (n) => _str(n, 'status.phase')), _ageCol],
      health: (n) => _str(n, 'status.phase') == 'Active'
          ? PodHealth.ok
          : PodHealth.pending,
    ),
    KubeKind(
      type: 'events',
      label: 'Events',
      columns: [
        _col('Type', (e) => _str(e, 'type'), flex: 1),
        _col('Reason', (e) => _str(e, 'reason')),
        _col(
          'Object',
          (e) =>
              '${_str(e, 'involvedObject.kind')}/${_str(e, 'involvedObject.name')}',
          flex: 3,
        ),
        _col('Message', (e) => _str(e, 'message'), flex: 6),
        _col('Count', (e) => '${_int(e, 'count')}', flex: 1),
        _col(
          'Last seen',
          (e) => formatAge(
            field(e, 'lastTimestamp') as String? ??
                field(e, 'eventTime') as String? ??
                _str(e, 'metadata.creationTimestamp'),
          ),
          flex: 1,
        ),
      ],
      health: (e) =>
          _str(e, 'type') == 'Warning' ? PodHealth.failing : PodHealth.done,
    ),
    KubeKind(
      type: 'deployments',
      ownsPods: true,
      label: 'Deployments',
      columns: [
        _name,
        _col('Ready', _replicas, flex: 1),
        _col(
          'Up-to-date',
          (d) => '${_int(d, 'status.updatedReplicas')}',
          flex: 1,
        ),
        _col(
          'Available',
          (d) => '${_int(d, 'status.availableReplicas')}',
          flex: 1,
        ),
        _col('Image', (d) => _images(d, 'spec.template.spec'), flex: 4),
        _ageCol,
      ],
      health: _replicaHealth,
      actions: (_) => const [
        KubeAction.scale,
        KubeAction.restart,
        KubeAction.rollback,
      ],
    ),
    KubeKind(
      type: 'statefulsets',
      ownsPods: true,
      label: 'StatefulSets',
      columns: [
        _name,
        _col('Ready', _replicas, flex: 1),
        _col('Image', (s) => _images(s, 'spec.template.spec'), flex: 4),
        _ageCol,
      ],
      health: _replicaHealth,
      actions: (_) => const [
        KubeAction.scale,
        KubeAction.restart,
        KubeAction.rollback,
      ],
    ),
    KubeKind(
      type: 'daemonsets',
      ownsPods: true,
      label: 'DaemonSets',
      columns: [
        _name,
        _col(
          'Desired',
          (d) => '${_int(d, 'status.desiredNumberScheduled')}',
          flex: 1,
        ),
        _col('Ready', (d) => '${_int(d, 'status.numberReady')}', flex: 1),
        _col(
          'Available',
          (d) => '${_int(d, 'status.numberAvailable')}',
          flex: 1,
        ),
        _col('Image', (d) => _images(d, 'spec.template.spec'), flex: 4),
        _ageCol,
      ],
      health: (d) =>
          _int(d, 'status.numberReady') ==
              _int(d, 'status.desiredNumberScheduled')
          ? PodHealth.ok
          : PodHealth.pending,
      actions: (_) => const [KubeAction.restart, KubeAction.rollback],
    ),
    KubeKind(
      type: 'jobs',
      ownsPods: true,
      label: 'Jobs',
      columns: [
        _name,
        _col('Status', _jobStatus, flex: 1),
        _col(
          'Completions',
          (j) =>
              '${_int(j, 'status.succeeded')}/${field(j, 'spec.completions') ?? 1}',
          flex: 1,
        ),
        _col('Image', (j) => _images(j, 'spec.template.spec'), flex: 4),
        _ageCol,
      ],
      health: (j) => switch (_jobStatus(j)) {
        'Complete' => PodHealth.done,
        'Failed' => PodHealth.failing,
        _ => PodHealth.pending,
      },
    ),
    KubeKind(
      type: 'cronjobs',
      label: 'CronJobs',
      columns: [
        _name,
        _col('Schedule', (c) => _str(c, 'spec.schedule')),
        _col(
          'Suspend',
          (c) => field(c, 'spec.suspend') == true ? 'True' : 'False',
          flex: 1,
        ),
        _col('Active', (c) => '${_list(c, 'status.active').length}', flex: 1),
        _col(
          'Last schedule',
          (c) => formatAge(field(c, 'status.lastScheduleTime') as String?),
          flex: 1,
        ),
        _ageCol,
      ],
      health: (c) =>
          field(c, 'spec.suspend') == true ? PodHealth.done : PodHealth.ok,
      actions: (c) => [
        KubeAction.runNow,
        field(c, 'spec.suspend') == true
            ? KubeAction.resume
            : KubeAction.suspend,
      ],
    ),
    KubeKind(
      type: 'pods',
      label: 'Pods',
      columns: [
        _name,
        _col('Status', podStatus),
        _col('Ready', _podReady, flex: 1),
        _col('Restarts', (p) => '${podRestarts(p)}', flex: 1),
        _col('Node', (p) => _str(p, 'spec.nodeName')),
        _col('IP', (p) => _str(p, 'status.podIP')),
        _ageCol,
      ],
      health: podHealthOf,
      actions: (_) => const [KubeAction.logs, KubeAction.shell],
    ),
    KubeKind(
      type: 'services',
      label: 'Services',
      columns: [
        _name,
        _col('Type', (s) => _str(s, 'spec.type')),
        _col('Cluster IP', (s) => _str(s, 'spec.clusterIP')),
        _col('External', _lbAddress),
        _col('Ports', _servicePorts, flex: 3),
        _col('Selector', (s) => _selector(s, 'spec.selector'), flex: 3),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'ingresses',
      label: 'Ingresses',
      columns: [
        _name,
        _col('Class', (i) => _str(i, 'spec.ingressClassName')),
        _col(
          'Hosts',
          (i) => [
            for (final r in _list(i, 'spec.rules')) r['host'] ?? '*',
          ].join(', '),
          flex: 4,
        ),
        _col('Address', _lbAddress),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'horizontalpodautoscalers',
      label: 'HorizontalPodAutoscalers',
      columns: [
        _name,
        _col(
          'Reference',
          (h) =>
              '${_str(h, 'spec.scaleTargetRef.kind')}/${_str(h, 'spec.scaleTargetRef.name')}',
          flex: 3,
        ),
        _col(
          'Min / Max',
          (h) =>
              '${field(h, 'spec.minReplicas') ?? 1} / ${_int(h, 'spec.maxReplicas')}',
          flex: 1,
        ),
        _col(
          'Replicas',
          (h) => '${_int(h, 'status.currentReplicas')}',
          flex: 1,
        ),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'persistentvolumes',
      label: 'PersistentVolumes',
      namespaced: false,
      columns: [
        _name,
        _col('Capacity', (p) => _str(p, 'spec.capacity.storage'), flex: 1),
        _col(
          'Access',
          (p) => (field(p, 'spec.accessModes') as List? ?? []).join(','),
        ),
        _col(
          'Reclaim',
          (p) => _str(p, 'spec.persistentVolumeReclaimPolicy'),
          flex: 1,
        ),
        _col('Status', (p) => _str(p, 'status.phase'), flex: 1),
        _col(
          'Claim',
          (p) => field(p, 'spec.claimRef') == null
              ? ''
              : '${_str(p, 'spec.claimRef.namespace')}/${_str(p, 'spec.claimRef.name')}',
          flex: 3,
        ),
        _col('StorageClass', (p) => _str(p, 'spec.storageClassName')),
        _ageCol,
      ],
      health: (p) => switch (_str(p, 'status.phase')) {
        'Bound' => PodHealth.ok,
        'Available' => PodHealth.done,
        'Pending' => PodHealth.pending,
        _ => PodHealth.failing,
      },
    ),
    KubeKind(
      type: 'persistentvolumeclaims',
      label: 'PersistentVolumeClaims',
      columns: [
        _name,
        _col('Status', (p) => _str(p, 'status.phase'), flex: 1),
        _col('Volume', (p) => _str(p, 'spec.volumeName'), flex: 3),
        _col('Capacity', (p) => _str(p, 'status.capacity.storage'), flex: 1),
        _col(
          'Access',
          (p) => (field(p, 'spec.accessModes') as List? ?? []).join(','),
        ),
        _col('StorageClass', (p) => _str(p, 'spec.storageClassName')),
        _ageCol,
      ],
      health: (p) =>
          _str(p, 'status.phase') == 'Bound' ? PodHealth.ok : PodHealth.pending,
    ),
    KubeKind(
      type: 'storageclasses',
      label: 'StorageClasses',
      namespaced: false,
      columns: [
        _name,
        _col('Provisioner', (s) => _str(s, 'provisioner'), flex: 3),
        _col('Reclaim', (s) => _str(s, 'reclaimPolicy'), flex: 1),
        _col('Binding', (s) => _str(s, 'volumeBindingMode')),
        _col(
          'Default',
          (s) =>
              _map(
                    s,
                    'metadata.annotations',
                  )['storageclass.kubernetes.io/is-default-class'] ==
                  'true'
              ? 'Yes'
              : '',
          flex: 1,
        ),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'configmaps',
      label: 'ConfigMaps',
      columns: [_name, _col('Keys', (c) => _keys(c, 'data'), flex: 1), _ageCol],
    ),
    KubeKind(
      type: 'secrets',
      label: 'Secrets',
      columns: [
        _name,
        _col('Type', (s) => _str(s, 'type'), flex: 3),
        _col('Keys', (s) => _keys(s, 'data'), flex: 1),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'networkpolicies',
      label: 'NetworkPolicies',
      columns: [
        _name,
        _col(
          'Pod selector',
          (n) => _selector(n, 'spec.podSelector.matchLabels'),
          flex: 4,
        ),
        _col(
          'Types',
          (n) => (field(n, 'spec.policyTypes') as List? ?? []).join(','),
        ),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'poddisruptionbudgets',
      label: 'PodDisruptionBudgets',
      columns: [
        _name,
        _col('Min available', (p) => _str(p, 'spec.minAvailable'), flex: 1),
        _col('Max unavailable', (p) => _str(p, 'spec.maxUnavailable'), flex: 1),
        _col(
          'Allowed disruptions',
          (p) => '${_int(p, 'status.disruptionsAllowed')}',
          flex: 1,
        ),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'resourcequotas',
      label: 'ResourceQuotas',
      columns: [
        _name,
        _col(
          'Used / Hard',
          (q) => [
            for (final MapEntry(:key, :value) in _map(q, 'status.hard').entries)
              '$key: ${_map(q, 'status.used')[key] ?? 0}/$value',
          ].join(', '),
          flex: 8,
        ),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'serviceaccounts',
      label: 'ServiceAccounts',
      columns: [_name, _ageCol],
    ),
    KubeKind(type: 'roles', label: 'Roles', columns: [_name, _ageCol]),
    KubeKind(
      type: 'rolebindings',
      label: 'RoleBindings',
      columns: [
        _name,
        _col(
          'Role',
          (b) => '${_str(b, 'roleRef.kind')}/${_str(b, 'roleRef.name')}',
          flex: 3,
        ),
        _col('Subjects', _subjects, flex: 4),
        _ageCol,
      ],
    ),
    KubeKind(
      type: 'clusterroles',
      label: 'ClusterRoles',
      namespaced: false,
      columns: [_name, _ageCol],
    ),
    KubeKind(
      type: 'clusterrolebindings',
      label: 'ClusterRoleBindings',
      namespaced: false,
      columns: [
        _name,
        _col(
          'Role',
          (b) => '${_str(b, 'roleRef.kind')}/${_str(b, 'roleRef.name')}',
          flex: 3,
        ),
        _col('Subjects', _subjects, flex: 4),
        _ageCol,
      ],
    ),
  ])
    kind.type: kind,
};

/// `items` of a `kubectl get -o json` list.
List<Json> parseItems(String output) =>
    ((jsonDecode(output) as Json)['items'] as List).cast<Json>();

String _nsFlag(String? namespace) =>
    namespace == null ? '' : ' -n ${shellQuote(namespace)}';

/// Every [kind] in [namespace], or in all namespaces when null.
String listCommand(KubeKind kind, String? namespace) =>
    'kubectl get ${kind.type}'
    '${!kind.namespaced
        ? ''
        : namespace == null
        ? ' -A'
        : _nsFlag(namespace)}'
    ' -o json';

String _target(KubeKind kind, Json item) =>
    '${kind.type} ${shellQuote(nameOf(item))}${_nsFlag(namespaceOf(item))}';

String yamlCommand(KubeKind kind, Json item) =>
    'kubectl get ${_target(kind, item)} -o yaml';

String describeCommand(KubeKind kind, Json item) =>
    'kubectl describe ${_target(kind, item)}';

String deleteCommand(KubeKind kind, Json item) =>
    'kubectl delete ${_target(kind, item)} --wait=false';

/// `kubectl apply` of [yaml] (into [namespace] when given), passed as
/// base64 so no quoting can break it.
String applyCommand(String yaml, [String? namespace]) =>
    "printf '%s' ${base64.encode(utf8.encode(yaml))} | base64 -d | "
    'kubectl apply${_nsFlag(namespace)} -f -';

String scaleCommand(KubeKind kind, Json item, int replicas) =>
    'kubectl scale ${_target(kind, item)} --replicas=$replicas';

/// The command for one of [kind]'s extra actions; null for [KubeAction.shell]
/// and [KubeAction.logs], which open elsewhere, and [KubeAction.scale],
/// which needs a count ([scaleCommand]).
String? actionCommand(
  KubeAction action,
  KubeKind kind,
  Json item, [
  DateTime? now,
]) {
  final name = nameOf(item);
  final ns = _nsFlag(namespaceOf(item));
  final ref = shellQuote('${kind.type}/$name');
  return switch (action) {
    KubeAction.restart => 'kubectl rollout restart $ref$ns',
    KubeAction.rollback => 'kubectl rollout undo $ref$ns',
    KubeAction.runNow =>
      'kubectl create job $ns --from=${shellQuote('cronjob/$name')} '
          '${shellQuote(manualJobName(name, now ?? DateTime.now()))}',
    KubeAction.suspend || KubeAction.resume =>
      'kubectl patch cronjob ${shellQuote(name)}$ns -p '
          '\'{"spec":{"suspend":${action == KubeAction.suspend}}}\'',
    KubeAction.cordon => 'kubectl cordon ${shellQuote(name)}',
    KubeAction.uncordon => 'kubectl uncordon ${shellQuote(name)}',
    // The exec worker is one per server: bound the wait so a stuck eviction
    // doesn't hold every other kubectl call behind it.
    KubeAction.drain =>
      'kubectl drain ${shellQuote(name)} --ignore-daemonsets '
          '--delete-emptydir-data --timeout=5m',
    KubeAction.scale || KubeAction.shell || KubeAction.logs => null,
  };
}

/// `<cronjob>-manual-<unix seconds>`, cut to the 63 characters a name allows.
String manualJobName(String cronJob, DateTime now) {
  final suffix = '-manual-${now.millisecondsSinceEpoch ~/ 1000}';
  final keep = 63 - suffix.length;
  return '${cronJob.length > keep ? cronJob.substring(0, keep) : cronJob}$suffix';
}

/// `kubectl exec -it` into [pod]'s [container], bash when it has one.
String shellCommand(String namespace, String pod, String? container) =>
    'kubectl exec -it -n ${shellQuote(namespace)} ${shellQuote(pod)}'
    '${container == null ? '' : ' -c ${shellQuote(container)}'} -- '
    "sh -c 'command -v bash >/dev/null && exec bash || exec sh'";

/// The current context on the first line (empty when none is set), then
/// every context name.
const kubeContextsCommand =
    r'printf "%s\n" "$(kubectl config current-context 2>/dev/null)"; '
    'kubectl config get-contexts -o name';

({String? current, List<String> names}) parseContexts(String output) {
  final lines = output.split('\n');
  final current = lines.first.trim();
  return (
    current: current.isEmpty ? null : current,
    names: [
      for (final line in lines.skip(1))
        if (line.trim().isNotEmpty) line.trim(),
    ],
  );
}

/// CPU in cores from a quantity like `3800m` or `4`.
double parseCpu(String quantity) => quantity.endsWith('m')
    ? (double.tryParse(quantity.substring(0, quantity.length - 1)) ?? 0) / 1000
    : double.tryParse(quantity) ?? 0;

const _byteUnits = {
  'Ki': 1024,
  'Mi': 1024 * 1024,
  'Gi': 1024 * 1024 * 1024,
  'Ti': 1024 * 1024 * 1024 * 1024,
  'K': 1000,
  'M': 1000 * 1000,
  'G': 1000 * 1000 * 1000,
  'T': 1000 * 1000 * 1000 * 1000,
};

/// Bytes from a quantity like `16302124Ki` or `2Gi`.
double parseBytes(String quantity) {
  for (final MapEntry(key: unit, value: factor) in _byteUnits.entries) {
    if (quantity.endsWith(unit)) {
      final number = quantity.substring(0, quantity.length - unit.length);
      return (double.tryParse(number) ?? 0) * factor;
    }
  }
  return double.tryParse(quantity) ?? 0;
}

String formatBytes(double bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 1)} '
      '${units[unit]}';
}

/// Sum of `kubectl top nodes --no-headers`: (cores, bytes) in use, or null
/// when metrics-server isn't there.
({double cpu, double memory})? parseTopNodes(String output) {
  var cpu = 0.0;
  var memory = 0.0;
  var rows = 0;
  for (final line in output.split('\n')) {
    final cols = line.trim().split(RegExp(r'\s+'));
    if (cols.length < 5) continue;
    cpu += parseCpu(cols[1]);
    memory += parseBytes(cols[3]);
    rows++;
  }
  return rows == 0 ? null : (cpu: cpu, memory: memory);
}

/// Separates the parts of a command that runs several kubectl calls.
const kubeSeparator = '---portix---';

/// `spec.selector.matchLabels` as a `-l` selector; null when there is none.
// ponytail: matchExpressions are left out; every built-in controller sets
// matchLabels, add them if a CRD-made workload needs it.
String? podSelector(Json item) {
  final labels = _map(item, 'spec.selector.matchLabels');
  if (labels.isEmpty) return null;
  return [
    for (final MapEntry(:key, :value) in labels.entries) '$key=$value',
  ].join(',');
}

/// A workload's latest state, its pods and its events, in one round trip.
String detailCommand(KubeKind kind, Json item) {
  final ns = _nsFlag(namespaceOf(item));
  final selector = podSelector(item);
  return [
    'kubectl get ${_target(kind, item)} -o json',
    selector == null
        ? "echo '{\"items\":[]}'"
        : 'kubectl get pods$ns -l ${shellQuote(selector)} -o json',
    'kubectl get events$ns --field-selector '
        '${shellQuote('involvedObject.name=${nameOf(item)}')} -o json',
  ].join(" && echo '$kubeSeparator' && ");
}

typedef KubeDetail = ({Json item, List<Json> pods, List<Json> events});

/// Parses [detailCommand]'s output; events newest first.
KubeDetail parseDetail(String output) {
  final [item, pods, events] = output.split('$kubeSeparator\n');
  String stamp(Json e) =>
      '${field(e, 'lastTimestamp') ?? field(e, 'eventTime') ?? field(e, 'metadata.creationTimestamp')}';
  return (
    item: jsonDecode(item) as Json,
    pods: parseItems(pods)..sort((a, b) => nameOf(a).compareTo(nameOf(b))),
    events: parseItems(events)..sort((a, b) => stamp(b).compareTo(stamp(a))),
  );
}

/// `status.conditions` as (type, status, reason, message).
List<({String type, bool ok, String reason, String message})> conditionsOf(
  Json item,
) => [
  for (final c in _list(item, 'status.conditions'))
    (
      type: '${c['type'] ?? ''}',
      ok: c['status'] == 'True',
      reason: '${c['reason'] ?? ''}',
      message: '${c['message'] ?? ''}',
    ),
];
