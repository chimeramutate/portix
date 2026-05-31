part of '../../page/sftp_workspace_page.dart';

enum _FileAction {
  open,
  edit,
  openWith,
  download,
  uploadHere,
  newFile,
  newFolder,
  rename,
  duplicate,
  move,
  chmod,
  delete,
}

class _FileActionMenu extends StatelessWidget {
  const _FileActionMenu({
    required this.file,
    required this.isRemote,
    required this.onSelected,
  });

  final SftpFileEntry file;
  final bool isRemote;
  final ValueChanged<_FileAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final isParent = file.name == '..';
    if (isParent) return const SizedBox.shrink();

    return PopupMenuButton<_FileAction>(
      tooltip: 'Actions',
      color: AppColors.surfaceCard,
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: AppColors.muted,
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (file.folder)
          const PopupMenuItem(
            value: _FileAction.open,
            child: _MenuItem(icon: Icons.folder_open_rounded, label: 'Open'),
          )
        else ...const [
          PopupMenuItem(
            value: _FileAction.edit,
            child: _MenuItem(icon: Icons.edit_rounded, label: 'Edit'),
          ),
          PopupMenuItem(
            value: _FileAction.openWith,
            child: _MenuItem(
              icon: Icons.open_in_new_rounded,
              label: 'Open With…',
            ),
          ),
        ],
        if (isRemote && file.folder) ...const [
          PopupMenuDivider(),
          PopupMenuItem(
            value: _FileAction.uploadHere,
            child: _MenuItem(icon: Icons.upload_rounded, label: 'Upload here'),
          ),
          PopupMenuItem(
            value: _FileAction.newFile,
            child: _MenuItem(icon: Icons.note_add_outlined, label: 'New file'),
          ),
          PopupMenuItem(
            value: _FileAction.newFolder,
            child: _MenuItem(
              icon: Icons.create_new_folder_outlined,
              label: 'New folder',
            ),
          ),
        ],
        const PopupMenuDivider(),
        if (isRemote || !file.folder)
          const PopupMenuItem(
            value: _FileAction.download,
            child: _MenuItem(icon: Icons.download_rounded, label: 'Download'),
          ),
        const PopupMenuItem(
          value: _FileAction.rename,
          child: _MenuItem(
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'Rename',
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.duplicate,
          child: _MenuItem(icon: Icons.copy_rounded, label: 'Duplicate'),
        ),
        const PopupMenuItem(
          value: _FileAction.move,
          child: _MenuItem(icon: Icons.drive_file_move_rounded, label: 'Move'),
        ),
        const PopupMenuItem(
          value: _FileAction.chmod,
          child: _MenuItem(
            icon: Icons.lock_outline_rounded,
            label: 'Permissions (CHMOD)',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _FileAction.delete,
          child: _MenuItem(icon: Icons.delete_outline_rounded, label: 'Delete'),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.muted, size: 17),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.data,
    required this.selected,
    required this.isRemote,
    required this.onAction,
    required this.onOpenFolder,
  });

  final SftpFileEntry data;
  final bool selected;
  final bool isRemote;
  final void Function(_FileAction action, SftpFileEntry data) onAction;
  final void Function(SftpFileEntry data) onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () {
        if (data.folder || data.name == '..') {
          onOpenFolder(data);
        } else {
          onAction(_FileAction.open, data);
        }
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF123B63) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: .65)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Icon(
                    data.folder
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                    color: data.folder ? AppColors.cyan : AppColors.muted,
                    size: 16,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      data.name,
                      overflow: TextOverflow.ellipsis,
                      style: portixTitle(12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                isRemote ? data.type : data.size,
                style: portixMuted(11),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                isRemote ? data.size : data.modified,
                style: portixMuted(11),
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isRemote ? data.modified : '',
                      overflow: TextOverflow.ellipsis,
                      style: portixMuted(11),
                    ),
                  ),
                  _FileActionMenu(
                    file: data,
                    isRemote: isRemote,
                    onSelected: (action) => onAction(action, data),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (data.name == '..') return row;

    return Draggable<SftpFileTransfer>(
      data: SftpFileTransfer(file: data, fromRemote: isRemote),
      feedback: Material(
        color: Colors.transparent,
        child: _DragFeedback(data: data, fromRemote: isRemote),
      ),
      childWhenDragging: Opacity(opacity: .45, child: row),
      child: row,
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.data, required this.fromRemote});
  final SftpFileEntry data;
  final bool fromRemote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cyan),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            data.folder ? Icons.folder_outlined : Icons.insert_drive_file,
            color: data.folder ? AppColors.amber : AppColors.cyan,
            size: 17,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              data.name,
              overflow: TextOverflow.ellipsis,
              style: portixTitle(12),
            ),
          ),
          Icon(
            fromRemote ? Icons.download_rounded : Icons.upload_rounded,
            color: AppColors.green,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _PaneFooter extends StatelessWidget {
  const _PaneFooter({required this.left, required this.right});
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(left, style: portixMuted(11)),
          const Spacer(),
          Text(
            right,
            overflow: TextOverflow.ellipsis,
            style: portixMuted(11).copyWith(color: AppColors.cyan),
          ),
        ],
      ),
    );
  }
}
