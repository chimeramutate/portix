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
    required Stream<RdpClipboardEvent> clipboardStream,
    required Stream<RdpConnectionStatusEvent> statusStream,
    required Stream<RdpConnectionStatusEvent> errorStream,
    Future<RdpSessionInfo> Function(RdpProfile profile)? connectHandler,
    Future<void> Function(String sessionId)? disconnectHandler,
    Future<void> Function(
      String sessionId, {
      required int scancode,
      required bool isPressed,
    })?
    keyboardHandler,
    Future<void> Function(
      String sessionId, {
      required int x,
      required int y,
      required RdpMouseButton button,
      required bool isPressed,
    })?
    mouseButtonHandler,
    Future<void> Function(String sessionId, {required int x, required int y})?
    mouseMoveHandler,
    Future<Uint8List> Function(String sessionId)? requestFrameHandler,
    Future<void> Function(String sessionId, String text)? clipboardHandler,
  }) : _frameStream = frameStream,
       _clipboardStream = clipboardStream,
       _statusStream = statusStream,
       _errorStream = errorStream,
       _connectHandler = connectHandler,
       _disconnectHandler = disconnectHandler,
       _keyboardHandler = keyboardHandler,
       _mouseButtonHandler = mouseButtonHandler,
       _mouseMoveHandler = mouseMoveHandler,
       _requestFrameHandler = requestFrameHandler,
       _clipboardHandler = clipboardHandler;

  static Future<RdpBackend> create() async {
    return RdpBackend._(
      frameStream: rust_api
          .rdpFrameStream()
          .map(_frameEventFromJson)
          .asBroadcastStream(),
      clipboardStream: rust_api
          .rdpClipboardStream()
          .map(_clipboardEventFromJson)
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

  /// Test-only constructor for driving RDP widgets without a live Rust bridge.
  factory RdpBackend.test({
    required Stream<RdpFrameEvent> frameStream,
    Stream<RdpClipboardEvent>? clipboardStream,
    Stream<RdpConnectionStatusEvent>? statusStream,
    Stream<RdpConnectionStatusEvent>? errorStream,
    Future<RdpSessionInfo> Function(RdpProfile profile)? connectHandler,
    Future<void> Function(String sessionId)? disconnectHandler,
    Future<void> Function(
      String sessionId, {
      required int scancode,
      required bool isPressed,
    })?
    keyboardHandler,
    Future<void> Function(
      String sessionId, {
      required int x,
      required int y,
      required RdpMouseButton button,
      required bool isPressed,
    })?
    mouseButtonHandler,
    Future<void> Function(String sessionId, {required int x, required int y})?
    mouseMoveHandler,
    Future<Uint8List> Function(String sessionId)? requestFrameHandler,
    Future<void> Function(String sessionId, String text)? clipboardHandler,
  }) {
    return RdpBackend._(
      frameStream: frameStream,
      clipboardStream: clipboardStream ?? const Stream.empty(),
      statusStream: statusStream ?? const Stream.empty(),
      errorStream: errorStream ?? const Stream.empty(),
      connectHandler: connectHandler,
      disconnectHandler: disconnectHandler,
      keyboardHandler: keyboardHandler,
      mouseButtonHandler: mouseButtonHandler,
      mouseMoveHandler: mouseMoveHandler,
      requestFrameHandler: requestFrameHandler,
      clipboardHandler: clipboardHandler,
    );
  }

  final Stream<RdpFrameEvent> _frameStream;
  final Stream<RdpClipboardEvent> _clipboardStream;
  final Stream<RdpConnectionStatusEvent> _statusStream;
  final Stream<RdpConnectionStatusEvent> _errorStream;
  final Future<RdpSessionInfo> Function(RdpProfile profile)? _connectHandler;
  final Future<void> Function(String sessionId)? _disconnectHandler;
  final Future<void> Function(
    String sessionId, {
    required int scancode,
    required bool isPressed,
  })?
  _keyboardHandler;
  final Future<void> Function(
    String sessionId, {
    required int x,
    required int y,
    required RdpMouseButton button,
    required bool isPressed,
  })?
  _mouseButtonHandler;
  final Future<void> Function(
    String sessionId, {
    required int x,
    required int y,
  })?
  _mouseMoveHandler;
  final Future<Uint8List> Function(String sessionId)? _requestFrameHandler;
  final Future<void> Function(String sessionId, String text)? _clipboardHandler;

  /// Stream of frame updates from active RDP sessions.
  Stream<RdpFrameEvent> get frameStream => _frameStream;

  Stream<RdpClipboardEvent> get clipboardStream => _clipboardStream;

  /// Stream of connection status events.
  Stream<RdpConnectionStatusEvent> get connectionStatusStream => _statusStream;

  /// Stream of error events.
  Stream<RdpConnectionStatusEvent> get errorStream => _errorStream;

  /// Connect to an RDP server.
  Future<RdpSessionInfo> connect(RdpProfile profile) async {
    final handler = _connectHandler;
    if (handler != null) return handler(profile);

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
    final handler = _disconnectHandler;
    if (handler != null) return handler(sessionId);

    return rust_api.rdpDisconnect(sessionId: sessionId);
  }

  /// Send keyboard input.
  Future<void> sendKeyboardInput(
    String sessionId, {
    required int scancode,
    required bool isPressed,
  }) {
    final handler = _keyboardHandler;
    if (handler != null) {
      return handler(sessionId, scancode: scancode, isPressed: isPressed);
    }

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
    final handler = _mouseButtonHandler;
    if (handler != null) {
      return handler(
        sessionId,
        x: x,
        y: y,
        button: button,
        isPressed: isPressed,
      );
    }

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
    final handler = _mouseMoveHandler;
    if (handler != null) {
      return handler(sessionId, x: x, y: y);
    }

    return rust_api.rdpSendMouseMove(sessionId: sessionId, x: x, y: y);
  }

  /// Request current frame buffer as raw RGBA bytes.
  Future<Uint8List> requestFrame(String sessionId) async {
    final handler = _requestFrameHandler;
    if (handler != null) return handler(sessionId);

    final data = await rust_api.rdpRequestFrame(sessionId: sessionId);
    return Uint8List.fromList(data);
  }

  Future<void> setClipboardText(String sessionId, String text) {
    final handler = _clipboardHandler;
    if (handler != null) return handler(sessionId, text);
    return rust_api.rdpSetClipboardText(sessionId: sessionId, text: text);
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

RdpClipboardEvent _clipboardEventFromJson(String source) {
  final json = jsonDecode(source) as Map<String, Object?>;
  return RdpClipboardEvent.fromJson(json);
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
