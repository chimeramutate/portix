import 'package:get_it/get_it.dart';

import '../../connection_manager/connection_backend.dart';
import '../../connection_manager/connection_manager.dart';
import '../../connection_manager/mock_backend.dart';
import '../../connection_manager/rust_bridge_backend.dart';
import '../../connection_manager/unavailable_backend.dart';
import '../../data/repositories/ssh/index.dart';
import '../../domain/repositories/ssh/index.dart';
import '../../domain/usecases/ssh/index.dart';
import '../../features/sftp/bloc/index.dart';
import '../../features/ssh_profiles/bloc/index.dart';

final sl = GetIt.instance;

Future<void> configureDependencies() async {
  final backend = await _createConnectionBackend();
  sl
    ..registerLazySingleton<ConnectionBackend>(() => backend)
    ..registerLazySingleton<ConnectionManager>(
      () => ConnectionManager(backend: sl()),
      dispose: (manager) => manager.dispose(),
    )
    ..registerLazySingleton<SshProfileRepository>(
      InMemorySshProfileRepository.new,
    )
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
    ..registerFactory(() => SftpWorkspaceBloc(getProfiles: sl()));
}

Future<ConnectionBackend> _createConnectionBackend() async {
  const backendMode = String.fromEnvironment(
    'PORTIX_BACKEND',
    defaultValue: 'rust',
  );
  if (backendMode == 'mock') return MockConnectionBackend();

  try {
    return await RustBridgeBackend.create();
  } catch (error) {
    return UnavailableConnectionBackend(error);
  }
}
