import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

part '../widget/remote/remote_folder_parts.dart';

class RemoteFolderPage extends StatefulWidget {
  const RemoteFolderPage({super.key});

  @override
  State<RemoteFolderPage> createState() => _RemoteFolderPageState();
}

class _RemoteFolderPageState extends State<RemoteFolderPage> {
  late final ConnectionManager _connectionManager = sl<ConnectionManager>();
  late final LocalEditorService _localEditorService = LocalEditorService();
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
            sessionState.preferExistingSession ||
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
          _remotePath = _terminalFolderPath(profile);
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
        if (profile == null) {
          _returnToProfilesWhenInactive(state);
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final showRemotePanel =
                _remotePanelVisible && constraints.maxWidth >= 420;
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
                ] else if (constraints.maxWidth >= 260)
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
                          onSessionChanged: (_) {},
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
                      if (_transferJobs.isNotEmpty)
                        Positioned(
                          right: 18,
                          bottom: 18,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 280,
                              maxWidth: 380,
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

  bool get _canShowRemoteActions =>
      _activeSessionId != null && _remoteFolderMounted && _remoteError == null;

  void _returnToProfilesWhenInactive(SshWorkspaceState state) {
    if (state.activeView != WorkspaceView.remoteFolder) return;
    // Don't auto-redirect if a connection is in progress.
    final sessionState = context.read<SshSessionBloc>().state;
    if (sessionState.targetProfileId != null) return;
    // Don't redirect if there are any sessions (even connecting ones).
    if (_connectionManager.sessions.isNotEmpty) return;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || sessionId == _activeSessionId) return;
      setState(() {
        _activeSessionId = sessionId;
        _clearRemoteSelection();
        _clearInlineRename();
      });
      if (sessionId != null) {
        final state = context.read<SshWorkspaceBloc>().state;
        final profile = _activeProfile(state);
        final path = _terminalFolderPath(profile);
        // Only reload if path actually changed. Don't reload when switching
        // between panes in same workspace/profile.
        if (path != _remotePath) {
          setState(() {
            _remotePath = path;
            _remoteEntries = const [];
            _remoteError = null;
            _remoteFolderMounted = false;
            _autoLoadedSessionId = null;
            _autoLoadedPath = null;
            _remoteLoadToken += 1;
          });
          _maybeAutoLoadRemoteFolder(sessionId, path);
        } else if (!_remoteFolderMounted && _remoteEntries.isEmpty) {
          _maybeAutoLoadRemoteFolder(sessionId, path);
        }
      }
    });
  }

  void _handleConnectionManagerChanged() {
    final sessionId = _activeSessionId;
    if (!mounted || sessionId == null) return;
    // Defer to avoid setState during build when ConnectionManager notifies
    // synchronously from within a widget update cycle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeSessionId != sessionId) return;
      if (!_isSessionConnected(sessionId)) {
        _markRemoteDisconnected();
        return;
      }
      _maybeAutoLoadRemoteFolder(sessionId, _remotePath);
    });
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
    final result = await _connectionManager.executeRemoteCommand(
      sessionId,
      'mv -- ${_shellQuote(entry.path)} ${_shellQuote(targetPath)}',
      action: 'rename remote path',
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
    final tempRoot = await LocalEditorService.createOpenTempDir();
    final localFileName = LocalEditorService.buildRemoteTempFileName(
      _safeLocalFileName(entry.name),
      remotePath: entry.path,
    );
    final localPath =
        '${tempRoot.path}${Platform.pathSeparator}${localFileName}';
    try {
      final ok = await _downloadRemoteFile(
        sessionId,
        entry.path,
        localPath,
        sizeBytes: entry.sizeBytes,
      );
      if (!ok) return;
      final originalText = await _readFileTextIfPossible(localPath);

      // For non-code files (documents, images, etc.), always use system default
      // unless an explicit editor override is provided or code editor requested.
      final isCodeFile = _shouldOpenInCodeEditor(entry.name);
      if (!isCodeFile && !preferCodeEditor && editorOverride == null) {
        await _localEditorService.openWithSystemDefault(localPath);
        return;
      }

      final editors = await _localEditorService.detectEditors();
      final useCodeEditor = isCodeFile && preferCodeEditor;
      final editor =
          editorOverride ??
          _preferredLocalEditor(editors, preferCodeEditor: useCodeEditor);
      if (editor == null) {
        // No code editor detected — fall back to system default handler.
        await _localEditorService.openWithSystemDefault(localPath);
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

    final extension = _fileExtension(entry.name);
    final isCodeFile = _shouldOpenInCodeEditor(entry.name);

    // For non-code files, show extension-specific apps (Word, VLC, etc.)
    // For code files, show code editors + system default.
    final List<LocalEditor> editors;
    if (isCodeFile) {
      final codeEditors = await _localEditorService.detectEditors();
      editors = [
        ...codeEditors,
        // Always offer system default for code files too.
        if (!codeEditors.any(
          (e) =>
              e.command == 'xdg-open' ||
              e.command == 'open' ||
              e.command == '_system_default_',
        ))
          LocalEditor(
            Platform.isMacOS
                ? 'Default macOS app'
                : Platform.isWindows
                ? 'Default Windows app'
                : 'System default',
            '_system_default_',
            icon: Icons.open_in_new_rounded,
          ),
      ];
    } else {
      editors = await _localEditorService.detectAppsForExtension(extension);
    }

    if (!context.mounted) return;
    if (editors.isEmpty) {
      // No specific apps found — open with system default directly.
      await _openWithSystemDefault(entry);
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

    // Handle the "_system_default_" special command.
    if (editor.command == '_system_default_') {
      await _openWithSystemDefault(entry);
      return;
    }

    await _openRemoteFileLocally(
      entry,
      editorOverride: editor,
      watchForRewrite: isCodeFile,
    );
  }

  Future<void> _openWithSystemDefault(RemoteFileEntry entry) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    final tempRoot = await LocalEditorService.createOpenTempDir();
    final localFileName = LocalEditorService.buildRemoteTempFileName(
      _safeLocalFileName(entry.name),
      remotePath: entry.path,
    );
    final localPath =
        '${tempRoot.path}${Platform.pathSeparator}${localFileName}';
    final ok = await _downloadRemoteFile(
      sessionId,
      entry.path,
      localPath,
      sizeBytes: entry.sizeBytes,
    );
    if (!ok) return;
    await _localEditorService.openWithSystemDefault(localPath);
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
    if (Platform.isMacOS || Platform.isWindows) {
      for (final editor in editors) {
        if (_isDefaultSystemEditor(editor)) return editor;
      }
    }
    return editors.first;
  }

  bool _isDefaultSystemEditor(LocalEditor editor) {
    if (Platform.isWindows) {
      return editor.command == 'cmd.exe' && editor.arguments.contains('start');
    }
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

    // Build unified diff with context lines around changes.
    const contextSize = 2;
    final changedIndices = <int>{};
    for (var index = 0; index < maxLength; index += 1) {
      final oldLine = index < beforeLines.length ? beforeLines[index] : null;
      final newLine = index < afterLines.length ? afterLines[index] : null;
      if (oldLine != newLine) changedIndices.add(index);
    }

    final visibleIndices = <int>{};
    for (final changed in changedIndices) {
      for (var offset = -contextSize; offset <= contextSize; offset += 1) {
        final idx = changed + offset;
        if (idx >= 0 && idx < maxLength) visibleIndices.add(idx);
      }
    }

    final sorted = visibleIndices.toList()..sort();
    var lastIndex = -2;
    for (final index in sorted) {
      if (preview.length >= 120) break;
      if (index > lastIndex + 1 && preview.isNotEmpty) {
        preview.add('  ···');
      }
      lastIndex = index;
      final oldLine = index < beforeLines.length ? beforeLines[index] : null;
      final newLine = index < afterLines.length ? afterLines[index] : null;
      if (oldLine == newLine) {
        // Context (unchanged) line.
        preview.add('  ${oldLine ?? ''}');
      } else {
        if (oldLine != null) {
          removed += 1;
          preview.add('- $oldLine');
        }
        if (newLine != null) {
          added += 1;
          preview.add('+ $newLine');
        }
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
    final confirmed = await _confirmDeleteRemoteEntry(context, entry);
    if (confirmed != true) return;
    setState(() => _isLoadingRemote = true);
    final result = await _connectionManager.executeRemoteCommand(
      sessionId,
      'rm -rf -- ${_shellQuote(path)}',
      action: 'delete remote path',
    );
    result.fold((failure) => _showMessage(context, _failureDetails(failure)), (
      _,
    ) {
      _selectedRemotePaths.remove(path);
    });
    await _loadRemoteDirectory(_remotePath);
    if (mounted) setState(() => _isLoadingRemote = false);
  }

  Future<bool?> _confirmDeleteRemoteEntry(
    BuildContext context,
    RemoteFileEntry entry,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete ${entry.isDirectory ? 'folder' : 'file'}?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, style: portixTitle(15)),
              const SizedBox(height: 8),
              Text(
                'This will delete the remote item permanently.',
                style: portixMuted(12),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  entry.path,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
          content: Text(
            message,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFF1A2E42),
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
