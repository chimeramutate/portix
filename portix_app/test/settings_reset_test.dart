import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/repositories/settings/index.dart';
import 'package:portix/src/features/settings/bloc/index.dart';

class _MemorySettings implements SettingsRepository {
  _MemorySettings(this.values);

  Map<String, String> values;

  @override
  Future<Map<String, String>> loadSettings() async => {...values};

  @override
  Future<void> saveSettings(Map<String, String> values) async =>
      this.values = {...values};
}

void main() {
  test('Reset restores the page defaults but keeps snippets', () async {
    final repository = _MemorySettings({
      'general.terminal_font': 'Fira Code',
      'terminal.snippets': '[{"name":"logs","command":"tail -f"}]',
    });
    final bloc = SettingsBloc(repository: repository);
    addTearDown(bloc.close);

    bloc.add(
      const SettingsStarted(defaults: {'general.terminal_font': 'Monospace'}),
    );
    await bloc.stream.firstWhere((s) => s.status == SettingsStatus.ready);
    bloc.add(const SettingsReset());
    await bloc.stream.firstWhere(
      (s) => s.status == SettingsStatus.ready && s.message.isNotEmpty,
    );

    expect(repository.values, {
      'terminal.snippets': '[{"name":"logs","command":"tail -f"}]',
    });
    expect(bloc.state.draftValues['general.terminal_font'], 'Monospace');
  });
}
