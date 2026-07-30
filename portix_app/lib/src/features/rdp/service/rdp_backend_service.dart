import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/rust_rdp/api.dart' as rdp_api;
import 'package:portix/src/rust_rdp/domain/profile.dart' as rdp_profile;
import 'package:portix/src/rust_rdp/frb_generated.dart';

/// Service untuk berinteraksi dengan RDP backend (portix_rdp via Rust bridge).
///
/// Handles:
/// - Parsing .rdp files menggunakan Rust backend
/// - Connecting ke RDP server via IronRDP
/// - Streaming bitmap frames dan input forwarding
///
/// Requires [RdpBackendService.init] to be called once at app startup
/// (or [RdpBackendService.initDev] in dev mode) before using any method.
class RdpBackendService {
  const RdpBackendService();

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Initialise the RDP Rust library in development mode (loads from default path).
  static Future<void> initDev() async {
    await RdpRustLib.init();
  }

  /// Initialise the RDP Rust library in production mode (loads libportix_rdp.so
  /// from the same directory as the application executable).
  static Future<void> initProduction() async {
    await RdpRustLib.init(
      externalLibrary: ExternalLibrary.open(
        _productionLibraryPath(),
        debugInfo: 'Portix RDP library',
      ),
    );
  }

  // ── Parsing ──────────────────────────────────────────────────────────────

  /// Parse file .rdp dan return [RdpProfile].
  /// File dibaca lalu content-nya dikirim ke Rust backend untuk parsing.
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

  /// Parse konten string .rdp langsung (tanpa membaca file).
  Future<Either<Failure, RdpProfile>> parseRdpContent(
    String content, {
    String? profileName,
  }) async {
    try {
      final sessionInfo = await rdp_api.rdpParseFile(
        rdpContent: content,
        profileName: profileName,
      );
      // rdpParseFile returns RdpSessionInfo; the full profile is embedded
      // in the session. We return a minimal RdpProfile derived from it.
      // The caller can call connect() later with this profile.
      //
      // Note: For now we use the Dart-side parser to get the full profile
      // data (host, port, etc.) because rdpParseFile only returns session
      // metadata. The Rust parse is used for validation.
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

  // ── Connection ───────────────────────────────────────────────────────────

  /// Connect ke RDP server menggunakan profile.
  Future<Either<Failure, RdpConnectionResult>> connect(
    RdpProfile profile,
  ) async {
    try {
      final rustProfile = profile.toRustProfile();
      final sessionInfo = await rdp_api.rdpConnect(profile: rustProfile);
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

  /// Disconnect dari RDP session.
  Future<Either<Failure, void>> disconnect(String sessionId) async {
    try {
      await rdp_api.rdpDisconnect(sessionId: sessionId);
      return const Right(null);
    } catch (e) {
      return Left(Failure('Gagal disconnect: $e'));
    }
  }

  // ── Input Forwarding ─────────────────────────────────────────────────────

  /// Send mouse move event ke RDP session.
  Future<void> sendMouseMove(String sessionId, int x, int y) async {
    await rdp_api.rdpSendMouseMove(sessionId: sessionId, x: x, y: y);
  }

  /// Send mouse button event ke RDP session.
  /// button: 1=left, 2=right, 3=middle
  Future<void> sendMouseButton(
    String sessionId,
    int x,
    int y,
    int button,
    bool down,
  ) async {
    await rdp_api.rdpSendMouseButton(
      sessionId: sessionId,
      x: x,
      y: y,
      button: button,
      down: down,
    );
  }

  /// Send keyboard scancode input ke RDP session.
  Future<void> sendKeyboardInput(
    String sessionId,
    int scancode,
    bool down,
  ) async {
    await rdp_api.rdpSendKeyboardInput(
      sessionId: sessionId,
      scancode: scancode,
      down: down,
    );
  }

  // ── Event Streams ────────────────────────────────────────────────────────

  /// Stream bitmap frame updates (RGBA pixel data) dari semua RDP session.
  /// Setiap event adalah JSON-serialised [RdpFrameEvent].
  Stream<RdpFrameEvent> frameStream() {
    return rdp_api.rdpFrameStream().map(
      (json) =>
          RdpFrameEvent.fromJson(jsonDecode(json) as Map<String, Object?>),
    );
  }

  /// Stream status updates dari semua RDP session.
  Stream<RdpStatusEvent> statusStream() {
    return rdp_api.rdpStatusStream().map(
      (json) =>
          RdpStatusEvent.fromJson(jsonDecode(json) as Map<String, Object?>),
    );
  }

  /// Stream error events dari semua RDP session.
  Stream<RdpErrorEvent> errorStream() {
    return rdp_api.rdpErrorStream().map(
      (json) =>
          RdpErrorEvent.fromJson(jsonDecode(json) as Map<String, Object?>),
    );
  }
}

// ── Result types ─────────────────────────────────────────────────────────────

/// Result dari koneksi RDP yang sukses.
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

/// Bitmap frame event dari RDP session.
class RdpFrameEvent {
  const RdpFrameEvent({
    required this.sessionId,
    required this.data,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
  });

  factory RdpFrameEvent.fromJson(Map<String, Object?> json) => RdpFrameEvent(
    sessionId: json['session_id']! as String,
    data: (json['data']! as List<dynamic>).cast<int>(),
    width: json['width']! as int,
    height: json['height']! as int,
    x: json['x']! as int,
    y: json['y']! as int,
  );

  final String sessionId;
  final List<int> data;
  final int width;
  final int height;
  final int x;
  final int y;
}

/// Status event dari RDP session.
class RdpStatusEvent {
  const RdpStatusEvent({
    required this.sessionId,
    required this.status,
    this.message,
  });

  factory RdpStatusEvent.fromJson(Map<String, Object?> json) => RdpStatusEvent(
    sessionId: json['session_id']! as String,
    status: _statusFromString(json['status']! as String),
    message: json['message'] as String?,
  );

  final String sessionId;
  final RdpConnectionState status;
  final String? message;

  static RdpConnectionState _statusFromString(String s) => switch (s) {
    'Connecting' || 'connecting' => RdpConnectionState.connecting,
    'Connected' || 'connected' => RdpConnectionState.connected,
    'Error' || 'error' => RdpConnectionState.error,
    _ => RdpConnectionState.disconnected,
  };
}

/// Error event dari RDP session.
class RdpErrorEvent {
  const RdpErrorEvent({required this.message, this.sessionId});

  factory RdpErrorEvent.fromJson(Map<String, Object?> json) => RdpErrorEvent(
    message: json['message'] as String? ?? 'Unknown RDP error',
    sessionId: json['session_id'] as String?,
  );

  final String message;
  final String? sessionId;
}

/// Status koneksi RDP (Dart-side representation).
enum RdpConnectionState { disconnected, connecting, connected, error }

// ── Private helpers ───────────────────────────────────────────────────────────

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
    // Empty string → null for Rust Option<String>
    alternateShell: alternateShell.isEmpty ? null : alternateShell,
    // Dart RdpProfile doesn't carry raw .rdp file content
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
