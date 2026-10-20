import 'package:flutter/material.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 38,
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
              for (final tab in _tabs)
                _KubeLogView(
                  key: ValueKey(tab.id),
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
        height: 38,
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : null,
          border: Border(
            right: BorderSide(color: AppColors.border),
            top: BorderSide(
              color: selected ? AppColors.cyan : Colors.transparent,
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

const _controlHeight = 36.0;

class _KubeLogView extends StatefulWidget {
  const _KubeLogView({required this.onTitle, super.key});

  final ValueChanged<String> onTitle;

  @override
  State<_KubeLogView> createState() => _KubeLogViewState();
}

class _KubeLogViewState extends State<_KubeLogView> {
  final _manager = sl<ConnectionManager>();
  final _search = TextEditingController();
  final _scroll = ScrollController();

  String? _profileId;
  List<KubeNamespace> _namespaces = const [];
  List<KubePod> _pods = const [];
  String? _namespace;
  String? _pod; // null = all pods in the namespace
  /// A [_relativeRanges] key, or null for the absolute [_from]..[_to].
  String? _relative = _relativeRanges.keys.first;
  DateTime? _from;
  DateTime? _to;
  List<LogLine> _lines = const [];
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _search.dispose();
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
    setState(() {
      _profileId = id;
      _namespaces = const [];
      _namespace = null;
      _pods = const [];
      _pod = null;
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
    setState(() {
      _namespace = namespace;
      _pod = null;
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

  Future<void> _loadLogs() async {
    final namespace = _namespace;
    if (namespace == null) return;
    final output = await _run(
      kubeLogsCommand(
        namespace,
        _pod,
        since: _relativeRanges[_relative],
        sinceTime: _relative == null ? _from : null,
      ),
    );
    if (output == null) return;
    widget.onTitle('${_pod ?? 'all pods'} · $namespace');
    setState(() => _lines = parseLogLines(output));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
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
    // kubectl applies the start; an absolute end and the query cut here.
    final shown = filterLogLines(
      _lines,
      to: _relative == null ? _to : null,
      query: query,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
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
                  placeholder: '—',
                  enabled: !_loading && _namespaces.isNotEmpty,
                  noun: 'namespaces',
                  options: [
                    for (final ns in _namespaces)
                      (
                        value: ns.name,
                        label: ns.name,
                        subtitle: '${ns.status} · ${ns.age}',
                        leading: _NamespaceIcon(system: _isSystem(ns.name)),
                      ),
                  ],
                  selected: _namespace,
                  onSelected: _selectNamespace,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _SelectButton<String?>(
                  icon: Icons.view_in_ar_outlined,
                  label: 'Pod',
                  value: _pod ?? 'All pods',
                  leading: _selectedPod == null
                      ? null
                      : _PodDot(podHealth(_selectedPod!)),
                  placeholder: '—',
                  enabled: !_loading && _namespace != null,
                  noun: 'pods',
                  options: [
                    (
                      value: null,
                      label: 'All pods',
                      subtitle: _podSummary,
                      leading: Icon(
                        Icons.layers_outlined,
                        size: 18,
                        color: AppColors.cyan,
                      ),
                    ),
                    for (final pod in _pods)
                      (
                        value: pod.name,
                        label: pod.name,
                        subtitle: [
                          pod.status,
                          '${pod.ready} ready',
                          if (pod.restarts > 0)
                            '${pod.restarts} restart${pod.restarts == 1 ? '' : 's'}',
                          pod.age,
                        ].join(' · '),
                        leading: _PodDot(podHealth(pod)),
                      ),
                  ],
                  selected: _pod,
                  onSelected: (pod) => setState(() => _pod = pod),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _controlHeight,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: appFieldTextStyle(),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      hintText:
                          'Search…   error -timeout   "receive from"   '
                          'ERROR OR WARN',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppColors.muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              iconSize: 16,
                              onPressed: () => setState(() => _search.clear()),
                              icon: Icon(
                                Icons.close_rounded,
                                color: AppColors.muted,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _TimeRangeButton(
                label: _rangeLabel,
                ranges: _relativeRanges.keys.toList(),
                selected: _relative,
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
                  onPressed: _loading || _namespace == null ? null : _loadLogs,
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
            ],
          ),
          const SizedBox(height: 10),
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
                    error: _error,
                    shown: shown.length,
                    total: _lines.length,
                  ),
                  Expanded(child: _buildLines(shown, query.highlights)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLines(List<LogLine> shown, List<String> highlights) {
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
          itemBuilder: (_, i) =>
              _LogRow(line: shown[i], highlights: highlights, odd: i.isOdd),
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
  });

  final LogLine line;
  final List<String> highlights;
  final bool odd;

  static Color? _levelColor(LogLevel? level) => switch (level) {
    LogLevel.error => AppColors.danger,
    LogLevel.warn => AppColors.amber,
    LogLevel.info => AppColors.cyan,
    LogLevel.debug => AppColors.muted,
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final (:level, :message) = splitLogText(line.text);
    final color = _levelColor(level);
    final time = line.time;
    return Container(
      decoration: BoxDecoration(
        color: level == LogLevel.error
            ? AppColors.dangerTint.withValues(alpha: .35)
            : odd
            ? AppColors.surface.withValues(alpha: .45)
            : null,
        border: Border(
          left: BorderSide(color: color ?? Colors.transparent, width: 2),
          bottom: BorderSide(color: AppColors.border.withValues(alpha: .45)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 7, 16, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 152,
            child: Text(
              time == null ? '' : _formatStamp(time),
              style: _mono.copyWith(
                fontSize: 12,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
          ),
          SizedBox(
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
                          fontWeight: FontWeight.w700,
                          letterSpacing: .4,
                          color: color,
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: _highlight(
                  message,
                  highlights,
                  TextStyle(
                    color: AppColors.text,
                    backgroundColor: AppColors.amber.withValues(alpha: .28),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              style: _mono.copyWith(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.text.withValues(alpha: .92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [text] as spans with every case-insensitive occurrence of [terms] in
/// [style].
List<TextSpan> _highlight(String text, List<String> terms, TextStyle style) {
  if (terms.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    var start = -1, length = 0;
    for (final term in terms) {
      final j = lower.indexOf(term, i);
      if (j != -1 && (start == -1 || j < start))
        (start, length) = (j, term.length);
    }
    if (start == -1) break;
    if (start > i) spans.add(TextSpan(text: text.substring(i, start)));
    spans.add(
      TextSpan(text: text.substring(start, start + length), style: style),
    );
    i = start + length;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return spans;
}

/// Line count and the last error, above the log lines.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.error,
    required this.shown,
    required this.total,
  });

  final String? error;
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: error != null ? AppColors.dangerTint : AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (error != null) ...[
            Icon(
              Icons.error_outline_rounded,
              size: 14,
              color: AppColors.danger,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                error!,
                overflow: TextOverflow.ellipsis,
                style: portixMuted(12).copyWith(color: AppColors.danger),
              ),
            ),
          ] else
            const Spacer(),
          Text(
            shown == total ? '$total lines' : '$shown of $total lines',
            style: portixMuted(12),
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
    color: system ? AppColors.muted : AppColors.cyan,
  );
}

/// One choice in a [_SelectButton].
typedef _Option<T> = ({
  T value,
  String label,
  String? subtitle,
  Widget? leading,
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
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final picked = await showGeneralDialog<_Picked<T>>(
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
        final width = anchor.width.clamp(300.0, 460.0);
        final left = anchor.left.clamp(8.0, screen.width - width - 8);
        final top = anchor.bottom + 6;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: _PickerPanel<T>(
                options: options,
                selected: selected,
                noun: noun,
                maxHeight: (screen.height - top - 16).clamp(160.0, 460.0),
              ),
            ),
          ],
        );
      },
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
                  fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
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
    return Material(
      color: AppColors.surface,
      elevation: 12,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
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
                      itemBuilder: (_, i) => _PickerRow(
                        option: filtered[i],
                        selected: filtered[i].value == widget.selected,
                        onTap: () => _pick(filtered[i]),
                      ),
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
            ? AppColors.cyan.withValues(alpha: .12)
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
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected ? AppColors.cyan : AppColors.text,
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
                  Icon(Icons.check_rounded, size: 16, color: AppColors.cyan),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kibana-style time picker: quick relative ranges or an absolute range.
class _TimeRangeButton extends StatelessWidget {
  const _TimeRangeButton({
    required this.label,
    required this.ranges,
    required this.selected,
    required this.onRelative,
    required this.onAbsolute,
  });

  final String label;
  final List<String> ranges;
  final String? selected;
  final ValueChanged<String> onRelative;
  final VoidCallback onAbsolute;

  @override
  Widget build(BuildContext context) {
    Widget check(bool on) => SizedBox(
      width: 18,
      child: on
          ? Icon(Icons.check_rounded, size: 16, color: AppColors.cyan)
          : null,
    );
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text('Commonly used', style: portixMuted(11)),
        ),
        for (final range in ranges)
          MenuItemButton(
            leadingIcon: check(range == selected),
            onPressed: () => onRelative(range),
            child: Text(range),
          ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: check(selected == null),
          trailingIcon: const Icon(Icons.edit_calendar_outlined, size: 16),
          onPressed: onAbsolute,
          child: const Text('Absolute range…'),
        ),
      ],
      builder: (context, controller, _) => _ControlShell(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: AppColors.cyan),
            const SizedBox(width: 8),
            Text(
              label,
              style: appFieldTextStyle().copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more_rounded, size: 18, color: AppColors.muted),
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
                      color: AppColors.cyan.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.date_range_rounded,
                      size: 18,
                      color: AppColors.cyan,
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
          ? AppColors.cyan.withValues(alpha: .08)
          : AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: active ? AppColors.cyan : AppColors.border,
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
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: active ? AppColors.cyan : AppColors.muted,
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
                  fontWeight: FontWeight.w600,
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
                  color: on ? AppColors.cyan.withValues(alpha: .16) : null,
                  child: Text(
                    '${_two(hour)}:${_two(minute)}',
                    style: _mono.copyWith(
                      fontSize: 12,
                      color: on ? AppColors.cyan : AppColors.text,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w400,
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
