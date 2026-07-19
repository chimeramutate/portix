abstract interface class SettingsRepository {
  Future<Map<String, String>> loadSettings();
  Future<void> saveSettings(Map<String, String> values);
  Future<void> clearSettings();
}
