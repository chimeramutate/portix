part of '../../page/sftp_workspace_page.dart';

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
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: active ? AppColors.cyan : AppColors.border),
    );
    return FocusRing(
      child: Material(
        color: active ? AppColors.selected : AppColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          onSecondaryTapDown: (details) => _showContextMenu(context, details),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 14,
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? AppColors.text : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (closable) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Close tab',
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 22,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
