import 'dart:io';

import 'package:get_it/get_it.dart';

import '../../connection_manager/connection_backend.dart';
import '../../connection_manager/connection_manager.dart';
import '../../connection_manager/mock_backend.dart';
import '../../connection_manager/rust_bridge_backend.dart';
import '../../connection_manager/unavailable_backend.dart';
import '../../connection_manager/profile_secret_store.dart';
import '../../data/repositories/settings/index.dart';
import '../../domain/repositories/settings/index.dart';
import '../../domain/repositories/ssh/index.dart';
import '../../features/rdp/service/rdp_backend_service.dart';
import '../../features/settings/bloc/index.dart';
import '../../features/sftp/bloc/index.dart';
import '../../features/ssh_profiles/bloc/index.dart';
import '../../features/ssh_sessions/bloc/index.dart';
import '../../security/security_policy.dart';

final sl = GetIt.instance;

Future<void> configureDependencies() async {
  final backend = await _createConnectionBackend();
  await _initRdpBackend();
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
      () => SshProfileRepository(secretStore: sl()),
    )
    ..registerLazySingleton<SettingsRepository>(LocalSettingsRepository.new)
    ..registerLazySingleton<RdpBackendService>(RdpBackendService.new)
    ..registerFactory(() => SshWorkspaceBloc(repository: sl()))
    ..registerFactory(
      () => SettingsBloc(repository: sl(), securityPolicy: sl()),
    )
    ..registerFactory(() => SftpWorkspaceBloc(repository: sl()))
    ..registerFactory(SshSessionBloc.new);
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

Future<void> _initRdpBackend() async {
  if (Platform.isAndroid || Platform.isIOS) return;
  try {
    const rustLibraryMode = String.fromEnvironment(
      'RUST_LIBRARY_MODE',
      defaultValue: 'dev',
    );
    if (rustLibraryMode == 'production') {
      await RdpBackendService.initProduction();
    } else {
      await RdpBackendService.initDev();
    }
  } catch (error) {
    // RDP backend init failure is non-fatal — SSH still works.
    // RdpBackendService calls will fail gracefully at call site.
    // ignore: avoid_print
    print('Warning: RDP backend init failed: $error');
  }
}
