part of 'kubernetes_page.dart';

/// Sections of the Kubernetes view, grouped in its side panel like
/// Rancher's cluster explorer. [type] names the [KubeKind] a section lists;
/// the others (overview, contexts, logs) have pages of their own.
enum KubeSection {
  overview('Overview', Icons.dashboard_outlined, 'Cluster'),
  nodes('Nodes', Icons.storage_rounded, 'Cluster', 'nodes'),
  namespaces('Namespaces', Icons.folder_outlined, 'Cluster', 'namespaces'),
  events('Events', Icons.notifications_none_rounded, 'Cluster', 'events'),
  contexts('Contexts', Icons.hub_outlined, 'Cluster'),
  deployments(
    'Deployments',
    Icons.account_tree_outlined,
    'Workloads',
    'deployments',
  ),
  statefulSets(
    'StatefulSets',
    Icons.view_stream_outlined,
    'Workloads',
    'statefulsets',
  ),
  daemonSets('DaemonSets', Icons.lan_outlined, 'Workloads', 'daemonsets'),
  jobs('Jobs', Icons.task_alt_rounded, 'Workloads', 'jobs'),
  cronJobs('CronJobs', Icons.schedule_rounded, 'Workloads', 'cronjobs'),
  pods('Pods', Icons.view_in_ar_outlined, 'Workloads', 'pods'),
  services('Services', Icons.cable_rounded, 'Service Discovery', 'services'),
  ingresses(
    'Ingresses',
    Icons.public_rounded,
    'Service Discovery',
    'ingresses',
  ),
  autoscalers(
    'HorizontalPodAutoscalers',
    Icons.open_in_full_rounded,
    'Service Discovery',
    'horizontalpodautoscalers',
  ),
  persistentVolumes(
    'PersistentVolumes',
    Icons.save_outlined,
    'Storage',
    'persistentvolumes',
  ),
  volumeClaims(
    'PersistentVolumeClaims',
    Icons.inventory_2_outlined,
    'Storage',
    'persistentvolumeclaims',
  ),
  storageClasses(
    'StorageClasses',
    Icons.layers_outlined,
    'Storage',
    'storageclasses',
  ),
  configMaps('ConfigMaps', Icons.description_outlined, 'Storage', 'configmaps'),
  secrets('Secrets', Icons.key_outlined, 'Storage', 'secrets'),
  networkPolicies(
    'NetworkPolicies',
    Icons.shield_outlined,
    'Policy',
    'networkpolicies',
  ),
  disruptionBudgets(
    'PodDisruptionBudgets',
    Icons.health_and_safety_outlined,
    'Policy',
    'poddisruptionbudgets',
  ),
  resourceQuotas(
    'ResourceQuotas',
    Icons.pie_chart_outline_rounded,
    'Policy',
    'resourcequotas',
  ),
  serviceAccounts(
    'ServiceAccounts',
    Icons.badge_outlined,
    'RBAC',
    'serviceaccounts',
  ),
  roles('Roles', Icons.rule_rounded, 'RBAC', 'roles'),
  roleBindings('RoleBindings', Icons.link_rounded, 'RBAC', 'rolebindings'),
  clusterRoles(
    'ClusterRoles',
    Icons.admin_panel_settings_outlined,
    'RBAC',
    'clusterroles',
  ),
  clusterRoleBindings(
    'ClusterRoleBindings',
    Icons.link_rounded,
    'RBAC',
    'clusterrolebindings',
  ),
  logs('Logs', Icons.article_outlined, 'Monitoring');

  const KubeSection(this.label, this.icon, this.group, [this.type]);

  final String label;
  final IconData icon;
  final String group;
  final String? type;

  KubeKind? get kind => kubeKinds[type];
}

/// One open cluster: the server, the namespace filter and the section
/// showing, shared by that tab's sections.
class KubeCluster extends ChangeNotifier {
  KubeSection _section = KubeSection.overview;
  KubeSection get section => _section;
  set section(KubeSection value) {
    _section = value;
    notifyListeners();
  }

  String? profileId;
  List<String> namespaces = const [];

  /// Null = all namespaces.
  String? namespace;

  /// Bumped when the server or its kubeconfig context changes, so every
  /// section reloads.
  int generation = 0;

  /// The newest "View logs" ask; the serial tells repeats apart.
  ({String namespace, String pod, int serial})? logRequest;

  void pickServer(String id) {
    profileId = id;
    namespaces = const [];
    namespace = null;
    generation++;
    notifyListeners();
  }

  void pickNamespace(String? value) {
    namespace = value;
    notifyListeners();
  }

  void setNamespaces(List<String> value) {
    namespaces = value;
    if (namespace != null && !value.contains(namespace)) namespace = null;
    notifyListeners();
  }

  void reload() {
    generation++;
    notifyListeners();
  }

  void openLogs(String namespace, String pod) {
    logRequest = (
      namespace: namespace,
      pod: pod,
      serial: (logRequest?.serial ?? 0) + 1,
    );
    section = KubeSection.logs;
  }
}

/// The open clusters, one tab each, so each can be on a different server.
/// Forwards the active one's changes, for the side panel and title bar.
class KubeTabs extends ChangeNotifier {
  KubeTabs() {
    _tabs.first.addListener(notifyListeners);
  }

  final _tabs = [KubeCluster()];
  int _active = 0;

  List<KubeCluster> get tabs => List.unmodifiable(_tabs);
  int get active => _active;
  KubeCluster get current => _tabs[_active];

  void add() {
    _tabs.add(KubeCluster()..addListener(notifyListeners));
    _active = _tabs.length - 1;
    notifyListeners();
  }

  void select(int index) {
    _active = index;
    notifyListeners();
  }

  void close(int index) {
    // Not disposed: its pages still unregister from it as they unmount.
    _tabs.removeAt(index).removeListener(notifyListeners);
    if (_tabs.isEmpty) _tabs.add(KubeCluster()..addListener(notifyListeners));
    if (_active >= _tabs.length || _active > index) {
      _active = (_active - 1).clamp(0, _tabs.length - 1);
    }
    notifyListeners();
  }
}

final kubeTabs = KubeTabs();

/// Hands a cluster tab's [KubeCluster] to its sections.
class _KubeScope extends InheritedNotifier<KubeCluster> {
  const _KubeScope({required KubeCluster cluster, required super.child})
    : super(notifier: cluster);

  /// Without a dependency: callers listen to the cluster themselves.
  static KubeCluster of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_KubeScope>()!.notifier!;
}

/// kubectl on the picked server for a Kubernetes section: the running flag
/// and the last error, shown by [_ClusterFrame].
mixin _KubeExec<T extends StatefulWidget> on State<T> {
  final _manager = sl<ConnectionManager>();
  String? _error;
  bool _loading = false;

  /// This tab's cluster; a tab's pages never move to another one.
  late final kube = _KubeScope.of(context);

  String? get _profileId => kube.profileId;

  manager_profile.SshProfile? _profile() {
    final profile = context
        .read<SshWorkspaceBloc>()
        .state
        .profiles
        .where((p) => p.id == _profileId)
        .firstOrNull;
    return profile == null
        ? null
        : manager_profile.SshProfile.fromDomain(profile);
  }

  /// Output or error of [command], answering a host-key or OTP prompt
  /// once if the connection needs it (never when [quiet]).
  Future<(String?, String?)> _exec(String command, {bool quiet = false}) async {
    final profile = _profile();
    if (profile == null) return (null, 'Pick a server first.');
    Future<(String?, String?)> attempt() async => (await _manager.execOnProfile(
      profile,
      command,
    )).fold((failure) => (null, '$failure'), (output) => (output, null));

    var (output, error) = await attempt();
    if (quiet) return (output, error);
    if (error != null && mounted) {
      final hostKey = await resolveRefusedHostKey(context, _manager, profile);
      if (hostKey == true) (output, error) = await attempt();
      if (hostKey == false) error = 'Host key not trusted.';
    }
    while (error != null && mounted) {
      final prompts = await resolveAuthPrompts(context, _manager, profile);
      if (prompts != true) break;
      (output, error) = await attempt();
    }
    return (output, error);
  }

  /// Runs [command], showing progress and any error; null on failure.
  /// [quiet] runs (auto-refresh) leave the progress and prompts out.
  Future<String?> _run(String command, {bool quiet = false}) async {
    if (_profile() == null) return null;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final (output, error) = await _exec(command, quiet: quiet);
    if (!mounted) return null;
    setState(() {
      if (!quiet) _loading = false;
      _error = error;
    });
    return output;
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// The namespace filter of a cluster tab, for namespaced sections:
/// Rancher's namespace picker. The server is fixed when the tab opens.
class _KubeHeader extends StatefulWidget {
  const _KubeHeader();

  @override
  State<_KubeHeader> createState() => _KubeHeaderState();
}

class _KubeHeaderState extends State<_KubeHeader> with _KubeExec<_KubeHeader> {
  int _loadedGeneration = 0;

  @override
  void initState() {
    super.initState();
    kube.addListener(_onCluster);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onCluster();
    });
  }

  @override
  void dispose() {
    kube.removeListener(_onCluster);
    super.dispose();
  }

  void _onCluster() {
    if (kube.generation != _loadedGeneration && kube.profileId != null) {
      _loadedGeneration = kube.generation;
      unawaited(_loadNamespaces());
    }
    setState(() {});
  }

  Future<void> _loadNamespaces() async {
    final generation = kube.generation;
    final output = await _run('kubectl get namespaces -o name');
    if (output == null || kube.generation != generation) return;
    kube.setNamespaces([
      for (final line in output.split('\n'))
        if (line.trim().isNotEmpty) line.trim().replaceFirst('namespace/', ''),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final showNamespace = kube.section.kind?.namespaced ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showNamespace)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 380,
                child: _SelectButton<String?>(
                  icon: Icons.folder_outlined,
                  label: 'Namespace',
                  value: kube.namespace ?? 'All namespaces',
                  placeholder: 'Loading namespaces…',
                  enabled: !_loading && kube.namespaces.isNotEmpty,
                  noun: 'namespaces',
                  options: [
                    (
                      value: null,
                      label: 'All namespaces',
                      subtitle: null,
                      leading: Icon(
                        Icons.layers_outlined,
                        size: 18,
                        color: AppColors.accent,
                      ),
                      section: null,
                    ),
                    for (final ns in kube.namespaces)
                      (
                        value: ns,
                        label: ns,
                        subtitle: null,
                        leading: _NamespaceIcon(system: ns.startsWith('kube-')),
                        section: 'Namespaces',
                      ),
                  ],
                  selected: kube.namespace,
                  onSelected: kube.pickNamespace,
                ),
              ),
            ),
          ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _ErrorBanner(
                error: describeKubeError(error),
                retrying: _loading,
                onRetry: _loadNamespaces,
                onDismiss: () => setState(() => _error = null),
              ),
            ),
          ),
      ],
    );
  }
}

/// Side panel groups the user folded; kept while the app runs, so the
/// panel opens the way it was left.
final _collapsedGroups = <String>{};

class KubeSectionsPanel extends StatefulWidget {
  const KubeSectionsPanel({super.key});

  @override
  State<KubeSectionsPanel> createState() => _KubeSectionsPanelState();
}

class _KubeSectionsPanelState extends State<KubeSectionsPanel> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: kubeTabs,
    builder: (context, _) {
      final current = kubeTabs.current.section;
      return ListView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          for (final section in KubeSection.values) ...[
            if (section.index == 0 ||
                KubeSection.values[section.index - 1].group != section.group)
              _GroupHeader(
                label: section.group,
                collapsed: _collapsedGroups.contains(section.group),
                onTap: () => setState(() {
                  if (!_collapsedGroups.remove(section.group)) {
                    _collapsedGroups.add(section.group);
                  }
                }),
              ),
            // A folded group still shows the section that is open.
            if (!_collapsedGroups.contains(section.group) || section == current)
              SidePanelTile(
                icon: section.icon,
                label: section.label,
                selected: section == current,
                onTap: () => kubeTabs.current.section = section,
              ),
          ],
        ],
      );
    },
  );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.collapsed,
    required this.onTap,
  });

  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: !collapsed,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 4, 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: portixMuted(11))),
            Icon(
              collapsed
                  ? Icons.chevron_right_rounded
                  : Icons.expand_more_rounded,
              size: 16,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

/// What a new cluster tab shows: the servers marked "Runs Kubernetes", as
/// a grid like the SSH profiles. Picking one fixes the tab's server.
class _ServerPickPage extends StatefulWidget {
  const _ServerPickPage({required this.onPicked});

  final ValueChanged<String> onPicked;

  @override
  State<_ServerPickPage> createState() => _ServerPickPageState();
}

class _ServerPickPageState extends State<_ServerPickPage> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = context.select(
      (SshWorkspaceBloc bloc) => [
        for (final p in bloc.state.profiles)
          if (p.runsKubernetes) p,
      ],
    );
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final p in servers)
        if ([
          p.name,
          p.group,
          ...p.tags,
        ].join(' ').toLowerCase().contains(query))
          p,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Open a cluster', style: portixTitle(18)),
          const SizedBox(height: 4),
          Text(
            'Servers whose profile is marked "Runs Kubernetes"; their kubectl '
            'and kubeconfig are used.',
            style: portixMuted(13),
          ),
          const SizedBox(height: 16),
          if (servers.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 420,
                child: _FilterField(
                  controller: _search,
                  hint: 'Search servers',
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: servers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.view_in_ar_outlined,
                          size: 28,
                          color: AppColors.muted,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No server is marked "Runs Kubernetes" yet.',
                          style: portixMuted(13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Edit a profile and turn it on to open it here.',
                          style: portixMuted(12),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () => context.read<SshWorkspaceBloc>().add(
                            const NavigationChanged(WorkspaceView.gallery),
                          ),
                          icon: const Icon(
                            Icons.format_list_bulleted_rounded,
                            size: 16,
                          ),
                          label: const Text('Go to SSH profiles'),
                        ),
                      ],
                    ),
                  )
                : shown.isEmpty
                ? const _Empty(
                    Icons.filter_alt_off_outlined,
                    'No server matches the search.',
                  )
                : GridView(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    children: [
                      for (final p in shown)
                        _ServerCard(
                          profile: p,
                          onTap: () => widget.onPicked(p.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.profile, required this.onTap});

  final domain.SshProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      hoverColor: AppColors.surfaceDark,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            ProfileOsIcon(profile: profile, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    overflow: TextOverflow.ellipsis,
                    style: portixTitle(13),
                  ),
                  if (profile.group.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      profile.group,
                      overflow: TextOverflow.ellipsis,
                      style: portixMuted(12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Toolbar on top, then a bordered box holding the error (if any) and
/// [child].
class _ClusterFrame extends StatelessWidget {
  const _ClusterFrame({
    required this.toolbar,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onDismissError,
    required this.child,
    this.note,
  });

  final List<Widget> toolbar;
  final bool loading;
  final String? error;

  /// Null while there's nothing to refresh yet.
  final VoidCallback? onRefresh;
  final VoidCallback onDismissError;
  final Widget child;

  /// A muted line under the toolbar.
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ...toolbar,
              const SizedBox(width: 8),
              SizedBox(
                height: _controlHeight,
                child: FilledButton.icon(
                  onPressed: loading ? null : onRefresh,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, _controlHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: loading
                      ? SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onAccent,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh'),
                ),
              ),
            ],
          ),
          if (note case final note?) ...[
            const SizedBox(height: 8),
            Text(note, style: portixMuted(12)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error case final error?)
                    _ErrorBanner(
                      error: describeKubeError(error),
                      retrying: loading,
                      onRetry: onRefresh ?? () {},
                      onDismiss: onDismissError,
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.message);

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 28, color: AppColors.muted),
        const SizedBox(height: 10),
        Text(message, style: portixMuted(13)),
      ],
    ),
  );
}

const _pickServer = 'Pick a server with kubectl above.';

/// A search box for a [_ClusterFrame] toolbar.
class _FilterField extends StatelessWidget {
  const _FilterField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => _ControlShell(
    onTap: null,
    child: Row(
      children: [
        Icon(Icons.search_rounded, size: 16, color: AppColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            style: appFieldTextStyle(),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintStyle: portixMuted(13),
              hintText: hint,
            ),
          ),
        ),
      ],
    ),
  );
}

enum _Common { yaml, describe, delete }

/// One [KubeKind] as a sortable, searchable table, Rancher-style: the dot
/// shows health, a click describes, the menu holds the actions.
class _ResourcePage extends StatefulWidget {
  const _ResourcePage({required this.kind, required this.visible, super.key});

  final KubeKind kind;
  final bool visible;

  @override
  State<_ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends State<_ResourcePage>
    with _KubeExec<_ResourcePage> {
  final _search = TextEditingController();
  List<Json> _items = const [];

  /// What [_items] were read for; a different one reloads.
  Object? _loadedFor;
  int? _sortColumn;
  bool _ascending = true;
  Timer? _timer;

  KubeKind get _kind => widget.kind;
  String? get _namespace => _kind.namespaced ? kube.namespace : null;
  Object get _key => (kube.profileId, _namespace, kube.generation);

  @override
  void initState() {
    super.initState();
    kube.addListener(_sync);
    _search.addListener(() => setState(() {}));
    _sync();
  }

  @override
  void didUpdateWidget(_ResourcePage old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _sync();
  }

  @override
  void dispose() {
    kube.removeListener(_sync);
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Loads when shown for a new server or namespace, and refreshes
  /// quietly every 10 s while shown.
  void _sync() {
    _timer?.cancel();
    if (!widget.visible || kube.profileId == null) return;
    if (_loadedFor != _key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loadedFor != _key) unawaited(_load());
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_loading && _error == null) unawaited(_load(quiet: true));
    });
  }

  Future<void> _load({bool quiet = false}) async {
    final key = _key;
    if (!quiet && _loadedFor != key) setState(() => _items = const []);
    final output = await _run(listCommand(_kind, _namespace), quiet: quiet);
    if (output == null || !mounted || _key != key) return;
    try {
      final items = parseItems(output);
      setState(() {
        _items = items;
        _loadedFor = key;
      });
    } on Object {
      setState(() => _error = 'Unexpected kubectl output:\n$output');
    }
  }

  List<KubeColumn> get _columns => [
    _kind.columns.first,
    if (_kind.namespaced && kube.namespace == null)
      (header: 'Namespace', flex: 2, cell: (i) => namespaceOf(i) ?? ''),
    ..._kind.columns.skip(1),
  ];

  List<Json> _shown(List<KubeColumn> columns) {
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final item in _items)
        if (query.isEmpty ||
            columns.any((c) => c.cell(item).toLowerCase().contains(query)))
          item,
    ];
    final sort = _sortColumn;
    if (sort != null && sort < columns.length) {
      final column = columns[sort];
      final age = column.header == 'Age';
      Comparable<Object> key(Json item) => age
          ? '${field(item, 'metadata.creationTimestamp')}'
          : num.tryParse(column.cell(item)) ?? column.cell(item).toLowerCase();
      int compare(Json a, Json b) {
        final (x, y) = (key(a), key(b));
        final result = x.runtimeType == y.runtimeType
            ? x.compareTo(y)
            : '$x'.compareTo('$y');
        // Age grows as the timestamp shrinks.
        return age ? -result : result;
      }

      shown.sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
    }
    return shown;
  }

  /// Runs an action's [command], tells its outcome and reloads.
  Future<void> _apply(String command) async {
    final output = await _run(command);
    if (output == null || !mounted) return;
    final said = output.trim();
    _toast(said.isEmpty ? 'Done.' : said.split('\n').last);
    await _load();
  }

  Future<void> _describe(Json item) async {
    final output = await _run(describeCommand(_kind, item));
    if (output == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _TextDialog(title: '${_kind.label} · ${nameOf(item)}', text: output),
    );
  }

  Future<void> _editYaml(Json item) async {
    final yaml = await _run(yamlCommand(_kind, item));
    if (yaml == null || !mounted) return;
    await _openYaml('Edit ${nameOf(item)}', yaml);
  }

  Future<void> _openYaml(String title, String yaml, {String? namespace}) async {
    final said = await showDialog<String>(
      context: context,
      builder: (_) => _YamlDialog(
        title: title,
        yaml: yaml,
        onApply: (text) => _exec(applyCommand(text, namespace)),
      ),
    );
    if (said == null || !mounted) return;
    _toast(said.trim().isEmpty ? 'Applied.' : said.trim());
    await _load();
  }

  Future<void> _delete(Json item) async {
    final ns = namespaceOf(item);
    if (await _confirm(
      context,
      title: 'Delete ${nameOf(item)}?',
      message:
          'Deletes this ${_kind.label} entry${ns == null ? '' : ' in $ns'}. '
          'This cannot be undone.',
      action: 'Delete',
    )) {
      await _apply(deleteCommand(_kind, item));
    }
  }

  Future<void> _action(KubeAction action, Json item) async {
    final name = nameOf(item);
    switch (action) {
      case KubeAction.logs:
        kube.openLogs(namespaceOf(item)!, name);
      case KubeAction.shell:
        final containers = podContainers(item);
        String? container;
        if (containers.length > 1) {
          container = await showDialog<String>(
            context: context,
            builder: (dialogContext) => SimpleDialog(
              title: const Text('Container'),
              children: [
                for (final c in containers)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(dialogContext).pop(c),
                    child: Text(c),
                  ),
              ],
            ),
          );
          if (container == null) return;
        }
        if (!mounted) return;
        _openShell(
          context,
          kube.profileId!,
          shellCommand(namespaceOf(item)!, name, container),
        );
      case KubeAction.scale:
        final replicas = await showDialog<int>(
          context: context,
          builder: (_) => _ScaleDialog(
            name: name,
            replicas: (field(item, 'spec.replicas') as num?)?.toInt() ?? 0,
          ),
        );
        if (replicas != null) {
          await _apply(scaleCommand(_kind, item, replicas));
        }
      case KubeAction.drain || KubeAction.rollback:
        if (await _confirm(
          context,
          title: '${action.label} $name?',
          message: action == KubeAction.drain
              ? 'Cordons the node and evicts its pods (DaemonSets stay). '
                    'Pods without a controller are not recreated elsewhere.'
              : 'Rolls back to the previous revision.',
          action: action.label,
        )) {
          await _apply(actionCommand(action, _kind, item)!);
        }
      default:
        await _apply(actionCommand(action, _kind, item)!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    final shown = _shown(columns);
    final where = _kind.namespaced && kube.namespace != null
        ? ' in ${kube.namespace}'
        : '';
    return _ClusterFrame(
      toolbar: [
        Expanded(
          child: _FilterField(
            controller: _search,
            hint: 'Filter ${_kind.label}',
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _search.text.isEmpty
              ? '${_items.length}'
              : '${shown.length} of ${_items.length}',
          style: portixMuted(12),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: _controlHeight,
          child: OutlinedButton.icon(
            onPressed: _loading || kube.profileId == null
                ? null
                : () =>
                      _openYaml('Import YAML$where', '', namespace: _namespace),
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Import YAML'),
          ),
        ),
      ],
      loading: _loading,
      error: _error,
      onRefresh: kube.profileId == null ? null : _load,
      onDismissError: () => setState(() => _error = null),
      child: kube.profileId == null
          ? const _Empty(Icons.dns_outlined, _pickServer)
          : _items.isEmpty
          ? _Empty(
              Icons.inbox_outlined,
              _loading ? 'Loading ${_kind.label}…' : 'No ${_kind.label}$where.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TableHeader(
                  columns: columns,
                  dot: _kind.health != null,
                  sortColumn: _sortColumn,
                  ascending: _ascending,
                  onSort: (i) => setState(() {
                    _ascending = _sortColumn == i ? !_ascending : true;
                    _sortColumn = i;
                  }),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const _Empty(
                          Icons.filter_alt_off_outlined,
                          'Nothing matches the filter.',
                        )
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (_, i) => _TableRow(
                            item: shown[i],
                            columns: columns,
                            health: _kind.health?.call(shown[i]),
                            odd: i.isOdd,
                            enabled: !_loading,
                            actions: _kind.actions(shown[i]),
                            onDescribe: () => _describe(shown[i]),
                            onAction: (action) => _action(action, shown[i]),
                            onCommon: (common) => switch (common) {
                              _Common.yaml => _editYaml(shown[i]),
                              _Common.describe => _describe(shown[i]),
                              _Common.delete => _delete(shown[i]),
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

/// Opens a terminal on [profileId] and types [command] once it connects.
void _openShell(BuildContext context, String profileId, String command) {
  final profile = context
      .read<SshWorkspaceBloc>()
      .state
      .profiles
      .where((p) => p.id == profileId)
      .firstOrNull;
  if (profile == null) return;
  final manager = sl<ConnectionManager>();
  final before = {for (final s in manager.sessions) s.id};
  Timer? timeout;
  late final VoidCallback listener;
  void stop() {
    manager.removeListener(listener);
    timeout?.cancel();
  }

  listener = () {
    final session = manager.sessions
        .where((s) => s.profileId == profileId && !before.contains(s.id))
        .firstOrNull;
    if (session == null ||
        session.status != session_models.ConnectionStatus.connected) {
      return;
    }
    stop();
    unawaited(manager.sendTerminalInput(session.id, '$command\r'));
  };
  manager.addListener(listener);
  // Long enough for a host-key or OTP prompt in the terminal.
  timeout = Timer(const Duration(minutes: 2), stop);
  context.read<SshSessionBloc>().add(
    SshSessionOpenRequested(
      profile: profile,
      target: SshSessionTarget.remoteFolder,
    ),
  );
}

const _dotWidth = 26.0;
const _menuWidth = 40.0;

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.columns,
    required this.dot,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
  });

  final List<KubeColumn> columns;
  final bool dot;
  final int? sortColumn;
  final bool ascending;
  final ValueChanged<int> onSort;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        if (dot) const SizedBox(width: _dotWidth),
        for (final (i, column) in columns.indexed)
          Expanded(
            flex: column.flex,
            child: InkWell(
              onTap: () => onSort(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        column.header,
                        overflow: TextOverflow.ellipsis,
                        style: portixMuted(12).copyWith(
                          fontWeight: FontWeight.w500,
                          color: sortColumn == i ? AppColors.text : null,
                        ),
                      ),
                    ),
                    if (sortColumn == i)
                      Icon(
                        ascending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: AppColors.text,
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(width: _menuWidth),
      ],
    ),
  );
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.item,
    required this.columns,
    required this.health,
    required this.odd,
    required this.enabled,
    required this.actions,
    required this.onDescribe,
    required this.onAction,
    required this.onCommon,
  });

  final Json item;
  final List<KubeColumn> columns;
  final PodHealth? health;
  final bool odd;
  final bool enabled;
  final List<KubeAction> actions;
  final VoidCallback onDescribe;
  final ValueChanged<KubeAction> onAction;
  final ValueChanged<_Common> onCommon;

  @override
  Widget build(BuildContext context) {
    final health = this.health;
    return Material(
      color: odd
          ? AppColors.surface.withValues(alpha: .35)
          : Colors.transparent,
      child: InkWell(
        onTap: enabled ? onDescribe : null,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border.withValues(alpha: .5)),
            ),
          ),
          child: Row(
            children: [
              if (health != null)
                SizedBox(width: _dotWidth, child: _PodDot(health)),
              for (final (i, column) in columns.indexed)
                Expanded(
                  flex: column.flex,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Tooltip(
                      message: column.cell(item),
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(
                        column.cell(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: i == 0
                              ? FontWeight.w500
                              : FontWeight.w400,
                          color: i == 0
                              ? AppColors.text
                              : AppColors.text.withValues(alpha: .78),
                        ),
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: _menuWidth,
                child: PopupMenuButton<Object>(
                  enabled: enabled,
                  tooltip: 'Actions',
                  iconSize: 18,
                  icon: Icon(Icons.more_vert_rounded, color: AppColors.muted),
                  onSelected: (choice) => switch (choice) {
                    final KubeAction action => onAction(action),
                    final _Common common => onCommon(common),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    for (final action in actions)
                      _menuItem(action, action.label, _actionIcon(action)),
                    if (actions.isNotEmpty) const PopupMenuDivider(),
                    _menuItem(
                      _Common.yaml,
                      'Edit YAML',
                      Icons.edit_note_rounded,
                    ),
                    _menuItem(
                      _Common.describe,
                      'Describe',
                      Icons.info_outline_rounded,
                    ),
                    const PopupMenuDivider(),
                    _menuItem(
                      _Common.delete,
                      'Delete',
                      Icons.delete_outline_rounded,
                      danger: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _actionIcon(KubeAction action) => switch (action) {
    KubeAction.scale => Icons.unfold_more_rounded,
    KubeAction.restart => Icons.restart_alt_rounded,
    KubeAction.rollback => Icons.undo_rounded,
    KubeAction.runNow => Icons.play_arrow_rounded,
    KubeAction.suspend => Icons.pause_rounded,
    KubeAction.resume => Icons.play_circle_outline_rounded,
    KubeAction.cordon => Icons.block_rounded,
    KubeAction.uncordon => Icons.check_circle_outline_rounded,
    KubeAction.drain => Icons.logout_rounded,
    KubeAction.shell => Icons.terminal_rounded,
    KubeAction.logs => Icons.article_outlined,
  };

  PopupMenuItem<Object> _menuItem(
    Object value,
    String label,
    IconData icon, {
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.text;
    return PopupMenuItem(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

class _DialogTitle extends StatelessWidget {
  const _DialogTitle({required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.only(left: 18, right: 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
        ),
        ...actions,
        IconButton(
          tooltip: 'Close',
          iconSize: 18,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

/// A large dialog: [_DialogTitle] over [child].
class _BigDialog extends StatelessWidget {
  const _BigDialog({
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (size.width * .8).clamp(360.0, 1100.0),
        height: size.height * .85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogTitle(title: title, actions: actions),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Read-only kubectl output (describe), selectable and copyable.
class _TextDialog extends StatelessWidget {
  const _TextDialog({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => _BigDialog(
    title: title,
    actions: [
      IconButton(
        tooltip: 'Copy',
        iconSize: 16,
        onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        icon: const Icon(Icons.copy_rounded),
      ),
    ],
    child: Container(
      color: AppColors.surfaceDark,
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: _mono.copyWith(
            fontSize: 12,
            height: 1.5,
            color: AppColors.text,
          ),
        ),
      ),
    ),
  );
}

/// A YAML editor that `kubectl apply`s on Apply and stays open on failure,
/// showing why. Pops with what kubectl said.
class _YamlDialog extends StatefulWidget {
  const _YamlDialog({
    required this.title,
    required this.yaml,
    required this.onApply,
  });

  final String title;
  final String yaml;

  /// kubectl's output, or the error.
  final Future<(String?, String?)> Function(String yaml) onApply;

  @override
  State<_YamlDialog> createState() => _YamlDialogState();
}

class _YamlDialogState extends State<_YamlDialog> {
  late final _text = TextEditingController(text: widget.yaml);
  bool _applying = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    final (output, error) = await widget.onApply(_text.text);
    if (!mounted) return;
    if (error == null) return Navigator.of(context).pop(output ?? '');
    setState(() {
      _applying = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => _BigDialog(
    title: widget.title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: AppColors.surfaceDark,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _text,
              expands: true,
              maxLines: null,
              autofocus: widget.yaml.isEmpty,
              style: _mono.copyWith(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.text,
              ),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintStyle: portixMuted(13),
                hintText:
                    'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: …',
              ),
            ),
          ),
        ),
        if (_error case final error?)
          _ErrorBanner(
            error: describeKubeError(error),
            retrying: _applying,
            onRetry: _save,
            onDismiss: () => setState(() => _error = null),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _applying ? null : _save,
                icon: _applying
                    ? SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onAccent,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ScaleDialog extends StatefulWidget {
  const _ScaleDialog({required this.name, required this.replicas});

  final String name;
  final int replicas;

  @override
  State<_ScaleDialog> createState() => _ScaleDialogState();
}

class _ScaleDialogState extends State<_ScaleDialog> {
  late int _replicas = widget.replicas;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Scale ${widget.name}'),
    content: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Fewer',
          onPressed: _replicas == 0 ? null : () => setState(() => _replicas--),
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 64,
          child: Text(
            '$_replicas',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, color: AppColors.text),
          ),
        ),
        IconButton(
          tooltip: 'More',
          onPressed: () => setState(() => _replicas++),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _replicas == widget.replicas
            ? null
            : () => Navigator.of(context).pop(_replicas),
        child: Text('Scale to $_replicas'),
      ),
    ],
  );
}

/// Loads a section's data once per server/context while it is visible.
mixin _LoadWhenShown<T extends StatefulWidget> on _KubeExec<T> {
  Object? _loadedFor;
  Object get _key => (kube.profileId, kube.generation);
  bool get _visible;
  Future<void> _load();

  @override
  void initState() {
    super.initState();
    kube.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    kube.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (_visible && kube.profileId != null && _loadedFor != _key) {
      _loadedFor = _key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
  }
}

/// Cluster health at a glance: nodes, pods, deployments, capacity and use,
/// and the latest warnings.
class _OverviewPage extends StatefulWidget {
  const _OverviewPage({required this.visible});

  final bool visible;

  @override
  State<_OverviewPage> createState() => _OverviewPageState();
}

typedef _Overview = ({
  int nodes,
  int readyNodes,
  double cpu,
  double memory,
  ({double cpu, double memory})? used,
  Map<String, int> podPhases,
  int deployments,
  int availableDeployments,
  String version,
  List<Json> warnings,
});

const _sep = '---portix---';

/// One round trip for everything the overview shows; `top` and `version`
/// may fail without failing the rest.
final _overviewCommand = [
  'kubectl get nodes -o json',
  'kubectl get pods -A --no-headers -o custom-columns=PHASE:.status.phase',
  'kubectl get deployments -A --no-headers '
      '-o custom-columns=WANT:.spec.replicas,HAVE:.status.availableReplicas',
  'kubectl get events -A --field-selector type=Warning -o json',
  '{ kubectl top nodes --no-headers 2>/dev/null || true; }',
  '{ kubectl version -o json 2>/dev/null || true; }',
].join(" && echo '$_sep' && ");

_Overview parseOverview(String output) {
  final [nodesJson, pods, deployments, events, top, version] = output.split(
    '$_sep\n',
  );
  final nodes = parseItems(nodesJson);
  final phases = <String, int>{};
  for (final line in pods.split('\n')) {
    if (line.trim().isNotEmpty) {
      phases.update(line.trim(), (n) => n + 1, ifAbsent: () => 1);
    }
  }
  var total = 0;
  var available = 0;
  for (final line in deployments.split('\n')) {
    final cols = line.trim().split(RegExp(r'\s+'));
    if (cols.length != 2) continue;
    total++;
    if (cols[0] == cols[1] || cols[0] == '0') available++;
  }
  String stamp(Json e) =>
      '${field(e, 'lastTimestamp') ?? field(e, 'eventTime') ?? field(e, 'metadata.creationTimestamp')}';
  final warnings = parseItems(events)
    ..sort((a, b) => stamp(b).compareTo(stamp(a)));
  var serverVersion = '';
  try {
    serverVersion =
        '${field(jsonDecode(version) as Json, 'serverVersion.gitVersion') ?? ''}';
  } on FormatException {
    // No answer, or a kubectl too old for -o json: leave it out.
  }
  final nodeHealth = kubeKinds['nodes']!.health!;
  return (
    nodes: nodes.length,
    readyNodes: nodes.where((n) => nodeHealth(n) != PodHealth.failing).length,
    cpu: nodes.fold(
      0.0,
      (sum, n) => sum + parseCpu('${field(n, 'status.allocatable.cpu') ?? 0}'),
    ),
    memory: nodes.fold(
      0.0,
      (sum, n) =>
          sum + parseBytes('${field(n, 'status.allocatable.memory') ?? 0}'),
    ),
    used: parseTopNodes(top),
    podPhases: phases,
    deployments: total,
    availableDeployments: available,
    version: serverVersion,
    warnings: warnings.take(20).toList(),
  );
}

class _OverviewPageState extends State<_OverviewPage>
    with _KubeExec<_OverviewPage>, _LoadWhenShown<_OverviewPage> {
  _Overview? _data;

  @override
  bool get _visible => widget.visible;

  @override
  void didUpdateWidget(_OverviewPage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  Future<void> _load() async {
    final key = _key;
    final output = await _run(_overviewCommand);
    if (output == null || !mounted || _key != key) return;
    try {
      setState(() => _data = parseOverview(output));
    } on Object {
      setState(() => _error = 'Unexpected kubectl output:\n$output');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    int phase(String name) => data?.podPhases[name] ?? 0;
    return _ClusterFrame(
      toolbar: [
        Expanded(
          child: Text(
            data == null || data.version.isEmpty
                ? 'Cluster overview'
                : 'Cluster overview · Kubernetes ${data.version}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
        ),
      ],
      loading: _loading,
      error: _error,
      onRefresh: kube.profileId == null ? null : _load,
      onDismissError: () => setState(() => _error = null),
      child: kube.profileId == null
          ? const _Empty(Icons.dns_outlined, _pickServer)
          : data == null
          ? _Empty(
              Icons.dashboard_outlined,
              _loading ? 'Reading the cluster…' : 'No data yet.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      icon: Icons.storage_rounded,
                      label: 'Nodes',
                      value: '${data.readyNodes}/${data.nodes}',
                      detail: data.readyNodes == data.nodes
                          ? 'All ready'
                          : '${data.nodes - data.readyNodes} not ready',
                      bad: data.readyNodes < data.nodes,
                      onTap: () => kube.section = KubeSection.nodes,
                    ),
                    _StatCard(
                      icon: Icons.view_in_ar_outlined,
                      label: 'Pods',
                      value:
                          '${phase('Running')}/'
                          '${data.podPhases.values.fold(0, (a, b) => a + b)}',
                      detail: [
                        'running',
                        if (phase('Pending') > 0) '${phase('Pending')} pending',
                        if (phase('Failed') > 0) '${phase('Failed')} failed',
                      ].join(' · '),
                      bad: phase('Failed') > 0,
                      onTap: () => kube.section = KubeSection.pods,
                    ),
                    _StatCard(
                      icon: Icons.account_tree_outlined,
                      label: 'Deployments',
                      value: '${data.availableDeployments}/${data.deployments}',
                      detail: 'fully available',
                      bad: data.availableDeployments < data.deployments,
                      onTap: () => kube.section = KubeSection.deployments,
                    ),
                    _StatCard(
                      icon: Icons.warning_amber_rounded,
                      label: 'Warnings',
                      value: '${data.warnings.length}',
                      detail: 'latest events',
                      bad: data.warnings.isNotEmpty,
                      onTap: () => kube.section = KubeSection.events,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Capacity', style: portixMuted(12)),
                const SizedBox(height: 8),
                _UsageBar(
                  label: 'CPU',
                  used: data.used?.cpu,
                  total: data.cpu,
                  format: (v) => '${v.toStringAsFixed(v < 10 ? 2 : 1)} cores',
                ),
                const SizedBox(height: 10),
                _UsageBar(
                  label: 'Memory',
                  used: data.used?.memory,
                  total: data.memory,
                  format: formatBytes,
                ),
                if (data.used == null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Usage needs metrics-server (kubectl top); showing '
                    'allocatable only.',
                    style: portixMuted(12),
                  ),
                ],
                const SizedBox(height: 20),
                Text('Recent warnings', style: portixMuted(12)),
                const SizedBox(height: 8),
                if (data.warnings.isEmpty)
                  Text('No warning events.', style: portixMuted(13))
                else
                  for (final e in data.warnings) _WarningLine(e),
              ],
            ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  const _WarningLine(this.event);

  final Json event;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: AppColors.amber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${field(event, 'reason')} · '
                      '${field(event, 'involvedObject.kind')}/'
                      '${field(event, 'involvedObject.name')}'
                      '${namespaceOf(event) == null ? '' : ' (${namespaceOf(event)})'}  ',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
                TextSpan(
                  text: '${field(event, 'message') ?? ''}',
                  style: portixMuted(12.5),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.bad,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool bad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: bad ? AppColors.danger : AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(label, style: portixMuted(12)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                overflow: TextOverflow.ellipsis,
                style: portixMuted(
                  12,
                ).copyWith(color: bad ? AppColors.danger : null),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.used,
    required this.total,
    required this.format,
  });

  final String label;
  final double? used;
  final double total;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final used = this.used;
    final ratio = used == null || total == 0
        ? 0.0
        : (used / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: AppColors.text)),
            const Spacer(),
            Text(
              used == null
                  ? '${format(total)} allocatable'
                  : '${format(used)} of ${format(total)} · '
                        '${(ratio * 100).round()}%',
              style: portixMuted(12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: AppColors.surface,
            color: ratio > .85
                ? AppColors.danger
                : ratio > .65
                ? AppColors.amber
                : AppColors.accent,
          ),
        ),
      ],
    );
  }
}

/// The server kubeconfig's contexts; switching one changes the cluster
/// every Kubernetes section reads.
class _ContextsPage extends StatefulWidget {
  const _ContextsPage({required this.visible});

  final bool visible;

  @override
  State<_ContextsPage> createState() => _ContextsPageState();
}

class _ContextsPageState extends State<_ContextsPage>
    with _KubeExec<_ContextsPage>, _LoadWhenShown<_ContextsPage> {
  String? _current;
  List<String> _contexts = const [];

  @override
  bool get _visible => widget.visible;

  @override
  void didUpdateWidget(_ContextsPage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  Future<void> _load() async {
    final key = _key;
    final output = await _run(kubeContextsCommand);
    if (output == null || !mounted || _key != key) return;
    final (:current, :names) = parseContexts(output);
    setState(() {
      _current = current;
      _contexts = names;
    });
  }

  Future<void> _use(String name) async {
    if (await _run('kubectl config use-context ${shellQuote(name)}') != null) {
      kube.reload(); // every section reads the new cluster
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ClusterFrame(
      toolbar: [
        Expanded(
          child: Text(
            _current == null ? 'Contexts' : 'Contexts · using $_current',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
        ),
      ],
      note:
          'Switching edits the kubeconfig on the server, so every section '
          'and any kubectl there follows it.',
      loading: _loading,
      error: _error,
      onRefresh: kube.profileId == null ? null : _load,
      onDismissError: () => setState(() => _error = null),
      child: kube.profileId == null
          ? const _Empty(Icons.dns_outlined, _pickServer)
          : _contexts.isEmpty
          ? const _Empty(Icons.hub_outlined, 'No contexts in the kubeconfig.')
          : ListView(
              children: [
                for (final name in _contexts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          name == _current
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 18,
                          color: name == _current
                              ? AppColors.green
                              : AppColors.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (name == _current)
                          Text('Current', style: portixMuted(12))
                        else
                          TextButton.icon(
                            onPressed: _loading ? null : () => _use(name),
                            icon: const Icon(
                              Icons.swap_horiz_rounded,
                              size: 15,
                            ),
                            label: const Text('Use'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
