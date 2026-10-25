import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart'
    as manager_profile;
import 'package:portix/src/sftp_client/sftp_manager.dart';
import 'package:portix/src/sftp_client/sftp_models.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/data/services/sftp/index.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart' as domain;

class SftpWorkspaceController extends ChangeNotifier {
  SftpWorkspaceController({
    required SftpManager sftpManager,
    LocalFileBrowser? localFileBrowser,
    LocalEditorService? localEditorService,
    String? tabId,
    this.resolveConnectFailure,
  }) : _sftp = sftpManager,
       _localFileBrowser = localFileBrowser ?? LocalFileBrowser(),
       _localEditorService = localEditorService ?? LocalEditorService(),
       tabId = tabId ?? const Uuid().v4() {
    _localPath = _localFileBrowser.defaultPath();
    unawaited(loadLocalDirectory(_localPath));
    _sftp.addListener(_handleSftpChanged);
  }

  /// Lets the UI fix a failed connect it can explain (a host key to trust,
  /// a key passphrase to enter). True means connect again.
  final Future<bool> Function(manager_profile.SshProfile profile, Object error)?
  resolveConnectFailure;

  /// Unique per tab, so a re-opened tab never picks up a closed tab's stale
  /// session or disconnect notifications.
  final String tabId;
  final SftpManager _sftp;

  /// Used by the workspace page to resolve saved passwords for
  /// duplicate-window flows.
  SftpManager get sftpManager => _sftp;
  final LocalFileBrowser _localFileBrowser;
  final LocalEditorService _localEditorService;

  /// True once [dispose] has run; async work that resumes after a tab closes
  /// checks it before notifying.
  bool _isDisposed = false;

  final List<SftpTransferJob> _transferJobs = [];
  int _transferSerial = 0;
  Timer? _clearTransferTimer;
  late String _localPath;
  List<SftpFileEntry> _localRows = const [];
  String _localSearchQuery = '';
  String _remotePath = '~';
  List<SftpFileEntry> _remoteRows = const [];
  List<SftpFileEntry> _remoteSearchRows = const [];
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
  String? _remoteProfileName;

  /// Profile pending password submission (when authMethod is password-based
  /// and no saved password exists). Used by [submitPassword] to complete
  /// the connection once the inline form collects a password.
  domain.SshProfile? _pendingProfile;

  /// Set while [submitPassword] awaits the keychain save, so a post-frame
  /// `attachRemoteProfile` with the password-less profile can't re-show the form.
  bool _passwordSubmitting = false;

  /// Exposed for the UI to read the profile currently awaiting password
  /// input, so it can show a contextual dialog.
  domain.SshProfile? get pendingProfile => _pendingProfile;

  /// True once the 'authenticating' step was visited, so the indicator keeps
  /// all 4 steps afterwards.
  bool _didAuthenticate = false;
  // Consecutive remote operation failures. When this hits the threshold the
  // session is force-closed so the disconnect overlay appears immediately
  // without waiting for the Rust keepalive timeout (~17 s).
  int _remoteConsecutiveFailures = 0;
  static const int _remoteFailThreshold = 2;
  int _remoteLoadToken = 0;
  int _remoteSearchToken = 0;
  Timer? _remoteSearchDebounce;

  // Set while disconnected, so 'connection lost' is entered once per drop,
  // not on every ConnectionManager notification.
  bool _remoteDisconnectNotified = false;

  /// Whether `SftpManager.connect` is in flight. [beginLoading] pre-sets
  /// 'connecting' without connecting, so the status alone can't guard.
  bool _connectInProgress = false;

  bool _showConnectionSteps = false;

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

  /// Raw remote connection status string (e.g. 'authenticating',
  /// 'connecting', 'listing', 'connected', 'disconnected', 'failed',
  /// 'idle'). Exposed so the UI can drive step-based loading indicators.
  String get remoteStatus => _remoteStatus;

  /// The UI session ID currently attached to this tab, or null when no
  /// remote profile is selected. Exposed for diagnostics and testing.
  String? get remoteSessionId => _remoteSessionId;

  /// Human-readable name of the currently attached SSH profile, or null when
  /// no remote profile is selected.
  String? get remoteProfileName => _remoteProfileName;
  String? get remoteProfileId => _remoteProfileId;

  /// 4 steps (with a password step) when the profile needed an unsaved
  /// password; key or saved-password profiles get 3.
  bool get showPasswordStep =>
      _didAuthenticate || _remoteStatus == 'authenticating';

  /// True during the initial connect or a reconnect; false once the first
  /// listing finishes, so reloads show only the skeleton table.
  bool get showConnectionSteps => _showConnectionSteps;

  bool get isRemoteDisconnected {
    final sessionId = _remoteSessionId;
    return sessionId != null && !_sftp.isConnected(sessionId);
  }

  /// Marks the remote pane loading before [attachRemoteProfile] is scheduled,
  /// so the file table doesn't flash for a frame after a profile is picked.
  void beginLoading() {
    if (_loadingRemote) return;
    _loadingRemote = true;
    _remoteStatus = 'connecting';
    _showConnectionSteps = true;
    _remoteError = null;
    notifyListeners();
  }

  bool get isRemoteConnected {
    final sessionId = _remoteSessionId;
    return sessionId != null && _sftp.isConnected(sessionId);
  }

  /// Like [isRemoteConnected], but asks the server now: after a network
  /// drop the session still reads as connected until the liveness check.
  Future<bool> probeRemote() async {
    final sessionId = _remoteSessionId;
    return sessionId != null && await _sftp.probe(sessionId);
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

  /// True when the session needs re-validating on the next visit: no session,
  /// a known disconnect, or a remote error (the channel can die behind a live port).
  bool get needsRevalidation {
    if (_remoteSessionId == null) return true;
    if (isRemoteDisconnected) return true;
    if (_remoteError != null) return true;
    return false;
  }

  String get remoteStatusTitle {
    if (_remoteError != null) {
      if (_remoteStatus == 'failed') return 'Connection failed';
      return 'Remote unavailable';
    }
    if (_remoteStatus == 'authenticating') return 'Authenticating';
    if (_remoteStatus == 'connecting') return 'Loading';
    if (_remoteStatus == 'listing') return 'Connecting...';
    if (_remoteSessionId != null) return 'Connected';
    return 'No remote session';
  }

  String get remoteStatusMessage {
    // During 'authenticating' the message is always empty — the error
    // (if any) is shown inline in the password form, not above the
    // step indicator.
    if (_remoteStatus == 'authenticating') {
      return '';
    }
    if (_remoteError != null) return _remoteError!;
    if (_remoteStatus == 'connecting') {
      return 'Connecting to server...';
    }
    if (_remoteStatus == 'listing') {
      return '';
    }
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

  /// Reads the children of [path] without changing the current local
  /// selection. Used by the path-bar autocomplete so typing an absolute path
  /// (e.g. `/opt/`) can complete against that directory instead of the
  /// currently‑browsed one.
  Future<List<SftpFileEntry>> readLocalDirectory(String path) {
    return _localFileBrowser.readDirectory(path).then((r) => r.entries);
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

    // Initial connection or auth-error retry — show the step indicator
    // so the user can follow the connection progress.
    _showConnectionSteps = true;

    // Reuse the session only if connected with no remote error; an error means
    // the channel may be dead even though port 22 still answers.
    if (_remoteProfileId == profile.id && _remoteSessionId != null) {
      if (isRemoteConnected && _remoteError == null) {
        if (_remoteRows.isEmpty && !_loadingRemote) {
          await loadRemoteDirectory(_remotePath);
        } else if (_remotePath != normalizedPath && _remoteRows.isEmpty) {
          await loadRemoteDirectory(normalizedPath);
        }
        // Undo beginLoading()'s pre-set 'connecting' so the indicator doesn't stick.
        if (_loadingRemote && _remoteStatus == 'connecting') {
          _loadingRemote = false;
          _showConnectionSteps = false;
          _remoteStatus = 'connected';
          notifyListeners();
        }
        return;
      }
      // Stale session: show the disconnected overlay instead of reconnecting on
      // every tab switch.
      _remoteError ??= 'Remote connection lost.';
      _remoteStatus = 'disconnected';
      _remoteDisconnectNotified = true;
      notifyListeners();
      return;
    }

    // No usable password: wait in 'authenticating' for the inline form;
    // [submitPassword] resumes the connect.
    if (profile.authMethod == domain.AuthMethod.password &&
        (profile.credentialLabel.trim().isEmpty ||
            profile.credentialLabel == 'Saved password')) {
      // See [_passwordSubmitting].
      if (_passwordSubmitting) {
        return;
      }
      final hasSaved = await _sftp.credentials.hasSavedPassword(profile.id);
      if (!hasSaved) {
        _pendingProfile = profile;
        _remoteProfileId = profile.id;
        _remoteProfileName = profile.name;
        _remotePath = normalizedPath;
        _remoteStatus = 'authenticating';
        _loadingRemote = true;
        _remoteError = null;
        _didAuthenticate = true;
        notifyListeners();
        return;
      }
    }

    // Block only a real connect or a listing in progress, not beginLoading()'s
    // pre-set 'connecting'; 'authenticating' passes so [submitPassword] can resume.
    if (_connectInProgress || _remoteStatus == 'listing') {
      return;
    }

    _remotePath = normalizedPath;
    _loadingRemote = true;
    _remoteStatus = 'connecting';
    _remoteError = null;
    notifyListeners();

    _connectInProgress = true;
    final managerProfile = manager_profile.SshProfile.fromDomain(profile);
    final result = await _sftp.connect(managerProfile);
    _connectInProgress = false;
    if (result case Left(value: final failure)) {
      final failureStr = failure.toString();
      final resolve = resolveConnectFailure;
      if (resolve != null && !_isDisposed) {
        _connectInProgress = true;
        final retry = await resolve(managerProfile, failure);
        _connectInProgress = false;
        if (retry) return attachRemoteProfile(profile, normalizedPath);
      }

      // If the profile is password-based and the error is auth-related,
      // re-enter the 'authenticating' state so the inline form can collect
      // a different password. The error is shown below the password field.
      if (profile.authMethod == domain.AuthMethod.password &&
          _isAuthError(failureStr)) {
        _pendingProfile = profile;
        _remoteStatus = 'authenticating';
        _loadingRemote = true;
        _remoteError = 'Authentication failed';
        notifyListeners();
        return;
      }

      // The server didn't answer in time; reconnect retries.
      if (_isTimeoutError(failureStr)) {
        _loadingRemote = false;
        _remoteStatus = 'failed';
        _remoteError = 'Connection timeout';
        notifyListeners();
        return;
      }

      _loadingRemote = false;
      _remoteStatus = 'failed';
      _remoteError = failureStr;
      notifyListeners();
      return;
    }

    final sessionId = result.fold((_) => '', (id) => id);
    if (_isDisposed) {
      unawaited(_sftp.close(sessionId));
      return;
    }
    _remoteSessionId = sessionId;
    _remoteProfileId = profile.id;
    _remoteProfileName = profile.name;
    await loadRemoteDirectory(_remotePath);
  }

  Future<void> clearRemoteSession() async {
    final sessionId = _remoteSessionId;
    _remoteSessionId = null;
    _remoteProfileId = null;
    _remoteProfileName = null;
    _pendingProfile = null;
    _didAuthenticate = false;
    _passwordSubmitting = false;
    _remoteRows = const [];
    _clearRemoteSearchState();
    _remoteError = null;
    _loadingRemote = false;
    _remoteStatus = 'idle';
    _remoteDisconnectNotified = false;
    _connectInProgress = false;
    _showConnectionSteps = false;
    _remoteConsecutiveFailures = 0;
    _remoteLoadToken += 1;
    _remoteSearchToken += 1;
    notifyListeners();
    if (sessionId != null) {
      await _sftp.close(sessionId);
    }
  }

  /// Whether [error] looks like an auth failure, so the password is asked
  /// again inline instead of showing "Connection failed".
  static bool _isAuthError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('password') ||
        lower.contains('auth') ||
        lower.contains('credential') ||
        lower.contains('permission denied') ||
        lower.contains('access denied');
  }

  /// Returns true when [error] indicates a connection timeout rather than
  /// an authentication or generic failure.
  static bool _isTimeoutError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('timedout');
  }

  Future<void> loadRemoteDirectory(String path) async {
    final sessionId = _remoteSessionId;
    if (sessionId == null) return;
    final token = ++_remoteLoadToken;
    _remoteSearchToken += 1;
    _clearRemoteSearchState();
    _loadingRemote = true;
    _remoteStatus = 'listing';
    _remoteError = null;
    notifyListeners();

    final resolvedResult = await _sftp.resolve(
      sessionId,
      path.trim().isEmpty ? _remotePath : path.trim(),
    );
    final resolvedPath = resolvedResult.fold<String?>((failure) {
      if (!_isCurrentRemoteRequest(token)) return null;
      _loadingRemote = false;
      _remoteStatus = 'failed';
      _remoteError = failure.message;
      notifyListeners();
      _recordRemoteFailure(sessionId);
      return null;
    }, (value) => value);
    if (resolvedPath == null) return;

    final entriesResult = await _sftp.list(sessionId, resolvedPath);
    entriesResult.fold(
      (failure) {
        if (!_isCurrentRemoteRequest(token)) return;
        _loadingRemote = false;
        _remoteStatus = 'failed';
        _remoteError = failure.message;
        notifyListeners();
        _recordRemoteFailure(sessionId);
      },
      (entries) {
        if (!_isCurrentRemoteRequest(token)) return;
        _remotePath = resolvedPath;
        _remoteRows = _mapRemoteRows(resolvedPath, entries);
        _loadingRemote = false;
        _remoteStatus = 'connected';
        _remoteError = null;
        _remoteConsecutiveFailures = 0;
        // Later reloads show only the skeleton, not the step indicator.
        _showConnectionSteps = false;
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

    final entriesResult = await _sftp.list(sessionId, path);
    entriesResult.fold(
      (failure) {
        if (!_isCurrentRemoteRequest(token)) return;
        _remoteError = failure.message;
        notifyListeners();
        _recordRemoteFailure(sessionId);
      },
      (entries) {
        if (!_isCurrentRemoteRequest(token)) return;
        _remoteRows = _mapRemoteRows(path, entries);
        _remoteError = null;
        _remoteConsecutiveFailures = 0;
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
        await _downloadRemoteFile(
          sessionId,
          remotePath,
          localPath,
          onProgress: (progress) => _reportProgress(jobId, progress),
        );
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
    if (sessionId == null) {
      throw StateError('Remote SFTP session is not connected yet.');
    }
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
        await _uploadFile(
          sessionId,
          File(normalized),
          targetDirectory,
          onProgress: (progress) => _reportProgress(jobId, progress),
        );
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
    final result = await _sftp.chmod(sessionId, remotePath, normalizedMode);
    result.fold((failure) => throw StateError(failure.message), (_) {});
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> renameRemotePath(SftpFileEntry file, String newName) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    final trimmed = newName.trim();
    if (sessionId == null) {
      throw StateError('Remote SFTP session is not connected yet.');
    }
    if (remotePath == null || trimmed.isEmpty) return;
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      throw StateError('Rename only supports a name, not a path.');
    }
    final targetPath = _renameTargetPath(remotePath, trimmed);
    final result = await _sftp.rename(sessionId, remotePath, targetPath);
    result.fold((failure) => throw StateError(failure.message), (_) {});
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
    final result = await _sftp.copy(sessionId, remotePath, targetPath);
    result.fold((failure) => throw StateError(failure.message), (_) {});
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> moveRemotePath(SftpFileEntry file, String targetPath) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    final trimmed = targetPath.trim();
    if (sessionId == null || remotePath == null || trimmed.isEmpty) return;
    final result = await _sftp.rename(sessionId, remotePath, trimmed);
    result.fold((failure) => throw StateError(failure.message), (_) {});
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
    final result = await _sftp.remove(sessionId, trimmed);
    result.fold((failure) => throw StateError(failure.message), (_) {});
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> renameLocalPath(SftpFileEntry file, String newName) async {
    final localPath = file.path;
    final trimmed = newName.trim();
    if (localPath == null) {
      throw StateError('Local file path is missing.');
    }
    if (trimmed.isEmpty) return;
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
    _remoteSearchDebounce?.cancel();
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
    _remoteSearchDebounce?.cancel();
    final sessionId = _remoteSessionId;
    if (sessionId == null) return;
    final parsed = _parseRemoteSearch(rawQuery);
    if (parsed.query.isEmpty) {
      clearRemoteSearch();
      return;
    }

    // Show searching state immediately but debounce the actual network call.
    _remoteSearchQuery = parsed.query;
    _remoteSearchBase = parsed.base;
    _searchingRemote = true;
    notifyListeners();

    _remoteSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_executeRemoteSearch(sessionId, parsed));
    });
  }

  Future<void> _executeRemoteSearch(
    String sessionId,
    _RemoteSearchInput parsed,
  ) async {
    final token = ++_remoteSearchToken;
    _remoteSearchRows = const [];
    _remoteSearchError = null;
    _searchingRemote = true;
    notifyListeners();

    final resolvedResult = await _sftp.resolve(sessionId, parsed.base);
    final resolvedBase = resolvedResult.fold<String?>((failure) {
      if (!_isCurrentRemoteSearch(token)) return null;
      _remoteSearchError = failure.message;
      _searchingRemote = false;
      notifyListeners();
      return null;
    }, (value) => value);
    if (resolvedBase == null) return;

    final result = await _sftp.find(
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

  /// Byte progress of a single-file transfer; only whole-percent changes
  /// reach the UI so a big file does not rebuild it on every chunk.
  void _reportProgress(int jobId, TransferProgress progress) {
    final job = _transferJobs.where((job) => job.id == jobId).firstOrNull;
    final value = (progress.fraction * 100).floor() / 100;
    if (job == null || job.value == value) return;
    _updateTransfer(jobId, value: value);
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
    final result = await _sftp.list(sessionId, path);
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
    final tempRoot = await LocalEditorService.createOpenTempDir();
    final localFileName = LocalEditorService.buildRemoteTempFileName(
      file.name,
      remotePath: remotePath,
      profileName: _remoteProfileName,
    );
    final localPath =
        '${tempRoot.path}${Platform.pathSeparator}${localFileName}';
    await _downloadRemoteFile(sessionId, remotePath, localPath);
    return localPath;
  }

  /// Uploads [localPath] over [file], refusing when this pane is no longer on
  /// [profileId], the server the copy was downloaded from.
  Future<void> rewriteRemoteFileFromLocal(
    SftpFileEntry file,
    String localPath, {
    required String profileId,
  }) async {
    final sessionId = _remoteSessionId;
    final remotePath = file.path;
    if (sessionId == null || remotePath == null) {
      throw StateError('Remote SFTP session is not connected.');
    }
    if (_remoteProfileId != profileId) {
      throw StateError('This pane is now on a different server.');
    }
    // In place, so the file keeps its owner and permissions.
    final result = await _sftp.write(
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
  void notifyListeners() {
    // Async work may resume on a closed tab; notifying a disposed
    // ChangeNotifier would assert.
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _sftp.removeListener(_handleSftpChanged);
    _clearTransferTimer?.cancel();
    _remoteSearchDebounce?.cancel();
    final sessionId = _remoteSessionId;
    _remoteSessionId = null;
    if (sessionId != null) {
      unawaited(_sftp.close(sessionId));
    }
    super.dispose();
  }

  void _handleSftpChanged() {
    final sessionId = _remoteSessionId;
    if (sessionId == null) return;
    final session = _sftp.session(sessionId);
    if (session != null && session.isConnected) {
      _remoteDisconnectNotified = false;
      return;
    }
    // Only enter the disconnected state once per disconnect so the overlay
    // is not re-triggered on every SftpManager notification.
    if (_remoteDisconnectNotified) return;
    _remoteError ??= session == null
        ? 'SFTP session lost. Connection was closed.'
        : 'Remote connection lost.';
    _remoteStatus = 'disconnected';
    _remoteDisconnectNotified = true;
    notifyListeners();
  }

  /// A disconnect was detected and not yet shown; the page calls
  /// [clearDisconnectionNotification] after showing the snackbar.
  bool get shouldNotifyDisconnection =>
      isRemoteDisconnected && _remoteDisconnectNotified;

  /// Clears the disconnection notification flag so the snackbar is not
  /// shown again until a new disconnection is detected.
  void clearDisconnectionNotification() {
    _remoteDisconnectNotified = false;
  }

  /// Reconnect the SFTP session using the same profile and path.
  Future<void> reconnect(domain.SshProfile profile) async {
    final previousPath = _remotePath;
    await clearRemoteSession();
    // beginLoading() runs synchronously, so its notify and attachRemoteProfile's
    // setState land in one frame and the table header never flashes.
    beginLoading();
    await attachRemoteProfile(profile, previousPath);
  }

  /// Saves the password from the inline 'authenticating' form and connects.
  Future<void> submitPassword(String password) async {
    final profile = _pendingProfile;
    if (profile == null) return;
    // Set before the keychain await, so a scheduled sync during it can't
    // re-enter 'authenticating' and re-show the form.
    _pendingProfile = null;
    _passwordSubmitting = true;
    try {
      await _sftp.credentials.savePassword(profile.id, password);
      final resolvedProfile = profile.copyWith(credentialLabel: password);
      await attachRemoteProfile(resolvedProfile, _remotePath);
    } finally {
      _passwordSubmitting = false;
    }
  }

  /// Called when the user cancels the inline password form. Resets the
  /// remote status so the profile-selection UI returns.
  void cancelPasswordRequest() {
    if (_remoteStatus != 'authenticating') return;
    _pendingProfile = null;
    _didAuthenticate = false;
    _remoteStatus = 'idle';
    _loadingRemote = false;
    _remoteError = null;
    notifyListeners();
  }

  bool _isCurrentRemoteRequest(int token) {
    return token == _remoteLoadToken && _remoteSessionId != null;
  }

  bool _isCurrentRemoteSearch(int token) {
    return token == _remoteSearchToken && _remoteSessionId != null;
  }

  /// After [_remoteFailThreshold] consecutive failures the session is
  /// force-closed, so the disconnect overlay shows right away.
  void _recordRemoteFailure(String sessionId) {
    if (_remoteSessionId != sessionId) return;
    _remoteConsecutiveFailures++;
    if (_remoteConsecutiveFailures >= _remoteFailThreshold) {
      _remoteConsecutiveFailures = 0;
      _remoteStatus = 'disconnected';
      _remoteDisconnectNotified = true;
      _remoteError ??= 'Remote connection lost.';
      notifyListeners();
      // Force-close so SftpManager forgets the session and
      // isRemoteDisconnected becomes true, making the overlay appear.
      unawaited(_sftp.close(sessionId));
    }
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
        ? await _sftp.createDir(sessionId, remotePath)
        : await _sftp.createFile(sessionId, remotePath);
    result.fold((failure) => throw StateError(failure.message), (_) {});
    await _refreshCurrentRemoteDirectory();
  }

  Future<void> _downloadRemoteFile(
    String sessionId,
    String remotePath,
    String localPath, {
    void Function(TransferProgress progress)? onProgress,
  }) async {
    await File(localPath).parent.create(recursive: true);
    final result = await _sftp.download(
      sessionId,
      remotePath,
      localPath,
      onProgress: onProgress,
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
  }

  Future<void> _downloadRemoteDirectory(
    String sessionId,
    String remotePath,
    String localPath,
  ) async {
    await Directory(localPath).create(recursive: true);
    final result = await _sftp.list(sessionId, remotePath);
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
    String remoteDirectory, {
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final remotePath = _joinRemote(remoteDirectory, _basename(file.path));
    final result = await _sftp.upload(
      sessionId,
      file.path,
      remotePath,
      onProgress: onProgress,
    );
    result.fold((failure) => throw StateError(failure.message), (_) {});
  }

  Future<void> _uploadDirectory(
    String sessionId,
    Directory directory,
    String remoteDirectory,
  ) async {
    final remoteRoot = _joinRemote(remoteDirectory, _basename(directory.path));
    final createResult = await _sftp.createDir(sessionId, remoteRoot);
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
        ),
      ...entries.map(
        (entry) => SftpFileEntry(
          name: entry.name,
          path: entry.path,
          size: entry.isDirectory ? '-' : _formatFileSize(entry.sizeBytes),
          modified: _formatUnixDate(entry.modifiedUnixSeconds),
          type: entry.isDirectory ? 'dir' : 'file',
          folder: entry.isDirectory,
          chmodMode: _chmodText(entry.mode),
          sizeBytes: entry.isDirectory ? 0 : entry.sizeBytes,
          modifiedAt: DateTime.fromMillisecondsSinceEpoch(
            entry.modifiedUnixSeconds * 1000,
          ),
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
      chmodMode: _chmodText(entry.mode),
      sizeBytes: entry.isDirectory ? 0 : entry.sizeBytes,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        entry.modifiedUnixSeconds * 1000,
      ),
    );
  }

  static String? _chmodText(int mode) =>
      mode == 0 ? null : (mode & 0x1FF).toRadixString(8).padLeft(3, '0');
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
