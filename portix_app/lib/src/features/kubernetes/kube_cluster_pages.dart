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

  /// The connect checks passed for [profileId]; until then the tab shows
  /// them instead of the sections.
  bool connected = false;
  List<String> namespaces = const [];

  /// The namespaces picked; empty = all of them.
  final picked = <String>{};

  /// The one namespace picked, for `-n`; null when all or several are.
  String? get namespace => picked.length == 1 ? picked.single : null;

  /// Bumped when the server or its kubeconfig context changes, so every
  /// section reloads.
  int generation = 0;

  /// The newest "View logs" ask; the serial tells repeats apart.
  ({String namespace, String pod, int serial})? logRequest;

  void pickServer(String id) {
    profileId = id;
    connected = false;
    namespaces = const [];
    picked.clear();
    generation++;
    notifyListeners();
  }

  void markConnected() {
    connected = true;
    notifyListeners();
  }

  /// Back to picking a server, e.g. when the checks failed.
  void leaveServer() {
    profileId = null;
    connected = false;
    notifyListeners();
  }

  /// Adds or drops [value]; null goes back to all namespaces.
  void toggleNamespace(String? value) {
    if (value == null) {
      picked.clear();
    } else if (!picked.remove(value)) {
      picked.add(value);
    }
    notifyListeners();
  }

  void setNamespaces(List<String> value) {
    namespaces = value;
    picked.retainAll(value);
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
                  value: kube.picked.isEmpty
                      ? 'All namespaces'
                      : (kube.picked.toList()..sort()).join(', '),
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
                  selected: null,
                  isSelected: (ns) => ns == null
                      ? kube.picked.isEmpty
                      : kube.picked.contains(ns),
                  onSelected: kube.toggleNamespace,
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

/// What a tab shows right after its server is picked: the
/// [kubeConnectSteps] run one by one, each ticking off with what it found.
/// All passing opens the cluster; one failing stops with its error, Retry
/// and a way back to the servers.
class _ConnectPage extends StatefulWidget {
  const _ConnectPage({super.key});

  @override
  State<_ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<_ConnectPage>
    with _KubeExec<_ConnectPage> {
  /// What each step found; a step past the end has not run yet.
  final _found = <String>[];

  /// The step that failed, with its error.
  (int, String)? _failed;

  /// Set while a password the connection needs is not saved: whose it is
  /// (the server's, or a jump host's).
  ({String id, String name})? _needsPassword;
  final _password = TextEditingController();
  bool _savingPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _found.clear();
      _failed = null;
      _needsPassword = null;
    });
    // A password that was never saved (or the keychain lost) is asked for
    // here, before any connect; an unknown host key is asked by _exec.
    if (_profile() case final profile?) {
      try {
        await _manager.credentials.resolve(profile);
      } on PasswordUnavailableException catch (e) {
        if (mounted) {
          setState(
            () => _needsPassword = (id: e.profileId, name: e.profileName),
          );
        }
        return;
      } on Object {
        // A broken jump host chain fails the first step with its message.
      }
    }
    for (final (i, step) in kubeConnectSteps.indexed) {
      final (output, error) = await _exec(step.command);
      if (!mounted) return;
      if (output == null) {
        setState(() => _failed = (i, error ?? 'No output.'));
        return;
      }
      setState(() => _found.add(describeConnectStep(i, output)));
    }
    // A beat with every step ticked, so the checks read as done.
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) kube.markConnected();
  }

  /// Saves the typed password in the keychain, where connects read it,
  /// then runs the checks again.
  Future<void> _submitPassword() async {
    final need = _needsPassword;
    final password = _password.text;
    if (need == null || password.isEmpty || _savingPassword) return;
    setState(() => _savingPassword = true);
    try {
      await _manager.credentials.savePassword(need.id, password);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _savingPassword = false;
          _needsPassword = null;
          _failed = (0, 'Could not save the password in the keychain: $e');
        });
      }
      return;
    }
    if (!mounted) return;
    _password.clear();
    setState(() => _savingPassword = false);
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context
        .select((SshWorkspaceBloc bloc) => bloc.state.profiles)
        .where((p) => p.id == kube.profileId)
        .firstOrNull;
    final failed = _failed;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (profile != null)
                    ProfileOsIcon(profile: profile, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.name ?? 'Unknown server',
                          overflow: TextOverflow.ellipsis,
                          style: portixTitle(16),
                        ),
                        Text(
                          _needsPassword != null
                              ? 'Password needed'
                              : failed == null
                              ? 'Connecting to the cluster…'
                              : 'Could not open the cluster',
                          style: portixMuted(12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ConnectStepper(
                found: _found.length,
                failed: failed?.$1,
                waitingForPassword: _needsPassword != null,
              ),
              if (_needsPassword case final need?) ...[
                const SizedBox(height: 12),
                _PasswordForm(
                  name: need.name,
                  controller: _password,
                  saving: _savingPassword,
                  onSubmit: _submitPassword,
                  onCancel: kube.leaveServer,
                ),
              ],
              const SizedBox(height: 8),
              for (final (i, found) in _found.indexed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${kubeConnectSteps[i].label}: $found',
                          overflow: TextOverflow.ellipsis,
                          style: portixMuted(12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              if (failed != null) ...[
                const SizedBox(height: 12),
                _ConnectError(describeKubeError(failed.$2)),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: kube.leaveServer,
                      child: const Text('Choose another server'),
                    ),
                    // A rejected or stale saved password: type it again.
                    if (failed.$1 == 0 &&
                        profile?.authMethod == domain.AuthMethod.password)
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _failed = null;
                          _needsPassword = (
                            id: profile!.id,
                            name: profile.name,
                          );
                        }),
                        icon: const Icon(Icons.key_rounded, size: 16),
                        label: const Text('Enter password'),
                      ),
                    FilledButton.icon(
                      onPressed: _check,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Why a connect step failed: the plain-words title and hint, with the
/// raw message under them to copy.
class _ConnectError extends StatelessWidget {
  const _ConnectError(this.error);

  final KubeError error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: AppColors.dangerTint,
      borderRadius: BorderRadius.circular(8),
      border: Border(left: BorderSide(color: AppColors.danger, width: 3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          error.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(error.hint, style: portixMuted(12)),
        if (error.detail.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(
            error.detail,
            maxLines: 6,
            style: _mono.copyWith(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ],
    ),
  );
}

/// The [kubeConnectSteps] as an [EasyStepper], styled like SFTP's connect
/// steps: [found] steps done, the next one running, or [failed] in red.
class _ConnectStepper extends StatelessWidget {
  const _ConnectStepper({
    required this.found,
    required this.failed,
    this.waitingForPassword = false,
  });

  final int found;
  final int? failed;

  /// The first step waits on a password the user has to type.
  final bool waitingForPassword;

  static const _icons = [
    Icons.dns_outlined,
    Icons.terminal_rounded,
    Icons.view_in_ar_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final failed = this.failed;
    final finishIcon = Icon(
      Icons.check_rounded,
      size: 16,
      color: AppColors.accent,
    );
    return EasyStepper(
      activeStep: failed ?? found,
      reachedSteps: {for (var i = 0; i <= found; i++) i},
      direction: Axis.horizontal,
      enableStepTapping: false,
      disableScroll: true,
      showTitle: true,
      showLoadingAnimation:
          failed == null &&
          !waitingForPassword &&
          found < kubeConnectSteps.length,
      stepRadius: 24,
      internalPadding: 12,
      borderThickness: 0,
      showStepBorder: false,
      activeStepBackgroundColor: AppColors.surfaceDark,
      finishedStepBackgroundColor: Colors.transparent,
      unreachedStepBackgroundColor: Colors.transparent,
      unreachedStepBorderColor: AppColors.border,
      activeStepBorderColor: failed == null
          ? AppColors.accent
          : AppColors.danger,
      finishedStepBorderColor: AppColors.accent,
      finishedStepIconColor: AppColors.accent,
      unreachedStepIconColor: AppColors.muted,
      activeStepIconColor: failed == null ? AppColors.accent : AppColors.danger,
      unreachedStepTextColor: AppColors.muted,
      activeStepTextColor: failed == null ? AppColors.accent : AppColors.danger,
      finishedStepTextColor: AppColors.accent,
      lineStyle: LineStyle(
        lineLength: 56,
        lineThickness: 1,
        defaultLineColor: AppColors.border,
        activeLineColor: AppColors.accent,
        finishedLineColor: AppColors.accent,
        unreachedLineColor: AppColors.border,
        lineType: LineType.normal,
      ),
      maxTitleLines: 1,
      steps: [
        for (final (i, step) in kubeConnectSteps.indexed)
          EasyStep(
            title: step.label,
            icon: Icon(
              i == failed
                  ? Icons.close_rounded
                  : i == 0 && waitingForPassword
                  ? Icons.key_rounded
                  : _icons[i],
              size: 16,
            ),
            finishIcon: finishIcon,
          ),
      ],
    );
  }
}

/// The password for [name], typed into the connect page and saved in the
/// keychain, as SFTP asks for an unsaved one.
class _PasswordForm extends StatelessWidget {
  const _PasswordForm({
    required this.name,
    required this.controller,
    required this.saving,
    required this.onSubmit,
    required this.onCancel,
  });

  final String name;
  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Password for $name', style: portixTitle(13)),
      const SizedBox(height: 2),
      Text(
        'No saved password on this device. It is kept in the system '
        'keychain for the next connect.',
        style: portixMuted(12),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        enabled: !saving,
        style: appFieldTextStyle(),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Password',
          prefixIcon: Icon(Icons.key_rounded, size: 16),
        ),
        onSubmitted: (_) => onSubmit(),
      ),
      const SizedBox(height: 10),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: saving ? null : onCancel,
            child: const Text('Choose another server'),
          ),
          FilledButton(
            onPressed: saving ? null : onSubmit,
            child: Text(saving ? 'Saving…' : 'Connect'),
          ),
        ],
      ),
    ],
  );
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

/// Confirms an action on several rows, listing them under their
/// namespaces with their current health; pops true to go ahead.
class _BulkConfirmDialog extends StatelessWidget {
  const _BulkConfirmDialog({
    required this.title,
    required this.message,
    required this.action,
    required this.icon,
    required this.items,
    required this.health,
    required this.danger,
  });

  final String title;
  final String message;
  final String action;
  final IconData icon;
  final List<Json> items;
  final PodHealth Function(Json item)? health;
  final bool danger;

  Widget _row(Json item) {
    final health = this.health;
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: health == null ? null : _PodDot(health(item)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              nameOf(item),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _namespace(String name, int count) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Row(
      children: [
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('$count', style: portixMuted(12)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tone = danger ? AppColors.danger : AppColors.accent;
    return Dialog(
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 19, color: tone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: portixTitle(15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: danger
                              ? TextStyle(fontSize: 12, color: AppColors.danger)
                              : portixMuted(12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxHeight: 264),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  children: [
                    for (final MapEntry(key: ns, value: group)
                        in groupByNamespace(items).entries) ...[
                      if (ns.isNotEmpty) _namespace(ns, group.length),
                      ...group.map(_row),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.text,
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: danger
                        ? FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                          )
                        : null,
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('$action ${items.length}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

enum _Common { form, yaml, describe, delete }

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

  /// Namespace groups folded shut while all namespaces are listed.
  final _foldedNamespaces = <String>{};

  /// Rows ticked for a bulk action, by [_pickKey]: they stay ticked through
  /// the 10 s refresh.
  final _picked = <String>{};
  Timer? _timer;

  /// The details opened, each as clicked (a workload, then one of its
  /// pods); the last is shown, with its latest read.
  final _trail = <(KubeKind, Json)>[];
  KubeDetail? _detailData;
  (KubeKind, Json)? get _detail => _trail.lastOrNull;

  KubeKind get _kind => widget.kind;

  String _pickKey(Json item) => '${namespaceOf(item) ?? ''}/${nameOf(item)}';

  List<Json> get _pickedItems => [
    for (final item in _items)
      if (_picked.contains(_pickKey(item))) item,
  ];
  String? get _namespace => _kind.namespaced ? kube.namespace : null;
  Object get _key => (
    kube.profileId,
    _kind.namespaced ? (kube.picked.toList()..sort()).join(',') : null,
    kube.generation,
  );

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
      // Another server or namespace: back to the list.
      _trail.clear();
      _detailData = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loadedFor != _key) unawaited(_load());
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_loading && _error == null) unawaited(_load(quiet: true));
    });
  }

  Future<void> _load({bool quiet = false}) async {
    if (_detail != null) return _loadDetail(quiet: quiet);
    final key = _key;
    if (!quiet && _loadedFor != key) setState(() => _items = const []);
    final output = await _run(listCommand(_kind, _namespace), quiet: quiet);
    if (output == null || !mounted || _key != key) return;
    try {
      // kubectl takes one -n, so several namespaces are listed with -A
      // and narrowed here.
      final several = _kind.namespaced && kube.picked.length > 1;
      final items = [
        for (final item in parseItems(output))
          if (!several || kube.picked.contains(namespaceOf(item))) item,
      ];
      setState(() {
        _items = items;
        _loadedFor = key;
        _picked.retainAll(items.map(_pickKey));
      });
    } on Object {
      setState(() => _error = 'Unexpected kubectl output:\n$output');
    }
  }

  Future<void> _loadDetail({bool quiet = false}) async {
    final open = _detail!;
    final output = await _run(detailCommand(open.$1, open.$2), quiet: quiet);
    if (output == null || !mounted || _detail != open) return;
    try {
      setState(() => _detailData = parseDetail(output));
    } on Object {
      setState(() => _error = 'Unexpected kubectl output:\n$output');
    }
  }

  void _openDetail(Json item, KubeKind kind) {
    setState(() {
      _trail.add((kind, item));
      _detailData = null;
    });
    unawaited(_load());
  }

  /// Back one step: to the previous detail, or to the list.
  void _closeDetail() {
    setState(() {
      _trail.removeLast();
      _detailData = null;
      _error = null;
    });
    unawaited(_load(quiet: _trail.isEmpty));
  }

  List<KubeColumn> get _columns => _kind.columns;

  /// All namespaces listed: rows go under a header per namespace.
  bool get _grouped => _kind.namespaced && kube.namespace == null;

  /// [shown] under namespace headers (a String entry), alphabetically,
  /// keeping the sort within each; folded groups keep only their header.
  List<Object> _rows(List<Json> shown) {
    if (!_grouped) return shown;
    return [
      for (final MapEntry(key: ns, value: items) in groupByNamespace(
        shown,
      ).entries) ...[ns, if (!_foldedNamespaces.contains(ns)) ...items],
    ];
  }

  List<Json> _shown(List<KubeColumn> columns) {
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final item in _items)
        if (query.isEmpty ||
            columns.any((c) => c.cell(item).toLowerCase().contains(query)) ||
            (_grouped && (namespaceOf(item) ?? '').contains(query)))
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

  /// Runs an action's [command], tells its outcome and reloads; false
  /// when it failed.
  Future<bool> _apply(String command) async {
    final output = await _run(command);
    if (output == null || !mounted) return false;
    final said = output.trim();
    _toast(said.isEmpty ? 'Done.' : said.split('\n').last);
    await _load();
    return true;
  }

  // The handlers below act on [kind] items: this page's own, or the pods
  // listed in a workload's detail.

  Future<void> _describe(Json item, KubeKind kind) async {
    final output = await _run(describeCommand(kind, item));
    if (output == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _TextDialog(title: '${kind.label} · ${nameOf(item)}', text: output),
    );
  }

  Future<void> _editYaml(Json item, KubeKind kind) async {
    final yaml = await _run(yamlCommand(kind, item));
    if (yaml == null || !mounted) return;
    await _openYaml('Edit ${nameOf(item)}', yaml);
  }

  /// The form works on a fresh read: the row may be up to 10 s old, and
  /// the save carries this read's resourceVersion.
  Future<void> _editForm(Json item, KubeKind kind) async {
    final output = await _run(itemCommand(kind, item));
    if (output == null || !mounted) return;
    final fresh = jsonDecode(output) as Json;
    final said = await showDialog<String>(
      context: context,
      builder: (_) => _EditFormDialog(
        kind: kind,
        item: fresh,
        onSave: (edited) => _exec(replaceCommand(edited)),
      ),
    );
    if (said == null || !mounted) return;
    _toast(said.trim().isEmpty ? 'Saved.' : said.trim());
    await _load();
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

  Future<bool> _delete(Json item, KubeKind kind) async {
    final ns = namespaceOf(item);
    return await _confirm(
          context,
          title: 'Delete ${nameOf(item)}?',
          message:
              'Deletes this ${kind.label} entry${ns == null ? '' : ' in $ns'}. '
              'This cannot be undone.',
          action: 'Delete',
        ) &&
        await _apply(deleteCommand(kind, item));
  }

  /// Asks about the ticked rows, then runs [command] on each in turn:
  /// what worked is unticked, what failed stays ticked to try again.
  Future<void> _applyPicked({
    required String action,
    required String message,
    required IconData icon,
    required String Function(Json) command,
    bool danger = false,
  }) async {
    final items = _pickedItems;
    final what = items.length == 1
        ? nameOf(items.single)
        : '${items.length} ${_kind.label}';
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => _BulkConfirmDialog(
        title: '$action $what?',
        message: message,
        action: action,
        icon: icon,
        items: items,
        health: _kind.health,
        danger: danger,
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final failed = <String>[];
    for (final item in items) {
      final (_, error) = await _exec(command(item));
      if (!mounted) return;
      if (error == null) {
        setState(() => _picked.remove(_pickKey(item)));
      } else {
        failed.add('${nameOf(item)}: $error');
      }
    }
    setState(() => _loading = false);
    await _load(quiet: true);
    if (!mounted) return;
    if (failed.isEmpty) {
      _toast('$action: ${items.length} done.');
    } else {
      // After the reload, which clears the banner.
      setState(() => _error = failed.join('\n'));
    }
  }

  Future<void> _common(_Common common, Json item, KubeKind kind) =>
      switch (common) {
        _Common.form => _editForm(item, kind),
        _Common.yaml => _editYaml(item, kind),
        _Common.describe => _describe(item, kind),
        _Common.delete => _delete(item, kind),
      };

  Future<void> _action(KubeAction action, Json item, KubeKind kind) async {
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
        final profile = _profile();
        if (!mounted || profile == null) return;
        await showDialog<void>(
          context: context,
          // Esc and stray clicks belong to the shell (vim, less…).
          barrierDismissible: false,
          builder: (_) => _PodShellDialog(
            profile: profile,
            command: shellCommand(namespaceOf(item)!, name, container),
            title: [name, ?container].join(' · '),
          ),
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
          await _apply(scaleCommand(kind, item, replicas));
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
          await _apply(actionCommand(action, kind, item)!);
        }
      default:
        await _apply(actionCommand(action, kind, item)!);
    }
  }

  Widget _buildDetail((KubeKind, Json) opened) {
    final (kind, _) = opened;
    final data = _detailData;
    final item = data?.item ?? opened.$2;
    final back = _trail.length > 1
        ? nameOf(_trail[_trail.length - 2].$2)
        : _kind.label;
    return _ClusterFrame(
      toolbar: [
        TextButton.icon(
          onPressed: _closeDetail,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: Text(back),
        ),
        Text(' / ', style: portixMuted(13)),
        Expanded(
          child: Text(
            nameOf(item),
            overflow: TextOverflow.ellipsis,
            style: portixTitle(14),
          ),
        ),
      ],
      loading: _loading,
      error: _error,
      onRefresh: _load,
      onDismissError: () => setState(() => _error = null),
      child: data == null
          ? _Empty(
              Icons.account_tree_outlined,
              _loading ? 'Loading ${nameOf(item)}…' : 'No data yet.',
            )
          : _ResourceDetail(
              kind: kind,
              detail: data,
              enabled: !_loading,
              onScale: (replicas) => _apply(scaleCommand(kind, item, replicas)),
              onAction: (action) => _action(action, item, kind),
              onCommon: (common) async {
                if (common == _Common.delete) {
                  if (await _delete(item, kind)) _closeDetail();
                } else {
                  await _common(common, item, kind);
                }
              },
              onOpen: (kind, item) => _openDetail(item, kind),
              onRelatedAction: _action,
              onRelatedCommon: _common,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_detail case final opened?) return _buildDetail(opened);
    final columns = _columns;
    final shown = _shown(columns);
    final rows = _rows(shown);
    final visible = rows.whereType<Json>().toList();
    final picked = _pickedItems;
    final allPicked =
        visible.isNotEmpty &&
        visible.every((i) => _picked.contains(_pickKey(i)));
    final where = !_kind.namespaced || kube.picked.isEmpty
        ? ''
        : kube.namespace != null
        ? ' in ${kube.namespace}'
        : ' in ${kube.picked.length} namespaces';
    return _ClusterFrame(
      toolbar: [
        Expanded(
          child: _FilterField(
            controller: _search,
            hint: 'Filter ${_kind.label}',
          ),
        ),
        const SizedBox(width: 12),
        if (picked.isEmpty)
          Text(
            _search.text.isEmpty
                ? '${_items.length}'
                : '${shown.length} of ${_items.length}',
            style: portixMuted(12),
          ),
        if (picked.isNotEmpty) ...[
          Text('${picked.length} selected', style: portixTitle(12.5)),
          const SizedBox(width: 8),
          if (picked.every(
            (i) => _kind.actions(i).contains(KubeAction.restart),
          )) ...[
            SizedBox(
              height: _controlHeight,
              child: OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _applyPicked(
                        action: KubeAction.restart.label,
                        message: 'Restarts their pods with a rolling update.',
                        icon: Icons.restart_alt_rounded,
                        command: (item) =>
                            actionCommand(KubeAction.restart, _kind, item)!,
                      ),
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: Text(KubeAction.restart.label),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            height: _controlHeight,
            child: OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _applyPicked(
                      action: 'Delete',
                      message: 'This cannot be undone.',
                      icon: Icons.delete_outline_rounded,
                      danger: true,
                      command: (item) => deleteCommand(_kind, item),
                    ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Delete'),
            ),
          ),
        ],
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
                  picked: allPicked
                      ? true
                      : visible.any((i) => _picked.contains(_pickKey(i)))
                      ? null
                      : false,
                  onPickAll: () => setState(
                    () => allPicked
                        ? _picked.removeAll(visible.map(_pickKey))
                        : _picked.addAll(visible.map(_pickKey)),
                  ),
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
                          itemCount: rows.length,
                          itemBuilder: (_, i) => switch (rows[i]) {
                            final String ns => _NamespaceHeader(
                              namespace: ns,
                              count: shown
                                  .where((s) => (namespaceOf(s) ?? '') == ns)
                                  .length,
                              folded: _foldedNamespaces.contains(ns),
                              onTap: () => setState(
                                () => _foldedNamespaces.contains(ns)
                                    ? _foldedNamespaces.remove(ns)
                                    : _foldedNamespaces.add(ns),
                              ),
                            ),
                            final row as Json => _TableRow(
                              item: row,
                              columns: columns,
                              health: _kind.health?.call(row),
                              odd: i.isOdd,
                              enabled: !_loading,
                              picked: _picked.contains(_pickKey(row)),
                              onPicked: () => setState(
                                () => _picked.contains(_pickKey(row))
                                    ? _picked.remove(_pickKey(row))
                                    : _picked.add(_pickKey(row)),
                              ),
                              actions: _kind.actions(row),
                              hasForm: kubeFormSpec(_kind) != null,
                              onDescribe: () => _openDetail(row, _kind),
                              onAction: (action) => _action(action, row, _kind),
                              onCommon: (common) => _common(common, row, _kind),
                            ),
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// A namespace's group in a list of all namespaces; a tap folds it.
class _NamespaceHeader extends StatelessWidget {
  const _NamespaceHeader({
    required this.namespace,
    required this.count,
    required this.folded,
    required this.onTap,
  });

  final String namespace;
  final int count;
  final bool folded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: !folded,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Icon(
              folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
              size: 18,
              color: AppColors.muted,
            ),
            const SizedBox(width: 6),
            Text('Namespace: ', style: portixMuted(12.5)),
            Text(
              namespace,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 8),
            Text('$count', style: portixMuted(12)),
          ],
        ),
      ),
    ),
  );
}

/// An item at a glance, Rancher-style: title and state, its facts beside
/// its labels and annotations, cards for its pods and health, then tabs
/// for pods, what its kind has (containers, ports, data…), conditions and
/// events.
class _ResourceDetail extends StatefulWidget {
  const _ResourceDetail({
    required this.kind,
    required this.detail,
    required this.enabled,
    required this.onScale,
    required this.onAction,
    required this.onCommon,
    required this.onRelatedAction,
    required this.onRelatedCommon,
    required this.onOpen,
  });

  final KubeKind kind;
  final KubeDetail detail;
  final bool enabled;
  final ValueChanged<int> onScale;
  final ValueChanged<KubeAction> onAction;
  final ValueChanged<_Common> onCommon;

  /// For the pods and services listed in the detail.
  final void Function(KubeAction action, Json item, KubeKind kind)
  onRelatedAction;
  final void Function(_Common common, Json item, KubeKind kind) onRelatedCommon;
  final void Function(KubeKind kind, Json item) onOpen;

  @override
  State<_ResourceDetail> createState() => _ResourceDetailState();
}

class _ResourceDetailState extends State<_ResourceDetail> {
  /// The open tab, by title, so a refresh keeps it.
  String? _tab;

  KubeKind get kind => widget.kind;
  KubeDetail get detail => widget.detail;
  bool get enabled => widget.enabled;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final actions = kind.actions(item);
    final replicas = (field(item, 'spec.replicas') as num?)?.toInt();
    final conditions = conditionsOf(item);
    final sections = detailSections(kind, item);
    Map<String, String> meta(String title) => {
      for (final s in sections)
        if (s.title == title)
          for (final (k, v) in s.rows) k: v,
    };
    final tabs = <(String, Widget Function())>[
      if (detailHasPods(kind))
        ('Pods (${detail.pods.length})', () => _podsTab(replicas)),
      if (kind.ownsPods)
        (
          'Services (${detail.services.length})',
          () => detail.services.isEmpty
              ? Text('No service selects its pods.', style: portixMuted(13))
              : _relatedTable(kubeKinds['services']!, detail.services),
        ),
      for (final s in sections)
        if (s.title != 'Labels' && s.title != 'Annotations')
          (s.title, () => _FactTable(s)),
      if (conditions.isNotEmpty)
        ('Conditions (${conditions.length})', () => _conditionsTab(conditions)),
      ('Recent Events (${detail.events.length})', _eventsTab),
    ];
    // Tabs keep their place by name, whatever their count says now.
    String base(String title) => title.replaceFirst(RegExp(r' \(\d+\)$'), '');
    final open =
        tabs.where((t) => base(t.$1) == _tab).firstOrNull ?? tabs.first;
    final facts = <(String, String)>[
      if (namespaceOf(item) case final ns?) ('Namespace', ns),
      ('Age', formatAge('${field(item, 'metadata.creationTimestamp')}')),
      for (final column in kind.columns.skip(1))
        if (column.header != 'Age' && column.cell(item).isNotEmpty)
          (column.header, column.cell(item)),
      if (workloadPorts(kind, item) case final ports when ports.isNotEmpty)
        ('Ports', ports),
      if ({
            ...publicEndpoints(item),
            for (final s in detail.services) ...serviceEndpoints(s),
          }.join(', ')
          case final endpoints when endpoints.isNotEmpty)
        ('Endpoints', endpoints),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        _title(item, actions),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final columns = [
              _FactList(facts),
              _ChipList('Labels', meta('Labels')),
              _ChipList('Annotations', meta('Annotations')),
            ];
            if (box.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in columns)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: c,
                    ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, c) in columns.indexed) ...[
                  if (i > 0) const SizedBox(width: 24),
                  Expanded(child: c),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (detailHasPods(kind)) ...[
                Expanded(child: _podsCard(replicas, actions)),
                const SizedBox(width: 16),
              ],
              Expanded(child: _insightsCard(conditions)),
              if (detailHasPods(kind))
                const Spacer()
              else
                const Spacer(flex: 2),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (title, _) in tabs)
                  _DetailTab(
                    label: title,
                    selected: title == open.$1,
                    onTap: () => setState(() => _tab = base(title)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        open.$2(),
      ],
    );
  }

  Widget _title(Json item, List<KubeAction> actions) {
    final health = kind.health?.call(item);
    final state = switch (kind.type) {
      'pods' => podStatus(item),
      'nodes' => kind.columns[1].cell(item),
      _ => switch (health) {
        PodHealth.pending => 'Updating',
        PodHealth.failing => 'Error',
        PodHealth.done => 'Completed',
        _ => 'Active',
      },
    };
    return Row(
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${_singular(kind.label)}: ',
                  style: TextStyle(color: AppColors.accent),
                ),
                TextSpan(text: nameOf(item)),
              ],
            ),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
        const SizedBox(width: 12),
        _StateBadge(state, health ?? PodHealth.ok),
        const Spacer(),
        FilledButton.icon(
          onPressed: enabled ? () => widget.onCommon(_Common.yaml) : null,
          icon: const Icon(Icons.description_outlined, size: 16),
          label: const Text('Show Configuration'),
        ),
        const SizedBox(width: 6),
        PopupMenuButton<Object>(
          enabled: enabled,
          tooltip: 'More actions',
          icon: Icon(Icons.more_vert_rounded, color: AppColors.muted),
          onSelected: (choice) => switch (choice) {
            final KubeAction action => widget.onAction(action),
            final _Common common => widget.onCommon(common),
            _ => null,
          },
          itemBuilder: (_) => [
            if (kubeFormSpec(kind) != null)
              _TableRow._menuItem(
                _Common.form,
                'Edit config',
                Icons.tune_rounded,
              ),
            for (final action in actions)
              if (action != KubeAction.scale)
                _TableRow._menuItem(
                  action,
                  action.label,
                  _TableRow._actionIcon(action),
                ),
            _TableRow._menuItem(
              _Common.describe,
              'Describe',
              Icons.info_outline_rounded,
            ),
            const PopupMenuDivider(),
            _TableRow._menuItem(
              _Common.delete,
              'Delete',
              Icons.delete_outline_rounded,
              danger: true,
            ),
          ],
        ),
      ],
    );
  }

  /// Pods by state as one bar, with a line per state, as Rancher's card.
  Widget _podsCard(int? replicas, List<KubeAction> actions) {
    final states = <String, (PodHealth, int)>{};
    for (final pod in detail.pods) {
      final (health, n) = states[podStatus(pod)] ?? (podHealthOf(pod), 0);
      states[podStatus(pod)] = (health, n + 1);
    }
    final total = detail.pods.length;
    return _DetailCard(
      title: 'Pods',
      trailing: replicas != null && actions.contains(KubeAction.scale)
          ? _ReplicaStepper(
              replicas: replicas,
              enabled: enabled,
              onScale: widget.onScale,
            )
          : null,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: total == 0
                ? ColoredBox(color: AppColors.border)
                : Row(
                    children: [
                      for (final (health, n) in states.values)
                        Expanded(
                          flex: n,
                          child: ColoredBox(color: _healthColor(health)),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        if (total == 0)
          Text(
            replicas == 0 ? 'Scaled to 0: no pods run.' : 'No pods.',
            style: portixMuted(13),
          ),
        for (final MapEntry(key: state, value: (health, n)) in states.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(width: 14, height: 3, color: _healthColor(health)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state,
                    style: TextStyle(fontSize: 13, color: AppColors.text),
                  ),
                ),
                Text(
                  '$n',
                  style: TextStyle(fontSize: 13, color: AppColors.text),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '${(n * 100 / total).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: portixMuted(13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _insightsCard(
    List<({String type, bool ok, String reason, String message})> conditions,
  ) {
    final ok = [
      for (final c in conditions)
        if (c.ok) c.type.toLowerCase(),
    ];
    final failing = conditions.where((c) => !c.ok).length;
    Widget line(
      String label,
      String value, {
      VoidCallback? onTap,
      Color? dot,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          InkWell(
            onTap: onTap,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text,
                decoration: onTap == null ? null : TextDecoration.underline,
              ),
            ),
          ),
          const Spacer(),
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
    return _DetailCard(
      title: 'Insights',
      children: [
        line(
          'Conditions',
          conditions.isEmpty
              ? '—'
              : [
                  if (ok.isNotEmpty) ok.join(' + '),
                  if (failing > 0) '$failing not met',
                ].join(', '),
          dot: conditions.isEmpty
              ? null
              : failing > 0
              ? AppColors.amber
              : AppColors.green,
          onTap: conditions.isEmpty
              ? null
              : () => setState(() => _tab = 'Conditions'),
        ),
        line(
          'Events',
          '${detail.events.length}',
          onTap: () => setState(() => _tab = 'Recent Events'),
        ),
        if (detail.events.where((e) => e['type'] == 'Warning').length
            case final warnings when warnings > 0)
          line('Warnings', '$warnings', dot: AppColors.amber),
      ],
    );
  }

  Widget _podsTab(int? replicas) {
    if (detail.pods.isEmpty) {
      return Text(
        replicas == 0
            ? 'Scaled to 0: no pods run.'
            : kind.type == 'nodes'
            ? 'No pods run on this node.'
            : 'No pods match its selector yet.',
        style: portixMuted(13),
      );
    }
    return _relatedTable(kubeKinds['pods']!, detail.pods);
  }

  /// Pods or services this item relates to, each opening its own detail.
  Widget _relatedTable(KubeKind related, List<Json> items) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        _TableHeader(
          columns: related.columns,
          dot: related.health != null,
          sortColumn: null,
          ascending: true,
          onSort: (_) {},
        ),
        for (final (i, item) in items.indexed)
          _TableRow(
            item: item,
            columns: related.columns,
            health: related.health?.call(item),
            odd: i.isOdd,
            enabled: enabled,
            actions: related.actions(item),
            onDescribe: () => widget.onOpen(related, item),
            onAction: (action) => widget.onRelatedAction(action, item, related),
            onCommon: (common) => widget.onRelatedCommon(common, item, related),
          ),
      ],
    ),
  );

  Widget _conditionsTab(
    List<({String type, bool ok, String reason, String message})> conditions,
  ) => Column(
    children: [
      for (final c in conditions)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                c.ok
                    ? Icons.check_circle_outline_rounded
                    : Icons.cancel_outlined,
                size: 16,
                color: c.ok ? AppColors.green : AppColors.danger,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: Text(
                  c.type,
                  style: TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ),
              Expanded(
                child: SelectableText(
                  [c.reason, c.message].where((t) => t.isNotEmpty).join(' · '),
                  style: portixMuted(12.5),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _eventsTab() => detail.events.isEmpty
      ? Text(
          'No recent events (Kubernetes keeps them for about an hour).',
          style: portixMuted(13),
        )
      : Column(
          children: [for (final e in detail.events.take(30)) _EventLine(e)],
        );
}

/// "Deployments" → "Deployment", "Ingresses" → "Ingress",
/// "Network Policies" → "Network Policy".
String _singular(String label) => label.endsWith('sses')
    ? label.substring(0, label.length - 2)
    : label.endsWith('ies')
    ? '${label.substring(0, label.length - 3)}y'
    : label.replaceFirst(RegExp(r's$'), '');

class _StateBadge extends StatelessWidget {
  const _StateBadge(this.state, this.health);

  final String state;
  final PodHealth health;

  @override
  Widget build(BuildContext context) {
    final color = _healthColor(health);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// Key/value lines beside the labels, e.g. "Namespace  mgate-sit".
class _FactList extends StatelessWidget {
  const _FactList(this.facts);

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (key, value) in facts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: Text(key, style: portixMuted(13))),
              Expanded(
                child: Tooltip(
                  message: value,
                  waitDuration: const Duration(milliseconds: 600),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.text),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Labels or annotations as `key: value` chips under a counted title.
class _ChipList extends StatelessWidget {
  const _ChipList(this.title, this.entries);

  final String title;
  final Map<String, String> entries;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(title, style: portixMuted(13)),
          const SizedBox(width: 12),
          Text(
            '${entries.length}',
            style: TextStyle(fontSize: 13, color: AppColors.text),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final MapEntry(:key, :value) in entries.entries)
            Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.border),
              ),
              child: Tooltip(
                message: value.isEmpty ? key : '$key: $value',
                waitDuration: const Duration(milliseconds: 600),
                child: Text(
                  value.isEmpty ? key : '$key: $value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 34,
          child: Row(
            children: [
              Expanded(child: Text(title, style: portixTitle(15))),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

class _DetailTab extends StatelessWidget {
  const _DetailTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? AppColors.accent : AppColors.text,
        ),
      ),
    ),
  );
}

/// A detail section as key/value rows; a Secret's values stay masked
/// until revealed.
class _FactTable extends StatefulWidget {
  const _FactTable(this.facts);

  final KubeFacts facts;

  @override
  State<_FactTable> createState() => _FactTableState();
}

class _FactTableState extends State<_FactTable> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final masked = widget.facts.secret && !_revealed;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (key, value)) in widget.facts.rows.indexed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 240,
                    child: SelectableText(key, style: portixMuted(12.5)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      masked ? '••••••••' : value,
                      maxLines: 12,
                      style: _mono.copyWith(
                        fontSize: 12.5,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.facts.secret)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _revealed = !_revealed),
                icon: Icon(
                  masked
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 15,
                ),
                label: Text(masked ? 'Reveal values' : 'Hide values'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Replicas as − n +; each press scales right away, as in Rancher.
class _ReplicaStepper extends StatelessWidget {
  const _ReplicaStepper({
    required this.replicas,
    required this.enabled,
    required this.onScale,
  });

  final int replicas;
  final bool enabled;
  final ValueChanged<int> onScale;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.accent.withValues(alpha: .6)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text('Replicas', style: portixMuted(12)),
        ),
        IconButton(
          tooltip: 'Scale down',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          onPressed: enabled && replicas > 0
              ? () => onScale(replicas - 1)
              : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Text(
          '$replicas',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        ),
        IconButton(
          tooltip: 'Scale up',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onScale(replicas + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
  );
}

/// A pod shell in a modal of its own. `kubectl exec` runs as the SSH
/// command (no login shell reads it), so it never lands in the server's
/// shell history, and it stays out of the terminal tabs.
class _PodShellDialog extends StatefulWidget {
  const _PodShellDialog({
    required this.profile,
    required this.command,
    required this.title,
  });

  final manager_profile.SshProfile profile;
  final String command;
  final String title;

  @override
  State<_PodShellDialog> createState() => _PodShellDialogState();
}

enum _ShellState { connecting, open, ended, failed }

class _PodShellDialogState extends State<_PodShellDialog> {
  final _manager = sl<ConnectionManager>();
  late final _terminal = Terminal(
    maxLines: 5000,
    onOutput: (data) {
      if (_sessionId case final id?) {
        unawaited(_manager.sendTerminalInput(id, data));
      }
    },
    onResize: (cols, rows, _, _) {
      _size = (cols, rows);
      if (_sessionId case final id?) {
        unawaited(_manager.resizeTerminal(id, cols, rows));
      }
    },
  );
  final _subscriptions = <StreamSubscription<Object>>[];
  String? _sessionId;
  (int, int)? _size;
  _ShellState _state = _ShellState.connecting;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _manager.terminalOutputStream.listen((event) {
        if (event.sessionId == _sessionId) _terminal.write(event.data);
      }),
      _manager.commandStatusStream.listen((event) {
        if (event.sessionId != _sessionId || !mounted) return;
        setState(() {
          _state = switch (event.status) {
            session_models.ConnectionStatus.connected => _ShellState.open,
            session_models.ConnectionStatus.connecting => _state,
            _ =>
              _state == _ShellState.failed
                  ? _ShellState.failed
                  : _ShellState.ended,
          };
        });
      }),
      _manager.errorEventStream.listen((event) {
        if (event.sessionId != _sessionId || !mounted) return;
        setState(() {
          _state = _ShellState.failed;
          _error = event.message;
        });
      }),
    ]);
    unawaited(_open());
  }

  Future<void> _open() async {
    setState(() {
      _state = _ShellState.connecting;
      _error = null;
    });
    final result = await _manager.openCommandSession(
      widget.profile,
      widget.command,
    );
    if (!mounted) {
      result.fold((_) {}, (id) => unawaited(_manager.disconnect(id)));
      return;
    }
    result.fold(
      (failure) => setState(() {
        _state = _ShellState.failed;
        _error = '$failure';
      }),
      (id) {
        _sessionId = id;
        if (_size case (final cols, final rows)) {
          unawaited(_manager.resizeTerminal(id, cols, rows));
        }
      },
    );
  }

  /// Answers a host-key or OTP prompt if that is what failed, then opens
  /// a fresh shell.
  Future<void> _retry() async {
    final hostKey = await resolveRefusedHostKey(
      context,
      _manager,
      widget.profile,
    );
    if (hostKey == false || !mounted) return;
    if (hostKey == null) {
      await resolveAuthPrompts(context, _manager, widget.profile);
      if (!mounted) return;
    }
    _close();
    _terminal.write('\r\n');
    await _open();
  }

  void _close() {
    if (_sessionId case final id?) unawaited(_manager.disconnect(id));
    _sessionId = null;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktop =
        !kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
    final (statusText, statusColor) = switch (_state) {
      _ShellState.connecting => ('Connecting…', AppColors.muted),
      _ShellState.open => ('Connected', AppColors.green),
      _ShellState.ended => ('Shell ended', AppColors.muted),
      _ShellState.failed => ('Failed', AppColors.danger),
    };
    return _BigDialog(
      title: 'Shell · ${widget.title}',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            statusText,
            style: portixMuted(12).copyWith(color: statusColor),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: portixBuiltinTheme.background,
              child: TerminalView(
                _terminal,
                autofocus: true,
                hardwareKeyboardOnly: desktop,
                padding: const EdgeInsets.all(12),
                readOnly: _state != _ShellState.open,
                textStyle: TerminalStyle(
                  fontSize: 13,
                  height: 1.28,
                  fontFamily: _mono.fontFamily!,
                  fontFamilyFallback: _mono.fontFamilyFallback!,
                ),
                theme: portixBuiltinTheme,
                cursorType: TerminalCursorType.block,
              ),
            ),
          ),
          if (_state == _ShellState.failed || _state == _ShellState.ended)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _state == _ShellState.ended
                          ? 'The shell exited.'
                          : describeKubeError(_error ?? '').title,
                      style: portixMuted(12.5),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _state == _ShellState.ended ? _open : _retry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      _state == _ShellState.ended ? 'Reconnect' : 'Retry',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const _pickWidth = 26.0;
const _dotWidth = 26.0;
const _menuWidth = 40.0;

/// A table's tick box: small and quiet so it doesn't outweigh the rows.
/// A null [value] is the header's "some ticked".
class _TickBox extends StatelessWidget {
  const _TickBox({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final bool? value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _pickWidth,
    child: Transform.scale(
      scale: .78,
      child: Checkbox(
        value: value,
        tristate: true,
        semanticLabel: label,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BorderSide.none
              : BorderSide(
                  width: 1.5,
                  color: states.contains(WidgetState.hovered)
                      ? AppColors.muted
                      : AppColors.inputBorder,
                ),
        ),
        onChanged: (_) => onTap(),
      ),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.columns,
    required this.dot,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
    this.picked = false,
    this.onPickAll,
  });

  final List<KubeColumn> columns;
  final bool dot;

  /// All rows ticked, some (null) or none; no [onPickAll], no tick column.
  final bool? picked;
  final VoidCallback? onPickAll;
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
        if (onPickAll case final pickAll?)
          _TickBox(value: picked, label: 'Select all', onTap: pickAll),
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
    this.picked = false,
    this.onPicked,
    this.hasForm = false,
  });

  final Json item;
  final List<KubeColumn> columns;
  final PodHealth? health;
  final bool odd;
  final bool enabled;
  final bool picked;

  /// Null leaves the row without a tick box.
  final VoidCallback? onPicked;

  /// Offers Edit config beside Edit YAML.
  final bool hasForm;
  final List<KubeAction> actions;
  final VoidCallback onDescribe;
  final ValueChanged<KubeAction> onAction;
  final ValueChanged<_Common> onCommon;

  @override
  Widget build(BuildContext context) {
    final health = this.health;
    return Material(
      color: picked
          ? AppColors.selectedSoft
          : odd
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
              if (onPicked case final pick?)
                _TickBox(
                  value: picked,
                  label: 'Select ${nameOf(item)}',
                  onTap: pick,
                ),
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
                    if (hasForm)
                      _menuItem(
                        _Common.form,
                        'Edit config',
                        Icons.tune_rounded,
                      ),
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

  static PopupMenuItem<Object> _menuItem(
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
    this.maxWidth = 1100,
  });

  final String title;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (size.width * .8).clamp(360.0, maxWidth),
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
        _SaveFooter(
          error: _error,
          saving: _applying,
          label: 'Apply',
          onSave: _save,
          onDismiss: () => setState(() => _error = null),
        ),
      ],
    ),
  );
}

/// A dialog's foot: what went wrong, then Cancel and the save button.
class _SaveFooter extends StatelessWidget {
  const _SaveFooter({
    required this.error,
    required this.saving,
    required this.label,
    required this.onSave,
    required this.onDismiss,
    this.canSave = true,
  });

  final String? error;
  final bool saving;
  final String label;
  final VoidCallback onSave;
  final VoidCallback onDismiss;
  final bool canSave;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error case final error?)
        _ErrorBanner(
          error: describeKubeError(error),
          retrying: saving,
          onRetry: onSave,
          onDismiss: onDismiss,
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
              onPressed: saving || !canSave ? null : onSave,
              icon: saving
                  ? SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onAccent,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 16),
              label: Text(label),
            ),
          ],
        ),
      ),
    ],
  );
}

/// An env var's row in the form; [source] marks one that can only be seen.
class _EnvRow {
  _EnvRow(String name, String value, this.source)
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value);

  final TextEditingController name;
  final TextEditingController value;
  final String? source;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

/// One container's fields in the form.
class _ContainerFields {
  _ContainerFields(KubeContainerEdit edit)
    : name = edit.name,
      image = TextEditingController(text: edit.image),
      cpuRequest = TextEditingController(text: edit.cpuRequest),
      memoryRequest = TextEditingController(text: edit.memoryRequest),
      cpuLimit = TextEditingController(text: edit.cpuLimit),
      memoryLimit = TextEditingController(text: edit.memoryLimit),
      env = [for (final e in edit.env) _EnvRow(e.name, e.value, e.source)];

  final String name;
  final TextEditingController image;
  final TextEditingController cpuRequest;
  final TextEditingController memoryRequest;
  final TextEditingController cpuLimit;
  final TextEditingController memoryLimit;
  final List<_EnvRow> env;

  /// Rows left empty are not variables.
  List<_EnvRow> get _filled => [
    for (final row in env)
      if (row.name.text.trim().isNotEmpty || row.value.text.isNotEmpty) row,
  ];

  bool get valid =>
      image.text.trim().isNotEmpty &&
      _filled.every((row) => row.name.text.trim().isNotEmpty);

  KubeContainerEdit get edit => (
    name: name,
    image: image.text.trim(),
    env: [
      for (final row in _filled)
        (name: row.name.text.trim(), value: row.value.text, source: row.source),
    ],
    cpuRequest: cpuRequest.text.trim(),
    memoryRequest: memoryRequest.text.trim(),
    cpuLimit: cpuLimit.text.trim(),
    memoryLimit: memoryLimit.text.trim(),
  );

  void dispose() {
    image.dispose();
    cpuRequest.dispose();
    memoryRequest.dispose();
    cpuLimit.dispose();
    memoryLimit.dispose();
    for (final row in env) {
      row.dispose();
    }
  }
}

/// Edits a workload's common settings without touching YAML: replicas,
/// and each container's image, resources and env. A pod takes only images.
class _EditFormDialog extends StatefulWidget {
  const _EditFormDialog({
    required this.kind,
    required this.item,
    required this.onSave,
  });

  final KubeKind kind;
  final Json item;

  /// kubectl's output, or the error.
  final Future<(String?, String?)> Function(Json edited) onSave;

  @override
  State<_EditFormDialog> createState() => _EditFormDialogState();
}

class _EditFormDialogState extends State<_EditFormDialog> {
  late final _containers = [
    for (final edit in containerEdits(widget.kind, widget.item))
      _ContainerFields(edit),
  ];
  late final _replicas = TextEditingController(
    text: '${field(widget.item, 'spec.replicas') ?? 1}',
  );
  bool _saving = false;
  String? _error;

  KubeKind get _kind => widget.kind;
  bool get _hasReplicas => kubeFormHasReplicas(_kind);

  @override
  void dispose() {
    _replicas.dispose();
    for (final c in _containers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      (!_hasReplicas || int.tryParse(_replicas.text) != null) &&
      _containers.every((c) => c.valid);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final (output, error) = await widget.onSave(
      withFormEdits(
        _kind,
        widget.item,
        containers: [for (final c in _containers) c.edit],
        replicas: _hasReplicas ? int.parse(_replicas.text) : null,
      ),
    );
    if (!mounted) return;
    if (error == null) return Navigator.of(context).pop(output ?? '');
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  void _changed(String _) => setState(() {});

  Widget _quantity(
    TextEditingController controller,
    String label,
    String hint,
  ) => Expanded(
    child: AppTextField(
      controller: controller,
      label: label,
      hint: hint,
      onChanged: _changed,
    ),
  );

  Widget _envRow(_ContainerFields container, _EnvRow row) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: AppTextField(
            controller: row.name,
            label: '',
            hint: 'NAME',
            readOnly: row.source != null,
            onChanged: _changed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: row.source != null
              ? Text(
                  'from ${row.source}',
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(12),
                )
              : AppTextField(
                  controller: row.value,
                  label: '',
                  hint: 'value',
                  onChanged: _changed,
                ),
        ),
        IconButton(
          tooltip: 'Remove ${row.name.text}',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
          onPressed: () => setState(() {
            container.env.remove(row);
            row.dispose();
          }),
        ),
      ],
    ),
  );

  Widget _container(_ContainerFields c) => AppPanel(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.name, style: portixTitle(13.5)),
        const SizedBox(height: 12),
        AppTextField(
          controller: c.image,
          label: 'Image',
          hint: 'registry.example.com/app:1.0',
          onChanged: _changed,
        ),
        if (!kubeFormImageOnly(_kind)) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              _quantity(c.cpuRequest, 'CPU request', '100m'),
              const SizedBox(width: 8),
              _quantity(c.cpuLimit, 'CPU limit', '500m'),
              const SizedBox(width: 8),
              _quantity(c.memoryRequest, 'Memory request', '128Mi'),
              const SizedBox(width: 8),
              _quantity(c.memoryLimit, 'Memory limit', '512Mi'),
            ],
          ),
          const SizedBox(height: 14),
          Text('Environment variables', style: appFieldLabelStyle()),
          const SizedBox(height: 6),
          for (final row in c.env) _envRow(c, row),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => c.env.add(_EnvRow('', '', null))),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.text,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add variable'),
            ),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => _BigDialog(
    title: 'Edit ${nameOf(widget.item)}',
    maxWidth: 720,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            children: [
              Text(
                kubeFormImageOnly(_kind)
                    ? 'A running pod can only change its images. The container '
                          'restarts, and a pod owned by a workload goes back '
                          "to the workload's image when it is recreated."
                    : '${_kind.type == 'cronjobs' ? 'Changes apply from the next run.' : 'Image, resource and variable changes roll out new pods.'} '
                          'Other settings stay as they are; change them with '
                          'Edit YAML.',
                style: portixMuted(12),
              ),
              const SizedBox(height: 14),
              if (_hasReplicas) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 140,
                    child: AppTextField(
                      controller: _replicas,
                      label: 'Replicas',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _changed,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              ..._containers.map(_container),
            ],
          ),
        ),
        _SaveFooter(
          error: _error,
          saving: _saving,
          label: 'Save',
          canSave: _valid,
          onSave: _save,
          onDismiss: () => setState(() => _error = null),
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

const _sep = kubeSeparator;

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
                  for (final e in data.warnings) _EventLine(e),
              ],
            ),
    );
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine(this.event);

  final Json event;

  @override
  Widget build(BuildContext context) {
    final warning = field(event, 'type') == 'Warning';
    final seen = formatAge(
      (field(event, 'lastTimestamp') ??
              field(event, 'eventTime') ??
              field(event, 'metadata.creationTimestamp'))
          as String?,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              warning
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline_rounded,
              size: 15,
              color: warning ? AppColors.amber : AppColors.muted,
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
                  TextSpan(text: '  · $seen ago', style: portixMuted(11.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
