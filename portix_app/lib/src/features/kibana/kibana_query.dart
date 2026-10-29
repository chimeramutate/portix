import 'dart:convert';
import 'dart:io';

import 'package:portix/src/features/kubernetes/kube_logs.dart' show shellQuote;

/// One document from a search: its time field as sent and the whole
/// `_source`.
typedef KibanaHit = ({String time, Map<String, dynamic> source});

/// The time window Discover searches.
typedef KibanaRange = ({DateTime from, DateTime to});

/// One search, as Discover runs it: [index] (a pattern), a Lucene [query]
/// within [range] on [timeField], [size] newest documents.
typedef KibanaSearch = ({
  String index,
  String query,
  KibanaRange range,
  String timeField,
  int size,
});

const _intervals = [
  Duration(seconds: 1),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 3),
  Duration(hours: 12),
  Duration(days: 1),
  Duration(days: 7),
];

/// The histogram's bucket width: the smallest round step that keeps
/// [range] to about 60 bars, like Kibana's "Auto interval".
Duration kibanaInterval(KibanaRange range) {
  final span = range.to.difference(range.from).inMilliseconds;
  return _intervals.firstWhere(
    (step) => span / step.inMilliseconds <= 60,
    orElse: () => _intervals.last,
  );
}

/// [step] in Elasticsearch's units, e.g. `30s`, `5m`, `3h`, `1d`.
String kibanaIntervalLabel(Duration step) => step.inDays > 0
    ? '${step.inDays}d'
    : step.inHours > 0
    ? '${step.inHours}h'
    : step.inMinutes > 0
    ? '${step.inMinutes}m'
    : '${step.inSeconds}s';

/// curl on the server against Elasticsearch's `_search`. Credentials come
/// from the server's `~/.netrc`, so Portix never stores them.
String kibanaSearchCommand(String baseUrl, KibanaSearch search) {
  final url = '${_base(baseUrl)}/${_index(search.index)}/_search';
  return 'curl -sS --netrc-optional -X POST '
      "-H 'Content-Type: application/json' "
      '${shellQuote(url)} -d ${shellQuote(kibanaSearchBody(search))}';
}

String _base(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

String _index(String index) => index.trim().isEmpty ? '*' : index.trim();

/// The `_search` body: newest first, the query inside the time range, and
/// the per-interval counts for the histogram.
String kibanaSearchBody(KibanaSearch search) {
  final (:index, :query, :range, :timeField, :size) = search;
  return jsonEncode({
    'size': size,
    'track_total_hits': true,
    'sort': [
      {
        timeField: {'order': 'desc', 'unmapped_type': 'date'},
      },
    ],
    'query': {
      'bool': {
        'must': [
          if (query.trim().isEmpty)
            {'match_all': <String, dynamic>{}}
          else
            {
              'query_string': {'query': query.trim()},
            },
        ],
        'filter': [
          {
            'range': {
              timeField: {
                'gte': range.from.toUtc().toIso8601String(),
                'lte': range.to.toUtc().toIso8601String(),
                'format': 'strict_date_optional_time',
              },
            },
          },
        ],
      },
    },
    'aggs': {
      'histogram': {
        'date_histogram': {
          'field': timeField,
          'fixed_interval': kibanaIntervalLabel(kibanaInterval(range)),
          'min_doc_count': 0,
          'extended_bounds': {
            'min': range.from.millisecondsSinceEpoch,
            'max': range.to.millisecondsSinceEpoch,
          },
        },
      },
    },
  });
}

/// What a `_search` answered: how many documents match in all, how long
/// Elasticsearch took, the hits it sent back and the histogram's bars.
typedef KibanaResult = ({
  int total,
  int tookMs,
  List<KibanaHit> hits,
  List<({DateTime start, int count})> buckets,
});

/// [output] as JSON; throws [FormatException] with Kibana's or
/// Elasticsearch's reason when it answered with an error.
Map<String, dynamic> _decode(String output) {
  final Object? json;
  try {
    json = jsonDecode(output);
  } on FormatException {
    throw FormatException(
      output.trim().isEmpty ? 'No response' : output.trim(),
    );
  }
  if (json is! Map<String, dynamic>) throw const FormatException('No hits');
  final error = json['error'];
  // Kibana's own errors: {statusCode, error: "Unauthorized", message}.
  if (json['statusCode'] case final int code when code >= 400) {
    throw FormatException('$error: ${json['message'] ?? code}');
  }
  if (error != null) {
    final reason = error is Map ? error['reason'] ?? error['type'] : error;
    throw FormatException('$reason');
  }
  return json;
}

/// [output] of a search as a [KibanaResult].
KibanaResult parseKibanaHits(String output, {String timeField = '@timestamp'}) {
  final json = _decode(output);
  final outer = json['hits'] as Map? ?? const {};
  final hits = [
    for (final hit
        in (outer['hits'] as List? ?? const []).cast<Map<String, dynamic>>())
      if (hit['_source'] case final Map<String, dynamic> source)
        (time: '${source[timeField] ?? ''}', source: source),
  ];
  // ES 7+ sends {value, relation}; 6 sends a bare number.
  final total = switch (outer['total']) {
    {'value': final int value} => value,
    final int value => value,
    _ => hits.length,
  };
  final buckets =
      ((json['aggregations'] as Map?)?['histogram'] as Map?)?['buckets']
          as List? ??
      const [];
  return (
    total: total,
    tookMs: json['took'] as int? ?? 0,
    hits: hits,
    buckets: [
      for (final b in buckets.cast<Map<String, dynamic>>())
        (
          start: DateTime.fromMillisecondsSinceEpoch(b['key'] as int),
          count: b['doc_count'] as int? ?? 0,
        ),
    ],
  );
}

/// Every field in [hits] with how many documents have it, sorted by name,
/// for the field list.
Map<String, int> kibanaFields(List<KibanaHit> hits) {
  final counts = <String, int>{};
  for (final hit in hits) {
    for (final field in flattenSource(hit.source).keys) {
      counts[field] = (counts[field] ?? 0) + 1;
    }
  }
  return Map.fromEntries(
    counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// The log level of [source] in ECS (`log.level`, flat or nested) or the
/// plain `level` field, lowercased; null when it has none.
String? kibanaLevel(Map<String, dynamic> source) {
  final log = source['log'];
  final level =
      source['log.level'] ??
      (log is Map ? log['level'] : null) ??
      source['level'];
  return level is String && level.isNotEmpty ? level.toLowerCase() : null;
}

/// A failed search as a title and what to check, from curl's or
/// Elasticsearch's [raw] message.
({String title, String hint}) describeKibanaError(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('curl: not found') ||
      text.contains('curl: command not found')) {
    return (
      title: 'curl is not installed on this server',
      hint: 'Install curl there, or pick a server that has it.',
    );
  }
  if (text.contains('could not resolve host') ||
      text.contains('failed to connect') ||
      text.contains('connection refused') ||
      text.contains('failed host lookup') ||
      text.contains('socketexception') ||
      text.contains('timeoutexception')) {
    return (
      title: "Can't reach the server",
      hint: 'Check the URL; through SSH it is resolved on that server.',
    );
  }
  if (text.contains('ssl') ||
      text.contains('certificate') ||
      text.contains('handshake')) {
    return (
      title: 'TLS certificate not trusted',
      hint: 'Use a certificate this machine (or the SSH server) trusts.',
    );
  }
  if (text.startsWith('unauthorized')) {
    return (
      title: 'Kibana rejected the sign-in',
      hint: 'Check the username and password, or the API key.',
    );
  }
  if (text.contains('security_exception') ||
      text.contains('missing authentication') ||
      text.contains('unable to authenticate')) {
    return (
      title: 'Elasticsearch rejected the credentials',
      hint: 'Add a machine entry for this host to ~/.netrc on the server.',
    );
  }
  if (text.contains('no such index') || text.contains('index_not_found')) {
    return (
      title: 'No index matches',
      hint: 'Check the index pattern, e.g. logs-* or filebeat-*.',
    );
  }
  if (text.contains('not available with the current configuration')) {
    return (
      title: 'Kibana blocks its console proxy here',
      hint: 'This Kibana restricts internal APIs; search via SSH instead.',
    );
  }
  if (text.startsWith('not found')) {
    return (
      title: 'Kibana has no console proxy here',
      hint: 'Check the Kibana URL (and its base path), or search via SSH.',
    );
  }
  if (text.contains('failed to parse query') ||
      text.contains('query_shard_exception')) {
    return (
      title: "The query couldn't be parsed",
      hint: 'Use Lucene syntax, e.g. level:error AND service:api.',
    );
  }
  return (title: 'Search failed', hint: 'See the details below.');
}

/// A Discover filter pill: [field] is (or with [exclude], isn't) [value].
/// A list [value] is "is one of"; null is "does not exist" (with
/// [exclude]: "exists"). [label] replaces the text on the pill.
typedef KibanaFilter = ({
  String field,
  Object? value,
  bool exclude,
  String? label,
});

final _luceneSpecial = RegExp(r'[+\-=&|><!(){}\[\]^"~*?:\\/ ]');

/// [filter] in Lucene; a null [KibanaFilter.value] means the field is
/// missing.
String kibanaClause(KibanaFilter filter) {
  final field = filter.field.replaceAllMapped(
    _luceneSpecial,
    (m) => '\\${m[0]}',
  );
  if (filter.value == null) {
    return filter.exclude ? '_exists_:$field' : 'NOT _exists_:$field';
  }
  String quoted(Object? v) =>
      '"${'$v'.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  final value = switch (filter.value) {
    final List<Object?> values => '(${values.map(quoted).join(' OR ')})',
    final v => quoted(v),
  };
  return '${filter.exclude ? 'NOT ' : ''}$field:$value';
}

/// [query] and every filter ANDed, each in parentheses so an OR inside
/// one can't leak into the others.
String kibanaQueryWith(String query, List<KibanaFilter> filters) => [
  if (query.trim().isNotEmpty) query.trim(),
  ...filters.map(kibanaClause),
].map((part) => filters.isEmpty ? part : '($part)').join(' AND ');

/// [source] as dotted field paths, sorted, the way Discover's table lists
/// them; lists stay whole.
Map<String, Object?> flattenSource(Map<String, dynamic> source) {
  final fields = <String, Object?>{};
  void walk(Map<String, dynamic> map, String prefix) {
    for (final MapEntry(:key, :value) in map.entries) {
      if (value is Map<String, dynamic>) {
        walk(value, '$prefix$key.');
      } else {
        fields['$prefix$key'] = value;
      }
    }
  }

  walk(source, '');
  return Map.fromEntries(
    fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// Signing in to Kibana: a user and password, or (with [apiKey]) an
/// encoded API key in [secret].
typedef KibanaAuth = ({bool apiKey, String user, String secret});

String kibanaAuthHeader(KibanaAuth auth) => auth.apiKey
    ? 'ApiKey ${auth.secret.trim()}'
    : 'Basic ${base64Encode(utf8.encode('${auth.user}:${auth.secret}'))}';

/// A Kibana data view: what the picker shows and the index pattern it
/// searches.
typedef KibanaDataView = ({String id, String name, String pattern});

Future<String> _send(
  String method,
  Uri uri,
  KibanaAuth? auth, [
  String? body,
]) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.openUrl(method, uri);
    request.headers
      ..contentType = ContentType.json
      ..set('kbn-xsrf', 'portix')
      // Kibana with server.restrictInternalApis (8.x, serverless) refuses
      // internal routes like the console proxy without it; its own UI
      // sends the same.
      ..set('x-elastic-internal-origin', 'Kibana');
    if (auth != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        kibanaAuthHeader(auth),
      );
    }
    if (body != null) request.write(body);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await response.transform(utf8.decoder).join();
    if (text.trim().isEmpty && response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return text;
  } finally {
    client.close(force: true);
  }
}

/// Kibana's console proxy (what Dev Tools uses), which runs `_search` on
/// Elasticsearch as the signed-in Kibana user.
Uri kibanaProxyUri(String kibanaUrl, String index) =>
    Uri.parse('${_base(kibanaUrl)}/api/console/proxy').replace(
      queryParameters: {'path': '${_index(index)}/_search', 'method': 'POST'},
    );

/// Searches straight from this machine through Kibana, no SSH server;
/// the body comes back whatever the status, for [parseKibanaHits].
Future<String> kibanaDirectSearch(
  String kibanaUrl,
  KibanaSearch search,
  KibanaAuth? auth,
) => _send(
  'POST',
  kibanaProxyUri(kibanaUrl, search.index),
  auth,
  kibanaSearchBody(search),
);

/// The data views defined in Kibana, by name.
Future<List<KibanaDataView>> kibanaDataViews(
  String kibanaUrl,
  KibanaAuth? auth,
) async {
  final json = _decode(
    await _send('GET', Uri.parse('${_base(kibanaUrl)}/api/data_views'), auth),
  );
  return [
    for (final view
        in (json['data_view'] as List? ?? const [])
            .cast<Map<String, dynamic>>())
      (
        id: '${view['id']}',
        name: '${view['name'] ?? view['title']}',
        pattern: '${view['title']}',
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// The time field of data view [id]; null when it has none.
Future<String?> kibanaTimeField(
  String kibanaUrl,
  String id,
  KibanaAuth? auth,
) async {
  final json = _decode(
    await _send(
      'GET',
      Uri.parse(
        '${_base(kibanaUrl)}/api/data_views/data_view/${Uri.encodeComponent(id)}',
      ),
      auth,
    ),
  );
  return (json['data_view'] as Map?)?['timeFieldName'] as String?;
}

/// The [n] most common values of [field] in [hits] with how many
/// documents hold each, like Discover's field popover; missing ones are
/// left out.
List<({Object? value, int count})> kibanaTopValues(
  List<KibanaHit> hits,
  String field, {
  int n = 5,
}) {
  final counts = <String, ({Object? value, int count})>{};
  for (final hit in hits) {
    final fields = flattenSource(hit.source);
    if (!fields.containsKey(field)) continue;
    final value = fields[field];
    final key = jsonEncode(value);
    counts[key] = (value: value, count: (counts[key]?.count ?? 0) + 1);
  }
  return (counts.values.toList()..sort((a, b) => b.count - a.count))
      .take(n)
      .toList();
}

/// The shown documents as tab-separated text, a header line first: the
/// time field, then [columns] or Discover's "Summary" of every field.
String kibanaTable(
  List<KibanaHit> hits,
  String timeField,
  List<String> columns,
) {
  String cell(Object? v) =>
      (v is String
              ? v
              : v == null
              ? ''
              : jsonEncode(v))
          .replaceAll(RegExp(r'[\t\r\n]+'), ' ');
  return [
    [
      timeField,
      ...columns.isEmpty ? ['Summary'] : columns,
    ].join('\t'),
    for (final hit in hits)
      () {
        final fields = flattenSource(hit.source);
        return [
          cell(hit.time),
          if (columns.isEmpty)
            cell(
              [
                for (final MapEntry(:key, :value) in fields.entries)
                  if (key != timeField) '$key ${cell(value)}',
              ].join('  '),
            )
          else
            for (final field in columns) cell(fields[field]),
        ].join('\t');
      }(),
  ].join('\n');
}
