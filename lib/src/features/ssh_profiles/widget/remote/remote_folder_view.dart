import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/widgets/index.dart';

import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/ssh/index.dart'
    hide ConnectionStatus;
import '../../bloc/index.dart';
import 'terminal_panel.dart';

class RemoteFolderView extends StatefulWidget {
  const RemoteFolderView({super.key});

  @override
  State<RemoteFolderView> createState() => _RemoteFolderViewState();
}

class _RemoteFolderViewState extends State<RemoteFolderView> {
  late final ConnectionManager _connectionManager = sl<ConnectionManager>();
  bool _hasTerminalSession = true;
  String? _profileId;
  String? _activeSessionId;
  String _remotePath = '~';
  bool _isLoadingRemote = false;
  bool _remoteFolderMounted = false;
  String? _remoteError;
  List<RemoteFileEntry> _remoteEntries = const [];
  RemoteFileEntry? _selectedEntry;
  double _remotePanelWidth = 320;
  bool _remotePanelVisible = true;
  String? _autoLoadedSessionId;
  String? _autoLoadedPath;
  int _remoteLoadToken = 0;

  static const double _minRemotePanelWidth = 220;
  static const double _maxRemotePanelWidth = 520;
  static const double _collapseThreshold = 140;

  @override
  void initState() {
    super.initState();
    _connectionManager.addListener(_handleConnectionManagerChanged);
  }

  @override
  void dispose() {
    _connectionManager.removeListener(_handleConnectionManagerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshWorkspaceBloc, SshWorkspaceState>(
      builder: (context, state) {
        final isVisible = state.activeView == WorkspaceView.remoteFolder;
        final activeProfile = _activeProfile(state);
        final profile =
            activeProfile ??
            state.terminalProfile ??
            (isVisible ? state.selectedProfile : null);
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
          _selectedEntry = null;
          if (profile == null) {
            _activeSessionId = null;
          }
        }
        if (profile == null || !_hasTerminalSession) {
          return _NoRemoteSession(profile: profile);
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
                  child: TerminalPanel(
                    profile: profile,
                    profiles: state.profiles,
                    onSessionChanged: (active) {
                      if (mounted) setState(() => _hasTerminalSession = active);
                    },
                    onActiveSessionChanged: _handleActiveSessionChanged,
                    onLastSessionClosed: () {
                      context.read<SshWorkspaceBloc>()
                        ..add(const ProfileSelectionCleared())
                        ..add(const NavigationChanged(WorkspaceView.gallery));
                    },
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

  void _handleActiveSessionChanged(String? sessionId) {
    if (!mounted) return;
    if (sessionId == _activeSessionId) return;
    setState(() {
      _activeSessionId = sessionId;
      _hasTerminalSession = sessionId != null;
      _selectedEntry = null;
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
    if (!_isSessionConnected(sessionId)) return;
    _maybeAutoLoadRemoteFolder(sessionId, _remotePath);
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
          session.status == ConnectionStatus.connected,
    );
  }

  Future<void> _loadRemoteDirectory(String path) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    final token = ++_remoteLoadToken;
    setState(() {
      _isLoadingRemote = true;
      _remoteError = null;
    });

    final resolvedResult = await _connectionManager.resolveRemoteDirectory(
      sessionId,
      path,
    );
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
          _selectedEntry = null;
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

  void _selectRemoteEntry(RemoteFileEntry entry) {
    if (entry.name == '..') {
      _openRemoteEntry(entry);
      return;
    }
    setState(() => _selectedEntry = entry);
  }

  void _openRemoteEntry(RemoteFileEntry entry) {
    if (!entry.isDirectory) return;
    unawaited(_loadRemoteDirectory(entry.path));
  }

  Future<void> _handleFolderAction(BuildContext context, String action) async {
    switch (action) {
      case 'Upload':
        await _uploadLocalPath(context);
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
    final entry = _selectedEntry;
    if (sessionId == null) return;
    if (entry == null || entry.name == '..') {
      _showMessage(context, 'Select a remote file or folder first.');
      return;
    }
    final target = await _promptText(
      context,
      title: 'Download to local path',
      label: 'Local destination folder',
      initialValue: _downloadsPath(),
    );
    if (target == null || target.trim().isEmpty) return;
    setState(() => _isLoadingRemote = true);
    try {
      final localRoot = Directory(target.trim());
      await localRoot.create(recursive: true);
      if (entry.isDirectory) {
        await _downloadRemoteDirectory(
          sessionId,
          entry.path,
          '${localRoot.path}${Platform.pathSeparator}${entry.name}',
        );
      } else {
        await _downloadRemoteFile(
          sessionId,
          entry.path,
          '${localRoot.path}${Platform.pathSeparator}${entry.name}',
        );
      }
      if (mounted) _showMessage(context, 'Downloaded ${entry.name}.');
    } catch (error) {
      if (mounted) _showMessage(context, 'Download failed: $error');
    } finally {
      if (mounted) setState(() => _isLoadingRemote = false);
    }
  }

  Future<void> _downloadRemoteFile(
    String sessionId,
    String remotePath,
    String localPath,
  ) async {
    final result = await _connectionManager.readRemoteFileBytes(
      sessionId,
      remotePath,
    );
    final bytes = result.fold<List<int>>((failure) {
      throw StateError(failure.message);
    }, (bytes) => bytes);
    await File(localPath).create(recursive: true);
    await File(localPath).writeAsBytes(bytes);
  }

  Future<void> _downloadRemoteDirectory(
    String sessionId,
    String remotePath,
    String localPath,
  ) async {
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
        await _downloadRemoteDirectory(sessionId, entry.path, childPath);
      } else {
        await _downloadRemoteFile(sessionId, entry.path, childPath);
      }
    }
  }

  Future<void> _uploadLocalPath(BuildContext context) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    final localPath = await _promptText(
      context,
      title: 'Upload from local',
      label: 'Local file or folder path',
      initialValue: _defaultLocalPath(),
    );
    if (localPath == null || localPath.trim().isEmpty) return;
    final entityType = FileSystemEntity.typeSync(localPath.trim());
    if (entityType == FileSystemEntityType.notFound) {
      if (mounted) _showMessage(context, 'Local path not found.');
      return;
    }
    setState(() => _isLoadingRemote = true);
    try {
      if (entityType == FileSystemEntityType.directory) {
        await _uploadDirectory(
          sessionId,
          Directory(localPath.trim()),
          _remotePath,
        );
      } else {
        await _uploadFile(sessionId, File(localPath.trim()), _remotePath);
      }
      await _loadRemoteDirectory(_remotePath);
      if (mounted) _showMessage(context, 'Upload complete.');
    } catch (error) {
      if (mounted) _showMessage(context, 'Upload failed: $error');
    } finally {
      if (mounted) setState(() => _isLoadingRemote = false);
    }
  }

  Future<void> _uploadFile(
    String sessionId,
    File file,
    String remoteDirectory,
  ) async {
    final remotePath = _joinRemote(remoteDirectory, _basename(file.path));
    final result = await _connectionManager.uploadRemoteFile(
      sessionId,
      remotePath,
      await file.readAsBytes(),
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
  }

  Future<void> _uploadDirectory(
    String sessionId,
    Directory directory,
    String remoteDirectory,
  ) async {
    final remoteRoot = _joinRemote(remoteDirectory, _basename(directory.path));
    final createResult = await _connectionManager.createRemoteDirectory(
      sessionId,
      remoteRoot,
    );
    createResult.fold((failure) => throw StateError(failure.message), (_) {});
    await for (final entity in directory.list()) {
      if (entity is Directory) {
        await _uploadDirectory(sessionId, entity, remoteRoot);
      } else if (entity is File) {
        await _uploadFile(sessionId, entity, remoteRoot);
      }
    }
  }

  Future<void> _createRemoteFolder(BuildContext context) async {
    await _createRemoteEntry(
      context,
      title: 'Create remote folder',
      label: 'Folder name',
      create: (sessionId, path) =>
          _connectionManager.createRemoteDirectory(sessionId, path),
    );
  }

  Future<void> _createRemoteFile(BuildContext context) async {
    await _createRemoteEntry(
      context,
      title: 'Create remote file',
      label: 'File name',
      create: (sessionId, path) =>
          _connectionManager.createRemoteFile(sessionId, path),
    );
  }

  Future<void> _createRemoteEntry(
    BuildContext context, {
    required String title,
    required String label,
    required Future<Result<void>> Function(String sessionId, String path)
    create,
  }) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    final name = await _promptText(context, title: title, label: label);
    if (name == null || name.trim().isEmpty) return;
    final path = _joinRemote(_remotePath, name.trim());
    final result = await create(sessionId, path);
    result.fold(
      (failure) {
        _showMessage(context, failure.message);
      },
      (_) {
        _showMessage(context, '$name created.');
        unawaited(_loadRemoteDirectory(_remotePath));
      },
    );
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
        icon: Icons.error_outline_rounded,
        title: 'Remote folder unavailable',
        message: _remoteError!,
        actionLabel: 'Retry',
        onAction: () => _loadRemoteDirectory(_remotePath),
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
    final entries = [
      if (_remotePath != '/' && _remotePath != '~')
        RemoteFileEntry(
          name: '..',
          path: _parentPath(_remotePath),
          isDirectory: true,
          sizeBytes: 0,
        ),
      ..._remoteEntries,
    ];
    if (entries.isEmpty) {
      return const _RemoteStatus(
        icon: Icons.folder_open_rounded,
        title: 'Remote folder is empty',
        message: 'Create or upload a file to start filling this path.',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemBuilder: (context, index) => _RemoteItem(
        item: entries[index],
        selected: entries[index].path == _selectedEntry?.path,
        onTap: () => _selectRemoteEntry(entries[index]),
        onDoubleTap: () => _openRemoteEntry(entries[index]),
      ),
    );
  }

  Future<String?> _promptText(
    BuildContext context, {
    required String title,
    required String label,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
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

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
    return parts.isEmpty ? normalized : parts.last;
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

class _NoRemoteSession extends StatelessWidget {
  const _NoRemoteSession({required this.profile});
  final SshProfile? profile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AppPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.folder_off_outlined,
                color: AppColors.muted,
                size: 38,
              ),
              const SizedBox(height: 10),
              Text('No active SSH session', style: portixTitle(16)),
              const SizedBox(height: 8),
              Text(
                profile == null
                    ? 'Select a profile and open SSH before browsing remote files.'
                    : 'Open SSH for ${profile!.name} to mount the remote folder.',
                textAlign: TextAlign.center,
                style: portixMuted(13),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  onPressed: () => context.read<SshWorkspaceBloc>().add(
                    const NavigationChanged(WorkspaceView.gallery),
                  ),
                  icon: const Icon(Icons.list_rounded, size: 16),
                  label: const Text('Back to SSH profiles'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surfaceCard.withValues(
                      alpha: .55,
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
  });

  final RemoteFileEntry item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

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
            ],
          ),
        ),
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
