part of 'settings_bloc.dart';

enum SettingsStatus { initial, loading, ready, saving, failure }

class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsStatus.initial,
    this.selectedId = 'configuration',
    this.defaults = const {},
    this.savedValues = const {},
    this.draftValues = const {},
    this.lastSavedAt,
    this.message = '',
  });

  final SettingsStatus status;
  final String selectedId;
  final Map<String, String> defaults;
  final Map<String, String> savedValues;
  final Map<String, String> draftValues;
  final DateTime? lastSavedAt;
  final String message;

  bool get dirty => !_mapEquals(savedValues, draftValues);
  bool get busy =>
      status == SettingsStatus.loading || status == SettingsStatus.saving;

  String valueFor(String key, String fallback) {
    return draftValues[key] ?? savedValues[key] ?? defaults[key] ?? fallback;
  }

  SettingsState copyWith({
    SettingsStatus? status,
    String? selectedId,
    Map<String, String>? defaults,
    Map<String, String>? savedValues,
    Map<String, String>? draftValues,
    DateTime? lastSavedAt,
    String? message,
  }) {
    return SettingsState(
      status: status ?? this.status,
      selectedId: selectedId ?? this.selectedId,
      defaults: defaults ?? this.defaults,
      savedValues: savedValues ?? this.savedValues,
      draftValues: draftValues ?? this.draftValues,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      message: message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [
    status,
    selectedId,
    defaults,
    savedValues,
    draftValues,
    lastSavedAt,
    message,
  ];
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
