/// Single-quotes [value] for a POSIX shell.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// RFC 3339 in UTC without fractions, as `kubectl --since-time` takes it.
String _rfc3339(DateTime time) =>
    '${time.toUtc().toIso8601String().split('.').first.replaceAll('Z', '')}Z';

/// `kubectl logs --timestamps` for [pod] in [namespace], or for every pod
/// there when [pod] is null, from [since] ago or from [sinceTime] on.
String kubeLogsCommand(
  String namespace,
  String? pod, {
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
  // One pod at a time so a Pending or crashing pod doesn't hide the rest.
  return 'pods=\$(kubectl get pods -n $ns -o name) || exit 1; '
      'for p in \$pods; do kubectl logs -n $ns "\$p" $args 2>&1 || true; done';
}

/// `kubectl get <kind> -o name` lines without the `<kind>/` prefix.
List<String> kubeNames(String output) => [
  for (final line in output.split('\n'))
    if (line.trim().isNotEmpty) line.trim().split('/').last,
];

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

/// A Kibana-style search: every term must appear (case-insensitive),
/// `"quoted phrases"` match as a whole, `-term` excludes, `a OR b` matches
/// either side.
class LogQuery {
  LogQuery(String query) : _groups = _parse(query);

  /// OR-groups of AND-terms; a term starting with `-` must be absent.
  final List<List<String>> _groups;

  bool get isEmpty => _groups.isEmpty;

  /// Terms to highlight in matching lines (exclusions left out).
  List<String> get highlights => [
    for (final group in _groups)
      for (final term in group)
        if (!term.startsWith('-')) term,
  ];

  static final _token = RegExp(r'-?"[^"]*"|\S+');

  static List<List<String>> _parse(String query) {
    final groups = <List<String>>[[]];
    for (final match in _token.allMatches(query)) {
      final token = match[0]!;
      if (token == 'OR') {
        groups.add([]);
        continue;
      }
      final term = token.replaceAll('"', '').toLowerCase();
      if (term.isNotEmpty && term != '-') groups.last.add(term);
    }
    return groups.where((g) => g.isNotEmpty).toList();
  }

  bool matches(String text) {
    if (_groups.isEmpty) return true;
    final lower = text.toLowerCase();
    return _groups.any(
      (terms) => terms.every(
        (t) => t.startsWith('-')
            ? !lower.contains(t.substring(1))
            : lower.contains(t),
      ),
    );
  }
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
          (query == null || query.matches(line.text)))
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
