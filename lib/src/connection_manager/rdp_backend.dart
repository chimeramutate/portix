import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../rust/api.dart' as rust_api;
import '../rust/domain/rdp_profile.dart' as rust_rdp_profile;
import 'rdp_profile.dart';
import 'rdp_session_models.dart';

/// Backend interface for RDP connections via Rust bridge.
class RdpBackend {
  RdpBackend._({
    required Stream<RdpFrameEvent> frameStream,
    required Stream<RdpConnectionStatusEvent> statusStream,
    required Stream<RdpConnectionStatusEvent> errorStream,
  }) : _frameStream = frameStream,
       _statusStream = statusStream,
       _errorStream = errorStream;

  static Future<RdpBackend> create() async {
    return RdpBackend._(
      frameStream: rust_api
          .rdpFrameStream()
          .map(_frameEventFromJson)
          .asBroadcastStream(),
      statusStream: rust_api
          .rdpConnectionStatusStream()
          .map(_statusEventFromJson)
          .asBroadcastStream(),
      errorStream: rust_api
          .rdpErrorEventStream()
          .map(_errorEventFromJson)
          .asBroadcastStream(),
    );
  }

  final Stream<RdpFrameEvent> _frameStream;
  final Stream<RdpConnectionStatusEvent> _statusStream;
  final Stream<RdpConnectionStatusEvent> _errorStream;

  /// Stream of frame updates from active RDP sessions.
  Stream<RdpFrameEvent> get frameStream => _frameStream;

  /// Stream of connection status events.
  Stream<RdpConnectionStatusEvent> get connectionStatusStream => _statusStream;

  /// Stream of error events.
  Stream<RdpConnectionStatusEvent> get errorStream => _errorStream;

  /// Connect to an RDP server.
  Future<RdpSessionInfo> connect(RdpProfile profile) async {
    final rustProfile = rust_rdp_profile.RdpProfile(
      id: profile.id,
      name: profile.name,
      host: profile.host,
      port: profile.port,
      username: profile.username,
      password: profile.password,
      domain: profile.domain,
      width: profile.width,
      height: profile.height,
      screenMode: profile.screenMode,
      extra: profile.extra,
    );

    final info = await rust_api.rdpConnect(profile: rustProfile);
    return RdpSessionInfo(
      id: info.id,
      profileId: info.profileId,
      width: info.width,
      height: info.height,
      status: RdpConnectionStatus.connecting,
    );
  }

  /// Disconnect an active RDP session.
  Future<void> disconnect(String sessionId) {
    return rust_api.rdpDisconnect(sessionId: sessionId);
  }

  /// Send keyboard input.
  Future<void> sendKeyboardInput(
    String sessionId, {
    required int scancode,
    required bool isPressed,
  }) {
    return rust_api.rdpSendKeyboard(
      sessionId: sessionId,
      scancode: scancode,
      isPressed: isPressed,
    );
  }

  /// Send mouse button input.
  Future<void> sendMouseButton(
    String sessionId, {
    required int x,
    required int y,
    required RdpMouseButton button,
    required bool isPressed,
  }) {
    return rust_api.rdpSendMouseButton(
      sessionId: sessionId,
      x: x,
      y: y,
      button: button.value,
      isPressed: isPressed,
    );
  }

  /// Send mouse move event.
  Future<void> sendMouseMove(
    String sessionId, {
    required int x,
    required int y,
  }) {
    return rust_api.rdpSendMouseMove(sessionId: sessionId, x: x, y: y);
  }

  /// Request current frame buffer as raw RGBA bytes.
  Future<Uint8List> requestFrame(String sessionId) async {
    final data = await rust_api.rdpRequestFrame(sessionId: sessionId);
    return Uint8List.fromList(data);
  }

  /// Parse an .rdp file and return a profile.
  RdpProfile parseRdpFile({
    required String id,
    required String name,
    required String content,
  }) {
    return RdpProfile.fromRdpFile(id: id, name: name, content: content);
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

RdpFrameEvent _frameEventFromJson(String source) {
  final json = jsonDecode(source) as Map<String, Object?>;
  return RdpFrameEvent.fromJson(json);
}

RdpConnectionStatusEvent _statusEventFromJson(String source) {
  final json = jsonDecode(source) as Map<String, Object?>;
  return RdpConnectionStatusEvent.fromJson(json);
}

RdpConnectionStatusEvent _errorEventFromJson(String source) {
  final json = jsonDecode(source) as Map<String, Object?>;
  final sessionId = json['session_id'] as String? ?? '';
  final message = json['message'] as String? ?? 'Unknown error';
  return RdpConnectionStatusEvent(
    sessionId: sessionId,
    status: RdpConnectionStatus.error,
    message: message,
  );
}
