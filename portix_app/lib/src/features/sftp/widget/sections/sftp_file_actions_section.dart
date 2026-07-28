part of '../../page/sftp_workspace_page.dart';

enum _FileAction {
  open,
  edit,
  openWith,
  download,
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
        if (isRemote)
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
        if (isRemote) ...const [
          PopupMenuItem(
            value: _FileAction.duplicate,
            child: _MenuItem(icon: Icons.copy_rounded, label: 'Duplicate'),
          ),
          PopupMenuItem(
            value: _FileAction.move,
            child: _MenuItem(
              icon: Icons.drive_file_move_rounded,
              label: 'Move',
            ),
          ),
          PopupMenuItem(
            value: _FileAction.chmod,
            child: _MenuItem(
              icon: Icons.lock_outline_rounded,
              label: 'Permissions (CHMOD)',
            ),
          ),
        ],
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
    required this.onSelected,
    required this.dragEntries,
  });

  final SftpFileEntry data;
  final bool selected;
  final bool isRemote;
  final void Function(_FileAction action, SftpFileEntry data) onAction;
  final void Function(SftpFileEntry data) onOpenFolder;
  final VoidCallback onSelected;
  final List<SftpFileEntry> dragEntries;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelected,
      onDoubleTap: () {
        if (data.folder || data.name == '..') {
          onOpenFolder(data);
        } else {
          onAction(_FileAction.open, data);
        }
      },
      child: Container(
        height: compact
            ? data.location == null
                  ? 52
                  : 58
            : data.location == null
            ? 34
            : 44,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF123B63) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: .65)),
          ),
        ),
        child: compact ? _compactRow() : _desktopRow(),
      ),
    );

    if (data.name == '..') return row;

    return Draggable<SftpFileTransfer>(
      data: SftpFileTransfer(
        file: data,
        files: dragEntries,
        fromRemote: isRemote,
      ),
      feedback: Material(
        color: Colors.transparent,
        child: _DragFeedback(
          data: data,
          fromRemote: isRemote,
          count: dragEntries.length,
        ),
      ),
      childWhenDragging: Opacity(opacity: .45, child: row),
      child: row,
    );
  }

  Widget _nameCell({required bool compact}) {
    final meta = [
      if (data.location != null) data.location!,
      if (data.location == null && data.size.trim().isNotEmpty) data.size,
      if (data.location == null && data.modified.trim().isNotEmpty)
        data.modified,
    ].where((item) => item.trim().isNotEmpty && item != '-').join(' · ');
    return Row(
      children: [
        Icon(
          data.folder
              ? Icons.folder_outlined
              : Icons.insert_drive_file_outlined,
          color: data.folder ? AppColors.cyan : AppColors.muted,
          size: compact ? 18 : 16,
        ),
        SizedBox(width: compact ? 10 : 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(compact ? 13 : 12),
              ),
              if (compact && meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(10),
                ),
              ] else if (!compact && data.location != null)
                Text(
                  data.location!,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(9),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactRow() {
    return Row(
      children: [
        Expanded(child: _nameCell(compact: true)),
        const SizedBox(width: 8),
        _FileActionMenu(
          file: data,
          isRemote: isRemote,
          onSelected: (action) => onAction(action, data),
        ),
      ],
    );
  }

  Widget _desktopRow() {
    return Row(
      children: [
        Expanded(flex: 5, child: _nameCell(compact: false)),
        Expanded(
          flex: 2,
          child: Text(isRemote ? data.type : data.size, style: portixMuted(11)),
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
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({
    required this.data,
    required this.fromRemote,
    required this.count,
  });
  final SftpFileEntry data;
  final bool fromRemote;
  final int count;

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
              count > 1 ? '$count items' : data.name,
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
