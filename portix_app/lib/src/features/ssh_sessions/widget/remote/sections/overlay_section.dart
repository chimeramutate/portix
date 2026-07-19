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

  @override
  void initState() {
    super.initState();
    if (!widget.connecting) _checkConnectivity();
  }

  @override
  void didUpdateWidget(covariant TerminalConnectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.connecting && oldWidget.connecting) {
      // Became disconnected — check network.
      _checkConnectivity();
    }
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

  @override
  Widget build(BuildContext context) {
    final label = widget.profile == null
        ? 'This terminal session is not connected.'
        : '${widget.profile!.username}@${widget.profile!.name} is not connected.';

    final noNetwork = _hasNetwork == false;

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
                    const SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
                          ? 'Connecting session'
                          : noNetwork
                          ? 'No network connection'
                          : 'No terminal connection',
                      style: portixTitle(15),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.connecting
                        ? label
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
