import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../connection_manager/connection_manager.dart';
import '../../../connection_manager/session_models.dart';

class RemoteMetricSample {
  const RemoteMetricSample({
    required this.createdAt,
    required this.memoryPercent,
    required this.diskPercent,
    this.cpuPercent,
  });

  final DateTime createdAt;
  final double memoryPercent;
  final double diskPercent;
  final double? cpuPercent;
}

/// Polls the tracked SSH session's system snapshot every 4 s for the status
/// footer and keeps a short memory/disk history.
///
/// Two consecutive failures close the session, so the disconnect overlay
/// shows right away instead of waiting for the Rust keepalive (~17 s).
class TerminalTelemetryController extends ChangeNotifier {
  TerminalTelemetryController({
    required ConnectionManager connectionManager,
    required this.onOsDetected,
  }) : _connectionManager = connectionManager;

  static const _pollInterval = Duration(seconds: 4);
  static const _maxSamples = 36;

  final ConnectionManager _connectionManager;

  /// Called with the tracked session id and the OS icon of its host.
  final void Function(String sessionId, String osIconAsset) onOsDetected;

  RemoteSystemSnapshot? snapshot;
  String? error;
  final List<RemoteMetricSample> samples = [];

  Timer? _timer;
  String? _sessionId;
  bool _loading = false;
  bool _disposed = false;
  int _consecutiveFailures = 0;

  /// Starts polling [sessionId] (or stops when null). No-op if unchanged.
  void track(String? sessionId) {
    if (_sessionId == sessionId) return;
    _timer?.cancel();
    _sessionId = sessionId;
    _consecutiveFailures = 0;
    clear();
    if (sessionId == null) return;
    unawaited(refresh());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(refresh()));
  }

  void clear({String? error}) {
    _loading = false;
    snapshot = null;
    this.error = error;
    samples.clear();
    notifyListeners();
  }

  Future<void> refresh() async {
    final sessionId = _sessionId;
    if (sessionId == null || !_isConnected(sessionId) || _loading) return;
    _loading = true;
    final result = await _connectionManager.remoteSystemSnapshot(sessionId);
    _loading = false;
    if (_disposed || _sessionId != sessionId) return;
    result.fold(
      (failure) {
        error = failure.message;
        notifyListeners();
        _consecutiveFailures++;
        if (_consecutiveFailures >= 2 && _isConnected(sessionId)) {
          _consecutiveFailures = 0;
          unawaited(_connectionManager.closeSession(sessionId));
        }
      },
      (next) {
        _consecutiveFailures = 0;
        onOsDetected(sessionId, osIconAssetFor(next.os));
        snapshot = next;
        error = null;
        samples.add(
          RemoteMetricSample(
            createdAt: DateTime.now(),
            memoryPercent: _percent(
              next.memoryUsedBytes,
              next.memoryTotalBytes,
            ),
            diskPercent: _percent(next.diskUsedBytes, next.diskTotalBytes),
          ),
        );
        if (samples.length > _maxSamples) {
          samples.removeRange(0, samples.length - _maxSamples);
        }
        notifyListeners();
      },
    );
  }

  bool _isConnected(String sessionId) => _connectionManager.sessions.any(
    (session) =>
        session.id == sessionId && session.status == ConnectionStatus.connected,
  );

  static double _percent(int used, int total) =>
      total <= 0 ? 0 : (used / total * 100).clamp(0, 100).toDouble();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Icon asset for a remote OS name as reported by the telemetry snapshot.
String osIconAssetFor(String os) {
  final normalized = os.toLowerCase();
  if (normalized.contains('ubuntu')) return 'assets/icons/os/ubuntu-linux.svg';
  if (normalized.contains('debian')) return 'assets/icons/os/debian-linux.svg';
  if (normalized.contains('fedora')) return 'assets/icons/os/fedora-linux.svg';
  if (normalized.contains('centos')) return 'assets/icons/os/centos-linux.svg';
  if (normalized.contains('red hat') || normalized.contains('redhat')) {
    return 'assets/icons/os/redhat-linux.svg';
  }
  if (normalized.contains('arch')) return 'assets/icons/os/arch-linux.svg';
  if (normalized.contains('windows')) return 'assets/icons/os/windows.svg';
  if (normalized.contains('darwin') ||
      normalized.contains('mac') ||
      normalized.contains('apple')) {
    return 'assets/icons/os/apple.svg';
  }
  return 'assets/icons/os/linux.svg';
}
