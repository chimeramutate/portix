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
                  '${jobs.where((job) => !job.done && !job.failed).length} running / ${jobs.where((job) => job.queued).length} waiting',
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
    final color = job.failed
        ? AppColors.danger
        : job.done
        ? AppColors.green
        : AppColors.cyan;
    final label = job.failed
        ? 'failed'
        : job.done
        ? 'done'
        : job.queued
        ? 'queued'
        : '${(job.value * 100).round()}%';
    return Container(
      height: 42,
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
            color: color,
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
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: job.failed ? 1 : job.value.clamp(0, 1),
                    backgroundColor: AppColors.border.withValues(alpha: .55),
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Text(label, style: portixMuted(10).copyWith(color: color)),
        ],
      ),
    );
  }
}
