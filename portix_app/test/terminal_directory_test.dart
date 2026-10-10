import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_session_ui_controller.dart';

void main() {
  test('working directory from prompt title and OSC 7', () {
    expect(terminalDirectoryFrom(title: 'root@srv: /tmp'), '/tmp');
    expect(terminalDirectoryFrom(title: 'ubuntu@ip-10-0-0-1: ~/app'), '~/app');
    expect(terminalDirectoryFrom(title: 'vim notes.txt'), isNull);
    expect(
      terminalDirectoryFrom(osc7: 'file://srv/var/my%20dir'),
      '/var/my dir',
    );
    expect(terminalDirectoryFrom(osc7: 'http://x/y'), isNull);
  });
}
