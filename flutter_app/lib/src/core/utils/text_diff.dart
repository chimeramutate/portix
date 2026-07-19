/// Represents a unified text diff with context lines.
class TextDiffResult {
  const TextDiffResult({
    required this.added,
    required this.removed,
    required this.lines,
  });

  final int added;
  final int removed;
  final List<String> lines;
}

/// Build a unified diff between [before] and [after] text content.
/// Returns null-safe result with context lines around changes.
TextDiffResult buildTextDiff(String? before, String? after) {
  if (before == null || after == null) {
    return const TextDiffResult(
      added: 0,
      removed: 0,
      lines: ['Binary or non-text diff preview is not available.'],
    );
  }
  final beforeLines = before.split('\n');
  final afterLines = after.split('\n');
  final maxLength = beforeLines.length > afterLines.length
      ? beforeLines.length
      : afterLines.length;
  var added = 0;
  var removed = 0;
  final preview = <String>[];

  const contextSize = 2;
  final changedIndices = <int>{};
  for (var index = 0; index < maxLength; index += 1) {
    final oldLine = index < beforeLines.length ? beforeLines[index] : null;
    final newLine = index < afterLines.length ? afterLines[index] : null;
    if (oldLine != newLine) changedIndices.add(index);
  }

  final visibleIndices = <int>{};
  for (final changed in changedIndices) {
    for (var offset = -contextSize; offset <= contextSize; offset += 1) {
      final idx = changed + offset;
      if (idx >= 0 && idx < maxLength) visibleIndices.add(idx);
    }
  }

  final sorted = visibleIndices.toList()..sort();
  var lastIndex = -2;
  for (final index in sorted) {
    if (preview.length >= 120) break;
    if (index > lastIndex + 1 && preview.isNotEmpty) {
      preview.add('  ···');
    }
    lastIndex = index;
    final oldLine = index < beforeLines.length ? beforeLines[index] : null;
    final newLine = index < afterLines.length ? afterLines[index] : null;
    if (oldLine == newLine) {
      preview.add('  ${oldLine ?? ''}');
    } else {
      if (oldLine != null) {
        removed += 1;
        preview.add('- $oldLine');
      }
      if (newLine != null) {
        added += 1;
        preview.add('+ $newLine');
      }
    }
  }

  return TextDiffResult(
    added: added,
    removed: removed,
    lines: preview.isEmpty ? const ['No textual diff detected.'] : preview,
  );
}
