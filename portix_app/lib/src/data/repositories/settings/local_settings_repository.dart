import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:portix/src/domain/repositories/settings/index.dart';

class LocalSettingsRepository implements SettingsRepository {
  const LocalSettingsRepository();

  @override
  Future<Map<String, String>> loadSettings() async {
    final file = await _settingsFile();
    if (!await file.exists()) return const {};
    final content = await file.readAsString();
    if (content.trim().isEmpty) return const {};
    final json = jsonDecode(content) as Map<String, Object?>;
    return {
      for (final entry in json.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
  }

  @override
  Future<void> saveSettings(Map<String, String> values) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(values));
  }

  @override
  Future<void> clearSettings() async {
    final file = await _settingsFile();
    if (await file.exists()) await file.delete();
  }

  Future<File> _settingsFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}settings.json');
  }
}
