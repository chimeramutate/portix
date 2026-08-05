import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/domain/repositories/rdp/index.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';
import 'package:portix/src/rust_rdp/api.dart' as rdp_api;
import 'package:portix/src/rust_rdp/domain/events.dart';
import 'package:portix/src/rust_rdp/domain/profile.dart' as rdp_profile;
import 'package:portix/src/rust_rdp/domain/session.dart';
import 'package:portix/src/rust_rdp/frb_generated.dart';

class RdpBackendService {
  RdpBackendService() {
    _initStreamSubscriptions();
  }

  final Map<String, String> _activeSessions = {};
  final Map<String, String> _sessionToProfile = {};

  // ──────────────────────────────────────────────────────────────────────
  // FRAME BUFFER PER SESSION
  //
  // Rust mulai mengirim frame SEGERA setelah connect() — jauh sebelum
  // viewer widget selesai dibuat dan subscribe ke stream.
  // Buffer ini menampung frame yang datang sebelum viewer subscribe,
  // lalu di-flush saat viewer pertama kali listen via frameStream().
  //
  // Batas: 256 frame per session (≈ burst awal xRDP login screen).
  // ──────────────────────────────────────────────────────────────────────
  static const int _maxBufferedFrames = 256;
  final Map<String, List<RdpFrameEvent>> _frameBuffer = {};
  final Map<String, StreamController<RdpFrameEvent>> _frameControllers = {};
  StreamSubscription<RdpFrameEvent>? _rawFrameSub;

  void _initStreamSubscriptions() {
    statusStream().listen((event) {
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
    });

    errorStream().listen((event) {
      if (event.sessionId != null) {
        final profileId = _sessionToProfile.remove(event.sessionId);
        if (profileId != null) {
          _activeSessions.remove(profileId);
        }
      }
    });
  }

  static Future<void> initDev() async {
    await RustLib.init();
  }

  static String productionPathHint() => _productionLibraryPath();

  static Future<void> initProduction() async {
    await RustLib.init(
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

  // Stream sekarang langsung mengembalikan object dari FRB tanpa jsonDecode
  Stream<RdpFrameEvent> frameStream() {
    return rdp_api.rdpFrameStream();
  }

  Stream<RdpStatusEvent> statusStream() {
    return rdp_api.rdpStatusStream();
  }

  Stream<RdpErrorEvent> errorStream() {
    return rdp_api.rdpErrorStream();
  }

  void dispose() {
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
  rdp_profile.RdpProfile toRustProfile() => rdp_profile.RdpProfile(
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
    alternateShell: alternateShell.isEmpty ? null : alternateShell,
    sourceRdpContent: null,
  );
}

String _productionLibraryPath() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isMacOS) return '$executableDir/libportix_rdp.dylib';
  if (Platform.isWindows) return '$executableDir\\portix_rdp.dll';
  if (Platform.isLinux) return '$executableDir/libportix_rdp.so';
  throw UnsupportedError('Unsupported platform');
}
