import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/widgets/index.dart';

import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/error/failure.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/data/services/sftp/local_editor_service.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart'
    hide ConnectionStatus;
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';

import '../widget/remote/terminal_panel.dart';

class RemoteFolderPage extends StatefulWidget {
  const RemoteFolderPage({super.key});

  @override
  State<RemoteFolderPage> createState() => _RemoteFolderPageState();
}

class _RemoteFolderPageState extends State<RemoteFolderPage> {
  late final ConnectionManager _connectionManager = sl<ConnectionManager>();
  late final LocalEditorService _localEditorService = LocalEditorService();
  bool _hasTerminalSession = true;
  String? _profileId;
  String? _activeSessionId;
  String _remotePath = '~';
  bool _isLoadingRemote = false;
  bool _remoteFolderMounted = false;
  String? _remoteError;
  List<RemoteFileEntry> _remoteEntries = const [];
  final Set<String> _selectedRemotePaths = {};
  String? _selectionAnchorPath;
  double _remotePanelWidth = 320;
  bool _remotePanelVisible = true;
  final FocusNode _remoteListFocusNode = FocusNode(debugLabel: 'Remote files');
  final TextEditingController _inlineCreateController = TextEditingController();
  final FocusNode _inlineCreateFocusNode = FocusNode(
    debugLabel: 'Remote create',
  );
  final TextEditingController _inlineRenameController = TextEditingController();
  final FocusNode _inlineRenameFocusNode = FocusNode(
    debugLabel: 'Remote rename',
  );
  _InlineCreateKind? _inlineCreateKind;
  RemoteFileEntry? _renamingEntry;
  String? _autoLoadedSessionId;
  String? _autoLoadedPath;
  int _remoteLoadToken = 0;
  int _handledOpenRequestSerial = 0;
  final List<_TransferJob> _transferJobs = [];
  final Map<String, _LocalEditSession> _localEditSessions = {};
  int _transferSerial = 0;
  Timer? _transferAutoDismissTimer;

  static const double _minRemotePanelWidth = 220;
  static const double _maxRemotePanelWidth = 520;
  static const double _collapseThreshold = 140;
  static const Set<String> _codeFileExtensions = {
    'astro',
    'bash',
    'bat',
    'c',
    'cc',
    'conf',
    'cpp',
    'cs',
    'css',
    'dart',
    'env',
    'go',
    'gradle',
    'h',
    'hpp',
    'html',
    'java',
    'js',
    'json',
    'jsx',
    'kt',
    'kts',
    'lua',
    'm',
    'md',
    'php',
    'plist',
    'py',
    'rb',
    'rs',
    'scss',
    'sh',
    'sql',
    'swift',
    'toml',
    'ts',
    'tsx',
    'txt',
    'vue',
    'xml',
    'yaml',
    'yml',
    'zsh',
  };

  @override
  void initState() {
    super.initState();
    _connectionManager.addListener(_handleConnectionManagerChanged);
  }

  @override
  void dispose() {
    _transferAutoDismissTimer?.cancel();
    for (final editSession in _localEditSessions.values) {
      editSession.timer.cancel();
    }
    _inlineCreateController.dispose();
    _inlineCreateFocusNode.dispose();
    _inlineRenameController.dispose();
    _inlineRenameFocusNode.dispose();
    _remoteListFocusNode.dispose();
    _connectionManager.removeListener(_handleConnectionManagerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshWorkspaceBloc, SshWorkspaceState>(
      builder: (context, state) {
        final sessionState = context.watch<SshSessionBloc>().state;
        final isVisible = state.activeView == WorkspaceView.remoteFolder;
        final hasNewOpenRequest =
            sessionState.openRequestSerial != _handledOpenRequestSerial;
        if (hasNewOpenRequest) {
          _handledOpenRequestSerial = sessionState.openRequestSerial;
          _activeSessionId = null;
          _remoteLoadToken += 1;
          _isLoadingRemote = false;
          _remoteFolderMounted = false;
          _remoteEntries = const [];
          _remoteError = null;
          _autoLoadedSessionId = null;
          _autoLoadedPath = null;
          _clearRemoteSelection();
          _clearInlineRename();
        }
        final requestedProfile = sessionState.profileFrom(state.profiles);
        final activeProfile = _activeProfile(state);
        final shouldUseRequestedProfile =
            hasNewOpenRequest ||
            (sessionState.activeSessionId == null &&
                sessionState.targetProfileId != null);
        final profile = shouldUseRequestedProfile
            ? requestedProfile ?? activeProfile ?? state.selectedProfile
            : activeProfile ??
                  requestedProfile ??
                  (isVisible ? state.selectedProfile : null);
        final fallbackSession = profile == null
            ? null
            : _connectedSshSessionForProfile(profile.id);
        final needsSessionFallback =
            profile != null &&
            fallbackSession != null &&
            (_activeSessionId == null ||
                !_isSessionConnected(_activeSessionId!));
        if (needsSessionFallback) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _handleActiveSessionChanged(fallbackSession.id);
          });
        }
        if (profile?.id != _profileId) {
          _profileId = profile?.id;
          _hasTerminalSession = profile != null;
          _remotePath = _terminalFolderPath(profile);
          _remotePanelVisible = true;
          _remoteEntries = const [];
          _remoteError = null;
          _remoteFolderMounted = false;
          _autoLoadedSessionId = null;
          _autoLoadedPath = null;
          _clearRemoteSelection();
          _clearInlineRename();
          if (profile == null) {
            _activeSessionId = null;
          }
        }
        if (profile == null || !_hasTerminalSession) {
          _returnToProfilesWhenInactive(state);
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final mobile = constraints.maxWidth < 720;
            final showRemotePanel =
                !mobile && _remotePanelVisible && constraints.maxWidth >= 420;
            final remotePanelWidth = _remotePanelWidth
                .clamp(
                  _minRemotePanelWidth,
                  (constraints.maxWidth - 220).clamp(
                    _minRemotePanelWidth,
                    _maxRemotePanelWidth,
                  ),
                )
                .toDouble();
            return Row(
              children: [
                if (showRemotePanel) ...[
                  SizedBox(
                    width: remotePanelWidth,
                    child: _RemotePanelShell(
                      panelWidth: remotePanelWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 14),
                          _ConnectionCard(
                            profile: profile,
                            onClose: _closeRemotePanel,
                          ),
                          const SizedBox(height: 10),
                          _PathCrumb(
                            path: _remotePath,
                            onSubmit: (path) => _loadRemoteDirectory(path),
                          ),
                          if (_canShowRemoteActions) ...[
                            const SizedBox(height: 10),
                            _RemoteActionBar(onPressed: _handleFolderAction),
                          ],
                          const SizedBox(height: 14),
                          Expanded(child: _remoteList()),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _closeRemotePanel,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _remotePanelWidth += details.delta.dx;
                        if (_remotePanelWidth < _collapseThreshold) {
                          _remotePanelVisible = false;
                          _remotePanelWidth = 320;
                        } else {
                          _remotePanelWidth = _remotePanelWidth.clamp(
                            _minRemotePanelWidth,
                            _maxRemotePanelWidth,
                          );
                        }
                      });
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 8,
                        color: AppColors.border.withValues(alpha: .35),
                        child: Center(
                          child: Tooltip(
                            message: 'Click to close, drag to resize',
                            child: Container(
                              width: 2,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withValues(
                                  alpha: .55,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else if (!mobile && constraints.maxWidth >= 260)
                  _CollapsedRemoteRail(
                    onPressed: () => setState(() => _remotePanelVisible = true),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: TerminalPanel(
                          profile: profile,
                          profiles: state.profiles,
                          connectRequestId: sessionState.openRequestSerial,
                          keyboardEnabled: isVisible,
                          onSessionChanged: (active) {
                            if (mounted) {
                              setState(() => _hasTerminalSession = active);
                            }
                          },
                          onActiveSessionChanged: _handleActiveSessionChanged,
                          onLastSessionClosed: () {
                            context.read<SshSessionBloc>().add(
                              const SshSessionCleared(),
                            );
                            context.read<SshWorkspaceBloc>()
                              ..add(const ProfileSelectionCleared())
                              ..add(
                                const NavigationChanged(WorkspaceView.gallery),
                              );
                          },
                        ),
                      ),
                      if (mobile)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: AppIconButton(
                            icon: Icons.folder_open_rounded,
                            onPressed: () => _showMobileRemotePanel(profile),
                          ),
                        ),
                      if (_transferJobs.isNotEmpty)
                        Positioned(
                          right: mobile ? 12 : 18,
                          bottom: mobile ? 12 : 18,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: 280,
                              maxWidth: mobile
                                  ? (constraints.maxWidth - 24).clamp(
                                      280.0,
                                      380.0,
                                    )
                                  : 380,
                            ),
                            child: _TransferQueuePanel(
                              jobs: _transferJobs,
                              onClearFinished: _clearFinishedTransfers,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMobileRemotePanel(SshProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height * .72;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              height: height,
              child: _RemotePanelShell(
                panelWidth: MediaQuery.sizeOf(context).width - 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ConnectionCard(
                            profile: profile,
                            onClose: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _PathCrumb(
                      path: _remotePath,
                      onSubmit: (path) {
                        Navigator.of(context).pop();
                        _loadRemoteDirectory(path);
                      },
                    ),
                    if (_canShowRemoteActions) ...[
                      const SizedBox(height: 10),
                      _RemoteActionBar(onPressed: _handleFolderAction),
                    ],
                    const SizedBox(height: 12),
                    Expanded(child: _remoteList()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _canShowRemoteActions =>
      _activeSessionId != null && _remoteFolderMounted && _remoteError == null;

  void _returnToProfilesWhenInactive(SshWorkspaceState state) {
    if (state.activeView != WorkspaceView.remoteFolder) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SshSessionBloc>().add(const SshSessionCleared());
      context.read<SshWorkspaceBloc>()
        ..add(const ProfileSelectionCleared())
        ..add(const NavigationChanged(WorkspaceView.gallery));
    });
  }

  void _closeRemotePanel() {
    setState(() {
      _remotePanelVisible = false;
      _remotePanelWidth = 320;
    });
  }

  String _terminalFolderPath(SshProfile? profile) {
    if (profile == null) return '~';
    final startup = profile.startupCommand.trim();
    final cdMatch = RegExp(r'^cd\s+(.+)$').firstMatch(startup);
    if (cdMatch != null) return cdMatch.group(1)!.trim();
    final defaultPath = profile.defaultPath.trim();
    return defaultPath.isEmpty ? '~' : defaultPath;
  }

  SshProfile? _activeProfile(SshWorkspaceState state) {
    final sessionId = _activeSessionId;
    if (sessionId == null) return null;
    final session = _connectionManager.sessions
        .where((session) => session.id == sessionId)
        .firstOrNull;
    if (session == null) return null;
    return state.profiles
        .where((profile) => profile.id == session.profileId)
        .firstOrNull;
  }

  TerminalSession? _connectedSshSessionForProfile(String profileId) {
    for (final session in _connectionManager.sessions.reversed) {
      if (session.profileId == profileId &&
          session.kind == SessionKind.ssh &&
          session.status == ConnectionStatus.connected) {
        return session;
      }
    }
    return null;
  }

  void _handleActiveSessionChanged(String? sessionId) {
    if (!mounted) return;
    if (sessionId == _activeSessionId) return;
    setState(() {
      _activeSessionId = sessionId;
      _hasTerminalSession = sessionId != null;
      _clearRemoteSelection();
      _clearInlineRename();
      _remoteEntries = const [];
      _remoteError = null;
      _remoteFolderMounted = false;
      _autoLoadedSessionId = null;
      _autoLoadedPath = null;
      _remoteLoadToken += 1;
    });
    if (sessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _activeSessionId != sessionId) return;
        final state = context.read<SshWorkspaceBloc>().state;
        final profile = _activeProfile(state);
        final path = _terminalFolderPath(profile);
        setState(() {
          _remotePath = path;
          _remotePanelVisible = true;
        });
        _maybeAutoLoadRemoteFolder(sessionId, path);
      });
    }
  }

  void _handleConnectionManagerChanged() {
    final sessionId = _activeSessionId;
    if (!mounted || sessionId == null) return;
    if (!_isSessionConnected(sessionId)) {
      _markRemoteDisconnected();
      return;
    }
    _maybeAutoLoadRemoteFolder(sessionId, _remotePath);
  }

  void _clearFinishedTransfers() {
    _transferAutoDismissTimer?.cancel();
    setState(() {
      _transferJobs.removeWhere(
        (job) =>
            job.status == _TransferStatus.done ||
            job.status == _TransferStatus.failed,
      );
    });
  }

  _TransferJob _addTransferJob({
    required _TransferKind kind,
    required String label,
    required String remotePath,
    required int totalBytes,
  }) {
    _transferAutoDismissTimer?.cancel();
    final job = _TransferJob(
      id: ++_transferSerial,
      kind: kind,
      label: label,
      remotePath: remotePath,
      totalBytes: totalBytes,
    );
    setState(() => _transferJobs.insert(0, job));
    return job;
  }

  void _updateTransferJob(
    _TransferJob job, {
    _TransferStatus? status,
    int? transferredBytes,
    int? totalBytes,
    String? error,
  }) {
    if (!mounted) return;
    setState(() {
      job
        ..status = status ?? job.status
        ..transferredBytes = transferredBytes ?? job.transferredBytes
        ..totalBytes = totalBytes ?? job.totalBytes
        ..error = error;
    });
    _scheduleTransferAutoDismissIfIdle();
  }

  void _scheduleTransferAutoDismissIfIdle() {
    _transferAutoDismissTimer?.cancel();
    if (_transferJobs.isEmpty) return;
    final hasActiveTransfer = _transferJobs.any(
      (job) =>
          job.status == _TransferStatus.queued ||
          job.status == _TransferStatus.running,
    );
    if (hasActiveTransfer) return;
    _transferAutoDismissTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      setState(() => _transferJobs.clear());
    });
  }

  void _maybeAutoLoadRemoteFolder(String sessionId, String path) {
    if (!_isSessionConnected(sessionId)) return;
    if (_autoLoadedSessionId == sessionId && _autoLoadedPath == path) return;
    _autoLoadedSessionId = sessionId;
    _autoLoadedPath = path;
    unawaited(_loadRemoteDirectory(path));
  }

  bool _isSessionConnected(String sessionId) {
    return _connectionManager.sessions.any(
      (session) =>
          session.id == sessionId &&
          session.kind == SessionKind.ssh &&
          session.status == ConnectionStatus.connected,
    );
  }

  void _markRemoteDisconnected() {
    if (!_isLoadingRemote && !_remoteFolderMounted && _remoteError != null) {
      return;
    }
    setState(() {
      _remoteLoadToken += 1;
      _isLoadingRemote = false;
      _remoteFolderMounted = false;
      _remoteEntries = const [];
      _clearRemoteSelection();
      _clearInlineRename();
      _autoLoadedSessionId = null;
      _autoLoadedPath = null;
      _remoteError = 'SSH session is disconnected.';
    });
  }

  Future<void> _loadRemoteDirectory(String path) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    if (!_isSessionConnected(sessionId)) {
      _markRemoteDisconnected();
      return;
    }
    final token = ++_remoteLoadToken;
    setState(() {
      _isLoadingRemote = true;
      _remoteError = null;
    });

    final resolvedResult = await _connectionManager.resolveRemoteDirectory(
      sessionId,
      path,
    );
    if (!_isSessionConnected(sessionId)) {
      if (_isCurrentRemoteRequest(sessionId, token)) _markRemoteDisconnected();
      return;
    }
    final resolvedPath = resolvedResult.fold<String?>((failure) {
      if (!_isCurrentRemoteRequest(sessionId, token)) return null;
      setState(() {
        _isLoadingRemote = false;
        _remoteError = failure.message;
        _remoteFolderMounted = false;
      });
      return null;
    }, (value) => value);
    if (resolvedPath == null) return;

    final entriesResult = await _connectionManager.listRemoteDirectory(
      sessionId,
      resolvedPath,
    );
    if (!_isSessionConnected(sessionId)) {
      if (_isCurrentRemoteRequest(sessionId, token)) _markRemoteDisconnected();
      return;
    }
    entriesResult.fold(
      (failure) {
        if (!_isCurrentRemoteRequest(sessionId, token)) return;
        setState(() {
          _isLoadingRemote = false;
          _remoteError = failure.message;
          _remoteFolderMounted = false;
        });
      },
      (entries) {
        if (!_isCurrentRemoteRequest(sessionId, token)) return;
        setState(() {
          _remotePath = resolvedPath;
          _remoteEntries = [...entries]..sort(_sortRemoteEntries);
          _isLoadingRemote = false;
          _remoteError = null;
          _remoteFolderMounted = true;
          _clearRemoteSelection();
          _clearInlineRename();
        });
      },
    );
  }

  bool _isCurrentRemoteRequest(String sessionId, int token) {
    return mounted &&
        _activeSessionId == sessionId &&
        _remoteLoadToken == token;
  }

  int _sortRemoteEntries(RemoteFileEntry a, RemoteFileEntry b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _clearRemoteSelection() {
    _selectedRemotePaths.clear();
    _selectionAnchorPath = null;
  }

  void _clearInlineRename() {
    _renamingEntry = null;
    _inlineRenameController.clear();
  }

  void _selectAllRemoteEntries(List<RemoteFileEntry> entries) {
    setState(() {
      _selectedRemotePaths
        ..clear()
        ..addAll(
          entries
              .where((entry) => entry.name != '..')
              .map((entry) => entry.path),
        );
      _selectionAnchorPath = _selectedRemotePaths.isEmpty
          ? null
          : _selectedRemotePaths.last;
    });
  }

  void _selectRemoteEntry(
    RemoteFileEntry entry,
    List<RemoteFileEntry> entries,
  ) {
    if (entry.name == '..') {
      _openRemoteEntry(entry);
      return;
    }
    _remoteListFocusNode.requestFocus();
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final togglePressed =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final shiftPressed =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);

    setState(() {
      if (shiftPressed && _selectionAnchorPath != null) {
        final selectable = entries
            .where((entry) => entry.name != '..')
            .toList(growable: false);
        final anchorIndex = selectable.indexWhere(
          (item) => item.path == _selectionAnchorPath,
        );
        final currentIndex = selectable.indexWhere(
          (item) => item.path == entry.path,
        );
        if (anchorIndex != -1 && currentIndex != -1) {
          final start = anchorIndex < currentIndex ? anchorIndex : currentIndex;
          final end = anchorIndex < currentIndex ? currentIndex : anchorIndex;
          _selectedRemotePaths
            ..clear()
            ..addAll(
              selectable.sublist(start, end + 1).map((entry) => entry.path),
            );
          return;
        }
      }

      if (togglePressed) {
        if (_selectedRemotePaths.contains(entry.path)) {
          _selectedRemotePaths.remove(entry.path);
        } else {
          _selectedRemotePaths.add(entry.path);
          _selectionAnchorPath = entry.path;
        }
        if (_selectedRemotePaths.isEmpty) _selectionAnchorPath = null;
        return;
      }

      _selectedRemotePaths
        ..clear()
        ..add(entry.path);
      _selectionAnchorPath = entry.path;
    });
  }

  void _openRemoteEntry(RemoteFileEntry entry) {
    if (!entry.isDirectory) return;
    unawaited(_loadRemoteDirectory(entry.path));
  }

  Future<void> _handleRemoteEntryDoubleTap(RemoteFileEntry entry) async {
    if (entry.isDirectory) {
      _openRemoteEntry(entry);
      return;
    }
    await _openRemoteFileLocally(entry);
  }

  Future<void> _handleRemoteEntryAction(
    BuildContext context,
    _RemoteEntryAction action,
    RemoteFileEntry entry,
  ) async {
    switch (action) {
      case _RemoteEntryAction.open:
        if (entry.isDirectory) {
          _openRemoteEntry(entry);
        } else {
          await _openRemoteFileLocally(entry);
        }
      case _RemoteEntryAction.edit:
        await _openRemoteFileLocally(
          entry,
          preferCodeEditor: true,
          watchForRewrite: true,
        );
      case _RemoteEntryAction.openWith:
        await _openRemoteFileWithEditorPicker(context, entry);
      case _RemoteEntryAction.rename:
        _startInlineRename(entry);
      case _RemoteEntryAction.delete:
        await _deleteRemoteEntry(context, entry);
    }
  }

  void _startInlineRename(RemoteFileEntry entry) {
    if (entry.name == '..') return;
    setState(() {
      _inlineCreateKind = null;
      _renamingEntry = entry;
      _inlineRenameController.text = entry.name;
      _selectedRemotePaths
        ..clear()
        ..add(entry.path);
      _selectionAnchorPath = entry.path;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _renamingEntry?.path != entry.path) return;
      _inlineRenameFocusNode.requestFocus();
      _inlineRenameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inlineRenameController.text.length,
      );
    });
  }

  void _cancelInlineRename() {
    setState(_clearInlineRename);
  }

  Future<void> _submitInlineRename() async {
    final sessionId = _activeSessionId;
    final entry = _renamingEntry;
    final newName = _inlineRenameController.text.trim();
    if (sessionId == null || entry == null) return;
    if (newName.isEmpty || newName == entry.name) {
      _cancelInlineRename();
      return;
    }
    if (newName.contains('/') || newName.contains('\\')) {
      _showMessage(context, 'Rename only supports a name, not a path.');
      return;
    }
    final targetPath = _renameTargetPath(entry.path, newName);
    setState(() => _isLoadingRemote = true);
    final command =
        'mv -- ${_shellQuote(entry.path)} ${_shellQuote(targetPath)} && printf "\\nPORTIX_RENAME_OK\\n"\n';
    final result = await _connectionManager.sendTerminalInput(
      sessionId,
      command,
    );
    result.fold((failure) => _showMessage(context, _failureDetails(failure)), (
      _,
    ) {
      _selectedRemotePaths
        ..remove(entry.path)
        ..add(targetPath);
      _selectionAnchorPath = targetPath;
      _clearInlineRename();
    });
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await _loadRemoteDirectory(_remotePath);
    if (mounted) setState(() => _isLoadingRemote = false);
  }

  Future<void> _openRemoteFileLocally(
    RemoteFileEntry entry, {
    bool preferCodeEditor = false,
    bool watchForRewrite = false,
    LocalEditor? editorOverride,
  }) async {
    final sessionId = _activeSessionId;
    if (sessionId == null || entry.isDirectory || entry.name == '..') return;
    final tempRoot = await Directory.systemTemp.createTemp(
      'portix-remote-open-',
    );
    final localPath =
        '${tempRoot.path}${Platform.pathSeparator}${_safeLocalFileName(entry.name)}';
    try {
      final ok = await _downloadRemoteFile(
        sessionId,
        entry.path,
        localPath,
        sizeBytes: entry.sizeBytes,
      );
      if (!ok) return;
      final originalText = await _readFileTextIfPossible(localPath);
      final editors = await _localEditorService.detectEditors();
      final useCodeEditor =
          _shouldOpenInCodeEditor(entry.name) && preferCodeEditor;
      final editor =
          editorOverride ??
          _preferredLocalEditor(editors, preferCodeEditor: useCodeEditor);
      if (editor == null) {
        if (mounted) {
          _showMessage(context, 'Local editor was not found on this machine.');
        }
        return;
      }
      await _localEditorService.open(editor, localPath);
      final shouldWatchForRewrite =
          watchForRewrite || (useCodeEditor && !_isDefaultSystemEditor(editor));
      if (shouldWatchForRewrite) {
        await _watchLocalEditForRewrite(
          sessionId: sessionId,
          entry: entry,
          localPath: localPath,
          originalText: originalText,
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          context,
          'Open file failed: ${_compactErrorMessage('$error')}',
        );
      }
    }
  }

  Future<void> _openRemoteFileWithEditorPicker(
    BuildContext context,
    RemoteFileEntry entry,
  ) async {
    if (entry.isDirectory || entry.name == '..') return;
    final editors = await _localEditorService.detectEditors();
    if (!context.mounted) return;
    if (editors.isEmpty) {
      _showMessage(context, 'Local editor was not found on this machine.');
      return;
    }
    final editor = await showModalBottomSheet<LocalEditor>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) => _OpenWithEditorSheet(editors: editors),
    );
    if (editor == null) return;
    await _openRemoteFileLocally(
      entry,
      editorOverride: editor,
      watchForRewrite: editor.command != 'open' || editor.arguments.isNotEmpty,
    );
  }

  LocalEditor? _preferredLocalEditor(
    List<LocalEditor> editors, {
    required bool preferCodeEditor,
  }) {
    if (editors.isEmpty) return null;
    if (preferCodeEditor) {
      for (final editor in editors) {
        if (!_isDefaultSystemEditor(editor)) return editor;
      }
    }
    if (Platform.isMacOS) {
      for (final editor in editors) {
        if (editor.command == 'open' && editor.arguments.isEmpty) {
          return editor;
        }
      }
    }
    return editors.first;
  }

  bool _isDefaultSystemEditor(LocalEditor editor) {
    return editor.command == 'open' && editor.arguments.isEmpty;
  }

  bool _shouldOpenInCodeEditor(String fileName) {
    final extension = _fileExtension(fileName);
    if (extension.isEmpty) {
      return fileName.startsWith('.') ||
          const {
            'dockerfile',
            'makefile',
            'gemfile',
            'rakefile',
            'procfile',
            'license',
            'readme',
          }.contains(fileName.toLowerCase());
    }
    return _codeFileExtensions.contains(extension);
  }

  Future<void> _watchLocalEditForRewrite({
    required String sessionId,
    required RemoteFileEntry entry,
    required String localPath,
    required String? originalText,
  }) async {
    final file = File(localPath);
    final stat = await file.stat();
    _localEditSessions.remove(localPath)?.timer.cancel();
    var lastPromptedAt = stat.modified;
    var promptOpen = false;
    final timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final currentStat = await file.stat();
        if (!currentStat.modified.isAfter(lastPromptedAt)) return;
        lastPromptedAt = currentStat.modified;
        if (promptOpen) return;
        promptOpen = true;
        await _showRewritePrompt(sessionId, entry, localPath, originalText);
        promptOpen = false;
      } catch (_) {
        timer.cancel();
        _localEditSessions.remove(localPath);
      }
    });
    _localEditSessions[localPath] = _LocalEditSession(
      remotePath: entry.path,
      localPath: localPath,
      timer: timer,
      originalText: originalText,
    );
  }

  Future<void> _showRewritePrompt(
    String sessionId,
    RemoteFileEntry entry,
    String localPath,
    String? originalText,
  ) async {
    if (!mounted) return;
    final currentText = await _readFileTextIfPossible(localPath);
    if (!mounted) return;
    final diff = _buildTextDiff(originalText, currentText);
    final shouldRewrite = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _RewriteRemoteDialog(fileName: entry.name, diff: diff),
    );
    if (shouldRewrite == true) {
      await _rewriteEditedRemoteFile(sessionId, entry, localPath);
    }
  }

  Future<String?> _readFileTextIfPossible(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.contains(0)) return null;
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }

  _TextDiff _buildTextDiff(String? before, String? after) {
    if (before == null || after == null) {
      return const _TextDiff(
        added: 0,
        removed: 0,
        lines: ['Binary or non-text diff preview is not available.'],
      );
    }
    final beforeLines = before.split('\n');
    final afterLines = after.split('\n');
    final maxLength = beforeLines.length > afterLines.length
        ? beforeLines.length
        : afterLines.length;
    var added = 0;
    var removed = 0;
    final preview = <String>[];
    for (var index = 0; index < maxLength; index += 1) {
      final oldLine = index < beforeLines.length ? beforeLines[index] : null;
      final newLine = index < afterLines.length ? afterLines[index] : null;
      if (oldLine == newLine) continue;
      if (oldLine != null) {
        removed += 1;
        if (preview.length < 80) preview.add('- $oldLine');
      }
      if (newLine != null) {
        added += 1;
        if (preview.length < 80) preview.add('+ $newLine');
      }
    }
    return _TextDiff(
      added: added,
      removed: removed,
      lines: preview.isEmpty ? const ['No textual diff detected.'] : preview,
    );
  }

  Future<void> _rewriteEditedRemoteFile(
    String sessionId,
    RemoteFileEntry entry,
    String localPath,
  ) async {
    try {
      final bytes = await File(localPath).readAsBytes();
      final result = await _connectionManager.uploadRemoteFile(
        sessionId,
        entry.path,
        bytes,
      );
      result.fold(
        (failure) => _showMessage(context, _failureDetails(failure)),
        (_) {
          _showMessage(context, 'Remote file rewritten: ${entry.name}');
          unawaited(_loadRemoteDirectory(_remotePath));
        },
      );
    } catch (error) {
      _showMessage(
        context,
        'Rewrite failed: ${_compactErrorMessage('$error')}',
      );
    }
  }

  Future<void> _deleteRemoteEntry(
    BuildContext context,
    RemoteFileEntry entry,
  ) async {
    final sessionId = _activeSessionId;
    if (sessionId == null || entry.name == '..') return;
    final path = entry.path.trim();
    if (path.isEmpty || path == '/' || path == '~') {
      _showMessage(context, 'This remote path cannot be deleted.');
      return;
    }
    setState(() => _isLoadingRemote = true);
    final command =
        'rm -rf -- ${_shellQuote(path)} && printf "\\nPORTIX_DELETE_OK\\n"\n';
    final result = await _connectionManager.sendTerminalInput(
      sessionId,
      command,
    );
    result.fold((failure) => _showMessage(context, _failureDetails(failure)), (
      _,
    ) {
      _selectedRemotePaths.remove(path);
    });
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await _loadRemoteDirectory(_remotePath);
    if (mounted) setState(() => _isLoadingRemote = false);
  }

  Future<void> _handleFolderAction(BuildContext context, String action) async {
    switch (action) {
      case 'Upload':
        await _uploadLocalEntries(context);
      case 'Download':
        await _downloadSelected(context);
      case 'New folder':
        await _createRemoteFolder(context);
      case 'New file':
        await _createRemoteFile(context);
    }
  }

  Future<void> _downloadSelected(BuildContext context) async {
    final sessionId = _activeSessionId;
    final selectedEntries = _selectedRemoteEntries();
    if (sessionId == null) return;
    if (selectedEntries.isEmpty) {
      _showMessage(context, 'Select a remote file or folder first.');
      return;
    }
    final singleEntry = selectedEntries.length == 1
        ? selectedEntries.first
        : null;
    final target = singleEntry == null || singleEntry.isDirectory
        ? await _pickDownloadFolder(context)
        : await _pickDownloadFilePath(context, singleEntry.name);
    if (target == null || target.trim().isEmpty) return;
    setState(() => _isLoadingRemote = true);
    var completed = 0;
    var failed = 0;
    try {
      if (singleEntry != null) {
        final stats = await _downloadEntryToTarget(
          sessionId,
          singleEntry,
          target.trim(),
          keepNameForFile: false,
        );
        completed = stats.completed;
        failed = stats.failed;
      } else {
        final localRoot = Directory(target.trim());
        await localRoot.create(recursive: true);
        for (final entry in selectedEntries) {
          final stats = await _downloadEntryToTarget(
            sessionId,
            entry,
            localRoot.path,
            keepNameForFile: true,
          );
          completed += stats.completed;
          failed += stats.failed;
        }
      }
      if (mounted && completed + failed > 0) setState(() {});
    } catch (error) {
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isLoadingRemote = false);
    }
  }

  List<RemoteFileEntry> _selectedRemoteEntries() {
    if (_selectedRemotePaths.isEmpty) return const [];
    return _remoteEntries
        .where((entry) => _selectedRemotePaths.contains(entry.path))
        .toList(growable: false);
  }

  Future<_TransferStats> _downloadEntryToTarget(
    String sessionId,
    RemoteFileEntry entry,
    String target, {
    required bool keepNameForFile,
  }) async {
    if (entry.isDirectory) {
      final localRoot = Directory(target);
      await localRoot.create(recursive: true);
      return _downloadRemoteDirectory(
        sessionId,
        entry.path,
        '${localRoot.path}${Platform.pathSeparator}${entry.name}',
      );
    }

    final localPath = keepNameForFile
        ? '$target${Platform.pathSeparator}${entry.name}'
        : target;
    final ok = await _downloadRemoteFile(
      sessionId,
      entry.path,
      localPath,
      sizeBytes: entry.sizeBytes,
    );
    return _TransferStats(completed: ok ? 1 : 0, failed: ok ? 0 : 1);
  }

  Future<bool> _downloadRemoteFile(
    String sessionId,
    String remotePath,
    String localPath, {
    int totalBytes = 0,
    int sizeBytes = 0,
  }) async {
    final job = _addTransferJob(
      kind: _TransferKind.download,
      label: _basename(remotePath),
      remotePath: remotePath,
      totalBytes: totalBytes > 0 ? totalBytes : sizeBytes,
    );
    _updateTransferJob(job, status: _TransferStatus.running);
    final result = await _connectionManager.readRemoteFileBytes(
      sessionId,
      remotePath,
    );
    final bytes = result.fold<List<int>>((failure) {
      _updateTransferJob(
        job,
        status: _TransferStatus.failed,
        error: _failureDetails(failure),
      );
      throw StateError(failure.message);
    }, (bytes) => bytes);
    if (bytes.isEmpty && (totalBytes > 0 || sizeBytes > 0)) {
      const message = 'Remote download returned empty data.';
      _updateTransferJob(job, status: _TransferStatus.failed, error: message);
      throw StateError(message);
    }
    _updateTransferJob(
      job,
      status: _TransferStatus.running,
      totalBytes: bytes.length,
      transferredBytes: (bytes.length * .75).round(),
    );
    final file = File(localPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    _updateTransferJob(
      job,
      status: _TransferStatus.done,
      totalBytes: bytes.length,
      transferredBytes: bytes.length,
    );
    return true;
  }

  Future<_TransferStats> _downloadRemoteDirectory(
    String sessionId,
    String remotePath,
    String localPath,
  ) async {
    var completed = 0;
    var failed = 0;
    await Directory(localPath).create(recursive: true);
    final result = await _connectionManager.listRemoteDirectory(
      sessionId,
      remotePath,
    );
    final entries = result.fold<List<RemoteFileEntry>>((failure) {
      throw StateError(failure.message);
    }, (entries) => entries);
    for (final entry in entries) {
      final childPath = '$localPath${Platform.pathSeparator}${entry.name}';
      if (entry.isDirectory) {
        final stats = await _downloadRemoteDirectory(
          sessionId,
          entry.path,
          childPath,
        );
        completed += stats.completed;
        failed += stats.failed;
      } else {
        try {
          final ok = await _downloadRemoteFile(
            sessionId,
            entry.path,
            childPath,
            sizeBytes: entry.sizeBytes,
          );
          if (ok) {
            completed += 1;
          } else {
            failed += 1;
          }
        } catch (_) {
          failed += 1;
        }
      }
    }
    return _TransferStats(completed: completed, failed: failed);
  }

  Future<void> _uploadLocalEntries(BuildContext context) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    final localPaths = await _pickUploadEntries(context);
    if (localPaths == null || localPaths.isEmpty) return;
    await _uploadLocalPaths(context, sessionId, localPaths);
  }

  Future<void> _uploadLocalPaths(
    BuildContext context,
    String sessionId,
    List<String> localPaths,
  ) async {
    setState(() => _isLoadingRemote = true);
    var completed = 0;
    var failed = 0;
    try {
      final plan = await _buildUploadPlan(localPaths, _remotePath);
      if (plan.files.isEmpty) {
        if (mounted) _showMessage(context, 'No uploadable files selected.');
        return;
      }
      for (final directoryPath in plan.directories) {
        final createResult = await _connectionManager.createRemoteDirectory(
          sessionId,
          directoryPath,
        );
        createResult.fold(
          (failure) => throw StateError(failure.message),
          (_) {},
        );
      }
      for (final file in plan.files) {
        try {
          final ok = await _uploadPlannedFile(sessionId, file);
          if (ok) {
            completed += 1;
          } else {
            failed += 1;
          }
        } catch (_) {
          failed += 1;
        }
      }
      await _loadRemoteDirectory(_remotePath);
      if (mounted && completed + failed > 0) setState(() {});
    } catch (error) {
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isLoadingRemote = false);
    }
  }

  Future<bool> _uploadPlannedFile(
    String sessionId,
    _UploadFilePlan file,
  ) async {
    final job = _addTransferJob(
      kind: _TransferKind.upload,
      label: file.label,
      remotePath: file.remotePath,
      totalBytes: file.sizeBytes,
    );
    _updateTransferJob(job, status: _TransferStatus.running);
    final bytes = await file.file.readAsBytes();
    _updateTransferJob(
      job,
      transferredBytes: (bytes.length * .25).round(),
      totalBytes: bytes.length,
    );
    final result = await _connectionManager.uploadRemoteFile(
      sessionId,
      file.remotePath,
      bytes,
    );
    final uploaded = result.fold(
      (failure) {
        _updateTransferJob(
          job,
          status: _TransferStatus.failed,
          error: _failureDetails(failure),
        );
        return false;
      },
      (_) {
        return true;
      },
    );
    if (!uploaded) return false;
    _updateTransferJob(
      job,
      status: _TransferStatus.running,
      transferredBytes: (bytes.length * .85).round(),
      totalBytes: bytes.length,
    );
    final verified = await _verifyRemoteFileUploaded(sessionId, file);
    if (!verified) {
      _updateTransferJob(
        job,
        status: _TransferStatus.failed,
        transferredBytes: bytes.length,
        totalBytes: bytes.length,
        error: 'Upload finished but file was not found on remote.',
      );
      return false;
    }
    _updateTransferJob(
      job,
      status: _TransferStatus.done,
      transferredBytes: bytes.length,
      totalBytes: bytes.length,
    );
    return true;
  }

  Future<bool> _verifyRemoteFileUploaded(
    String sessionId,
    _UploadFilePlan file,
  ) async {
    final parentPath = _parentPath(file.remotePath);
    final result = await _connectionManager.listRemoteDirectory(
      sessionId,
      parentPath,
    );
    return result.fold((_) => false, (entries) {
      final name = _basename(file.remotePath);
      return entries.any(
        (entry) =>
            !entry.isDirectory &&
            entry.name == name &&
            (file.sizeBytes <= 0 ||
                entry.sizeBytes <= 0 ||
                entry.sizeBytes == file.sizeBytes),
      );
    });
  }

  String _failureDetails(Failure failure) {
    if (failure is AppFailure && failure.cause != null) {
      final cause = failure.cause.toString().trim();
      if (cause.isNotEmpty) return _compactErrorMessage(cause);
    }
    return _compactErrorMessage(failure.message);
  }

  String _compactErrorMessage(String message) {
    var compact = message.split('Stack backtrace:').first.trim();
    if (compact.startsWith('AnyhowException(') && compact.endsWith(')')) {
      compact = compact.substring(
        'AnyhowException('.length,
        compact.length - 1,
      );
    }
    compact = compact.replaceAll(RegExp(r'\s+'), ' ').trim();
    const maxLength = 180;
    if (compact.length > maxLength) {
      return '${compact.substring(0, maxLength)}...';
    }
    return compact.isEmpty ? 'Transfer failed.' : compact;
  }

  Future<_UploadPlan> _buildUploadPlan(
    List<String> localPaths,
    String remoteDirectory,
  ) async {
    final directories = <String>{};
    final files = <_UploadFilePlan>[];
    for (final rawPath in localPaths) {
      final localPath = rawPath.trim();
      final entityType = FileSystemEntity.typeSync(localPath);
      if (entityType == FileSystemEntityType.notFound) {
        throw StateError('Local path not found: $localPath');
      }
      if (entityType == FileSystemEntityType.directory) {
        final directory = Directory(localPath);
        final remoteRoot = _joinRemote(remoteDirectory, _basename(localPath));
        directories.add(remoteRoot);
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is Directory) {
            directories.add(
              _joinRemoteRelative(
                remoteRoot,
                _relativeLocalPath(entity.path, directory.path),
              ),
            );
          } else if (entity is File) {
            final relativePath = _relativeLocalPath(
              entity.path,
              directory.path,
            );
            final remotePath = _joinRemoteRelative(remoteRoot, relativePath);
            files.add(
              _UploadFilePlan(
                file: entity,
                remotePath: remotePath,
                label: '${_basename(localPath)}/$relativePath',
                sizeBytes: await entity.length(),
              ),
            );
          }
        }
      } else if (entityType == FileSystemEntityType.file) {
        final file = File(localPath);
        files.add(
          _UploadFilePlan(
            file: file,
            remotePath: _joinRemote(remoteDirectory, _basename(localPath)),
            label: _basename(localPath),
            sizeBytes: await file.length(),
          ),
        );
      }
    }
    return _UploadPlan(directories: directories.toList(), files: files);
  }

  Future<void> _createRemoteFolder(BuildContext context) async {
    _startInlineCreate(_InlineCreateKind.folder);
  }

  Future<void> _createRemoteFile(BuildContext context) async {
    _startInlineCreate(_InlineCreateKind.file);
  }

  void _startInlineCreate(_InlineCreateKind kind) {
    setState(() {
      _inlineCreateKind = kind;
      _inlineCreateController.clear();
      _clearRemoteSelection();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _inlineCreateKind != kind) return;
      _inlineCreateFocusNode.requestFocus();
    });
  }

  void _cancelInlineCreate() {
    setState(() {
      _inlineCreateKind = null;
      _inlineCreateController.clear();
    });
  }

  Future<void> _submitInlineCreate() async {
    final sessionId = _activeSessionId;
    final kind = _inlineCreateKind;
    final name = _inlineCreateController.text.trim();
    if (sessionId == null || kind == null) return;
    if (name.isEmpty) {
      _cancelInlineCreate();
      return;
    }
    final path = _joinRemote(_remotePath, name);
    final result = kind == _InlineCreateKind.folder
        ? await _connectionManager.createRemoteDirectory(sessionId, path)
        : await _connectionManager.createRemoteFile(sessionId, path);
    result.fold((failure) => _showMessage(context, _failureDetails(failure)), (
      _,
    ) {
      _cancelInlineCreate();
      unawaited(_loadRemoteDirectory(_remotePath));
    });
  }

  Future<List<String>?> _pickUploadEntries(BuildContext context) async {
    try {
      if (Platform.isMacOS) {
        final paths = await FilePicker.pickFileAndDirectoryPaths(
          initialDirectory: _defaultLocalPath(),
        );
        return _cleanPickedPaths(paths);
      }
      return _pickUploadFilesOnly();
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Local explorer failed: $error');
      }
      return null;
    }
  }

  Future<List<String>?> _pickUploadFilesOnly() async {
    final result = await FilePicker.pickFiles(
      initialDirectory: _defaultLocalPath(),
      allowMultiple: true,
      dialogTitle: 'Upload from local',
    );
    return _cleanPickedPaths(result?.paths);
  }

  Future<String?> _pickDownloadFolder(BuildContext context) async {
    try {
      return FilePicker.getDirectoryPath(
        initialDirectory: _downloadsPath(),
        dialogTitle: 'Download remote folder to',
      );
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'Local explorer failed.');
      }
      return null;
    }
  }

  Future<String?> _pickDownloadFilePath(
    BuildContext context,
    String fileName,
  ) async {
    try {
      return FilePicker.saveFile(
        initialDirectory: _downloadsPath(),
        fileName: fileName,
        dialogTitle: 'Download remote file to',
      );
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'Local explorer failed.');
      }
      return null;
    }
  }

  List<String>? _cleanPickedPaths(List<String?>? paths) {
    final clean = paths
        ?.whereType<String>()
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList();
    if (clean == null || clean.isEmpty) return null;
    return clean;
  }

  String _parentPath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty || normalized == '/' || normalized == '~') {
      return normalized.isEmpty ? '~' : normalized;
    }
    final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
    if (parts.length <= 1) return '/';
    return '/${parts.take(parts.length - 1).join('/')}';
  }

  Widget _remoteList() {
    if (_activeSessionId == null) {
      return const _RemoteStatus(
        icon: Icons.cloud_sync_outlined,
        title: 'Waiting for SSH session',
        message: 'Remote folder will load after the Rust bridge is ready.',
      );
    }
    if (_isLoadingRemote) {
      return const _RemoteStatus(
        icon: Icons.sync_rounded,
        title: 'Loading remote folder',
        message: 'Reading directory through Rust bridge...',
        loading: true,
      );
    }
    if (_remoteError != null) {
      return _RemoteStatus(
        icon: _isSessionConnected(_activeSessionId!)
            ? Icons.error_outline_rounded
            : Icons.cloud_off_outlined,
        title: 'Remote folder unavailable',
        message: _remoteError!,
        actionLabel: _isSessionConnected(_activeSessionId!) ? 'Retry' : null,
        onAction: _isSessionConnected(_activeSessionId!)
            ? () => _loadRemoteDirectory(_remotePath)
            : null,
      );
    }
    if (!_remoteFolderMounted) {
      return _RemoteStatus(
        icon: Icons.folder_outlined,
        title: 'Remote folder not mounted',
        message: 'Open the path when you want to browse remote files.',
        actionLabel: 'Open folder',
        onAction: () => _loadRemoteDirectory(_remotePath),
      );
    }
    final entries = _visibleRemoteEntries();
    if (entries.isEmpty) {
      return const _RemoteStatus(
        icon: Icons.folder_open_rounded,
        title: 'Remote folder is empty',
        message: 'Create or upload a file to start filling this path.',
      );
    }
    return Focus(
      focusNode: _remoteListFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final isSelectAll =
            event.logicalKey == LogicalKeyboardKey.keyA &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed);
        if (!isSelectAll) return KeyEventResult.ignored;
        _selectAllRemoteEntries(entries);
        return KeyEventResult.handled;
      },
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: entries.length + (_inlineCreateKind == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (_inlineCreateKind != null && index == 0) {
            return _InlineCreateItem(
              kind: _inlineCreateKind!,
              controller: _inlineCreateController,
              focusNode: _inlineCreateFocusNode,
              onSubmit: _submitInlineCreate,
              onCancel: _cancelInlineCreate,
            );
          }
          final entryIndex = index - (_inlineCreateKind == null ? 0 : 1);
          final entry = entries[entryIndex];
          if (_renamingEntry?.path == entry.path) {
            return _InlineRenameItem(
              entry: entry,
              controller: _inlineRenameController,
              focusNode: _inlineRenameFocusNode,
              onSubmit: _submitInlineRename,
              onCancel: _cancelInlineRename,
            );
          }
          return _RemoteItem(
            item: entry,
            selected: _selectedRemotePaths.contains(entry.path),
            onTap: () => _selectRemoteEntry(entry, entries),
            onDoubleTap: () => _handleRemoteEntryDoubleTap(entry),
            onAction: (action) =>
                _handleRemoteEntryAction(context, action, entry),
          );
        },
      ),
    );
  }

  List<RemoteFileEntry> _visibleRemoteEntries() {
    return [
      if (_remotePath != '/' && _remotePath != '~')
        RemoteFileEntry(
          name: '..',
          path: _parentPath(_remotePath),
          isDirectory: true,
          sizeBytes: 0,
        ),
      ..._remoteEntries,
    ];
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.surfaceCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _joinRemote(String base, String name) {
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    if (normalized.isEmpty || normalized == '/') return '/$name';
    if (normalized == '~') return '~/$name';
    return '$normalized/$name';
  }

  String _joinRemoteRelative(String base, String relativePath) {
    var path = base;
    final parts = relativePath
        .replaceAll('\\', '/')
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    for (final part in parts) {
      path = _joinRemote(path, part);
    }
    return path;
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
    return parts.isEmpty ? normalized : parts.last;
  }

  String _fileExtension(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) return '';
    return fileName.substring(index + 1).toLowerCase();
  }

  String _renameTargetPath(String oldPath, String newName) {
    final normalized = oldPath
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    final slashIndex = normalized.lastIndexOf('/');
    if (slashIndex < 0) return newName;
    if (slashIndex == 0) return '/$newName';
    final parent = normalized.substring(0, slashIndex);
    return '$parent/$newName';
  }

  String _safeLocalFileName(String name) {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    return safe.trim().isEmpty ? 'remote-file' : safe;
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  String _relativeLocalPath(String childPath, String parentPath) {
    final parent = parentPath
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    final child = childPath.replaceAll('\\', '/');
    if (child == parent) return '';
    if (child.startsWith('$parent/')) {
      return child.substring(parent.length + 1);
    }
    return _basename(childPath);
  }

  String _downloadsPath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return '$home${Platform.pathSeparator}Downloads';
    }
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return '$userProfile${Platform.pathSeparator}Downloads';
    }
    return Directory.current.path;
  }

  String _defaultLocalPath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) return home;
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return userProfile;
    }
    return Directory.current.path;
  }
}

enum _TransferKind { upload, download }

enum _TransferStatus { queued, running, done, failed }

enum _InlineCreateKind { folder, file }

enum _RemoteEntryAction { open, edit, openWith, rename, delete }

class _LocalEditSession {
  const _LocalEditSession({
    required this.remotePath,
    required this.localPath,
    required this.timer,
    required this.originalText,
  });

  final String remotePath;
  final String localPath;
  final Timer timer;
  final String? originalText;
}

class _TextDiff {
  const _TextDiff({
    required this.added,
    required this.removed,
    required this.lines,
  });

  final int added;
  final int removed;
  final List<String> lines;
}

class _TransferJob {
  _TransferJob({
    required this.id,
    required this.kind,
    required this.label,
    required this.remotePath,
    required this.totalBytes,
  });

  final int id;
  final _TransferKind kind;
  final String label;
  final String remotePath;
  int totalBytes;
  int transferredBytes = 0;
  _TransferStatus status = _TransferStatus.queued;
  String? error;

  double get progress {
    if (status == _TransferStatus.done) return 1;
    if (status == _TransferStatus.failed) return 1;
    if (totalBytes <= 0) return status == _TransferStatus.running ? .2 : 0;
    return (transferredBytes / totalBytes).clamp(0, 1).toDouble();
  }

  String get percent => '${(progress * 100).round()}%';
}

class _TransferStats {
  const _TransferStats({required this.completed, required this.failed});

  final int completed;
  final int failed;
}

class _UploadPlan {
  const _UploadPlan({required this.directories, required this.files});

  final List<String> directories;
  final List<_UploadFilePlan> files;
}

class _UploadFilePlan {
  const _UploadFilePlan({
    required this.file,
    required this.remotePath,
    required this.label,
    required this.sizeBytes,
  });

  final File file;
  final String remotePath;
  final String label;
  final int sizeBytes;
}

class _TransferQueuePanel extends StatelessWidget {
  const _TransferQueuePanel({
    required this.jobs,
    required this.onClearFinished,
  });

  final List<_TransferJob> jobs;
  final VoidCallback onClearFinished;

  @override
  Widget build(BuildContext context) {
    final running = jobs.where((job) => job.status == _TransferStatus.running);
    final failed = jobs.where((job) => job.status == _TransferStatus.failed);
    final finished = jobs.where(
      (job) =>
          job.status == _TransferStatus.done ||
          job.status == _TransferStatus.failed,
    );
    final totalBytes = jobs.fold<int>(
      0,
      (total, job) => total + job.totalBytes,
    );
    final doneBytes = jobs.fold<int>(
      0,
      (total, job) => total + job.transferredBytes.clamp(0, job.totalBytes),
    );
    final fallbackProgress = jobs.isEmpty ? 0.0 : finished.length / jobs.length;
    final progress = totalBytes > 0 ? doneBytes / totalBytes : fallbackProgress;
    final clampedProgress = progress.clamp(0, 1).toDouble();
    final maxListHeight = jobs.length <= 2 ? jobs.length * 34.0 : 112.0;
    final headerColor = failed.isNotEmpty
        ? AppColors.danger
        : running.isEmpty
        ? AppColors.green
        : AppColors.cyan;
    final headerIcon = failed.isNotEmpty
        ? Icons.error_outline_rounded
        : running.isEmpty
        ? Icons.task_alt_rounded
        : Icons.sync_alt_rounded;
    final headerText = failed.isNotEmpty
        ? '${failed.length} transfer failed'
        : running.isEmpty
        ? 'Transfer queue'
        : 'Transferring ${running.length} item';
    final headerProgress = failed.isNotEmpty
        ? 'failed'
        : '${(clampedProgress * 100).round()}%';
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(headerIcon, color: headerColor, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headerText,
                  overflow: TextOverflow.ellipsis,
                  style: portixTitle(11),
                ),
              ),
              Text(
                headerProgress,
                style: portixTitle(11).copyWith(color: headerColor),
              ),
              if (finished.isNotEmpty) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Clear finished transfers',
                  onPressed: onClearFinished,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clampedProgress,
              minHeight: 5,
              backgroundColor: AppColors.surfaceCard,
              color: headerColor,
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: maxListHeight.clamp(34.0, 112.0),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 5),
              itemBuilder: (context, index) =>
                  _TransferQueueRow(job: jobs[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferQueueRow extends StatelessWidget {
  const _TransferQueueRow({required this.job});

  final _TransferJob job;

  @override
  Widget build(BuildContext context) {
    final color = switch (job.status) {
      _TransferStatus.done => AppColors.green,
      _TransferStatus.failed => AppColors.danger,
      _TransferStatus.running => AppColors.cyan,
      _TransferStatus.queued => AppColors.muted,
    };
    final icon = job.kind == _TransferKind.upload
        ? Icons.upload_rounded
        : Icons.download_rounded;
    final status = switch (job.status) {
      _TransferStatus.done => 'done',
      _TransferStatus.failed => 'failed',
      _TransferStatus.running => job.percent,
      _TransferStatus.queued => 'queued',
    };
    return Row(
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.label,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(10),
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: job.progress,
                  minHeight: 3,
                  backgroundColor: AppColors.surfaceCard,
                  color: color,
                ),
              ),
              if (job.status == _TransferStatus.failed &&
                  job.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  job.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(9).copyWith(color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(status, style: portixTitle(10).copyWith(color: color)),
      ],
    );
  }
}

class _RemotePanelShell extends StatelessWidget {
  const _RemotePanelShell({required this.panelWidth, required this.child});

  final double panelWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.all(panelWidth < 260 ? 10 : 16),
      child: child,
    );
  }
}

class _CollapsedRemoteRail extends StatelessWidget {
  const _CollapsedRemoteRail({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: IconButton(
            tooltip: 'Show remote folder',
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 32),
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.cyan,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.profile, required this.onClose});
  final SshProfile? profile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_sync_outlined,
            color: AppColors.green,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.address ?? 'root@172.24.82.36:22',
                  overflow: TextOverflow.ellipsis,
                  style: portixTitle(13),
                ),
                Text(
                  'Mounted from active SSH session',
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Close remote folder',
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(
              Icons.keyboard_double_arrow_left_rounded,
              color: AppColors.muted,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteActionBar extends StatelessWidget {
  const _RemoteActionBar({required this.onPressed});

  final void Function(BuildContext context, String action) onPressed;

  @override
  Widget build(BuildContext context) {
    const actions = [
      (Icons.upload_rounded, 'Upload'),
      (Icons.download_rounded, 'Download'),
      (Icons.create_new_folder_outlined, 'New folder'),
      (Icons.note_add_outlined, 'New file'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = ((constraints.maxWidth - 21) / 4).clamp(34.0, 80.0);
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final action in actions)
              SizedBox(
                width: itemWidth,
                child: _FolderAction(
                  icon: action.$1,
                  tooltip: action.$2,
                  onPressed: onPressed,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PathCrumb extends StatelessWidget {
  const _PathCrumb({required this.path, required this.onSubmit});
  final String path;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: path);
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, color: AppColors.muted, size: 16),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmit,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Open path',
            onPressed: () => onSubmit(controller.text),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            icon: const Icon(
              Icons.keyboard_return_rounded,
              color: AppColors.muted,
              size: 17,
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderAction extends StatelessWidget {
  const _FolderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final void Function(BuildContext context, String action) onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 34,
        child: OutlinedButton(
          onPressed: () => onPressed(context, tooltip),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: AppColors.surfaceCard.withValues(alpha: .55),
          ),
          child: Icon(icon, size: 16, color: AppColors.text),
        ),
      ),
    );
  }
}

class _RemoteItem extends StatelessWidget {
  const _RemoteItem({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onAction,
  });

  final RemoteFileEntry item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<_RemoteEntryAction> onAction;

  @override
  Widget build(BuildContext context) {
    final icon = item.isDirectory
        ? Icons.folder_outlined
        : Icons.insert_drive_file_outlined;
    final meta = item.name == '..'
        ? 'parent directory'
        : item.isDirectory
        ? 'folder'
        : '${_formatFileSize(item.sizeBytes)} · ${_formatModified(item.modifiedUnixSeconds)}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF143B63) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: item.isDirectory ? AppColors.amber : AppColors.muted,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      overflow: TextOverflow.ellipsis,
                      style: portixTitle(12),
                    ),
                    Text(
                      meta,
                      overflow: TextOverflow.ellipsis,
                      style: portixMuted(10),
                    ),
                  ],
                ),
              ),
              if (item.name != '..') ...[
                const SizedBox(width: 6),
                _RemoteItemMenu(
                  isDirectory: item.isDirectory,
                  fileName: item.name,
                  onSelected: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteItemMenu extends StatelessWidget {
  const _RemoteItemMenu({
    required this.isDirectory,
    required this.fileName,
    required this.onSelected,
  });

  final bool isDirectory;
  final String fileName;
  final ValueChanged<_RemoteEntryAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_RemoteEntryAction>(
      tooltip: 'File actions',
      onSelected: onSelected,
      color: AppColors.surfaceCard,
      constraints: const BoxConstraints(minWidth: 156, maxWidth: 190),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        PopupMenuItem(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          value: _RemoteEntryAction.open,
          child: _RemoteMenuItem(
            icon: _openIcon(isDirectory, fileName),
            label: _openLabel(isDirectory, fileName),
          ),
        ),
        if (!isDirectory)
          const PopupMenuItem(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: 10),
            value: _RemoteEntryAction.edit,
            child: _RemoteMenuItem(icon: Icons.edit_rounded, label: 'Edit'),
          ),
        if (!isDirectory)
          const PopupMenuItem(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: 10),
            value: _RemoteEntryAction.openWith,
            child: _RemoteMenuItem(
              icon: Icons.apps_rounded,
              label: 'Open with...',
            ),
          ),
        const PopupMenuItem(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: 10),
          value: _RemoteEntryAction.rename,
          child: _RemoteMenuItem(
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'Rename',
          ),
        ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: 10),
          value: _RemoteEntryAction.delete,
          child: _RemoteMenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            danger: true,
          ),
        ),
      ],
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 17,
          color: AppColors.muted,
        ),
      ),
    );
  }

  static String _extension(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) return '';
    return fileName.substring(index + 1).toLowerCase();
  }

  static String _openLabel(bool isDirectory, String fileName) {
    if (isDirectory) return 'Open folder';
    final extension = _extension(fileName);
    if ((extension.isEmpty && fileName.startsWith('.')) ||
        _RemoteFolderPageState._codeFileExtensions.contains(extension)) {
      return 'Open in editor';
    }
    if (const {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'svg',
    }.contains(extension)) {
      return 'View image';
    }
    if (const {'pdf'}.contains(extension)) return 'Open PDF';
    if (const {
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
    }.contains(extension)) {
      return 'Open document';
    }
    return 'Open file';
  }

  static IconData _openIcon(bool isDirectory, String fileName) {
    if (isDirectory) return Icons.folder_open_rounded;
    final extension = _extension(fileName);
    if ((extension.isEmpty && fileName.startsWith('.')) ||
        _RemoteFolderPageState._codeFileExtensions.contains(extension)) {
      return Icons.code_rounded;
    }
    if (const {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'svg',
    }.contains(extension)) {
      return Icons.image_outlined;
    }
    if (const {'pdf'}.contains(extension)) return Icons.picture_as_pdf_outlined;
    if (const {
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
    }.contains(extension)) {
      return Icons.description_outlined;
    }
    return Icons.open_in_new_rounded;
  }
}

class _RemoteMenuItem extends StatelessWidget {
  const _RemoteMenuItem({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : AppColors.text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: portixTitle(11).copyWith(color: color)),
      ],
    );
  }
}

class _OpenWithEditorSheet extends StatelessWidget {
  const _OpenWithEditorSheet({required this.editors});

  final List<LocalEditor> editors;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.apps_rounded, color: AppColors.cyan, size: 18),
                const SizedBox(width: 10),
                Text('Open with', style: portixTitle(15)),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: editors.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final editor = editors[index];
                  final isDefault =
                      editor.command == 'open' && editor.arguments.isEmpty;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    tileColor: AppColors.surfaceCard.withValues(alpha: .5),
                    leading: Icon(
                      editor.icon ??
                          (isDefault
                              ? Icons.open_in_new_rounded
                              : Icons.code_rounded),
                      color: isDefault ? AppColors.amber : AppColors.cyan,
                      size: 18,
                    ),
                    title: Text(editor.name, style: portixTitle(12)),
                    subtitle: Text(
                      editor.arguments.isEmpty
                          ? editor.command
                          : '${editor.command} ${editor.arguments.join(' ')}',
                      style: portixMuted(10),
                    ),
                    onTap: () => Navigator.of(context).pop(editor),
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

class _RewriteRemoteDialog extends StatelessWidget {
  const _RewriteRemoteDialog({required this.fileName, required this.diff});

  final String fileName;
  final _TextDiff diff;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.sync_alt_rounded,
                    color: AppColors.cyan,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Rewrite remote file?', style: portixTitle(16)),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fileName,
                overflow: TextOverflow.ellipsis,
                style: portixMuted(12),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _DiffBadge(label: '+${diff.added}', color: AppColors.green),
                  const SizedBox(width: 8),
                  _DiffBadge(
                    label: '-${diff.removed}',
                    color: AppColors.danger,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.terminal,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: diff.lines.length,
                    itemBuilder: (context, index) {
                      final line = diff.lines[index];
                      final isAdd = line.startsWith('+ ');
                      final isRemove = line.startsWith('- ');
                      final color = isAdd
                          ? AppColors.green
                          : isRemove
                          ? AppColors.danger
                          : AppColors.muted;
                      return Text(
                        line,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          height: 1.35,
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Cancel', style: portixTitle(12)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.upload_file_rounded, size: 16),
                    label: const Text('Rewrite remote'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffBadge extends StatelessWidget {
  const _DiffBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .8)),
      ),
      child: Text(label, style: portixTitle(11).copyWith(color: color)),
    );
  }
}

class _InlineRenameItem extends StatelessWidget {
  const _InlineRenameItem({
    required this.entry,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
  });

  final RemoteFileEntry entry;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isFolder = entry.isDirectory;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF143B63),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryBlue),
      ),
      child: Row(
        children: [
          Icon(
            isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            color: isFolder ? AppColors.amber : AppColors.muted,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  onCancel();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                onSubmitted: (_) => unawaited(onSubmit()),
                style: portixTitle(12),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  hintText: isFolder ? 'Rename folder' : 'Rename file',
                  hintStyle: portixMuted(12),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Cancel rename',
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.muted,
              size: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineCreateItem extends StatelessWidget {
  const _InlineCreateItem({
    required this.kind,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
  });

  final _InlineCreateKind kind;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isFolder = kind == _InlineCreateKind.folder;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryBlue),
      ),
      child: Row(
        children: [
          Icon(
            isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            color: isFolder ? AppColors.amber : AppColors.muted,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  onCancel();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                onSubmitted: (_) => unawaited(onSubmit()),
                style: portixTitle(12),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  hintText: isFolder ? 'New folder name' : 'New file name',
                  hintStyle: portixMuted(12),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Cancel',
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.muted,
              size: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteStatus extends StatelessWidget {
  const _RemoteStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: AppPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, color: AppColors.muted, size: 24),
              const SizedBox(height: 10),
              Text(title, textAlign: TextAlign.center, style: portixTitle(13)),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: portixMuted(11),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 30,
                  child: OutlinedButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  final value = size >= 10 || unitIndex == 0
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(1);
  return '$value ${units[unitIndex]}';
}

String _formatModified(int unixSeconds) {
  if (unixSeconds <= 0) return 'modified unknown';
  final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}-$month-$day $hour:$minute';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
