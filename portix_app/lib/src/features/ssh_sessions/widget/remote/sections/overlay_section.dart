part of '../terminal_workspace_view.dart';

class TerminalConnectionOverlay extends StatefulWidget {
  const TerminalConnectionOverlay({
    required this.profile,
    required this.connecting,
    required this.onReconnect,
    this.failure,
    this.onBack,
  });

  final domain.SshProfile? profile;
  final bool connecting;
  final VoidCallback? onReconnect;

  /// Why the session went down, when the backend said.
  final String? failure;
  final VoidCallback? onBack;

  @override
  State<TerminalConnectionOverlay> createState() =>
      _TerminalConnectionOverlayState();
}

class _TerminalConnectionOverlayState extends State<TerminalConnectionOverlay> {
  bool _checkingNetwork = false;
  bool? _hasNetwork; // null = not checked yet
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    if (widget.connecting) {
      _startElapsedTimer();
    } else {
      _checkConnectivity();
    }
  }

  @override
  void didUpdateWidget(covariant TerminalConnectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connecting && !oldWidget.connecting) {
      // Became connecting — start timer.
      _elapsedSeconds = 0;
      _startElapsedTimer();
    } else if (!widget.connecting && oldWidget.connecting) {
      // Became disconnected — stop timer and check network.
      _stopElapsedTimer();
      _checkConnectivity();
    }
  }

  @override
  void dispose() {
    _stopElapsedTimer();
    super.dispose();
  }

  void _startElapsedTimer() {
    _stopElapsedTimer();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  Future<void> _checkConnectivity() async {
    if (_checkingNetwork) return;
    setState(() => _checkingNetwork = true);
    try {
      // Try to resolve a public DNS name; succeeds only when there is a
      // working internet connection.
      await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 4));
      if (mounted) setState(() => _hasNetwork = true);
    } on SocketException catch (_) {
      if (mounted) setState(() => _hasNetwork = false);
    } catch (_) {
      // Any other error (timeout, etc.) — assume no network.
      if (mounted) setState(() => _hasNetwork = false);
    } finally {
      if (mounted) setState(() => _checkingNetwork = false);
    }
  }

  String _elapsedLabel() {
    if (_elapsedSeconds < 5) return '';
    if (_elapsedSeconds < 60) return '${_elapsedSeconds}s';
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m}m ${s}s';
  }

  String _connectingSubtitle() {
    final label = widget.profile == null
        ? 'Establishing SSH session...'
        : '${widget.profile!.username}@${widget.profile!.name}';
    if (_elapsedSeconds >= 10) {
      return '$label\nThis is taking longer than usual. The remote host may be slow or unreachable.';
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.profile == null
        ? 'This terminal session is not connected.'
        : '${widget.profile!.username}@${widget.profile!.name} is not connected.';

    final noNetwork = _hasNetwork == false;
    final elapsed = _elapsedLabel();
    final slowConnection = widget.connecting && _elapsedSeconds >= 10;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.terminal.withValues(alpha: .86),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: AppPanel(
              padding: const EdgeInsets.all(20),
              color: AppColors.surface,
              radius: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.connecting)
                    SizedBox.square(
                      dimension: ConnectionStatusIcon.size,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.square(
                            dimension: 36,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: slowConnection ? AppColors.amber : null,
                            ),
                          ),
                          if (elapsed.isNotEmpty)
                            Text(
                              elapsed,
                              style: TextStyle(
                                fontSize: 11,
                                color: slowConnection
                                    ? AppColors.amber
                                    : AppColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    )
                  else if (noNetwork)
                    ConnectionStatusIcon(
                      icon: Icons.wifi_off_rounded,
                      color: AppColors.danger,
                      tint: AppColors.dangerTint,
                    )
                  else
                    ConnectionStatusIcon(
                      icon: Icons.link_off_rounded,
                      color: AppColors.amber,
                      tint: AppColors.amberTint,
                    ),
                  const SizedBox(height: 14),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.connecting
                          ? slowConnection
                                ? 'Connecting (slow)...'
                                : 'Connecting session'
                          : noNetwork
                          ? 'No network connection'
                          : 'No terminal connection',
                      style: portixTitle(15),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.connecting
                        ? _connectingSubtitle()
                        : widget.failure != null
                        ? widget.failure!
                        : noNetwork
                        ? 'Check your internet connection and try again.'
                        : label,
                    textAlign: TextAlign.center,
                    style: portixMuted(12).copyWith(height: 1.4),
                  ),
                  if (!widget.connecting) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (widget.onBack != null) ...[
                          Expanded(
                            child: AppButton(
                              icon: Icons.arrow_back_rounded,
                              label: 'Back',
                              onPressed: widget.onBack,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (widget.onReconnect != null)
                          Expanded(
                            child: SizedBox(
                              height: 34,
                              child: FilledButton.icon(
                                onPressed: _checkingNetwork
                                    ? null
                                    : () {
                                        // Re-check connectivity before reconnecting.
                                        _checkConnectivity();
                                        if (_hasNetwork != false) {
                                          widget.onReconnect?.call();
                                        }
                                      },
                                // The spinner lives in the button so the card
                                // keeps its height while the check runs.
                                icon: _checkingNetwork
                                    ? SizedBox.square(
                                        dimension: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.muted,
                                        ),
                                      )
                                    : Icon(
                                        noNetwork
                                            ? Icons
                                                  .signal_wifi_statusbar_connected_no_internet_4_rounded
                                            : Icons.refresh_rounded,
                                        size: 16,
                                      ),
                                label: Text(noNetwork ? 'Retry' : 'Connect'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Status glyph on a soft tile, shared by the terminal's connection cards.
class ConnectionStatusIcon extends StatelessWidget {
  const ConnectionStatusIcon({
    required this.icon,
    required this.color,
    required this.tint,
  });

  static const size = 44.0;

  final IconData icon;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
