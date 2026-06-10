import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart'
    as manager_profile;
import 'package:portix/src/data/services/sftp/index.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;

class SftpWorkspaceController extends ChangeNotifier {
  SftpWorkspaceController({
    required ConnectionManager connectionManager,
    LocalFileBrowser? localFileBrowser,
    LocalEditorService? localEditorService,
  }) : _connectionManager = connectionManager,
       _localFileBrowser = localFileBrowser ?? LocalFileBrowser(),
       _localEditorService = localEditorService ?? LocalEditorService() {
    _localPath = _localFileBrowser.defaultPath();
    unawaited(loadLocalDirectory(_localPath));
    _connectionManager.addListener(_handleConnectionManagerChanged);
  }

  final ConnectionManager _connectionManager;
  final LocalFileBrowser _localFileBrowser;
  final LocalEditorService _localEditorService;

  final List<SftpTransferJob> _transferJobs = [];
  int _transferSerial = 0;
  Timer? _clearTransferTimer;
  late String _localPath;
  List<SftpFileEntry> _localRows = const [];
  String _localSearchQuery = '';
  String _remotePath = '~';
  List<SftpFileEntry> _remoteRows = const [];
  List<SftpFileEntry> _remoteSearchRows = const [];
  final Map<String, String> _remoteChmodModes = {};
  String _remoteSearchQuery = '';
  String _remoteSearchBase = '~';
  String? _localError;
  String? _remoteError;
  String? _remoteSearchError;
  String _remoteStatus = 'idle';
  bool _loadingLocal = false;
  bool _loadingRemote = false;
  bool _searchingRemote = false;
  String? _remoteSessionId;
  String? _remoteProfileId;
  int _remoteLoadToken = 0;
  int _remoteSearchToken = 0;

  List<SftpTransferJob> get transferJobs => List.unmodifiable(_transferJobs);
  String get localPath => _localPath;
  String get remotePath => _remotePath;
  List<SftpFileEntry> get localRows => _localRows;
  List<SftpFileEntry> get localVisibleRows => localSearchActive
      ? _localRows
            .where((row) => _matchesLocalSearch(row, _localSearchQuery))
            .toList(growable: false)
      : _localRows;
  List<SftpFileEntry> get remoteRows => _remoteRows;
  List<SftpFileEntry> get remoteVisibleRows =>
      remoteSearchActive ? _remoteSearchRows : _remoteRows;
  String get remoteSearchQuery => _remoteSearchQuery;
  String get localSearchQuery => _localSearchQuery;
  String get remoteSearchBase => _remoteSearchBase;
  String? get localError => _localError;
  String? get remoteError => _remoteError;
  String? get remoteSearchError => _remoteSearchError;
  bool get loadingLocal => _loadingLocal;
  bool get loadingRemote => _loadingRemote;
  bool get searchingRemote => _searchingRemote;
  bool get hasRemoteSession => _remoteSessionId != null;
  bool get isRemoteDisconnected {
    if (_remoteSessionId == null) return false;
    final session = _connectionManager.sessions
        .where((s) => s.id == _remoteSessionId)
        .firstOrNull;
    if (session == null) return true;
    return session.status == ConnectionStatus.disconnected ||
        session.status == ConnectionStatus.error;
  }

  bool get isRemoteConnected {
    if (_remoteSessionId == null) return false;
    final session = _connectionManager.sessions
        .where((s) => s.id == _remoteSessionId)
        .firstOrNull;
    return session?.status == ConnectionStatus.connected;
  }
  bool get localSearchActive => _localSearchQuery.trim().isNotEmpty;
  bool get remoteSearchActive => _remoteSearchQuery.trim().isNotEmpty;
  int get localItemCount => _localRows.where((row) => row.name != '..').length;
  int get localVisibleItemCount =>
      localVisibleRows.where((row) => row.name != '..').length;
  int get remoteItemCount =>
      _remoteRows.where((row) => row.name != '..').length;
  int get remoteVisibleItemCount =>
      remoteVisibleRows.where((row) => row.name != '..').length;
  String get remoteStatusTitle {
    if (_remoteError != null) return 'Remote unavailable';
    if (_remoteStatus == 'connecting') return 'Connecting to SFTP';
    if (_remoteStatus == 'resolving') return 'Resolving remote path';
    if (_remoteStatus == 'listing') return 'Loading remote folder';
    if (_remoteSessionId != null) return 'Remote connected';
    return 'No remote session';
  }

  String get remoteStatusMessage {
    if (_remoteError != null) return _remoteError!;
    if (_remoteStatus == 'connecting') {
      return 'Opening SSH/SFTP channel through the Rust backend...';
    }
    if (_remoteStatus == 'resolving') return 'Checking path $_remotePath';
    if (_remoteStatus == 'listing') return 'Reading files from $_remotePath';
    if (_remoteSessionId != null) return 'Connected to $_remotePath';
    return 'Choose a profile to start SFTP.';
  }

  String get defaultDownloadsPath => _localFileBrowser.defaultDownloadsPath();

  Future<void> loadLocalDirectory(String path) async {
    _loadingLocal = true;
    _localError = null;
    notifyListeners();

    try {
      final result = await _localFileBrowser.readDirectory(path);
      _localPath = result.path;
      _localRows = result.entries;
    } catch (error) {
      _localError = '$error';
      _localRows = const [];
    } finally {
      _loadingLocal = false;
      notifyListeners();
    }
  }

  Future<void> attachRemoteProfile(
    domain.SshProfile? profile,
    String initialPath,
  ) async {
    if (profile == null) {
      await clearRemoteSession();
      return;
    }
    final normalizedPath = initialPath.trim().isEmpty
        ? '~'
        : initialPath.trim();
    if (_remoteProfileId == profile.id && _remoteSessionId != null) {
      if (_remoteRows.isEmpty && !_loadingRemote) {
        await loadRemoteDirectory(_remotePath);
      } else if (_remotePath != normalizedPath && _remoteRows.isEmpty) {
        await loadRemoteDirectory(normalizedPath);
      }
      return;
    }
    await clearRemoteSession();
    _remoteProfileId = profile.id;
    _remotePath = normalizedPath;
    _loadingRemote = true;
    _remoteStatus = 'connecting';
    _remoteError = null;
    notifyListeners();

    final result = await _connectionManager.connectSftp(
      _toManagerProfile(profile),
    );
    final failure = result.fold<String?>(
      (failure) => failure.message,
      (_) => null,
    );
    if (failure != null) {
      _loadingRemote = false;
      _remoteStatus = 'failed';
      _remoteError = failure;
      notifyListeners();
      return;
    }

    final sessions = _connectionManager.sessions
        .where(
          (session) =>
              session.kind == SessionKind.sftp &&
              session.profileId == profile.id,
        )
        .toList(growable: false);
    if (sessions.isEmpty) {
      _loadingRemote = false;
      _remoteStatus = 'failed';
      _remoteError = 'SFTP session was not created by the backend.';
      notifyListeners();
      return;
    }
    final session = sessions.last;
    _remoteSessionId = session.id;
    await loadRemoteDirectory(_remotePath);
  }

  Future<void> clearRemoteSession() async {
    final sessionId = _remoteSessionId;
    _remoteSessionId = null;
    _remoteProfileId = null;
    _remoteRows = const [];
    _clearRemoteSearchState();
    _remoteError = null;
    _loadingRemote = false;
    _remoteStatus = 'idle';
    _remoteLoadToken += 1;
    _remoteSearchToken += 1;
    notifyListeners();
    if (sessionId != null) {
      await _connectionManager.closeSession(sessionId);
    }
  }

  Future<void> loadRemoteDirectory(String path) async {
    final sessionId = _remoteSessionId;
    if (sessionId == null) return;
    final token = ++_remoteLoadToken;
    _remoteSearchToken += 1;
    _clearRemoteSearchState();
    _loadingRemote = true;
    _remoteStatus = 'resolving';
    _remoteError = null;
    notifyListeners();

    final resolvedResult = await _connectionManager.resolveRemoteDirectory(
      sessionId,
      path.trim().isEmpty ? _remotePath : path.trim(),
    );
    final resolvedPath = resolvedResult.fold<String?>((failure) {
      if (!_isCurrentRemoteRequest(token)) return null;
      _loadingRemote = false;
      _remoteStatus = 'failed';
      _remoteError = failure.message;
      notifyListeners();
      return null;
    }, (value) => value);
    if (resolvedPath == null) return;

    _remoteStatus = 'listing';
    notifyListeners();
    final entriesResult = await _connectionManager.listRemoteDirectory(
      sessionId,
      resolvedPath,
    );
    entriesResult.fold(
      (failure) {
        if (!_isCurrentRemoteRequest(token)) return;
        _loadingRemote = false;
        _remoteStatus = 'failed';
        _remoteError = failure.message;
        notifyListeners();
      },
      (entries) {
        if (!_isCurrentRemoteRequest(token)) return;
        _remotePath = resolvedPath;
        _remoteRows = _mapRemoteRows(resolvedPath, entries);
        _loadingRemote = false;
        _remoteStatus = 'connected';
        _remoteError = null;
        notifyListeners();
      },
    );
  }

  /// Reload the current remote directory without showing loading state.
  /// Keeps existing rows visible until new data arrives.
  Future<void> _refreshCurrentRemoteDirectory() async {
    final sessionId = _remoteSessionId;
    if (sessionId == null) return;
    final token = ++_remoteLoadToken;
    final path = _remotePath;

    final entriesResult = await _connectionManager.listRemoteDirectory(
      sessionId,
      path,
    );
    entriesResult.fold(
      (failure) {
        if (!_isCurrentRemoteRequest(token)) return;
        _remoteError = failure.message;
        notifyListeners();
      },
      (entries) {
        if (!_isCurrentRemoteRequest(token)) return;
        _remoteRows = _mapRemoteRows(path, entries);
        _remoteError = null;
        notifyListeners();
      },
    );
  }

  Future<void> downloadRemoteEntry(
    SftpFileEntry file,
    String localPath, {
    bool overwrite = false,
  }) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    if (sessionId == null || remotePath == null) return;
    if (!overwrite && localTargetExists(localPath)) {
      throw StateError('Local target already exists: $localPath');
    }
    final jobId = _beginTransfer(file.name, 'Remote -> Local');
    try {
      _updateTransfer(jobId, value: .12);
      if (file.folder) {
        await _downloadRemoteDirectory(sessionId, remotePath, localPath);
      } else {
        await _downloadRemoteFile(sessionId, remotePath, localPath);
      }
      _updateTransfer(jobId, value: 1, done: true);
      await _refreshLocalDirectoryForDownloadedPath(localPath);
    } catch (error) {
      _updateTransfer(jobId, failed: true, error: '$error');
      rethrow;
    }
  }

  Future<void> uploadLocalPath(
    String localPath, {
    String? remoteDirectory,
    bool overwrite = false,
  }) async {
    final sessionId = _remoteSessionId;
    if (sessionId == null) return;
    final normalized = localPath.trim();
    final entityType = FileSystemEntity.typeSync(normalized);
    if (entityType == FileSystemEntityType.notFound) {
      throw FileSystemException('Local path not found', normalized);
    }
    final targetDirectory = remoteDirectory ?? _remotePath;
    final targetPath = remoteUploadTargetPath(
      normalized,
      remoteDirectory: targetDirectory,
    );
    if (!overwrite &&
        remoteTargetExistsForLocalPath(
          normalized,
          remoteDirectory: targetDirectory,
        )) {
      throw StateError('Remote target already exists: $targetPath');
    }
    final jobId = _beginTransfer(_basename(normalized), 'Local -> Remote');
    try {
      _updateTransfer(jobId, value: .12);
      if (entityType == FileSystemEntityType.directory) {
        await _uploadDirectory(
          sessionId,
          Directory(normalized),
          targetDirectory,
        );
      } else {
        await _uploadFile(sessionId, File(normalized), targetDirectory);
      }
      _updateTransfer(jobId, value: 1, done: true);
    } catch (error) {
      _updateTransfer(jobId, failed: true, error: '$error');
      rethrow;
    }
    await loadRemoteDirectory(targetDirectory);
  }

  String remoteUploadTargetPath(String localPath, {String? remoteDirectory}) {
    return _joinRemote(remoteDirectory ?? _remotePath, _basename(localPath));
  }

  bool remoteTargetExistsForLocalPath(
    String localPath, {
    String? remoteDirectory,
  }) {
    final targetDirectory = remoteDirectory ?? _remotePath;
    final targetPath = remoteUploadTargetPath(
      localPath,
      remoteDirectory: targetDirectory,
    );
    return _remoteRows.any(
      (row) =>
          row.name != '..' &&
          (row.path == targetPath || row.name == _basename(localPath)),
    );
  }

  bool localTargetExists(String localPath) {
    return FileSystemEntity.typeSync(localPath) !=
        FileSystemEntityType.notFound;
  }

  void searchLocal(String query) {
    _localSearchQuery = query.trim();
    notifyListeners();
  }

  void clearLocalSearch() {
    if (!localSearchActive) return;
    _localSearchQuery = '';
    notifyListeners();
  }

  Future<void> createLocalFolder(String name) async {
    final localPath = _joinLocal(_localPath, name.trim());
    if (localPath == null) return;
    await Directory(localPath).create();
    await loadLocalDirectory(_localPath);
  }

  Future<void> createLocalFile(String name) async {
    final localPath = _joinLocal(_localPath, name.trim());
    if (localPath == null) return;
    final file = File(localPath);
    if (await file.exists()) {
      throw StateError('Local file already exists: $localPath');
    }
    await file.create();
    await loadLocalDirectory(_localPath);
  }

  Future<void> createRemoteFolder(String name) async {
    await _createRemoteEntry(name, folder: true);
  }

  Future<void> createRemoteFile(String name) async {
    await _createRemoteEntry(name, folder: false);
  }

  Future<void> chmodRemotePath(SftpFileEntry file, int mode) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    if (sessionId == null || remotePath == null) return;
    final normalizedMode = mode.toString().padLeft(3, '0');
    final result = await _connectionManager.chmodRemotePath(
      sessionId,
      remotePath,
      normalizedMode,
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
    _remoteChmodModes[remotePath] = normalizedMode;
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> renameRemotePath(SftpFileEntry file, String newName) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    final trimmed = newName.trim();
    if (sessionId == null || remotePath == null || trimmed.isEmpty) return;
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      throw StateError('Rename only supports a name, not a path.');
    }
    final targetPath = _renameTargetPath(remotePath, trimmed);
    final result = await _connectionManager.executeRemoteCommand(
      sessionId,
      'mv -- ${_shellQuote(remotePath)} ${_shellQuote(targetPath)}',
      action: 'rename remote path',
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
    final oldMode = _remoteChmodModes.remove(remotePath);
    if (oldMode != null) _remoteChmodModes[targetPath] = oldMode;
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> duplicateRemotePath(SftpFileEntry file, String newName) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    final trimmed = newName.trim();
    if (sessionId == null || remotePath == null || trimmed.isEmpty) return;
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      throw StateError('Duplicate only supports a name, not a path.');
    }
    final targetPath = _renameTargetPath(remotePath, trimmed);
    final command = file.folder
        ? 'cp -R -- ${_shellQuote(remotePath)} ${_shellQuote(targetPath)}'
        : 'cp -- ${_shellQuote(remotePath)} ${_shellQuote(targetPath)}';
    final result = await _connectionManager.executeRemoteCommand(
      sessionId,
      command,
      action: 'duplicate remote path',
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> moveRemotePath(SftpFileEntry file, String targetPath) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    final trimmed = targetPath.trim();
    if (sessionId == null || remotePath == null || trimmed.isEmpty) return;
    final result = await _connectionManager.executeRemoteCommand(
      sessionId,
      'mv -- ${_shellQuote(remotePath)} ${_shellQuote(trimmed)}',
      action: 'move remote path',
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
    _remoteChmodModes.remove(remotePath);
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> deleteRemotePath(SftpFileEntry file) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    if (sessionId == null || remotePath == null || file.name == '..') return;
    final trimmed = remotePath.trim();
    if (trimmed.isEmpty || trimmed == '/' || trimmed == '~') {
      throw StateError('This remote path cannot be deleted.');
    }
    final result = await _connectionManager.executeRemoteCommand(
      sessionId,
      'rm -rf -- ${_shellQuote(trimmed)}',
      action: 'delete remote path',
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
    _remoteChmodModes.remove(trimmed);
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> renameLocalPath(SftpFileEntry file, String newName) async {
    final localPath = file.path;
    final trimmed = newName.trim();
    if (localPath == null || trimmed.isEmpty) return;
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      throw StateError('Rename only supports a name, not a path.');
    }
    final targetPath =
        '${File(localPath).parent.path}${Platform.pathSeparator}$trimmed';
    final type = FileSystemEntity.typeSync(localPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(localPath).rename(targetPath);
    } else if (type != FileSystemEntityType.notFound) {
      await File(localPath).rename(targetPath);
    }
    await loadLocalDirectory(_localPath);
  }

  Future<void> deleteLocalPath(SftpFileEntry file) async {
    final localPath = file.path;
    if (localPath == null || file.name == '..') return;
    final type = FileSystemEntity.typeSync(localPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(localPath).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(localPath).delete();
    }
    await loadLocalDirectory(_localPath);
  }

  Future<void> duplicateLocalPath(SftpFileEntry file, String newName) async {
    final localPath = file.path;
    final trimmed = newName.trim();
    if (localPath == null || trimmed.isEmpty) return;
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      throw StateError('Duplicate only supports a name, not a path.');
    }
    final targetPath =
        '${File(localPath).parent.path}${Platform.pathSeparator}$trimmed';
    final type = FileSystemEntity.typeSync(localPath);
    if (type == FileSystemEntityType.directory) {
      await _copyLocalDirectory(Directory(localPath), Directory(targetPath));
    } else if (type != FileSystemEntityType.notFound) {
      await File(localPath).copy(targetPath);
    }
    await loadLocalDirectory(_localPath);
  }

  Future<void> moveLocalPath(SftpFileEntry file, String targetPath) async {
    final localPath = file.path;
    final trimmed = targetPath.trim();
    if (localPath == null || trimmed.isEmpty) return;
    final type = FileSystemEntity.typeSync(localPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(localPath).rename(trimmed);
    } else if (type != FileSystemEntityType.notFound) {
      await File(localPath).rename(trimmed);
    }
    await loadLocalDirectory(_localPath);
  }

  void clearRemoteSearch() {
    if (!remoteSearchActive &&
        !_searchingRemote &&
        _remoteSearchError == null) {
      return;
    }
    _remoteSearchToken += 1;
    _clearRemoteSearchState();
    notifyListeners();
  }

  Future<void> searchRemote(String rawQuery) async {
    final sessionId = _remoteSessionId;
    if (sessionId == null) return;
    final parsed = _parseRemoteSearch(rawQuery);
    if (parsed.query.isEmpty) {
      clearRemoteSearch();
      return;
    }

    final token = ++_remoteSearchToken;
    _remoteSearchQuery = parsed.query;
    _remoteSearchBase = parsed.base;
    _remoteSearchRows = const [];
    _remoteSearchError = null;
    _searchingRemote = true;
    notifyListeners();

    final resolvedResult = await _connectionManager.resolveRemoteDirectory(
      sessionId,
      parsed.base,
    );
    final resolvedBase = resolvedResult.fold<String?>((failure) {
      if (!_isCurrentRemoteSearch(token)) return null;
      _remoteSearchError = failure.message;
      _searchingRemote = false;
      notifyListeners();
      return null;
    }, (value) => value);
    if (resolvedBase == null) return;

    final result = await _connectionManager.findRemoteEntries(
      sessionId,
      resolvedBase,
      parsed.query,
      maxResults: _maxRemoteSearchResults,
    );
    result.fold(
      (failure) {
        if (!_isCurrentRemoteSearch(token)) return;
        _remoteSearchError = failure.message;
        _remoteSearchRows = const [];
        _searchingRemote = false;
        notifyListeners();
      },
      (entries) {
        if (!_isCurrentRemoteSearch(token)) return;
        final results = entries.map(_mapSearchResult).toList(growable: false);
        _remoteSearchBase = resolvedBase;
        _remoteSearchRows = results;
        _remoteSearchError = results.length >= _maxRemoteSearchResults
            ? 'Showing first $_maxRemoteSearchResults matches.'
            : null;
        _searchingRemote = false;
        notifyListeners();
      },
    );
  }

  void queueTransfer(SftpFileTransfer transfer, bool targetRemote) {
    if (transfer.fromRemote == targetRemote) return;
    _transferJobs.insert(
      0,
      SftpTransferJob(
        id: ++_transferSerial,
        name: transfer.file.name,
        direction: targetRemote ? 'Local -> Remote' : 'Remote -> Local',
        value: transfer.file.folder ? .18 : .46,
        queued: _transferJobs.isNotEmpty,
      ),
    );
    notifyListeners();
  }

  int _beginTransfer(String name, String direction) {
    _clearTransferTimer?.cancel();
    final id = ++_transferSerial;
    _transferJobs.insert(
      0,
      SftpTransferJob(id: id, name: name, direction: direction, value: 0),
    );
    notifyListeners();
    return id;
  }

  void _updateTransfer(
    int id, {
    double? value,
    bool? done,
    bool? failed,
    String? error,
  }) {
    final index = _transferJobs.indexWhere((job) => job.id == id);
    if (index == -1) return;
    _transferJobs[index] = _transferJobs[index].copyWith(
      value: value,
      queued: false,
      done: done,
      failed: failed,
      error: error,
    );
    _scheduleTransferAutoClear();
    notifyListeners();
  }

  void clearTransfers() {
    _clearTransferTimer?.cancel();
    _transferJobs.clear();
    notifyListeners();
  }

  void _scheduleTransferAutoClear() {
    _clearTransferTimer?.cancel();
    if (_transferJobs.isEmpty ||
        _transferJobs.any((job) => !job.done && !job.failed)) {
      return;
    }
    _clearTransferTimer = Timer(const Duration(seconds: 20), () {
      _transferJobs.clear();
      notifyListeners();
    });
  }

  Future<List<LocalEditor>> detectLocalEditors() {
    return _localEditorService.detectEditors();
  }

  /// List remote directory entries without affecting controller state.
  /// Used by folder picker dialogs.
  Future<List<SftpFileEntry>> listRemoteDirectoryRaw(String path) async {
    final sessionId = _remoteSessionId;
    if (sessionId == null) throw StateError('No remote session');
    final result = await _connectionManager.listRemoteDirectory(sessionId, path);
    return result.fold(
      (failure) => throw StateError(failure.message),
      (entries) => _mapRemoteRows(path, entries),
    );
  }

  Future<String> editablePathFor(SftpFileEntry file, bool isRemote) async {
    if (!isRemote) return file.path ?? file.name;
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    if (sessionId == null || remotePath == null) {
      throw StateError('Remote SFTP session is not connected.');
    }
    final tempRoot = await Directory.systemTemp.createTemp('portix-sftp-edit-');
    final localPath = '${tempRoot.path}${Platform.pathSeparator}${file.name}';
    await _downloadRemoteFile(sessionId, remotePath, localPath);
    return localPath;
  }

  Future<void> rewriteRemoteFileFromLocal(
    SftpFileEntry file,
    String localPath,
  ) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    if (sessionId == null || remotePath == null) {
      throw StateError('Remote SFTP session is not connected.');
    }
    final result = await _connectionManager.uploadRemoteFile(
      sessionId,
      remotePath,
      await File(localPath).readAsBytes(),
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> openEditor(LocalEditor editor, String path) {
    return _localEditorService.open(editor, path);
  }

  Future<void> openWithSystemDefault(String path) {
    return _localEditorService.openWithSystemDefault(path);
  }

  Future<List<LocalEditor>> detectAppsForExtension(String extension) {
    return _localEditorService.detectAppsForExtension(extension);
  }

  @override
  void dispose() {
    _connectionManager.removeListener(_handleConnectionManagerChanged);
    _clearTransferTimer?.cancel();
    final sessionId = _remoteSessionId;
    _remoteSessionId = null;
    if (sessionId != null) {
      unawaited(_connectionManager.closeSession(sessionId));
    }
    super.dispose();
  }

  void _handleConnectionManagerChanged() {
    if (_remoteSessionId == null) return;
    final session = _connectionManager.sessions
        .where((s) => s.id == _remoteSessionId)
        .firstOrNull;
    if (session == null) {
      // Session was removed entirely — mark as disconnected.
      _remoteError = 'SFTP session lost. Connection was closed.';
      _remoteStatus = 'disconnected';
      notifyListeners();
      return;
    }
    if (session.status == ConnectionStatus.disconnected ||
        session.status == ConnectionStatus.error) {
      _remoteError ??= 'Remote connection lost.';
      _remoteStatus = 'disconnected';
      notifyListeners();
    }
  }

  /// Reconnect the SFTP session using the same profile and path.
  Future<void> reconnect(domain.SshProfile profile) async {
    final previousPath = _remotePath;
    await clearRemoteSession();
    await attachRemoteProfile(profile, previousPath);
  }

  bool _isCurrentRemoteRequest(int token) {
    return token == _remoteLoadToken && _remoteSessionId != null;
  }

  bool _isCurrentRemoteSearch(int token) {
    return token == _remoteSearchToken && _remoteSessionId != null;
  }

  void _clearRemoteSearchState() {
    _remoteSearchRows = const [];
    _remoteSearchQuery = '';
    _remoteSearchBase = _remotePath;
    _remoteSearchError = null;
    _searchingRemote = false;
  }

  _RemoteSearchInput _parseRemoteSearch(String rawQuery) {
    final trimmed = rawQuery.trim();
    final splitIndex = trimmed.indexOf(':');
    if (splitIndex > 0 && trimmed.startsWith('/')) {
      final base = trimmed.substring(0, splitIndex).trim();
      final query = trimmed.substring(splitIndex + 1).trim();
      return _RemoteSearchInput(base: base.isEmpty ? '/' : base, query: query);
    }
    return _RemoteSearchInput(base: _remotePath, query: trimmed);
  }

  static const int _maxRemoteSearchResults = 120;

  Future<void> _createRemoteEntry(String name, {required bool folder}) async {
    final sessionId = _remoteSessionId;
    if (sessionId == null) return;
    final remotePath = _joinRemote(_remotePath, name.trim());
    final result = folder
        ? await _connectionManager.createRemoteDirectory(sessionId, remotePath)
        : await _connectionManager.createRemoteFile(sessionId, remotePath);
    result.fold((failure) => throw StateError(failure.message), (_) {});
    await _refreshCurrentRemoteDirectory();
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
    final bytes = result.fold<List<int>>(
      (failure) => throw StateError(failure.message),
      (bytes) => bytes,
    );
    final file = File(localPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
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
    final entries = result.fold<List<RemoteFileEntry>>(
      (failure) => throw StateError(failure.message),
      (entries) => entries,
    );
    for (final entry in entries) {
      final childPath = '$localPath${Platform.pathSeparator}${entry.name}';
      if (entry.isDirectory) {
        await _downloadRemoteDirectory(sessionId, entry.path, childPath);
      } else {
        await _downloadRemoteFile(sessionId, entry.path, childPath);
      }
    }
  }

  Future<void> _copyLocalDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final childTarget =
          '${target.path}${Platform.pathSeparator}${_basename(entity.path)}';
      if (entity is Directory) {
        await _copyLocalDirectory(entity, Directory(childTarget));
      } else if (entity is File) {
        await entity.copy(childTarget);
      }
    }
  }

  Future<void> _refreshLocalDirectoryForDownloadedPath(String localPath) async {
    final targetParent = Directory(localPath).parent.absolute.path;
    final currentLocal = Directory(_localPath).absolute.path;
    if (targetParent == currentLocal) {
      await loadLocalDirectory(_localPath);
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
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        await _uploadDirectory(sessionId, entity, remoteRoot);
      } else if (entity is File) {
        await _uploadFile(sessionId, entity, remoteRoot);
      }
    }
  }

  List<SftpFileEntry> _mapRemoteRows(
    String currentPath,
    List<RemoteFileEntry> entries,
  ) {
    final rows = <SftpFileEntry>[
      if (currentPath != '/' && currentPath.trim().isNotEmpty)
        SftpFileEntry(
          name: '..',
          path: _parentRemotePath(currentPath),
          size: '-',
          modified: '-',
          type: 'dir',
          folder: true,
          chmodMode: _remoteChmodModes[_parentRemotePath(currentPath)],
        ),
      ...entries.map(
        (entry) => SftpFileEntry(
          name: entry.name,
          path: entry.path,
          size: entry.isDirectory ? '-' : _formatFileSize(entry.sizeBytes),
          modified: _formatUnixDate(entry.modifiedUnixSeconds),
          type: entry.isDirectory ? 'dir' : 'file',
          folder: entry.isDirectory,
          chmodMode: _remoteChmodModes[entry.path],
        ),
      ),
    ];
    rows.sort((a, b) {
      if (a.name == '..') return -1;
      if (b.name == '..') return 1;
      if (a.folder != b.folder) return a.folder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return rows;
  }

  SftpFileEntry _mapSearchResult(RemoteFileEntry entry) {
    return SftpFileEntry(
      name: entry.name,
      path: entry.path,
      location: _parentRemotePath(entry.path),
      size: entry.isDirectory ? '-' : _formatFileSize(entry.sizeBytes),
      modified: _formatUnixDate(entry.modifiedUnixSeconds),
      type: entry.isDirectory ? 'dir' : 'file',
      folder: entry.isDirectory,
      chmodMode: _remoteChmodModes[entry.path],
    );
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
}

class _RemoteSearchInput {
  const _RemoteSearchInput({required this.base, required this.query});

  final String base;
  final String query;
}

String _joinRemote(String directory, String name) {
  final base = directory.trim().isEmpty ? '~' : directory.trim();
  if (base == '/') return '/$name';
  return '${base.replaceFirst(RegExp(r'/+$'), '')}/$name';
}

String? _joinLocal(String directory, String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.contains('/') || trimmed.contains('\\')) {
    throw StateError('Use a name, not a path.');
  }
  return '$directory${Platform.pathSeparator}$trimmed';
}

String _parentRemotePath(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty || normalized == '/' || normalized == '~') {
    return normalized.isEmpty ? '~' : normalized;
  }

  final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
  if (parts.length <= 1) return '/';
  return '/${parts.take(parts.length - 1).join('/')}';
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

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
  return parts.isEmpty ? normalized : parts.last;
}

bool _matchesLocalSearch(SftpFileEntry row, String query) {
  if (row.name == '..') return true;
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return row.name.toLowerCase().contains(normalized) ||
      (row.location?.toLowerCase().contains(normalized) ?? false) ||
      row.type.toLowerCase().contains(normalized);
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

String _formatUnixDate(int seconds) {
  if (seconds <= 0) return '-';
  return _formatDate(
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal(),
  );
}

String _formatDate(DateTime date) {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return 'Today ${two(date.hour)}:${two(date.minute)}';
  }
  final yesterday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 1));
  if (date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day) {
    return 'Yesterday';
  }
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
