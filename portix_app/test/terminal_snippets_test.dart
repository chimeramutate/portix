import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_snippets.dart';

void main() {
  test('finds distinct placeholders in order', () {
    expect(
      snippetVariables('scp {{file}} {{ host }}:{{file}} && echo {{x-1}}'),
      ['file', 'host', 'x-1'],
    );
    expect(snippetVariables('ls -la'), isEmpty);
    expect(snippetVariables(r'echo ${HOME} {{}}'), isEmpty);
  });

  test('fills every occurrence and leaves unknown names untouched', () {
    expect(
      fillSnippet('tail -f {{log}} | grep {{ term }} # {{log}} {{other}}', {
        'log': '/var/log/syslog',
        'term': 'error',
      }),
      'tail -f /var/log/syslog | grep error # /var/log/syslog {{other}}',
    );
  });
}
