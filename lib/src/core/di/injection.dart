import 'dart:io';

import 'package:get_it/get_it.dart';

import '../../connection_manager/connection_backend.dart';
import '../../connection_manager/connection_manager.dart';
import '../../connection_manager/mock_backend.dart';
import '../../connection_manager/rdp_backend.dart';
import '../../connection_manager/rust_bridge_backend.dart';
import '../../connection_manager/unavailable_backend.dart';
import '../../data/repositories/settings/index.dart';
import '../../data/repositories/ssh/index.dart';
import '../../domain/repositories/settings/index.dart';
import '../../domain/repositories/ssh/index.dart';
import '../../domain/usecases/ssh/index.dart';
import '../../features/settings/bloc/index.dart';
import '../../features/sftp/bloc/index.dart';
import '../../features/ssh_profiles/bloc/index.dart';
import '../../features/ssh_sessions/bloc/index.dart';
import '../../connection_manager/profile_secret_store.dart';
import '../../security/security_policy.dart';

final sl = GetIt.instance;

Future<void> configureDependencies() async {
  final backend = await _createConnectionBackend();
  sl
    ..registerLazySingleton<SecurityPolicy>(SecurityPolicy.new)
    ..registerLazySingleton<ProfileSecretStore>(
      () => ProfileSecretStore(policy: sl()),
    )
    ..registerLazySingleton<ConnectionBackend>(() => backend)
    ..registerLazySingleton<ConnectionManager>(
      () => ConnectionManager(backend: sl(), secretStore: sl()),
      dispose: (manager) => manager.dispose(),
    )
    ..registerLazySingleton<SshProfileRepository>(
      () => InMemorySshProfileRepository(secretStore: sl()),
    )
    ..registerLazySingleton<SettingsRepository>(LocalSettingsRepository.new)
    ..registerLazySingleton(() => GetProfiles(sl()))
    ..registerLazySingleton(() => SaveProfile(sl()))
    ..registerLazySingleton(() => TestConnection(sl()))
    ..registerLazySingleton(() => ConnectProfile(sl()))
    ..registerLazySingleton(() => DeleteProfile(sl()))
    ..registerFactory(
      () => SshWorkspaceBloc(
        getProfiles: sl(),
        saveProfile: sl(),
        testConnection: sl(),
        deleteProfile: sl(),
      ),
    )
    ..registerFactory(
      () => SettingsBloc(repository: sl(), securityPolicy: sl()),
    )
    ..registerFactory(() => SftpWorkspaceBloc(getProfiles: sl()))
    ..registerFactory(SshSessionBloc.new);

  // Register RDP backend lazily — it requires Rust library to be already loaded
  // by the SSH backend above.
  try {
    final rdpBackend = await RdpBackend.create();
    sl.registerLazySingleton<RdpBackend>(() => rdpBackend);
  } catch (_) {
    // RDP not available (e.g. mock mode or mobile). Consumers should check
    // sl.isRegistered<RdpBackend>() before using it.
  }
}

Future<ConnectionBackend> _createConnectionBackend() async {
  const backendMode = String.fromEnvironment(
    'PORTIX_BACKEND',
    defaultValue: 'rust',
  );
  if (backendMode == 'mock') return MockConnectionBackend();
  if (Platform.isAndroid || Platform.isIOS) {
    return UnavailableConnectionBackend(
      'Mobile SSH backend is disabled for now. Use the desktop app while the mobile Rust library bundling is being prepared.',
    );
  }

  try {
    return await RustBridgeBackend.create();
  } catch (error) {
    return UnavailableConnectionBackend(error);
  }
}
