import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/utils/text_diff.dart';

void main() {
  test('buildTextDiff counts changes and keeps 2 lines of context', () {
    final diff = buildTextDiff(
      'a\nb\nc\nd\ne\nf\ng\nh',
      'a\nb\nc\nX\ne\nf\ng\nh',
    );

    expect(diff.added, 1);
    expect(diff.removed, 1);
    expect(diff.lines, ['  b', '  c', '- d', '+ X', '  e', '  f']);
  });

  test('buildTextDiff handles identical and binary input', () {
    expect(buildTextDiff('same', 'same').lines, ['No textual diff detected.']);
    expect(buildTextDiff(null, 'x').added, 0);
  });
}
