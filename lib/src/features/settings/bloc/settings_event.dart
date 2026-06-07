part of 'settings_bloc.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => const [];
}

class SettingsStarted extends SettingsEvent {
  const SettingsStarted({
    required this.defaults,
    this.initialSelectedId = 'configuration',
  });

  final Map<String, String> defaults;
  final String initialSelectedId;

  @override
  List<Object?> get props => [defaults, initialSelectedId];
}

class SettingsSectionSelected extends SettingsEvent {
  const SettingsSectionSelected(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

class SettingsValueChanged extends SettingsEvent {
  const SettingsValueChanged({required this.key, required this.value});

  final String key;
  final String value;

  @override
  List<Object?> get props => [key, value];
}

class SettingsSaved extends SettingsEvent {
  const SettingsSaved();
}

class SettingsReverted extends SettingsEvent {
  const SettingsReverted();
}

class SettingsReset extends SettingsEvent {
  const SettingsReset();
}
