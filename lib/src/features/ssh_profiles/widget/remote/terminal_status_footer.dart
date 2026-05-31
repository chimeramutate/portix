import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

class RemoteMetricSample {
  const RemoteMetricSample({
    required this.createdAt,
    required this.memoryPercent,
    required this.diskPercent,
    this.cpuPercent,
  });

  final DateTime createdAt;
  final double memoryPercent;
  final double diskPercent;
  final double? cpuPercent;
}

class TerminalStatusFooter extends StatelessWidget {
  const TerminalStatusFooter({
    required this.snapshot,
    required this.samples,
    required this.onUngroupWorkspace,
    required this.canUngroupWorkspace,
    this.error,
    super.key,
  });

  final session_models.RemoteSystemSnapshot? snapshot;
  final List<RemoteMetricSample> samples;
  final String? error;
  final bool canUngroupWorkspace;
  final VoidCallback? onUngroupWorkspace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Row(
          children: [
            _RemoteOsChip(snapshot: snapshot, error: error, compact: compact),
            const SizedBox(width: 10),
            _MetricStrip(
              label: 'Memory',
              value: _percentLabel(
                snapshot?.memoryUsedBytes,
                snapshot?.memoryTotalBytes,
              ),
              color: AppColors.cyan,
              samples: [for (final sample in samples) sample.memoryPercent],
            ),
            const SizedBox(width: 10),
            _MetricStrip(
              label: 'Disk',
              value: _percentLabel(
                snapshot?.diskUsedBytes,
                snapshot?.diskTotalBytes,
              ),
              color: AppColors.amber,
              samples: [for (final sample in samples) sample.diskPercent],
            ),
            if (canUngroupWorkspace) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Ungroup active workspace',
                onPressed: onUngroupWorkspace,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                icon: const Icon(
                  Icons.call_split_rounded,
                  color: AppColors.muted,
                  size: 18,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _percentLabel(int? used, int? total) {
    if (used == null || total == null) return '--';
    if (total <= 0) return '--';
    final percent = used / total.clamp(1, 1 << 62);
    return '${(percent * 100).clamp(0, 100).round()}%';
  }
}

class _RemoteOsChip extends StatelessWidget {
  const _RemoteOsChip({
    required this.snapshot,
    required this.error,
    required this.compact,
  });

  final session_models.RemoteSystemSnapshot? snapshot;
  final String? error;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = error != null
        ? 'N/A'
        : snapshot == null
        ? '--'
        : _shortOsLabel(snapshot!.os);
    final assetPath = snapshot == null || error != null
        ? null
        : _osAssetPath(snapshot!.os);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 100 : 150),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OsIcon(assetPath: assetPath, error: error != null),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: portixMuted(12).copyWith(
                color: error == null ? AppColors.text : AppColors.amber,
                fontWeight: FontWeight.w900,
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

  String _osAssetPath(String os) {
    final normalized = os.toLowerCase();
    if (normalized.contains('ubuntu'))
      return 'assets/icons/os/ubuntu-linux.svg';
    if (normalized.contains('debian'))
      return 'assets/icons/os/debian-linux.svg';
    if (normalized.contains('fedora'))
      return 'assets/icons/os/fedora-linux.svg';
    if (normalized.contains('centos'))
      return 'assets/icons/os/centos-linux.svg';
    if (normalized.contains('red hat') || normalized.contains('redhat')) {
      return 'assets/icons/os/redhat-linux.svg';
    }
    if (normalized.contains('arch')) return 'assets/icons/os/arch-linux.svg';
    if (normalized.contains('windows')) return 'assets/icons/os/windows.svg';
    if (normalized.contains('darwin') ||
        normalized.contains('mac') ||
        normalized.contains('apple')) {
      return 'assets/icons/os/apple.svg';
    }
    return 'assets/icons/os/linux.svg';
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
          const Icon(Icons.dns_rounded, color: AppColors.green, size: 16),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({
    required this.label,
    required this.value,
    required this.color,
    required this.samples,
  });

  final String label;
  final String value;
  final Color color;
  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              '$label $value',
              overflow: TextOverflow.ellipsis,
              style: portixMuted(
                11,
              ).copyWith(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniLineChart(color: color, values: samples),
          ),
        ],
      ),
    );
  }
}

class _MiniLineChart extends StatelessWidget {
  const _MiniLineChart({required this.color, required this.values});

  static const int _windowSize = 20;

  final Color color;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final chartValues = _fixedWindowValues();
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        minX: 0,
        maxX: (_windowSize - 1).toDouble(),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var index = 0; index < chartValues.length; index += 1)
                FlSpot(index.toDouble(), chartValues[index].clamp(0, 100)),
            ],
            isCurved: true,
            color: color,
            barWidth: 2.4,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: .14),
            ),
          ),
        ],
      ),
    );
  }

  List<double> _fixedWindowValues() {
    if (values.isEmpty) return List<double>.filled(_windowSize, 0);
    final visible = values.length > _windowSize
        ? values.sublist(values.length - _windowSize)
        : values;
    final first = visible.first;
    return [
      for (var index = visible.length; index < _windowSize; index += 1) first,
      ...visible,
    ];
  }
}
