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

  final _frameCtrl = StreamController<RdpFrameEvent>.broadcast();
  final _statusCtrl = StreamController<RdpStatusEvent>.broadcast();
  final _errorCtrl = StreamController<RdpErrorEvent>.broadcast();

  StreamSubscription<RdpFrameEvent>? _frameSub;
  StreamSubscription<RdpStatusEvent>? _statusSub;
  StreamSubscription<RdpErrorEvent>? _errorSub;

  void _initPersistentStreams() {
    _frameSub = rdp_api.rdpFrameStream().listen(
      _frameCtrl.add,
      onError: _frameCtrl.addError,
    );

    _statusSub = rdp_api.rdpStatusStream().listen((event) {
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
    if (RdpRustLib.instance.initialized) return;
    await RdpRustLib.init();
  }

  static String productionPathHint() => _productionLibraryPath();

  static Future<void> initProduction() async {
    if (RdpRustLib.instance.initialized) return;
    await RdpRustLib.init(
      externalLibrary: ExternalLibrary.open(
        _productionLibraryPath(),
        debugInfo: 'Portix RDP library',
      ),
    );
  }

  void attachExistingSession({
    required String profileId,
    required String sessionId,
  }) {
    _activeSessions[profileId] = sessionId;
    _sessionToProfile[sessionId] = profileId;
  }

  Future<Either<Failure, RdpProfile>> parseRdpFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Left(Failure('File tidak ditemukan: $filePath'));
      }
      final content = await file.readAsString();
      return parseRdpContent(content, filePath: filePath);
    } catch (e) {
      return Left(Failure('Gagal membaca file .rdp: $e'));
    }
  }

  Future<Either<Failure, RdpProfile>> parseRdpContent(
    String content, {
    String? profileName,
    String? filePath,
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
        filePath: filePath,
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
          '[RDP] Dart-side: profile ${profile.id} already has session '
          '$existingSessionId — returning existing',
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
      if (rustProfile.redirectDrives && rustProfile.localSharePath != null) {
        await Directory(rustProfile.localSharePath!).create(recursive: true);
      }

      RdpSessionInfo? sessionInfo;
      String? lastError;

      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          sessionInfo = await rdp_api.rdpConnect(profile: rustProfile);
          lastError = null;
          break;
        } catch (e) {
          lastError = e.toString();
          if (lastError.contains('already has active session')) {
            debugPrint(
              '[RDP] connect attempt ${attempt + 1}: session still alive in '
              'Rust, waiting 600ms for cleanup…',
            );
            await Future<void>.delayed(const Duration(milliseconds: 600));
          } else {
            rethrow;
          }
        }
      }

      if (sessionInfo == null) {
        return Left(
          Failure(
            lastError ??
                'Failed to connect: session still active. '
                    'Please wait a moment and try again.',
          ),
        );
      }

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

  Future<void> pasteTextAsKeystrokes(String sessionId, String text) async {
    if (!_sessionToProfile.containsKey(sessionId)) return;

    for (final codeUnit in text.codeUnits) {
      final stroke = _KeyboardStroke.fromAscii(codeUnit);
      if (stroke == null) continue;

      if (stroke.shift) {
        await sendKeyboardInput(sessionId, _KeyboardStroke.shiftLeft, true);
      }
      await sendKeyboardInput(sessionId, stroke.hidUsage, true);
      await sendKeyboardInput(sessionId, stroke.hidUsage, false);
      if (stroke.shift) {
        await sendKeyboardInput(sessionId, _KeyboardStroke.shiftLeft, false);
      }

      await Future<void>.delayed(const Duration(milliseconds: 8));
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

class _KeyboardStroke {
  const _KeyboardStroke(this.hidUsage, {this.shift = false});

  static const int shiftLeft = 0xE1;

  final int hidUsage;
  final bool shift;

  static _KeyboardStroke? fromAscii(int codeUnit) {
    if (codeUnit >= 0x61 && codeUnit <= 0x7A) {
      return _KeyboardStroke(0x04 + codeUnit - 0x61);
    }
    if (codeUnit >= 0x41 && codeUnit <= 0x5A) {
      return _KeyboardStroke(0x04 + codeUnit - 0x41, shift: true);
    }
    if (codeUnit >= 0x31 && codeUnit <= 0x39) {
      return _KeyboardStroke(0x1E + codeUnit - 0x31);
    }

    return switch (codeUnit) {
      0x30 => const _KeyboardStroke(0x27),
      0x0A => const _KeyboardStroke(0x28),
      0x0D => const _KeyboardStroke(0x28),
      0x08 => const _KeyboardStroke(0x2A),
      0x09 => const _KeyboardStroke(0x2B),
      0x20 => const _KeyboardStroke(0x2C),
      0x2D => const _KeyboardStroke(0x2D),
      0x3D => const _KeyboardStroke(0x2E),
      0x5B => const _KeyboardStroke(0x2F),
      0x5D => const _KeyboardStroke(0x30),
      0x5C => const _KeyboardStroke(0x31),
      0x3B => const _KeyboardStroke(0x33),
      0x27 => const _KeyboardStroke(0x34),
      0x60 => const _KeyboardStroke(0x35),
      0x2C => const _KeyboardStroke(0x36),
      0x2E => const _KeyboardStroke(0x37),
      0x2F => const _KeyboardStroke(0x38),
      0x21 => const _KeyboardStroke(0x1E, shift: true),
      0x40 => const _KeyboardStroke(0x1F, shift: true),
      0x23 => const _KeyboardStroke(0x20, shift: true),
      0x24 => const _KeyboardStroke(0x21, shift: true),
      0x25 => const _KeyboardStroke(0x22, shift: true),
      0x5E => const _KeyboardStroke(0x23, shift: true),
      0x26 => const _KeyboardStroke(0x24, shift: true),
      0x2A => const _KeyboardStroke(0x25, shift: true),
      0x28 => const _KeyboardStroke(0x26, shift: true),
      0x29 => const _KeyboardStroke(0x27, shift: true),
      0x5F => const _KeyboardStroke(0x2D, shift: true),
      0x2B => const _KeyboardStroke(0x2E, shift: true),
      0x7B => const _KeyboardStroke(0x2F, shift: true),
      0x7D => const _KeyboardStroke(0x30, shift: true),
      0x7C => const _KeyboardStroke(0x31, shift: true),
      0x3A => const _KeyboardStroke(0x33, shift: true),
      0x22 => const _KeyboardStroke(0x34, shift: true),
      0x7E => const _KeyboardStroke(0x35, shift: true),
      0x3C => const _KeyboardStroke(0x36, shift: true),
      0x3E => const _KeyboardStroke(0x37, shift: true),
      0x3F => const _KeyboardStroke(0x38, shift: true),
      _ => null,
    };
  }
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

      redirectDrives: redirectDrives,
      redirectClipboard: redirectClipboard,

      localSharePath: redirectDrives
          ? _expandLocalSharePath(effectiveLocalSharePath)
          : null,
      localShareName: effectiveLocalShareName,

      alternateShell: alternateShell.isEmpty ? null : alternateShell,

      sourceRdpContent: null,
    );
  }

  String _expandLocalSharePath(String path) {
    final trimmed = path.trim();
    if (!trimmed.startsWith('~')) return trimmed;

    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;

    if (trimmed == '~') return home;
    if (trimmed.startsWith('~/') || trimmed.startsWith(r'~\')) {
      return '$home${Platform.pathSeparator}${trimmed.substring(2)}';
    }

    return trimmed;
  }
}

String _productionLibraryPath() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isMacOS) return '$executableDir/libportix_rdp.dylib';
  if (Platform.isWindows) return '$executableDir\\portix_rdp.dll';
  if (Platform.isLinux) return '$executableDir/libportix_rdp.so';
  throw UnsupportedError('Unsupported platform');
}
