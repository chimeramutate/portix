import 'dart:async';

import 'package:flutter/material.dart';

import '../../connection_manager/rdp_backend.dart';
import '../../connection_manager/rdp_profile.dart';
import '../../connection_manager/rdp_session_models.dart';
import 'rdp_canvas.dart';

/// A full-page widget for an active RDP session.
class RdpSessionPage extends StatefulWidget {
  const RdpSessionPage({
    super.key,
    required this.profile,
    required this.backend,
  });

  final RdpProfile profile;
  final RdpBackend backend;

  @override
  State<RdpSessionPage> createState() => _RdpSessionPageState();
}

class _RdpSessionPageState extends State<RdpSessionPage> {
  RdpSessionInfo? _session;
  RdpConnectionStatus _status = RdpConnectionStatus.disconnected;
  String? _errorMessage;
  StreamSubscription<RdpConnectionStatusEvent>? _statusSub;

  @override
  void initState() {
    super.initState();
    _statusSub = widget.backend.connectionStatusStream.listen(_onStatusChange);
    _connect();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    if (_session != null) {
      widget.backend.disconnect(_session!.id);
    }
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _status = RdpConnectionStatus.connecting;
      _errorMessage = null;
    });

    try {
      final session = await widget.backend.connect(widget.profile);
      if (mounted) {
        setState(() {
          _session = session;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = RdpConnectionStatus.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onStatusChange(RdpConnectionStatusEvent event) {
    if (_session == null || event.sessionId != _session!.id) return;

    if (mounted) {
      setState(() {
        _status = event.status;
        if (event.status == RdpConnectionStatus.error) {
          _errorMessage = event.message ?? 'Connection error';
        }
      });
    }
  }

  void _disconnect() {
    if (_session != null) {
      widget.backend.disconnect(_session!.id);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Text(
          widget.profile.name.isNotEmpty
              ? widget.profile.name
              : '${widget.profile.host}:${widget.profile.port}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          _StatusIndicator(status: _status),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: _disconnect,
            tooltip: 'Disconnect',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_status == RdpConnectionStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Connection Failed',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_session == null || _status == RdpConnectionStatus.connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Connecting to RDP server...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Center(
      child: InteractiveViewer(
        maxScale: 3.0,
        minScale: 0.5,
        child: RdpCanvas(
          sessionId: _session!.id,
          width: _session!.width,
          height: _session!.height,
          backend: widget.backend,
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final RdpConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      RdpConnectionStatus.connected => (Colors.green, 'Connected'),
      RdpConnectionStatus.connecting => (Colors.orange, 'Connecting'),
      RdpConnectionStatus.disconnected => (Colors.grey, 'Disconnected'),
      RdpConnectionStatus.error => (Colors.red, 'Error'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}
