import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/connection_manager/ssh_profile.dart'
    as manager_profile;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;
import 'package:portix/src/domain/repositories/settings/index.dart';
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';
import 'package:xterm/xterm.dart';

import '../../controller/index.dart';
import 'terminal_settings.dart';
import 'terminal_shortcuts.dart';
import 'host_key_dialog.dart';
import 'key_passphrase_dialog.dart';
import 'port_forward_dialog.dart';
import 'session_snapshots_dialog.dart';
import 'terminal_profile_picker_dialog.dart';
import 'terminal_search_bar.dart';
import 'terminal_snippets.dart';
import 'terminal_status_footer.dart';
import 'terminal_theme_picker.dart';
import 'terminal_workspace_view.dart';

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({
    required this.profile,
    required this.profiles,
    super.key,
    this.connectRequestId = 0,
    this.keyboardEnabled = true,
    this.onSessionChanged,
    this.onActiveSessionChanged,
    this.onLastSessionClosed,
  });

  final domain.SshProfile? profile;
  final List<domain.SshProfile> profiles;
  final int connectRequestId;
  final bool keyboardEnabled;
  final ValueChanged<bool>? onSessionChanged;
  final ValueChanged<String?>? onActiveSessionChanged;
  final VoidCallback? onLastSessionClosed;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  late final Terminal _idleTerminal;
  late final TerminalController _idleController;
  late final FocusNode _idleFocusNode;
  late final TerminalSessionUiController _terminalUi;

  /// Tracks, per session, whether the terminal is currently "following"
  /// output (i.e. the viewport is at or near the bottom).  This is updated
  /// by a persistent scroll-listener so that the check remains accurate
  /// even across layout cycles where `maxScrollExtent` has not yet been
  /// refreshed after new text blocks are written.
  final Map<String, bool> _isFollowingOutput = {};

  /// Guards one-time registration of scroll listeners per session.
  final Set<String> _scrollListenersRegistered = {};
  late final ConnectionManager _connectionManager;
  late final TerminalTelemetryController _telemetry;
  late final SettingsRepository _settingsRepository;
  final TerminalSplitController _splitController =
      const TerminalSplitController();
  final TerminalSessionOrderController _sessionOrder =
      TerminalSessionOrderController();
  SplitNode? _splitRoot;
  final List<TerminalWorkspaceGroup> _workspaces = [];
  bool _workspaceActive = false;
  bool _workspaceReconnectInProgress = false;
  int _workspaceCounter = 0;
  String? _activeWorkspaceId;
  String? _soloSessionId;
  bool _broadcastTyping = false;
  StreamSubscription<session_models.TerminalOutputEvent>? _outputSubscription;
  StreamSubscription<session_models.ConnectionErrorEvent>? _errorSubscription;
  StreamSubscription<String>? _sessionLostSubscription;
  // Sessions with an auto-reconnect loop running.
  final Set<String> _autoReconnecting = {};
  // Serializes reconnects: after wake from sleep every tab drops at once, and
  // _reconnectSession shares _workspaceReconnectInProgress across calls.
  Future<void> _reconnectQueue = Future.value();
  String? _sessionId;
  String? _connectedProfileId;
  bool _connectInProgress = false;
  TerminalClipboardShortcut _copyShortcut = TerminalClipboardShortcut.shiftCtrl;
  TerminalClipboardShortcut _pasteShortcut = TerminalClipboardShortcut.ctrl;
  Color _terminalTextColor = AppColors.text;
  Color _terminalBackgroundColor = AppColors.terminal;
  String _terminalFontFamily = 'monospace';
  double _terminalFontSize = 13;
  String? _terminalThemeName;
  bool _passwordPromptActive = false;
  bool _activeTabClosed = false;
  int _cols = 80;
  int _rows = 24;
  final ScrollController _tabScrollController = ScrollController();
  final SessionSnapshotStore _snapshotStore = SessionSnapshotStore();
  bool _toolsExpanded = false;
  bool _showTabScrollStart = false;
  bool _showTabScrollEnd = false;

  @override
  void initState() {
    super.initState();
    _connectionManager = sl<ConnectionManager>();
    _settingsRepository = sl<SettingsRepository>();
    _telemetry = TerminalTelemetryController(
      connectionManager: _connectionManager,
      onOsDetected: _handleOsDetected,
    );
    _terminalUi = TerminalSessionUiController(
      onInput: _handleTerminalInput,
      onResize: _handleTerminalResize,
    );
    _idleController = _terminalUi.idleController;
    _idleFocusNode = _terminalUi.idleFocusNode;
    _idleTerminal = _terminalUi.idleTerminal;
    _listenToConnectionManager();
    _connectionManager.addListener(_handleConnectionManagerChanged);
    HardwareKeyboard.instance.addHandler(_handlePanelShortcut);
    _bootTerminal();
    _tabScrollController.addListener(_handleTabScrollChanged);
    unawaited(_loadTerminalSettings());
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void didUpdateWidget(covariant TerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.id != widget.profile?.id ||
        oldWidget.connectRequestId != widget.connectRequestId) {
      // Skip if same profile and already have a session or connection in progress.
      if (oldWidget.profile?.id == widget.profile?.id &&
          (_sessionId != null || _connectInProgress)) {
        return;
      }
      _activeTabClosed = false;
      _connect();
    }
  }

  @override
  void dispose() {
    _connectionManager.removeListener(_handleConnectionManagerChanged);
    HardwareKeyboard.instance.removeHandler(_handlePanelShortcut);
    _search?.dispose();
    _tabScrollController.dispose();

    // Jangan close session di sini.
    // Session harus hidup walaupun TerminalPanel tidak sedang tampil.
    // final sessionId = _sessionId;
    // if (sessionId != null) {
    //   unawaited(_connectionManager.closeSession(sessionId));
    // }

    unawaited(_outputSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_sessionLostSubscription?.cancel());
    _pendingDisposedSessionIds.clear();
    _terminalUi.dispose();
    _telemetry.dispose();

    super.dispose();
  }

  /// Reads clipboard + appearance settings in one file read. On failure the
  /// current values (initially the defaults) are kept.
  Future<void> _loadTerminalSettings() async {
    final Map<String, String> values;
    try {
      values = await _settingsRepository.loadSettings();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _copyShortcut = terminalClipboardShortcutFromValue(
        values[terminalCopyShortcutSettingKey],
      );
      _pasteShortcut = terminalClipboardShortcutFromValue(
        values[terminalPasteShortcutSettingKey],
      );
      _terminalThemeName = values[terminalThemeSettingKey];
      _terminalTextColor = terminalTextColorFromValue(
        values[terminalTextColorSettingKey],
      );
      _terminalBackgroundColor = terminalBackgroundColorFromValue(
        values[terminalBackgroundColorSettingKey],
      );
      _terminalFontFamily = terminalFontFamilyFromValue(
        values[terminalFontSettingKey],
      );
      _terminalFontSize = terminalFontSizeFromValue(
        values[terminalFontSizeSettingKey],
      ).toDouble();
    });
  }

  /// Tools tucked behind one button at the right end of the tab bar.
  Widget _buildTerminalTools() {
    final hasSession = _sessionId != null;
    Widget tool(
      String message,
      IconData icon,
      VoidCallback? onPressed, {
      Key? key,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Tooltip(
          message: message,
          child: AppIconButton(key: key, icon: icon, onPressed: onPressed),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          child: !_toolsExpanded
              ? const SizedBox.shrink()
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tool(
                      'Snippets (Ctrl+Shift+P)',
                      Icons.bolt_rounded,
                      _openSnippetPalette,
                    ),
                    tool(
                      'Port forwarding',
                      Icons.swap_horiz_rounded,
                      _openPortForwarding,
                    ),
                    tool(
                      'Terminal theme',
                      Icons.palette_outlined,
                      _openThemePicker,
                      key: const ValueKey('terminal-theme'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildRecordButton(),
                    ),
                    tool(
                      Platform.isMacOS
                          ? 'Find in terminal (Cmd+F)'
                          : 'Find in terminal (Ctrl+Shift+F)',
                      Icons.search_rounded,
                      hasSession ? _openSearch : null,
                      key: const ValueKey('terminal-search'),
                    ),
                    tool(
                      'Save session state',
                      Icons.bookmark_add_outlined,
                      hasSession ? _saveSnapshot : null,
                      key: const ValueKey('save-session-state'),
                    ),
                    tool(
                      'Saved sessions',
                      Icons.history_rounded,
                      _openSnapshots,
                      key: const ValueKey('saved-sessions'),
                    ),
                  ],
                ),
        ),
        Tooltip(
          message: _toolsExpanded ? 'Hide tools' : 'Terminal tools',
          child: AppIconButton(
            key: const ValueKey('terminal-tools'),
            icon: _toolsExpanded
                ? Icons.chevron_right_rounded
                : Icons.more_horiz_rounded,
            onPressed: () => setState(() => _toolsExpanded = !_toolsExpanded),
          ),
        ),
      ],
    );
  }

  Future<void> _renameTab(String sessionId) async {
    final session = _sessionById(sessionId);
    if (session == null) return;
    final name = await showNameDialog(
      context,
      title: 'Rename tab',
      initial: session.title,
      action: 'Rename',
    );
    if (name != null) _connectionManager.renameSession(sessionId, name);
  }

  Future<void> _saveSnapshot() async {
    final sessionId = _sessionId;
    final session = sessionId == null ? null : _sessionById(sessionId);
    if (session == null) return;
    final name = await showNameDialog(
      context,
      title: 'Save session state',
      initial: session.title,
      action: 'Save',
    );
    if (name == null || !mounted) return;
    final now = DateTime.now();
    final snapshot = SessionSnapshot(
      id: '${now.microsecondsSinceEpoch}',
      profileId: session.profileId,
      title: name,
      savedAt: now,
      output: terminalSnapshotText(_terminalForSession(session.id)),
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _snapshotStore.save(snapshot);
      messenger?.showSnackBar(SnackBar(content: Text('Saved "$name"')));
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to save session: $error')),
      );
    }
  }

  /// Picks a saved snapshot (per profile) and opens it in a new tab.
  Future<void> _openSnapshots() async {
    final sessionId = _sessionId;
    final snapshot = await showSessionSnapshotsDialog(
      context,
      store: _snapshotStore,
      profiles: widget.profiles,
      initialProfileId:
          (sessionId == null ? null : _sessionById(sessionId)?.profileId) ??
          widget.profile?.id,
    );
    if (snapshot == null || !mounted) return;
    final profile = widget.profiles
        .where((profile) => profile.id == snapshot.profileId)
        .firstOrNull;
    if (profile == null) return;
    _activeTabClosed = false;
    await _connectNewSession(profile, restore: snapshot);
  }

  void _openThemePicker() {
    unawaited(
      showTerminalThemePicker(
        context,
        current: _terminalThemeName,
        onSelected: (name) {
          setState(() => _terminalThemeName = name);
          unawaited(_saveTerminalTheme(name));
        },
      ),
    );
  }

  /// Persists [name] so new windows and the Settings page use it too.
  Future<void> _saveTerminalTheme(String name) async {
    try {
      final values = await _settingsRepository.loadSettings();
      await _settingsRepository.saveSettings({
        ...values,
        terminalThemeSettingKey: name,
      });
    } catch (_) {
      // Applied for this session anyway; the next pick retries the save.
    }
  }

  void _notifyActiveSessionChanged(String? sessionId) {
    widget.onActiveSessionChanged?.call(sessionId);
    _telemetry.track(sessionId);
    if (!mounted) return;

    if (sessionId == null) {
      context.read<SshSessionBloc>().add(const SshSessionCleared());
      return;
    }

    final session = _sessionById(sessionId);
    if (session == null) return;
    context.read<SshSessionBloc>().add(
      SshSessionActivated(
        sessionId: session.id,
        profileId: session.profileId,
        connected: session.status == session_models.ConnectionStatus.connected,
      ),
    );
  }

  Future<void> _connect() async {
    final profile = widget.profile;
    if (profile == null) {
      _activeTerminal.write(
        '\r\n\x1b[33mNo active SSH profile selected.\x1b[0m\r\n',
      );
      return;
    }
    // Don't auto-connect if all tabs were closed - user needs to explicitly request a new connection
    if (_activeTabClosed) {
      _activeTerminal.write(
        '\r\n\x1b[33mAll sessions closed. Click "Connect" to start a new session.\x1b[0m\r\n',
      );
      return;
    }
    if (_connectInProgress) return;
    if (_passwordPromptActive) return;
    if (_connectedProfileId == profile.id &&
        _sessionId != null &&
        _isSessionReusable(_sessionId!)) {
      return;
    }

    // Look for any existing session for this profile (even disconnected ones).
    final existingSession = _lastSessionForProfile(profile.id);
    if (existingSession != null) {
      if (_isSessionReusable(existingSession.id)) {
        _activateSession(existingSession);
        return;
      }
      // Session exists but is disconnected — reconnect it in place
      // to preserve workspace membership.
      await _reconnectSession(existingSession.id);
      return;
    }

    if (_sessionId != null && !_isSessionReusable(_sessionId!)) {
      _sessionId = null;
      _connectedProfileId = null;
    }
    await _connectNewSession(profile);
  }

  void _listenToConnectionManager() {
    _outputSubscription ??= _connectionManager.terminalOutputStream.listen(
      (event) {
        final sessionId = event.sessionId;
        // Capture whether the terminal was "following" output *before*
        // writing new text.  `terminal.write` triggers `markNeedsLayout`
        // (asynchronous), so the ScrollController still reflects the state
        // from the last committed frame.  Checking after `write` would test
        // a stale position that hasn't been updated for the new content,
        // causing the auto-scroll to be skipped at the upper/lower scroll
        // boundaries ("batas atas/bawah") when a full text block has just
        // been added.
        final wasFollowing =
            _isFollowingOutput[sessionId] ?? _isScrollAtBottom(sessionId);
        _ensureScrollListenerRegistered(sessionId);
        _terminalForSession(sessionId).write(event.data);
        // Auto-scroll to follow the text block (terminal output) when the
        // user is viewing the bottom.  This mirrors the xterm
        // `RenderTerminal._stickToBottom` behaviour but is invoked explicitly
        // so that scroll reliably follows every incoming block of text —
        // including command-output that arrives after the initial Enter
        // auto-scroll (which the built-in layout pass does not always catch).
        if (wasFollowing) {
          _scrollTerminalToBottom(sessionId);
        }
      },
      onError: (Object error) => _activeTerminal.write(
        '\r\n\x1b[31mterminal stream: $error\x1b[0m\r\n',
      ),
    );
    _errorSubscription ??= _connectionManager.errorEventStream.listen(
      _handleBackendError,
    );
    _sessionLostSubscription ??= _connectionManager.sessionLostStream.listen(
      (sessionId) => unawaited(_autoReconnect(sessionId)),
    );
  }

  static const List<int> _autoReconnectDelaysSeconds = [2, 4, 8, 16, 30, 30];

  /// Retries a dropped session with exponential backoff. Each attempt first
  /// waits for the host's SSH port to accept TCP again, then runs the normal
  /// [_reconnectSession] once. Aborts as soon as the user closes or
  /// reconnects the tab themselves.
  Future<void> _autoReconnect(String sessionId) async {
    if (!_autoReconnecting.add(sessionId)) return;
    try {
      final profileId = _sessionById(sessionId)?.profileId;
      final profile = widget.profiles
          .where((profile) => profile.id == profileId)
          .firstOrNull;
      if (profile == null) return;
      final total = _autoReconnectDelaysSeconds.length;
      for (var attempt = 0; attempt < total; attempt++) {
        final delay = _autoReconnectDelaysSeconds[attempt];
        _terminalForSession(sessionId).write(
          '\r\n\x1b[33m[portix] Reconnecting in ${delay}s '
          '(attempt ${attempt + 1}/$total)...\x1b[0m\r\n',
        );
        await Future<void>.delayed(Duration(seconds: delay));
        if (!mounted ||
            _sessionById(sessionId) == null ||
            _isSessionReusable(sessionId)) {
          return;
        }
        if (await _connectionManager.isSessionHostReachable(sessionId)) {
          final reconnect = _reconnectQueue.then(
            (_) => _reconnectSession(sessionId),
          );
          _reconnectQueue = reconnect.catchError((_) {});
          await reconnect;
          return;
        }
      }
      if (mounted && _sessionById(sessionId) != null) {
        _terminalForSession(sessionId).write(
          '\r\n\x1b[31m[portix] Host still unreachable. '
          'Use Reconnect to try again.\x1b[0m\r\n',
        );
      }
    } finally {
      _autoReconnecting.remove(sessionId);
    }
  }

  /// Registers a scroll-listener on the session's [ScrollController] that
  /// continuously tracks whether the viewport is at (or near) the bottom.
  /// This state is used by [_listenToConnectionManager] to decide whether
  /// new output blocks should trigger auto-scroll, replacing the fragile
  /// point-in-time `_isScrollAtBottom` check that could go stale between
  /// layout cycles at the scroll boundaries.
  void _ensureScrollListenerRegistered(String sessionId) {
    if (!_scrollListenersRegistered.add(sessionId)) return;
    _isFollowingOutput.putIfAbsent(sessionId, () => true);
    final scrollController = _scrollControllerForSession(sessionId);
    scrollController.addListener(() {
      if (!scrollController.hasClients) return;
      final position = scrollController.position;
      _isFollowingOutput[sessionId] =
          position.pixels >= position.maxScrollExtent - 10;
    });
  }

  // Sessions whose failure is being resolved (one failure can arrive as
  // both a backend error and a status event).
  final Set<String> _resolvingFailures = {};

  /// Connects fail asynchronously (Rust returns the session id first), so a
  /// refused host key or an encrypted key surfaces here as an error event.
  /// Resolve it with the user, then reconnect the same tab.
  Future<void> _resolveSessionFailure(String sessionId, String message) async {
    final session = _sessionById(sessionId);
    if (session == null ||
        session.status == session_models.ConnectionStatus.connected ||
        !_resolvingFailures.add(sessionId)) {
      return;
    }
    try {
      final profile = widget.profiles
          .where((p) => p.id == session.profileId)
          .firstOrNull;
      if (profile == null) return;
      final managerProfile = manager_profile.SshProfile.fromDomain(profile);

      final hostKey = await resolveRefusedHostKey(
        context,
        _connectionManager,
        managerProfile,
      );
      if (hostKey == true && mounted) return _reconnectSession(sessionId);
      if (hostKey != null || !mounted) return;

      final retry = await resolveKeyPassphrase(
        context,
        _connectionManager.credentials,
        managerProfile,
        message,
      );
      if (retry && mounted) await _reconnectSession(sessionId);
    } finally {
      _resolvingFailures.remove(sessionId);
    }
  }

  void _handleBackendError(session_models.ConnectionErrorEvent error) {
    final sessionId = error.sessionId;
    if (sessionId != null && _sessionById(sessionId) != null) {
      _terminalForSession(
        sessionId,
      ).write('\r\n\x1b[31m${error.message}\x1b[0m\r\n');
      unawaited(_resolveSessionFailure(sessionId, error.message));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error.message,
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.surfaceCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _handleConnectionManagerChanged() {
    if (!mounted) return;
    if (_workspaceReconnectInProgress) {
      _updateTabScrollAffordances();
      setState(() {});
      return;
    }
    final sessions = _sshSessions;
    _syncSplitTreeWithSessions(sessions);
    final activeSessionStillExists = sessions.any(
      (session) => session.id == _sessionId,
    );
    if (_sessionId != null && !activeSessionStillExists) {
      if (sessions.isEmpty) {
        // Don't mark as closed when a reconnection is in progress (e.g.,
        // after password prompt). The new session will arrive shortly.
        if (_connectInProgress) {
          _sessionId = null;
          _splitRoot = null;
          _updateTabScrollAffordances();
          setState(() {});
          return;
        }
        _sessionId = null;
        _connectedProfileId = null;
        _activeTabClosed = true;
        widget.onSessionChanged?.call(false);
        _notifyActiveSessionChanged(null);
      } else {
        _activateSession(sessions.last);
      }
    } else if (_sessionId != null) {
      final activeSession = _sessionById(_sessionId!);
      widget.onSessionChanged?.call(activeSession != null);
      _notifyActiveSessionChanged(_sessionId);
      if (_isSessionConnected(_sessionId!) && _telemetry.snapshot == null) {
        unawaited(_telemetry.refresh());
      } else if (!_isSessionConnected(_sessionId!)) {
        _telemetry.clear(
          error:
              _statusForSession(_sessionId!) ==
                  session_models.ConnectionStatus.connecting
              ? null
              : 'Session disconnected',
        );
      }
    }
    _updateTabScrollAffordances();
    setState(() {});
  }

  void _handleOsDetected(String sessionId, String osIconAsset) {
    final profileId = _sessionById(sessionId)?.profileId;
    if (profileId == null || !mounted) return;
    context.read<SshWorkspaceBloc>().add(
      ProfileOsDetected(profileId: profileId, osIconAsset: osIconAsset),
    );
  }

  void _bootTerminal() {
    _idleTerminal.write('\x1b[2J\x1b[H');
  }

  void _handleTabScrollChanged() {
    if (!mounted || !_tabScrollController.hasClients) return;
    final position = _tabScrollController.position;
    final showStart = position.pixels > 8;
    final showEnd = position.pixels < position.maxScrollExtent - 8;
    if (showStart == _showTabScrollStart && showEnd == _showTabScrollEnd) {
      return;
    }
    setState(() {
      _showTabScrollStart = showStart;
      _showTabScrollEnd = showEnd;
    });
  }

  void _updateTabScrollAffordances() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabScrollController.hasClients) return;
      _handleTabScrollChanged();
    });
  }

  Future<void> _scrollTabsBy(double delta) async {
    if (!_tabScrollController.hasClients) return;
    final position = _tabScrollController.position;
    final target = (_tabScrollController.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    await _tabScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Terminal get _activeTerminal {
    final sessionId = _sessionId;
    if (sessionId == null) return _idleTerminal;
    return _terminalForSession(sessionId);
  }

  Terminal _terminalForSession(String sessionId) {
    return _terminalUi.terminalForSession(sessionId);
  }

  TerminalController _controllerForSession(String sessionId) {
    return _terminalUi.controllerForSession(sessionId);
  }

  ScrollController _scrollControllerForSession(String sessionId) {
    return _terminalUi.scrollControllerForSession(sessionId);
  }

  FocusNode _focusNodeForSession(String sessionId) {
    return _terminalUi.focusNodeForSession(sessionId);
  }

  GlobalKey<TerminalViewState> _viewKeyForSession(String sessionId) {
    return _terminalUi.viewKeyForSession(sessionId);
  }

  final Set<String> _pendingDisposedSessionIds = <String>{};

  void _disposeSessionUi(String sessionId) {
    _isFollowingOutput.remove(sessionId);
    _scrollListenersRegistered.remove(sessionId);
    _terminalUi.disposeSession(sessionId);
  }

  void _scheduleSessionUiDisposal(String sessionId) {
    if (!_pendingDisposedSessionIds.add(sessionId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingDisposedSessionIds.remove(sessionId);
      if (!mounted) return;
      _disposeSessionUi(sessionId);
    });
  }

  void _scrollTerminalToBottom(String sessionId) {
    final scrollController = _scrollControllerForSession(sessionId);

    void performScroll() {
      if (!mounted) return;
      if (!scrollController.hasClients) return;
      final position = scrollController.position;
      // Only jump if we're not already at the bottom (avoids redundant
      // notifyListeners that could fight the RenderTerminal's own
      // `_stickToBottom` correctBy during the same frame).
      if (position.pixels < position.maxScrollExtent - 1.0) {
        scrollController.jumpTo(position.maxScrollExtent);
      }
    }

    // Attempt an immediate jump first — this catches the case where the
    // RenderTerminal has already laid out with the new content (maxScrollExtent
    // is already updated) in the current frame.
    performScroll();

    // Then schedule a post-frame jump — this catches the case where
    // `terminal.write` triggered `markNeedsLayout` and the new maxScrollExtent
    // is only available after the next frame's layout pass.  This is the
    // critical timing for "block text + scroll" at the upper/lower boundaries:
    // the scroll must wait for layout to complete before jumping to the
    // updated maxScrollExtent, otherwise `jumpTo` uses a stale value and the
    // terminal appears "stuck".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      performScroll();
    });
  }

  /// Returns `true` when the terminal for [sessionId] is scrolled to (or
  /// within 10px of) the bottom, meaning it is safe to auto-follow new output
  /// without stealing focus from a user who has scrolled up to read history.
  bool _isScrollAtBottom(String sessionId) {
    final scrollController = _scrollControllerForSession(sessionId);
    if (!scrollController.hasClients) return false;
    final position = scrollController.position;
    return position.pixels >= position.maxScrollExtent - 10;
  }

  void _handleTerminalInput(String data, String? sessionId) {
    if (data == '\x02') {
      _toggleBroadcastTyping();
      return;
    }
    final targetSessionId = sessionId ?? _sessionId;
    if (targetSessionId == null) return;
    if (!_isSessionConnected(targetSessionId)) return;

    // Auto-scroll to the bottom on every keystroke so the cursor / prompt and
    // the just-typed input stay visible while typing.  Previously this only
    // ran for Enter ('\r'), so ordinary characters did not bring the viewport
    // back to the bottom and the cursor drifted off-screen until Enter was
    // pressed.
    //
    // `_scrollTerminalToBottom` is a no-op when the viewport is already at the
    // bottom, so in the common (following) case this adds no extra scrolling.
    // It only moves the viewport back to the prompt when the user had scrolled
    // up to read history and starts typing again — which is the standard
    // terminal behaviour (the prompt lives at the bottom).
    _scrollTerminalToBottom(targetSessionId);

    if (_broadcastTyping && _visibleSessionIds.contains(targetSessionId)) {
      for (final visibleSessionId in _visibleSessionIds) {
        if (!_isSessionConnected(visibleSessionId)) continue;
        unawaited(_connectionManager.sendTerminalInput(visibleSessionId, data));
      }
      return;
    }
    unawaited(_connectionManager.sendTerminalInput(targetSessionId, data));
  }

  void _handleTerminalResize(int cols, int rows, String? sessionId) {
    _cols = cols;
    _rows = rows;
    final targetSessionId = sessionId ?? _sessionId;
    if (targetSessionId == null) return;
    unawaited(_connectionManager.resizeTerminal(targetSessionId, cols, rows));
  }

  void _toggleBroadcastTyping() {
    if (!mounted) return;
    if (_visibleSessionIds.length < 2) {
      if (_broadcastTyping) {
        setState(() => _broadcastTyping = false);
      }
      return;
    }
    setState(() => _broadcastTyping = !_broadcastTyping);
  }

  void _toggleSoloPane(String sessionId) {
    if (!mounted) return;
    setState(() {
      final enteringSolo = _soloSessionId != sessionId;
      _soloSessionId = enteringSolo ? sessionId : null;
      if (enteringSolo) {
        _broadcastTyping = false;
      }
      _sessionId = sessionId;
      _connectedProfileId = _sessionById(sessionId)?.profileId;
    });
    _notifyActiveSessionChanged(sessionId);
    _focusNodeForSession(sessionId).requestFocus();
  }

  List<session_models.TerminalSession> get _sshSessions =>
      _connectionManager.sessions;

  session_models.TerminalSession? _lastSessionForProfile(String profileId) {
    final sessions = _sshSessions;
    for (var index = sessions.length - 1; index >= 0; index -= 1) {
      final session = sessions[index];
      if (session.profileId == profileId) return session;
    }
    return null;
  }

  bool _isSessionConnected(String sessionId) =>
      _sessionById(sessionId)?.status ==
      session_models.ConnectionStatus.connected;

  bool _isSessionReusable(String sessionId) {
    final status = _sessionById(sessionId)?.status;
    return status == session_models.ConnectionStatus.connected ||
        status == session_models.ConnectionStatus.connecting;
  }

  session_models.ConnectionStatus _statusForSession(String sessionId) =>
      _sessionById(sessionId)?.status ??
      session_models.ConnectionStatus.disconnected;

  domain.SshProfile? _profileForSession(String sessionId) {
    final profileId = _sessionById(sessionId)?.profileId;
    if (profileId == null) return null;
    return widget.profiles
        .where((profile) => profile.id == profileId)
        .firstOrNull;
  }

  void _activateSession(
    session_models.TerminalSession session, {
    bool keepWorkspaceVisible = false,
  }) {
    _terminalForSession(session.id);
    setState(() {
      _sessionId = session.id;
      _connectedProfileId = session.profileId;
      _activeTabClosed = false;

      final workspace = keepWorkspaceVisible
          ? _workspaceContainingSession(session.id)
          : null;
      if (workspace != null) {
        _activeWorkspaceId = workspace.id;
        _splitRoot = workspace.root;
        _workspaceActive = true;
      } else {
        _splitRoot = SplitLeaf(session.id);
        _workspaceActive = false;
        _activeWorkspaceId = null;
      }
    });
    _updateTabScrollAffordances();
    widget.onSessionChanged?.call(true);
    _notifyActiveSessionChanged(session.id);
    unawaited(_connectionManager.resizeTerminal(session.id, _cols, _rows));
  }

  Future<void> _duplicateSession(String sessionId) async {
    final session = _sessionById(sessionId);
    if (session == null) return;
    final profile = widget.profiles
        .where((profile) => profile.id == session.profileId)
        .firstOrNull;
    if (profile == null) return;

    final existingSessionIds = _sshSessions.map((s) => s.id).toSet();
    final prevSessionId = _sessionId;

    final result = await _connectionManager.connect(
      manager_profile.SshProfile.fromDomain(profile),
    );
    final failure = result.fold<Object?>((f) => f, (_) => null);
    if (failure != null || !mounted) {
      if (mounted) unawaited(_showConnectionFailedDialog(profile, failure!));
      return;
    }

    final newSession = _connectionManager.sessions
        .where(
          (s) =>
              s.profileId == profile.id && !existingSessionIds.contains(s.id),
        )
        .lastOrNull;

    if (newSession == null || !mounted) return;

    _terminalForSession(newSession.id).write('\x1b[2J\x1b[H');
    setState(() {
      _placeSessionInOrder(newSession.id);
      _sessionId = newSession.id;
      _connectedProfileId = newSession.profileId;
      _activeTabClosed = false;
      // Keep the existing split layout — the duplicated session becomes the
      // new active standalone session, not inserted into the split tree.
      if (_splitRoot == null || prevSessionId == null) {
        _splitRoot = SplitLeaf(newSession.id);
      }
      _workspaceActive = false;
    });
    _updateTabScrollAffordances();
    widget.onSessionChanged?.call(true);
    _notifyActiveSessionChanged(newSession.id);
    await _connectionManager.resizeTerminal(newSession.id, _cols, _rows);

    // Scroll the tab bar to reveal the new tab.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tabScrollController.hasClients) {
        _tabScrollController.animateTo(
          _tabScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Ctrl/Cmd+Shift+P opens snippets; Cmd+F (macOS) or Ctrl+Shift+F finds
  /// in the terminal (plain Ctrl+F belongs to the shell). Registered on
  /// [HardwareKeyboard] because xterm's focused view would otherwise consume
  /// them and send control characters to the shell.
  bool _handlePanelShortcut(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!mounted || !widget.keyboardEnabled || event is! KeyDownEvent) {
      return false;
    }
    final key = event.logicalKey;
    final shift = keyboard.isShiftPressed;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (key == LogicalKeyboardKey.keyP && shift && command) {
      if (_snippetPaletteOpen) return false;
      unawaited(_openSnippetPalette());
      return true;
    }
    final find = Platform.isMacOS
        ? keyboard.isMetaPressed && !shift
        : keyboard.isControlPressed && shift;
    if (key == LogicalKeyboardKey.keyF && find && _sessionId != null) {
      _openSearch();
      return true;
    }
    return false;
  }

  TerminalSearchController? _search;

  void _openSearch() {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    if (_search?.terminal == _terminalForSession(sessionId)) {
      setState(() {}); // already open: the bar takes focus again
      return;
    }
    _search?.dispose();
    setState(() {
      _search = TerminalSearchController(
        terminal: _terminalForSession(sessionId),
        controller: _controllerForSession(sessionId),
        theme: terminalThemeForProfile(
          _profileForSession(sessionId),
          foreground: _terminalTextColor,
          background: _terminalBackgroundColor,
          themeName: _terminalThemeName,
        ),
        reveal: (line) => _revealLine(sessionId, line),
      );
    });
  }

  void _closeSearch() {
    _search?.dispose();
    setState(() => _search = null);
    final sessionId = _sessionId;
    if (sessionId != null) _focusNodeForSession(sessionId).requestFocus();
  }

  /// Scrolls [sessionId]'s terminal so buffer [line] sits mid-viewport.
  void _revealLine(String sessionId, int line) {
    final view = _viewKeyForSession(sessionId).currentState;
    final scroll = _scrollControllerForSession(sessionId);
    if (view == null || !scroll.hasClients) return;
    final position = scroll.position;
    final target =
        line * view.renderTerminal.lineHeight - position.viewportDimension / 2;
    scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  bool _snippetPaletteOpen = false;

  Widget _buildRecordButton() {
    final sessionId = _sessionId;
    final recording =
        sessionId != null &&
        _connectionManager.recordingPath(sessionId) != null;
    return Tooltip(
      message: recording ? 'Stop recording' : 'Record session to a log file',
      child: AppIconButton(
        key: const ValueKey('record-session'),
        icon: recording
            ? Icons.stop_circle_rounded
            : Icons.fiber_manual_record_rounded,
        color: recording ? AppColors.danger : AppColors.cyan,
        onPressed: sessionId == null ? null : _toggleRecording,
      ),
    );
  }

  /// Tunnels go through the active tab's server (or the selected profile).
  Future<void> _openPortForwarding() async {
    final profileId = _sessionId == null
        ? widget.profile?.id
        : _sessionById(_sessionId!)?.profileId;
    final profile = widget.profiles
        .where((profile) => profile.id == profileId)
        .firstOrNull;
    if (profile == null) return;
    await showPortForwardDialog(
      context,
      _connectionManager,
      manager_profile.SshProfile.fromDomain(profile),
    );
  }

  /// Starts or stops logging the active tab's output to
  /// `~/.portix/logs/<profile>-<timestamp>.log`.
  Future<void> _toggleRecording() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final current = _connectionManager.recordingPath(sessionId);
    if (current != null) {
      await _connectionManager.stopRecording(sessionId);
      messenger.showSnackBar(
        SnackBar(content: Text('Session log saved: $current')),
      );
      return;
    }
    final profileId = _sessionById(sessionId)?.profileId;
    final name =
        widget.profiles
            .where((profile) => profile.id == profileId)
            .firstOrNull
            ?.name ??
        'session';
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final stamp = DateTime.now()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(RegExp('[-:]'), '')
        .replaceFirst('T', '-');
    final safeName = name.replaceAll(RegExp(r'[^\w.-]+'), '_');
    final path = '$home/.portix/logs/$safeName-$stamp.log';
    try {
      _connectionManager.startRecording(sessionId, path);
      messenger.showSnackBar(SnackBar(content: Text('Recording to $path')));
    } on FileSystemException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Cannot record session: ${error.message}')),
      );
    }
  }

  Future<void> _openSnippetPalette() async {
    if (_snippetPaletteOpen) return;
    _snippetPaletteOpen = true;
    String? command;
    try {
      command = await showTerminalSnippetPalette(context, _settingsRepository);
      if (command != null && mounted) {
        command = await resolveSnippetVariables(context, command);
      }
    } finally {
      _snippetPaletteOpen = false;
    }
    final sessionId = _sessionId;
    if (command == null || sessionId == null) return;
    if (!_isSessionConnected(sessionId)) return;
    unawaited(_connectionManager.sendTerminalInput(sessionId, '$command\r'));
  }

  Future<void> _openNewSessionForCurrentProfile() async {
    final profile = await _pickSessionProfile();
    if (profile == null || !mounted) return;
    if (!widget.profiles.any((saved) => saved.id == profile.id)) {
      // A quick connect: save it so reconnect, SFTP and snapshots find it.
      context.read<SshWorkspaceBloc>().add(QuickProfileSaved(profile));
    }
    _activeTabClosed = false;
    _connectedProfileId = null;
    _sessionId = null;
    await _connectNewSession(profile);
  }

  Future<void> _reconnectSession(String sessionId) async {
    final oldSession = _sessionById(sessionId);
    if (oldSession == null) return;
    final profile = widget.profiles
        .where((profile) => profile.id == oldSession.profileId)
        .firstOrNull;
    if (profile == null) return;

    _workspaceReconnectInProgress = true;
    final orderIndex = _sessionOrder.indexOf(sessionId);
    final recordingPath = _connectionManager.recordingPath(sessionId);
    await _connectionManager.closeSession(sessionId);
    _sessionOrder.remove(sessionId);
    _syncSplitTreeWithSessions(_sshSessions);
    if (mounted) {
      _updateTabScrollAffordances();
      setState(() {});
    }
    _scheduleSessionUiDisposal(sessionId);

    final result = await _connectionManager.connect(
      manager_profile.SshProfile.fromDomain(profile),
    );
    final failure = result.fold<Object?>((failure) => failure, (_) => null);
    if (failure != null || !mounted) {
      _workspaceReconnectInProgress = false;
      if (mounted) {
        _syncSplitTreeWithSessions(_sshSessions);
        setState(() {});
        unawaited(_showConnectionFailedDialog(profile, failure!));
      }
      return;
    }

    final newSession = _connectionManager.sessions.lastWhere(
      (session) => session.profileId == profile.id,
    );
    _terminalForSession(newSession.id).write('\x1b[2J\x1b[H');
    _connectionManager.renameSession(newSession.id, oldSession.title);
    if (recordingPath != null) {
      // Keep logging into the same file across the reconnect.
      _connectionManager.startRecording(newSession.id, recordingPath);
    }
    _workspaceReconnectInProgress = false;
    setState(() {
      _sessionOrder.restoreAtOrPlaceLast(newSession.id, orderIndex);
      _replaceSessionIdEverywhere(sessionId, newSession.id);
      _sessionId = newSession.id;
      _connectedProfileId = newSession.profileId;
      _splitRoot ??= SplitLeaf(newSession.id);
    });
    _updateTabScrollAffordances();
    widget.onSessionChanged?.call(true);
    _notifyActiveSessionChanged(newSession.id);
    await _connectionManager.resizeTerminal(newSession.id, _cols, _rows);
  }

  Future<domain.SshProfile?> _pickSessionProfile() {
    final profiles =
        widget.profiles
            .where((profile) => profile.isConnectable)
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    // Shown even with no profiles: a quick connect needs none.
    return showDialog<domain.SshProfile>(
      context: context,
      builder: (context) => SessionProfilePickerDialog(
        profiles: profiles,
        activeProfileId: _connectedProfileId ?? widget.profile?.id,
      ),
    );
  }

  Future<void> _connectNewSession(
    domain.SshProfile profile, {
    SessionSnapshot? restore,
  }) async {
    final existingSessionIds = _sshSessions
        .map((session) => session.id)
        .toSet();
    _connectedProfileId = profile.id;
    _connectInProgress = true;
    _sessionId = null;
    _splitRoot = null;
    _idleTerminal.write('\x1b[2J\x1b[H');

    try {
      final result = await _connectionManager.connect(
        manager_profile.SshProfile.fromDomain(profile),
      );
      result.fold((failure) {
        throw failure;
      }, (_) {});
      final session = _newSessionForProfile(profile.id, existingSessionIds);
      if (session == null) {
        throw StateError('SSH session was not created for ${profile.name}.');
      }
      final terminal = _terminalForSession(session.id);
      terminal.write('\x1b[2J\x1b[H');
      if (restore != null) {
        terminal.write(restoredSnapshotText(restore));
        _connectionManager.renameSession(session.id, restore.title);
      }
      if (!mounted) return;
      setState(() {
        _sessionId = session.id;
        _connectedProfileId = session.profileId;
        _activeTabClosed = false;
        _splitRoot = SplitLeaf(session.id);
        _workspaceActive = false;
        _activeWorkspaceId = null;
        _placeSessionInOrder(session.id);
      });
      _updateTabScrollAffordances();
      widget.onSessionChanged?.call(true);
      _notifyActiveSessionChanged(session.id);
      await _connectionManager.resizeTerminal(session.id, _cols, _rows);
    } catch (error) {
      final failedSession = _newSessionForProfile(
        profile.id,
        existingSessionIds,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = failedSession?.id;
        _connectedProfileId = failedSession?.profileId;
        _splitRoot = failedSession == null ? null : SplitLeaf(failedSession.id);
        if (failedSession != null) _placeSessionInOrder(failedSession.id);
      });
      widget.onSessionChanged?.call(failedSession != null);
      _notifyActiveSessionChanged(failedSession?.id);
      if (mounted) {
        unawaited(_showConnectionFailedDialog(profile, error));
      }
    } finally {
      _connectInProgress = false;
    }
  }

  session_models.TerminalSession? _newSessionForProfile(
    String profileId,
    Set<String> existingSessionIds,
  ) {
    return _connectionManager.sessions
        .where(
          (item) =>
              item.profileId == profileId &&
              !existingSessionIds.contains(item.id),
        )
        .lastOrNull;
  }

  Future<void> _showConnectionFailedDialog(
    domain.SshProfile profile,
    Object error,
  ) async {
    // A refused host key gets its own dialog (trust a new host, or a blocking
    // warning for a changed key) instead of the generic failure.
    final passwordUnavailable = _extractPasswordUnavailable(error);
    if (passwordUnavailable != null) {
      return _showPasswordPromptDialog(profile);
    }
    final bridgeMismatch = _isBridgeContentHashMismatch(error);
    final message = bridgeMismatch
        ? 'Portix Rust bridge was regenerated while the app was still running. Stop the app completely, then run it again so Dart and Rust load the same bridge build.'
        : _connectionFailureSummary(error);
    final details = '$error';
    return showDialog<void>(
      context: context,
      builder: (context) {
        final media = MediaQuery.sizeOf(context);
        final dialogWidth = media.width < 560 ? media.width - 32 : 500.0;
        final maxContentHeight = media.height * .58;
        return AlertDialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.all(16),
          title: Text(
            bridgeMismatch
                ? 'Rust bridge needs restart'
                : 'SSH connection failed',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: SizedBox(
            width: dialogWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxContentHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${profile.username}@${profile.host}:${profile.port}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: portixTitle(13),
                    ),
                    const SizedBox(height: 10),
                    Text(message, style: portixMuted(12)),
                    if (details != message) ...[
                      const SizedBox(height: 12),
                      Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          iconColor: AppColors.muted,
                          collapsedIconColor: AppColors.muted,
                          title: Text(
                            'Technical details',
                            style: portixMuted(12),
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.terminal,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: SelectableText(
                                details,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_connectNewSession(profile));
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  PasswordUnavailableException? _extractPasswordUnavailable(Object error) {
    if (error is PasswordUnavailableException) return error;
    if (error is AppFailure) {
      final cause = error.cause;
      if (cause is PasswordUnavailableException) return cause;
    }
    return null;
  }

  Future<void> _showPasswordPromptDialog(domain.SshProfile profile) {
    _passwordPromptActive = true;
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.all(16),
          title: const Text('Enter SSH Password'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Password for ${profile.username}@${profile.host}:${profile.port} '
                    'is not available on this device. Please enter it manually.',
                    style: portixMuted(12),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter SSH password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: AppColors.bg,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Password is required';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (formKey.currentState!.validate()) {
                        Navigator.of(context).pop();
                        _passwordPromptActive = false;
                        _connectWithPassword(
                          profile,
                          passwordController.text.trim(),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The password will be saved to local secure storage.',
                    style: portixMuted(10),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _passwordPromptActive = false;
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop();
                  _passwordPromptActive = false;
                  _connectWithPassword(profile, passwordController.text.trim());
                }
              },
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text('Connect'),
            ),
          ],
        );
      },
    ).whenComplete(() => _passwordPromptActive = false);
  }

  Future<void> _connectWithPassword(
    domain.SshProfile profile,
    String password,
  ) async {
    // Save password to secure storage for next time.
    unawaited(
      _connectionManager.credentials.savePassword(profile.id, password),
    );

    final managerProfile = manager_profile.SshProfile.fromDomain(profile)
        .copyWith(
          password: password,
          hasPassword: true,
          clearPrivateKeyPath: true,
        );

    // Close the failed session and reconnect in its place (same tab).
    final failedSessionId = _sessionId;
    final orderIndex = failedSessionId != null
        ? _sessionOrder.indexOf(failedSessionId)
        : -1;

    // Mark reconnection as in-progress BEFORE closing the failed session so
    // that _handleConnectionManagerChanged doesn't set _activeTabClosed.
    _connectedProfileId = profile.id;
    _connectInProgress = true;

    if (failedSessionId != null && !_isSessionConnected(failedSessionId)) {
      await _connectionManager.closeSession(failedSessionId);
      _sessionOrder.remove(failedSessionId);
      _syncSplitTreeWithSessions(_sshSessions);
      if (mounted) {
        setState(() {});
      }
      _scheduleSessionUiDisposal(failedSessionId);
    }

    final existingSessionIds = _sshSessions
        .map((session) => session.id)
        .toSet();

    try {
      final result = await _connectionManager.connect(managerProfile);
      result.fold((failure) {
        throw failure;
      }, (_) {});
      final session = _newSessionForProfile(profile.id, existingSessionIds);
      if (session == null) {
        throw StateError('SSH session was not created for ${profile.name}.');
      }
      final terminal = _terminalForSession(session.id);
      terminal.write('\x1b[2J\x1b[H');
      if (!mounted) return;
      setState(() {
        _sessionId = session.id;
        _connectedProfileId = session.profileId;
        _activeTabClosed = false;
        _splitRoot = SplitLeaf(session.id);
        _workspaceActive = false;
        _activeWorkspaceId = null;
        // Restore at the same position so the tab doesn't jump.
        _sessionOrder.restoreAtOrPlaceLast(session.id, orderIndex);
      });
      widget.onSessionChanged?.call(true);
      _notifyActiveSessionChanged(session.id);
      await _connectionManager.resizeTerminal(session.id, _cols, _rows);
    } catch (error) {
      final failedSession = _newSessionForProfile(
        profile.id,
        existingSessionIds,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = failedSession?.id;
        _connectedProfileId = failedSession?.profileId;
        _splitRoot = failedSession == null ? null : SplitLeaf(failedSession.id);
        if (failedSession != null) _placeSessionInOrder(failedSession.id);
      });
      widget.onSessionChanged?.call(failedSession != null);
      _notifyActiveSessionChanged(failedSession?.id);
      if (mounted) {
        unawaited(_showConnectionFailedDialog(profile, error));
      }
    } finally {
      _connectInProgress = false;
    }
  }

  String _connectionFailureSummary(Object error) {
    final message = '$error';
    final lower = message.toLowerCase();
    if (lower.contains('failed to load dynamic library') &&
        lower.contains('portix_serv.framework')) {
      return 'Rust backend iOS belum dibundle ke app. Build iOS butuh portix_serv.framework/xcframework di dalam Runner.app/Frameworks sebelum SSH bisa dipakai.';
    }
    if (lower.contains('mobile ssh backend is disabled')) {
      return 'SSH mobile belum diaktifkan. Untuk sekarang gunakan build desktop agar Rust backend dan SSH session berjalan stabil.';
    }
    if (lower.contains('rust ssh backend is unavailable')) {
      return 'Rust SSH backend belum tersedia untuk platform ini. Pastikan native library Portix sudah dibuild dan dibundle bersama app.';
    }
    return message.length > 420 ? '${message.substring(0, 420)}...' : message;
  }

  bool _isBridgeContentHashMismatch(Object error) {
    final message = '$error'.toLowerCase();
    return message.contains('content hash') ||
        message.contains('out-of-sync code') ||
        message.contains('recompiled');
  }

  Future<void> _closeTab(String sessionId) async {
    final before = _sshSessions;
    final closedIndex = before.indexWhere((session) => session.id == sessionId);
    final wasActive = sessionId == _sessionId;

    await _connectionManager.closeSession(sessionId);
    // `closeSession` notifies listeners synchronously (the session status
    // drops and `onLastSessionClosed` fires from that listener), which can
    // dispose this widget before we resume. Skip the post-close UI update to
    // avoid `setState() called after dispose()` when disconnecting the last
    // session.
    if (!mounted) return;
    _sessionOrder.remove(sessionId);
    _splitRoot = _splitController.removeSession(_splitRoot, sessionId);
    _removeSessionFromWorkspaces(sessionId);
    _pruneWorkspaces();

    final remaining = before
        .where((session) => session.id != sessionId)
        .toList(growable: false);

    if (remaining.isEmpty) {
      setState(() {
        _sessionId = null;
        _connectedProfileId = null;
        _activeTabClosed = true;
        _splitRoot = null;
        _workspaces.clear();
        _workspaceActive = false;
        _activeWorkspaceId = null;
      });
      widget.onSessionChanged?.call(false);
      _notifyActiveSessionChanged(null);
      _idleTerminal.write('\x1b[2J\x1b[H');
      _scheduleSessionUiDisposal(sessionId);
      widget.onLastSessionClosed?.call();
      return;
    }

    if (!wasActive) {
      setState(() {});
      _scheduleSessionUiDisposal(sessionId);
      return;
    }

    final safeIndex = closedIndex < 0 ? 0 : closedIndex;
    final nextIndex = safeIndex >= remaining.length
        ? remaining.length - 1
        : safeIndex;
    _activateSession(remaining[nextIndex]);
    _scheduleSessionUiDisposal(sessionId);
  }

  void _splitPane(
    String targetSessionId,
    String draggedSessionId,
    SplitDirection direction,
  ) {
    final effectiveTargetSessionId = _splitTargetForDrag(
      draggedSessionId,
      fallbackTargetSessionId: targetSessionId,
    );
    if (effectiveTargetSessionId == draggedSessionId) return;
    final session = _sessionById(draggedSessionId);
    if (session == null) return;
    _terminalForSession(draggedSessionId);

    setState(() {
      final targetWorkspace = _workspaceContainingSession(
        effectiveTargetSessionId,
      );

      if (targetWorkspace != null) {
        _removeSessionFromWorkspaces(
          draggedSessionId,
          exceptWorkspaceId: targetWorkspace.id,
        );
        final cleanedRoot = targetWorkspace.root.contains(draggedSessionId)
            ? _splitController.removeSession(
                targetWorkspace.root,
                draggedSessionId,
              )
            : targetWorkspace.root;
        targetWorkspace.root = _splitController.insertSplit(
          cleanedRoot ?? SplitLeaf(effectiveTargetSessionId),
          effectiveTargetSessionId,
          draggedSessionId,
          direction,
        );
        _activeWorkspaceId = targetWorkspace.id;
        _splitRoot = targetWorkspace.root;
      } else {
        _removeSessionFromWorkspaces(draggedSessionId);
        final workspace = TerminalWorkspaceGroup(
          id: 'workspace-$_workspaceCounter',
          label: _workspaceCounter == 0
              ? 'Workspace'
              : 'Workspace-$_workspaceCounter',
          root: _splitController.insertSplit(
            SplitLeaf(effectiveTargetSessionId),
            effectiveTargetSessionId,
            draggedSessionId,
            direction,
          ),
        );
        _workspaceCounter += 1;
        _workspaces.add(workspace);
        _activeWorkspaceId = workspace.id;
        _splitRoot = workspace.root;
      }

      _pruneWorkspaces();
      _workspaceActive = true;
      _sessionId = draggedSessionId;
      _connectedProfileId = session.profileId;
    });
    widget.onSessionChanged?.call(true);
    _notifyActiveSessionChanged(draggedSessionId);
  }

  String _splitTargetForDrag(
    String draggedSessionId, {
    required String fallbackTargetSessionId,
  }) {
    return _splitController.resolveSplitTargetForDrag(
      draggedSessionId: draggedSessionId,
      fallbackTargetSessionId: fallbackTargetSessionId,
      orderedSessionIds: _orderedSessions(
        _sshSessions,
      ).map((session) => session.id),
      workspaceSessionIds: _workspaceSessionIds,
      existingSessionIds: _sshSessions.map((session) => session.id).toSet(),
    );
  }

  void _removeSplit(String sessionId) {
    if ((_splitRoot?.sessionIds.length ?? 0) <= 1) return;
    setState(() {
      final activeWorkspace = _activeWorkspace;
      _splitRoot = _splitController.removeSession(_splitRoot, sessionId);
      if (activeWorkspace != null) {
        activeWorkspace.root =
            _splitController.removeSession(activeWorkspace.root, sessionId) ??
            activeWorkspace.root;
      }
      _removeSessionFromWorkspaces(
        sessionId,
        exceptWorkspaceId: _activeWorkspaceId,
      );
      _pruneWorkspaces();
      final currentWorkspace = _activeWorkspace;
      if (currentWorkspace != null) {
        _splitRoot = currentWorkspace.root;
      }
      if (_soloSessionId == sessionId) {
        _soloSessionId = _splitRoot?.sessionIds.last;
      }
      if (_sessionId == sessionId) {
        _sessionId = _splitRoot?.sessionIds.last;
        _connectedProfileId = _sessionId == null
            ? null
            : _sessionById(_sessionId!)?.profileId;
      }
    });
    _notifyActiveSessionChanged(_sessionId);
  }

  void _activateWorkspace(String workspaceId) {
    final workspace = _workspaceById(workspaceId);
    if (workspace == null) return;
    final sessionId = workspace.root.sessionIds.contains(_sessionId)
        ? _sessionId
        : workspace.root.sessionIds.last;
    final session = sessionId == null ? null : _sessionById(sessionId);
    setState(() {
      _activeWorkspaceId = workspace.id;
      _splitRoot = workspace.root;
      _workspaceActive = true;
      _sessionId = sessionId;
      _connectedProfileId = session?.profileId;
    });
    widget.onSessionChanged?.call(sessionId != null);
    _notifyActiveSessionChanged(sessionId);
  }

  Future<void> _closeWorkspace(String workspaceId) async {
    final workspace = _workspaceById(workspaceId);
    final sessionIds = workspace?.root.sessionIds.toList() ?? const <String>[];
    if (workspace == null || sessionIds.isEmpty) return;

    for (final sessionId in sessionIds) {
      await _connectionManager.closeSession(sessionId);
      _sessionOrder.remove(sessionId);
      _scheduleSessionUiDisposal(sessionId);
    }
    // Each `closeSession` can synchronously notify listeners and dispose this
    // widget (via `onLastSessionClosed`) before we resume. Skip the post-close
    // UI update to avoid `setState() called after dispose()` when disconnecting.
    if (!mounted) return;
    final remaining = _sshSessions
        .where((session) => !sessionIds.contains(session.id))
        .toList(growable: false);

    setState(() {
      _workspaces.removeWhere((item) => item.id == workspaceId);
      if (_activeWorkspaceId == workspaceId) {
        _activeWorkspaceId = null;
        _workspaceActive = false;
        _splitRoot = null;
      }
      if (_soloSessionId != null && sessionIds.contains(_soloSessionId)) {
        _soloSessionId = null;
      }
      if (remaining.isEmpty) {
        _sessionId = null;
        _connectedProfileId = null;
        _activeTabClosed = true;
      } else {
        _sessionId = remaining.last.id;
        _connectedProfileId = remaining.last.profileId;
        _splitRoot = SplitLeaf(remaining.last.id);
      }
    });
    if (remaining.isEmpty) {
      widget.onSessionChanged?.call(false);
      _notifyActiveSessionChanged(null);
      widget.onLastSessionClosed?.call();
    } else {
      widget.onSessionChanged?.call(true);
      _notifyActiveSessionChanged(_sessionId);
    }
  }

  void _ungroupActiveWorkspace() {
    final workspace = _activeWorkspace;
    if (workspace == null) return;
    setState(() {
      _workspaces.removeWhere((item) => item.id == workspace.id);
      _workspaceActive = false;
      _activeWorkspaceId = null;
      final sessionId = _sessionId ?? workspace.root.sessionIds.last;
      _splitRoot = SplitLeaf(sessionId);
      _sessionId = sessionId;
      _connectedProfileId = _sessionById(sessionId)?.profileId;
    });
    _notifyActiveSessionChanged(_sessionId);
  }

  Future<void> _reconnectWorkspace([String? workspaceId]) async {
    final workspace = workspaceId == null
        ? _activeWorkspace
        : _workspaceById(workspaceId);
    if (workspace == null) return;
    _workspaceReconnectInProgress = true;
    final oldRoot = workspace.root;
    final oldIds = oldRoot.sessionIds.toList();
    final oldActiveId = _sessionId;
    try {
      final profilesByOldId = {
        for (final session in _sshSessions)
          if (oldIds.contains(session.id))
            session.id: widget.profiles
                .where((profile) => profile.id == session.profileId)
                .firstOrNull,
      };
      final replacements = <String, String>{};
      for (final oldId in oldIds) {
        final profile = profilesByOldId[oldId];
        if (profile == null) continue;
        await _connectionManager.closeSession(oldId);
        _scheduleSessionUiDisposal(oldId);
        final result = await _connectionManager.connect(
          manager_profile.SshProfile.fromDomain(profile),
        );
        final connected = result.fold<bool>((_) => false, (_) => true);
        if (!connected) continue;
        final newSession = _connectionManager.sessions.lastWhere(
          (session) => session.profileId == profile.id,
        );
        replacements[oldId] = newSession.id;
        final terminal = _terminalForSession(newSession.id);
        terminal.write('\x1b[2J\x1b[H');
        terminal.write(
          '\x1b[36mReconnected to ${profile.username}@${profile.host}:${profile.port}...\x1b[0m\r\n',
        );
      }
      if (!mounted) return;
      if (replacements.isNotEmpty) {
        setState(() {
          workspace.root = _splitController.replaceSessionIds(
            oldRoot,
            replacements,
          );
          _splitRoot = workspace.root;
          _workspaceActive = true;
          _activeWorkspaceId = workspace.id;
          _sessionId =
              replacements[oldActiveId] ?? workspace.root.sessionIds.last;
          _connectedProfileId = _sessionId == null
              ? null
              : _sessionById(_sessionId!)?.profileId;
        });
        widget.onSessionChanged?.call(_sessionId != null);
        _notifyActiveSessionChanged(_sessionId);
      }
    } finally {
      _workspaceReconnectInProgress = false;
      if (mounted) {
        _syncSplitTreeWithSessions(_sshSessions);
        setState(() {});
      }
    }
  }

  session_models.TerminalSession? _sessionById(String id) {
    return _sshSessions.where((session) => session.id == id).firstOrNull;
  }

  TerminalWorkspaceGroup? get _activeWorkspace =>
      _activeWorkspaceId == null ? null : _workspaceById(_activeWorkspaceId!);

  TerminalWorkspaceGroup? _workspaceById(String id) {
    return _workspaces.where((workspace) => workspace.id == id).firstOrNull;
  }

  session_models.ConnectionStatus _workspaceStatus(
    TerminalWorkspaceGroup workspace,
  ) {
    final statuses = [
      for (final sessionId in workspace.root.sessionIds)
        _statusForSession(sessionId),
    ];
    if (statuses.any(
      (status) =>
          status == session_models.ConnectionStatus.disconnected ||
          status == session_models.ConnectionStatus.error,
    )) {
      return session_models.ConnectionStatus.disconnected;
    }
    if (statuses.any(
      (status) => status == session_models.ConnectionStatus.connecting,
    )) {
      return session_models.ConnectionStatus.connecting;
    }
    return session_models.ConnectionStatus.connected;
  }

  TerminalWorkspaceGroup? _workspaceContainingSession(String sessionId) {
    return _workspaces
        .where((workspace) => workspace.root.contains(sessionId))
        .firstOrNull;
  }

  void _removeSessionFromWorkspaces(
    String sessionId, {
    String? exceptWorkspaceId,
  }) {
    for (final workspace in _workspaces) {
      if (workspace.id == exceptWorkspaceId) continue;
      workspace.root =
          _splitController.removeSession(workspace.root, sessionId) ??
          workspace.root;
    }
  }

  List<session_models.TerminalSession> _orderedSessions(
    List<session_models.TerminalSession> sessions,
  ) {
    return _sessionOrder.ordered(sessions, (session) => session.id);
  }

  void _placeSessionInOrder(
    String draggedSessionId, {
    String? targetSessionId,
    bool afterTarget = true,
  }) {
    _sessionOrder.place(
      draggedSessionId,
      targetSessionId: targetSessionId,
      afterTarget: afterTarget,
    );
  }

  void _handleTabDroppedOnTab({
    required String draggedSessionId,
    required String targetSessionId,
  }) {
    if (draggedSessionId == targetSessionId) return;
    _splitPane(targetSessionId, draggedSessionId, SplitDirection.right);
  }

  void _moveSessionTab(
    String draggedSessionId, {
    String? targetSessionId,
    bool afterTarget = true,
  }) {
    if (draggedSessionId == targetSessionId) return;
    final session = _sessionById(draggedSessionId);
    if (session == null) return;
    setState(() {
      final workspace = _workspaceContainingSession(draggedSessionId);
      if (workspace != null) {
        workspace.root =
            _splitController.removeSession(workspace.root, draggedSessionId) ??
            workspace.root;
        _pruneWorkspaces();
      }
      _placeSessionInOrder(
        draggedSessionId,
        targetSessionId: targetSessionId,
        afterTarget: afterTarget,
      );
      _workspaceActive = false;
      _activeWorkspaceId = null;
      _splitRoot = SplitLeaf(draggedSessionId);
      _sessionId = draggedSessionId;
      _connectedProfileId = session.profileId;
    });
    widget.onSessionChanged?.call(true);
    _notifyActiveSessionChanged(draggedSessionId);
    _focusNodeForSession(draggedSessionId).requestFocus();
  }

  void _resizeSplitBranch(SplitBranch target, SplitBranch replacement) {
    final activeWorkspace = _activeWorkspace;
    setState(() {
      if (activeWorkspace != null) {
        final newRoot = _splitController.replaceBranch(
          activeWorkspace.root,
          target,
          replacement,
        );
        activeWorkspace.root = newRoot;
        _splitRoot = newRoot;
      } else if (_splitRoot != null) {
        _splitRoot = _splitController.replaceBranch(
          _splitRoot!,
          target,
          replacement,
        );
      }
    });
  }

  Widget _buildSessionTab(session_models.TerminalSession session) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data != session.id && _sessionById(details.data) != null,
      onAcceptWithDetails: (details) => _handleTabDroppedOnTab(
        draggedSessionId: details.data,
        targetSessionId: session.id,
      ),
      builder: (context, candidates, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: candidates.isNotEmpty
                ? Border.all(color: AppColors.green, width: 1.2)
                : null,
          ),
          child: TerminalSessionTab(
            sessionId: session.id,
            label: session.title,
            status: session.status,
            active: !_workspaceActive && session.id == _sessionId,
            onTap: () => _activateSession(session),
            onClose: () => _closeTab(session.id),
            onReconnect: () => _reconnectSession(session.id),
            onDuplicate: () => _duplicateSession(session.id),
            onRename: () => _renameTab(session.id),
          ),
        );
      },
    );
  }

  Set<String> get _workspaceSessionIds => {
    for (final workspace in _workspaces) ...workspace.root.sessionIds,
  };

  List<String> get _visibleSessionIds {
    final sessions = _sshSessions.map((session) => session.id).toSet();
    final visible =
        _splitRoot?.sessionIds
            .where((sessionId) => sessions.contains(sessionId))
            .toList() ??
        const <String>[];
    if (visible.isNotEmpty) return visible;
    final sessionId = _sessionId;
    if (sessionId == null || !sessions.contains(sessionId)) return const [];
    return [sessionId];
  }

  void _syncSplitTreeWithSessions(
    List<session_models.TerminalSession> sessions,
  ) {
    final activeIds = sessions.map((session) => session.id).toSet();
    var root = _splitRoot;
    for (final sessionId in root?.sessionIds ?? const <String>[]) {
      if (!activeIds.contains(sessionId)) {
        root = _splitController.removeSession(root, sessionId);
      }
    }
    _splitRoot = root;
    if (_soloSessionId != null && !activeIds.contains(_soloSessionId)) {
      _soloSessionId = null;
    }

    for (final workspace in _workspaces) {
      var workspaceRoot = workspace.root;
      for (final sessionId in workspaceRoot.sessionIds) {
        if (!activeIds.contains(sessionId)) {
          workspaceRoot =
              _splitController.removeSession(workspaceRoot, sessionId) ??
              workspaceRoot;
        }
      }
      workspace.root = workspaceRoot;
    }
    _pruneWorkspaces();
  }

  void _pruneWorkspaces() {
    _workspaces.removeWhere(
      (workspace) => workspace.root.sessionIds.length < 2,
    );
    if (_activeWorkspaceId != null &&
        _workspaceById(_activeWorkspaceId!) == null) {
      _activeWorkspaceId = null;
      _workspaceActive = false;
    }
  }

  void _replaceSessionIdEverywhere(String oldId, String newId) {
    final replacements = {oldId: newId};
    final root = _splitRoot;
    if (root != null && root.contains(oldId)) {
      _splitRoot = _splitController.replaceSessionIds(root, replacements);
    }
    for (final workspace in _workspaces) {
      if (workspace.root.contains(oldId)) {
        workspace.root = _splitController.replaceSessionIds(
          workspace.root,
          replacements,
        );
      }
    }
  }

  /// Builds a combined ordered list of tab items (workspaces + single sessions)
  /// so that a workspace tab appears at the position of its earliest member
  /// session in [_sessionOrder], not always at the front.
  List<Object> _orderedTabItems(
    List<session_models.TerminalSession> sessions,
    List<session_models.TerminalSession> singleSessions,
  ) {
    final workspaceSessionIds = _workspaceSessionIds;
    // Map from the first session-order index of each workspace to the workspace.
    final result = <Object>[];
    final addedWorkspaceIds = <String>{};

    for (final session in sessions) {
      // If this session belongs to a workspace and that workspace hasn't been
      // added yet, insert the workspace tab at this position.
      if (workspaceSessionIds.contains(session.id)) {
        final workspace = _workspaceContainingSession(session.id);
        if (workspace != null && addedWorkspaceIds.add(workspace.id)) {
          result.add(workspace);
        }
        continue;
      }
      result.add(session);
    }

    // Append any workspaces whose sessions were all pruned from the order list.
    for (final workspace in _workspaces) {
      if (addedWorkspaceIds.add(workspace.id)) {
        result.add(workspace);
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _orderedSessions(_sshSessions);
    final workspaceSessionIds = _workspaceSessionIds;
    final singleSessions = sessions
        .where((session) => !workspaceSessionIds.contains(session.id))
        .toList(growable: false);
    final splitRoot =
        _splitRoot ??
        switch (_sessionId) {
          final id? => SplitLeaf(id),
          null => null,
        };
    final soloSessionId = _soloSessionId;
    final displayRoot =
        soloSessionId != null && _sessionById(soloSessionId) != null
        ? SplitLeaf(soloSessionId)
        : splitRoot;
    final showPaneControls = (splitRoot?.sessionIds.length ?? 0) > 1;
    return BlocListener<SshWorkspaceBloc, SshWorkspaceState>(
      listenWhen: (previous, current) =>
          previous.activeView != current.activeView &&
          current.activeView == WorkspaceView.remoteFolder,
      listener: (context, state) {
        unawaited(_loadTerminalSettings());
      },
      child: Focus(
        autofocus: false,
        canRequestFocus: false,
        descendantsAreFocusable: widget.keyboardEnabled,
        descendantsAreTraversable: widget.keyboardEnabled,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (!widget.keyboardEnabled) return KeyEventResult.ignored;
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final isModifierPressed =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          if (isModifierPressed &&
              event.logicalKey == LogicalKeyboardKey.keyB) {
            _toggleBroadcastTyping();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Container(
          color: AppColors.terminal,
          child: Column(
            children: [
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: DragTarget<String>(
                  onAcceptWithDetails: (details) =>
                      _moveSessionTab(details.data),
                  builder: (context, candidates, rejected) {
                    final showDropHint = candidates.isNotEmpty;
                    return Row(
                      children: [
                        if (_showTabScrollStart)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                tooltip: 'Scroll tabs left',
                                padding: EdgeInsets.zero,
                                onPressed: () => _scrollTabsBy(-220),
                                icon: const Icon(
                                  Icons.chevron_left_rounded,
                                  color: AppColors.muted,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Scrollbar(
                                interactive: false,
                                thumbVisibility: false,
                                notificationPredicate: (_) => true,
                                child: SingleChildScrollView(
                                  controller: _tabScrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 8),
                                        for (final item in _orderedTabItems(
                                          sessions,
                                          singleSessions,
                                        )) ...[
                                          if (item is TerminalWorkspaceGroup)
                                            TerminalSessionTab(
                                              sessionId: item.id,
                                              label: item.label,
                                              status: _workspaceStatus(item),
                                              active:
                                                  _workspaceActive &&
                                                  item.id == _activeWorkspaceId,
                                              leadingIcon:
                                                  Icons.view_quilt_rounded,
                                              draggable: false,
                                              onTap: () =>
                                                  _activateWorkspace(item.id),
                                              onClose: () =>
                                                  _closeWorkspace(item.id),
                                              onReconnect: () =>
                                                  _reconnectWorkspace(item.id),
                                              reconnectNearClose: true,
                                            )
                                          else if (item
                                              is session_models.TerminalSession)
                                            _buildSessionTab(item),
                                          const SizedBox(width: 8),
                                        ],
                                        AppIconButton(
                                          key: const ValueKey(
                                            'new-terminal-tab',
                                          ),
                                          icon: Icons.add_rounded,
                                          onPressed:
                                              _openNewSessionForCurrentProfile,
                                        ),
                                        if (showDropHint) ...[
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Drop here to move this session',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: AppColors.green,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_showTabScrollEnd)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                tooltip: 'Scroll tabs right',
                                padding: EdgeInsets.zero,
                                onPressed: () => _scrollTabsBy(220),
                                icon: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.muted,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        _buildTerminalTools(),
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                child: displayRoot == null
                    ? _connectInProgress
                          ? Container(
                              color: AppColors.terminal,
                              alignment: Alignment.center,
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.cyan,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Connecting...',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : NoTerminalConnection(
                              profile: widget.profile,
                              onConnect: widget.profile == null
                                  ? null
                                  : _connect,
                              onViewProfiles: () {
                                context.read<SshSessionBloc>().add(
                                  const SshSessionCleared(),
                                );
                                context.read<SshWorkspaceBloc>()
                                  ..add(const ProfileSelectionCleared())
                                  ..add(
                                    const NavigationChanged(
                                      WorkspaceView.gallery,
                                    ),
                                  );
                              },
                            )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: _buildWorkspaceView(
                              displayRoot,
                              soloSessionId,
                              showPaneControls,
                            ),
                          ),
                          if (_search case final search?
                              when _sessionId != null &&
                                  search.terminal ==
                                      _terminalForSession(_sessionId!))
                            Positioned(
                              top: 8,
                              right: 16,
                              child: TerminalSearchBar(
                                key: ObjectKey(search),
                                search: search,
                                onClose: _closeSearch,
                              ),
                            ),
                        ],
                      ),
              ),
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => ListenableBuilder(
                    listenable: _telemetry,
                    builder: (context, _) => TerminalStatusFooter(
                      snapshot: _telemetry.snapshot,
                      samples: _telemetry.samples,
                      error: _telemetry.error,
                      canUngroupWorkspace:
                          constraints.maxWidth >= 360 &&
                          _activeWorkspace != null,
                      onUngroupWorkspace: _activeWorkspace == null
                          ? null
                          : _ungroupActiveWorkspace,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceView(
    SplitNode displayRoot,
    String? soloSessionId,
    bool showPaneControls,
  ) {
    return TerminalWorkspaceView(
      root: displayRoot,
      activeSessionId: _sessionId,
      soloSessionId: soloSessionId,
      broadcastTyping: _broadcastTyping,
      showPaneControls: showPaneControls,
      terminalForSession: _terminalForSession,
      statusForSession: _statusForSession,
      profileForSession: _profileForSession,
      idleTerminal: _idleTerminal,
      controllerForSession: _controllerForSession,
      scrollControllerForSession: _scrollControllerForSession,
      focusNodeForSession: _focusNodeForSession,
      viewKeyForSession: _viewKeyForSession,
      idleController: _idleController,
      idleScrollController: _terminalUi.idleScrollController,
      idleFocusNode: _idleFocusNode,
      idleViewKey: _terminalUi.idleViewKey,
      keyboardEnabled: widget.keyboardEnabled,
      copyShortcut: _copyShortcut,
      pasteShortcut: _pasteShortcut,
      textColor: _terminalTextColor,
      backgroundColor: _terminalBackgroundColor,
      fontFamily: _terminalFontFamily,
      fontSize: _terminalFontSize,
      themeName: _terminalThemeName,
      onFocus: (sessionId) {
        final session = _sessionById(sessionId);
        if (session != null) {
          _activateSession(session, keepWorkspaceVisible: true);
        }
      },
      onClosePane: _removeSplit,
      onSplit: _splitPane,
      onResizeBranch: _resizeSplitBranch,
      onReconnect: _reconnectSession,
      onToggleBroadcast: _toggleBroadcastTyping,
      onToggleSolo: _toggleSoloPane,
    );
  }
}
