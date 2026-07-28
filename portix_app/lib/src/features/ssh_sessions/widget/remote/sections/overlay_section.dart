part of '../terminal_workspace_view.dart';

class TerminalConnectionOverlay extends StatefulWidget {
  const TerminalConnectionOverlay({
    required this.profile,
    required this.connecting,
    required this.onReconnect,
    this.onBack,
  });

  final domain.SshProfile? profile;
  final bool connecting;
  final VoidCallback? onReconnect;
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
          padding: const EdgeInsets.all(10),
          child: AppPanel(
            padding: const EdgeInsets.all(16),
            color: AppColors.surfaceDark.withValues(alpha: .96),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.connecting)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: slowConnection
                                ? AppColors.amber
                                : null,
                          ),
                        ),
                        if (elapsed.isNotEmpty)
                          Text(
                            elapsed,
                            style: TextStyle(
                              fontSize: 9,
                              color: slowConnection
                                  ? AppColors.amber
                                  : AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    )
                  else if (noNetwork)
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: AppColors.danger,
                      size: 30,
                    )
                  else
                    const Icon(
                      Icons.link_off_rounded,
                      color: AppColors.amber,
                      size: 30,
                    ),
                  const SizedBox(height: 10),
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
                        : noNetwork
                        ? 'Check your internet connection and try again.'
                        : label,
                    textAlign: TextAlign.center,
                    style: portixMuted(12),
                  ),
                  if (!widget.connecting) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onBack != null) ...[
                          SizedBox(
                            height: 34,
                            child: OutlinedButton.icon(
                              onPressed: widget.onBack,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 16,
                              ),
                              label: const Text('Back'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (widget.onReconnect != null)
                          SizedBox(
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
                              icon: Icon(
                                noNetwork
                                    ? Icons
                                          .signal_wifi_statusbar_connected_no_internet_4_rounded
                                    : Icons.refresh_rounded,
                                size: 16,
                              ),
                              label: Text(noNetwork ? 'Retry' : 'Connect'),
                            ),
                          ),
                      ],
                    ),
                    if (_checkingNetwork) ...[
                      const SizedBox(height: 10),
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
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
