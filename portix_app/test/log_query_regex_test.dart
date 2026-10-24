import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/kubernetes/kube_logs.dart';

void main() {
  test('re: token matches a case-insensitive regex', () {
    final q = LogQuery(r're:status:\s(5\d\d|4\d\d)');
    expect(q.matches('receive from x status: 503 Service'), isTrue);
    expect(q.matches('receive from x status: 200 OK'), isFalse);
  });

  test('re: excludes with a leading minus and combines with terms', () {
    final q = LogQuery(r'receive -re:timeout OR receive re:dormant');
    expect(q.matches('receive from x dormant'), isTrue);
    expect(q.matches('receive from x timeout'), isFalse);
  });

  test('half-typed regex falls back to literal matching', () {
    final q = LogQuery('re:(send');
    expect(q.matches('typed re:(send here'), isTrue);
    expect(q.matches('send to x'), isFalse);
    expect(q.highlights.single.hasMatch('re:(send'), isTrue);
  });
}
