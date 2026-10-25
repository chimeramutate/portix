import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:easy_stepper/easy_stepper.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/constants/file_extensions.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/utils/text_diff.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/data/services/sftp/local_edit_watcher.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/features/sftp/bloc/sftp_workspace_bloc.dart';
import 'package:portix/src/features/sftp/controller/sftp_workspace_controller.dart';
import 'package:portix/src/features/sftp/window/index.dart';
import 'package:portix/src/features/ssh_profiles/widget/gallery/profile_card.dart'
    show ProfileOsIcon;
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/auth_prompt_dialog.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/host_key_dialog.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/key_passphrase_dialog.dart';
import 'package:portix/src/sftp_client/sftp_manager.dart';
import 'package:skeletonizer/skeletonizer.dart';

part '../widget/sections/sftp_dialogs_section.dart';
part '../widget/sections/sftp_file_actions_section.dart';
part '../widget/sections/sftp_file_pane_section.dart';
part '../widget/sections/sftp_profile_gate_section.dart';
part '../widget/sections/sftp_tabs_section.dart';
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
  // Profile of the LEFT pane's own controller; null means Local. Either side
  // can be Local or any server, independently of the other.
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
  final LocalEditWatcher _editWatcher = LocalEditWatcher();

  /// Remote files open in an external editor, by local copy path.
  final Map<String, _EditedCopy> _editedCopies = {};

  /// Copies saved while their pane was offline, awaiting the reconnect.
  final Set<String> _pendingUploads = {};
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

  /// The controller behind the pane on [isLeft]: the per-tab controller on
  /// the right, an independent one with its own session on the left.
  SftpWorkspaceController _c(bool isLeft) =>
      isLeft ? _leftController : _controller;

  final _leftPaneKey = GlobalKey();
  final _rightPaneKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => showTutorialOnce(context, 'sftp', [
        (
          key: _rightPaneKey,
          title: 'Choose a server',
          body:
              'Pick an SSH profile in the right pane to open its remote files over SFTP.',
        ),
        (
          key: _leftPaneKey,
          title: 'Local files',
          body:
              'The left pane shows the files on this computer. Click the pane title to switch it to another server.',
        ),
        (
          key: _rightPaneKey,
          title: 'Drag & drop transfer',
          body:
              'Drag files or folders from one pane and drop them on the other to upload or download. Progress appears in the bottom-right corner.',
        ),
      ]),
    );
    _controller = _newController();
    _leftController = _newController();
    _tabs.add(_SftpTab(controller: _controller, label: 'SFTP 1'));

    // A duplicated window connects on its first build via [_scheduleRemoteSync],
    // mirroring the original tab's session.
    final initialProfile = widget.initialProfile;
    if (initialProfile != null) {
      _activeTab.selectedProfile = initialProfile;
      _remoteSyncKey = null;
    }
  }

  @override
  void dispose() {
    // No snackbar: the context is unusable during dispose.
    _discardEditedCopies((_) => true, notify: false);
    _editWatcher.dispose();
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

  SftpWorkspaceController _newController() {
    final sftpManager = sl<SftpManager>();
    return SftpWorkspaceController(
      sftpManager: sftpManager,
      resolveConnectFailure: (profile, error) async {
        final hostKey = await resolveRefusedHostKey(
          context,
          sl<ConnectionManager>(),
          profile,
        );
        if (hostKey != null) return hostKey;
        if (!mounted) return false;
        final prompts = await resolveAuthPrompts(
          context,
          sl<ConnectionManager>(),
          profile,
        );
        if (prompts != null) return prompts;
        if (!mounted) return false;
        return resolveKeyPassphrase(
          context,
          sftpManager.credentials,
          profile,
          error,
        );
      },
    )..addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _promptPendingUploads();
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
    // Re-attach whenever re-validation is due, which covers a channel that died
    // behind a live port 22. Skip without a profile or it reschedules every frame.
    final forceSync = profile != null && _controller.needsRevalidation;
    if (!forceSync && _remoteSyncKey == key) return;
    _remoteSyncKey = key;
    // Re-attach at the directory being viewed, not the profile's initial path.
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
    final forceSync = profile != null && _leftController.needsRevalidation;
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
    final newController = _newController();
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
      _discardEditedCopies((copy) => copy.controller == tab.controller);
      tab.controller
        ..removeListener(_handleControllerChanged)
        ..dispose();
      if (_tabs.isEmpty) {
        // Always keep at least one tab.
        final newController = _newController();
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

  /// Duplicates the tab at [index] with a fresh controller on the same
  /// profile and remote path.
  void _duplicateSftpTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final sourceTab = _tabs[index];
    final newController = _newController();
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

  /// Opens the tab at [index] in a detached SFTP window. A saved password is
  /// embedded in the profile so the child window doesn't re-prompt.
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
      final saved = await _controller.sftpManager.credentials.readPassword(
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
    // The password is asked at the 'authenticating' step, not before connecting.
    if (!mounted) return;
    // Before setState, so the first rebuild shows the step indicator instead of
    // flashing the file-table controls.
    _controller.beginLoading();
    setState(() {
      _activeTab.selectedProfile = profile;
      _remoteSyncKey = null;
    });
    context.read<SftpWorkspaceBloc>().add(SftpProfileSelected(profile));
  }

  Future<void> _selectLeftProfileForActiveTab(SshProfile? profile) async {
    if (!mounted) return;
    // Left-pane twin of the beginLoading() call in [_selectProfileForActiveTab].
    if (profile != null) {
      _leftController.beginLoading();
    }
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
            _showSnack(context, 'Download is only available for remote files.');
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
                  ? 'A folder with this name already exists locally. Downloading merges the folders and overwrites files with the same name.'
                  : 'A file with this name already exists locally. Replace overwrites the local file.',
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
              'Changing local permissions is not available here yet.',
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
      // Opening may throw while the session is down or on a stale context; show
      // a snack instead of crashing.
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
      _showSnack(context, 'The editor only opens files. Use Open for folders.');
      return;
    }

    final isCodeFile = isCodeFileName(file.name);

    // Non-code files open in the OS default app (Word for .docx, etc.).
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
      final extension = fileExtension(file.name);
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
        ? preferredLocalEditor(editors, preferCodeEditor: preferCodeEditor)
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
    final originalText = isRemote ? await readTextIfPossible(path) : null;

    try {
      await controller.openEditor(editor, path);
      if (!mounted) return;
      if (isRemote) {
        // Bound to this pane and server now: the active tab or the pane's
        // server may have changed by the time the copy is saved.
        _editedCopies[path] = (
          controller: controller,
          profileId: controller.remoteProfileId ?? '',
          serverName: controller.remoteProfileName,
          file: file,
          originalText: originalText,
        );
        await _editWatcher.watch(path, () => _onEditedCopySaved(path));
        _showSnack(
          context,
          'Opened a temporary copy in ${editor.name}. Save the file to be asked whether to upload it.',
        );
      } else {
        _showSnack(context, 'Opened ${file.name} in ${editor.name}.');
      }
    } catch (error) {
      if (!mounted) return;
      _showSnack(context, 'Failed to open ${editor.name}: $error');
    }
  }

  /// Whether [copy]'s pane is connected to the server it came from.
  bool _canUpload(_EditedCopy copy) =>
      copy.controller.isRemoteConnected &&
      copy.controller.remoteProfileId == copy.profileId;

  /// A save while offline (or with the pane on another server) waits for
  /// the reconnect instead of prompting for an upload that can only fail.
  /// The server is probed first: after a network drop the session still
  /// reads as connected for a while.
  Future<void> _onEditedCopySaved(String localPath) async {
    final copy = _editedCopies[localPath];
    if (copy == null || !mounted) return;
    if (_canUpload(copy) && await copy.controller.probeRemote()) {
      return _showRewritePrompt(copy, localPath);
    }
    _holdForReconnect(copy, localPath);
  }

  void _holdForReconnect(_EditedCopy copy, String localPath) {
    if (!_pendingUploads.add(localPath) || !mounted) return;
    _showSnack(
      context,
      'No connection to ${copy.serverName ?? 'the server'}: ${copy.file.name} is saved here and you will be asked to upload it after reconnecting.',
    );
  }

  /// Prompts for the saves held back by [_onEditedCopySaved] once their
  /// pane is back on their server.
  void _promptPendingUploads() {
    for (final path in [..._pendingUploads]) {
      final copy = _editedCopies[path];
      if (copy == null || !_canUpload(copy)) continue;
      _pendingUploads.remove(path);
      unawaited(_showRewritePrompt(copy, path));
    }
  }

  /// Stops watching the copies [where] picks and deletes their temp folders,
  /// except copies with an upload still pending: those stay on disk so the
  /// edits aren't lost.
  void _discardEditedCopies(
    bool Function(_EditedCopy copy) where, {
    bool notify = true,
  }) {
    final kept = <String>[];
    for (final MapEntry(key: path, value: copy) in [..._editedCopies.entries]) {
      if (!where(copy)) continue;
      _editWatcher.unwatch(path);
      _editedCopies.remove(path);
      if (_pendingUploads.remove(path)) {
        kept.add(path);
        continue;
      }
      // Each copy has its own temp folder (see editablePathFor).
      File(path).parent.delete(recursive: true).ignore();
    }
    if (kept.isNotEmpty && notify && mounted) {
      _showSnack(
        context,
        'Not uploaded, kept on this computer: ${kept.join(', ')}',
      );
    }
  }

  Future<void> _showRewritePrompt(_EditedCopy copy, String localPath) async {
    try {
      if (!mounted) return;
      final currentText = await readTextIfPossible(localPath);
      if (!mounted) return;
      final diff = buildTextDiff(copy.originalText, currentText);
      final shouldRewrite = await showDialog<bool>(
        context: context,
        builder: (context) => RewriteRemoteDialog(
          fileName: copy.file.path ?? copy.file.name,
          diff: diff,
          serverName: copy.serverName,
        ),
      );
      if (shouldRewrite == true) {
        await _rewriteEditedRemoteFile(copy, localPath);
      }
    } catch (error) {
      // Must not reach the file-watch timer's catch: it cancels the timer and
      // later saves silently stop showing the diff prompt.
      if (!mounted) return;
      _showSnack(context, 'Could not show rewrite preview: $error');
    }
  }

  Future<void> _rewriteEditedRemoteFile(
    _EditedCopy copy,
    String localPath,
  ) async {
    try {
      await copy.controller.rewriteRemoteFileFromLocal(
        copy.file,
        localPath,
        profileId: copy.profileId,
      );
      if (!mounted) return;
      _showSnack(context, 'Remote file rewritten: ${copy.file.name}');
    } catch (error) {
      // The connection may have dropped while the dialog was open.
      if (!await copy.controller.probeRemote()) {
        return _holdForReconnect(copy, localPath);
      }
      if (!mounted) return;
      _showSnack(context, 'Rewrite failed: $error');
    }
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
            // A detached window opens at the original tab's path.
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
                  // Tab strip, styled like the terminal tabs: flat tabs,
                  // the active one lifted with a accent top marker.
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            scrollDirection: Axis.horizontal,
                            itemCount: _tabs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 2),
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
                        const SizedBox(width: 4),
                        AppIconButton(
                          tooltip: 'New SFTP tab',
                          outlined: false,
                          icon: Icons.add_rounded,
                          onPressed: _addSftpTab,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
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
    // The LEFT pane is Local or its own server; the RIGHT pane keeps the tab
    // controller. Tapping the left header swaps in an inline profile gate.
    final leftPickGate = _leftPicking ? _leftPickGate(context, profiles) : null;
    Widget leftPane = leftSelectedProfile == null
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
    leftPane = KeyedSubtree(key: _leftPaneKey, child: leftPane);
    final rightPane = KeyedSubtree(
      key: _rightPaneKey,
      child: _buildRemoteFilePane(
        context,
        _controller,
        profiles,
        selectedProfile,
        isLeft: false,
        onTitleTap: null,
        pickGate: null,
      ),
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

  /// Inline Local-first profile gate for (re-)picking the LEFT pane's profile.
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
        // Same beginLoading() call as in [_selectProfileForActiveTab].
        _leftController.beginLoading();
        setState(() {
          _leftPicking = false;
          _leftSelectedProfile = profile;
          _leftSyncKey = null;
        });
        // SFTP only: the left controller connects via [_scheduleLeftSync]; don't
        // open a terminal session.
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
      isRemote: false,
      showSteps: false,
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
      onListPath: (p) => controller.readLocalDirectory(p),
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
                    // SFTP only: the pane's controller connects on the next sync; don't open
                    // a terminal session.
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
      onListPath: controller.listRemoteDirectoryRaw,
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
    // `isLeft` identifies which PANE received the drop.
    // `controller` = the pane that owns the *target* filesystem.
    final controller = _c(isLeft);
    if (transfer.fromRemote == targetRemote) return;

    if (targetRemote) {
      // Local → Remote: use the target pane's controller (it has the remote
      // session we want to upload into).
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
                ? 'A folder with this name already exists on the server. Uploading merges the folders and overwrites files with the same name.'
                : 'A file with this name already exists on the server. Replace overwrites the remote file.',
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

    // Remote → Local: download through whichever controller holds the remote
    // session (the drop target may be Local), into the target's localPath.
    final remoteController = _remoteControllerForTransfer(isLeft);
    if (remoteController == null) {
      if (mounted) {
        _showSnack(context, 'No active remote session to download from.');
      }
      return;
    }

    final destinationDir = controller.localPath;

    for (final entry in transfer.entries) {
      final localPath = '$destinationDir${Platform.pathSeparator}${entry.name}';
      final exists = controller.localTargetExists(localPath);
      if (exists) {
        final replace = await _confirmReplace(
          context,
          title: entry.folder ? 'Replace local folder?' : 'Replace local file?',
          name: entry.name,
          targetPath: localPath,
          message: entry.folder
              ? 'A folder with this name already exists locally. Downloading merges the folders and overwrites files with the same name.'
              : 'A file with this name already exists locally. Replace overwrites the local file.',
        );
        if (replace != true) return;
      }
      await _runSftpAction(
        context,
        () => remoteController.downloadRemoteEntry(
          entry,
          localPath,
          overwrite: exists,
        ),
      );
    }
    // Refresh the local pane so the downloaded files appear immediately.
    if (mounted) {
      unawaited(controller.loadLocalDirectory(destinationDir));
    }
  }

  /// The controller whose remote session started the drag: the pane opposite
  /// the drop target, or null when neither side is connected.
  SftpWorkspaceController? _remoteControllerForTransfer(bool targetIsLeft) {
    final sourceController = targetIsLeft ? _controller : _leftController;
    if (sourceController.hasRemoteSession &&
        !sourceController.isRemoteDisconnected) {
      return sourceController;
    }
    // Fall back to the target controller itself (e.g. both panes remote).
    final fallback = targetIsLeft ? _leftController : _controller;
    if (fallback.hasRemoteSession && !fallback.isRemoteDisconnected) {
      return fallback;
    }
    return null;
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

enum _SftpInlineCreateKind { folder, file }

/// A remote file's local copy open in an external editor, and the pane and
/// server its saves upload to.
typedef _EditedCopy = ({
  SftpWorkspaceController controller,
  String profileId,
  String? serverName,
  SftpFileEntry file,
  String? originalText,
});
