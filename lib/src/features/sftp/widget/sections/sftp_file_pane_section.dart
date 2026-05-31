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
    this.footerLeft,
    this.footerRight,
    this.loading = false,
    this.error,
    this.isRemote = false,
    this.showActions = true,
    this.contentOverride,
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
  final ValueChanged<SftpFileTransfer> onTransferDropped;
  final void Function(_FileAction action, SftpFileEntry file) onFileAction;
  final ValueChanged<String> onPathSubmitted;
  // final ValueChanged<String> onOpenFolder;
  final void Function(SftpFileEntry data) onOpenFolder;
  @override
  Widget build(BuildContext context) {
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
                  Expanded(child: Text(title, style: portixTitle(16))),
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
                _PaneActions(isRemote: isRemote),
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
                      ? const _PaneStatus(
                          icon: Icons.folder_open_rounded,
                          title: 'Loading local folder',
                          message: 'Reading files from this computer...',
                        )
                      : error != null
                      ? _PaneStatus(
                          icon: Icons.error_outline_rounded,
                          title: isRemote
                              ? 'Remote unavailable'
                              : 'Local folder unavailable',
                          message: error!,
                        )
                      : Column(
                          children: [
                            _TableHeader(isRemote: isRemote),
                            Expanded(
                              child: ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return _FileRow(
                                    data: item,
                                    selected: false,
                                    isRemote: isRemote,
                                    onOpenFolder: onOpenFolder,
                                    onAction: onFileAction,
                                  );
                                },
                              ),
                            ),
                            _PaneFooter(
                              left: footerLeft ?? '${items.length} items',
                              right:
                                  footerRight ??
                                  (isRemote ? 'Free: 19.2 GB' : ''),
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

class _PaneActions extends StatelessWidget {
  const _PaneActions({required this.isRemote});
  final bool isRemote;

  @override
  Widget build(BuildContext context) {
    final actions = isRemote
        ? const [
            (Icons.upload_rounded, 'Put'),
            (Icons.download_rounded, 'Get'),
            (Icons.copy_rounded, 'Duplicate'),
            (Icons.delete_outline_rounded, 'Delete'),
          ]
        : const [
            (Icons.add_rounded, 'New'),
            (Icons.upload_rounded, 'Upload'),
            (Icons.create_new_folder_outlined, 'Folder'),
            (Icons.search_rounded, 'Find'),
          ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return AppButton(icon: action.$1, label: action.$2, onPressed: () {});
        },
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
