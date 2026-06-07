part of '../../page/remote_folder_page.dart';

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
