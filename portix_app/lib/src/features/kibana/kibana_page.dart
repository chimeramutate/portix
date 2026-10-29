import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart'
    as manager_profile;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart' as domain;
import 'package:portix/src/features/kubernetes/kubernetes_page.dart'
    show showAbsoluteRangeDialog, showAnchoredPanel;
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'package:portix/src/features/ssh_profiles/widget/gallery/profile_card.dart'
    show ProfileOsIcon;
import 'package:portix/src/features/ssh_sessions/widget/remote/auth_prompt_dialog.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/host_key_dialog.dart';

import 'kibana_query.dart';

const _controlHeight = 32.0;

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

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Oct 29 12:04:05.120" in local time, or [raw] when it isn't a date.
String _stamp(String raw) {
  final t = DateTime.tryParse(raw)?.toLocal();
  if (t == null) return raw;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${_months[t.month - 1]} ${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}';
}

Color? _levelColor(String? level) => switch (level) {
  'error' || 'err' || 'fatal' || 'critical' => AppColors.danger,
  'warn' || 'warning' => AppColors.amber,
  'info' || 'notice' => AppColors.cyan,
  'debug' || 'trace' => AppColors.muted,
  _ => null,
};

/// Kibana's Discover through a saved SSH server: curl on that server
/// searches Elasticsearch, so a cluster only reachable from inside the
/// network works without a tunnel.
class KibanaPage extends StatefulWidget {
  const KibanaPage({super.key});

  @override
  State<KibanaPage> createState() => _KibanaPageState();
}

class _KibanaPageState extends State<KibanaPage> {
  final _manager = sl<ConnectionManager>();
  final _url = TextEditingController(text: 'http://localhost:9200');
  final _index = TextEditingController(text: '*');
  final _query = TextEditingController();
  final _kibanaUrl = TextEditingController(text: 'http://localhost:5601');

  /// Straight to Kibana's API from this machine instead of curl on a
  /// saved server.
  bool _direct = false;

  /// The Kibana sign-in, in memory only: gone when Portix quits.
  KibanaAuth? _auth;
  String? _profileId;

  /// Kibana's data views once listed, and the one picked (direct only).
  List<KibanaDataView>? _dataViews;
  KibanaDataView? _dataView;
  String _timeField = '@timestamp';

  /// "Last 15 minutes" and the like, unless a histogram bar zoomed in to
  /// [_absolute].
  Duration _last = const Duration(minutes: 15);
  KibanaRange? _absolute;

  /// The range [_result] covers, for the histogram's axis.
  KibanaRange? _searched;
  KibanaResult? _result;

  /// Fields of [_result]'s documents with their counts and a sample value.
  Map<String, int> _fields = const {};
  Map<String, Object?> _samples = const {};

  /// Fields shown as table columns; empty shows Discover's "Summary".
  final _columns = <String>[];

  /// Widths the user dragged columns to; the rest use [_columnWidth].
  final _widths = <String, double>{};
  final _expanded = <int>{};
  final _filters = <KibanaFilter>[];

  /// Filters kept on the bar but left out of the query.
  final _disabled = <KibanaFilter>{};
  final _selection = GlobalKey<SelectionAreaState>();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _url.dispose();
    _index.dispose();
    _query.dispose();
    _kibanaUrl.dispose();
    super.dispose();
  }

  KibanaSearch _searchFor(KibanaRange range) => (
    index: _direct ? (_dataView?.pattern ?? '*') : _index.text,
    query: kibanaQueryWith(_query.text, [
      for (final f in _filters)
        if (!_disabled.contains(f)) f,
    ]),
    range: range,
    timeField: _timeField,
    size: 200,
  );

  Future<void> _search() async {
    final now = DateTime.now();
    final range = _absolute ?? (from: now.subtract(_last), to: now);
    if (_direct) return _searchDirect(range);
    final picked = context
        .read<SshWorkspaceBloc>()
        .state
        .profiles
        .where((p) => p.id == _profileId)
        .firstOrNull;
    if (picked == null) return;
    final profile = manager_profile.SshProfile.fromDomain(picked);
    final command = kibanaSearchCommand(_url.text, _searchFor(range));
    Future<(String?, String?)> attempt() async => (await _manager.execOnProfile(
      profile,
      command,
    )).fold((failure) => (null, '$failure'), (output) => (output, null));

    setState(() {
      _loading = true;
      _error = null;
    });
    var (output, error) = await attempt();
    if (error != null && mounted) {
      final hostKey = await resolveRefusedHostKey(context, _manager, profile);
      if (hostKey == true) (output, error) = await attempt();
      if (hostKey == false) error = 'Host key not trusted.';
    }
    while (error != null && mounted) {
      if (await resolveAuthPrompts(context, _manager, profile) != true) break;
      (output, error) = await attempt();
    }
    if (mounted) _show(output, error, range);
  }

  /// Runs [call] against Kibana; a 401 asks for the login once and runs
  /// it again. The error text when it failed.
  Future<(T?, String?)> _kibana<T>(Future<T> Function() call) async {
    for (var retried = false; ; retried = true) {
      try {
        return (await call(), null);
      } on FormatException catch (e) {
        if (retried || !e.message.startsWith('Unauthorized') || !mounted) {
          return (null, e.message);
        }
      } catch (e) {
        return (null, '$e');
      }
      setState(() => _loading = false); // not behind the dialog
      if (await _signIn() == null) return (null, 'Not signed in.');
      if (mounted) setState(() => _loading = true);
    }
  }

  Future<void> _searchDirect(KibanaRange range) async {
    if (_kibanaUrl.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final (output, error) = await _kibana(() async {
      final output = await kibanaDirectSearch(
        _kibanaUrl.text,
        _searchFor(range),
        _auth,
      );
      parseKibanaHits(output); // throws a 401 here, so _kibana can sign in
      return output;
    });
    if (mounted) _show(output, error, range);
  }

  /// Lists Kibana's data views for the picker, signing in when needed.
  Future<void> _loadDataViews() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final (views, error) = await _kibana(
      () => kibanaDataViews(_kibanaUrl.text, _auth),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
      if (views != null) _dataViews = views;
    });
  }

  Future<void> _pickDataView(KibanaDataView view) async {
    setState(() => _dataView = view);
    final (field, _) = await _kibana(
      () => kibanaTimeField(_kibanaUrl.text, view.id, _auth),
    );
    if (!mounted) return;
    setState(() => _timeField = field ?? '@timestamp');
    await _search();
  }

  /// Asks for the Kibana login; null when cancelled.
  Future<KibanaAuth?> _signIn() async {
    final auth = await showDialog<KibanaAuth>(
      context: context,
      builder: (_) => _SignInDialog(initial: _auth, url: _kibanaUrl.text),
    );
    if (auth != null && mounted) {
      setState(() {
        _auth = auth;
        _dataViews = null; // another user may see other views
      });
    }
    return auth;
  }

  void _setDirect(bool direct) {
    if (direct == _direct) return;
    setState(() {
      _direct = direct;
      _timeField = '@timestamp';
      _dataView = null;
      _result = null;
      _error = null;
      _expanded.clear();
    });
  }

  /// Drops any text selection before the rows change under it: a
  /// selection left on text that is rebuilt trips SelectionArea's
  /// "!debugNeedsLayout" assertion.
  void _clearSelection() =>
      _selection.currentState?.selectableRegion.clearSelection();

  void _show(String? output, String? error, KibanaRange range) {
    _clearSelection();
    setState(() {
      _loading = false;
      _expanded.clear();
      if (output == null) {
        _error = error;
        return;
      }
      try {
        final result = parseKibanaHits(output, timeField: _timeField);
        _result = result;
        _searched = range;
        _fields = kibanaFields(result.hits);
        final samples = <String, Object?>{};
        for (final hit in result.hits) {
          for (final MapEntry(:key, :value) in flattenSource(
            hit.source,
          ).entries) {
            samples[key] ??= value;
          }
        }
        _samples = samples;
      } on FormatException catch (e) {
        _error = e.message;
      }
    });
  }

  /// Adds [filter] (replacing the same field and value with the other
  /// sense) and searches again, like Discover's +/- buttons.
  void _addFilter(KibanaFilter filter) {
    setState(() {
      _filters
        ..removeWhere((f) => f.field == filter.field && f.value == filter.value)
        ..add(filter);
    });
    _search();
  }

  void _removeFilter(KibanaFilter filter) {
    setState(() {
      _filters.remove(filter);
      _disabled.remove(filter);
    });
    _search();
  }

  /// Drops [dragged] onto [target]'s place, like Discover's header drag:
  /// moving right lands after it, moving left before it.
  void _moveColumn(String dragged, String target) => setState(() {
    _clearSelection();
    final right = _columns.indexOf(dragged) < _columns.indexOf(target);
    _columns.remove(dragged);
    _columns.insert(_columns.indexOf(target) + (right ? 1 : 0), dragged);
  });

  void _resizeColumn(String field, double dx) => setState(
    () => _widths[field] = ((_widths[field] ?? _columnWidth) + dx).clamp(
      80.0,
      800.0,
    ),
  );

  void _toggleColumn(String field) {
    _clearSelection();
    setState(
      () => _columns.contains(field)
          ? _columns.remove(field)
          : _columns.add(field),
    );
  }

  Future<KibanaFilter?> _filterDialog([KibanaFilter? initial]) =>
      showDialog<KibanaFilter>(
        context: context,
        builder: (_) => _FilterDialog(
          samples: _samples,
          hits: _result?.hits ?? const [],
          initial: initial,
        ),
      );

  Future<void> _openAddFilter() async {
    final filter = await _filterDialog();
    if (filter != null) _addFilter(filter);
  }

  /// [next] in [old]'s place on the bar, enabled.
  void _replaceFilter(KibanaFilter old, KibanaFilter next) {
    setState(() {
      final at = _filters.indexOf(old);
      _disabled.remove(old);
      if (at < 0) return;
      _filters[at] = next;
    });
    _search();
  }

  Future<void> _editFilter(KibanaFilter old) async {
    final edited = await _filterDialog(old);
    if (edited != null && mounted) _replaceFilter(old, edited);
  }

  void _toggleDisabled(KibanaFilter filter) {
    setState(() => _disabled.remove(filter) ? null : _disabled.add(filter));
    _search();
  }

  /// The table as shown (time, then the columns or the summary) as
  /// tab-separated text, ready to paste into a sheet or a ticket.
  Future<void> _copyView(KibanaResult result) async {
    await Clipboard.setData(
      ClipboardData(text: kibanaTable(result.hits, _timeField, _columns)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Copied ${result.hits.length} rows as tab-separated text',
          ),
        ),
      );
  }

  void _setLast(Duration last) {
    setState(() {
      _last = last;
      _absolute = null;
    });
    _search();
  }

  void _zoom(KibanaRange range) {
    setState(() => _absolute = range);
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = context.select(
      (SshWorkspaceBloc bloc) => bloc.state.profiles,
    );
    final server = profiles.where((p) => p.id == _profileId).firstOrNull;
    final result = _result;
    final searched = _searched;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              _SourceToggle(direct: _direct, onChanged: _setDirect),
              const SizedBox(width: 8),
              if (_direct) ...[
                SizedBox(
                  width: 240,
                  child: _DataViewButton(
                    views: _dataViews,
                    picked: _dataView,
                    onLoad: _loadDataViews,
                    onPicked: _pickDataView,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Field(
                    label: 'Kibana',
                    controller: _kibanaUrl,
                    hint: 'https://kibana.example.com',
                    onSubmit: _search,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 170,
                  child: _Shell(
                    onTap: _signIn,
                    child: Row(
                      children: [
                        Icon(
                          _auth == null
                              ? Icons.login_rounded
                              : Icons.person_outline_rounded,
                          size: 16,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            switch (_auth) {
                              null => 'Sign in',
                              (apiKey: true, user: _, secret: _) => 'API key',
                              final auth => auth.user,
                            },
                            overflow: TextOverflow.ellipsis,
                            style: appFieldTextStyle().copyWith(
                              fontWeight: FontWeight.w500,
                              color: _auth == null
                                  ? AppColors.muted
                                  : AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: 220,
                  child: _ServerButton(
                    server: server,
                    profiles: profiles,
                    onPicked: (id) {
                      setState(() => _profileId = id);
                      _search();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _Field(
                    label: 'Elasticsearch',
                    controller: _url,
                    hint: 'http://localhost:9200',
                    onSubmit: _search,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _Field(
                    label: 'Index',
                    controller: _index,
                    hint: 'logs-*',
                    onSubmit: _search,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _query,
                  onSubmitted: (_) => _search(),
                  style: _mono.copyWith(fontSize: 13, color: AppColors.text),
                  decoration: _bare(
                    'Filter with Lucene, e.g. level:error AND service:api',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _openAddFilter,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.text,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add filter'),
              ),
              const SizedBox(width: 4),
              _TimeButton(
                last: _last,
                absolute: _absolute,
                onLast: _setLast,
                onAbsolute: _zoom,
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 30,
                child: FilledButton.icon(
                  onPressed: (!_direct && server == null) || _loading
                      ? null
                      : _search,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(_loading ? 'Searching…' : 'Refresh'),
                ),
              ),
            ],
          ),
        ),
        if (_filters.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final filter in _filters)
                  _FilterPill(
                    filter: filter,
                    disabled: _disabled.contains(filter),
                    onEdit: () => _editFilter(filter),
                    onToggleDisabled: () => _toggleDisabled(filter),
                    onRemove: () => _removeFilter(filter),
                    onInvert: () => _replaceFilter(filter, (
                      field: filter.field,
                      value: filter.value,
                      exclude: !filter.exclude,
                      label: filter.label,
                    )),
                  ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _filters.clear();
                      _disabled.clear();
                    });
                    _search();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.muted,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Clear all'),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 2,
          child: _loading ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        if (_error case final error?)
          _ErrorBanner(
            raw: error,
            onRetry: _search,
            onDismiss: () => setState(() => _error = null),
          ),
        Expanded(
          child: switch (result) {
            _ when !_direct && server == null => const _Empty(
              icon: Icons.dns_outlined,
              title: 'Pick a server to search from',
              hint:
                  'Its curl queries Elasticsearch, so internal clusters work '
                  'without a tunnel. Credentials come from ~/.netrc there.',
            ),
            null => _Empty(
              icon: Icons.manage_search_rounded,
              title: _loading
                  ? 'Searching…'
                  : _direct
                  ? 'Pick a data view, or search every index'
                  : 'Search ${server!.name}',
              hint: _direct
                  ? 'Goes from this machine straight to Kibana, no SSH '
                        'server. The sign-in stays in memory until Portix '
                        'quits.'
                  : 'Press Enter in any field to run the search.',
            ),
            final result => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 250,
                  child: _FieldList(
                    fields: _fields,
                    samples: _samples,
                    hits: result.hits,
                    columns: _columns,
                    onToggle: _toggleColumn,
                    onFilter: _addFilter,
                  ),
                ),
                VerticalDivider(width: 1, color: AppColors.border),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (searched != null)
                        _Histogram(
                          buckets: result.buckets,
                          range: searched,
                          onZoom: _zoom,
                        ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: Row(
                          children: [
                            Text(
                              'Documents (${result.total})',
                              style: portixTitle(13),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                [
                                  if (result.total > result.hits.length)
                                    'newest ${result.hits.length} shown',
                                  '${result.tookMs} ms',
                                ].join(' · '),
                                style: portixMuted(12),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: result.hits.isEmpty
                                  ? null
                                  : () => _copyView(result),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.text,
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(fontSize: 12.5),
                              ),
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: const Text('Copy view'),
                            ),
                          ],
                        ),
                      ),
                      _TableHeader(
                        timeField: _timeField,
                        columns: _columns,
                        widths: _widths,
                        onRemove: _toggleColumn,
                        onMove: _moveColumn,
                        onResize: _resizeColumn,
                      ),
                      Expanded(
                        child: result.hits.isEmpty
                            ? const _Empty(
                                icon: Icons.search_off_rounded,
                                title: 'No documents match',
                                hint:
                                    'Widen the time range or the index '
                                    'pattern, or clear the query.',
                              )
                            : SelectionArea(
                                key: _selection,
                                child: ListView.builder(
                                  itemCount: result.hits.length,
                                  itemBuilder: (context, i) => _HitRow(
                                    hit: result.hits[i],
                                    timeField: _timeField,
                                    columns: _columns,
                                    widths: _widths,
                                    odd: i.isOdd,
                                    expanded: _expanded.contains(i),
                                    onFilter: _addFilter,
                                    onToggleColumn: _toggleColumn,
                                    onTap: () {
                                      _clearSelection();
                                      setState(
                                        () => _expanded.contains(i)
                                            ? _expanded.remove(i)
                                            : _expanded.add(i),
                                      );
                                    },
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          },
        ),
      ],
    );
  }
}

InputDecoration _bare(String hint) => InputDecoration(
  isDense: true,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  contentPadding: EdgeInsets.zero,
  hintStyle: portixMuted(13),
  hintText: hint,
);

/// Where searches go: curl on a saved SSH server, or Kibana's API from
/// this machine.
class _SourceToggle extends StatelessWidget {
  const _SourceToggle({required this.direct, required this.onChanged});

  final bool direct;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, IconData icon, bool value) {
      final selected = direct == value;
      return Tooltip(
        message: value
            ? "Kibana's API, straight from this machine"
            : 'curl on a saved SSH server',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: _controlHeight - 6,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.surfaceCard : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected ? AppColors.text : AppColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected ? AppColors.text : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Search source',
      child: Container(
        height: _controlHeight,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment('SSH', Icons.dns_outlined, false),
            segment('Kibana', Icons.public_rounded, true),
          ],
        ),
      ),
    );
  }
}

/// The Kibana login: username and password, or an API key.
class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.initial, required this.url});

  final KibanaAuth? initial;
  final String url;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  late bool _apiKey = widget.initial?.apiKey ?? false;
  late final _user = TextEditingController(
    text: widget.initial?.apiKey == false ? widget.initial!.user : '',
  );
  final _secret = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _submit() {
    if (_secret.text.isEmpty || (!_apiKey && _user.text.trim().isEmpty)) {
      return;
    }
    Navigator.pop<KibanaAuth>(context, (
      apiKey: _apiKey,
      user: _apiKey ? '' : _user.text.trim(),
      secret: _secret.text,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sign in to Kibana'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.url.trim(), style: portixMuted(12)),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Username')),
              ButtonSegment(value: true, label: Text('API key')),
            ],
            selected: {_apiKey},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _apiKey = v.first),
          ),
          const SizedBox(height: 12),
          if (!_apiKey) ...[
            AppTextField(controller: _user, label: 'Username', hint: 'elastic'),
            const SizedBox(height: 10),
          ],
          AppTextField(
            controller: _secret,
            label: _apiKey ? 'API key (encoded)' : 'Password',
            obscureText: true,
          ),
          const SizedBox(height: 10),
          Text(
            'Kept in memory until Portix quits; never written to disk.',
            style: portixMuted(12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Sign in')),
    ],
  );
}

/// The bordered 32 px frame every header control sits in.
class _Shell extends StatelessWidget {
  const _Shell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
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
        child: child,
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onSubmit,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => _Shell(
    child: Row(
      children: [
        Text(label, style: portixMuted(12)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: (_) => onSubmit(),
            style: _mono.copyWith(fontSize: 12.5, color: AppColors.text),
            decoration: _bare(hint),
          ),
        ),
      ],
    ),
  );
}

class _ServerButton extends StatelessWidget {
  const _ServerButton({
    required this.server,
    required this.profiles,
    required this.onPicked,
  });

  final domain.SshProfile? server;
  final List<domain.SshProfile> profiles;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    alignmentOffset: const Offset(0, 4),
    menuChildren: [
      if (profiles.isEmpty)
        MenuItemButton(child: Text('No saved servers', style: portixMuted(13))),
      for (final p in profiles)
        MenuItemButton(
          leadingIcon: ProfileOsIcon(profile: p, size: 18),
          trailingIcon: p.id == server?.id
              ? Icon(Icons.check_rounded, size: 16, color: AppColors.accent)
              : null,
          onPressed: () => onPicked(p.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
            child: Text(p.name, overflow: TextOverflow.ellipsis),
          ),
        ),
    ],
    builder: (context, menu, _) => _Shell(
      onTap: () => menu.isOpen ? menu.close() : menu.open(),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: server == null
                ? Icon(Icons.dns_outlined, size: 16, color: AppColors.muted)
                : ProfileOsIcon(profile: server!, size: 18),
          ),
          const SizedBox(width: 8),
          Text('Server', style: portixMuted(12)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              server?.name ?? 'Pick one',
              overflow: TextOverflow.ellipsis,
              style: appFieldTextStyle().copyWith(
                fontWeight: FontWeight.w500,
                color: server == null ? AppColors.muted : AppColors.text,
              ),
            ),
          ),
          Icon(Icons.unfold_more_rounded, size: 16, color: AppColors.muted),
        ],
      ),
    ),
  );
}

/// "1.2k", "48k" for long counts.
String _size(int n) => n >= 10000
    ? '${n ~/ 1000}k'
    : n >= 1000
    ? '${(n / 1000).toStringAsFixed(1)}k'
    : '$n';

String _shown(Object? value) => switch (value) {
  null => '-',
  final String s => s,
  _ => jsonEncode(value),
};

/// "HH:mm" (with seconds when [seconds]), or "MMM dd HH:mm" for ranges
/// longer than a day.
String _axisLabel(DateTime t, {required bool days, bool seconds = false}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final clock =
      '${two(t.hour)}:${two(t.minute)}'
      '${seconds ? ':${two(t.second)}' : ''}';
  return days ? '${_months[t.month - 1]} ${two(t.day)} $clock' : clock;
}

/// Discover's "Commonly used" ranges, named as Kibana names them.
const _quickRanges = [
  (Duration(minutes: 15), '15 minutes'),
  (Duration(hours: 1), '1 hour'),
  (Duration(hours: 4), '4 hours'),
  (Duration(hours: 24), '24 hours'),
  (Duration(days: 7), '7 days'),
  (Duration(days: 30), '30 days'),
];

const _units = [
  (Duration(seconds: 1), 'second'),
  (Duration(minutes: 1), 'minute'),
  (Duration(hours: 1), 'hour'),
  (Duration(days: 1), 'day'),
  (Duration(days: 7), 'week'),
];

/// The largest unit [last] is a whole number of.
(Duration, String) _unitOf(Duration last) => _units.reversed.firstWhere(
  (u) => last.inSeconds % u.$1.inSeconds == 0,
  orElse: () => _units.first,
);

/// "Last 15 minutes"; a common range keeps Kibana's name ("24 hours").
String _lastLabel(Duration last) {
  final common = _quickRanges.where((r) => r.$1 == last).firstOrNull;
  if (common != null) return 'Last ${common.$2}';
  final (unit, name) = _unitOf(last);
  final n = last.inSeconds ~/ unit.inSeconds;
  return 'Last $n $name${n == 1 ? '' : 's'}';
}

/// Discover's time picker button; opens [_TimePanel] under itself.
class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.last,
    required this.absolute,
    required this.onLast,
    required this.onAbsolute,
  });

  final Duration last;
  final KibanaRange? absolute;
  final ValueChanged<Duration> onLast;
  final ValueChanged<KibanaRange> onAbsolute;

  Future<void> _pickAbsolute(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showAbsoluteRangeDialog(
      context,
      from: absolute?.from ?? now.subtract(last),
      to: absolute?.to ?? now,
    );
    if (picked != null) onAbsolute((from: picked.$1, to: picked.$2));
  }

  @override
  Widget build(BuildContext context) {
    final range = absolute;
    final label = range == null
        ? _lastLabel(last)
        : '${_stamp(range.from.toIso8601String()).substring(0, 12)} → '
              '${_stamp(range.to.toIso8601String()).substring(0, 12)}';
    return SizedBox(
      width: 230,
      child: _Shell(
        onTap: () async {
          final picked = await showAnchoredPanel<Object>(
            context,
            label: 'Time range',
            width: (_) => 360,
            builder: (_) => _TimePanel(last: last, absolute: range),
          );
          if (!context.mounted) return;
          switch (picked) {
            case final Duration last:
              onLast(last);
            case #absolute:
              await _pickAbsolute(context);
          }
        },
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: AppColors.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: appFieldTextStyle().copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Kibana's time popover, laid out like the Kubernetes logs' one: quick
/// select ("Last N units"), the commonly used ranges, and the absolute
/// range. Pops a [Duration], or `#absolute` to pick dates.
class _TimePanel extends StatefulWidget {
  const _TimePanel({required this.last, required this.absolute});

  final Duration last;
  final KibanaRange? absolute;

  @override
  State<_TimePanel> createState() => _TimePanelState();
}

class _TimePanelState extends State<_TimePanel> {
  late var _unit = _unitOf(widget.last);
  late final _count = TextEditingController(
    text: '${widget.last.inSeconds ~/ _unit.$1.inSeconds}',
  );

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  int? get _n => switch (int.tryParse(_count.text.trim())) {
    final n? when n > 0 => n,
    _ => null,
  };

  void _apply() {
    if (_n case final n?) Navigator.pop(context, _unit.$1 * n);
  }

  Widget _heading(IconData icon, String text) => Padding(
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

  @override
  Widget build(BuildContext context) {
    final absolute = widget.absolute;
    final n = _n;
    final field = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
    return Material(
      color: AppColors.surface,
      elevation: 12,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(Icons.tune_rounded, 'Quick select'),
                Row(
                  children: [
                    Text('Last', style: appFieldTextStyle()),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: _count,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: appFieldTextStyle(),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _apply(),
                        decoration: field,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<(Duration, String)>(
                        initialValue: _unit,
                        isDense: true,
                        isExpanded: true,
                        style: appFieldTextStyle(),
                        decoration: field,
                        items: [
                          for (final unit in _units)
                            DropdownMenuItem(
                              value: unit,
                              child: Text('${unit.$2}s'),
                            ),
                        ],
                        onChanged: (unit) =>
                            setState(() => _unit = unit ?? _unit),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: n == null ? null : _apply,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  n == null
                      ? 'Enter a whole number above 0.'
                      : 'From ${_stamp(DateTime.now().subtract(_unit.$1 * n).toIso8601String()).substring(0, 15)} to now',
                  style: portixMuted(11),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(Icons.bolt_rounded, 'Commonly used'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (range, name) in _quickRanges)
                      _RangeChip(
                        label: name,
                        selected: absolute == null && range == widget.last,
                        onTap: () => Navigator.pop(context, range),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Material(
            color: absolute != null
                ? AppColors.accent.withValues(alpha: .08)
                : Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context, #absolute),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_calendar_outlined,
                      size: 18,
                      color: absolute != null
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
                              color: absolute != null
                                  ? AppColors.accent
                                  : AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            absolute == null
                                ? 'Pick a start and end date & time'
                                : '${_stamp(absolute.from.toIso8601String())}'
                                      ' → ${_stamp(absolute.to.toIso8601String())}',
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
        ],
      ),
    );
  }
}

/// A range choice: accent outline and tint when selected, as in the
/// Kubernetes logs' time panel.
class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? AppColors.accent.withValues(alpha: .14)
        : AppColors.surfaceDark,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: selected ? AppColors.accent : AppColors.inputBorder,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? AppColors.accent : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _Operator {
  isValue('is'),
  isNot('is not'),
  isOneOf('is one of'),
  isNotOneOf('is not one of'),
  exists('exists'),
  doesNotExist('does not exist');

  const _Operator(this.label);

  final String label;

  bool get needsValue => this != exists && this != doesNotExist;
  bool get many => this == isOneOf || this == isNotOneOf;

  /// The operator [filter] was made with.
  static _Operator of(KibanaFilter filter) => switch (filter) {
    (value: null, exclude: true, field: _, label: _) => exists,
    (value: null, exclude: false, field: _, label: _) => doesNotExist,
    (value: List _, exclude: true, field: _, label: _) => isNotOneOf,
    (value: List _, exclude: false, field: _, label: _) => isOneOf,
    (exclude: true, value: _, field: _, label: _) => isNot,
    _ => isValue,
  };
}

/// An input matching [AppTextField]: muted label above, 32 px box.
Widget _labeled(String label, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Text(label, style: appFieldLabelStyle()),
    const SizedBox(height: 6),
    SizedBox(height: 32, child: child),
  ],
);

/// The theme's input look, plus the disabled border it lacks.
InputDecoration _input(String hint, {Widget? suffix}) => InputDecoration(
  hintText: hint,
  suffixIcon: suffix,
  suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  disabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: AppColors.border),
  ),
);

/// Kibana's filter editor: a field, an operator, the value(s) and an
/// optional label for the pill. With [initial] it edits that filter.
class _FilterDialog extends StatefulWidget {
  const _FilterDialog({
    required this.samples,
    required this.hits,
    this.initial,
  });

  /// Fields of the shown documents with a sample value each, offered as
  /// you type; any name works.
  final Map<String, Object?> samples;
  final List<KibanaHit> hits;
  final KibanaFilter? initial;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late final _fieldText = TextEditingController(
    text: widget.initial?.field ?? '',
  );
  final _fieldFocus = FocusNode();
  late var _operator = widget.initial == null
      ? _Operator.isValue
      : _Operator.of(widget.initial!);
  late final _value = TextEditingController(
    text: switch (widget.initial?.value) {
      null => '',
      final List<Object?> values => values.map(_shown).join(', '),
      final value => _shown(value),
    },
  );
  final _valueFocus = FocusNode();

  /// The values before the one being typed, for "is one of".
  String _prefix = '';
  late final _label = TextEditingController(text: widget.initial?.label ?? '');

  @override
  void dispose() {
    _fieldText.dispose();
    _fieldFocus.dispose();
    _value.dispose();
    _valueFocus.dispose();
    _label.dispose();
    super.dispose();
  }

  String get _field => _fieldText.text.trim();

  List<String> get _values => [
    for (final v in _value.text.split(','))
      if (v.trim().isNotEmpty) v.trim(),
  ];

  KibanaFilter? get _filter {
    final field = _field;
    if (field.isEmpty) return null;
    if (_operator.needsValue && _values.isEmpty) return null;
    final label = _label.text.trim().isEmpty ? null : _label.text.trim();
    return switch (_operator) {
      _Operator.isValue || _Operator.isNot => (
        field: field,
        value: _value.text.trim(),
        exclude: _operator == _Operator.isNot,
        label: label,
      ),
      _Operator.isOneOf || _Operator.isNotOneOf => (
        field: field,
        value: _values,
        exclude: _operator == _Operator.isNotOneOf,
        label: label,
      ),
      _Operator.exists || _Operator.doesNotExist => (
        field: field,
        value: null,
        exclude: _operator == _Operator.exists,
        label: label,
      ),
    };
  }

  /// The Material options popup, in the app's popup look.
  Widget _options(
    BuildContext context,
    AutocompleteOnSelected<String> onSelected,
    Iterable<String> options,
  ) => Align(
    alignment: Alignment.topLeft,
    child: Material(
      color: AppColors.surface,
      elevation: 12,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          children: [
            for (final option in options)
              InkWell(
                onTap: () => onSelected(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      if (widget.samples.containsKey(option)) ...[
                        Icon(
                          _fieldType(widget.samples[option]).$1,
                          size: 14,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          option,
                          overflow: TextOverflow.ellipsis,
                          style: appFieldTextStyle(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final suggestions = [
      for (final top in kibanaTopValues(widget.hits, _field, n: 20))
        if (top.value != null) _shown(top.value),
    ];
    final editing = widget.initial != null;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Text(editing ? 'Edit filter' : 'Add filter'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: _labeled(
                    'Field',
                    Autocomplete<String>(
                      textEditingController: _fieldText,
                      focusNode: _fieldFocus,
                      optionsBuilder: (text) => [
                        for (final f in widget.samples.keys)
                          if (f.toLowerCase().contains(text.text.toLowerCase()))
                            f,
                      ],
                      optionsViewBuilder: _options,
                      onSelected: (_) {
                        setState(() {});
                        _valueFocus.requestFocus();
                      },
                      fieldViewBuilder: (context, controller, focus, submit) =>
                          TextField(
                            controller: controller,
                            focusNode: focus,
                            autofocus: !editing,
                            style: appFieldTextStyle(),
                            onChanged: (_) => setState(() {}),
                            decoration: _input(
                              'Select a field',
                              suffix: Icon(
                                Icons.unfold_more_rounded,
                                size: 16,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: _labeled(
                    'Operator',
                    MenuAnchor(
                      alignmentOffset: const Offset(0, 4),
                      menuChildren: [
                        for (final op in _Operator.values)
                          MenuItemButton(
                            trailingIcon: op == _operator
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: AppColors.accent,
                                  )
                                : null,
                            onPressed: () => setState(() => _operator = op),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 150),
                              child: Text(op.label),
                            ),
                          ),
                      ],
                      builder: (context, menu, _) => Material(
                        color: AppColors.surfaceDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: menu.isOpen
                                ? AppColors.accent
                                : AppColors.inputBorder,
                            width: menu.isOpen ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => menu.isOpen ? menu.close() : menu.open(),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10, right: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _operator.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: appFieldTextStyle(),
                                  ),
                                ),
                                Icon(
                                  Icons.unfold_more_rounded,
                                  size: 16,
                                  color: AppColors.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: _labeled(
                    _operator.many ? 'Values, comma separated' : 'Value',
                    !_operator.needsValue
                        ? TextField(
                            enabled: false,
                            decoration: _input('No value needed'),
                          )
                        : Autocomplete<String>(
                            textEditingController: _value,
                            focusNode: _valueFocus,
                            optionsViewBuilder: _options,
                            optionsBuilder: (text) {
                              final typed = _operator.many
                                  ? text.text.split(',').last.trim()
                                  : text.text.trim();
                              return [
                                for (final v in suggestions)
                                  if (v.toLowerCase().contains(
                                    typed.toLowerCase(),
                                  ))
                                    v,
                              ];
                            },
                            // Autocomplete puts just the option in the
                            // field; "is one of" puts back the values before.
                            onSelected: (v) => setState(() {
                              final text = _prefix.isEmpty ? v : '$_prefix, $v';
                              _value.value = TextEditingValue(
                                text: text,
                                selection: TextSelection.collapsed(
                                  offset: text.length,
                                ),
                              );
                            }),
                            fieldViewBuilder:
                                (context, controller, focus, submit) =>
                                    TextField(
                                      controller: controller,
                                      focusNode: focus,
                                      enabled: _field.isNotEmpty,
                                      style: appFieldTextStyle(),
                                      onChanged: (text) => setState(() {
                                        final cut = text.lastIndexOf(',');
                                        _prefix = !_operator.many || cut < 0
                                            ? ''
                                            : text.substring(0, cut).trim();
                                      }),
                                      decoration: _input(
                                        _field.isEmpty
                                            ? 'Select a field first'
                                            : _operator.many
                                            ? 'e.g. web, api'
                                            : 'Enter a value',
                                      ),
                                    ),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _label,
              label: 'Custom label (optional)',
              hint: 'Shown on the pill instead of the filter',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.code_rounded,
                      size: 15,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: filter == null
                        ? Text(
                            'Pick a field and a value to see the query.',
                            style: portixMuted(12),
                          )
                        : SelectableText(
                            kibanaClause(filter),
                            style: _mono.copyWith(
                              fontSize: 12,
                              color: AppColors.text,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Read again: typing the label doesn't rebuild the dialog.
          onPressed: filter == null
              ? null
              : () => Navigator.pop(context, _filter),
          child: Text(editing ? 'Save filter' : 'Add filter'),
        ),
      ],
    );
  }
}

/// Kibana's data view picker; lists them from Kibana on first open.
class _DataViewButton extends StatelessWidget {
  const _DataViewButton({
    required this.views,
    required this.picked,
    required this.onLoad,
    required this.onPicked,
  });

  final List<KibanaDataView>? views;
  final KibanaDataView? picked;
  final Future<void> Function() onLoad;
  final ValueChanged<KibanaDataView> onPicked;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    alignmentOffset: const Offset(0, 4),
    menuChildren: [
      if (views case final views? when views.isEmpty)
        MenuItemButton(child: Text('No data views', style: portixMuted(13))),
      for (final view in views ?? const <KibanaDataView>[])
        MenuItemButton(
          trailingIcon: view.id == picked?.id
              ? Icon(Icons.check_rounded, size: 16, color: AppColors.accent)
              : null,
          onPressed: () => onPicked(view),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(view.name, overflow: TextOverflow.ellipsis),
                if (view.name != view.pattern)
                  Text(view.pattern, style: portixMuted(11)),
              ],
            ),
          ),
        ),
    ],
    builder: (context, menu, _) => _Shell(
      onTap: () async {
        if (menu.isOpen) return menu.close();
        if (views == null) await onLoad();
        if (context.mounted) menu.open();
      },
      child: Row(
        children: [
          Text('Data view', style: portixMuted(12)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              picked?.name ?? 'All indices (*)',
              overflow: TextOverflow.ellipsis,
              style: appFieldTextStyle().copyWith(
                fontWeight: FontWeight.w500,
                color: picked == null ? AppColors.muted : AppColors.text,
              ),
            ),
          ),
          Icon(Icons.unfold_more_rounded, size: 16, color: AppColors.muted),
        ],
      ),
    ),
  );
}

/// Documents per interval over the searched range, like Discover's chart;
/// clicking a bar zooms the time range to it.
class _Histogram extends StatelessWidget {
  const _Histogram({
    required this.buckets,
    required this.range,
    required this.onZoom,
  });

  final List<({DateTime start, int count})> buckets;
  final KibanaRange range;
  final ValueChanged<KibanaRange> onZoom;

  @override
  Widget build(BuildContext context) {
    final step = kibanaInterval(range);
    final peak = buckets.fold(0, (m, b) => b.count > m ? b.count : m);
    final days = range.to.difference(range.from) > const Duration(days: 1);
    final seconds = step < const Duration(minutes: 1);
    final axis = _mono.copyWith(fontSize: 10.5, color: AppColors.muted);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 84,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 36,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$peak', style: axis),
                      Text('0', style: axis),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final b in buckets)
                          Expanded(
                            child: Tooltip(
                              message:
                                  '${_axisLabel(b.start, days: days, seconds: seconds)}'
                                  ' · ${b.count} documents',
                              waitDuration: Duration.zero,
                              child: InkWell(
                                onTap: b.count == 0
                                    ? null
                                    : () => onZoom((
                                        from: b.start,
                                        to: b.start.add(step),
                                      )),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: peak == 0
                                        ? 0
                                        : b.count / peak,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      color: AppColors.cyan.withValues(
                                        alpha: .75,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i <= 4; i++)
                  Text(
                    _axisLabel(
                      range.from.add(range.to.difference(range.from) * (i / 4)),
                      days: days,
                    ),
                    style: axis,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_stamp(range.from.toIso8601String())} – '
            '${_stamp(range.to.toIso8601String())} '
            '(interval: ${kibanaIntervalLabel(step)})',
            textAlign: TextAlign.center,
            style: portixMuted(12),
          ),
        ],
      ),
    );
  }
}

/// What kind of value a field holds, for its badge in the field list.
(IconData, String) _fieldType(Object? value) => switch (value) {
  num _ => (Icons.tag_rounded, 'number'),
  bool _ => (Icons.toggle_on_outlined, 'boolean'),
  List _ => (Icons.data_array_rounded, 'array'),
  final String s when s.length >= 10 && DateTime.tryParse(s) != null => (
    Icons.calendar_today_outlined,
    'date',
  ),
  _ => (Icons.text_fields_rounded, 'text'),
};

/// Discover's field sidebar: search the fields of the shown documents; a
/// click shows a field's top values (filter for or out of each), the +
/// adds it as a table column.
class _FieldList extends StatefulWidget {
  const _FieldList({
    required this.fields,
    required this.samples,
    required this.hits,
    required this.columns,
    required this.onToggle,
    required this.onFilter,
  });

  final Map<String, int> fields;
  final Map<String, Object?> samples;
  final List<KibanaHit> hits;
  final List<String> columns;
  final ValueChanged<String> onToggle;
  final ValueChanged<KibanaFilter> onFilter;

  @override
  State<_FieldList> createState() => _FieldListState();
}

class _FieldListState extends State<_FieldList> {
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

  Widget _row(String field) {
    final selected = widget.columns.contains(field);
    final (icon, type) = _fieldType(widget.samples[field]);
    final count = widget.fields[field] ?? 0;
    return MenuAnchor(
      alignmentOffset: const Offset(250, -28),
      menuChildren: [
        _FieldDetails(
          field: field,
          icon: icon,
          type: type,
          present: count,
          hits: widget.hits,
          column: selected,
          onToggle: () => widget.onToggle(field),
          onFilter: widget.onFilter,
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: '$type · in $count of ${widget.hits.length} documents',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: Container(
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsets.fromLTRB(12, 3, 4, 3),
            color: menu.isOpen
                ? AppColors.selected
                : selected
                ? AppColors.selectedSoft
                : null,
            child: Row(
              children: [
                Icon(icon, size: 14, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    field,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppColors.text),
                  ),
                ),
                IconButton(
                  tooltip: selected ? 'Remove column' : 'Add column',
                  visualDensity: VisualDensity.compact,
                  iconSize: 14,
                  color: selected ? AppColors.text : AppColors.muted,
                  onPressed: () => widget.onToggle(field),
                  icon: Icon(
                    selected ? Icons.remove_rounded : Icons.add_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String label, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: portixLabel(12))),
        Text('$count', style: portixMuted(12)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final available = [
      for (final field in widget.fields.keys)
        if (!widget.columns.contains(field) &&
            field.toLowerCase().contains(query))
          field,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _Shell(
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 15, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _search,
                    style: appFieldTextStyle(),
                    decoration: _bare('Search field names'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (widget.columns.isNotEmpty) ...[
                _heading('Selected fields', widget.columns.length),
                for (final field in widget.columns) _row(field),
              ],
              _heading('Available fields', available.length),
              for (final field in available) _row(field),
            ],
          ),
        ),
      ],
    );
  }
}

/// A field's popover: its top values in the shown documents with a bar
/// and filter for / out buttons each, and the column toggle.
class _FieldDetails extends StatelessWidget {
  const _FieldDetails({
    required this.field,
    required this.icon,
    required this.type,
    required this.present,
    required this.hits,
    required this.column,
    required this.onToggle,
    required this.onFilter,
  });

  final String field;
  final IconData icon;
  final String type;

  /// Documents that have [field].
  final int present;
  final List<KibanaHit> hits;
  final bool column;
  final VoidCallback onToggle;
  final ValueChanged<KibanaFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final top = kibanaTopValues(hits, field);
    void close() => MenuController.maybeOf(context)?.close();
    Widget filterButton(Object? value, bool exclude) => IconButton(
      tooltip: exclude ? 'Filter out value' : 'Filter for value',
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      color: AppColors.muted,
      onPressed: () {
        close();
        onFilter((field: field, value: value, exclude: exclude, label: null));
      },
      icon: Icon(
        exclude ? Icons.remove_circle_outline : Icons.add_circle_outline,
      ),
    );
    return SizedBox(
      width: 340,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    field,
                    style: portixTitle(13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Filter for field present',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  color: AppColors.muted,
                  onPressed: () {
                    close();
                    onFilter((
                      field: field,
                      value: null,
                      exclude: true,
                      label: null,
                    ));
                  },
                  icon: const Icon(Icons.filter_list_rounded),
                ),
              ],
            ),
            Divider(height: 16, color: AppColors.border),
            Text('Top values', style: portixLabel(12)),
            const SizedBox(height: 8),
            for (final (:value, :count) in top)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _shown(value),
                                  overflow: TextOverflow.ellipsis,
                                  style: _mono.copyWith(
                                    fontSize: 12,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(count * 100 / hits.length).toStringAsFixed(1)}%',
                                style: portixMuted(12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: count / hits.length,
                              minHeight: 4,
                              color: AppColors.cyan,
                              backgroundColor: AppColors.border,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (value is! List) ...[
                      filterButton(value, false),
                      filterButton(value, true),
                    ],
                  ],
                ),
              ),
            Text(
              'Calculated from ${hits.length} records'
              '${present < hits.length ? '; $present have this field' : ''}.',
              style: portixMuted(12),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  close();
                  onToggle();
                },
                icon: Icon(
                  column ? Icons.remove_rounded : Icons.view_column_outlined,
                  size: 16,
                ),
                label: Text(column ? 'Remove column' : 'Add as column'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Column titles over the documents: the time field (newest first), then
/// the picked columns or "Summary".
class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.timeField,
    required this.columns,
    required this.widths,
    required this.onRemove,
    required this.onMove,
    required this.onResize,
  });

  final String timeField;
  final List<String> columns;
  final Map<String, double> widths;
  final ValueChanged<String> onRemove;

  /// The dragged column onto another one.
  final void Function(String dragged, String target) onMove;
  final void Function(String field, double dx) onResize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.text,
    );
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 30, right: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 172,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    timeField,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_downward_rounded,
                  size: 13,
                  color: AppColors.muted,
                  semanticLabel: 'newest first',
                ),
              ],
            ),
          ),
          if (columns.isEmpty)
            Text('Summary', style: style)
          else
            for (final field in columns)
              _columnCell(
                columns,
                widths,
                field,
                DragTarget<String>(
                  onWillAcceptWithDetails: (d) => d.data != field,
                  onAcceptWithDetails: (d) => onMove(d.data, field),
                  builder: (context, incoming, _) => Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: incoming.isEmpty
                              ? Colors.transparent
                              : AppColors.accent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Draggable<String>(
                            data: field,
                            axis: Axis.horizontal,
                            feedback: Material(
                              color: AppColors.surfaceCard,
                              borderRadius: BorderRadius.circular(6),
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Text(field, style: style),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: .4,
                              child: Text(field, style: style),
                            ),
                            child: Tooltip(
                              message: 'Drag to move the column',
                              waitDuration: const Duration(milliseconds: 600),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Text(
                                  field,
                                  overflow: TextOverflow.ellipsis,
                                  style: style,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove column',
                          visualDensity: VisualDensity.compact,
                          iconSize: 13,
                          color: AppColors.muted,
                          onPressed: () => onRemove(field),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        // The last column fills the rest, so only the
                        // others have an edge to drag.
                        if (field != columns.last)
                          MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (d) =>
                                  onResize(field, d.delta.dx),
                              child: SizedBox(
                                key: ValueKey('resize $field'),
                                width: 10,
                                height: 32,
                                child: Center(
                                  child: Container(
                                    width: 1,
                                    height: 16,
                                    color: AppColors.inputBorder,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// A table cell: the whole value, wrapped, with a copy button right after
/// it on hover.
class _CopyableCell extends StatefulWidget {
  const _CopyableCell({
    required this.field,
    required this.value,
    required this.style,
  });

  final String field;
  final Object? value;
  final TextStyle style;

  @override
  State<_CopyableCell> createState() => _CopyableCellState();
}

class _CopyableCellState extends State<_CopyableCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = _shown(widget.value);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: Text(text, style: widget.style)),
          if (widget.value != null)
            SelectionContainer.disabled(
              child: Opacity(
                // Kept in the tree so Tab still reaches it.
                opacity: _hovered ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, top: 1),
                  child: SizedBox.square(
                    dimension: 22,
                    child: IconButton(
                      tooltip: 'Copy ${widget.field}',
                      padding: EdgeInsets.zero,
                      iconSize: 13,
                      color: AppColors.muted,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(content: Text('Copied ${widget.field}')),
                          );
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _columnWidth = 220.0;

/// [field]'s cell in the header and every row: the last column fills what
/// is left, as in Discover; the others keep their (dragged) width.
// ponytail: no horizontal scroll, so columns wider than the view clip;
// add a shared horizontal scroll if people keep many wide columns.
Widget _columnCell(
  List<String> columns,
  Map<String, double> widths,
  String field,
  Widget child,
) => field == columns.last
    ? Expanded(child: child)
    : SizedBox(width: widths[field] ?? _columnWidth, child: child);

class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.hit,
    required this.timeField,
    required this.columns,
    required this.widths,
    required this.odd,
    required this.expanded,
    required this.onTap,
    required this.onFilter,
    required this.onToggleColumn,
  });

  final KibanaHit hit;
  final String timeField;
  final List<String> columns;
  final Map<String, double> widths;
  final bool odd;
  final bool expanded;
  final VoidCallback onTap;
  final ValueChanged<KibanaFilter> onFilter;
  final ValueChanged<String> onToggleColumn;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(kibanaLevel(hit.source));
    final isError = color == AppColors.danger;
    final fields = flattenSource(hit.source);
    final style = _mono.copyWith(
      fontSize: 12.5,
      height: 1.6,
      color: AppColors.text,
    );
    return Container(
      decoration: BoxDecoration(
        color: isError
            ? AppColors.dangerTint.withValues(alpha: .35)
            : odd
            ? AppColors.surface.withValues(alpha: .45)
            : null,
        border: Border(
          left: BorderSide(color: color ?? Colors.transparent, width: 2),
          bottom: BorderSide(color: AppColors.border.withValues(alpha: .45)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 16, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The only toggle: a press on the text starts a selection.
                SelectionContainer.disabled(
                  child: SizedBox(
                    width: 16,
                    height: 20,
                    child: IconButton(
                      tooltip: expanded
                          ? 'Collapse document'
                          : 'Expand document',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 16,
                      color: AppColors.muted,
                      onPressed: onTap,
                      icon: Icon(
                        expanded
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 172,
                  child: Text(
                    _stamp(hit.time),
                    style: style.copyWith(fontSize: 12, color: AppColors.muted),
                  ),
                ),
                if (columns.isEmpty)
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          for (final MapEntry(:key, :value) in fields.entries)
                            if (key != timeField) ...[
                              TextSpan(
                                text: '$key ',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextSpan(text: '${_shown(value)}  '),
                            ],
                        ],
                      ),
                      maxLines: expanded ? null : 3,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: style,
                    ),
                  )
                else
                  for (final field in columns)
                    _columnCell(
                      columns,
                      widths,
                      field,
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _CopyableCell(
                          field: field,
                          value: fields[field],
                          style: fields[field] == null
                              ? style.copyWith(color: AppColors.muted)
                              : style,
                        ),
                      ),
                    ),
              ],
            ),
          ),

          if (expanded)
            _DocView(
              source: hit.source,
              columns: columns,
              onFilter: onFilter,
              onToggleColumn: onToggleColumn,
            ),
        ],
      ),
    );
  }
}

/// An opened document, as Discover shows it: a field table with
/// filter-for / filter-out buttons per value, or the raw JSON.
class _DocView extends StatefulWidget {
  const _DocView({
    required this.source,
    required this.columns,
    required this.onFilter,
    required this.onToggleColumn,
  });

  final Map<String, dynamic> source;
  final List<String> columns;
  final ValueChanged<KibanaFilter> onFilter;
  final ValueChanged<String> onToggleColumn;

  @override
  State<_DocView> createState() => _DocViewState();
}

class _DocViewState extends State<_DocView> {
  bool _json = false;

  @override
  Widget build(BuildContext context) {
    final json = const JsonEncoder.withIndent('  ').convert(widget.source);
    Widget tab(String label, bool selected, VoidCallback onTap) => TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? AppColors.text : AppColors.muted,
        backgroundColor: selected ? AppColors.surface : null,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
        ),
      ),
      child: Text(label),
    );
    final valueStyle = _mono.copyWith(
      fontSize: 12,
      height: 1.5,
      color: AppColors.text,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 0, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionContainer.disabled(
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  tab('Table', !_json, () => setState(() => _json = false)),
                  const SizedBox(width: 2),
                  tab('JSON', _json, () => setState(() => _json = true)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy JSON',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    color: AppColors.muted,
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: json)),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (_json)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(json, style: valueStyle),
            )
          else
            for (final MapEntry(key: field, :value) in flattenSource(
              widget.source,
            ).entries)
              _FieldRow(
                field: field,
                value: value,
                style: valueStyle,
                column: widget.columns.contains(field),
                onToggleColumn: () => widget.onToggleColumn(field),
                onFilter: value is List
                    ? null
                    : (exclude) => widget.onFilter((
                        field: field,
                        value: value,
                        exclude: exclude,
                        label: null,
                      )),
              ),
        ],
      ),
    );
  }
}

/// One field of [_DocView]'s table; the filter buttons show on hover or
/// focus so the values stay readable.
class _FieldRow extends StatefulWidget {
  const _FieldRow({
    required this.field,
    required this.value,
    required this.style,
    required this.column,
    required this.onToggleColumn,
    required this.onFilter,
  });

  final String field;
  final Object? value;
  final TextStyle style;

  /// [field] is a table column now.
  final bool column;
  final VoidCallback onToggleColumn;

  /// Null for values a single clause can't match (lists).
  final void Function(bool exclude)? onFilter;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool _hovered = false;

  /// A long value shown whole instead of its first [_clampLines] lines.
  bool _full = false;

  static const _clampLines = 4;

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied ${widget.field}')));
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final text = value is String ? value : jsonEncode(value);
    // Roughly more than the clamped lines at the table's width.
    final long =
        text.length > 320 || '\n'.allMatches(text).length >= _clampLines;
    Widget action(String tooltip, IconData icon, VoidCallback? onTap) =>
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          iconSize: 15,
          color: AppColors.muted,
          onPressed: onTap,
          icon: Icon(icon),
        );
    final onFilter = widget.onFilter;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        color: _hovered ? AppColors.surface.withValues(alpha: .6) : null,
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 260,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, right: 16),
                child: Text(
                  widget.field,
                  style: widget.style.copyWith(color: AppColors.muted),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            text,
                            maxLines: long && !_full ? _clampLines : null,
                            overflow: long && !_full
                                ? TextOverflow.ellipsis
                                : null,
                            style: value == null
                                ? widget.style.copyWith(color: AppColors.muted)
                                : widget.style,
                          ),
                        ),
                        // Right after the value, where the eye already is.
                        SelectionContainer.disabled(
                          child: Opacity(
                            opacity: _hovered ? 1 : 0,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: SizedBox.square(
                                dimension: 22,
                                child: IconButton(
                                  tooltip: 'Copy value',
                                  padding: EdgeInsets.zero,
                                  iconSize: 13,
                                  color: AppColors.muted,
                                  onPressed: () => _copy(text),
                                  icon: const Icon(Icons.copy_rounded),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (long)
                      SelectionContainer.disabled(
                        child: TextButton.icon(
                          onPressed: () => setState(() => _full = !_full),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.muted,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 24),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          icon: Icon(
                            _full
                                ? Icons.unfold_less_rounded
                                : Icons.unfold_more_rounded,
                            size: 14,
                          ),
                          label: Text(
                            _full
                                ? 'Show less'
                                : 'Show more (${_size(text.length)} chars)',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SelectionContainer.disabled(
              child: Opacity(
                // Kept in the tree so Tab still reaches them.
                opacity: _hovered ? 1 : 0,
                child: Focus(
                  skipTraversal: true,
                  onFocusChange: (focused) =>
                      setState(() => _hovered = focused),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      action(
                        'Filter for value',
                        Icons.zoom_in_rounded,
                        onFilter == null ? null : () => onFilter(false),
                      ),
                      action(
                        'Filter out value',
                        Icons.zoom_out_rounded,
                        onFilter == null ? null : () => onFilter(true),
                      ),
                      action(
                        widget.column ? 'Remove column' : 'Toggle column',
                        widget.column
                            ? Icons.view_column_rounded
                            : Icons.view_column_outlined,
                        widget.onToggleColumn,
                      ),
                    ],
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

/// An active filter under the query bar. A click opens Kibana's filter
/// menu (edit, include / exclude, disable, delete); × deletes it.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.filter,
    required this.disabled,
    required this.onEdit,
    required this.onInvert,
    required this.onToggleDisabled,
    required this.onRemove,
  });

  final KibanaFilter filter;

  /// Kept on the bar but left out of the query.
  final bool disabled;
  final VoidCallback onEdit;
  final VoidCallback onInvert;
  final VoidCallback onToggleDisabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final value = filter.value;
    // A null value is about the field itself: exclude means "exists".
    final negated = value == null ? !filter.exclude : filter.exclude;
    final shown = switch (value) {
      null => 'exists',
      final List<Object?> values => values.map(_shown).join(', '),
      _ => _shown(value),
    };
    final strike = disabled ? TextDecoration.lineThrough : null;
    Widget item(String text, IconData icon, VoidCallback onPressed) =>
        MenuItemButton(
          leadingIcon: Icon(icon, size: 16, color: AppColors.muted),
          onPressed: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 170),
            child: Text(text),
          ),
        );
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        item('Edit filter', Icons.edit_outlined, onEdit),
        item(
          negated ? 'Include results' : 'Exclude results',
          negated ? Icons.add_circle_outline : Icons.remove_circle_outline,
          onInvert,
        ),
        item(
          disabled ? 'Re-enable' : 'Temporarily disable',
          disabled ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          onToggleDisabled,
        ),
        const Divider(height: 8),
        item('Delete', Icons.delete_outline_rounded, onRemove),
      ],
      builder: (context, menu, _) => Opacity(
        opacity: disabled ? .55 : 1,
        child: Material(
          color: AppColors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: menu.isOpen
                  ? AppColors.accent
                  : negated && !disabled
                  ? AppColors.danger
                  : AppColors.inputBorder,
            ),
          ),
          child: InkWell(
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (negated)
                            TextSpan(
                              text: 'NOT ',
                              style: TextStyle(
                                color: disabled
                                    ? AppColors.muted
                                    : AppColors.danger,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (filter.label case final label?)
                            TextSpan(text: label)
                          else ...[
                            TextSpan(
                              text: '${filter.field}: ',
                              style: TextStyle(color: AppColors.muted),
                            ),
                            TextSpan(text: shown),
                          ],
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.text,
                        decoration: strike,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove filter',
                    visualDensity: VisualDensity.compact,
                    iconSize: 14,
                    color: AppColors.muted,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A failure, readably: what went wrong, what to check, Retry, and the raw
/// message behind "Details".
class _ErrorBanner extends StatefulWidget {
  const _ErrorBanner({
    required this.raw,
    required this.onRetry,
    required this.onDismiss,
  });

  final String raw;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  State<_ErrorBanner> createState() => _ErrorBannerState();
}

class _ErrorBannerState extends State<_ErrorBanner> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final (:title, :hint) = describeKibanaError(widget.raw);
    Widget link(String text, IconData icon, VoidCallback onTap) =>
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
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(hint, style: portixMuted(12)),
                  ],
                ),
              ),
              link('Retry', Icons.refresh_rounded, widget.onRetry),
              link(
                _details ? 'Hide details' : 'Details',
                _details
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                () => setState(() => _details = !_details),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                color: AppColors.muted,
                onPressed: widget.onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (_details)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 8, 0),
              child: SelectableText(
                widget.raw,
                style: _mono.copyWith(fontSize: 12, color: AppColors.text),
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.hint});

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title, style: portixTitle(15), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(hint, style: portixMuted(13), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
