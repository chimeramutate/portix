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
  bool _showOverlay = false;
  bool _disconnecting = false;

  @override
  void initState() {
    super.initState();
    _statusSub = widget.backend.connectionStatusStream.listen(_onStatusChange);
    _connect();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    unawaited(_disconnectSession());
    super.dispose();
  }

  Future<void> _connect() async {
    await _disconnectSession();
    if (!mounted) return;

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
    final navigator = Navigator.of(context);
    unawaited(
      _disconnectSession().whenComplete(() {
        if (mounted) navigator.pop();
      }),
    );
  }

  Future<void> _disconnectSession() async {
    if (_disconnecting) return;
    final session = _session;
    if (session == null) return;

    _disconnecting = true;
    _session = null;
    try {
      await widget.backend.disconnect(session.id);
    } catch (error) {
      debugPrint('RDP disconnect ignored: $error');
    } finally {
      _disconnecting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Stack(
        children: [
          // Remote desktop fills entire screen
          Positioned.fill(child: _buildBody()),
          // Floating overlay toolbar (toggle with mouse at top edge)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MouseRegion(
              onEnter: (_) => setState(() => _showOverlay = true),
              child: AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _showOverlay
                    ? _buildToolbar()
                    : const SizedBox(height: 4),
              ),
            ),
          ),
          // Invisible hit area at top to trigger overlay
          if (!_showOverlay)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 4,
              child: MouseRegion(
                onEnter: (_) => setState(() => _showOverlay = true),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return MouseRegion(
      onExit: (_) => setState(() => _showOverlay = false),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xDD2D2D2D),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back,
                size: 16,
                color: Colors.white70,
              ),
              onPressed: _disconnect,
              tooltip: 'Disconnect & Back',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
            const SizedBox(width: 8),
            Text(
              widget.profile.name.isNotEmpty
                  ? widget.profile.name
                  : widget.profile.host,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const Spacer(),
            _StatusIndicator(status: _status),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white70),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
          ],
        ),
      ),
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

    if (_session == null) {
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

    return RdpCanvas(
      sessionId: _session!.id,
      width: _session!.width,
      height: _session!.height,
      backend: widget.backend,
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
