import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/constants/file_extensions.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

void main() {
  test('programs and launchers count as runnable', () {
    for (final name in [
      'setup.exe',
      'SETUP.EXE',
      'run.bat',
      'start.cmd',
      'link.lnk',
      'tool.ps1',
      'page.hta',
      'x.desktop',
      'x.command',
      'app.jar',
      'invoice.pdf.exe',
      'trailing.exe.',
      'trailing.exe ',
    ]) {
      expect(isRunnableFileName(name), isTrue, reason: name);
    }
  });

  test('documents and archives do not', () {
    for (final name in ['report.pdf', 'a.docx', 'b.tar.gz', 'notes', '.env']) {
      expect(isRunnableFileName(name), isFalse, reason: name);
    }
  });

  Future<bool?> ask(WidgetTester tester, String button) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await confirmOpenRunnable(context, 'setup.exe');
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('setup.exe'), findsOneWidget);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('Cancel refuses to open the file', (tester) async {
    expect(await ask(tester, 'Cancel'), isFalse);
  });

  testWidgets('Open anyway lets it through', (tester) async {
    expect(await ask(tester, 'Open anyway'), isTrue);
  });
}
