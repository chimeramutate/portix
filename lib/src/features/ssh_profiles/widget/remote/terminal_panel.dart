import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:xterm/xterm.dart';

import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/connection_manager/ssh_profile.dart'
    as manager_profile;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;
import '../../bloc/index.dart';
import '../../controller/index.dart';
import 'terminal_status_footer.dart';
import 'terminal_workspace_view.dart';

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({
    required this.profile,
    required this.profiles,
    super.key,
    this.onSessionChanged,
    this.onActiveSessionChanged,
    this.onLastSessionClosed,
  });

  final domain.SshProfile? profile;
  final List<domain.SshProfile> profiles;
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
  late final ConnectionManager _connectionManager;
  final TerminalSplitController _splitController =
      const TerminalSplitController();
  final TerminalSessionOrderController _sessionOrder =
      TerminalSessionOrderController();
  SplitNode? _splitRoot;
  final List<TerminalWorkspaceGroup> _workspaces = [];
  bool _workspaceActive = false;
  int _workspaceCounter = 0;
  String? _activeWorkspaceId;
  String? _soloSessionId;
  bool _broadcastTyping = false;
  StreamSubscription<session_models.TerminalOutputEvent>? _outputSubscription;
  StreamSubscription<String>? _errorSubscription;
  Timer? _telemetryTimer;
  String? _sessionId;
  String? _telemetrySessionId;
  String? _connectedProfileId;
  session_models.RemoteSystemSnapshot? _remoteSnapshot;
  String? _telemetryError;
  final List<RemoteMetricSample> _metricSamples = [];
  bool _telemetryLoading = false;
  bool _activeTabClosed = false;
  int _cols = 80;
  int _rows = 24;

  @override
  void initState() {
    super.initState();
    _connectionManager = sl<ConnectionManager>();
    _terminalUi = TerminalSessionUiController(
      onInput: _handleTerminalInput,
      onResize: _handleTerminalResize,
    );
    _idleController = _terminalUi.idleController;
    _idleFocusNode = _terminalUi.idleFocusNode;
    _idleTerminal = _terminalUi.idleTerminal;
    _listenToConnectionManager();
    _connectionManager.addListener(_handleConnectionManagerChanged);
    _bootTerminal();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void didUpdateWidget(covariant TerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.id != widget.profile?.id) {
      _activeTabClosed = false;
      _connect();
    }
  }

  @override
  void dispose() {
    _connectionManager.removeListener(_handleConnectionManagerChanged);

    // Jangan close session di sini.
    // Session harus hidup walaupun TerminalPanel tidak sedang tampil.
    // final sessionId = _sessionId;
    // if (sessionId != null) {
    //   unawaited(_connectionManager.closeSession(sessionId));
    // }

    unawaited(_outputSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    _telemetryTimer?.cancel();
    _terminalUi.dispose();

    super.dispose();
  }

  void _notifyActiveSessionChanged(String? sessionId) {
    widget.onActiveSessionChanged?.call(sessionId);
    _syncTelemetrySession(sessionId);
    if (!mounted) return;

    if (sessionId == null) {
      context.read<SshWorkspaceBloc>().add(
        const ActiveTerminalSessionCleared(),
      );
      return;
    }

    final session = _sessionById(sessionId);
    if (session == null) return;
    context.read<SshWorkspaceBloc>().add(
      ActiveTerminalSessionChanged(
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
    if (_activeTabClosed) return;
    if (_connectedProfileId == profile.id && _sessionId != null) return;

    final existingSession = _lastSessionForProfile(profile.id);
    if (existingSession != null) {
      _activateSession(existingSession);
      return;
    }

    await _connectNewSession(profile);
  }

  void _listenToConnectionManager() {
    _outputSubscription ??= _connectionManager.terminalOutputStream.listen(
      (event) {
        _terminalForSession(event.sessionId).write(event.data);
      },
      onError: (Object error) => _activeTerminal.write(
        '\r\n\x1b[31mterminal stream: $error\x1b[0m\r\n',
      ),
    );
    _errorSubscription ??= _connectionManager.errorEventStream.listen((error) {
      _activeTerminal.write('\r\n\x1b[31m$error\x1b[0m\r\n');
    });
  }

  void _handleConnectionManagerChanged() {
    if (!mounted) return;
    final sessions = _sshSessions;
    _syncSplitTreeWithSessions(sessions);
    final activeSessionStillExists = sessions.any(
      (session) => session.id == _sessionId,
    );
    if (_sessionId != null && !activeSessionStillExists) {
      if (sessions.isEmpty) {
        _sessionId = null;
        _connectedProfileId = null;
        _activeTabClosed = true;
        widget.onSessionChanged?.call(false);
        _notifyActiveSessionChanged(null);
      } else {
        _activateSession(sessions.last);
      }
    } else if (_sessionId != null) {
      widget.onSessionChanged?.call(_sessionById(_sessionId!) != null);
      _notifyActiveSessionChanged(_sessionId);
      if (_isSessionConnected(_sessionId!) && _remoteSnapshot == null) {
        unawaited(_loadRemoteTelemetry(_sessionId!));
      }
    }
    setState(() {});
  }

  void _syncTelemetrySession(String? sessionId) {
    if (_telemetrySessionId == sessionId) return;
    _telemetryTimer?.cancel();
    _telemetrySessionId = sessionId;
    _remoteSnapshot = null;
    _telemetryError = null;
    _metricSamples.clear();
    _telemetryLoading = false;
    if (sessionId == null) return;
    unawaited(_loadRemoteTelemetry(sessionId));
    _telemetryTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_loadRemoteTelemetry(sessionId)),
    );
  }

  Future<void> _loadRemoteTelemetry(String sessionId) async {
    if (!_isSessionConnected(sessionId)) return;
    if (_telemetryLoading) return;
    _telemetryLoading = true;
    final result = await _connectionManager.remoteSystemSnapshot(sessionId);
    _telemetryLoading = false;
    if (!mounted || _telemetrySessionId != sessionId) return;
    result.fold(
      (failure) {
        setState(() => _telemetryError = failure.message);
      },
      (snapshot) {
        final memoryPercent = _capacityPercent(
          snapshot.memoryUsedBytes,
          snapshot.memoryTotalBytes,
        );
        final diskPercent = _capacityPercent(
          snapshot.diskUsedBytes,
          snapshot.diskTotalBytes,
        );
        setState(() {
          _remoteSnapshot = snapshot;
          _telemetryError = null;
          _metricSamples.add(
            RemoteMetricSample(
              createdAt: DateTime.now(),
              memoryPercent: memoryPercent,
              diskPercent: diskPercent,
            ),
          );
          if (_metricSamples.length > 36) {
            _metricSamples.removeRange(0, _metricSamples.length - 36);
          }
        });
      },
    );
  }

  double _capacityPercent(int used, int total) {
    if (total <= 0) return 0;
    return (used / total * 100).clamp(0, 100);
  }

  void _bootTerminal() {
    _idleTerminal.write('\x1b[2J\x1b[H');
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

  FocusNode _focusNodeForSession(String sessionId) {
    return _terminalUi.focusNodeForSession(sessionId);
  }

  void _disposeSessionUi(String sessionId) {
    _terminalUi.disposeSession(sessionId);
  }

  void _handleTerminalInput(String data, String? sessionId) {
    if (data == '\x02') {
      _toggleBroadcastTyping();
      return;
    }
    final targetSessionId = sessionId ?? _sessionId;
    if (targetSessionId == null) return;
    if (!_isSessionConnected(targetSessionId)) return;
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

  List<session_models.TerminalSession> get _sshSessions => _connectionManager
      .sessions
      .where((session) => session.kind == session_models.SessionKind.ssh)
      .toList(growable: false);

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
    widget.onSessionChanged?.call(true);
    _notifyActiveSessionChanged(session.id);
    unawaited(_connectionManager.resizeTerminal(session.id, _cols, _rows));
  }

  Future<void> _openNewSessionForCurrentProfile() async {
    final profile = await _pickSessionProfile();
    if (profile == null) return;
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

    final orderIndex = _sessionOrder.indexOf(sessionId);
    await _connectionManager.closeSession(sessionId);
    _disposeSessionUi(sessionId);
    _sessionOrder.remove(sessionId);

    final result = await _connectionManager.connect(_toManagerProfile(profile));
    final failure = result.fold<Object?>((failure) => failure, (_) => null);
    if (failure != null || !mounted) {
      if (mounted) unawaited(_showConnectionFailedDialog(profile, failure!));
      return;
    }

    final newSession = _connectionManager.sessions.lastWhere(
      (session) =>
          session.kind == session_models.SessionKind.ssh &&
          session.profileId == profile.id,
    );
    _terminalForSession(newSession.id).write('\x1b[2J\x1b[H');
    setState(() {
      _sessionOrder.restoreAtOrPlaceLast(newSession.id, orderIndex);
      _replaceSessionIdEverywhere(sessionId, newSession.id);
      _sessionId = newSession.id;
      _connectedProfileId = newSession.profileId;
      _splitRoot ??= SplitLeaf(newSession.id);
    });
    widget.onSessionChanged?.call(true);
    _notifyActiveSessionChanged(newSession.id);
    await _connectionManager.resizeTerminal(newSession.id, _cols, _rows);
  }

  Future<domain.SshProfile?> _pickSessionProfile() {
    final profiles = widget.profiles
        .where((profile) => profile.isConnectable)
        .toList(growable: false);
    if (profiles.isEmpty) return Future.value(null);

    return showDialog<domain.SshProfile>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.add_rounded, color: AppColors.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('New SSH session', style: portixTitle(18)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: profiles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return SessionProfileOption(
                        profile: profile,
                        onSelected: () => Navigator.of(context).pop(profile),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _connectNewSession(domain.SshProfile profile) async {
    _connectedProfileId = profile.id;
    _idleTerminal.write('\x1b[2J\x1b[H');

    try {
      final result = await _connectionManager.connect(
        _toManagerProfile(profile),
      );
      result.fold((failure) {
        throw failure;
      }, (_) {});
      final session = _connectionManager.sessions.lastWhere(
        (item) =>
            item.profileId == profile.id &&
            item.kind == session_models.SessionKind.ssh,
      );
      final terminal = _terminalForSession(session.id);
      terminal.write('\x1b[2J\x1b[H');
      setState(() {
        _sessionId = session.id;
        _connectedProfileId = session.profileId;
        _activeTabClosed = false;
        _splitRoot = SplitLeaf(session.id);
        _workspaceActive = false;
        _activeWorkspaceId = null;
        _placeSessionInOrder(session.id);
      });
      widget.onSessionChanged?.call(true);
      _notifyActiveSessionChanged(session.id);
      await _connectionManager.resizeTerminal(session.id, _cols, _rows);
    } catch (error) {
      final failedSession = _connectionManager.sessions
          .where(
            (item) =>
                item.profileId == profile.id &&
                item.kind == session_models.SessionKind.ssh,
          )
          .lastOrNull;
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
    }
  }

  Future<void> _showConnectionFailedDialog(
    domain.SshProfile profile,
    Object error,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('SSH connection failed'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${profile.username}@${profile.host}:${profile.port}',
                style: portixTitle(13),
              ),
              const SizedBox(height: 10),
              Text('$error', style: portixMuted(12)),
            ],
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
      ),
    );
  }

  Future<void> _closeTab(String sessionId) async {
    final before = _sshSessions;
    final closedIndex = before.indexWhere((session) => session.id == sessionId);
    final wasActive = sessionId == _sessionId;

    await _connectionManager.closeSession(sessionId);
    _disposeSessionUi(sessionId);
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
      widget.onLastSessionClosed?.call();
      return;
    }

    if (!wasActive) {
      setState(() {});
      return;
    }

    final safeIndex = closedIndex < 0 ? 0 : closedIndex;
    final nextIndex = safeIndex >= remaining.length
        ? remaining.length - 1
        : safeIndex;
    _activateSession(remaining[nextIndex]);
  }

  void _splitPane(
    String targetSessionId,
    String draggedSessionId,
    SplitDirection direction,
  ) {
    if (targetSessionId == draggedSessionId) return;
    final session = _sessionById(draggedSessionId);
    if (session == null) return;
    _terminalForSession(draggedSessionId);

    setState(() {
      final targetWorkspace = _workspaceContainingSession(targetSessionId);

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
          cleanedRoot ?? SplitLeaf(targetSessionId),
          targetSessionId,
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
            SplitLeaf(targetSessionId),
            targetSessionId,
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
      _disposeSessionUi(sessionId);
      _sessionOrder.remove(sessionId);
    }
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
    final oldRoot = workspace.root;
    final oldIds = oldRoot.sessionIds.toList();
    final oldActiveId = _sessionId;
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
      _disposeSessionUi(oldId);
      final result = await _connectionManager.connect(
        _toManagerProfile(profile),
      );
      final connected = result.fold<bool>((_) => false, (_) => true);
      if (!connected) continue;
      final newSession = _connectionManager.sessions.lastWhere(
        (session) =>
            session.kind == session_models.SessionKind.ssh &&
            session.profileId == profile.id,
      );
      replacements[oldId] = newSession.id;
      final terminal = _terminalForSession(newSession.id);
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        '\x1b[36mReconnected to ${profile.username}@${profile.host}:${profile.port}...\x1b[0m\r\n',
      );
    }
    if (!mounted || replacements.isEmpty) return;
    setState(() {
      workspace.root = _splitController.replaceSessionIds(
        oldRoot,
        replacements,
      );
      _splitRoot = workspace.root;
      _workspaceActive = true;
      _activeWorkspaceId = workspace.id;
      _sessionId = replacements[oldActiveId] ?? workspace.root.sessionIds.last;
      _connectedProfileId = _sessionId == null
          ? null
          : _sessionById(_sessionId!)?.profileId;
    });
    widget.onSessionChanged?.call(_sessionId != null);
    _notifyActiveSessionChanged(_sessionId);
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

  Widget _buildSessionTab(session_models.TerminalSession session) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data != session.id && _sessionById(details.data) != null,
      onAcceptWithDetails: (details) => _moveSessionTab(
        details.data,
        targetSessionId: session.id,
        afterTarget: true,
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

  manager_profile.SshProfile _toManagerProfile(domain.SshProfile profile) {
    final credential = profile.credentialLabel.trim();
    final password =
        profile.authMethod == domain.AuthMethod.password &&
            credential.isNotEmpty &&
            credential != 'Saved password'
        ? credential
        : null;
    return manager_profile.SshProfile(
      id: profile.id,
      name: profile.name,
      host: profile.host,
      port: profile.port,
      username: profile.username,
      password: password,
      hasPassword: profile.authMethod == domain.AuthMethod.password,
      privateKeyPath: profile.authMethod == domain.AuthMethod.sshKey
          ? credential
          : null,
      group: profile.group,
      tags: profile.tags,
    );
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
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final isModifierPressed =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.keyB) {
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
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: DragTarget<String>(
                onAcceptWithDetails: (details) => _moveSessionTab(details.data),
                builder: (context, candidates, rejected) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: Row(
                            children: [
                              for (final workspace in _workspaces) ...[
                                TerminalSessionTab(
                                  sessionId: workspace.id,
                                  label: workspace.label,
                                  status: _workspaceStatus(workspace),
                                  active:
                                      _workspaceActive &&
                                      workspace.id == _activeWorkspaceId,
                                  leadingIcon: Icons.view_quilt_rounded,
                                  draggable: false,
                                  onTap: () => _activateWorkspace(workspace.id),
                                  onClose: () => _closeWorkspace(workspace.id),
                                  onReconnect: () =>
                                      _reconnectWorkspace(workspace.id),
                                  reconnectNearClose: true,
                                ),
                                const SizedBox(width: 10),
                              ],
                              for (final session in singleSessions) ...[
                                _buildSessionTab(session),
                                const SizedBox(width: 10),
                              ],
                              AppIconButton(
                                key: const ValueKey('new-terminal-tab'),
                                icon: Icons.add_rounded,
                                onPressed: _openNewSessionForCurrentProfile,
                              ),
                              if (candidates.isNotEmpty) ...[
                                const SizedBox(width: 10),
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
                      );
                    },
                  );
                },
              ),
            ),
            Expanded(
              child: displayRoot == null
                  ? NoTerminalConnection(
                      profile: widget.profile,
                      onConnect: widget.profile == null ? null : _connect,
                    )
                  : TerminalWorkspaceView(
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
                      focusNodeForSession: _focusNodeForSession,
                      idleController: _idleController,
                      idleFocusNode: _idleFocusNode,
                      onFocus: (sessionId) {
                        final session = _sessionById(sessionId);
                        if (session != null) {
                          _activateSession(session, keepWorkspaceVisible: true);
                        }
                      },
                      onClosePane: _removeSplit,
                      onSplit: _splitPane,
                      onReconnect: _reconnectSession,
                      onToggleBroadcast: _toggleBroadcastTyping,
                      onToggleSolo: _toggleSoloPane,
                    ),
            ),
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return TerminalStatusFooter(
                    snapshot: _remoteSnapshot,
                    samples: _metricSamples,
                    error: _telemetryError,
                    canUngroupWorkspace:
                        constraints.maxWidth >= 360 && _activeWorkspace != null,
                    onUngroupWorkspace: _activeWorkspace == null
                        ? null
                        : _ungroupActiveWorkspace,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
