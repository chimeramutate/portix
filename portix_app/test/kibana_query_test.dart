import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/kibana/kibana_query.dart';

final _range = (
  from: DateTime.utc(2026, 10, 29, 21, 19),
  to: DateTime.utc(2026, 10, 29, 21, 34),
);

KibanaSearch _search(String index, String query) => (
  index: index,
  query: query,
  range: _range,
  timeField: '@timestamp',
  size: 200,
);

void main() {
  test('kibanaSearchCommand quotes the url and query body', () {
    final cmd = kibanaSearchCommand(
      'http://es:9200/',
      _search('logs-*', "msg:'x'"),
    );
    expect(cmd, contains("'http://es:9200/logs-*/_search'"));
    expect(cmd, contains(r"""\''x'\''"""));
    expect(cmd, contains('--netrc-optional'));
    expect(kibanaSearchCommand('u', _search('', '')), contains('match_all'));
  });

  test('the body filters the range and asks for a 30s histogram', () {
    final body = jsonDecode(kibanaSearchBody(_search('*', ''))) as Map;
    final range = body['query']['bool']['filter'][0]['range']['@timestamp'];
    expect(range['gte'], '2026-10-29T21:19:00.000Z');
    expect(
      body['aggs']['histogram']['date_histogram']['fixed_interval'],
      '30s',
      reason: '15 minutes in at most 60 bars',
    );
    expect(kibanaIntervalLabel(const Duration(hours: 3)), '3h');
  });

  test('parseKibanaHits reads hits and surfaces errors', () {
    final result = parseKibanaHits(
      '{"took":7,"hits":{"total":{"value":42},"hits":['
      '{"_source":{"@timestamp":"t1","message":"boom"}},'
      '{"_source":{"a":1}}]},"aggregations":{"histogram":{"buckets":['
      '{"key":0,"doc_count":3},{"key":30000,"doc_count":0}]}}}',
    );
    final hits = result.hits;
    expect((result.total, result.tookMs), (42, 7));
    expect(hits.map((h) => h.time), ['t1', '']);
    expect(result.buckets.map((b) => b.count), [3, 0]);
    expect(kibanaFields(hits), {'@timestamp': 1, 'a': 1, 'message': 1});
    expect(
      () => parseKibanaHits('{"error":{"reason":"no such index"}}'),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'm', 'no such index'),
      ),
    );
    expect(() => parseKibanaHits('curl: (7) refused'), throwsFormatException);
  });

  test('kibanaLevel reads ECS and plain level fields', () {
    expect(kibanaLevel({'log.level': 'ERROR'}), 'error');
    expect(
      kibanaLevel({
        'log': {'level': 'warn'},
      }),
      'warn',
    );
    expect(kibanaLevel({'level': 'info'}), 'info');
    expect(kibanaLevel({'message': 'x'}), isNull);
  });

  test('describeKibanaError names the usual failures', () {
    expect(
      describeKibanaError('curl: (7) Failed to connect to localhost').title,
      "Can't reach the server",
    );
    expect(
      describeKibanaError('missing authentication credentials').title,
      'Elasticsearch rejected the credentials',
    );
    expect(describeKibanaError('???').title, 'Search failed');
  });

  test('filters become escaped Lucene clauses ANDed to the query', () {
    expect(
      kibanaClause((
        field: 'host.name',
        value: 'a"b',
        exclude: false,
        label: null,
      )),
      r'host.name:"a\"b"',
    );
    expect(
      kibanaClause((field: 'k8s:pod', value: 1, exclude: true, label: null)),
      r'NOT k8s\:pod:"1"',
    );
    expect(
      kibanaClause((field: 'x', value: null, exclude: false, label: null)),
      'NOT _exists_:x',
    );
    expect(kibanaQueryWith('a OR b', const []), 'a OR b');
    expect(
      kibanaQueryWith('a OR b', [
        (field: 'c', value: 'd', exclude: false, label: null),
      ]),
      '(a OR b) AND (c:"d")',
    );
    expect(
      kibanaQueryWith('', [
        (field: 'c', value: 'd', exclude: true, label: null),
      ]),
      '(NOT c:"d")',
    );
  });

  test('lists are "is one of"; null with exclude is "exists"', () {
    expect(
      kibanaClause((
        field: 'ns',
        value: ['a', 'b"c'],
        exclude: true,
        label: null,
      )),
      r'NOT ns:("a" OR "b\"c")',
    );
    expect(
      kibanaClause((field: 'x', value: null, exclude: true, label: null)),
      '_exists_:x',
    );
  });

  test('top values count documents per value, most common first', () {
    KibanaHit hit(Object? ns) => (time: 't', source: {'ns': ns, 'm': 1});
    final hits = [
      hit('a'),
      hit('b'),
      hit('a'),
      (time: 't', source: {'m': 2}),
    ];
    expect(kibanaTopValues(hits, 'ns'), [
      (value: 'a', count: 2),
      (value: 'b', count: 1),
    ]);
  });

  test('kibanaTable copies the shown columns, one line per document', () {
    final hits = <KibanaHit>[
      (time: 't1', source: {'@timestamp': 't1', 'log': 'a\tb\nc', 'n': 1}),
    ];
    expect(
      kibanaTable(hits, '@timestamp', ['log', 'missing']),
      '@timestamp\tlog\tmissing\nt1\ta b c\t',
    );
    expect(
      kibanaTable(hits, '@timestamp', const []),
      '@timestamp\tSummary\nt1\tlog a b c  n 1',
    );
  });

  test('flattenSource dots nested fields and sorts them', () {
    expect(
      flattenSource({
        'z': 1,
        'log': {'level': 'info'},
        'tags': ['a'],
      }),
      {
        'log.level': 'info',
        'tags': ['a'],
        'z': 1,
      },
    );
  });

  test(
    'direct search goes through Kibana console proxy with the login',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final ok =
            request.uri.path == '/kb/api/console/proxy' &&
            request.uri.queryParameters['path'] == 'logs-*/_search' &&
            request.headers.value('kbn-xsrf') != null &&
            request.headers.value('x-elastic-internal-origin') != null &&
            request.headers.value('authorization') ==
                'Basic ${base64Encode(utf8.encode('elastic:pw'))}' &&
            body.contains('query_string');
        request.response
          ..statusCode = ok ? 200 : 401
          ..write(
            ok
                ? '{"took":1,"hits":{"total":{"value":0},"hits":[]}}'
                : '{"statusCode":401,"error":"Unauthorized","message":"bad"}',
          );
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/kb/';
      final good = await kibanaDirectSearch(
        url,
        _search('logs-*', 'level:error'),
        (apiKey: false, user: 'elastic', secret: 'pw'),
      );
      expect(parseKibanaHits(good).total, 0);
      final bad = await kibanaDirectSearch(url, _search('logs-*', 'x'), null);
      expect(
        () => parseKibanaHits(bad),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            'Unauthorized: bad',
          ),
        ),
      );
      expect(
        describeKibanaError('Unauthorized: bad').title,
        'Kibana rejected the sign-in',
      );
    },
  );

  test('data views are listed by name with their time field', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.write(switch (request.uri.path) {
        '/api/data_views' =>
          '{"data_view":[{"id":"b","title":"logs-*","name":"Ebanking Logs"},'
              '{"id":"a","title":"metrics-*"}]}',
        '/api/data_views/data_view/b' =>
          '{"data_view":{"timeFieldName":"@timestamp"}}',
        _ => '{"statusCode":404,"error":"Not Found"}',
      });
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}';
    final views = await kibanaDataViews(url, null);
    expect(views.map((v) => (v.name, v.pattern)), [
      ('Ebanking Logs', 'logs-*'),
      ('metrics-*', 'metrics-*'),
    ]);
    expect(await kibanaTimeField(url, 'b', null), '@timestamp');
  });

  test('a restricted console proxy is named as such', () {
    expect(
      describeKibanaError(
        'Bad Request: uri [/api/console/proxy] with method [post] exists but '
        'is not available with the current configuration',
      ).title,
      'Kibana blocks its console proxy here',
    );
  });

  test('API keys go in an ApiKey header', () {
    expect(
      kibanaAuthHeader((apiKey: true, user: '', secret: ' abc== ')),
      'ApiKey abc==',
    );
  });
}
