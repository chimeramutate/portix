import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_telemetry_controller.dart';

class _TelemetryBackend extends MockConnectionBackend {
  bool fail = false;

  @override
  Future<RemoteSystemSnapshot> remoteSystemSnapshot(String sessionId) async {
    if (fail) throw StateError('host down');
    return const RemoteSystemSnapshot(
      os: 'Ubuntu 24.04',
      hostname: 'h',
      uptime: '1d',
      memory: '',
      disk: '',
      memoryUsedBytes: 1,
      memoryTotalBytes: 4,
      diskUsedBytes: 1,
      diskTotalBytes: 2,
    );
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

void main() {
  test('records samples, reports the OS, and closes after two failures', () async {
    final backend = _TelemetryBackend();
    final manager = ConnectionManager(backend: backend);
    addTearDown(manager.dispose);
    await manager.connect(
      const SshProfile(id: 'p', name: 'p', host: 'h', port: 22, username: 'u'),
    );
    await _until(
      () => manager.sessions.single.status == ConnectionStatus.connected,
    );
    final sessionId = manager.sessions.single.id;

    final detectedOs = <String>[];
    final telemetry = TerminalTelemetryController(
      connectionManager: manager,
      onOsDetected: (_, asset) => detectedOs.add(asset),
    );
    addTearDown(telemetry.dispose);

    telemetry.track(sessionId);
    await _until(() => telemetry.samples.isNotEmpty);
    expect(telemetry.samples.single.memoryPercent, 25);
    expect(telemetry.samples.single.diskPercent, 50);
    expect(detectedOs, ['assets/icons/os/ubuntu-linux.svg']);

    backend.fail = true;
    await telemetry.refresh();
    expect(manager.sessions, isNotEmpty, reason: 'one failure is tolerated');
    await telemetry.refresh();
    expect(manager.sessions, isEmpty);
  });
}
