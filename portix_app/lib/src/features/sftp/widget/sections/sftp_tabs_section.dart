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

class _SftpTabChip extends StatefulWidget {
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
  State<_SftpTabChip> createState() => _SftpTabChipState();
}

class _SftpTabChipState extends State<_SftpTabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final lit = active || _hovered;
    return FocusRing(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapDown: (details) => _showContextMenu(context, details),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 36,
            constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.surface
                  : _hovered
                  ? AppColors.surface.withValues(alpha: .5)
                  : Colors.transparent,
              border: Border(
                top: BorderSide(
                  color: active ? AppColors.cyan : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 14,
                  color: active ? AppColors.cyan : AppColors.muted,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? AppColors.text : AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.closable) ...[
                  const SizedBox(width: 6),
                  // Shown on the active or hovered tab; kept in the tree so
                  // the width never jumps and it stays keyboard reachable.
                  Opacity(
                    opacity: lit ? 1 : 0,
                    child: SizedBox.square(
                      dimension: 22,
                      child: IconButton(
                        tooltip: 'Close ${widget.label}',
                        onPressed: widget.onClose,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: AppColors.muted,
                        ),
                      ),
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
        if (widget.onDuplicate != null)
          PopupMenuItem(
            onTap: widget.onDuplicate,
            child: const Row(
              children: [
                Icon(Icons.content_copy_rounded, size: 16),
                SizedBox(width: 8),
                Text('Duplicate tab'),
              ],
            ),
          ),
        if (widget.onDuplicateWindow != null)
          PopupMenuItem(
            onTap: widget.onDuplicateWindow,
            child: const Row(
              children: [
                Icon(Icons.open_in_new_rounded, size: 16),
                SizedBox(width: 8),
                Text('Duplicate as new window'),
              ],
            ),
          ),
        if (widget.closable)
          PopupMenuItem(
            onTap: widget.onClose,
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
