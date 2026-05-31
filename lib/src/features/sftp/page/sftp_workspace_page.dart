import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/sftp/bloc/index.dart';
import 'package:portix/src/features/sftp/controller/index.dart';

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
  late final SftpWorkspaceController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SftpWorkspaceController()
      ..addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
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
            _showSnack(
              context,
              'Remote folder open belum terhubung ke backend SFTP: ${file.name}',
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
        _showSnack(context, 'Download queued: ${file.name}');
      case _FileAction.uploadHere:
        _showSnack(context, 'Upload here: ${file.name}');
      case _FileAction.newFile:
        _showSnack(context, 'New file inside: ${file.name}');
      case _FileAction.newFolder:
        _showSnack(context, 'New folder inside: ${file.name}');
      case _FileAction.rename:
        await _showRenameDialog(context, file);
      case _FileAction.duplicate:
        _showSnack(context, 'Duplicate: ${file.name}');
      case _FileAction.move:
        _showSnack(context, 'Move: ${file.name}');
      case _FileAction.chmod:
        await _showChmodDialog(context, file, isRemote);
      case _FileAction.delete:
        await _showDeleteDialog(context, file);
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

    final editors = await _controller.detectLocalEditors();
    if (!mounted) return;

    if (editors.isEmpty) {
      _showSnack(
        context,
        'Editor lokal tidak ditemukan. Install VS Code, Cursor, Zed, Sublime, Xcode, atau editor lain.',
      );
      return;
    }

    final editor = preferredDefault
        ? editors.first
        : await showModalBottomSheet<LocalEditor>(
            context: context,
            backgroundColor: AppColors.surface,
            builder: (context) => _EditorPickerSheet(editors: editors),
          );

    if (editor == null || !mounted) return;

    final path = await _controller.editablePathFor(file, isRemote);

    try {
      await _controller.openEditor(editor, path);
      if (!mounted) return;
      _showSnack(
        context,
        isRemote
            ? 'Opened temp copy in ${editor.name}. Setelah selesai edit, gunakan Upload changes untuk sync balik.'
            : 'Opened ${file.name} in ${editor.name}.',
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack(context, 'Failed to open ${editor.name}: $error');
    }
  }

  Future<void> _showChmodDialog(
    BuildContext context,
    SftpFileEntry file,
    bool isRemote,
  ) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => _ChmodDialog(file: file),
    );
    if (result == null || !mounted) return;
    _showSnack(
      context,
      isRemote
          ? 'CHMOD ${result.toString().padLeft(3, '0')} queued for ${file.name}'
          : 'Local chmod ${result.toString().padLeft(3, '0')} queued for ${file.name}',
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    SftpFileEntry file,
  ) async {
    final controller = TextEditingController(text: file.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (result == null || result.trim().isEmpty || !mounted) return;
    _showSnack(context, 'Rename ${file.name} -> ${result.trim()}');
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    SftpFileEntry file,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete item?'),
        content: Text('Delete ${file.name}?'),
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
    if (confirmed == true && mounted)
      _showSnack(context, 'Delete queued: ${file.name}');
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

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<SftpWorkspaceBloc>()..add(const SftpProfilesRequested()),
      child: BlocBuilder<SftpWorkspaceBloc, SftpWorkspaceState>(
        builder: (context, state) {
          final profiles = state.connectableProfiles;
          final selectedProfile = state.selectedProfile;
          final remotePath = state.selectedRemotePath;

          return Padding(
            padding: const EdgeInsets.all(14),
            child: Stack(
              children: [
                Column(
                  children: [
                    _OperationBar(
                      profile: selectedProfile,
                      remotePath: remotePath,
                      hasProfiles: profiles.isNotEmpty,
                      onChangeProfile: selectedProfile == null
                          ? null
                          : () => context.read<SftpWorkspaceBloc>().add(
                              const SftpProfileCleared(),
                            ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: LayoutBuilder(
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
                                    items: _controller.localRows,
                                    countLabel: _controller.loadingLocal
                                        ? 'Loading'
                                        : '${_controller.localItemCount} items',
                                    footerLeft: _controller.localError == null
                                        ? '${_controller.localItemCount} items'
                                        : 'Local unavailable',
                                    footerRight: _controller.localError ?? '',
                                    loading: _controller.loadingLocal,
                                    error: _controller.localError,
                                    onPathSubmitted:
                                        _controller.loadLocalDirectory,
                                    onOpenFolder: (file) =>
                                        _controller.loadLocalDirectory(
                                          file.path ?? file.name,
                                        ),
                                    onTransferDropped: (transfer) => _controller
                                        .queueTransfer(transfer, false),
                                    onFileAction: (action, file) =>
                                        _handleFileAction(
                                          context,
                                          action,
                                          file,
                                          false,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 520,
                                  child: _FilePane(
                                    title: selectedProfile == null
                                        ? 'Remote'
                                        : 'Remote / ${selectedProfile.name}',
                                    path: remotePath,
                                    items: selectedProfile == null
                                        ? const []
                                        : _controller.remoteRows,
                                    countLabel: selectedProfile == null
                                        ? 'No session'
                                        : 'Ready',
                                    isRemote: true,
                                    showActions: selectedProfile != null,
                                    contentOverride: selectedProfile == null
                                        ? _SftpProfileGate(
                                            profiles: profiles,
                                            onSelected: (profile) => context
                                                .read<SftpWorkspaceBloc>()
                                                .add(
                                                  SftpProfileSelected(profile),
                                                ),
                                          )
                                        : null,
                                    onPathSubmitted: (_) {},
                                    onOpenFolder: (_) {},
                                    onTransferDropped: (transfer) => _controller
                                        .queueTransfer(transfer, true),
                                    onFileAction: (action, file) =>
                                        _handleFileAction(
                                          context,
                                          action,
                                          file,
                                          true,
                                        ),
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
                                  items: _controller.localRows,
                                  countLabel: _controller.loadingLocal
                                      ? 'Loading'
                                      : '${_controller.localItemCount} items',
                                  footerLeft: _controller.localError == null
                                      ? '${_controller.localItemCount} items'
                                      : 'Local unavailable',
                                  footerRight: _controller.localError ?? '',
                                  loading: _controller.loadingLocal,
                                  error: _controller.localError,
                                  onPathSubmitted:
                                      _controller.loadLocalDirectory,
                                  onOpenFolder: (file) =>
                                      _controller.loadLocalDirectory(
                                        file.path ?? file.name,
                                      ),
                                  onTransferDropped: (transfer) => _controller
                                      .queueTransfer(transfer, false),
                                  onFileAction: (action, file) =>
                                      _handleFileAction(
                                        context,
                                        action,
                                        file,
                                        false,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _FilePane(
                                  title: selectedProfile == null
                                      ? 'Remote'
                                      : 'Remote / ${selectedProfile.name}',
                                  path: remotePath,
                                  items: selectedProfile == null
                                      ? const []
                                      : _controller.remoteRows,
                                  countLabel: selectedProfile == null
                                      ? 'No session'
                                      : 'Ready',
                                  isRemote: true,
                                  showActions: selectedProfile != null,
                                  contentOverride: selectedProfile == null
                                      ? _SftpProfileGate(
                                          profiles: profiles,
                                          onSelected: (profile) => context
                                              .read<SftpWorkspaceBloc>()
                                              .add(
                                                SftpProfileSelected(profile),
                                              ),
                                        )
                                      : null,
                                  onPathSubmitted: (_) {},
                                  onOpenFolder: (_) {},
                                  onTransferDropped: (transfer) =>
                                      _controller.queueTransfer(transfer, true),
                                  onFileAction: (action, file) =>
                                      _handleFileAction(
                                        context,
                                        action,
                                        file,
                                        true,
                                      ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
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
            ),
          );
        },
      ),
    );
  }
}
