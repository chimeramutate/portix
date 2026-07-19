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
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RemoteOsChip(snapshot: snapshot, error: error),
            const SizedBox(width: 8),
            _UptimeChip(snapshot: snapshot, error: error),
            const SizedBox(width: 8),
            if (!compact || constraints.maxWidth >= 460) ...[
              _MetricStrip(
                label: 'Memory',
                value: _capacityLabel(
                  snapshot?.memoryUsedBytes,
                  snapshot?.memoryTotalBytes,
                ),
                color: AppColors.cyan,
                samples: [for (final sample in samples) sample.memoryPercent],
              ),
              const SizedBox(width: 8),
              _MetricStrip(
                label: 'Disk',
                value: _capacityLabel(
                  snapshot?.diskUsedBytes,
                  snapshot?.diskTotalBytes,
                ),
                color: AppColors.amber,
                samples: [for (final sample in samples) sample.diskPercent],
              ),
            ],
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
        if (compact) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
        }
        return Center(child: content);
      },
    );
  }

  static String _capacityLabel(int? used, int? total) {
    if (used == null || total == null) return '--';
    if (total <= 0) return '--';
    final percent = used / total.clamp(1, 1 << 62);
    return '${_bytesLabel(used)} / ${_bytesLabel(total)} ${percentLabel(percent)}';
  }

  static String percentLabel(double ratio) {
    return '(${(ratio * 100).clamp(0, 100).round()}%)';
  }

  static String _bytesLabel(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final precision = value >= 10 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)}${units[unitIndex]}';
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
        : _osAssetPath(snapshot!.os);
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
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Up $value',
              overflow: TextOverflow.ellipsis,
              style: portixMuted(11).copyWith(
                color: error == null ? AppColors.text : AppColors.amber,
                fontWeight: FontWeight.w900,
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
      width: 210,
      height: 42,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(
                    11,
                  ).copyWith(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 18,
                  child: _MiniLineChart(color: color, values: samples),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: portixMuted(10).copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
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
    final yBounds = _dynamicBounds(chartValues);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 24 || constraints.maxHeight < 8) {
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: color, width: 2)),
            ),
          );
        }
        return LineChart(
          duration: Duration.zero,
          LineChartData(
            minY: yBounds.$1,
            maxY: yBounds.$2,
            minX: 0,
            maxX: (_windowSize - 1).toDouble(),
            clipData: const FlClipData.all(),
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var index = 0; index < chartValues.length; index += 1)
                    FlSpot(index.toDouble(), chartValues[index]),
                ],
                isCurved: false,
                color: color,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withValues(alpha: .14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<double> _fixedWindowValues() {
    if (values.isEmpty) return List<double>.filled(_windowSize, 0);
    final visible = values.length > _windowSize
        ? values.sublist(values.length - _windowSize)
        : values;
    final first = visible.first.isFinite
        ? visible.first.clamp(0, 100).toDouble()
        : 0.0;
    return [
      for (var index = visible.length; index < _windowSize; index += 1) first,
      for (final value in visible)
        value.isFinite ? value.clamp(0, 100).toDouble() : 0.0,
    ];
  }

  (double, double) _dynamicBounds(List<double> chartValues) {
    if (chartValues.isEmpty) return (0, 100);
    final minValue = chartValues.reduce((a, b) => a < b ? a : b);
    final maxValue = chartValues.reduce((a, b) => a > b ? a : b);
    if ((maxValue - minValue).abs() < 0.8) {
      final center = maxValue;
      return (
        (center - 4).clamp(0, 100).toDouble(),
        (center + 4).clamp(0, 100).toDouble(),
      );
    }
    final padding = ((maxValue - minValue) * .35).clamp(2, 12).toDouble();
    return (
      (minValue - padding).clamp(0, 100).toDouble(),
      (maxValue + padding).clamp(0, 100).toDouble(),
    );
  }
}
