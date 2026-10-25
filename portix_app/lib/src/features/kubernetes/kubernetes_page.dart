import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart'
    as manager_profile;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'package:portix/src/features/ssh_profiles/widget/gallery/profile_card.dart'
    show ProfileOsIcon;
import 'package:portix/src/features/ssh_sessions/widget/remote/auth_prompt_dialog.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/host_key_dialog.dart';

import 'kube_logs.dart';

/// Pod logs through a saved SSH server's kubectl and kubeconfig, in tabs:
/// each tab picks its own server, namespace and pod (or all pods), a time
/// range like Kibana's (relative or absolute) and a search query.
class KubernetesPage extends StatefulWidget {
  const KubernetesPage({super.key});

  @override
  State<KubernetesPage> createState() => _KubernetesPageState();
}

class _Tab {
  _Tab(this.id);

  final int id;
  String title = 'New tab';
}

class _KubernetesPageState extends State<KubernetesPage> {
  final List<_Tab> _tabs = [_Tab(0)];
  int _nextId = 1;
  int _active = 0;

  void _add() => setState(() {
    _tabs.add(_Tab(_nextId++));
    _active = _tabs.length - 1;
  });

  void _close(int index) => setState(() {
    _tabs.removeAt(index);
    if (_tabs.isEmpty) _tabs.add(_Tab(_nextId++));
    if (_active >= _tabs.length || _active > index) {
      _active = (_active - 1).clamp(0, _tabs.length - 1);
    }
  });

  @override
  Widget build(BuildContext context) {
    // Only the visible tab of the visible page auto-refreshes.
    final pageVisible = context.select(
      (SshWorkspaceBloc bloc) =>
          bloc.state.activeView == WorkspaceView.kubernetes,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (i, tab) in _tabs.indexed)
                        _TabChip(
                          title: tab.title,
                          selected: i == _active,
                          onTap: () => setState(() => _active = i),
                          onClose: () => _close(i),
                        ),
                    ],
                  ),
                ),
              ),
              AppIconButton(
                tooltip: 'New log tab',
                icon: Icons.add_rounded,
                outlined: false,
                onPressed: _add,
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _active,
            children: [
              for (final (i, tab) in _tabs.indexed)
                _KubeLogView(
                  key: ValueKey(tab.id),
                  active: pageVisible && i == _active,
                  onTitle: (title) => setState(() => tab.title = title),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.title,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : null,
          border: Border(
            right: BorderSide(color: AppColors.border),
            top: BorderSide(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? AppColors.text : AppColors.muted,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close tab',
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

const _relativeRanges = {
  'Last 15 minutes': Duration(minutes: 15),
  'Last 1 hour': Duration(hours: 1),
  'Last 4 hours': Duration(hours: 4),
  'Last 24 hours': Duration(hours: 24),
  'Last 7 days': Duration(days: 7),
};

const _refreshIntervals = <Duration?>[
  null, // off
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 5),
];

String _intervalLabel(Duration every) =>
    every.inSeconds < 60 ? '${every.inSeconds}s' : '${every.inMinutes}m';

String _two(int n) => n.toString().padLeft(2, '0');

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatShort(DateTime time) =>
    '${_months[time.month - 1]} ${time.day}, '
    '${_two(time.hour)}:${_two(time.minute)}';

const _controlHeight = 32.0;

class _KubeLogView extends StatefulWidget {
  const _KubeLogView({required this.active, required this.onTitle, super.key});

  /// On screen; auto-refresh only runs while true.
  final bool active;
  final ValueChanged<String> onTitle;

  @override
  State<_KubeLogView> createState() => _KubeLogViewState();
}

class _KubeLogViewState extends State<_KubeLogView> {
  final _manager = sl<ConnectionManager>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Log search');
  final _scroll = ScrollController();

  /// Hide lines that don't match the search (else highlight them in place).
  bool _onlyMatches = true;

  /// The match the ↑/↓ buttons are on, by identity: it stays put while
  /// auto-refresh appends or trims lines. Null = none picked yet.
  LogLine? _current;

  /// Row the view is scrolling to; carries [_targetKey] once built.
  int? _targetIndex;
  final _targetKey = GlobalKey();

  String? _profileId;
  List<KubeNamespace> _namespaces = const [];
  List<KubePod> _pods = const [];
  String? _namespace;
  String? _pod; // null = all pods in the namespace (or [_workload]'s)

  /// Follow every pod of one controller, so rollouts and replaced pods
  /// keep streaming. Only set while [_pod] is null.
  Workload? _workload;

  /// The picked pod vanished during auto-refresh (deleted, evicted, rolled
  /// out); refresh pauses until the user switches. [_replacement] is the
  /// same workload's pod to offer, if any.
  String? _gonePod;
  KubePod? _replacement;

  /// A [_relativeRanges] key, or null for the absolute [_from]..[_to].
  String? _relative = _relativeRanges.keys.first;
  DateTime? _from;
  DateTime? _to;
  List<LogLine> _lines = const [];
  String? _error;
  bool _loading = false;

  Duration? _refreshEvery;
  Timer? _timer;
  bool _ticking = false;
  DateTime? _lastRefresh;

  /// Bumped by every full load or selection change, so a background
  /// refresh that was in flight doesn't append to the wrong lines.
  int _generation = 0;

  /// The list is scrolled to its end (following the newest lines).
  bool _atBottom = true;

  /// Lines auto-refresh added while the reader was scrolled up.
  int _newBelow = 0;

  /// Long lines the user opened past the first 2,000 characters.
  final _expanded = <LogLine>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final position = _scroll.position;
    final atBottom = position.pixels >= position.maxScrollExtent - 48;
    if (atBottom != _atBottom) {
      setState(() {
        _atBottom = atBottom;
        if (atBottom) _newBelow = 0;
      });
    }
  }

  /// Repeats whatever was last attempted: logs if a namespace is picked,
  /// else the server's namespaces.
  void _retry() {
    final profileId = _profileId;
    if (_namespace != null) {
      unawaited(_loadLogs());
    } else if (profileId != null) {
      unawaited(_selectProfile(profileId));
    }
  }

  /// Back to the newest line, and to following it.
  void _jumpToLatest() {
    setState(() {
      _current = null;
      _newBelow = 0;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void didUpdateWidget(_KubeLogView old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _syncTimer();
      if (widget.active) unawaited(_tick()); // catch up on return
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

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

  /// Runs [command] on the picked server, answering a host-key or OTP prompt
  /// once if the connection needs it. Shows the error and returns null on
  /// failure.
  Future<String?> _run(String command) async {
    final profile = _profile();
    if (profile == null) return null;
    setState(() {
      _loading = true;
      _error = null;
    });
    Future<(String?, String?)> attempt() async => (await _manager.execOnProfile(
      profile,
      command,
    )).fold((failure) => (null, '$failure'), (output) => (output, null));

    var (output, error) = await attempt();
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
    if (!mounted) return null;
    setState(() {
      _loading = false;
      _error = error;
    });
    return output;
  }

  Future<void> _selectProfile(String id) async {
    _generation++;
    setState(() {
      _profileId = id;
      _current = null;
      _lines = const [];
      _namespaces = const [];
      _namespace = null;
      _pods = const [];
      _pod = null;
      _workload = null;
      _gonePod = null;
    });
    final output = await _run('kubectl get namespaces --no-headers');
    if (output == null || _profileId != id) return;
    final namespaces = parseNamespaces(output);
    setState(() => _namespaces = namespaces);
    if (namespaces.isNotEmpty) {
      await _selectNamespace(
        namespaces.any((ns) => ns.name == 'default')
            ? 'default'
            : namespaces.first.name,
      );
    }
  }

  Future<void> _selectNamespace(String namespace) async {
    _generation++;
    setState(() {
      _namespace = namespace;
      _current = null;
      _pod = null;
      _workload = null;
      _gonePod = null;
      _pods = const [];
    });
    final output = await _run(
      'kubectl get pods -n ${shellQuote(namespace)} --no-headers',
    );
    if (output == null || _namespace != namespace) return;
    setState(() => _pods = parsePods(output));
  }

  static bool _isSystem(String namespace) => namespace.startsWith('kube-');

  KubePod? get _selectedPod => _pods.where((p) => p.name == _pod).firstOrNull;

  /// What the logs are read from, for the title and the pod button.
  String get _targetLabel => _pod ?? _workload?.name ?? 'All pods';

  /// Pods grouped by their controller, in first-seen order.
  Map<Workload, List<KubePod>> get _workloads {
    final groups = <Workload, List<KubePod>>{};
    for (final pod in _pods) {
      final workload = workloadOf(pod.name);
      if (workload != null) (groups[workload] ??= []).add(pod);
    }
    return groups;
  }

  /// Switches what the logs are read from. [keepLines] continues the
  /// current lines (a replaced pod); otherwise the view starts empty.
  void _setTarget({String? pod, Workload? workload, bool keepLines = false}) {
    _generation++;
    setState(() {
      _pod = pod;
      _workload = pod == null ? workload : null;
      _gonePod = null;
      _replacement = null;
      _current = null;
      if (!keepLines) _lines = const [];
    });
    final namespace = _namespace;
    if (keepLines && namespace != null) {
      widget.onTitle('$_targetLabel · $namespace');
      _syncTimer();
      unawaited(_tick()); // pick up from the newest line right away
    }
  }

  /// The single pod being followed is gone: refresh the pod list, look for
  /// its replacement and pause auto-refresh until the user picks.
  Future<void> _handlePodGone(String gone) async {
    final profile = _profile();
    final namespace = _namespace;
    if (profile == null || namespace == null) return;
    final result = await _manager.execOnProfile(
      profile,
      'kubectl get pods -n ${shellQuote(namespace)} --no-headers',
    );
    if (!mounted || _pod != gone) return;
    final pods = result.fold((_) => null, parsePods);
    setState(() {
      if (pods != null) _pods = pods;
      _gonePod = gone;
      _replacement = pods == null ? null : replacementFor(gone, pods);
      _error = null;
    });
    _syncTimer(); // pauses
  }

  /// e.g. "Deployment · 3 pods · 2 healthy · 1 failing".
  static String _workloadSummary(Workload workload, List<KubePod> pods) {
    final health = pods.map(podHealth).toList();
    final ok = health.where((h) => h == PodHealth.ok).length;
    final failing = health.where((h) => h == PodHealth.failing).length;
    return [
      switch (workload.kind) {
        WorkloadKind.deployment => 'Deployment',
        WorkloadKind.statefulSet => 'StatefulSet',
        WorkloadKind.other => 'DaemonSet / Job',
      },
      '${pods.length} pod${pods.length == 1 ? '' : 's'}',
      if (ok > 0) '$ok healthy',
      if (failing > 0) '$failing failing',
    ].join(' · ');
  }

  /// e.g. "14 pods merged by time · 12 healthy · 2 failing".
  String get _podSummary {
    final health = _pods.map(podHealth).toList();
    final failing = health.where((h) => h == PodHealth.failing).length;
    final ok = health.where((h) => h == PodHealth.ok).length;
    return [
      '${_pods.length} pods merged by time',
      if (ok > 0) '$ok healthy',
      if (failing > 0) '$failing failing',
    ].join(' · ');
  }

  /// What [_view] last computed, and from what: rebuilds (scrolling, the
  /// jump button, auto-refresh notes) reuse it instead of refiltering.
  Object? _viewKey;
  ({List<LogLine> shown, List<int> matches})? _viewCache;

  /// Lines to show and, among them, the indices matching the search.
  /// kubectl applies the start of the range; an absolute end is cut here.
  ({List<LogLine> shown, List<int> matches}) _view() {
    final to = _relative == null ? _to : null;
    final key = (_lines, _search.text, _onlyMatches, to);
    if (key == _viewKey) return _viewCache!;
    _viewKey = key;
    return _viewCache = _computeView(LogQuery(_search.text), to);
  }

  ({List<LogLine> shown, List<int> matches}) _computeView(
    LogQuery query,
    DateTime? to,
  ) {
    if (query.isEmpty) {
      return (shown: filterLogLines(_lines, to: to), matches: const []);
    }
    if (_onlyMatches) {
      final shown = filterLogLines(_lines, to: to, query: query);
      return (
        shown: shown,
        matches: [for (var i = 0; i < shown.length; i++) i],
      );
    }
    final shown = filterLogLines(_lines, to: to);
    return (
      shown: shown,
      matches: [
        for (final (i, line) in shown.indexed)
          if (query.matchesLine(line)) i,
      ],
    );
  }

  /// Where [_current] sits in [matches], or -1.
  int _cursorIn(List<LogLine> shown, List<int> matches) {
    final current = _current;
    if (current == null) return -1;
    return matches.indexWhere((i) => identical(shown[i], current));
  }

  /// Steps to the next ([delta] 1) or previous (-1) match, wrapping.
  void _goto(int delta) {
    final (:shown, :matches) = _view();
    if (matches.isEmpty) return;
    final cursor = _cursorIn(shown, matches);
    final next = cursor < 0
        ? (delta > 0 ? 0 : matches.length - 1)
        : (cursor + delta) % matches.length;
    setState(() => _current = shown[matches[next]]);
    unawaited(_scrollToIndex(matches[next], shown.length));
  }

  /// ListView can't jump to a row of unknown height: jump to an estimate,
  /// then, once the row is built, settle it a third of the way down.
  Future<void> _scrollToIndex(int index, int count) async {
    setState(() => _targetIndex = index);
    for (var attempt = 0; attempt < 6; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients || _targetIndex != index) return;
      final row = _targetKey.currentContext;
      if (row != null && row.mounted) {
        await Scrollable.ensureVisible(
          row,
          alignment: .33,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
        return;
      }
      final position = _scroll.position;
      final average =
          (position.maxScrollExtent + position.viewportDimension) / count;
      _scroll.jumpTo(
        (index * average - position.viewportDimension * .33).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  /// An absolute range whose end has passed: nothing new can arrive.
  bool get _rangeEnded =>
      _relative == null && _to != null && DateTime.now().isAfter(_to!);

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    final every = _refreshEvery;
    if (every == null || !widget.active || _rangeEnded || _gonePod != null) {
      return;
    }
    _timer = Timer.periodic(every, (_) => _tick());
  }

  void _setRefreshEvery(Duration? every) {
    setState(() => _refreshEvery = every);
    _syncTimer();
  }

  /// Background refresh: fetches only what arrived after the newest line
  /// and appends it, without the spinner or connection prompts.
  Future<void> _tick() async {
    final namespace = _namespace;
    final profile = _profile();
    if (_ticking || _loading || namespace == null || profile == null) return;
    final generation = _generation;
    final last = lastStamp(_lines);
    _ticking = true;
    final result = await _manager.execOnProfile(
      profile,
      kubeLogsCommand(
        namespace,
        _pod,
        workload: _workload,
        since: last == null ? _relativeRanges[_relative] : null,
        sinceTime: last ?? (_relative == null ? _from : null),
      ),
    );
    _ticking = false;
    if (!mounted || generation != _generation) return;
    final pod = _pod;
    if (pod != null &&
        result.fold(
          (failure) => '$failure'.contains('NotFound'),
          (_) => false,
        )) {
      await _handlePodGone(pod);
      return;
    }
    // Follow (scroll down, and let a relative range drop old lines) only
    // while the reader sits at the bottom and isn't stepping through
    // matches; otherwise just append, so nothing moves under them.
    final following =
        _current == null &&
        (!_scroll.hasClients ||
            _scroll.position.pixels >= _scroll.position.maxScrollExtent - 48);
    final range = following ? _relativeRanges[_relative] : null;
    setState(() {
      result.fold((failure) => _error = '$failure', (output) {
        _error = null;
        _lastRefresh = DateTime.now();
        final before = _lines.length;
        _lines = appendNewLines(
          _lines,
          parseLogLines(output),
          keepFrom: range == null ? null : DateTime.now().subtract(range),
        );
        // Not following means nothing was trimmed: the growth is new lines.
        if (!following) _newBelow += _lines.length - before;
      });
    });
    if (following) _scrollToEnd();
    if (_rangeEnded) _syncTimer(); // stops it
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  Future<void> _loadLogs() async {
    final namespace = _namespace;
    if (namespace == null) return;
    _generation++;
    final output = await _run(
      kubeLogsCommand(
        namespace,
        _pod,
        workload: _workload,
        since: _relativeRanges[_relative],
        sinceTime: _relative == null ? _from : null,
      ),
    );
    if (output == null) {
      final pod = _pod;
      if (pod != null && (_error?.contains('NotFound') ?? false)) {
        await _handlePodGone(pod);
      }
      return;
    }
    widget.onTitle('$_targetLabel · $namespace');
    setState(() {
      _lines = parseLogLines(output);
      _gonePod = null;
      _current = null;
      _lastRefresh = DateTime.now();
    });
    _scrollToEnd();
    _syncTimer();
  }

  Future<void> _pickAbsolute() async {
    final now = DateTime.now();
    final range = await showDialog<(DateTime, DateTime)>(
      context: context,
      builder: (_) => _AbsoluteRangeDialog(
        from: _from ?? now.subtract(const Duration(hours: 1)),
        to: _to ?? now,
      ),
    );
    if (range == null) return;
    setState(() {
      _relative = null;
      _from = range.$1;
      _to = range.$2;
    });
    if (_namespace != null) await _loadLogs();
  }

  /// "Auto-refresh every 10s · updated 14:21:05", or why it stopped.
  String? get _refreshNote {
    final every = _refreshEvery;
    if (every == null) return null;
    if (_rangeEnded) return 'Range ended · auto-refresh stopped';
    if (_gonePod != null) return 'Auto-refresh paused · pod is gone';
    final last = _lastRefresh;
    return [
      'Auto-refresh every ${_intervalLabel(every)}',
      if (last != null)
        'updated ${_two(last.hour)}:${_two(last.minute)}:${_two(last.second)}',
      if (_current != null) 'holding position on a search match',
    ].join(' · ');
  }

  String get _rangeLabel => _relative != null
      ? _relative!
      : '${_formatShort(_from!)}  →  ${_formatShort(_to!)}';

  @override
  Widget build(BuildContext context) {
    final profiles = context.select(
      (SshWorkspaceBloc bloc) => bloc.state.profiles,
    );
    final profile = profiles.where((p) => p.id == _profileId).firstOrNull;
    final query = LogQuery(_search.text);
    final (:shown, :matches) = _view();
    final cursor = _cursorIn(shown, matches);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final pickers = [
                Expanded(
                  flex: 4,
                  child: _SelectButton<String>(
                    icon: Icons.dns_outlined,
                    label: 'Server',
                    value: profile?.name,
                    placeholder: 'Select a server with kubectl',
                    enabled: !_loading,
                    leading: profile == null
                        ? null
                        : ProfileOsIcon(profile: profile, size: 18),
                    noun: 'servers',
                    options: [
                      for (final p in profiles)
                        (
                          value: p.id,
                          label: p.name,
                          subtitle: p.group,
                          leading: ProfileOsIcon(profile: p, size: 24),
                          section: null,
                        ),
                    ],
                    selected: _profileId,
                    onSelected: _selectProfile,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _SelectButton<String>(
                    icon: Icons.folder_outlined,
                    label: 'Namespace',
                    value: _namespace,
                    placeholder: 'Pick a server first',
                    enabled: !_loading && _namespaces.isNotEmpty,
                    noun: 'namespaces',
                    options: [
                      for (final ns in _namespaces)
                        (
                          value: ns.name,
                          label: ns.name,
                          subtitle: '${ns.status} · ${ns.age}',
                          leading: _NamespaceIcon(system: _isSystem(ns.name)),
                          section: null,
                        ),
                    ],
                    selected: _namespace,
                    onSelected: _selectNamespace,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: _SelectButton<_Target>(
                    icon: Icons.view_in_ar_outlined,
                    label: 'Pod',
                    value: _targetLabel,
                    leading: _workload != null
                        ? Icon(
                            Icons.account_tree_outlined,
                            size: 16,
                            color: AppColors.accent,
                          )
                        : _selectedPod == null
                        ? null
                        : _PodDot(podHealth(_selectedPod!)),
                    placeholder: '—',
                    enabled: !_loading && _namespace != null,
                    noun: 'pods',
                    options: [
                      (
                        value: (pod: null, workload: null),
                        label: 'All pods',
                        subtitle: _podSummary,
                        leading: Icon(
                          Icons.layers_outlined,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        section: null,
                      ),
                      for (final MapEntry(key: workload, value: pods)
                          in _workloads.entries)
                        (
                          value: (pod: null, workload: workload),
                          label: workload.name,
                          subtitle: _workloadSummary(workload, pods),
                          leading: Icon(
                            Icons.account_tree_outlined,
                            size: 18,
                            color:
                                pods.any(
                                  (p) => podHealth(p) == PodHealth.failing,
                                )
                                ? AppColors.danger
                                : AppColors.accent,
                          ),
                          section: 'Workloads · follow new pods automatically',
                        ),
                      for (final pod in _pods)
                        (
                          value: (pod: pod.name, workload: null),
                          label: pod.name,
                          subtitle: [
                            pod.status,
                            '${pod.ready} ready',
                            if (pod.restarts > 0)
                              '${pod.restarts} restart${pod.restarts == 1 ? '' : 's'}',
                            pod.age,
                          ].join(' · '),
                          leading: _PodDot(podHealth(pod)),
                          section: 'Pods · this pod only',
                        ),
                    ],
                    selected: (pod: _pod, workload: _workload),
                    onSelected: (target) =>
                        _setTarget(pod: target.pod, workload: target.workload),
                  ),
                ),
              ];
              final actions = [
                _TimeRangeButton(
                  label: _rangeLabel,
                  absolute: _relative == null ? _rangeLabel : null,
                  ranges: _relativeRanges.keys.toList(),
                  selected: _relative,
                  refreshEvery: _refreshEvery,
                  refreshDisabled: _rangeEnded
                      ? 'The range has ended; no new logs can arrive.'
                      : null,
                  onRefreshEvery: _setRefreshEvery,
                  onRelative: (range) {
                    setState(() => _relative = range);
                    if (_namespace != null) _loadLogs();
                  },
                  onAbsolute: _pickAbsolute,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: _controlHeight,
                  child: FilledButton.icon(
                    onPressed: _loading || _namespace == null
                        ? null
                        : _loadLogs,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, _controlHeight),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: _loading
                        ? SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onAccent,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(_lines.isEmpty ? 'Load' : 'Refresh'),
                  ),
                ),
              ];
              // One toolbar when it fits; narrow windows put the time
              // range and Load on their own row under the pickers.
              if (constraints.maxWidth >= 980) {
                return Row(
                  children: [...pickers, const SizedBox(width: 8), ...actions],
                );
              }
              return Column(
                children: [
                  Row(children: pickers),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              );
            },
          ),
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
                  _StatusBar(
                    search: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      onChanged: (_) => setState(() => _current = null),
                      onSubmitted: (_) {
                        _goto(1);
                        _searchFocus.requestFocus();
                      },
                      style: appFieldTextStyle(),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 9),
                        hintStyle: portixMuted(13),
                        hintText:
                            'Search logs   error -timeout   "exact phrase"   '
                            'ERROR OR WARN',
                        suffixIcon: query.isEmpty
                            ? null
                            : _SearchNav(
                                position: cursor,
                                total: matches.length,
                                onlyMatches: _onlyMatches,
                                onPrevious: () => _goto(-1),
                                onNext: () => _goto(1),
                                onToggleFilter: () => setState(() {
                                  _onlyMatches = !_onlyMatches;
                                  _current = null;
                                }),
                                onClear: () => setState(() {
                                  _search.clear();
                                  _current = null;
                                }),
                              ),
                      ),
                    ),
                    note: _refreshNote,
                    shown: shown.length,
                    total: _lines.length,
                  ),
                  if (_error case final error?)
                    _ErrorBanner(
                      error: describeKubeError(error),
                      retrying: _loading,
                      onRetry: _retry,
                      onDismiss: () => setState(() => _error = null),
                    ),
                  if (_gonePod case final gone?)
                    _PodGoneBanner(
                      gone: gone,
                      replacement: _replacement?.name,
                      workload: workloadOf(gone),
                      onSwitch: (pod) => _setTarget(pod: pod, keepLines: true),
                      onFollow: (workload) =>
                          _setTarget(workload: workload, keepLines: true),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _buildLines(
                            shown,
                            query.highlights,
                            cursor < 0 ? null : matches[cursor],
                          ),
                        ),
                        Positioned(
                          right: 16,
                          bottom: 14,
                          child: _JumpToLatest(
                            visible: !_atBottom && shown.isNotEmpty,
                            newLines: _newBelow,
                            onPressed: _jumpToLatest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLines(
    List<LogLine> shown,
    List<RegExp> highlights,
    int? current,
  ) {
    if (shown.isEmpty) {
      final (icon, message) = _lines.isNotEmpty
          ? (Icons.filter_alt_off_outlined, 'No lines match the search.')
          : _profileId == null
          ? (Icons.dns_outlined, 'Select a server that has kubectl.')
          : (Icons.article_outlined, 'Pick a pod and time range, then Load.');
      return Center(
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
    return SelectionArea(
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          itemCount: shown.length,
          itemBuilder: (_, i) => _LogRow(
            key: i == _targetIndex ? _targetKey : null,
            line: shown[i],
            highlights: highlights,
            odd: i.isOdd,
            current: i == current,
            expanded: _expanded.contains(shown[i]),
            onToggleExpanded: () => setState(() {
              if (!_expanded.remove(shown[i])) _expanded.add(shown[i]);
            }),
          ),
        ),
      ),
    );
  }
}

const _mono = TextStyle(
  fontFamily: 'JetBrains Mono',
  fontFamilyFallback: [
    'SF Mono',
    'SFMono-Regular',
    'Menlo',
    'Cascadia Mono',
    'Consolas',
    'DejaVu Sans Mono',
    'Ubuntu Mono',
    'monospace',
  ],
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
);

String _formatStamp(DateTime time) {
  final t = time.toLocal();
  return '${_months[t.month - 1]} ${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}';
}

/// One entry, Discover-style: local time, a level badge, then the message
/// wrapping in its own column, with search terms highlighted.
class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.line,
    required this.highlights,
    required this.odd,
    required this.expanded,
    required this.onToggleExpanded,
    this.current = false,
    super.key,
  });

  final LogLine line;
  final List<RegExp> highlights;
  final bool odd;

  /// The search match the ↑/↓ buttons are on.
  final bool current;

  /// Shows up to [_expandedChars] of a long message instead of
  /// [_collapsedChars].
  final bool expanded;
  final VoidCallback onToggleExpanded;

  static const _collapsedChars = 2000;
  static const _expandedChars = 50000;

  static String _size(int chars) => chars >= 1000000
      ? '${(chars / 1000000).toStringAsFixed(1)}M'
      : chars >= 1000
      ? '${(chars / 1000).toStringAsFixed(chars >= 10000 ? 0 : 1)}k'
      : '$chars';

  static Color? _levelColor(LogLevel? level) => switch (level) {
    LogLevel.error => AppColors.danger,
    LogLevel.warn => AppColors.amber,
    LogLevel.info => AppColors.cyan,
    LogLevel.debug => AppColors.muted,
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final (:level, :message) = displayOf(line);
    final clip = clipForDisplay(
      message,
      expanded ? _expandedChars : _collapsedChars,
    );
    final long = message.length > _collapsedChars;
    final color = _levelColor(level);
    final time = line.time;
    return Container(
      decoration: BoxDecoration(
        color: current
            ? AppColors.accent.withValues(alpha: .14)
            : level == LogLevel.error
            ? AppColors.dangerTint.withValues(alpha: .35)
            : odd
            ? AppColors.surface.withValues(alpha: .45)
            : null,
        border: Border(
          left: current
              ? BorderSide(color: AppColors.accent, width: 3)
              : BorderSide(color: color ?? Colors.transparent, width: 2),
          bottom: BorderSide(color: AppColors.border.withValues(alpha: .45)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 7, 16, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 152,
            child: Text.rich(
              TextSpan(
                children: [
                  // Flutter's copy joins rows with nothing between them, and a
                  // drag drops a trailing newline, so each row starts with a
                  // tiny, invisible one instead.
                  const TextSpan(
                    text: '\n',
                    style: TextStyle(fontSize: .01, height: .01),
                  ),
                  // The space keeps the stamp apart from the message.
                  if (time != null) TextSpan(text: '${_formatStamp(time)} '),
                ],
              ),
              style: _mono.copyWith(
                fontSize: 12,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
          ),
          // The badge is only a visual cue, so keep it out of copy.
          SelectionContainer.disabled(
            child: SizedBox(
              width: 58,
              child: level == null
                  ? null
                  : Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color!.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          level.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            letterSpacing: .4,
                            color: color,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      ..._highlight(
                        clip.shown,
                        highlights,
                        TextStyle(
                          color: AppColors.text,
                          backgroundColor: AppColors.amber.withValues(
                            alpha: .28,
                          ),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (clip.hidden > 0)
                        TextSpan(
                          text: ' …',
                          style: TextStyle(color: AppColors.muted),
                        ),
                    ],
                  ),
                  style: _mono.copyWith(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.text.withValues(alpha: .92),
                  ),
                ),
                if (long)
                  // Controls, not log text: keep "8.0k chars Show less" out of copy.
                  SelectionContainer.disabled(
                    child: _LongLineBar(
                      hidden: clip.hidden,
                      total: message.length,
                      expanded: expanded,
                      size: _size,
                      onToggle: onToggleExpanded,
                      onCopy: () =>
                          Clipboard.setData(ClipboardData(text: line.text)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Under a clipped long line: how much is hidden, more/less, copy all.
class _LongLineBar extends StatelessWidget {
  const _LongLineBar({
    required this.hidden,
    required this.total,
    required this.expanded,
    required this.size,
    required this.onToggle,
    required this.onCopy,
  });

  final int hidden;
  final int total;
  final bool expanded;
  final String Function(int chars) size;
  final VoidCallback onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    Widget link(String text, IconData icon, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            hidden > 0
                ? '+${size(hidden)} more of ${size(total)} chars'
                : '${size(total)} chars',
            style: portixMuted(11),
          ),
          if (hidden > 0 && !expanded)
            link('Show more', Icons.unfold_more_rounded, onToggle),
          if (expanded) link('Show less', Icons.unfold_less_rounded, onToggle),
          link('Copy line', Icons.copy_rounded, onCopy),
        ],
      ),
    );
  }
}

/// [text] as spans with every match of [terms] in [style].
List<TextSpan> _highlight(String text, List<RegExp> terms, TextStyle style) {
  if (terms.isEmpty) return [TextSpan(text: text)];
  final spans = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    Match? next;
    for (final term in terms) {
      final m = _firstNonEmpty(term, text, i);
      if (m != null && (next == null || m.start < next.start)) next = m;
    }
    if (next == null) break;
    if (next.start > i) {
      spans.add(TextSpan(text: text.substring(i, next.start)));
    }
    spans.add(TextSpan(text: next.group(0), style: style));
    i = next.end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return spans;
}

/// The first match of [term] at or after [from] that isn't empty (a regex
/// like `re:x*` can match nothing and would stall the loop above).
Match? _firstNonEmpty(RegExp term, String text, int from) {
  for (final m in term.allMatches(text, from)) {
    if (m.end > m.start) return m;
  }
  return null;
}

/// Floating pill over the log list while scrolled up: back to the newest
/// line, counting what auto-refresh added meanwhile.
class _JumpToLatest extends StatelessWidget {
  const _JumpToLatest({
    required this.visible,
    required this.newLines,
    required this.onPressed,
  });

  final bool visible;
  final int newLines;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, .4),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Material(
            color: newLines > 0 ? AppColors.accent : AppColors.surface,
            elevation: 6,
            shadowColor: Colors.black54,
            shape: StadiumBorder(
              side: BorderSide(
                color: newLines > 0 ? AppColors.accent : AppColors.border,
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 15,
                      color: newLines > 0 ? AppColors.onAccent : AppColors.text,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      newLines > 0
                          ? '$newLines new line${newLines == 1 ? '' : 's'}'
                          : 'Jump to latest',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: newLines > 0
                            ? AppColors.onAccent
                            : AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a tab reads logs from: one pod, one workload's pods, or (both null)
/// every pod in the namespace.
typedef _Target = ({String? pod, Workload? workload});

/// Shown when the followed pod disappeared: offers its replacement and
/// following the whole workload, so restarts and rollouts don't matter.
class _PodGoneBanner extends StatelessWidget {
  const _PodGoneBanner({
    required this.gone,
    required this.replacement,
    required this.workload,
    required this.onSwitch,
    required this.onFollow,
  });

  final String gone;
  final String? replacement;
  final Workload? workload;
  final ValueChanged<String> onSwitch;
  final ValueChanged<Workload> onFollow;

  @override
  Widget build(BuildContext context) {
    final replacement = this.replacement;
    final workload = this.workload;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_rounded, size: 18, color: AppColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: gone,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const TextSpan(text: ' no longer exists'),
                  if (replacement != null) ...[
                    const TextSpan(text: ' — replaced by '),
                    TextSpan(
                      text: replacement,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                  const TextSpan(text: '. Lines so far are kept.'),
                ],
              ),
              style: TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
          if (replacement != null) ...[
            const SizedBox(width: 8),
            AppButton(
              icon: Icons.swap_horiz_rounded,
              label: 'Switch',
              primary: true,
              onPressed: () => onSwitch(replacement),
            ),
          ],
          if (workload != null) ...[
            const SizedBox(width: 6),
            AppButton(
              icon: Icons.account_tree_outlined,
              label: 'Follow ${workload.name}',
              onPressed: () => onFollow(workload),
            ),
          ],
        ],
      ),
    );
  }
}

/// In the search field: "3 / 42", ↑ ↓, the only-matching-lines toggle and
/// clear.
class _SearchNav extends StatelessWidget {
  const _SearchNav({
    required this.position,
    required this.total,
    required this.onlyMatches,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleFilter,
    required this.onClear,
  });

  final int position;
  final int total;
  final bool onlyMatches;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Widget button(
      String tooltip,
      IconData icon,
      VoidCallback? onPressed, {
      Color? color,
    }) => IconButton(
      tooltip: tooltip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon, color: color ?? AppColors.muted),
    );
    final has = total > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          !has
              ? 'No results'
              : position < 0
              ? '$total'
              : '${position + 1} / $total',
          style: portixMuted(12).copyWith(
            color: has ? null : AppColors.danger,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 4),
        button(
          'Previous match',
          Icons.keyboard_arrow_up_rounded,
          has ? onPrevious : null,
        ),
        button(
          'Next match (Enter)',
          Icons.keyboard_arrow_down_rounded,
          has ? onNext : null,
        ),
        Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: AppColors.border,
        ),
        button(
          onlyMatches
              ? 'Showing only matching lines'
              : 'Showing all lines, matches highlighted',
          onlyMatches
              ? Icons.filter_alt_rounded
              : Icons.filter_alt_off_outlined,
          onToggleFilter,
          color: onlyMatches ? AppColors.accent : null,
        ),
        button('Clear search', Icons.close_rounded, onClear),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Line count and the last error, above the log lines.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.search,
    required this.note,
    required this.shown,
    required this.total,
  });

  /// The log search field, borderless; the header is its frame.
  final Widget search;
  final String? note;
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 12, right: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: search),
          if (note != null) ...[
            const SizedBox(width: 12),
            Icon(Icons.autorenew_rounded, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                note!,
                overflow: TextOverflow.ellipsis,
                style: portixMuted(12),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            shown == total ? '$total lines' : '$shown of $total lines',
            style: portixMuted(12),
          ),
        ],
      ),
    );
  }
}

/// A failure, readably: title, what to check, Retry, and the raw message
/// behind "Details" (selectable, copyable).
class _ErrorBanner extends StatefulWidget {
  const _ErrorBanner({
    required this.error,
    required this.retrying,
    required this.onRetry,
    required this.onDismiss,
  });

  final KubeError error;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  State<_ErrorBanner> createState() => _ErrorBannerState();
}

class _ErrorBannerState extends State<_ErrorBanner> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    Widget link(String text, IconData icon, VoidCallback? onTap) =>
        TextButton.icon(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.text,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          icon: Icon(icon, size: 14),
          label: Text(text),
        );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.dangerTint,
        border: Border(
          left: BorderSide(color: AppColors.danger, width: 3),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              link(
                widget.retrying ? 'Retrying…' : 'Retry',
                Icons.refresh_rounded,
                widget.retrying ? null : widget.onRetry,
              ),
              link(
                _details ? 'Hide details' : 'Details',
                _details
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                () => setState(() => _details = !_details),
              ),
              IconButton(
                tooltip: 'Dismiss',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: widget.onDismiss,
                icon: Icon(Icons.close_rounded, color: AppColors.muted),
              ),
            ],
          ),
          if (_details)
            Container(
              margin: const EdgeInsets.fromLTRB(28, 8, 8, 0),
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        error.detail,
                        style: _mono.copyWith(
                          fontSize: 11.5,
                          height: 1.5,
                          color: AppColors.text.withValues(alpha: .85),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy details',
                    iconSize: 14,
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: error.detail)),
                    icon: Icon(Icons.copy_rounded, color: AppColors.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A pod's health as a small colored dot with a soft halo.
class _PodDot extends StatelessWidget {
  const _PodDot(this.health);

  final PodHealth health;

  @override
  Widget build(BuildContext context) {
    final color = switch (health) {
      PodHealth.ok => AppColors.green,
      PodHealth.pending => AppColors.amber,
      PodHealth.failing => AppColors.danger,
      PodHealth.done => AppColors.muted,
    };
    return Center(
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .45), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}

class _NamespaceIcon extends StatelessWidget {
  const _NamespaceIcon({required this.system});

  final bool system;

  @override
  Widget build(BuildContext context) => Icon(
    system ? Icons.settings_suggest_outlined : Icons.folder_outlined,
    size: 18,
    color: system ? AppColors.muted : AppColors.accent,
  );
}

/// Opens [builder]'s panel just under the widget of [context] (a button),
/// kept on screen; returns what the panel pops with.
Future<R?> _showAnchored<R>(
  BuildContext context, {
  required String label,
  required double Function(Rect anchor) width,
  required Widget Function(double maxHeight) builder,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  return showGeneralDialog<R>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (dialogContext, _, _) {
      final screen = MediaQuery.sizeOf(dialogContext);
      final w = width(anchor);
      // Right-aligned to the button when it would run off screen.
      final left =
          (anchor.left + w > screen.width - 8 ? anchor.right - w : anchor.left)
              .clamp(8.0, screen.width - w - 8);
      final top = anchor.bottom + 6;
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: w,
            child: builder((screen.height - top - 16).clamp(160.0, 460.0)),
          ),
        ],
      );
    },
  );
}

/// The popup surface shared by the select and time panels.
class _PopupSurface extends StatelessWidget {
  const _PopupSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    elevation: 12,
    shadowColor: Colors.black54,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// One choice in a [_SelectButton]; a change of [section] between options
/// starts a titled group in the popup.
typedef _Option<T> = ({
  T value,
  String label,
  String? subtitle,
  Widget? leading,
  String? section,
});

/// A compact 36px select: small muted [label], bold value. Opens a popup
/// under itself with the options, searchable when the list is long.
class _SelectButton<T> extends StatelessWidget {
  const _SelectButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.enabled,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.leading,
    this.noun = 'items',
  });

  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final bool enabled;
  final List<_Option<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  /// Replaces [icon] once something is picked (e.g. the server's OS logo).
  final Widget? leading;

  /// Plural for the popup's count, e.g. "servers".
  final String noun;

  Future<void> _open(BuildContext context) async {
    final picked = await _showAnchored<_Picked<T>>(
      context,
      label: label,
      width: (anchor) => anchor.width.clamp(300.0, 460.0),
      builder: (maxHeight) => _PickerPanel<T>(
        options: options,
        selected: selected,
        noun: noun,
        maxHeight: maxHeight,
      ),
    );
    if (picked != null) onSelected(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final picked = value != null;
    return Builder(
      builder: (context) => _ControlShell(
        onTap: enabled ? () => _open(context) : null,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: picked && leading != null
                  ? leading
                  : Icon(icon, size: 16, color: AppColors.muted),
            ),
            const SizedBox(width: 8),
            Text(label, style: portixMuted(12)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value ?? placeholder,
                overflow: TextOverflow.ellipsis,
                style: appFieldTextStyle().copyWith(
                  fontWeight: picked ? FontWeight.w500 : FontWeight.w500,
                  color: picked ? AppColors.text : AppColors.muted,
                ),
              ),
            ),
            Icon(
              Icons.unfold_more_rounded,
              size: 16,
              color: enabled ? AppColors.muted : AppColors.border,
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps the pick so a null value ("All pods") differs from a dismiss.
class _Picked<T> {
  const _Picked(this.value);

  final T value;
}

class _PickerPanel<T> extends StatefulWidget {
  const _PickerPanel({
    required this.options,
    required this.selected,
    required this.noun,
    required this.maxHeight,
  });

  final List<_Option<T>> options;
  final T? selected;
  final String noun;
  final double maxHeight;

  @override
  State<_PickerPanel<T>> createState() => _PickerPanelState<T>();
}

class _PickerPanelState<T> extends State<_PickerPanel<T>> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<_Option<T>> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return [
      for (final o in widget.options)
        if (o.label.toLowerCase().contains(q) ||
            (o.subtitle?.toLowerCase().contains(q) ?? false))
          o,
    ];
  }

  void _pick(_Option<T> option) =>
      Navigator.of(context).pop(_Picked<T>(option.value));

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final searchable = widget.options.length > 6;
    return _PopupSurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (searchable) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (filtered.isNotEmpty) _pick(filtered.first);
                    },
                    style: appFieldTextStyle(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search ${widget.noun}…',
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 17,
                        color: AppColors.muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '${filtered.length}',
                          style: portixMuted(11),
                        ),
                      ),
                      suffixIconConstraints: const BoxConstraints(),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: AppColors.border),
            ],
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No ${widget.noun} match.',
                        textAlign: TextAlign.center,
                        style: portixMuted(12),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final section = filtered[i].section;
                        final row = _PickerRow(
                          option: filtered[i],
                          selected: filtered[i].value == widget.selected,
                          onTap: () => _pick(filtered[i]),
                        );
                        if (section == null ||
                            (i > 0 && filtered[i - 1].section == section)) {
                          return row;
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (i > 0)
                              Divider(height: 9, color: AppColors.border),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                              child: Text(
                                section.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: .7,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            row,
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _Option<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = option.subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: selected
            ? AppColors.accent.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          hoverColor: AppColors.text.withValues(alpha: .06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                if (option.leading != null) ...[
                  SizedBox.square(dimension: 24, child: option.leading),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                        style: appFieldTextStyle().copyWith(
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w500,
                          color: selected ? AppColors.accent : AppColors.text,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: portixMuted(11),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 16, color: AppColors.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kibana-style time picker: quick relative ranges, an absolute range and
/// the auto-refresh interval, in one panel.
class _TimeRangeButton extends StatelessWidget {
  const _TimeRangeButton({
    required this.label,
    required this.absolute,
    required this.ranges,
    required this.selected,
    required this.onRelative,
    required this.onAbsolute,
    required this.refreshEvery,
    required this.refreshDisabled,
    required this.onRefreshEvery,
  });

  final String label;

  /// The absolute range as text when one is in use.
  final String? absolute;
  final List<String> ranges;
  final String? selected;
  final ValueChanged<String> onRelative;
  final VoidCallback onAbsolute;
  final Duration? refreshEvery;

  /// Why auto-refresh can't run now, or null when it can.
  final String? refreshDisabled;
  final ValueChanged<Duration?> onRefreshEvery;

  @override
  Widget build(BuildContext context) {
    final refreshing = refreshEvery != null && refreshDisabled == null;
    return Builder(
      builder: (context) => _ControlShell(
        onTap: () => _showAnchored<void>(
          context,
          label: 'Time range',
          width: (_) => 340,
          builder: (_) => _TimePanel(button: this),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: appFieldTextStyle().copyWith(fontWeight: FontWeight.w500),
            ),
            if (refreshing) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.autorenew_rounded,
                      size: 12,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _intervalLabel(refreshEvery!),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.expand_more_rounded, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _TimePanel extends StatelessWidget {
  const _TimePanel({required this.button});

  final _TimeRangeButton button;

  @override
  Widget build(BuildContext context) {
    final b = button;
    void close() => Navigator.of(context).pop();
    Widget heading(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 6),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              letterSpacing: .8,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );

    return _PopupSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading(Icons.bolt_rounded, 'Commonly used'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final range in b.ranges)
                      _Chip(
                        label: range.replaceFirst('Last ', ''),
                        selected: range == b.selected,
                        onTap: () {
                          close();
                          b.onRelative(range);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Material(
            color: b.absolute != null
                ? AppColors.accent.withValues(alpha: .08)
                : Colors.transparent,
            child: InkWell(
              onTap: () {
                close();
                b.onAbsolute();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_calendar_outlined,
                      size: 18,
                      color: b.absolute != null
                          ? AppColors.accent
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Absolute range',
                            style: appFieldTextStyle().copyWith(
                              fontWeight: FontWeight.w400,
                              color: b.absolute != null
                                  ? AppColors.accent
                                  : AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            b.absolute ?? 'Pick a start and end date & time',
                            overflow: TextOverflow.ellipsis,
                            style: portixMuted(11),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading(Icons.autorenew_rounded, 'Auto-refresh'),
                _Segmented(
                  items: [
                    for (final every in _refreshIntervals)
                      (every == null ? 'Off' : _intervalLabel(every), every),
                  ],
                  selected: b.refreshDisabled == null ? b.refreshEvery : null,
                  enabled: b.refreshDisabled == null,
                  onSelected: (every) {
                    close();
                    b.onRefreshEvery(every);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  b.refreshDisabled ??
                      'Fetches only new lines; works with any range.',
                  style: portixMuted(11).copyWith(
                    color: b.refreshDisabled != null ? AppColors.amber : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill choice: accent outline and tint when selected.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: .14)
          : AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w500,
              color: selected ? AppColors.accent : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// A joined row of equal-width choices, like a segmented control.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.items,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final List<(String, T)> items;
  final T? selected;
  final bool enabled;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [
            for (final (text, value) in items)
              Expanded(
                child: Material(
                  color: value == selected
                      ? AppColors.accent.withValues(alpha: .18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: enabled ? () => onSelected(value) : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Center(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: value == selected
                              ? FontWeight.w500
                              : FontWeight.w500,
                          color: value == selected
                              ? AppColors.accent
                              : AppColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The bordered 36px box shared by the select and time buttons, matching the
/// text fields.
class _ControlShell extends StatelessWidget {
  const _ControlShell({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.inputBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: _controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          child: Opacity(opacity: onTap == null ? .55 : 1, child: child),
        ),
      ),
    );
  }
}

/// Kibana-style absolute range: pick the start or end card, then its day on
/// the calendar and its time (typed or from the half-hour list).
class _AbsoluteRangeDialog extends StatefulWidget {
  const _AbsoluteRangeDialog({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  State<_AbsoluteRangeDialog> createState() => _AbsoluteRangeDialogState();
}

class _AbsoluteRangeDialogState extends State<_AbsoluteRangeDialog> {
  late DateTime _start = widget.from;
  late DateTime _end = widget.to;
  bool _editingEnd = false;
  late final _time = TextEditingController(text: _hhmm(_start));

  static final _hhmmPattern = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  static String _hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  DateTime get _active => _editingEnd ? _end : _start;

  void _setActive(DateTime value) => setState(() {
    if (_editingEnd) {
      _end = value;
    } else {
      _start = value;
    }
  });

  void _edit(bool end) => setState(() {
    _editingEnd = end;
    _time.text = _hhmm(_active);
  });

  void _setTime(int hour, int minute) {
    final a = _active;
    _setActive(DateTime(a.year, a.month, a.day, hour, minute));
    _time.text = _hhmm(_active);
  }

  String get _zone {
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    return '${DateTime.now().timeZoneName} '
        '(UTC$sign${_two(abs.inHours)}:${_two(abs.inMinutes % 60)})';
  }

  String get _duration {
    final d = _end.difference(_start);
    final parts = [
      if (d.inDays > 0) '${d.inDays}d',
      if (d.inHours % 24 > 0) '${d.inHours % 24}h',
      if (d.inMinutes % 60 > 0) '${d.inMinutes % 60}m',
    ];
    return parts.isEmpty ? '0m' : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final valid = _start.isBefore(_end);
    final timeValid = _hhmmPattern.hasMatch(_time.text.trim());
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.date_range_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Absolute time range', style: portixTitle(15)),
                        const SizedBox(height: 2),
                        Text(_zone, style: portixMuted(11)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    iconSize: 18,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _RangeCard(
                      label: 'Start',
                      time: _start,
                      active: !_editingEnd,
                      onTap: () => _edit(false),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ),
                  Expanded(
                    child: _RangeCard(
                      label: 'End',
                      time: _end,
                      active: _editingEnd,
                      onTap: () => _edit(true),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              height: 300,
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CalendarDatePicker(
                      key: ValueKey(_editingEnd),
                      initialDate: _active,
                      firstDate: DateTime(_active.year - 5),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      onDateChanged: (day) => _setActive(
                        DateTime(
                          day.year,
                          day.month,
                          day.day,
                          _active.hour,
                          _active.minute,
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, color: AppColors.border),
                  SizedBox(
                    width: 112,
                    child: _TimeColumn(
                      controller: _time,
                      valid: timeValid,
                      selected: _active,
                      onTyped: (text) {
                        final m = _hhmmPattern.firstMatch(text.trim());
                        if (m != null) {
                          final a = _active;
                          _setActive(
                            DateTime(
                              a.year,
                              a.month,
                              a.day,
                              int.parse(m[1]!),
                              int.parse(m[2]!),
                            ),
                          );
                        } else {
                          setState(() {});
                        }
                      },
                      onPicked: _setTime,
                      onNow: () {
                        final now = DateTime.now();
                        _setActive(
                          DateTime(
                            now.year,
                            now.month,
                            now.day,
                            now.hour,
                            now.minute,
                          ),
                        );
                        setState(() => _time.text = _hhmm(_active));
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                children: [
                  Icon(
                    valid ? Icons.timelapse_rounded : Icons.error_outline,
                    size: 16,
                    color: valid ? AppColors.muted : AppColors.danger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      valid
                          ? 'Duration  $_duration'
                          : 'Start must be before end.',
                      style: portixMuted(
                        12,
                      ).copyWith(color: valid ? null : AppColors.danger),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: valid && timeValid
                        ? () => Navigator.of(context).pop((_start, _end))
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Start or end summary; the active one is the one being edited.
class _RangeCard extends StatelessWidget {
  const _RangeCard({
    required this.label,
    required this.time,
    required this.active,
    required this.onTap,
  });

  final String label;
  final DateTime time;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? AppColors.accent.withValues(alpha: .08)
          : AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: active ? AppColors.accent : AppColors.border,
          width: active ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: .8,
                  color: active ? AppColors.accent : AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_months[time.month - 1]} ${time.day}, ${time.year}',
                style: portixMuted(12),
              ),
              const SizedBox(height: 2),
              Text(
                '${_two(time.hour)}:${_two(time.minute)}',
                style: _mono.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Typed HH:mm, a "Now" shortcut and half-hour slots, like Kibana's list.
class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.controller,
    required this.valid,
    required this.selected,
    required this.onTyped,
    required this.onPicked,
    required this.onNow,
  });

  final TextEditingController controller;
  final bool valid;
  final DateTime selected;
  final ValueChanged<String> onTyped;
  final void Function(int hour, int minute) onPicked;
  final VoidCallback onNow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          child: SizedBox(
            height: 34,
            child: TextField(
              controller: controller,
              onChanged: onTyped,
              textAlign: TextAlign.center,
              style: _mono.copyWith(fontSize: 13, color: AppColors.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'HH:mm',
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: valid ? AppColors.inputBorder : AppColors.danger,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            onPressed: onNow,
            icon: const Icon(Icons.update_rounded, size: 14),
            label: const Text('Now'),
          ),
        ),
        Divider(height: 1, color: AppColors.border),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: 48,
            itemBuilder: (_, i) {
              final hour = i ~/ 2, minute = (i % 2) * 30;
              final on = selected.hour == hour && selected.minute == minute;
              return InkWell(
                onTap: () => onPicked(hour, minute),
                child: Container(
                  height: 28,
                  alignment: Alignment.center,
                  color: on ? AppColors.accent.withValues(alpha: .16) : null,
                  child: Text(
                    '${_two(hour)}:${_two(minute)}',
                    style: _mono.copyWith(
                      fontSize: 12,
                      color: on ? AppColors.accent : AppColors.text,
                      fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
