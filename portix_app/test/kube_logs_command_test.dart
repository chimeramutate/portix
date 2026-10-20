import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/kubernetes/kube_logs.dart';

void main() {
  test('shellQuote escapes single quotes', () {
    expect(shellQuote("a'b"), r"'a'\''b'");
  });

  group('kubeLogsCommand', () {
    test('relative range uses --since, no line cap', () {
      final cmd = kubeLogsCommand(
        'prod',
        'api-1',
        since: const Duration(minutes: 15),
      );
      expect(
        cmd,
        "kubectl logs -n 'prod' 'api-1' --all-containers --timestamps "
        '--since=900s 2>&1',
      );
      expect(cmd, isNot(contains('--tail')));
    });

    test('absolute range uses --since-time in UTC', () {
      final cmd = kubeLogsCommand(
        'prod',
        'api-1',
        sinceTime: DateTime.utc(2026, 10, 19, 11, 41, 36, 220),
      );
      expect(cmd, contains('--since-time=2026-10-19T11:41:36Z'));
    });

    test('all pods loops and tolerates a failing pod', () {
      final cmd = kubeLogsCommand('prod', null);
      expect(
        cmd,
        startsWith("pods=\$(kubectl get pods -n 'prod' -o name) || exit 1;"),
      );
      expect(cmd, endsWith('2>&1 || true; done'));
    });
  });

  test('parseNamespaces', () {
    expect(
      parseNamespaces('default   Active   120d\nkube-system Active 120d\n'),
      [
        (name: 'default', status: 'Active', age: '120d'),
        (name: 'kube-system', status: 'Active', age: '120d'),
      ],
    );
  });

  group('parsePods', () {
    test('plain and "(ago)" restarts, skips noise', () {
      final pods = parsePods(
        'api-1   1/1   Running            0             2d\n'
        'api-2   0/1   CrashLoopBackOff   3 (2m ago)    5h\n'
        'No resources found in prod namespace.\n',
      );
      expect(pods, [
        (
          name: 'api-1',
          ready: '1/1',
          status: 'Running',
          restarts: 0,
          age: '2d',
        ),
        (
          name: 'api-2',
          ready: '0/1',
          status: 'CrashLoopBackOff',
          restarts: 3,
          age: '5h',
        ),
      ]);
    });

    test('health', () {
      KubePod pod(String ready, String status) =>
          (name: 'p', ready: ready, status: status, restarts: 0, age: '1d');
      expect(podHealth(pod('1/1', 'Running')), PodHealth.ok);
      expect(podHealth(pod('1/2', 'Running')), PodHealth.pending);
      expect(podHealth(pod('0/1', 'Init:0/1')), PodHealth.pending);
      expect(podHealth(pod('0/1', 'CrashLoopBackOff')), PodHealth.failing);
      expect(podHealth(pod('0/1', 'Completed')), PodHealth.done);
    });
  });

  test('parseLogLines strips stamps and merges pods by time', () {
    final lines = parseLogLines(
      '2026-10-19T11:00:02.000000001Z pod-a second\n'
      '2026-10-19T11:00:03Z pod-a third\n'
      'error: container not found\n'
      '2026-10-19T11:00:01Z pod-b first\n',
    );
    expect(lines.map((l) => l.text), [
      'pod-b first',
      'pod-a second',
      'pod-a third',
      'error: container not found',
    ]);
    expect(lines.first.time, DateTime.utc(2026, 10, 19, 11, 0, 1));
  });

  group('LogQuery', () {
    bool m(String q, String text) => LogQuery(q).matches(text);

    test('all terms, case-insensitive', () {
      expect(m('error account', 'ERROR in Account'), isTrue);
      expect(m('error account', 'error only'), isFalse);
    });

    test('quoted phrase and exclusion', () {
      expect(m('"receive from"', 'receive from https://x'), isTrue);
      expect(m('"receive from"', 'from receive'), isFalse);
      expect(m('error -timeout', 'error: timeout'), isFalse);
      expect(m('error -"read timeout"', 'error: write timeout'), isTrue);
    });

    test('JSON fragments match literally, quotes included', () {
      const line = '14:06:01 sent: {"responseCode":"00","response":"06"}';
      expect(m('"response":"06"', line), isTrue);
      expect(m('"response":"06"', '14:06 {"response":"00"}'), isFalse);
      expect(m('"responseCode":"06"', line), isFalse);
      expect(m('-"response":"06"', line), isFalse);
      expect(LogQuery('"response":"06"').highlights, ['"response":"06"']);
    });

    test('OR', () {
      expect(m('ERROR OR WARN', '[ WARN] slow'), isTrue);
      expect(m('ERROR OR WARN', '[ INFO] ok'), isFalse);
    });

    test('empty matches everything', () {
      expect(LogQuery('  ').isEmpty, isTrue);
      expect(m('', 'anything'), isTrue);
    });
  });

  test('filterLogLines by absolute range and query', () {
    final lines = [
      LogLine(DateTime.utc(2026, 10, 19, 10), 'early error'),
      LogLine(DateTime.utc(2026, 10, 19, 11), 'inside error'),
      LogLine(DateTime.utc(2026, 10, 19, 11), 'inside ok'),
      LogLine(DateTime.utc(2026, 10, 19, 12), 'late error'),
    ];
    final shown = filterLogLines(
      lines,
      from: DateTime.utc(2026, 10, 19, 10, 30),
      to: DateTime.utc(2026, 10, 19, 11, 30),
      query: LogQuery('error'),
    );
    expect(shown.map((l) => l.text), ['inside error']);
    expect(filterLogLines(lines), same(lines));
  });

  group('splitLogText', () {
    test('drops the app timestamp and lifts the level', () {
      final r = splitLogText(
        '2026-10-19 14:19:03.465 [ INFO] - [77xK5] request received: {}',
      );
      expect(r.level, LogLevel.info);
      expect(r.message, '[77xK5] request received: {}');
    });

    test('slash dates, ISO stamps and bare levels', () {
      expect(
        splitLogText('2026/10/19 14:19:03 [transport] POST').message,
        '[transport] POST',
      );
      final r = splitLogText('2026-10-19T07:00:00.1Z ERROR: boom');
      expect((r.level, r.message), (LogLevel.error, 'boom'));
      expect(splitLogText('WARN slow').level, LogLevel.warn);
    });

    test('a word that starts like a level is not one', () {
      expect(splitLogText('Information only').level, isNull);
    });

    test('plain text is left alone', () {
      final r = splitLogText('\tat com.example.Foo(Foo.java:1)');
      expect((r.level, r.message), (null, '\tat com.example.Foo(Foo.java:1)'));
    });
  });

  test('LogQuery.highlights skips exclusions', () {
    expect(LogQuery('error -timeout "receive from"').highlights, [
      'error',
      'receive from',
    ]);
  });

  group('appendNewLines', () {
    LogLine at(int second, String text, [int micro = 0]) =>
        LogLine(DateTime.utc(2026, 10, 20, 9, 0, second, 0, micro), text);

    test('skips the re-read boundary second, keeps new lines', () {
      final existing = [at(1, 'a'), at(2, 'b', 300), at(2, 'c', 900)];
      // --since-time floors to 09:00:02, so b and c come back again.
      final fetched = [
        at(2, 'b', 300),
        at(2, 'c', 900),
        at(2, 'd', 950),
        at(3, 'e'),
      ];
      expect(appendNewLines(existing, fetched).map((l) => l.text), [
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
    });

    test('keepFrom drops lines that slid out of a relative range', () {
      final merged = appendNewLines(
        [at(1, 'old'), at(5, 'kept')],
        [at(9, 'new')],
        keepFrom: DateTime.utc(2026, 10, 20, 9, 0, 3),
      );
      expect(merged.map((l) => l.text), ['kept', 'new']);
    });

    test('empty existing takes everything', () {
      expect(appendNewLines(const [], [at(1, 'x')]).length, 1);
      expect(lastStamp(const []), isNull);
    });
  });

  group('huge lines', () {
    test('clipForDisplay keeps short text and counts what it cuts', () {
      expect(clipForDisplay('abc', 5), (shown: 'abc', hidden: 0));
      final huge = '/' * 1000000;
      final clip = clipForDisplay(huge, 2000);
      expect(clip.shown.length, 2000);
      expect(clip.hidden, 998000);
    });

    test('matchesLine agrees with matches and caches per line', () {
      final line = LogLine(null, 'ERROR: ${'/' * 100000} Timeout');
      final query = LogQuery('timeout');
      expect(query.matchesLine(line), isTrue);
      expect(query.matchesLine(line), query.matches(line.text));
      expect(LogQuery('-timeout').matchesLine(line), isFalse);
    });

    test('displayOf is splitLogText, cached', () {
      final line = LogLine(null, '2026-10-19 14:19:03.465 [ INFO] - hi');
      expect(displayOf(line), splitLogText(line.text));
      expect(displayOf(line).message, 'hi');
    });
  });

  group('workloads', () {
    test('workloadOf reads the controller from the pod name', () {
      expect(workloadOf('transport-core-system-75f95b665f-5zzfm'), (
        name: 'transport-core-system',
        kind: WorkloadKind.deployment,
      ));
      expect(workloadOf('postgres-0'), (
        name: 'postgres',
        kind: WorkloadKind.statefulSet,
      ));
      expect(workloadOf('fluentd-x7k2p'), (
        name: 'fluentd',
        kind: WorkloadKind.other,
      ));
      expect(workloadOf('standalone'), isNull);
    });

    test('replacementFor picks the healthy pod of the same workload', () {
      KubePod pod(String name, String status, [String ready = '1/1']) =>
          (name: name, ready: ready, status: status, restarts: 0, age: '1m');
      final pods = [
        pod('api-worker-6d5f8c9b7-aaaaa', 'Running'),
        pod('api-6d5f8c9b7-bbbbb', 'CrashLoopBackOff', '0/1'),
        pod('api-6d5f8c9b7-ccccc', 'Running'),
      ];
      expect(
        replacementFor('api-6d5f8c9b7-gone1', pods)?.name,
        'api-6d5f8c9b7-ccccc',
      );
      expect(replacementFor('db-0', pods), isNull);
    });

    test('command filters the pod list to the workload', () {
      final cmd = kubeLogsCommand(
        'prod',
        null,
        workload: (name: 'api', kind: WorkloadKind.deployment),
      );
      expect(
        cmd,
        contains(
          r"for p in $(printf '%s\n' $pods | grep -E "
          r"'^pod/api-[a-z0-9]{6,10}-[a-z0-9]{5}$');",
        ),
      );
    });
  });
}
