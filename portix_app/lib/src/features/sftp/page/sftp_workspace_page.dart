import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:easy_stepper/easy_stepper.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/sftp/bloc/index.dart';
import 'package:portix/src/features/sftp/controller/index.dart';
import 'package:portix/src/features/sftp/window/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';
import 'package:skeletonizer/skeletonizer.dart';

part '../widget/sections/sftp_dialogs_section.dart';
part '../widget/sections/sftp_file_actions_section.dart';
part '../widget/sections/sftp_file_pane_section.dart';
part '../widget/sections/sftp_profile_gate_section.dart';
part '../widget/sections/sftp_transfer_queue_section.dart';

class SftpWorkspacePage extends StatefulWidget {
  const SftpWorkspacePage({
    super.key,
    this.initialProfile,
    this.initialRemotePath,
  });

  final SshProfile? initialProfile;
  final String? initialRemotePath;

  @override
  State<SftpWorkspacePage> createState() => _SftpWorkspacePageState();
}

class _SftpWorkspacePageState extends State<SftpWorkspacePage> {
  late SftpWorkspaceController _controller;
  late SftpWorkspaceController _leftController;
  // Profile attached to the LEFT pane's independent controller. `null` means
  // the left pane shows the Local filesystem — so the left side can be Local
  // (local-vs-server) or any server (server-vs-server), independently of the
  // right pane. The SSH controller code is unchanged and proven
  // session-isolated, so two controllers on the shared ConnectionManager never
  // cross-talk (see the two-controller independence test).
  SshProfile? _leftSelectedProfile;
  String? _leftSyncKey;
  // When true, the LEFT pane renders the inline Local-first profile gate
  // (search + A→Z/Z→A) in place of its content instead of a popup.
  bool _leftPicking = false;

  // Side ownership of the shared inline-create / inline-rename editor, so the
  // editor only renders on the pane that started it (otherwise two server
  // panes would both display it).
  bool? _inlineCreateLeft;
  bool? _renamingLeft;
  final TextEditingController _inlineCreateController = TextEditingController();
  final FocusNode _inlineCreateFocusNode = FocusNode(debugLabel: 'SFTP create');
  final TextEditingController _inlineRenameController = TextEditingController();
  final FocusNode _inlineRenameFocusNode = FocusNode(debugLabel: 'SFTP rename');
  final Map<String, _SftpLocalEditSession> _localEditSessions = {};
  final Set<String> _selectedLocalPaths = {};
  final Set<String> _selectedRemotePaths = {};
  String? _localSelectionAnchor;
  String? _remoteSelectionAnchor;
  String? _remoteSyncKey;
  _SftpInlineCreateKind? _inlineCreateKind;
  bool _inlineCreateRemote = true;
  SftpFileEntry? _renamingFile;
  bool _renamingRemote = true;

  // Multi-tab state
  final List<_SftpTab> _tabs = [];
  int _activeTabIndex = 0;
  String? _lastHandledSftpProfileId;

  _SftpTab get _activeTab => _tabs[_activeTabIndex];

  /// The controller backing the pane on [isLeft]. The right pane keeps the
  /// per-tab controller verbatim; the left pane uses a single independent
  /// controller that owns its own SSH/SFTP session (proven session-isolated
  /// by the two-controller test). Routing every handler through this keeps the
  /// right pane byte-for-byte current while the left pane reuses the identical,
  /// proven code paths.
  SftpWorkspaceController _c(bool isLeft) =>
      isLeft ? _leftController : _controller;

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
    _controller = SftpWorkspaceController(
      connectionManager: sl<ConnectionManager>(),
    )..addListener(_handleControllerChanged);
    _leftController = SftpWorkspaceController(
      connectionManager: sl<ConnectionManager>(),
    )..addListener(_handleControllerChanged);
    _tabs.add(_SftpTab(controller: _controller, label: 'SFTP 1'));

    // When opened as a detached window (duplicate as new window),
    // auto-select the profile and start connecting so the new
    // window mirrors the original's session state. The actual
    // connection is triggered on the first build via
    // [_scheduleRemoteSync], which calls [_controller.attachRemoteProfile].
    final initialProfile = widget.initialProfile;
    if (initialProfile != null) {
      _activeTab.selectedProfile = initialProfile;
      _remoteSyncKey = null;
    }
  }

  @override
  void dispose() {
    for (final editSession in _localEditSessions.values) {
      editSession.timer.cancel();
    }
    _inlineCreateController.dispose();
    _inlineCreateFocusNode.dispose();
    _inlineRenameController.dispose();
    _inlineRenameFocusNode.dispose();
    for (final tab in _tabs) {
      tab.controller
        ..removeListener(_handleControllerChanged)
        ..dispose();
    }
    _leftController
      ..removeListener(_handleControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _syncSelectionsWithRows();
    setState(() {});
  }

  void _syncSelectionsWithRows() {
    final localPaths = {
      ..._leftController.localRows,
      ..._controller.localRows,
    }.map((row) => row.path).whereType<String>().toSet();
    final remotePaths = {
      ..._leftController.remoteVisibleRows,
      ..._controller.remoteVisibleRows,
    }.map((row) => row.path).whereType<String>().toSet();
    _selectedLocalPaths.removeWhere((path) => !localPaths.contains(path));
    _selectedRemotePaths.removeWhere((path) => !remotePaths.contains(path));
    if (_localSelectionAnchor != null &&
        !localPaths.contains(_localSelectionAnchor)) {
      _localSelectionAnchor = null;
    }
    if (_remoteSelectionAnchor != null &&
        !remotePaths.contains(_remoteSelectionAnchor)) {
      _remoteSelectionAnchor = null;
    }
  }

  void _handleRowSelected(
    SftpFileEntry file,
    int index,
    bool isRemote,
    List<SftpFileEntry> rows,
  ) {
    if (file.name == '..') return;
    final path = file.path;
    if (path == null) return;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final additive =
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final range =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    final selected = isRemote ? _selectedRemotePaths : _selectedLocalPaths;
    final anchor = isRemote ? _remoteSelectionAnchor : _localSelectionAnchor;
    setState(() {
      if (range && anchor != null) {
        final anchorIndex = rows.indexWhere((row) => row.path == anchor);
        if (anchorIndex != -1) {
          if (!additive) selected.clear();
          final start = anchorIndex < index ? anchorIndex : index;
          final end = anchorIndex < index ? index : anchorIndex;
          for (var i = start; i <= end; i += 1) {
            final row = rows[i];
            final rowPath = row.path;
            if (row.name != '..' && rowPath != null) selected.add(rowPath);
          }
        }
      } else if (additive) {
        if (!selected.add(path)) selected.remove(path);
      } else {
        selected
          ..clear()
          ..add(path);
      }
      if (isRemote) {
        _remoteSelectionAnchor = path;
      } else {
        _localSelectionAnchor = path;
      }
    });
  }

  List<SftpFileEntry> _selectedTransferEntries(
    SftpFileEntry file,
    bool isRemote,
    bool isLeft,
  ) {
    final path = file.path;
    final selected = isRemote ? _selectedRemotePaths : _selectedLocalPaths;
    if (path == null || !selected.contains(path)) return [file];
    final controller = _c(isLeft);
    final rows = isRemote
        ? controller.remoteVisibleRows
        : controller.localVisibleRows;
    final entries = rows
        .where(
          (row) =>
              row.name != '..' &&
              row.path != null &&
              selected.contains(row.path),
        )
        .toList(growable: false);
    return entries.isEmpty ? [file] : entries;
  }

  void _scheduleRemoteSync(SshProfile? profile, String remotePath) {
    final key = profile == null ? 'none' : '${profile.id}|$remotePath';
    // Always re-attach when the controller signals that the current session
    // needs re-validation (no session, disconnected, or has a remote error).
    // This handles the "silent stale" case where the SSH/SFTP channel has
    // died but TCP port-22 is still reachable (so ConnectionStatus stays
    // "connected" and no disconnect event is ever fired).
    final forceSync = _controller.needsRevalidation;
    if (!forceSync && _remoteSyncKey == key) return;
    _remoteSyncKey = key;
    // When a session is already active, re-attach to the directory the user
    // is currently viewing rather than the profile's initial path. This keeps
    // a drop-triggered refresh (or any revalidation) from jumping back to the
    // profile's root/initial path.
    final targetPath = _controller.hasRemoteSession
        ? _controller.remotePath
        : remotePath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_controller.attachRemoteProfile(profile, targetPath));
    });
  }

  void _scheduleLeftSync(SshProfile? profile, String remotePath) {
    // Mirrors [_scheduleRemoteSync] for the independent left controller so the
    // left pane can browse its own server.
    final key = profile == null ? 'none' : '${profile.id}|$remotePath';
    final forceSync = _leftController.needsRevalidation;
    if (!forceSync && _leftSyncKey == key) return;
    _leftSyncKey = key;
    final targetPath = _leftController.hasRemoteSession
        ? _leftController.remotePath
        : remotePath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_leftController.attachRemoteProfile(profile, targetPath));
    });
  }

  void _addSftpTab() {
    final newController = SftpWorkspaceController(
      connectionManager: sl<ConnectionManager>(),
    )..addListener(_handleControllerChanged);
    setState(() {
      _tabs.add(
        _SftpTab(controller: newController, label: 'SFTP ${_tabs.length + 1}'),
      );
      _activeTabIndex = _tabs.length - 1;
      _controller = newController;
      _remoteSyncKey = null;
      _selectedLocalPaths.clear();
      _selectedRemotePaths.clear();
      _localSelectionAnchor = null;
      _remoteSelectionAnchor = null;
    });
  }

  void _closeSftpTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final wasLastTab = _tabs.length <= 1;
    setState(() {
      final tab = _tabs.removeAt(index);
      tab.controller
        ..removeListener(_handleControllerChanged)
        ..dispose();
      if (_tabs.isEmpty) {
        // When the last tab is closed, create a fresh blank tab so the
        // user always has at least one tab to work with.
        final newController = SftpWorkspaceController(
          connectionManager: sl<ConnectionManager>(),
        )..addListener(_handleControllerChanged);
        _tabs.add(_SftpTab(controller: newController, label: 'SFTP 1'));
      }
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      _controller = _tabs[_activeTabIndex].controller;
      // Closing a tab returns the LEFT pane to Local so it never keeps an
      // orphaned server session from the closed tab's context.
      _leftSelectedProfile = null;
      _leftSyncKey = null;
      _leftPicking = false;
      _remoteSyncKey = null;
      _selectedLocalPaths.clear();
      _selectedRemotePaths.clear();
      _localSelectionAnchor = null;
      _remoteSelectionAnchor = null;
    });
    // Drop the left pane's remote session so it returns to Local.
    unawaited(_leftController.clearRemoteSession());
    if (wasLastTab) {
      // Reset the active tab's profile after rebuilding.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _activeTab.selectedProfile = null;
      });
      context.read<SftpWorkspaceBloc>().add(const SftpProfileCleared());
    } else {
      // Sync the workspace-level profile state with the new active tab.
      final activeProfile = _activeTab.selectedProfile;
      if (activeProfile != null) {
        context.read<SftpWorkspaceBloc>().add(
          SftpProfileSelected(activeProfile),
        );
      } else {
        context.read<SftpWorkspaceBloc>().add(const SftpProfileCleared());
      }
    }
  }

  void _switchSftpTab(int index) {
    if (index == _activeTabIndex || index < 0 || index >= _tabs.length) return;
    setState(() {
      _activeTabIndex = index;
      _controller = _tabs[index].controller;
      _remoteSyncKey = null;
      _selectedLocalPaths.clear();
      _selectedRemotePaths.clear();
      _localSelectionAnchor = null;
      _remoteSelectionAnchor = null;
    });
  }

  /// Duplicates the tab at [index], creating a new tab with a fresh
  /// [SftpWorkspaceController] that points to the same profile and remote
  /// path as the source tab.
  void _duplicateSftpTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final sourceTab = _tabs[index];
    final newController = SftpWorkspaceController(
      connectionManager: sl<ConnectionManager>(),
    )..addListener(_handleControllerChanged);
    setState(() {
      _tabs.insert(
        index + 1,
        _SftpTab(
          controller: newController,
          label: 'SFTP ${_tabs.length + 1}',
          selectedProfile: sourceTab.selectedProfile,
        ),
      );
      _activeTabIndex = index + 1;
      _controller = newController;
      _remoteSyncKey = null;
      _selectedLocalPaths.clear();
      _selectedRemotePaths.clear();
      _localSelectionAnchor = null;
      _remoteSelectionAnchor = null;
    });
    final profile = sourceTab.selectedProfile;
    if (profile != null) {
      final remotePath = sourceTab.controller.hasRemoteSession
          ? sourceTab.controller.remotePath
          : _remotePathForProfile(profile);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_controller.attachRemoteProfile(profile, remotePath));
      });
    }
  }

  /// Opens the tab at [index] in a new detached SFTP window via
  /// [SftpWindowService.openSession].
  ///
  /// If the profile is password-based and a password is saved in secure
  /// storage, the password is resolved and embedded in the profile's
  /// `credentialLabel` so the child window can connect immediately
  /// without re-prompting.
  Future<void> _openInNewWindow(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    var profile = tab.selectedProfile;
    if (profile == null || !tab.controller.isRemoteConnected) return;
    final remotePath = tab.controller.remotePath;

    // Resolve saved password so the child window doesn't re-prompt.
    if (profile.authMethod == AuthMethod.password &&
        (profile.credentialLabel.trim().isEmpty ||
            profile.credentialLabel == 'Saved password')) {
      final saved = await _controller.connectionManager.readProfilePassword(
        profile.id,
      );
      if (saved != null && saved.trim().isNotEmpty) {
        profile = profile.copyWith(credentialLabel: saved);
      }
    }

    await SftpWindowService.openSession(
      profile: profile,
      remotePath: remotePath,
    );
  }

  Future<void> _selectProfileForActiveTab(
    BuildContext context,
    SshProfile profile,
  ) async {
    // The password (if needed) is now collected during the 4-step
    // connection flow — specifically at step 1 ('authenticating')
    // — rather than prompting before the connection starts. This
    // keeps the step indicator visible so the user can follow:
    //   0 Pick profile → 1 Loading (password) → 2 Connecting → 3 Connected
    if (!mounted) return;
    setState(() {
      _activeTab.selectedProfile = profile;
      _remoteSyncKey = null;
    });
    context.read<SftpWorkspaceBloc>().add(SftpProfileSelected(profile));
  }

  Future<void> _selectLeftProfileForActiveTab(SshProfile? profile) async {
    if (!mounted) return;
    setState(() {
      _leftSelectedProfile = profile;
      _leftSyncKey = null;
    });
    // The left controller owns its own session; no bloc event is needed.
    // The following build schedules the attach via [_scheduleLeftSync].
  }

  void _handleIncomingSftpProfile(
    SshSessionState sessionState,
    List<SshProfile> profiles,
  ) {
    // Only handle when user explicitly opened SFTP from gallery.
    if (sessionState.pendingTarget != SshSessionTarget.sftp) return;
    final targetId = sessionState.targetProfileId;
    if (targetId == null || targetId == _lastHandledSftpProfileId) return;
    _lastHandledSftpProfileId = targetId;

    final profile = profiles.where((p) => p.id == targetId).firstOrNull;
    if (profile == null) return;

    // Find existing tab with this profile.
    final existingIndex = _tabs.indexWhere(
      (tab) => tab.selectedProfile?.id == targetId,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (existingIndex >= 0) {
        // Switch to existing tab.
        _switchSftpTab(existingIndex);
      } else {
        // Select profile in current tab if it's empty, otherwise create new tab.
        if (_activeTab.selectedProfile == null) {
          unawaited(_selectProfileForActiveTab(context, profile));
        } else {
          _addSftpTab();
          unawaited(_selectProfileForActiveTab(context, profile));
        }
      }
    });
  }

  String _remotePathForProfile(SshProfile profile) {
    final startup = profile.startupCommand.trim();
    final cdMatch = RegExp(r'^cd\s+(.+)$').firstMatch(startup);
    if (cdMatch != null) return cdMatch.group(1)!.trim();
    final defaultPath = profile.defaultPath.trim();
    return defaultPath.isEmpty ? '~' : defaultPath;
  }

  Future<void> _handleFileAction(
    BuildContext context,
    _FileAction action,
    SftpFileEntry file,
    bool isRemote,
    bool isLeft,
  ) async {
    final controller = _c(isLeft);
    try {
      switch (action) {
        case _FileAction.open:
          if (file.folder) {
            if (isRemote) {
              await _runSftpAction(
                context,
                () => controller.loadRemoteDirectory(file.path ?? file.name),
                success: 'Opened ${file.name}',
              );
            } else {
              await controller.loadLocalDirectory(file.path ?? file.name);
            }
          } else {
            await _openFileWithEditor(
              context,
              file,
              isRemote,
              preferredDefault: true,
              isLeft: isLeft,
            );
          }
        case _FileAction.edit:
          await _openFileWithEditor(
            context,
            file,
            isRemote,
            preferredDefault: true,
            isLeft: isLeft,
          );
        case _FileAction.openWith:
          await _openFileWithEditor(
            context,
            file,
            isRemote,
            preferredDefault: false,
            isLeft: isLeft,
          );
        case _FileAction.download:
          if (!isRemote) {
            _showSnack(context, 'Download hanya tersedia untuk remote file.');
            return;
          }
          final selectedDir = await FilePicker.getDirectoryPath(
            dialogTitle: 'Download ${file.name} to...',
            initialDirectory: controller.defaultDownloadsPath,
          );
          if (selectedDir == null || !mounted) return;
          final localPath = '$selectedDir${Platform.pathSeparator}${file.name}';
          final exists = controller.localTargetExists(localPath);
          if (exists) {
            final replace = await _confirmReplace(
              context,
              title: file.folder
                  ? 'Replace local folder?'
                  : 'Replace local file?',
              name: file.name,
              targetPath: localPath,
              message: file.folder
                  ? 'Folder dengan nama yang sama sudah ada di local. Download akan merge folder dan rewrite file yang namanya sama.'
                  : 'File dengan nama yang sama sudah ada di local. Replace akan rewrite file local.',
            );
            if (replace != true) return;
          }
          await _runSftpAction(
            context,
            () => controller.downloadRemoteEntry(
              file,
              localPath,
              overwrite: exists,
            ),
            showErrorSnack: false,
          );
        case _FileAction.newFile:
          _startInlineCreate(
            _SftpInlineCreateKind.file,
            remote: isRemote,
            isLeft: isLeft,
          );
        case _FileAction.newFolder:
          _startInlineCreate(
            _SftpInlineCreateKind.folder,
            remote: isRemote,
            isLeft: isLeft,
          );
        case _FileAction.rename:
          _startInlineRename(file, remote: isRemote, isLeft: isLeft);
        case _FileAction.duplicate:
          if (!isRemote) {
            final newName = await _promptText(
              context,
              title: 'Duplicate ${file.name}',
              label: 'Copy name',
              initialValue: _duplicateName(file.name),
            );
            if (newName == null) return;
            await _runSftpAction(
              context,
              () => controller.duplicateLocalPath(file, newName),
              success: 'Duplicated ${file.name}',
            );
            return;
          }
          final newName = await _promptText(
            context,
            title: 'Duplicate ${file.name}',
            label: 'Copy name',
            initialValue: _duplicateName(file.name),
          );
          if (newName == null) return;
          await _runSftpAction(
            context,
            () => controller.duplicateRemotePath(file, newName),
            success: 'Duplicated ${file.name}',
          );
        case _FileAction.move:
          if (!isRemote) {
            final selectedDir = await FilePicker.getDirectoryPath(
              dialogTitle: 'Move ${file.name} to...',
              initialDirectory: controller.localPath,
            );
            if (selectedDir == null || !mounted) return;
            final targetPath =
                '$selectedDir${Platform.pathSeparator}${file.name}';
            await _runSftpAction(
              context,
              () => controller.moveLocalPath(file, targetPath),
              success: 'Moved ${file.name} to $selectedDir',
            );
            return;
          }
          final moveTarget = await _showRemoteFolderPicker(
            context,
            controller,
            title: 'Move ${file.name}',
            currentPath: controller.remotePath,
          );
          if (moveTarget == null || !mounted) return;
          final remoteDest = moveTarget.endsWith('/')
              ? '$moveTarget${file.name}'
              : '$moveTarget/${file.name}';
          await _runSftpAction(
            context,
            () => controller.moveRemotePath(file, remoteDest),
            success: 'Moved ${file.name} to $moveTarget',
          );
        case _FileAction.chmod:
          final mode = await _showChmodDialog(context, file);
          if (mode == null) return;
          if (!isRemote) {
            _showSnack(
              context,
              'Local chmod belum tersedia dari workspace ini.',
            );
            return;
          }
          await _runSftpAction(
            context,
            () => controller.chmodRemotePath(file, mode),
            success: 'Updated permissions for ${file.name}',
          );
        case _FileAction.delete:
          final confirmed = await _confirmDelete(context, file, isRemote);
          if (confirmed != true) return;
          await _runSftpAction(
            context,
            () => isRemote
                ? controller.deleteRemotePath(file)
                : controller.deleteLocalPath(file),
            success: 'Deleted ${file.name}',
          );
      }
    } catch (error) {
      // Opening/editing files may throw while the SFTP session is down
      // (e.g. `editablePathFor` raises StateError('Remote SFTP session is
      // not connected.')) or when showing the editor picker on a stale
      // context. Surface as a snack instead of tearing down the isolate.
      if (!mounted) return;
      _showSnack(context, 'Failed: $error');
    }
  }

  Future<void> _openFileWithEditor(
    BuildContext context,
    SftpFileEntry file,
    bool isRemote, {
    required bool preferredDefault,
    required bool isLeft,
  }) async {
    final controller = _c(isLeft);
    if (file.folder) {
      _showSnack(context, 'Editor hanya untuk file. Pakai Open untuk folder.');
      return;
    }

    final isCodeFile = _shouldOpenInCodeEditor(file.name);

    // For non-code files opened with default action,
    // always use the OS system default application (Word for .docx, etc.)
    if (!isCodeFile && preferredDefault) {
      final path = await controller.editablePathFor(file, isRemote);
      try {
        await controller.openWithSystemDefault(path);
        if (!mounted) return;
        if (isRemote) {
          _showSnack(context, 'Opened ${file.name} with system default app.');
        }
      } catch (error) {
        if (!mounted) return;
        _showSnack(context, 'Failed to open ${file.name}: $error');
      }
      return;
    }

    // Detect appropriate apps based on file type.
    final List<LocalEditor> editors;
    if (isCodeFile) {
      editors = await controller.detectLocalEditors();
    } else {
      final extension = _fileExtension(file.name);
      editors = await controller.detectAppsForExtension(extension);
    }
    if (!mounted) return;

    if (editors.isEmpty) {
      // No apps found — use system default directly.
      final path = await controller.editablePathFor(file, isRemote);
      try {
        await controller.openWithSystemDefault(path);
      } catch (error) {
        if (!mounted) return;
        _showSnack(context, 'Failed to open ${file.name}: $error');
      }
      return;
    }

    final preferCodeEditor = preferredDefault && isCodeFile;
    final editor = preferredDefault
        ? _preferredLocalEditor(editors, preferCodeEditor: preferCodeEditor)
        : await showModalBottomSheet<LocalEditor>(
            context: context,
            backgroundColor: AppColors.surface,
            builder: (context) => _EditorPickerSheet(editors: editors),
          );

    if (editor == null || !mounted) return;

    // Handle system default pseudo-command.
    if (editor.command == '_system_default_') {
      final path = await controller.editablePathFor(file, isRemote);
      try {
        await controller.openWithSystemDefault(path);
      } catch (error) {
        if (!mounted) return;
        _showSnack(context, 'Failed to open ${file.name}: $error');
      }
      return;
    }

    final path = await controller.editablePathFor(file, isRemote);
    final originalText = isRemote ? await _readFileTextIfPossible(path) : null;

    try {
      await controller.openEditor(editor, path);
      if (!mounted) return;
      if (isRemote) {
        await _watchLocalEditForRewrite(
          file: file,
          localPath: path,
          originalText: originalText,
          isLeft: isLeft,
        );
        _showSnack(
          context,
          'Opened temp copy in ${editor.name}. Save file untuk memunculkan rewrite prompt.',
        );
      } else {
        _showSnack(context, 'Opened ${file.name} in ${editor.name}.');
      }
    } catch (error) {
      if (!mounted) return;
      _showSnack(context, 'Failed to open ${editor.name}: $error');
    }
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
    required SftpFileEntry file,
    required String localPath,
    required String? originalText,
    required bool isLeft,
  }) async {
    final localFile = File(localPath);
    final stat = await localFile.stat();
    _localEditSessions.remove(localPath)?.timer.cancel();
    var lastPromptedAt = stat.modified;
    var promptOpen = false;
    final timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final currentStat = await localFile.stat();
        if (!currentStat.modified.isAfter(lastPromptedAt)) return;
        lastPromptedAt = currentStat.modified;
        if (promptOpen) return;
        promptOpen = true;
        await _showRewritePrompt(file, localPath, originalText, isLeft);
        promptOpen = false;
      } catch (_) {
        timer.cancel();
        _localEditSessions.remove(localPath);
      }
    });
    _localEditSessions[localPath] = _SftpLocalEditSession(
      remotePath: file.path ?? file.name,
      localPath: localPath,
      timer: timer,
      originalText: originalText,
    );
  }

  Future<void> _showRewritePrompt(
    SftpFileEntry file,
    String localPath,
    String? originalText,
    bool isLeft,
  ) async {
    try {
      if (!mounted) return;
      final currentText = await _readFileTextIfPossible(localPath);
      if (!mounted) return;
      final diff = _buildTextDiff(originalText, currentText);
      final shouldRewrite = await showDialog<bool>(
        context: context,
        builder: (context) =>
            _SftpRewriteRemoteDialog(fileName: file.name, diff: diff),
      );
      if (shouldRewrite == true) {
        await _rewriteEditedRemoteFile(file, localPath, isLeft);
      }
    } catch (error) {
      // A dialog/context glitch here must not propagate into the file-watch
      // timer's catch (which cancels the timer), otherwise subsequent saves
      // silently stop showing the diff/rewrite prompt.
      if (!mounted) return;
      _showSnack(context, 'Could not show rewrite preview: $error');
    }
  }

  Future<void> _rewriteEditedRemoteFile(
    SftpFileEntry file,
    String localPath,
    bool isLeft,
  ) async {
    final controller = _c(isLeft);
    try {
      await controller.rewriteRemoteFileFromLocal(file, localPath);
      if (!mounted) return;
      _showSnack(context, 'Remote file rewritten: ${file.name}');
    } catch (error) {
      if (!mounted) return;
      _showSnack(context, 'Rewrite failed: $error');
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

  _SftpTextDiff _buildTextDiff(String? before, String? after) {
    if (before == null || after == null) {
      return const _SftpTextDiff(
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

    return _SftpTextDiff(
      added: added,
      removed: removed,
      lines: preview.isEmpty ? const ['No textual diff detected.'] : preview,
    );
  }

  String _fileExtension(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) return '';
    return fileName.substring(index + 1).toLowerCase();
  }

  String _duplicateName(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == name.length - 1) {
      return '$name copy';
    }
    return '${name.substring(0, dotIndex)} copy${name.substring(dotIndex)}';
  }

  Future<String?> _showRemoteFolderPicker(
    BuildContext context,
    SftpWorkspaceController controller, {
    required String title,
    required String currentPath,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _RemoteFolderPickerDialog(
        title: title,
        initialPath: currentPath,
        connectionManager: controller,
      ),
    );
  }

  Future<int?> _showChmodDialog(
    BuildContext context,
    SftpFileEntry file,
  ) async {
    return showDialog<int>(
      context: context,
      builder: (context) => _ChmodDialog(file: file),
    );
  }

  void _showSnack(BuildContext context, String message) {
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

  Future<String?> _promptText(
    BuildContext context, {
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
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
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _runSftpAction(
    BuildContext context,
    Future<void> Function() action, {
    String? success,
    bool showErrorSnack = true,
  }) async {
    try {
      await action();
      if (!mounted) return;
      if (success != null) _showSnack(context, success);
    } catch (error) {
      if (!mounted) return;
      if (showErrorSnack) _showSnack(context, '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sshSessionBloc = context.read<SshSessionBloc>();
    return BlocProvider.value(
      value: sshSessionBloc,
      child: MultiBlocListener(
        listeners: [
          BlocListener<SshSessionBloc, SshSessionState>(
            bloc: sshSessionBloc,
            listenWhen: (previous, current) =>
                current.pendingTarget == SshSessionTarget.sftp &&
                previous.targetProfileId != current.targetProfileId &&
                current.targetProfileId != null,
            listener: (context, state) {
              final profiles = context
                  .read<SftpWorkspaceBloc>()
                  .state
                  .connectableProfiles;
              _handleIncomingSftpProfile(state, profiles);
            },
          ),
        ],
        child: BlocBuilder<SftpWorkspaceBloc, SftpWorkspaceState>(
          builder: (context, state) {
            final profiles = state.connectableProfiles;
            final activeTab = _activeTab;
            final selectedProfile = activeTab.selectedProfile;
            // In a detached window, use the initialRemotePath (the path the
            // original tab was viewing) instead of re-deriving from the
            // profile, so the duplicate window opens at the same location.
            final remotePath = selectedProfile != null
                ? (widget.initialRemotePath != null
                      ? widget.initialRemotePath!
                      : _remotePathForProfile(selectedProfile))
                : '~';
            _scheduleRemoteSync(selectedProfile, remotePath);

            final leftPath = _leftSelectedProfile == null
                ? '~'
                : _remotePathForProfile(_leftSelectedProfile!);
            _scheduleLeftSync(_leftSelectedProfile, leftPath);

            return Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  // Tab bar
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _tabs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final tab = _tabs[index];
                              final active = index == _activeTabIndex;
                              final profileName = tab.selectedProfile?.name;
                              final label = profileName != null
                                  ? profileName
                                  : tab.label;
                              return _SftpTabChip(
                                label: label,
                                active: active,
                                closable: true,
                                onTap: () => _switchSftpTab(index),
                                onClose: () => _closeSftpTab(index),
                                onDuplicate: tab.selectedProfile != null
                                    ? () => _duplicateSftpTab(index)
                                    : null,
                                onDuplicateWindow:
                                    (tab.selectedProfile != null &&
                                        tab.controller.isRemoteConnected)
                                    ? () => _openInNewWindow(index)
                                    : null,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'New SFTP tab',
                          onPressed: _addSftpTab,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Content
                  Expanded(
                    child: _buildSftpContent(
                      context,
                      profiles: profiles,
                      selectedProfile: selectedProfile,
                      remotePath: remotePath,
                      leftSelectedProfile: _leftSelectedProfile,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSftpContent(
    BuildContext context, {
    required List<SshProfile> profiles,
    required SshProfile? selectedProfile,
    required String remotePath,
    required SshProfile? leftSelectedProfile,
  }) {
    // The LEFT pane is independent: Local when no left profile is selected, or
    // whatever server the user picked for the left side. The RIGHT pane keeps
    // the original behavior verbatim (same controller) — zero regression on the
    // existing remote path. Tapping the LEFT pane's header swaps its content
    // area for an inline Local-first profile gate (search + A→Z/Z→A); picking a
    // profile attaches it to the left controller, choosing Local stays Local.
    // No popup is used for choosing the left profile.
    final leftPickGate = _leftPicking ? _leftPickGate(context, profiles) : null;
    final leftPane = leftSelectedProfile == null
        ? _buildLocalFilePane(
            context,
            _leftController,
            isLeft: true,
            onTitleTap: () => setState(() => _leftPicking = true),
            pickGate: leftPickGate,
          )
        : _buildRemoteFilePane(
            context,
            _leftController,
            profiles,
            leftSelectedProfile,
            isLeft: true,
            onTitleTap: () => setState(() => _leftPicking = true),
            pickGate: leftPickGate,
          );
    final rightPane = _buildRemoteFilePane(
      context,
      _controller,
      profiles,
      selectedProfile,
      isLeft: false,
      onTitleTap: null,
      pickGate: null,
    );

    final leftJobs = _leftController.transferJobs;
    final rightJobs = _controller.transferJobs;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 900;
                  if (narrow) {
                    return ListView(
                      children: [
                        SizedBox(height: 520, child: leftPane),
                        const SizedBox(height: 14),
                        SizedBox(height: 520, child: rightPane),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: leftPane),
                      const SizedBox(width: 14),
                      Expanded(child: rightPane),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        if (leftJobs.isNotEmpty || rightJobs.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            width: 380,
            child: _TransferQueue(
              jobs: [...leftJobs, ...rightJobs],
              onClose: () {
                _leftController.clearTransfers();
                _controller.clearTransfers();
              },
            ),
          ),
      ],
    );
  }

  /// Inline (non-popup) Local-first profile gate used to (re-)pick the LEFT
  /// pane's profile. Tapping a profile attaches it to the left controller;
  /// choosing Local keeps (or returns) the left pane on the local filesystem.
  Widget _leftPickGate(BuildContext context, List<SshProfile> profiles) {
    return _SftpProfileGate(
      profiles: profiles,
      includeLocal: true,
      localSelected: _leftSelectedProfile == null,
      onLocalSelected: () {
        setState(() {
          _leftPicking = false;
          _leftSelectedProfile = null;
          _leftSyncKey = null;
        });
        unawaited(_leftController.clearRemoteSession());
      },
      onSelected: (profile) {
        setState(() {
          _leftPicking = false;
          _leftSelectedProfile = profile;
          _leftSyncKey = null;
        });
        // Klik profil di picker kiri: hanya buka SFTP ke pane kiri.
        // Koneksi SFTP dilakukan oleh SftpWorkspaceController melalui
        // _scheduleLeftSync -> attachRemoteProfile -> connectSftp.
        // Jangan membuka sesi SSH terminal (remoteFolder) karena picker
        // ini khusus SFTP, bukan terminal.
      },
    );
  }

  Widget _buildLocalFilePane(
    BuildContext context,
    SftpWorkspaceController controller, {
    required bool isLeft,
    VoidCallback? onTitleTap,
    Widget? pickGate,
  }) {
    return _FilePane(
      title: 'Local',
      path: controller.localPath,
      items: controller.localVisibleRows,
      countLabel: controller.loadingLocal
          ? 'Loading'
          : controller.localSearchActive
          ? '${controller.localVisibleItemCount} found'
          : '${controller.localItemCount} items',
      footerLeft: controller.localError == null
          ? '${controller.localItemCount} items'
          : 'Local unavailable',
      footerRight: controller.localError ?? '',
      loading: controller.loadingLocal,
      error: controller.localError,
      findQuery: controller.localSearchQuery,
      findActive: controller.localSearchActive,
      onFindSubmitted: controller.searchLocal,
      onFindCleared: controller.clearLocalSearch,
      onTitleTap: onTitleTap,
      contentOverride: pickGate,
      onCreateFileRequested: () => _startInlineCreate(
        _SftpInlineCreateKind.file,
        remote: false,
        isLeft: isLeft,
      ),
      onCreateFolderRequested: () => _startInlineCreate(
        _SftpInlineCreateKind.folder,
        remote: false,
        isLeft: isLeft,
      ),
      inlineCreateKind: !_inlineCreateRemote && _inlineCreateLeft == isLeft
          ? _inlineCreateKind
          : null,
      inlineCreateController: _inlineCreateController,
      inlineCreateFocusNode: _inlineCreateFocusNode,
      onInlineCreateSubmit: _submitInlineCreate,
      onInlineCreateCancel: _cancelInlineCreate,
      inlineRenameFile: !_renamingRemote && _renamingLeft == isLeft
          ? _renamingFile
          : null,
      inlineRenameController: _inlineRenameController,
      inlineRenameFocusNode: _inlineRenameFocusNode,
      onInlineRenameSubmit: _submitInlineRename,
      onInlineRenameCancel: _cancelInlineRename,
      onRefreshRequested: () =>
          unawaited(controller.loadLocalDirectory(controller.localPath)),
      onPathSubmitted: controller.loadLocalDirectory,
      onOpenFolder: (file) =>
          controller.loadLocalDirectory(file.path ?? file.name),
      selectedPaths: _selectedLocalPaths,
      onItemSelected: (file, index, rows) =>
          _handleRowSelected(file, index, false, rows),
      selectedTransferEntries: (file) =>
          _selectedTransferEntries(file, false, isLeft),
      onTransferDropped: (transfer) =>
          unawaited(_handleDroppedTransfer(context, transfer, false, isLeft)),
      onFileAction: (action, file) =>
          _handleFileAction(context, action, file, false, isLeft),
    );
  }

  Widget _buildRemoteFilePane(
    BuildContext context,
    SftpWorkspaceController controller,
    List<SshProfile> profiles,
    SshProfile? selectedProfile, {
    required bool isLeft,
    VoidCallback? onTitleTap,
    Widget? pickGate,
  }) {
    return _FilePane(
      title: selectedProfile?.name ?? 'Remote',
      path: controller.remotePath,
      items: selectedProfile == null ? const [] : controller.remoteVisibleRows,
      countLabel: selectedProfile == null
          ? 'No session'
          : controller.searchingRemote
          ? 'Searching'
          : controller.remoteSearchActive
          ? '${controller.remoteVisibleItemCount} found'
          : controller.loadingRemote
          ? 'Loading'
          : '${controller.remoteItemCount} items',
      footerLeft: selectedProfile == null
          ? 'No remote session'
          : controller.remoteError == null
          ? '${controller.remoteItemCount} items'
          : 'Remote unavailable',
      footerRight: controller.remoteError ?? '',
      loading: controller.loadingRemote,
      error: controller.remoteError,
      isRemote: true,
      onTitleTap: onTitleTap,
      showActions: selectedProfile != null && !controller.isRemoteDisconnected,
      showPathBar: selectedProfile != null && !controller.isRemoteDisconnected,
      statusTitle: controller.remoteStatusTitle,
      statusMessage: controller.remoteStatusMessage,
      remoteStatus: controller.remoteStatus,
      showSteps: controller.showConnectionSteps,
      showPasswordStep: controller.showPasswordStep,
      remoteOsIconAsset: selectedProfile?.osIconAsset,
      profileName: selectedProfile?.name,
      findQuery: controller.remoteSearchQuery,
      findBase: controller.remoteSearchBase,
      findActive: controller.remoteSearchActive,
      findError: controller.remoteSearchError,
      findSearching: controller.searchingRemote,
      onFindSubmitted:
          selectedProfile == null || controller.isRemoteDisconnected
          ? null
          : (query) => unawaited(controller.searchRemote(query)),
      onFindCleared: selectedProfile == null || controller.isRemoteDisconnected
          ? null
          : controller.clearRemoteSearch,
      inputForm: controller.showConnectionSteps && controller.showPasswordStep
          ? _SftpSecurePasswordInput(
              profile: selectedProfile,
              onSubmit: (password) => controller.submitPassword(password),
              errorText: controller.remoteError,
            )
          : null,
      onCreateFileRequested: selectedProfile == null
          ? null
          : () => _startInlineCreate(
              _SftpInlineCreateKind.file,
              remote: true,
              isLeft: isLeft,
            ),
      onCreateFolderRequested: selectedProfile == null
          ? null
          : () => _startInlineCreate(
              _SftpInlineCreateKind.folder,
              remote: true,
              isLeft: isLeft,
            ),
      inlineCreateKind:
          selectedProfile == null ||
              !_inlineCreateRemote ||
              _inlineCreateLeft != isLeft
          ? null
          : _inlineCreateKind,
      inlineCreateController: _inlineCreateController,
      inlineCreateFocusNode: _inlineCreateFocusNode,
      onInlineCreateSubmit: _submitInlineCreate,
      onInlineCreateCancel: _cancelInlineCreate,
      inlineRenameFile: !_renamingRemote || _renamingLeft != isLeft
          ? null
          : _renamingFile,
      inlineRenameController: _inlineRenameController,
      inlineRenameFocusNode: _inlineRenameFocusNode,
      onInlineRenameSubmit: _submitInlineRename,
      onInlineRenameCancel: _cancelInlineRename,
      onRefreshRequested: selectedProfile == null
          ? null
          : () => unawaited(
              controller.loadRemoteDirectory(controller.remotePath),
            ),
      contentOverride:
          pickGate ??
          (selectedProfile == null
              ? _SftpProfileGate(
                  profiles: profiles,
                  onSelected: (profile) {
                    if (isLeft) {
                      unawaited(_selectLeftProfileForActiveTab(profile));
                    } else {
                      unawaited(_selectProfileForActiveTab(context, profile));
                    }
                    // Klik profil di picker: hanya buka SFTP ke pane yang
                    // bersangkutan. Koneksi SFTP dilakukan oleh
                    // SftpWorkspaceController melalui _scheduleRemoteSync /
                    // _scheduleLeftSync -> attachRemoteProfile -> connectSftp.
                    // Jangan membuka sesi SSH terminal (remoteFolder) karena
                    // picker ini khusus SFTP, bukan terminal.
                  },
                )
              : controller.isRemoteDisconnected
              ? _SftpDisconnectedOverlay(
                  onReconnect: () =>
                      unawaited(controller.reconnect(selectedProfile)),
                  errorMessage: controller.remoteError,
                )
              : null),
      onPathSubmitted: controller.loadRemoteDirectory,
      onOpenFolder: (file) =>
          controller.loadRemoteDirectory(file.path ?? file.name),
      selectedPaths: _selectedRemotePaths,
      onItemSelected: (file, index, rows) =>
          _handleRowSelected(file, index, true, rows),
      selectedTransferEntries: (file) =>
          _selectedTransferEntries(file, true, isLeft),
      onTransferDropped: (transfer) =>
          unawaited(_handleDroppedTransfer(context, transfer, true, isLeft)),
      onFileAction: (action, file) =>
          _handleFileAction(context, action, file, true, isLeft),
    );
  }

  void _startInlineCreate(
    _SftpInlineCreateKind kind, {
    required bool remote,
    required bool isLeft,
  }) {
    setState(() {
      _clearInlineRename();
      _inlineCreateKind = kind;
      _inlineCreateRemote = remote;
      _inlineCreateLeft = isLeft;
      _inlineCreateController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _inlineCreateKind != kind) return;
      _inlineCreateFocusNode.requestFocus();
    });
  }

  void _cancelInlineCreate() {
    setState(() {
      _inlineCreateKind = null;
      _inlineCreateLeft = null;
      _inlineCreateController.clear();
    });
  }

  void _startInlineRename(
    SftpFileEntry file, {
    required bool remote,
    required bool isLeft,
  }) {
    if (file.name == '..') return;
    setState(() {
      _inlineCreateKind = null;
      _inlineCreateLeft = null;
      _renamingFile = file;
      _renamingRemote = remote;
      _renamingLeft = isLeft;
      _inlineRenameController.text = file.name;
      final selected = remote ? _selectedRemotePaths : _selectedLocalPaths;
      final path = file.path;
      if (path != null) {
        selected
          ..clear()
          ..add(path);
        if (remote) {
          _remoteSelectionAnchor = path;
        } else {
          _localSelectionAnchor = path;
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _renamingFile?.path != file.path) return;
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

  void _clearInlineRename() {
    _renamingFile = null;
    _renamingLeft = null;
    _inlineRenameController.clear();
  }

  Future<void> _submitInlineRename() async {
    final file = _renamingFile;
    final newName = _inlineRenameController.text.trim();
    if (file == null) return;
    if (newName.isEmpty || newName == file.name) {
      _cancelInlineRename();
      return;
    }
    final remote = _renamingRemote;
    final controller = _c(_renamingLeft ?? false);
    await _runSftpAction(
      context,
      () => remote
          ? controller.renameRemotePath(file, newName)
          : controller.renameLocalPath(file, newName),
      success: 'Renamed ${file.name}',
    );
    if (mounted) _cancelInlineRename();
  }

  Future<void> _submitInlineCreate() async {
    final kind = _inlineCreateKind;
    final name = _inlineCreateController.text.trim();
    if (kind == null) return;
    if (name.isEmpty) {
      _cancelInlineCreate();
      return;
    }
    final controller = _c(_inlineCreateLeft ?? false);
    await _runSftpAction(
      context,
      () {
        if (_inlineCreateRemote) {
          return kind == _SftpInlineCreateKind.folder
              ? controller.createRemoteFolder(name)
              : controller.createRemoteFile(name);
        }
        return kind == _SftpInlineCreateKind.folder
            ? controller.createLocalFolder(name)
            : controller.createLocalFile(name);
      },
      success: kind == _SftpInlineCreateKind.folder
          ? 'Created folder $name'
          : 'Created file $name',
    );
    if (mounted) _cancelInlineCreate();
  }

  Future<void> _handleDroppedTransfer(
    BuildContext context,
    SftpFileTransfer transfer,
    bool targetRemote,
    bool isLeft,
  ) async {
    final controller = _c(isLeft);
    if (transfer.fromRemote == targetRemote) return;
    if (targetRemote) {
      for (final entry in transfer.entries) {
        final localPath = entry.path;
        if (localPath == null) continue;
        final targetPath = controller.remoteUploadTargetPath(localPath);
        final exists = controller.remoteTargetExistsForLocalPath(localPath);
        if (exists) {
          final replace = await _confirmReplace(
            context,
            title: entry.folder
                ? 'Replace remote folder?'
                : 'Replace remote file?',
            name: entry.name,
            targetPath: targetPath,
            message: entry.folder
                ? 'Folder dengan nama yang sama sudah ada di remote. Upload akan merge folder dan rewrite file yang namanya sama.'
                : 'File dengan nama yang sama sudah ada di remote. Replace akan rewrite file remote.',
          );
          if (replace != true) return;
        }
        await _runSftpAction(
          context,
          () => controller.uploadLocalPath(localPath, overwrite: exists),
        );
      }
      return;
    }
    for (final entry in transfer.entries) {
      final localPath =
          '${controller.localPath}${Platform.pathSeparator}${entry.name}';
      final exists = controller.localTargetExists(localPath);
      if (exists) {
        final replace = await _confirmReplace(
          context,
          title: entry.folder ? 'Replace local folder?' : 'Replace local file?',
          name: entry.name,
          targetPath: localPath,
          message: entry.folder
              ? 'Folder dengan nama yang sama sudah ada di local. Download akan merge folder dan rewrite file yang namanya sama.'
              : 'File dengan nama yang sama sudah ada di local. Replace akan rewrite file local.',
        );
        if (replace != true) return;
      }
      await _runSftpAction(
        context,
        () =>
            controller.downloadRemoteEntry(entry, localPath, overwrite: exists),
      );
    }
  }

  Future<bool?> _confirmReplace(
    BuildContext context, {
    required String title,
    required String name,
    required String targetPath,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: portixTitle(15)),
              const SizedBox(height: 8),
              Text(message, style: portixMuted(12)),
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
                  targetPath,
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
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(
    BuildContext context,
    SftpFileEntry file,
    bool isRemote,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete ${file.folder ? 'folder' : 'file'}?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(file.name, style: portixTitle(15)),
              const SizedBox(height: 8),
              Text(
                isRemote
                    ? 'This will delete the remote item permanently.'
                    : 'This will delete the local item permanently.',
                style: portixMuted(12),
              ),
              if (file.path != null) ...[
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
                    file.path!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: portixMuted(11),
                  ),
                ),
              ],
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
}

class _SftpLocalEditSession {
  const _SftpLocalEditSession({
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

class _SftpTextDiff {
  const _SftpTextDiff({
    required this.added,
    required this.removed,
    required this.lines,
  });

  final int added;
  final int removed;
  final List<String> lines;
}

class _SftpRewriteRemoteDialog extends StatelessWidget {
  const _SftpRewriteRemoteDialog({required this.fileName, required this.diff});

  final String fileName;
  final _SftpTextDiff diff;

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
                  _SftpDiffBadge(
                    label: '+${diff.added}',
                    color: AppColors.green,
                  ),
                  const SizedBox(width: 8),
                  _SftpDiffBadge(
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
                      final isSeparator = line.trim() == '···';
                      final color = isAdd
                          ? AppColors.green
                          : isRemove
                          ? AppColors.danger
                          : isSeparator
                          ? AppColors.muted.withValues(alpha: .5)
                          : AppColors.text.withValues(alpha: .6);
                      final bgColor = isAdd
                          ? AppColors.green.withValues(alpha: .07)
                          : isRemove
                          ? AppColors.danger.withValues(alpha: .07)
                          : Colors.transparent;
                      return Container(
                        color: bgColor,
                        child: Text(
                          line,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            height: 1.4,
                            fontFamily: 'monospace',
                            fontWeight: (isAdd || isRemove)
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
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

class _SftpDiffBadge extends StatelessWidget {
  const _SftpDiffBadge({required this.label, required this.color});

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

enum _SftpInlineCreateKind { folder, file }

class _SftpTab {
  _SftpTab({
    required this.controller,
    required this.label,
    this.selectedProfile,
  });

  final SftpWorkspaceController controller;
  final String label;
  SshProfile? selectedProfile;
}

class _SftpTabChip extends StatelessWidget {
  const _SftpTabChip({
    required this.label,
    required this.active,
    required this.closable,
    required this.onTap,
    required this.onClose,
    this.onDuplicate,
    this.onDuplicateWindow,
  });

  final String label;
  final bool active;
  final bool closable;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDuplicateWindow;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (details) => _showContextMenu(context, details),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF143B63) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primaryBlue : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_open_rounded,
              size: 14,
              color: AppColors.cyan,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                color: active ? AppColors.text : AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (closable) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClose,
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, TapDownDetails details) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox != null
        ? renderBox.localToGlobal(details.localPosition)
        : details.localPosition;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx,
        offset.dy,
      ),
      items: [
        if (onDuplicate != null)
          PopupMenuItem(
            onTap: onDuplicate,
            child: const Row(
              children: [
                Icon(Icons.content_copy_rounded, size: 16),
                SizedBox(width: 8),
                Text('Duplicate tab'),
              ],
            ),
          ),
        if (onDuplicateWindow != null)
          PopupMenuItem(
            onTap: onDuplicateWindow,
            child: const Row(
              children: [
                Icon(Icons.open_in_new_rounded, size: 16),
                SizedBox(width: 8),
                Text('Duplicate as new window'),
              ],
            ),
          ),
        if (closable)
          PopupMenuItem(
            onTap: onClose,
            child: const Row(
              children: [
                Icon(Icons.close_rounded, size: 16),
                SizedBox(width: 8),
                Text('Close tab'),
              ],
            ),
          ),
      ],
    );
  }
}

class _RemoteFolderPickerDialog extends StatefulWidget {
  const _RemoteFolderPickerDialog({
    required this.title,
    required this.initialPath,
    required this.connectionManager,
  });

  final String title;
  final String initialPath;
  final SftpWorkspaceController connectionManager;

  @override
  State<_RemoteFolderPickerDialog> createState() =>
      _RemoteFolderPickerDialogState();
}

class _RemoteFolderPickerDialogState extends State<_RemoteFolderPickerDialog> {
  late String _currentPath;
  List<SftpFileEntry> _entries = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Use the controller's connection to list remote directories.
      final entries = await widget.connectionManager.listRemoteDirectoryRaw(
        _currentPath,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries.where((e) => e.name != '..').toList(growable: false)
          ..sort((a, b) {
            if (a.folder != b.folder) return a.folder ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _navigateInto(String folderName) {
    setState(() {
      _currentPath = _currentPath.endsWith('/')
          ? '$_currentPath$folderName'
          : '$_currentPath/$folderName';
    });
    _loadFolders();
  }

  void _navigateUp() {
    final parts = _currentPath.split('/')..removeWhere((p) => p.isEmpty);
    if (parts.length <= 1) {
      setState(() => _currentPath = '/');
    } else {
      parts.removeLast();
      setState(() => _currentPath = '/${parts.join('/')}');
    }
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.drive_file_move_rounded,
                    color: AppColors.cyan,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.title, style: portixTitle(16))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Current path bar
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_rounded,
                      size: 16,
                      color: AppColors.cyan,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentPath,
                        overflow: TextOverflow.ellipsis,
                        style: portixTitle(12),
                      ),
                    ),
                    if (_currentPath != '/')
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        onPressed: _navigateUp,
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          size: 16,
                          color: AppColors.muted,
                        ),
                        tooltip: 'Go up',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Folder list
              Expanded(
                child: _loading
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: portixMuted(12),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _entries.isEmpty
                    ? Center(
                        child: Text('Empty directory', style: portixMuted(12)),
                      )
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final isFolder = entry.folder;
                          return InkWell(
                            onTap: isFolder
                                ? () => _navigateInto(entry.name)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isFolder
                                        ? Icons.folder_rounded
                                        : Icons.insert_drive_file_outlined,
                                    color: isFolder
                                        ? AppColors.amber
                                        : AppColors.muted,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      entry.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: isFolder
                                          ? portixTitle(13)
                                          : portixMuted(12),
                                    ),
                                  ),
                                  if (isFolder)
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.muted,
                                      size: 18,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 14),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_currentPath),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Move here'),
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
