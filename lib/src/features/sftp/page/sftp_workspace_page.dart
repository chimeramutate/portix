import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/sftp/bloc/index.dart';
import 'package:portix/src/features/sftp/controller/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';

part '../widget/sections/sftp_dialogs_section.dart';
part '../widget/sections/sftp_file_actions_section.dart';
part '../widget/sections/sftp_file_pane_section.dart';
part '../widget/sections/sftp_profile_gate_section.dart';
part '../widget/sections/sftp_transfer_queue_section.dart';

class SftpWorkspacePage extends StatefulWidget {
  const SftpWorkspacePage({super.key});

  @override
  State<SftpWorkspacePage> createState() => _SftpWorkspacePageState();
}

class _SftpWorkspacePageState extends State<SftpWorkspacePage> {
  late SftpWorkspaceController _controller;
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
    _tabs.add(_SftpTab(
      controller: _controller,
      label: 'SFTP 1',
    ));
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
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _syncSelectionsWithRows();
    setState(() {});
  }

  void _syncSelectionsWithRows() {
    final localPaths = _controller.localRows
        .map((row) => row.path)
        .whereType<String>()
        .toSet();
    final remotePaths = _controller.remoteVisibleRows
        .map((row) => row.path)
        .whereType<String>()
        .toSet();
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
  ) {
    final path = file.path;
    final selected = isRemote ? _selectedRemotePaths : _selectedLocalPaths;
    if (path == null || !selected.contains(path)) return [file];
    final rows = isRemote
        ? _controller.remoteVisibleRows
        : _controller.localVisibleRows;
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
    if (_remoteSyncKey == key) return;
    _remoteSyncKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_controller.attachRemoteProfile(profile, remotePath));
    });
  }

  void _addSftpTab() {
    final newController = SftpWorkspaceController(
      connectionManager: sl<ConnectionManager>(),
    )..addListener(_handleControllerChanged);
    setState(() {
      _tabs.add(_SftpTab(
        controller: newController,
        label: 'SFTP ${_tabs.length + 1}',
      ));
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
    if (_tabs.length <= 1) return;
    setState(() {
      final tab = _tabs.removeAt(index);
      tab.controller
        ..removeListener(_handleControllerChanged)
        ..dispose();
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      _controller = _tabs[_activeTabIndex].controller;
      _remoteSyncKey = null;
      _selectedLocalPaths.clear();
      _selectedRemotePaths.clear();
      _localSelectionAnchor = null;
      _remoteSelectionAnchor = null;
    });
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

  void _selectProfileForActiveTab(BuildContext context, SshProfile profile) {
    setState(() {
      _activeTab.selectedProfile = profile;
      _remoteSyncKey = null;
    });
    // Also update bloc for backward compatibility
    context.read<SftpWorkspaceBloc>().add(SftpProfileSelected(profile));
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
          _selectProfileForActiveTab(context, profile);
        } else {
          _addSftpTab();
          _selectProfileForActiveTab(context, profile);
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
  ) async {
    switch (action) {
      case _FileAction.open:
        if (file.folder) {
          if (isRemote) {
            await _runSftpAction(
              context,
              () => _controller.loadRemoteDirectory(file.path ?? file.name),
              success: 'Opened ${file.name}',
            );
          } else {
            await _controller.loadLocalDirectory(file.path ?? file.name);
          }
        } else {
          await _openFileWithEditor(
            context,
            file,
            isRemote,
            preferredDefault: true,
          );
        }
      case _FileAction.edit:
        await _openFileWithEditor(
          context,
          file,
          isRemote,
          preferredDefault: true,
        );
      case _FileAction.openWith:
        await _openFileWithEditor(
          context,
          file,
          isRemote,
          preferredDefault: false,
        );
      case _FileAction.download:
        if (!isRemote) {
          _showSnack(context, 'Download hanya tersedia untuk remote file.');
          return;
        }
        final selectedDir = await FilePicker.getDirectoryPath(
          dialogTitle: 'Download ${file.name} to...',
          initialDirectory: _controller.defaultDownloadsPath,
        );
        if (selectedDir == null || !mounted) return;
        final localPath = '$selectedDir${Platform.pathSeparator}${file.name}';
        final exists = _controller.localTargetExists(localPath);
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
          () => _controller.downloadRemoteEntry(
            file,
            localPath,
            overwrite: exists,
          ),
          showErrorSnack: false,
        );
      case _FileAction.newFile:
        _startInlineCreate(_SftpInlineCreateKind.file, remote: isRemote);
      case _FileAction.newFolder:
        _startInlineCreate(_SftpInlineCreateKind.folder, remote: isRemote);
      case _FileAction.rename:
        _startInlineRename(file, remote: isRemote);
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
            () => _controller.duplicateLocalPath(file, newName),
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
          () => _controller.duplicateRemotePath(file, newName),
          success: 'Duplicated ${file.name}',
        );
      case _FileAction.move:
        if (!isRemote) {
          final selectedDir = await FilePicker.getDirectoryPath(
            dialogTitle: 'Move ${file.name} to...',
            initialDirectory: _controller.localPath,
          );
          if (selectedDir == null || !mounted) return;
          final targetPath =
              '$selectedDir${Platform.pathSeparator}${file.name}';
          await _runSftpAction(
            context,
            () => _controller.moveLocalPath(file, targetPath),
            success: 'Moved ${file.name} to $selectedDir',
          );
          return;
        }
        final moveTarget = await _showRemoteFolderPicker(
          context,
          title: 'Move ${file.name}',
          currentPath: _controller.remotePath,
        );
        if (moveTarget == null || !mounted) return;
        final remoteDest = moveTarget.endsWith('/')
            ? '$moveTarget${file.name}'
            : '$moveTarget/${file.name}';
        await _runSftpAction(
          context,
          () => _controller.moveRemotePath(file, remoteDest),
          success: 'Moved ${file.name} to $moveTarget',
        );
      case _FileAction.chmod:
        final mode = await _showChmodDialog(context, file);
        if (mode == null) return;
        if (!isRemote) {
          _showSnack(context, 'Local chmod belum tersedia dari workspace ini.');
          return;
        }
        await _runSftpAction(
          context,
          () => _controller.chmodRemotePath(file, mode),
          success: 'Updated permissions for ${file.name}',
        );
      case _FileAction.delete:
        final confirmed = await _confirmDelete(context, file, isRemote);
        if (confirmed != true) return;
        await _runSftpAction(
          context,
          () => isRemote
              ? _controller.deleteRemotePath(file)
              : _controller.deleteLocalPath(file),
          success: 'Deleted ${file.name}',
        );
    }
  }

  Future<void> _openFileWithEditor(
    BuildContext context,
    SftpFileEntry file,
    bool isRemote, {
    required bool preferredDefault,
  }) async {
    if (file.folder) {
      _showSnack(context, 'Editor hanya untuk file. Pakai Open untuk folder.');
      return;
    }

    final isCodeFile = _shouldOpenInCodeEditor(file.name);

    // For non-code files opened with default action,
    // always use the OS system default application (Word for .docx, etc.)
    if (!isCodeFile && preferredDefault) {
      final path = await _controller.editablePathFor(file, isRemote);
      try {
        await _controller.openWithSystemDefault(path);
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
      editors = await _controller.detectLocalEditors();
    } else {
      final extension = _fileExtension(file.name);
      editors = await _controller.detectAppsForExtension(extension);
    }
    if (!mounted) return;

    if (editors.isEmpty) {
      // No apps found — use system default directly.
      final path = await _controller.editablePathFor(file, isRemote);
      try {
        await _controller.openWithSystemDefault(path);
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
      final path = await _controller.editablePathFor(file, isRemote);
      try {
        await _controller.openWithSystemDefault(path);
      } catch (error) {
        if (!mounted) return;
        _showSnack(context, 'Failed to open ${file.name}: $error');
      }
      return;
    }

    final path = await _controller.editablePathFor(file, isRemote);
    final originalText = isRemote ? await _readFileTextIfPossible(path) : null;

    try {
      await _controller.openEditor(editor, path);
      if (!mounted) return;
      if (isRemote) {
        await _watchLocalEditForRewrite(
          file: file,
          localPath: path,
          originalText: originalText,
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
      return editor.command == 'cmd.exe' &&
          editor.arguments.contains('start');
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
        await _showRewritePrompt(file, localPath, originalText);
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
  ) async {
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
      await _rewriteEditedRemoteFile(file, localPath);
    }
  }

  Future<void> _rewriteEditedRemoteFile(
    SftpFileEntry file,
    String localPath,
  ) async {
    try {
      await _controller.rewriteRemoteFileFromLocal(file, localPath);
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
    BuildContext context, {
    required String title,
    required String currentPath,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _RemoteFolderPickerDialog(
        title: title,
        initialPath: currentPath,
        connectionManager: _controller,
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
    return MultiBlocListener(
      listeners: [
        BlocListener<SshSessionBloc, SshSessionState>(
          listenWhen: (previous, current) =>
              current.pendingTarget == SshSessionTarget.sftp &&
              previous.targetProfileId != current.targetProfileId &&
              current.targetProfileId != null,
          listener: (context, state) {
            final profiles = context.read<SftpWorkspaceBloc>().state.connectableProfiles;
            _handleIncomingSftpProfile(state, profiles);
          },
        ),
      ],
      child: BlocBuilder<SftpWorkspaceBloc, SftpWorkspaceState>(
      builder: (context, state) {
        final profiles = state.connectableProfiles;
        final activeTab = _activeTab;
        final selectedProfile = activeTab.selectedProfile;
        final remotePath = selectedProfile != null
            ? _remotePathForProfile(selectedProfile)
            : '~';
        _scheduleRemoteSync(selectedProfile, remotePath);

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
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                            closable: _tabs.length > 1,
                            onTap: () => _switchSftpTab(index),
                            onClose: () => _closeSftpTab(index),
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
                ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  Widget _buildSftpContent(
    BuildContext context, {
    required List<SshProfile> profiles,
    required SshProfile? selectedProfile,
    required String remotePath,
  }) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
                  if (narrow) {
                    return ListView(
                      children: [
                        SizedBox(
                          height: 520,
                          child: _FilePane(
                            title: 'Local',
                            path: _controller.localPath,
                            items: _controller.localVisibleRows,
                            countLabel: _controller.loadingLocal
                                ? 'Loading'
                                : _controller.localSearchActive
                                ? '${_controller.localVisibleItemCount} found'
                                : '${_controller.localItemCount} items',
                            footerLeft: _controller.localError == null
                                ? '${_controller.localItemCount} items'
                                : 'Local unavailable',
                            footerRight: _controller.localError ?? '',
                            loading: _controller.loadingLocal,
                            error: _controller.localError,
                            findQuery: _controller.localSearchQuery,
                            findActive: _controller.localSearchActive,
                            onFindSubmitted: _controller.searchLocal,
                            onFindCleared: _controller.clearLocalSearch,
                            onCreateFileRequested: () => _startInlineCreate(
                              _SftpInlineCreateKind.file,
                              remote: false,
                            ),
                            onCreateFolderRequested: () => _startInlineCreate(
                              _SftpInlineCreateKind.folder,
                              remote: false,
                            ),
                            inlineCreateKind: _inlineCreateRemote
                                ? null
                                : _inlineCreateKind,
                            inlineCreateController: _inlineCreateController,
                            inlineCreateFocusNode: _inlineCreateFocusNode,
                            onInlineCreateSubmit: _submitInlineCreate,
                            onInlineCreateCancel: _cancelInlineCreate,
                            inlineRenameFile: _renamingRemote
                                ? null
                                : _renamingFile,
                            inlineRenameController: _inlineRenameController,
                            inlineRenameFocusNode: _inlineRenameFocusNode,
                            onInlineRenameSubmit: _submitInlineRename,
                            onInlineRenameCancel: _cancelInlineRename,
                            onRefreshRequested: () => unawaited(
                              _controller.loadLocalDirectory(
                                _controller.localPath,
                              ),
                            ),
                            onPathSubmitted: _controller.loadLocalDirectory,
                            onOpenFolder: (file) => _controller
                                .loadLocalDirectory(file.path ?? file.name),
                            selectedPaths: _selectedLocalPaths,
                            onItemSelected: (file, index, rows) =>
                                _handleRowSelected(file, index, false, rows),
                            selectedTransferEntries: (file) =>
                                _selectedTransferEntries(file, false),
                            onTransferDropped: (transfer) => unawaited(
                              _handleDroppedTransfer(context, transfer, false),
                            ),
                            onFileAction: (action, file) =>
                                _handleFileAction(context, action, file, false),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 520,
                          child: _FilePane(
                            title: selectedProfile == null
                                ? 'Remote'
                                : 'Remote / ${selectedProfile.name}',
                            path: _controller.remotePath,
                            items: selectedProfile == null
                                ? const []
                                : _controller.remoteVisibleRows,
                            countLabel: selectedProfile == null
                                ? 'No session'
                                : _controller.searchingRemote
                                ? 'Searching'
                                : _controller.remoteSearchActive
                                ? '${_controller.remoteVisibleItemCount} found'
                                : _controller.loadingRemote
                                ? 'Loading'
                                : '${_controller.remoteItemCount} items',
                            footerLeft: selectedProfile == null
                                ? 'No remote session'
                                : _controller.remoteError == null
                                ? '${_controller.remoteItemCount} items'
                                : 'Remote unavailable',
                            footerRight: _controller.remoteError ?? '',
                            loading: _controller.loadingRemote,
                            error: _controller.remoteError,
                            isRemote: true,
                            showActions: selectedProfile != null,
                            statusTitle: _controller.remoteStatusTitle,
                            statusMessage: _controller.remoteStatusMessage,
                            findQuery: _controller.remoteSearchQuery,
                            findBase: _controller.remoteSearchBase,
                            findActive: _controller.remoteSearchActive,
                            findError: _controller.remoteSearchError,
                            findSearching: _controller.searchingRemote,
                            onFindSubmitted: selectedProfile == null
                                ? null
                                : (query) => unawaited(
                                    _controller.searchRemote(query),
                                  ),
                            onFindCleared: selectedProfile == null
                                ? null
                                : _controller.clearRemoteSearch,
                            onCreateFileRequested: selectedProfile == null
                                ? null
                                : () => _startInlineCreate(
                                    _SftpInlineCreateKind.file,
                                    remote: true,
                                  ),
                            onCreateFolderRequested: selectedProfile == null
                                ? null
                                : () => _startInlineCreate(
                                    _SftpInlineCreateKind.folder,
                                    remote: true,
                                  ),
                            inlineCreateKind:
                                selectedProfile == null || !_inlineCreateRemote
                                ? null
                                : _inlineCreateKind,
                            inlineCreateController: _inlineCreateController,
                            inlineCreateFocusNode: _inlineCreateFocusNode,
                            onInlineCreateSubmit: _submitInlineCreate,
                            onInlineCreateCancel: _cancelInlineCreate,
                            inlineRenameFile: !_renamingRemote
                                ? null
                                : _renamingFile,
                            inlineRenameController: _inlineRenameController,
                            inlineRenameFocusNode: _inlineRenameFocusNode,
                            onInlineRenameSubmit: _submitInlineRename,
                            onInlineRenameCancel: _cancelInlineRename,
                            onRefreshRequested: selectedProfile == null
                                ? null
                                : () => unawaited(
                                    _controller.loadRemoteDirectory(
                                      _controller.remotePath,
                                    ),
                                  ),
                            contentOverride: selectedProfile == null
                                ? _SftpProfileGate(
                                    profiles: profiles,
                                    onSelected: (profile) =>
                                        _selectProfileForActiveTab(
                                          context,
                                          profile,
                                        ),
                                  )
                                : _controller.isRemoteDisconnected
                                ? _SftpDisconnectedOverlay(
                                    onReconnect: () => unawaited(
                                      _controller.reconnect(selectedProfile),
                                    ),
                                  )
                                : null,
                            onPathSubmitted: _controller.loadRemoteDirectory,
                            onOpenFolder: (file) => _controller
                                .loadRemoteDirectory(file.path ?? file.name),
                            selectedPaths: _selectedRemotePaths,
                            onItemSelected: (file, index, rows) =>
                                _handleRowSelected(file, index, true, rows),
                            selectedTransferEntries: (file) =>
                                _selectedTransferEntries(file, true),
                            onTransferDropped: (transfer) => unawaited(
                              _handleDroppedTransfer(context, transfer, true),
                            ),
                            onFileAction: (action, file) =>
                                _handleFileAction(context, action, file, true),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: _FilePane(
                          title: 'Local',
                          path: _controller.localPath,
                          items: _controller.localVisibleRows,
                          countLabel: _controller.loadingLocal
                              ? 'Loading'
                              : _controller.localSearchActive
                              ? '${_controller.localVisibleItemCount} found'
                              : '${_controller.localItemCount} items',
                          footerLeft: _controller.localError == null
                              ? '${_controller.localItemCount} items'
                              : 'Local unavailable',
                          footerRight: _controller.localError ?? '',
                          loading: _controller.loadingLocal,
                          error: _controller.localError,
                          findQuery: _controller.localSearchQuery,
                          findActive: _controller.localSearchActive,
                          onFindSubmitted: _controller.searchLocal,
                          onFindCleared: _controller.clearLocalSearch,
                          onCreateFileRequested: () => _startInlineCreate(
                            _SftpInlineCreateKind.file,
                            remote: false,
                          ),
                          onCreateFolderRequested: () => _startInlineCreate(
                            _SftpInlineCreateKind.folder,
                            remote: false,
                          ),
                          inlineCreateKind: _inlineCreateRemote
                              ? null
                              : _inlineCreateKind,
                          inlineCreateController: _inlineCreateController,
                          inlineCreateFocusNode: _inlineCreateFocusNode,
                          onInlineCreateSubmit: _submitInlineCreate,
                          onInlineCreateCancel: _cancelInlineCreate,
                          inlineRenameFile: _renamingRemote
                              ? null
                              : _renamingFile,
                          inlineRenameController: _inlineRenameController,
                          inlineRenameFocusNode: _inlineRenameFocusNode,
                          onInlineRenameSubmit: _submitInlineRename,
                          onInlineRenameCancel: _cancelInlineRename,
                          onRefreshRequested: () => unawaited(
                            _controller.loadLocalDirectory(
                              _controller.localPath,
                            ),
                          ),
                          onPathSubmitted: _controller.loadLocalDirectory,
                          onOpenFolder: (file) => _controller
                              .loadLocalDirectory(file.path ?? file.name),
                          selectedPaths: _selectedLocalPaths,
                          onItemSelected: (file, index, rows) =>
                              _handleRowSelected(file, index, false, rows),
                          selectedTransferEntries: (file) =>
                              _selectedTransferEntries(file, false),
                          onTransferDropped: (transfer) => unawaited(
                            _handleDroppedTransfer(context, transfer, false),
                          ),
                          onFileAction: (action, file) =>
                              _handleFileAction(context, action, file, false),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _FilePane(
                          title: selectedProfile == null
                              ? 'Remote'
                              : 'Remote / ${selectedProfile.name}',
                          path: _controller.remotePath,
                          items: selectedProfile == null
                              ? const []
                              : _controller.remoteVisibleRows,
                          countLabel: selectedProfile == null
                              ? 'No session'
                              : _controller.searchingRemote
                              ? 'Searching'
                              : _controller.remoteSearchActive
                              ? '${_controller.remoteVisibleItemCount} found'
                              : _controller.loadingRemote
                              ? 'Loading'
                              : '${_controller.remoteItemCount} items',
                          footerLeft: selectedProfile == null
                              ? 'No remote session'
                              : _controller.remoteError == null
                              ? '${_controller.remoteItemCount} items'
                              : 'Remote unavailable',
                          footerRight: _controller.remoteError ?? '',
                          loading: _controller.loadingRemote,
                          error: _controller.remoteError,
                          isRemote: true,
                          showActions: selectedProfile != null,
                          statusTitle: _controller.remoteStatusTitle,
                          statusMessage: _controller.remoteStatusMessage,
                          findQuery: _controller.remoteSearchQuery,
                          findBase: _controller.remoteSearchBase,
                          findActive: _controller.remoteSearchActive,
                          findError: _controller.remoteSearchError,
                          findSearching: _controller.searchingRemote,
                          onFindSubmitted: selectedProfile == null
                              ? null
                              : (query) =>
                                    unawaited(_controller.searchRemote(query)),
                          onFindCleared: selectedProfile == null
                              ? null
                              : _controller.clearRemoteSearch,
                          onCreateFileRequested: selectedProfile == null
                              ? null
                              : () => _startInlineCreate(
                                  _SftpInlineCreateKind.file,
                                  remote: true,
                                ),
                          onCreateFolderRequested: selectedProfile == null
                              ? null
                              : () => _startInlineCreate(
                                  _SftpInlineCreateKind.folder,
                                  remote: true,
                                ),
                          inlineCreateKind:
                              selectedProfile == null || !_inlineCreateRemote
                              ? null
                              : _inlineCreateKind,
                          inlineCreateController: _inlineCreateController,
                          inlineCreateFocusNode: _inlineCreateFocusNode,
                          onInlineCreateSubmit: _submitInlineCreate,
                          onInlineCreateCancel: _cancelInlineCreate,
                          inlineRenameFile: !_renamingRemote
                              ? null
                              : _renamingFile,
                          inlineRenameController: _inlineRenameController,
                          inlineRenameFocusNode: _inlineRenameFocusNode,
                          onInlineRenameSubmit: _submitInlineRename,
                          onInlineRenameCancel: _cancelInlineRename,
                          onRefreshRequested: selectedProfile == null
                              ? null
                              : () => unawaited(
                                  _controller.loadRemoteDirectory(
                                    _controller.remotePath,
                                  ),
                                ),
                          contentOverride: selectedProfile == null
                              ? _SftpProfileGate(
                                  profiles: profiles,
                                  onSelected: (profile) =>
                                      _selectProfileForActiveTab(
                                        context,
                                        profile,
                                      ),
                                )
                              : _controller.isRemoteDisconnected
                              ? _SftpDisconnectedOverlay(
                                  onReconnect: () => unawaited(
                                    _controller.reconnect(selectedProfile),
                                  ),
                                )
                              : null,
                          onPathSubmitted: _controller.loadRemoteDirectory,
                          onOpenFolder: (file) => _controller
                              .loadRemoteDirectory(file.path ?? file.name),
                          selectedPaths: _selectedRemotePaths,
                          onItemSelected: (file, index, rows) =>
                              _handleRowSelected(file, index, true, rows),
                          selectedTransferEntries: (file) =>
                              _selectedTransferEntries(file, true),
                          onTransferDropped: (transfer) => unawaited(
                            _handleDroppedTransfer(context, transfer, true),
                          ),
                          onFileAction: (action, file) =>
                              _handleFileAction(context, action, file, true),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (_controller.transferJobs.isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: 16,
                  width: 380,
                  child: _TransferQueue(
                    jobs: _controller.transferJobs,
                    onClose: _controller.clearTransfers,
                  ),
                ),
            ],
    );
  }

  void _startInlineCreate(_SftpInlineCreateKind kind, {required bool remote}) {
    setState(() {
      _clearInlineRename();
      _inlineCreateKind = kind;
      _inlineCreateRemote = remote;
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
      _inlineCreateController.clear();
    });
  }

  void _startInlineRename(SftpFileEntry file, {required bool remote}) {
    if (file.name == '..') return;
    setState(() {
      _inlineCreateKind = null;
      _renamingFile = file;
      _renamingRemote = remote;
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
    await _runSftpAction(
      context,
      () => remote
          ? _controller.renameRemotePath(file, newName)
          : _controller.renameLocalPath(file, newName),
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
    await _runSftpAction(
      context,
      () {
        if (_inlineCreateRemote) {
          return kind == _SftpInlineCreateKind.folder
              ? _controller.createRemoteFolder(name)
              : _controller.createRemoteFile(name);
        }
        return kind == _SftpInlineCreateKind.folder
            ? _controller.createLocalFolder(name)
            : _controller.createLocalFile(name);
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
  ) async {
    if (transfer.fromRemote == targetRemote) return;
    if (targetRemote) {
      for (final entry in transfer.entries) {
        final localPath = entry.path;
        if (localPath == null) continue;
        final targetPath = _controller.remoteUploadTargetPath(localPath);
        final exists = _controller.remoteTargetExistsForLocalPath(localPath);
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
          () => _controller.uploadLocalPath(localPath, overwrite: exists),
          showErrorSnack: false,
        );
      }
      return;
    }
    for (final entry in transfer.entries) {
      final localPath =
          '${_controller.localPath}${Platform.pathSeparator}${entry.name}';
      final exists = _controller.localTargetExists(localPath);
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
        () => _controller.downloadRemoteEntry(
          entry,
          localPath,
          overwrite: exists,
        ),
        showErrorSnack: false,
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
  _SftpTab({required this.controller, required this.label});

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
  });

  final String label;
  final bool active;
  final bool closable;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            const Icon(Icons.folder_open_rounded, size: 14, color: AppColors.cyan),
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
                child: const Icon(Icons.close_rounded, size: 14, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
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
        _entries = entries
            .where((e) => e.name != '..')
            .toList(growable: false)
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
                  Expanded(
                    child: Text(widget.title, style: portixTitle(16)),
                  ),
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
                    const Icon(Icons.folder_rounded, size: 16, color: AppColors.cyan),
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
                        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                        onPressed: _navigateUp,
                        icon: const Icon(Icons.arrow_upward_rounded, size: 16, color: AppColors.muted),
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
                                child: Text(
                                  'Empty directory',
                                  style: portixMuted(12),
                                ),
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
