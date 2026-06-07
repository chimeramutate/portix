part of '../../page/sftp_workspace_page.dart';

class _FilePane extends StatelessWidget {
  const _FilePane({
    required this.title,
    required this.path,
    required this.items,
    required this.countLabel,
    required this.onTransferDropped,
    required this.onFileAction,
    required this.onPathSubmitted,
    required this.onOpenFolder,
    required this.selectedPaths,
    required this.onItemSelected,
    required this.selectedTransferEntries,
    this.footerLeft,
    this.footerRight,
    this.loading = false,
    this.error,
    this.isRemote = false,
    this.showActions = true,
    this.contentOverride,
    this.onCreateFileRequested,
    this.onCreateFolderRequested,
    this.onRefreshRequested,
    this.inlineCreateKind,
    this.inlineCreateController,
    this.inlineCreateFocusNode,
    this.onInlineCreateSubmit,
    this.onInlineCreateCancel,
    this.findQuery = '',
    this.findBase = '/',
    this.findActive = false,
    this.findSearching = false,
    this.findError,
    this.onFindSubmitted,
    this.onFindCleared,
    this.statusTitle,
    this.statusMessage,
  });

  final String title;
  final String path;
  final List<SftpFileEntry> items;
  final String countLabel;
  final String? footerLeft;
  final String? footerRight;
  final bool loading;
  final String? error;
  final bool isRemote;
  final bool showActions;
  final Widget? contentOverride;
  final VoidCallback? onCreateFileRequested;
  final VoidCallback? onCreateFolderRequested;
  final VoidCallback? onRefreshRequested;
  final _SftpInlineCreateKind? inlineCreateKind;
  final TextEditingController? inlineCreateController;
  final FocusNode? inlineCreateFocusNode;
  final Future<void> Function()? onInlineCreateSubmit;
  final VoidCallback? onInlineCreateCancel;
  final String findQuery;
  final String findBase;
  final bool findActive;
  final bool findSearching;
  final String? findError;
  final ValueChanged<String>? onFindSubmitted;
  final VoidCallback? onFindCleared;
  final String? statusTitle;
  final String? statusMessage;
  final ValueChanged<SftpFileTransfer> onTransferDropped;
  final void Function(_FileAction action, SftpFileEntry file) onFileAction;
  final ValueChanged<String> onPathSubmitted;
  final Set<String> selectedPaths;
  final void Function(SftpFileEntry file, int index, List<SftpFileEntry> rows)
  onItemSelected;
  final List<SftpFileEntry> Function(SftpFileEntry file)
  selectedTransferEntries;
  // final ValueChanged<String> onOpenFolder;
  final void Function(SftpFileEntry data) onOpenFolder;
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return DragTarget<SftpFileTransfer>(
      onWillAcceptWithDetails: (details) => details.data.fromRemote != isRemote,
      onAcceptWithDetails: (details) => onTransferDropped(details.data),
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;
        return AppPanel(
          padding: const EdgeInsets.all(14),
          borderColor: isDropTarget ? AppColors.cyan : AppColors.border,
          color: isDropTarget
              ? AppColors.surfaceCard.withValues(alpha: .78)
              : AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isRemote ? Icons.dns_outlined : Icons.computer_rounded,
                    color: isRemote ? AppColors.green : AppColors.cyan,
                    size: 18,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: portixTitle(compact ? 14 : 16),
                    ),
                  ),
                  AppPill(
                    label: countLabel,
                    color: isRemote ? AppColors.green : AppColors.cyan,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PathBar(path: path, onSubmitted: onPathSubmitted),
              if (showActions) ...[
                const SizedBox(height: 12),
                _PaneActions(
                  isRemote: isRemote,
                  onCreateFileRequested: onCreateFileRequested,
                  onCreateFolderRequested: onCreateFolderRequested,
                  onRefreshRequested: onRefreshRequested,
                ),
              ],
              if (onFindSubmitted != null) ...[
                const SizedBox(height: 10),
                _RemoteFindBar(
                  query: findQuery,
                  base: findBase,
                  active: findActive,
                  searching: findSearching,
                  error: findError,
                  remote: isRemote,
                  onSubmitted: onFindSubmitted!,
                  onCleared: onFindCleared,
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDropTarget ? AppColors.cyan : AppColors.border,
                    ),
                  ),
                  child: contentOverride != null
                      ? contentOverride
                      : loading
                      ? _PaneStatus(
                          icon: Icons.folder_open_rounded,
                          title:
                              statusTitle ??
                              (isRemote
                                  ? 'Loading remote folder'
                                  : 'Loading local folder'),
                          message:
                              statusMessage ??
                              (isRemote
                                  ? 'Reading files from remote...'
                                  : 'Reading files from this computer...'),
                        )
                      : error != null
                      ? _PaneStatus(
                          icon: Icons.error_outline_rounded,
                          title:
                              statusTitle ??
                              (isRemote
                                  ? 'Remote unavailable'
                                  : 'Local folder unavailable'),
                          message: statusMessage ?? error!,
                        )
                      : Column(
                          children: [
                            if (!compact) _TableHeader(isRemote: isRemote),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final createActive =
                                      inlineCreateKind != null &&
                                      inlineCreateController != null &&
                                      inlineCreateFocusNode != null &&
                                      onInlineCreateSubmit != null &&
                                      onInlineCreateCancel != null;
                                  return ListView.builder(
                                    itemCount:
                                        items.length + (createActive ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (createActive && index == 0) {
                                        return _SftpInlineCreateItem(
                                          kind: inlineCreateKind!,
                                          controller: inlineCreateController!,
                                          focusNode: inlineCreateFocusNode!,
                                          onSubmit: onInlineCreateSubmit!,
                                          onCancel: onInlineCreateCancel!,
                                        );
                                      }
                                      final item =
                                          items[index - (createActive ? 1 : 0)];
                                      final itemIndex =
                                          index - (createActive ? 1 : 0);
                                      return _FileRow(
                                        data: item,
                                        selected:
                                            item.path != null &&
                                            selectedPaths.contains(item.path),
                                        isRemote: isRemote,
                                        onOpenFolder: onOpenFolder,
                                        onAction: onFileAction,
                                        onSelected: () => onItemSelected(
                                          item,
                                          itemIndex,
                                          items,
                                        ),
                                        dragEntries: selectedTransferEntries(
                                          item,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            _PaneFooter(
                              left: footerLeft ?? '${items.length} items',
                              right: footerRight ?? '',
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PaneStatus extends StatelessWidget {
  const _PaneStatus({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppPanel(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.muted, size: 24),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: portixTitle(13)),
            const SizedBox(height: 5),
            Text(message, textAlign: TextAlign.center, style: portixMuted(11)),
          ],
        ),
      ),
    );
  }
}

class _PathBar extends StatefulWidget {
  const _PathBar({required this.path, required this.onSubmitted});
  final String path;
  final ValueChanged<String> onSubmitted;

  @override
  State<_PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<_PathBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.path,
  );

  @override
  void didUpdateWidget(covariant _PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller.text = widget.path;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, color: AppColors.muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: widget.onSubmitted,
              style: portixTitle(12),
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
            onPressed: () => widget.onSubmitted(_controller.text),
            icon: const Icon(
              Icons.keyboard_return_rounded,
              color: AppColors.muted,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteFindBar extends StatefulWidget {
  const _RemoteFindBar({
    required this.query,
    required this.base,
    required this.active,
    required this.searching,
    required this.remote,
    required this.onSubmitted,
    this.error,
    this.onCleared,
  });

  final String query;
  final String base;
  final bool active;
  final bool searching;
  final bool remote;
  final String? error;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onCleared;

  @override
  State<_RemoteFindBar> createState() => _RemoteFindBarState();
}

class _RemoteFindBarState extends State<_RemoteFindBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(covariant _RemoteFindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _controller.text != widget.query) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.active ? AppColors.cyan : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          widget.searching
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.search_rounded,
                  color: widget.error == null
                      ? AppColors.cyan
                      : AppColors.danger,
                  size: 17,
                ),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: widget.onSubmitted,
              style: portixTitle(12),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                hintText:
                    widget.error ??
                    (widget.remote
                        ? 'Find remote file or folder'
                        : 'Find local file or folder'),
                hintStyle: portixMuted(12).copyWith(
                  color: widget.error == null
                      ? AppColors.muted
                      : AppColors.danger,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (widget.active || widget.error != null)
            IconButton(
              tooltip: widget.searching ? 'Cancel find' : 'Clear find',
              onPressed: widget.onCleared,
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.muted,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}

class _PaneActions extends StatelessWidget {
  const _PaneActions({
    required this.isRemote,
    this.onCreateFileRequested,
    this.onCreateFolderRequested,
    this.onRefreshRequested,
  });

  final bool isRemote;
  final VoidCallback? onCreateFileRequested;
  final VoidCallback? onCreateFolderRequested;
  final VoidCallback? onRefreshRequested;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.note_add_outlined, 'New file', onCreateFileRequested),
      (Icons.create_new_folder_outlined, 'New folder', onCreateFolderRequested),
      (Icons.refresh_rounded, 'Reload', onRefreshRequested),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return Tooltip(
            message: action.$2,
            child: SizedBox.square(
              dimension: 34,
              child: OutlinedButton(
                onPressed: action.$3,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: AppColors.text,
                  side: BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Icon(action.$1, size: 16),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SftpInlineCreateItem extends StatelessWidget {
  const _SftpInlineCreateItem({
    required this.kind,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
  });

  final _SftpInlineCreateKind kind;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isFolder = kind == _SftpInlineCreateKind.folder;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: .58),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: .9),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            color: isFolder ? AppColors.amber : AppColors.muted,
            size: 17,
          ),
          const SizedBox(width: 12),
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
          IconButton(
            tooltip: 'Cancel',
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.muted,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.isRemote});
  final bool isRemote;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Name', style: portixLabel(11))),
          Expanded(
            flex: 2,
            child: Text(isRemote ? 'Type' : 'Size', style: portixLabel(11)),
          ),
          Expanded(
            flex: 2,
            child: Text(isRemote ? 'Size' : 'Modified', style: portixLabel(11)),
          ),
          Expanded(
            flex: 2,
            child: Text(isRemote ? 'Updated' : '', style: portixLabel(11)),
          ),
        ],
      ),
    );
  }
}
