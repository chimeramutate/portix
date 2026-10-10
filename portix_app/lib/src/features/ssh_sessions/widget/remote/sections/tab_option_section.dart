part of '../terminal_workspace_view.dart';

class TerminalSessionTab extends StatelessWidget {
  const TerminalSessionTab({
    required this.sessionId,
    required this.label,
    this.active = false,
    this.status = session_models.ConnectionStatus.connected,
    this.leadingIcon,
    this.draggable = true,
    this.onTap,
    this.onClose,
    this.onReconnect,
    this.onDuplicate,
    this.onRename,
    this.reconnectNearClose = false,
  });

  final String sessionId;
  final String label;
  final bool active;
  final session_models.ConnectionStatus status;
  final IconData? leadingIcon;
  final bool draggable;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final VoidCallback? onReconnect;
  final VoidCallback? onDuplicate;
  final VoidCallback? onRename;
  final bool reconnectNearClose;

  void _showContextMenu(BuildContext context, Offset position) {
    final canReconnect =
        status == session_models.ConnectionStatus.disconnected ||
        status == session_models.ConnectionStatus.error;

    showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.menu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      items: [
        if (onRename != null)
          PopupMenuItem(
            value: _TabMenuAction.rename,
            height: 38,
            child: Row(
              children: [
                Icon(Icons.edit_rounded, color: AppColors.cyan, size: 16),
                const SizedBox(width: 10),
                Text('Rename', style: portixTitle(13)),
              ],
            ),
          ),
        PopupMenuItem(
          value: _TabMenuAction.duplicate,
          height: 38,
          child: Row(
            children: [
              Icon(Icons.copy_all_rounded, color: AppColors.cyan, size: 16),
              const SizedBox(width: 10),
              Text('Duplicate', style: portixTitle(13)),
            ],
          ),
        ),
        if (canReconnect && onReconnect != null)
          PopupMenuItem(
            value: _TabMenuAction.reconnect,
            height: 38,
            child: Row(
              children: [
                Icon(Icons.refresh_rounded, color: AppColors.amber, size: 16),
                const SizedBox(width: 10),
                Text('Reconnect', style: portixTitle(13)),
              ],
            ),
          ),
        PopupMenuItem(
          value: _TabMenuAction.close,
          height: 38,
          child: Row(
            children: [
              Icon(Icons.close_rounded, color: AppColors.muted, size: 16),
              const SizedBox(width: 10),
              Text('Close', style: portixTitle(13)),
            ],
          ),
        ),
      ],
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case _TabMenuAction.rename:
          onRename?.call();
        case _TabMenuAction.duplicate:
          onDuplicate?.call();
        case _TabMenuAction.reconnect:
          onReconnect?.call();
        case _TabMenuAction.close:
          onClose?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = status == session_models.ConnectionStatus.connected;
    final connecting = status == session_models.ConnectionStatus.connecting;
    final canReconnect =
        status == session_models.ConnectionStatus.disconnected ||
        status == session_models.ConnectionStatus.error;
    final tab = _HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        key: ValueKey('terminal-session-tab-$sessionId'),
        onTap: onTap,
        onSecondaryTapUp: onDuplicate == null
            ? null
            : (details) => _showContextMenu(context, details.globalPosition),
        // Flat tab: the active one takes the panel color and a top marker.
        child: Container(
          height: 36,
          width: 200,
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            border: Border(
              top: BorderSide(
                color: active ? AppColors.cyan : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              if (canReconnect && onReconnect != null && !reconnectNearClose)
                SizedBox.square(
                  dimension: 22,
                  child: IconButton(
                    tooltip: 'Reconnect $label',
                    onPressed: onReconnect,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: AppColors.amber,
                      size: 15,
                    ),
                  ),
                )
              else
                Icon(
                  leadingIcon ??
                      (connecting ? Icons.sync_rounded : Icons.circle),
                  size: leadingIcon == null && !connecting ? 8 : 15,
                  // The dot is the connection status, active tab or not.
                  color: connected ? AppColors.green : AppColors.muted,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? AppColors.text : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canReconnect && onReconnect != null && reconnectNearClose)
                SizedBox.square(
                  dimension: 22,
                  child: IconButton(
                    tooltip: 'Reconnect $label',
                    onPressed: onReconnect,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: AppColors.amber,
                      size: 15,
                    ),
                  ),
                ),
              // Close shows on the active or hovered tab; it stays in the
              // tree (and keyboard reachable) so the layout never shifts.
              _RevealOnFocus(
                visible: active || hovered,
                child: SizedBox.square(
                  dimension: 22,
                  child: IconButton(
                    key: ValueKey('close-tab-$label'),
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    tooltip: 'Close $label',
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.muted,
                      size: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!draggable) return tab;
    return Draggable<String>(
      data: sessionId,
      onDragStarted: () => PaneDragHandle.dragging.value = true,
      onDragEnd: (_) => PaneDragHandle.dragging.value = false,
      onDraggableCanceled: (_, _) => PaneDragHandle.dragging.value = false,
      feedback: Material(color: Colors.transparent, child: tab),
      childWhenDragging: Opacity(opacity: .45, child: tab),
      child: tab,
    );
  }
}

class SessionProfileOption extends StatelessWidget {
  const SessionProfileOption({
    required this.profile,
    required this.onSelected,
    this.highlighted = false,
    this.subtitleLabel,
  });

  final domain.SshProfile profile;
  final VoidCallback onSelected;
  final bool highlighted;
  final String? subtitleLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('new-session-profile-${profile.id}'),
        onTap: onSelected,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: highlighted ? AppColors.selectedSoft : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted ? AppColors.cyan : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.cyan),
                ),
                child: Icon(
                  Icons.dns_rounded,
                  color: AppColors.muted,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(profile.name, style: portixTitle(14)),
                        ),
                        if (subtitleLabel != null) ...[
                          const SizedBox(width: 8),
                          AppPill(label: subtitleLabel!, color: AppColors.cyan),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.address,
                      overflow: TextOverflow.ellipsis,
                      style: portixMuted(12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TabMenuAction { rename, duplicate, reconnect, close }

class _HoverBuilder extends StatefulWidget {
  const _HoverBuilder({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}

/// Fully visible when [visible] or while its child has keyboard focus.
class _RevealOnFocus extends StatefulWidget {
  const _RevealOnFocus({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_RevealOnFocus> createState() => _RevealOnFocusState();
}

class _RevealOnFocusState extends State<_RevealOnFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) => setState(() => _focused = focused),
    child: Opacity(
      opacity: widget.visible || _focused ? 1 : 0,
      child: widget.child,
    ),
  );
}
