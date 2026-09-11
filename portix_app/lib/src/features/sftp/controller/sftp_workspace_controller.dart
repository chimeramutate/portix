import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
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
    String? tabId,
  }) : _connectionManager = connectionManager,
       _localFileBrowser = localFileBrowser ?? LocalFileBrowser(),
       _localEditorService = localEditorService ?? LocalEditorService(),
       tabId = tabId ?? const Uuid().v4() {
    _localPath = _localFileBrowser.defaultPath();
    unawaited(loadLocalDirectory(_localPath));
    _connectionManager.addListener(_handleConnectionManagerChanged);
  }

  /// Stable, unique identifier for the SFTP tab that owns this controller.
  /// Generated when the controller is created so every tab — even one that is
  /// closed and later re-opened — gets a fresh identity. This guarantees that a freshly created tab never picks up a stale SFTP session left behind by
  /// a previously closed tab, and that disconnect notifications fired for a
  /// closed tab never bleed into a new one.
  final String tabId;
  final ConnectionManager _connectionManager;

  /// Public accessor for the underlying connection manager, used by the
  /// workspace page to resolve saved passwords for duplicate-window flows.
  ConnectionManager get connectionManager => _connectionManager;
  final LocalFileBrowser _localFileBrowser;
  final LocalEditorService _localEditorService;

  /// True once [dispose] has run. The controller starts an in-flight
  /// `loadLocalDirectory` in its constructor and `attachRemoteProfile` awaits
  /// `ConnectionManager.connectSftp`, so those async ops can resume *after*
  /// the owning tab/page is closed and the controller is disposed. Guarding
  /// [notifyListeners] with this flag lets such resumes no-op instead of
  /// tripping Flutter's "A SftpWorkspaceController was used after being
  /// disposed" ChangeNotifier assert. This touches no SSH/auth logic.
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
  String? _remoteProfileName;

  /// Profile pending password submission (when authMethod is password-based
  /// and no saved password exists). Used by [submitPassword] to complete
  /// the connection once the inline form collects a password.
  domain.SshProfile? _pendingProfile;

  /// True while [submitPassword] is awaiting `saveProfilePassword` so that
  /// scheduled-sync callbacks (from the page's build-phase
  /// `_scheduleLeftSync` / `_scheduleRemoteSync`) can't re-enter the
  /// 'authenticating' state with the *original* (password-less) profile.
  ///
  /// Without this guard there is a race: `submitPassword` clears
  /// `_pendingProfile` and then `await`s `saveProfilePassword` (a platform
  /// channel round-trip to the secure keychain). During that suspension a
  /// post-frame callback fires `attachRemoteProfile(originalProfile)` which
  /// sees no saved password yet (`hasSavedPassword` → false), re-enters
  /// 'authenticating', re-sets `_pendingProfile`, and makes the inline
  /// password form re-appear — exactly the "password input comes back" bug.
  ///
  /// The flag is scoped to the auth-check block only, so
  /// `submitPassword`'s own `attachRemoteProfile(resolvedProfile)` — which
  /// carries the password in `credentialLabel` and therefore skips the auth
  /// check entirely — is never blocked by it.
  bool _passwordSubmitting = false;

  /// Exposed for the UI to read the profile currently awaiting password
  /// input, so it can show a contextual dialog.
  domain.SshProfile? get pendingProfile => _pendingProfile;

  /// True once the 'authenticating' step has been visited. Keeps the step
  /// indicator at 4 steps even after transitioning to 'connecting'/'listing'
  /// so the completed ✓ marks for "Pick profile" and "Loading" remain visible.
  bool _didAuthenticate = false;
  // Consecutive remote operation failures. When this hits the threshold the
  // session is force-closed so the disconnect overlay appears immediately
  // without waiting for the Rust keepalive timeout (~17 s).
  int _remoteConsecutiveFailures = 0;
  static const int _remoteFailThreshold = 2;
  int _remoteLoadToken = 0;
  int _remoteSearchToken = 0;
  Timer? _remoteSearchDebounce;

  // Guards against re-notifying while already disconnected so the
  // "connection lost" state is only entered once per disconnect event
  // instead of being re-triggered on every ConnectionManager notification
  // (heartbeat, status events, closeSession, etc.).
  bool _remoteDisconnectNotified = false;

  /// Whether an `attachRemoteProfile → connectSftp` call is currently in
  /// flight.  This replaces the old loading-guard that keyed on
  /// `_loadingRemote && (_remoteStatus == 'connecting' || 'listing')`,
  /// because [beginLoading] now pre-sets that same `_remoteStatus = 'connecting'`
  /// state — without starting `connectSftp` — to avoid a one-frame controls
  /// flash when a profile is selected.  The old guard would have tripped on
  /// that pre-set state and blocked the very connection it was meant to start.
  bool _connectInProgress = false;

  /// Whether the step indicator should be shown during remote loading.
  ///
  /// Set `true` at the start of an initial connection / reconnect (when
  /// `attachRemoteProfile` is called). Set `false` once the first directory
  /// listing completes — subsequent reloads via [loadRemoteDirectory] will
  /// therefore show *only* the skeleton table, without the step indicator.
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

  /// Whether the 4-step loading indicator should be used (with a dedicated
  /// "Loading" step for inline password input). This is true when the
  /// profile required a password that wasn't saved, and remains true after
  /// authentication succeeds so the step indicator shows all 4 steps with
  /// the first two marked as completed (✓).
  ///
  /// When the profile uses an SSH key or already has a saved password,
  /// only 3 steps are shown: Pick profile → Connecting... → Connected.
  bool get showPasswordStep =>
      _didAuthenticate || _remoteStatus == 'authenticating';

  /// Whether the step indicator should be displayed during remote loading.
  ///
  /// True during the initial connection / reconnect flow (set by
  /// [beginLoading] and [attachRemoteProfile]).  Becomes false once the
  /// first directory listing finishes — reloads via [loadRemoteDirectory]
  /// will then show only the skeleton table.
  bool get showConnectionSteps => _showConnectionSteps;

  bool get isRemoteDisconnected {
    if (_remoteSessionId == null) return false;
    final session = _connectionManager.sessions
        .where((s) => s.id == _remoteSessionId)
        .firstOrNull;
    if (session == null) return true;
    return session.status == ConnectionStatus.disconnected ||
        session.status == ConnectionStatus.error;
  }

  /// Marks the remote pane as loading **before** the async
  /// [attachRemoteProfile] call is scheduled (via addPostFrameCallback).
  ///
  /// Without this, there is a single-frame window after the profile is
  /// selected (via setState in [_selectProfileForActiveTab]) but before
  /// attachRemoteProfile sets _loadingRemote = true.  During that frame
  /// _loadingRemote is still false, so the file table — including the
  /// _TableHeader — flashes before the step indicator appears.  Calling
  /// this method before setState ensures loading = true on the very first
  /// rebuild, so only the step indicator is shown.
  void beginLoading() {
    if (_loadingRemote) return;
    _loadingRemote = true;
    _remoteStatus = 'connecting';
    _showConnectionSteps = true;
    _remoteError = null;
    notifyListeners();
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

  /// Returns true if the current session should be re-validated on the next
  /// visit to the SFTP view. This covers three cases:
  ///   1. There is no active session yet.
  ///   2. The session exists but is flagged as disconnected/error by the
  ///      ConnectionManager (detectable disconnect).
  ///   3. There is an outstanding remote error — the channel may be silently
  ///      dead even though TCP port-22 is still reachable (undetectable
  ///      disconnect: NAT timeout, SSH server idle timeout, etc.).
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

    // Check if we can reuse existing session - but only if it's still connected
    // and has no outstanding error (an error means the SFTP channel may be
    // silently dead even though TCP port-22 is still reachable).
    if (_remoteProfileId == profile.id && _remoteSessionId != null) {
      // Verify the session is still connected before reusing
      final session = _connectionManager.sessions
          .where((s) => s.id == _remoteSessionId)
          .firstOrNull;
      if (session != null &&
          session.status == ConnectionStatus.connected &&
          _remoteError == null) {
        if (_remoteRows.isEmpty && !_loadingRemote) {
          await loadRemoteDirectory(_remotePath);
        } else if (_remotePath != normalizedPath && _remoteRows.isEmpty) {
          await loadRemoteDirectory(normalizedPath);
        }
        // beginLoading() may have pre-emptively set _loadingRemote +
        // _remoteStatus = 'connecting' before this attachRemoteProfile
        // call fired (to avoid a one-frame controls flash).  If we reach
        // here with the session already connected and rows loaded, reset
        // to the connected state so the file table + controls show instead
        // of the step indicator getting stuck on 'connecting'.
        if (_loadingRemote && _remoteStatus == 'connecting') {
          _loadingRemote = false;
          _showConnectionSteps = false;
          _remoteStatus = 'connected';
          notifyListeners();
        }
        return;
      }
      // Session is stale, disconnected, or errored — do NOT auto-reconnect.
      // Show the disconnected overlay so the user can click "Reconnect"
      // manually instead of silently re-establishing the session on every
      // tab switch.
      _remoteError ??= 'Remote connection lost.';
      _remoteStatus = 'disconnected';
      _remoteDisconnectNotified = true;
      notifyListeners();
      return;
    }

    // If the profile is password-based but no usable password is stored
    // locally, enter the 'authenticating' state so the UI can collect a
    // password via an inline form. The connection is resumed in
    // [submitPassword] once the password is provided.
    if (profile.authMethod == domain.AuthMethod.password &&
        (profile.credentialLabel.trim().isEmpty ||
            profile.credentialLabel == 'Saved password')) {
      // Suppress scheduled-sync re-entry (see [_passwordSubmitting] docs)
      // while a password submission is in flight. submitPassword's own
      // attachRemoteProfile call carries the password in credentialLabel
      // and therefore never reaches this branch — it proceeds straight
      // to 'connecting' below.
      if (_passwordSubmitting) {
        return;
      }
      final hasSaved = await _connectionManager.hasSavedPassword(profile.id);
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

    // Prevent duplicate connection attempts while connectSftp is actually
    // in flight, or while a listing is already underway.
    //
    // [beginLoading] — called by the page before setState — sets
    // _remoteStatus = 'connecting' (without starting connectSftp) so the
    // step indicator shows immediately and the file-table controls don't
    // flash for one frame.  We must NOT block on that mere 'connecting'
    // status; only on _connectInProgress (set around the real connectSftp
    // call below) and on 'listing' (loadRemoteDirectory in progress,
    // already protected downstream by the session-reuse path or the
    // _remoteLoadToken mechanism).
    //
    // The 'authenticating' status is allowed through so [submitPassword]
    // can resume with the saved credential.
    if (_connectInProgress || _remoteStatus == 'listing') {
      return;
    }

    _remotePath = normalizedPath;
    _loadingRemote = true;
    _remoteStatus = 'connecting';
    _remoteError = null;
    notifyListeners();

    _connectInProgress = true;
    final result = await _connectionManager.connectSftp(
      _toManagerProfile(profile),
    );
    _connectInProgress = false;
    if (result.isLeft) {
      final failureStr = result.fold<String?>((f) => f.toString(), (_) => null);

      // If the profile is password-based and the error is auth-related,
      // re-enter the 'authenticating' state so the inline form can collect
      // a different password. The error is shown below the password field.
      if (profile.authMethod == domain.AuthMethod.password &&
          failureStr != null &&
          _isAuthError(failureStr)) {
        _pendingProfile = profile;
        _remoteStatus = 'authenticating';
        _loadingRemote = true;
        _remoteError = 'Authentication failed';
        notifyListeners();
        return;
      }

      // Timeout — surface a specific message so the user knows the
      // server didn't respond in time. Retry is possible via reconnect.
      if (failureStr != null && _isTimeoutError(failureStr)) {
        _loadingRemote = false;
        _remoteStatus = 'failed';
        _remoteError = 'Connection timeout';
        notifyListeners();
        return;
      }

      _loadingRemote = false;
      _remoteStatus = 'failed';
      _remoteError = failureStr ?? 'Unknown connection error.';
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
      await _connectionManager.closeSession(sessionId);
    }
  }

  /// Returns true when [error] looks like an authentication failure
  /// (wrong password, missing credentials, SSH auth rejection, etc.).
  /// Used to decide whether to re-prompt for a password inline instead of
  /// showing a generic "Connection failed" message.
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
      _recordRemoteFailure(sessionId);
      return null;
    }, (value) => value);
    if (resolvedPath == null) return;

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
        // First successful listing completes — subsequent
        // loadRemoteDirectory calls (reloads, folder navigation)
        // should show skeleton only, without the step indicator.
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

    final entriesResult = await _connectionManager.listRemoteDirectory(
      sessionId,
      path,
    );
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
    if (sessionId == null) {
      throw StateError('Remote SFTP session is not connected yet.');
    }
    if (remotePath == null || trimmed.isEmpty) return;
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
    final result = await _connectionManager.listRemoteDirectory(
      sessionId,
      path,
    );
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
    );
    final localPath =
        '${tempRoot.path}${Platform.pathSeparator}${localFileName}';
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
  void notifyListeners() {
    // No-op once disposed: in-flight async ops (the constructor's
    // loadLocalDirectory, attachRemoteProfile's connect await, etc.) may
    // resume on a closed tab and call notifyListeners — which would assert.
    // State they mutate is discarded along with the dead controller.
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _connectionManager.removeListener(_handleConnectionManagerChanged);
    _clearTransferTimer?.cancel();
    _remoteSearchDebounce?.cancel();
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
      if (!_remoteDisconnectNotified) {
        _remoteError = 'SFTP session lost. Connection was closed.';
        _remoteStatus = 'disconnected';
        _remoteDisconnectNotified = true;
        notifyListeners();
      }
      return;
    }
    final isDisconnected =
        session.status == ConnectionStatus.disconnected ||
        session.status == ConnectionStatus.error;
    if (isDisconnected) {
      // Only enter the disconnected state once per disconnect event so the
      // overlay is not re-triggered on every ConnectionManager notification.
      if (!_remoteDisconnectNotified) {
        _remoteError ??= 'Remote connection lost.';
        _remoteStatus = 'disconnected';
        _remoteDisconnectNotified = true;
        notifyListeners();
      }
    } else {
      // Session is connecting/connected — only re-arm the notification
      // when we reach a stable connected state, not during transient
      // "connecting" transitions that could re-trigger false notifications.
      if (session.status == ConnectionStatus.connected) {
        _remoteDisconnectNotified = false;
      }
    }
  }

  /// Whether the page should show a disconnection notification.
  ///
  /// Returns `true` when a disconnection has been detected by
  /// [_handleConnectionManagerChanged] (the flag is armed) and the
  /// connection is still considered disconnected. The page calls
  /// [clearDisconnectionNotification] after displaying the snackbar so the
  /// notification is not re-shown on subsequent change notifications.
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
    // beginLoading() sets _loadingRemote = true + _remoteStatus = 'connecting'
    // synchronously before the await attachRemoteProfile, so the page's
    // _pendingRebuild coalesces the notifyListeners from beginLoading and
    // the setState from attachRemoteProfile into a single frame — the
    // table header never flashes.
    beginLoading();
    await attachRemoteProfile(profile, previousPath);
  }

  /// Called when the user submits a password via the inline form shown
  /// when the remote status is 'authenticating'. Saves the password to
  /// secure storage, updates the profile, and proceeds with the SFTP
  /// connection.
  Future<void> submitPassword(String password) async {
    final profile = _pendingProfile;
    if (profile == null) return;
    // Clear _pendingProfile immediately so the UI no longer treats the
    // password form as awaiting input. _passwordSubmitting is set BEFORE
    // the save await so that any scheduled-sync callback that fires during
    // the secure-storage round-trip (saveProfilePassword) is suppressed by
    // the guard in attachRemoteProfile — preventing the 'authenticating'
    // state from being re-entered and the password form from re-appearing.
    _pendingProfile = null;
    _passwordSubmitting = true;
    try {
      await _connectionManager.saveProfilePassword(profile.id, password);
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

  /// Track consecutive remote failures. After [_remoteFailThreshold] failures,
  /// force-close the session so the disconnect overlay appears immediately
  /// instead of waiting for the Rust keepalive timeout (~17 s).
  void _recordRemoteFailure(String sessionId) {
    if (_remoteSessionId != sessionId) return;
    _remoteConsecutiveFailures++;
    if (_remoteConsecutiveFailures >= _remoteFailThreshold) {
      _remoteConsecutiveFailures = 0;
      _remoteStatus = 'disconnected';
      _remoteDisconnectNotified = true;
      _remoteError ??= 'Remote connection lost.';
      notifyListeners();
      // Force-close so ConnectionManager removes the session and
      // isRemoteDisconnected becomes true, making the overlay appear.
      unawaited(_connectionManager.closeSession(sessionId));
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
