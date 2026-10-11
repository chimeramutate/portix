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
      color: AppColors.menu,
      shape: _menuShape,
      elevation: 8,
      menuPadding: _menuPadding,
      constraints: _menuConstraints,
      icon: Icon(Icons.more_vert_rounded, size: 18, color: AppColors.muted),
      onSelected: onSelected,
      itemBuilder: (context) => _fileActionItems(file, isRemote),
    );
  }
}

/// Shared by the ⋮ button and the right-click menu on a row.
List<PopupMenuEntry<_FileAction>> _fileActionItems(
  SftpFileEntry file,
  bool isRemote,
) => [
  if (file.folder)
    _item(_FileAction.open, Icons.folder_open_rounded, 'Open')
  else ...[
    _item(_FileAction.edit, Icons.edit_outlined, 'Edit'),
    _item(_FileAction.openWith, Icons.open_in_new_rounded, 'Open With…'),
  ],
  if (isRemote && file.folder) ...[
    _divider,
    _item(_FileAction.newFile, Icons.note_add_outlined, 'New file'),
    _item(
      _FileAction.newFolder,
      Icons.create_new_folder_outlined,
      'New folder',
    ),
  ],
  _divider,
  if (isRemote) _item(_FileAction.download, Icons.download_rounded, 'Download'),
  _item(_FileAction.rename, Icons.drive_file_rename_outline_rounded, 'Rename'),
  if (isRemote) ...[
    _item(_FileAction.duplicate, Icons.copy_rounded, 'Duplicate'),
    _item(_FileAction.move, Icons.drive_file_move_outlined, 'Move'),
    _item(_FileAction.chmod, Icons.lock_outline_rounded, 'Permissions'),
  ],
  _divider,
  _item(
    _FileAction.delete,
    Icons.delete_outline_rounded,
    'Delete',
    danger: true,
  ),
];

final _divider = PopupMenuDivider(
  height: 9,
  thickness: 1,
  color: AppColors.border.withValues(alpha: .6),
);

PopupMenuItem<_FileAction> _item(
  _FileAction action,
  IconData icon,
  String label, {
  bool danger = false,
}) {
  final color = danger ? AppColors.danger : AppColors.text;
  return PopupMenuItem(
    value: action,
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Icon(icon, size: 16, color: danger ? color : AppColors.muted),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// Same look for the ⋮ menu and the right-click menu.
ShapeBorder get _menuShape => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(10),
  side: BorderSide(color: AppColors.border),
);

const _menuPadding = EdgeInsets.symmetric(vertical: 4);
const _menuConstraints = BoxConstraints(minWidth: 190);

/// Right-click on a row: the same actions as ⋮, at the pointer.
Future<void> _showFileActionMenu(
  BuildContext context,
  Offset position, {
  required SftpFileEntry file,
  required bool isRemote,
  required ValueChanged<_FileAction> onSelected,
}) async {
  final action = await showMenu<_FileAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    ),
    color: AppColors.menu,
    shape: _menuShape,
    elevation: 8,
    menuPadding: _menuPadding,
    constraints: _menuConstraints,
    items: _fileActionItems(file, isRemote),
  );
  if (action != null) onSelected(action);
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
      onSecondaryTapUp: data.name == '..'
          ? null
          : (details) {
              // Keep an existing multi-selection; a toggle here would
              // drop the row (Ctrl+click is a right-click on macOS).
              if (!selected) onSelected();
              unawaited(
                _showFileActionMenu(
                  context,
                  details.globalPosition,
                  file: data,
                  isRemote: isRemote,
                  onSelected: (action) => onAction(action, data),
                ),
              );
            },
      onDoubleTap: () {
        if (data.folder || data.name == '..') {
          onOpenFolder(data);
        } else {
          onAction(_FileAction.open, data);
        }
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelected,
          highlightColor: AppColors.surfaceDark.withValues(alpha: .35),
          splashColor: AppColors.cyan.withValues(alpha: .08),
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
              color: selected ? AppColors.selected : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.border.withValues(alpha: .65),
                ),
              ),
            ),
            child: compact ? _compactRow() : _desktopRow(),
          ),
        ),
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

  Widget _buildFileIcon({required bool compact}) {
    final iconSize = compact ? 20.0 : 18.0;
    final color = _iconColorForFile(data.name);
    if (data.folder) {
      return Icon(Icons.folder_outlined, color: color, size: iconSize);
    }
    final asset = FileTypeRegistry.assetForExtension(data.name);
    if (asset != null) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: SvgPicture.asset(
          asset,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      );
    }
    return Icon(Icons.insert_drive_file_outlined, color: color, size: iconSize);
  }

  Color _iconColorForFile(String fileName) {
    final category = FileTypeRegistry.categoryFor(fileName);
    return switch (category) {
      FileCategory.code => AppColors.cyan,
      FileCategory.document => AppColors.blue,
      FileCategory.image => AppColors.amber,
      FileCategory.audio => AppColors.danger,
      FileCategory.video => AppColors.danger,
      FileCategory.archive => AppColors.amber,
      FileCategory.executable => AppColors.danger,
      FileCategory.database => AppColors.blue,
      FileCategory.design => AppColors.amber,
      FileCategory.unknown => AppColors.muted,
    };
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
        _buildFileIcon(compact: compact),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(compact ? 15 : 14),
              ),
              if (compact && meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(12),
                ),
              ] else if (!compact && data.location != null)
                Text(
                  data.location!,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(11),
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
          child: Text(isRemote ? data.type : data.size, style: portixMuted(13)),
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
            color: AppColors.cyan,
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
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(left, style: portixMuted(12)),
          const Spacer(),
          Text(
            right,
            overflow: TextOverflow.ellipsis,
            style: portixMuted(12).copyWith(color: AppColors.cyan),
          ),
        ],
      ),
    );
  }
}
