import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SettingsRepository {
  const SettingsRepository();

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

  Future<void> saveSettings(Map<String, String> values) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(values));
  }

  Future<File> _settingsFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}settings.json');
  }
}
