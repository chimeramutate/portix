import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/domain/repositories/settings/index.dart';

part 'settings_event.dart';
part 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({required SettingsRepository repository})
    : _repository = repository,
      super(const SettingsState()) {
    on<SettingsStarted>(_onStarted);
    on<SettingsSectionSelected>(_onSectionSelected);
    on<SettingsValueChanged>(_onValueChanged);
    on<SettingsSaved>(_onSaved);
    on<SettingsReverted>(_onReverted);
    on<SettingsReset>(_onReset);
  }

  final SettingsRepository _repository;

  Future<void> _onStarted(
    SettingsStarted event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(status: SettingsStatus.loading));
    try {
      final stored = await _repository.loadSettings();
      final savedValues = {...event.defaults, ...stored};
      emit(
        state.copyWith(
          status: SettingsStatus.ready,
          selectedId: event.initialSelectedId,
          defaults: event.defaults,
          savedValues: savedValues,
          draftValues: savedValues,
          lastSavedAt: DateTime.now(),
          message: '',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          message: 'Failed to load settings: $error',
        ),
      );
    }
  }

  void _onSectionSelected(
    SettingsSectionSelected event,
    Emitter<SettingsState> emit,
  ) {
    emit(state.copyWith(selectedId: event.id, message: ''));
  }

  void _onValueChanged(
    SettingsValueChanged event,
    Emitter<SettingsState> emit,
  ) {
    final nextDraft = {...state.draftValues, event.key: event.value};
    emit(state.copyWith(draftValues: nextDraft, message: ''));
  }

  Future<void> _onSaved(
    SettingsSaved event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(status: SettingsStatus.saving));
    try {
      await _repository.saveSettings(state.draftValues);
      emit(
        state.copyWith(
          status: SettingsStatus.ready,
          savedValues: state.draftValues,
          lastSavedAt: DateTime.now(),
          message: 'Settings saved locally.',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          message: 'Failed to save settings: $error',
        ),
      );
    }
  }

  void _onReverted(SettingsReverted event, Emitter<SettingsState> emit) {
    emit(
      state.copyWith(
        status: SettingsStatus.ready,
        draftValues: state.savedValues,
        message: 'Draft changes reverted.',
      ),
    );
  }

  Future<void> _onReset(
    SettingsReset event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(status: SettingsStatus.saving));
    try {
      // Only the values this page shows: the same file also holds terminal
      // snippets and the theme picked from the terminal.
      final stored = await _repository.loadSettings();
      await _repository.saveSettings({
        for (final entry in stored.entries)
          if (!state.defaults.containsKey(entry.key)) entry.key: entry.value,
      });
      emit(
        state.copyWith(
          status: SettingsStatus.ready,
          savedValues: state.defaults,
          draftValues: state.defaults,
          lastSavedAt: DateTime.now(),
          message: 'Settings reset to defaults.',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: SettingsStatus.failure,
          message: 'Failed to reset settings: $error',
        ),
      );
    }
  }
}
