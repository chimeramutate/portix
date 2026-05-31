part of '../../page/sftp_workspace_page.dart';

class _TransferQueue extends StatelessWidget {
  const _TransferQueue({required this.jobs, required this.onClose});
  final List<SftpTransferJob> jobs;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 18,
      child: AppPanel(
        padding: const EdgeInsets.all(12),
        color: AppColors.surface.withValues(alpha: .96),
        borderColor: AppColors.primaryBlue,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Transfer Queue', style: portixTitle(12)),
                const Spacer(),
                Text(
                  '${jobs.where((job) => !job.queued).length} running / ${jobs.where((job) => job.queued).length} waiting',
                  style: portixMuted(10),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    tooltip: 'Hide transfer queue',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.muted,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final job in jobs.take(4)) _QueueRow(job: job),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.job});
  final SftpTransferJob job;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            job.direction.startsWith('Local')
                ? Icons.upload_rounded
                : Icons.download_rounded,
            color: AppColors.cyan,
            size: 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.name,
                  overflow: TextOverflow.ellipsis,
                  style: portixTitle(11),
                ),
                Text(job.direction, style: portixMuted(9)),
              ],
            ),
          ),
          Text(
            job.queued ? 'queued' : '${(job.value * 100).round()}%',
            style: portixMuted(
              10,
            ).copyWith(color: job.queued ? AppColors.muted : AppColors.cyan),
          ),
        ],
      ),
    );
  }
}
