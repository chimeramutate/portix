import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_telemetry_controller.dart'
    show osIconAssetFor;

/// Neutral until usage needs attention: amber from 85%, danger from 95%.
Color usageLevelColor(double ratio) => ratio >= .95
    ? AppColors.danger
    : ratio >= .85
    ? AppColors.amber
    : AppColors.text;

/// One-line status bar under the terminal: OS, uptime, memory and disk.
class TerminalStatusFooter extends StatelessWidget {
  const TerminalStatusFooter({
    required this.snapshot,
    required this.onUngroupWorkspace,
    required this.canUngroupWorkspace,
    this.error,
    super.key,
  });

  final session_models.RemoteSystemSnapshot? snapshot;
  final String? error;
  final bool canUngroupWorkspace;
  final VoidCallback? onUngroupWorkspace;

  @override
  Widget build(BuildContext context) {
    final snapshot = this.snapshot;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showMetrics = constraints.maxWidth >= 460;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _RemoteOsChip(snapshot: snapshot, error: error),
              const SizedBox(width: 14),
              _UptimeChip(snapshot: snapshot, error: error),
              if (showMetrics) ...[
                const SizedBox(width: 14),
                _UsageMeter(
                  label: 'Memory',
                  used: snapshot?.memoryUsedBytes,
                  total: snapshot?.memoryTotalBytes,
                ),
                const SizedBox(width: 14),
                _UsageMeter(
                  label: 'Disk',
                  used: snapshot?.diskUsedBytes,
                  total: snapshot?.diskTotalBytes,
                ),
              ],
              if (canUngroupWorkspace) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Ungroup active workspace',
                  onPressed: onUngroupWorkspace,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 22,
                    height: 22,
                  ),
                  icon: Icon(
                    Icons.call_split_rounded,
                    color: AppColors.muted,
                    size: 15,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String percentLabel(double ratio) =>
      '${(ratio * 100).clamp(0, 100).round()}%';

  static String bytesLabel(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final precision = value >= 10 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
  }
}

/// `Memory 6.4 GB / 16 GB  [bar]  41%`; the bar and percent turn amber or
/// danger near full, the percent carries the level so color is not alone.
class _UsageMeter extends StatelessWidget {
  const _UsageMeter({required this.label, this.used, this.total});

  final String label;
  final int? used;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final used = this.used;
    final total = this.total;
    final known = used != null && total != null && total > 0;
    final ratio = known ? (used / total).clamp(0.0, 1.0) : 0.0;
    final level = usageLevelColor(ratio);
    final value = TextStyle(
      color: AppColors.text,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: portixMuted(11)),
        const SizedBox(width: 6),
        Text(
          known
              ? '${TerminalStatusFooter.bytesLabel(used)} / '
                    '${TerminalStatusFooter.bytesLabel(total)}'
              : '--',
          style: value,
        ),
        if (known) ...[
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: 48,
              height: 4,
              child: LinearProgressIndicator(
                value: ratio,
                color: level == AppColors.text ? AppColors.muted : level,
                backgroundColor: AppColors.border,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            TerminalStatusFooter.percentLabel(ratio),
            style: value.copyWith(color: level),
          ),
        ],
      ],
    );
  }
}

class _RemoteOsChip extends StatelessWidget {
  const _RemoteOsChip({required this.snapshot, required this.error});

  final session_models.RemoteSystemSnapshot? snapshot;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final label = error != null
        ? 'N/A'
        : snapshot == null
        ? '--'
        : _shortOsLabel(snapshot!.os);
    final assetPath = snapshot == null || error != null
        ? null
        : osIconAssetFor(snapshot!.os);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OsIcon(assetPath: assetPath, error: error != null),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: portixMuted(11).copyWith(
                color: error == null ? AppColors.text : AppColors.amber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortOsLabel(String os) {
    final normalized = os.trim();
    if (normalized.isEmpty) return '--';
    final firstToken = normalized.split(RegExp(r'\s+')).first;
    return firstToken;
  }
}

class _OsIcon extends StatelessWidget {
  const _OsIcon({required this.assetPath, required this.error});

  final String? assetPath;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final assetPath = this.assetPath;
    if (assetPath == null) {
      return Icon(
        error ? Icons.cloud_off_outlined : Icons.dns_rounded,
        color: error ? AppColors.amber : AppColors.green,
        size: 16,
      );
    }

    return SvgPicture.asset(
      assetPath,
      width: 17,
      height: 17,
      fit: BoxFit.contain,
      placeholderBuilder: (_) =>
          Icon(Icons.dns_rounded, color: AppColors.muted, size: 16),
    );
  }
}

class _UptimeChip extends StatelessWidget {
  const _UptimeChip({required this.snapshot, required this.error});

  final session_models.RemoteSystemSnapshot? snapshot;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final value = error != null
        ? 'offline'
        : snapshot == null
        ? '--'
        : _shortUptime(snapshot!.uptime);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 130),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            color: error == null ? AppColors.green : AppColors.amber,
            size: 14,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Up $value',
              overflow: TextOverflow.ellipsis,
              style: portixMuted(11).copyWith(
                color: error == null ? AppColors.text : AppColors.amber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortUptime(String uptime) {
    final trimmed = uptime.trim();
    if (trimmed.isEmpty) return '--';
    final upMatch = RegExp(
      r'\bup\s+(.+?)(?:,\s+\d+\s+users?|\s+load average:|$)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final source = (upMatch?.group(1) ?? trimmed)
        .replaceFirst(RegExp(r'^up\s+', caseSensitive: false), '')
        .trim();
    final parts = source
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    final normalized = parts.isEmpty ? source : parts.join(' ');
    return normalized
        .replaceAll(RegExp(r'\bdays?\b'), 'd')
        .replaceAll(RegExp(r'\bhours?\b'), 'h')
        .replaceAll(RegExp(r'\bmins?(?:utes?)?\b'), 'm')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
