/// Single-quotes [value] for a POSIX shell.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// RFC 3339 in UTC without fractions, as `kubectl --since-time` takes it.
String _rfc3339(DateTime time) =>
    '${time.toUtc().toIso8601String().split('.').first.replaceAll('Z', '')}Z';

/// `kubectl logs --timestamps` for [pod] in [namespace], or for every pod
/// there when [pod] is null (only [workload]'s when given), from [since] ago
/// or from [sinceTime] on. The pod list is read on every call, so pods that
/// replace others are picked up.
String kubeLogsCommand(
  String namespace,
  String? pod, {
  Workload? workload,
  Duration? since,
  DateTime? sinceTime,
}) {
  final ns = shellQuote(namespace);
  final args = [
    '--all-containers',
    '--timestamps',
    if (sinceTime != null)
      '--since-time=${_rfc3339(sinceTime)}'
    else if (since != null)
      '--since=${since.inSeconds}s',
  ].join(' ');
  if (pod != null) {
    return 'kubectl logs -n $ns ${shellQuote(pod)} $args 2>&1';
  }
  final list = workload == null
      ? r'$pods'
      : "\$(printf '%s\\n' \$pods | grep -E "
            "${shellQuote('^pod/${_workloadPattern(workload)}\$')})";
  // One pod at a time so a Pending or crashing pod doesn't hide the rest.
  return 'pods=\$(kubectl get pods -n $ns -o name) || exit 1; '
      'for p in $list; do kubectl logs -n $ns "\$p" $args 2>&1 || true; done';
}

enum WorkloadKind { deployment, statefulSet, other }

/// The controller a pod belongs to, recognised from the suffix Kubernetes
/// appends to its pods' names.
typedef Workload = ({String name, WorkloadKind kind});

/// Name suffixes per kind, as POSIX ERE: shared by [workloadOf] here and the
/// shell's `grep -E`, so grouping and fetching always agree. Exact lengths
/// keep `api` from claiming `api-worker`'s pods.
const _suffixes = {
  // <deployment>-<replicaset hash>-<5 chars>
  WorkloadKind.deployment: '-[a-z0-9]{6,10}-[a-z0-9]{5}',
  // <statefulset>-<ordinal>
  WorkloadKind.statefulSet: '-[0-9]+',
  // <daemonset or job>-<5 chars>
  WorkloadKind.other: '-[a-z0-9]{5}',
};

/// Pod names are DNS labels/subdomains; `.` is the only ERE special in them.
String _workloadPattern(Workload workload) =>
    '${workload.name.replaceAll('.', r'\.')}${_suffixes[workload.kind]}';

Workload? workloadOf(String pod) {
  for (final MapEntry(key: kind, value: suffix) in _suffixes.entries) {
    final match = RegExp('^(.+)$suffix\$').firstMatch(pod);
    if (match != null) return (name: match[1]!, kind: kind);
  }
  return null;
}

/// After [gone] disappeared: a pod of the same workload in [pods],
/// healthiest first, or null.
KubePod? replacementFor(String gone, List<KubePod> pods) {
  final workload = workloadOf(gone);
  if (workload == null) return null;
  final candidates = [
    for (final pod in pods)
      if (pod.name != gone && workloadOf(pod.name) == workload) pod,
  ]..sort((a, b) => podHealth(a).index.compareTo(podHealth(b).index));
  return candidates.firstOrNull;
}

final _spaces = RegExp(r'\s+');
final _readyColumn = RegExp(r'^(\d+)/(\d+)$');

/// A row of `kubectl get namespaces --no-headers`.
typedef KubeNamespace = ({String name, String status, String age});

List<KubeNamespace> parseNamespaces(String output) => [
  for (final line in output.split('\n'))
    if (line.trim().split(_spaces) case [final name, final status, final age])
      (name: name, status: status, age: age),
];

/// A row of `kubectl get pods --no-headers`.
typedef KubePod = ({
  String name,
  String ready,
  String status,
  int restarts,
  String age,
});

/// Parses NAME READY STATUS RESTARTS AGE; RESTARTS may read `3 (2d ago)`.
List<KubePod> parsePods(String output) => [
  for (final line in output.split('\n'))
    if (line.trim().split(_spaces) case [
      final name,
      final ready,
      final status,
      final restarts,
      ...,
      final age,
    ] when _readyColumn.hasMatch(ready))
      (
        name: name,
        ready: ready,
        status: status,
        restarts: int.tryParse(restarts) ?? 0,
        age: age,
      ),
];

enum PodHealth { ok, pending, failing, done }

PodHealth podHealth(KubePod pod) {
  switch (pod.status) {
    case 'Completed' || 'Succeeded':
      return PodHealth.done;
    case 'Running':
      final m = _readyColumn.firstMatch(pod.ready);
      return m != null && m[1] == m[2] ? PodHealth.ok : PodHealth.pending;
    case 'Pending' || 'ContainerCreating' || 'PodInitializing' || 'Terminating':
      return PodHealth.pending;
    case final status when status.startsWith('Init:'):
      return PodHealth.pending;
    default:
      return PodHealth.failing; // CrashLoopBackOff, Error, ImagePullBackOff…
  }
}

/// One log line; [time] is kubectl's own timestamp (null for lines kubectl
/// didn't stamp, such as its error messages).
class LogLine {
  const LogLine(this.time, this.text);

  final DateTime? time;
  final String text;
}

/// Splits `kubectl logs --timestamps` output and orders it by time, so
/// all-pods output reads as one stream. Unstamped lines keep their place
/// after the line before them.
List<LogLine> parseLogLines(String output) {
  final lines = <LogLine>[];
  DateTime? previous;
  for (final raw in output.split('\n')) {
    if (raw.isEmpty) continue;
    final space = raw.indexOf(' ');
    final time = space > 0 ? DateTime.tryParse(raw.substring(0, space)) : null;
    if (time != null) previous = time;
    lines.add(
      time == null
          ? LogLine(previous, raw)
          : LogLine(time, raw.substring(space + 1)),
    );
  }
  // List.sort isn't stable; break ties on the original order.
  final indexed = lines.indexed.toList()
    ..sort((a, b) {
      final ta = a.$2.time, tb = b.$2.time;
      final byTime = ta == null || tb == null ? 0 : ta.compareTo(tb);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, line) in indexed) line];
}

/// [existing] plus a re-read [fetched] from the second of its last stamped
/// line on (`--since-time` has whole seconds): lines already shown are
/// skipped. With [keepFrom], lines older than it fall off (a sliding
/// relative range).
List<LogLine> appendNewLines(
  List<LogLine> existing,
  List<LogLine> fetched, {
  DateTime? keepFrom,
}) {
  String key(LogLine line) =>
      '${line.time?.microsecondsSinceEpoch}|${line.text}';
  final last = lastStamp(existing);
  final boundary = last == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          last.millisecondsSinceEpoch ~/ 1000 * 1000,
          isUtc: true,
        );
  final seen = {
    for (final line in existing)
      if (boundary != null &&
          line.time != null &&
          !line.time!.isBefore(boundary))
        key(line),
  };
  return [
    for (final line in existing)
      if (keepFrom == null ||
          line.time == null ||
          !line.time!.isBefore(keepFrom))
        line,
    for (final line in fetched)
      if (seen.add(key(line))) line,
  ];
}

/// kubectl's time of the newest stamped line, if any.
DateTime? lastStamp(List<LogLine> lines) => lines
    .lastWhere((l) => l.time != null, orElse: () => const LogLine(null, ''))
    .time;

/// A Kibana-style search: every term must appear (case-insensitive),
/// `"quoted phrases"` match as a whole, `-term` excludes, `a OR b` matches
/// either side, and anything else (e.g. `"code":"06"`) matches literally.
class LogQuery {
  LogQuery(String query) : _groups = _parse(query);

  /// OR-groups of AND-terms, lowercased; excluded terms must be absent.
  final List<List<({String text, bool exclude})>> _groups;

  bool get isEmpty => _groups.isEmpty;

  /// Terms to highlight in matching lines (exclusions left out).
  List<String> get highlights => [
    for (final group in _groups)
      for (final term in group)
        if (!term.exclude) term.text,
  ];

  static bool _isSpace(String c) => c.trim().isEmpty;

  /// Splits on whitespace. `"a b"` (quotes around the whole token) is a
  /// phrase; any other token is literal, quotes included, so a JSON fragment
  /// like `"response":"06"` matches as typed. A leading `-` excludes.
  static List<({String text, bool exclude, bool phrase})> _tokens(String q) {
    final tokens = <({String text, bool exclude, bool phrase})>[];
    var i = 0;
    while (i < q.length) {
      if (_isSpace(q[i])) {
        i++;
        continue;
      }
      final exclude = q[i] == '-' && i + 1 < q.length && !_isSpace(q[i + 1]);
      final start = exclude ? i + 1 : i;
      if (q[start] == '"') {
        final close = q.indexOf('"', start + 1);
        if (close != -1 && (close + 1 == q.length || _isSpace(q[close + 1]))) {
          tokens.add((
            text: q.substring(start + 1, close),
            exclude: exclude,
            phrase: true,
          ));
          i = close + 1;
          continue;
        }
      }
      var end = start;
      while (end < q.length && !_isSpace(q[end])) {
        end++;
      }
      tokens.add((
        text: q.substring(start, end),
        exclude: exclude,
        phrase: false,
      ));
      i = end;
    }
    return tokens;
  }

  static List<List<({String text, bool exclude})>> _parse(String query) {
    final groups = <List<({String text, bool exclude})>>[[]];
    for (final token in _tokens(query)) {
      if (!token.phrase && !token.exclude && token.text == 'OR') {
        groups.add([]);
      } else if (token.text.isNotEmpty) {
        groups.last.add((
          text: token.text.toLowerCase(),
          exclude: token.exclude,
        ));
      }
    }
    return groups.where((g) => g.isNotEmpty).toList();
  }

  bool matches(String text) => _matchesLower(text.toLowerCase());

  /// Like [matches], lowercasing each line once rather than per keystroke
  /// (a single log line can be megabytes).
  bool matchesLine(LogLine line) =>
      _matchesLower(_lowered[line] ??= line.text.toLowerCase());

  bool _matchesLower(String lower) {
    if (_groups.isEmpty) return true;
    return _groups.any(
      (terms) => terms.every((t) => lower.contains(t.text) != t.exclude),
    );
  }

  static final _lowered = Expando<String>('lowercased log line');
}

/// Lines inside [from]..[to] (either open) that match [query].
List<LogLine> filterLogLines(
  List<LogLine> lines, {
  DateTime? from,
  DateTime? to,
  LogQuery? query,
}) {
  if (from == null && to == null && (query == null || query.isEmpty)) {
    return lines;
  }
  return [
    for (final line in lines)
      if ((from == null || line.time == null || !line.time!.isBefore(from)) &&
          (to == null || line.time == null || !line.time!.isAfter(to)) &&
          (query == null || query.matchesLine(line)))
        line,
  ];
}

enum LogLevel { error, warn, info, debug }

final _leadingTimestamp = RegExp(
  r'^\d{4}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s*',
);
final _leadingLevel = RegExp(
  r'^\[?\s*(FATAL|ERROR|ERR|WARNING|WARN|INFO|DEBUG|TRACE)\b\s*\]?\s*[-:|]?\s*',
  caseSensitive: false,
);

/// [text] split for display: the level it starts with (if any) and the
/// message without the app's own leading timestamp and level, which the
/// viewer shows in their own columns.
({LogLevel? level, String message}) splitLogText(String text) {
  final rest = text.replaceFirst(_leadingTimestamp, '');
  final match = _leadingLevel.firstMatch(rest);
  if (match == null) return (level: null, message: rest);
  final level = switch (match[1]!.toUpperCase()) {
    'FATAL' || 'ERROR' || 'ERR' => LogLevel.error,
    'WARNING' || 'WARN' => LogLevel.warn,
    'INFO' => LogLevel.info,
    _ => LogLevel.debug,
  };
  return (level: level, message: rest.substring(match.end));
}

final _split = Expando<({LogLevel? level, String message})>('split log line');

/// [splitLogText] of [line], computed once per line (rows rebuild as they
/// scroll in and out).
({LogLevel? level, String message}) displayOf(LogLine line) =>
    _split[line] ??= splitLogText(line.text);

/// The first [limit] characters of [text] for display, and how many were
/// left out. Laying out a megabyte-long line on every scroll is what made
/// huge entries lag; the full text stays available for copy.
({String shown, int hidden}) clipForDisplay(String text, int limit) =>
    text.length <= limit
    ? (shown: text, hidden: 0)
    : (shown: text.substring(0, limit), hidden: text.length - limit);

/// A failure as people read it: what went wrong, what to check, and the
/// raw message (wrappers and backtrace removed) for the details view.
typedef KubeError = ({String title, String hint, String detail});

KubeError describeKubeError(String raw) {
  var detail = raw.split('Stack backtrace:').first.trim();
  for (final wrapper in ['Remote command failed: ', 'AnyhowException(']) {
    if (detail.startsWith(wrapper)) detail = detail.substring(wrapper.length);
  }
  if (raw.contains('AnyhowException(') && detail.endsWith(')')) {
    detail = detail.substring(0, detail.length - 1);
  }
  detail = detail
      .replaceFirst(RegExp(r'^remote command exited with \d+: '), '')
      .trim();

  final text = raw.toLowerCase();
  bool has(List<String> needles) => needles.any(text.contains);
  KubeError say(String title, String hint) =>
      (title: title, hint: hint, detail: detail);

  // kubectl's own messages first: "connection ... refused" also appears in
  // its "API server unreachable" error, which isn't an SSH problem.
  if (has(['command not found', 'exited with 127'])) {
    return say(
      "kubectl isn't installed on this server",
      'Install kubectl there, or pick a server that has it on the PATH of '
          'non-interactive SSH sessions.',
    );
  }
  if (has([
    'the connection to the server',
    'unable to connect to the server',
    'did you specify the right host',
  ])) {
    return say(
      'Kubernetes API unreachable from this server',
      "kubectl on the server can't reach the cluster. Check its kubeconfig "
          "context, or whether the cluster's API is up.",
    );
  }
  if (has(['unauthorized', 'you must be logged in', 'token has expired'])) {
    return say(
      'Cluster credentials were rejected',
      'The kubeconfig credentials on this server have expired or were '
          'revoked. Log in to the cluster again on the server.',
    );
  }
  if (text.contains('forbidden')) {
    return say(
      'No permission for this',
      "The kubeconfig user on this server isn't allowed to read it (RBAC). "
          'Ask for access, or pick another namespace.',
    );
  }
  if (has(['notfound', 'not found'])) {
    return say(
      'Not found',
      'The pod or namespace no longer exists. Pick it again from the list.',
    );
  }
  if (text.contains('host key')) {
    return say(
      "Server host key isn't trusted",
      'Connect to this server once from the SSH view to review and trust '
          'its key.',
    );
  }
  if (has(['authentication', 'permission denied', 'auth failed'])) {
    return say(
      'SSH login failed',
      "Check the profile's username, key or password.",
    );
  }
  if (has([
    'channel send error',
    'connectiontimeout',
    'timed out',
    'connection reset',
    'connection refused',
    'broken pipe',
    'disconnect',
    'network is unreachable',
  ])) {
    return say(
      'Lost connection to the server',
      'The SSH connection dropped. Check your VPN or network; Portix '
          'reconnects on the next try.',
    );
  }
  return say('Command failed', 'See the details below.');
}
