import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/rust_rdp/api.dart' as rdp_api;
import 'package:portix/src/rust_rdp/domain/events.dart';
import 'package:portix/src/rust_rdp/domain/profile.dart' as rdp_profile;
import 'package:portix/src/rust_rdp/domain/session.dart';
import 'package:portix/src/rust_rdp/frb_generated.dart';

class RdpBackendService {
  RdpBackendService() {
    _initPersistentStreams();
  }

  final Map<String, String> _activeSessions = {};
  final Map<String, String> _sessionToProfile = {};

  // ──────────────────────────────────────────────────────────────────────
  // PERSISTENT BROADCAST STREAMS
  //
  // StreamController.broadcast() tidak pernah close dan tidak bergantung
  // pada jumlah listener. Subscriber Rust dibuat sekali saat init dan
  // me-forward semua event ke controller ini.
  //
  // Viewer dan internal listener cukup listen ke _frame/status/errorCtrl
  // tanpa pernah menyentuh Rust API secara langsung.
  // ──────────────────────────────────────────────────────────────────────
  final _frameCtrl = StreamController<RdpFrameEvent>.broadcast();
  final _statusCtrl = StreamController<RdpStatusEvent>.broadcast();
  final _errorCtrl = StreamController<RdpErrorEvent>.broadcast();

  StreamSubscription<RdpFrameEvent>? _frameSub;
  StreamSubscription<RdpStatusEvent>? _statusSub;
  StreamSubscription<RdpErrorEvent>? _errorSub;

  void _initPersistentStreams() {
    // Subscribe ke Rust SEKALI — event di-forward ke controller broadcast
    _frameSub = rdp_api.rdpFrameStream().listen(
      _frameCtrl.add,
      onError: _frameCtrl.addError,
    );

    _statusSub = rdp_api.rdpStatusStream().listen((event) {
      // Update session map
      switch (event.status) {
        case RdpConnectionStatus.connected:
          break;
        case RdpConnectionStatus.disconnected:
        case RdpConnectionStatus.error:
          final profileId = _sessionToProfile.remove(event.sessionId);
          if (profileId != null) {
            _activeSessions.remove(profileId);
          }
          break;
        case RdpConnectionStatus.connecting:
          break;
      }
      _statusCtrl.add(event);
    }, onError: _statusCtrl.addError);

    _errorSub = rdp_api.rdpErrorStream().listen((event) {
      if (event.sessionId != null) {
        final profileId = _sessionToProfile.remove(event.sessionId);
        if (profileId != null) {
          _activeSessions.remove(profileId);
        }
      }
      _errorCtrl.add(event);
    }, onError: _errorCtrl.addError);
  }

  // Stream publik — viewer dan internal listener pakai ini
  Stream<RdpFrameEvent> frameStream() => _frameCtrl.stream;
  Stream<RdpStatusEvent> statusStream() => _statusCtrl.stream;
  Stream<RdpErrorEvent> errorStream() => _errorCtrl.stream;

  Future<void> sendMouseWheel(
    String sessionId,
    int x,
    int y,
    int delta, {
    bool isVertical = true,
  }) async {
    if (!_sessionToProfile.containsKey(sessionId)) {
      return;
    }

    try {
      await rdp_api.rdpSendMouseWheel(
        sessionId: sessionId,
        x: x,
        y: y,
        delta: delta,
        isVertical: isVertical,
      );
    } catch (e) {
      debugPrint('[RDP] sendMouseWheel error: $e');
    }
  }

  static Future<void> initDev() async {
    await RdpRustLib.init();
  }

  static String productionPathHint() => _productionLibraryPath();

  static Future<void> initProduction() async {
    await RdpRustLib.init(
      externalLibrary: ExternalLibrary.open(
        _productionLibraryPath(),
        debugInfo: 'Portix RDP library',
      ),
    );
  }

  Future<Either<Failure, RdpProfile>> parseRdpFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Left(Failure('File tidak ditemukan: $filePath'));
      }
      final content = await file.readAsString();
      return parseRdpContent(content);
    } catch (e) {
      return Left(Failure('Gagal membaca file .rdp: $e'));
    }
  }

  Future<Either<Failure, RdpProfile>> parseRdpContent(
    String content, {
    String? profileName,
  }) async {
    try {
      final sessionInfo = await rdp_api.rdpParseFile(
        rdpContent: content,
        profileName: profileName,
      );
      final parser = RdpFileParser();
      final profile = parser.parse(
        content,
        profileId: sessionInfo.id,
        filePath: null,
      );
      return Right(profile);
    } catch (e) {
      return Left(Failure('Gagal mem-parse .rdp: $e'));
    }
  }

  Future<Either<Failure, RdpConnectionResult>> connect(
    RdpProfile profile,
  ) async {
    try {
      final existingSessionId = _activeSessions[profile.id];
      if (existingSessionId != null) {
        debugPrint(
          '[RDP] Dart-side: profile ${profile.id} already has session $existingSessionId',
        );
        return Right(
          RdpConnectionResult(
            sessionId: existingSessionId,
            profileId: profile.id,
            host: profile.host,
            port: profile.port,
          ),
        );
      }

      final rustProfile = profile.toRustProfile();
      final sessionInfo = await rdp_api.rdpConnect(profile: rustProfile);

      _activeSessions[profile.id] = sessionInfo.id;
      _sessionToProfile[sessionInfo.id] = profile.id;

      return Right(
        RdpConnectionResult(
          sessionId: sessionInfo.id,
          profileId: sessionInfo.profileId,
          host: profile.host,
          port: profile.port,
        ),
      );
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('already has active session')) {
        debugPrint('[RDP] Recovering from duplicate session error');
        return Left(Failure('Session already active. Please try again.'));
      }

      return Left(Failure('Gagal connect ke RDP server: $e'));
    }
  }

  Future<Either<Failure, void>> disconnect(String sessionId) async {
    try {
      final profileId = _sessionToProfile.remove(sessionId);
      if (profileId != null) {
        _activeSessions.remove(profileId);
      }

      await rdp_api.rdpDisconnect(sessionId: sessionId);
      return const Right(null);
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('not found') || errorMsg.contains('may already')) {
        debugPrint('[RDP] Disconnect: session $sessionId already gone');
        return const Right(null);
      }
      return Left(Failure('Gagal disconnect: $e'));
    }
  }

  bool isSessionActiveForProfile(String profileId) {
    return _activeSessions.containsKey(profileId);
  }

  String? getActiveSessionId(String profileId) {
    return _activeSessions[profileId];
  }

  Map<String, String> get activeSessions => Map.unmodifiable(_activeSessions);

  Future<void> sendMouseMove(String sessionId, int x, int y) async {
    if (!_sessionToProfile.containsKey(sessionId)) return;
    try {
      await rdp_api.rdpSendMouseMove(sessionId: sessionId, x: x, y: y);
    } catch (e) {
      debugPrint('[RDP] sendMouseMove error: $e');
    }
  }

  Future<void> sendMouseButton(
    String sessionId,
    int x,
    int y,
    int button,
    bool down,
  ) async {
    if (!_sessionToProfile.containsKey(sessionId)) return;
    try {
      await rdp_api.rdpSendMouseButton(
        sessionId: sessionId,
        x: x,
        y: y,
        button: button,
        down: down,
      );
    } catch (e) {
      debugPrint('[RDP] sendMouseButton error: $e');
    }
  }

  Future<void> sendKeyboardInput(
    String sessionId,
    int scancode,
    bool down,
  ) async {
    if (!_sessionToProfile.containsKey(sessionId)) return;
    try {
      await rdp_api.rdpSendKeyboardInput(
        sessionId: sessionId,
        scancode: scancode,
        down: down,
      );
    } catch (e) {
      debugPrint('[RDP] sendKeyboardInput error: $e');
    }
  }

  void dispose() {
    _frameSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _frameCtrl.close();
    _statusCtrl.close();
    _errorCtrl.close();
    _activeSessions.clear();
    _sessionToProfile.clear();
  }
}

class RdpConnectionResult {
  const RdpConnectionResult({
    required this.sessionId,
    required this.profileId,
    required this.host,
    required this.port,
  });

  final String sessionId;
  final String profileId;
  final String host;
  final int port;
}

extension on RdpProfile {
  rdp_profile.RdpProfile toRustProfile() {
    return rdp_profile.RdpProfile(
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      password: password,
      domain: domain,

      desktopWidth: desktopWidth,
      desktopHeight: desktopHeight,
      fullScreen: fullScreen,

      enableCredSsp: enableCredSsp,

      // RDP device redirection
      redirectDrives: redirectDrives,
      redirectClipboard: redirectClipboard,

      // Nama share yang akan terlihat di remote Windows.
      // Misalnya: "PORTIX"
      localShareName: LocalSharePath ?? 'PORTIX',

      alternateShell: alternateShell.isEmpty ? null : alternateShell,

      sourceRdpContent: null,
    );
  }
}

String _productionLibraryPath() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isMacOS) return '$executableDir/libportix_rdp.dylib';
  if (Platform.isWindows) return '$executableDir\\portix_rdp.dll';
  if (Platform.isLinux) return '$executableDir/libportix_rdp.so';
  throw UnsupportedError('Unsupported platform');
}
