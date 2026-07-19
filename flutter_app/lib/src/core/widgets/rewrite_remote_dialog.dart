import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/text_diff.dart';
import 'app_panel.dart';
import 'diff_badge.dart';

/// A dialog that shows a unified diff and asks the user to confirm
/// rewriting a remote file with local changes.
class RewriteRemoteDialog extends StatelessWidget {
  const RewriteRemoteDialog({
    required this.fileName,
    required this.diff,
    super.key,
  });

  final String fileName;
  final TextDiffResult diff;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.sync_alt_rounded,
                    color: AppColors.cyan,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Rewrite remote file?', style: portixTitle(16)),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fileName,
                overflow: TextOverflow.ellipsis,
                style: portixMuted(12),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  DiffBadge(label: '+${diff.added}', color: AppColors.green),
                  const SizedBox(width: 8),
                  DiffBadge(label: '-${diff.removed}', color: AppColors.danger),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.terminal,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: diff.lines.length,
                    itemBuilder: (context, index) {
                      final line = diff.lines[index];
                      final isAdd = line.startsWith('+ ');
                      final isRemove = line.startsWith('- ');
                      final isSeparator = line.trim() == '···';
                      final color = isAdd
                          ? AppColors.green
                          : isRemove
                              ? AppColors.danger
                              : isSeparator
                                  ? AppColors.muted.withValues(alpha: .5)
                                  : AppColors.text.withValues(alpha: .6);
                      final bgColor = isAdd
                          ? AppColors.green.withValues(alpha: .07)
                          : isRemove
                              ? AppColors.danger.withValues(alpha: .07)
                              : Colors.transparent;
                      return Container(
                        color: bgColor,
                        child: Text(
                          line,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            height: 1.4,
                            fontFamily: 'monospace',
                            fontWeight: (isAdd || isRemove)
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Cancel', style: portixTitle(12)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.upload_file_rounded, size: 16),
                    label: const Text('Rewrite remote'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
