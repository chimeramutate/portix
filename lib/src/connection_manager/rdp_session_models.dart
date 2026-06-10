import 'dart:typed_data';

/// Information about an active RDP session.
class RdpSessionInfo {
  const RdpSessionInfo({
    required this.id,
    required this.profileId,
    required this.width,
    required this.height,
    required this.status,
  });

  final String id;
  final String profileId;
  final int width;
  final int height;
  final RdpConnectionStatus status;

  factory RdpSessionInfo.fromJson(Map<String, Object?> json) {
    return RdpSessionInfo(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      status: RdpConnectionStatus.fromString(json['status'] as String? ?? ''),
    );
  }

  /// Create from the Rust bridge return type.
  factory RdpSessionInfo.fromRustInfo(dynamic info) {
    return RdpSessionInfo(
      id: info.id as String,
      profileId: info.profileId as String,
      width: info.width as int,
      height: info.height as int,
      status: RdpConnectionStatus.connecting,
    );
  }
}

enum RdpConnectionStatus {
  disconnected,
  connecting,
  connected,
  error;

  static RdpConnectionStatus fromString(String value) {
    return switch (value.toLowerCase()) {
      'disconnected' => RdpConnectionStatus.disconnected,
      'connecting' => RdpConnectionStatus.connecting,
      'connected' => RdpConnectionStatus.connected,
      'error' => RdpConnectionStatus.error,
      _ => RdpConnectionStatus.error,
    };
  }
}

/// Represents a frame update from the RDP session.
class RdpFrameEvent {
  const RdpFrameEvent({
    required this.sessionId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.data,
  });

  final String sessionId;
  final int x;
  final int y;
  final int width;
  final int height;

  /// RGBA pixel data for the updated region
  final Uint8List data;

  factory RdpFrameEvent.fromJson(Map<String, Object?> json) {
    final dataList = json['data'] as List<dynamic>;
    return RdpFrameEvent(
      sessionId: json['session_id'] as String,
      x: json['x'] as int,
      y: json['y'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
      data: Uint8List.fromList(dataList.cast<int>()),
    );
  }
}

/// RDP connection status change event
class RdpConnectionStatusEvent {
  const RdpConnectionStatusEvent({
    required this.sessionId,
    required this.status,
    this.message,
  });

  final String sessionId;
  final RdpConnectionStatus status;
  final String? message;

  factory RdpConnectionStatusEvent.fromJson(Map<String, Object?> json) {
    return RdpConnectionStatusEvent(
      sessionId: json['session_id'] as String,
      status: RdpConnectionStatus.fromString(json['status'] as String? ?? ''),
      message: json['message'] as String?,
    );
  }
}

/// Mouse button identifiers for RDP input
enum RdpMouseButton {
  left(0),
  right(1),
  middle(2);

  const RdpMouseButton(this.value);
  final int value;
}
