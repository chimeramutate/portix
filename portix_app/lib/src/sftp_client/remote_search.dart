import 'dart:collection';

import 'sftp_models.dart';

const int _maxRemoteSearchDepth = 12;
const int _maxRemoteSearchDirectories = 600;
const Set<String> _remoteSearchSkippedDirectories = {
  '.cache',
  '.cargo',
  '.git',
  '.gradle',
  '.local',
  '.npm',
  '.rustup',
  '.venv',
  '.tox',
  '.m2',
  '.pub-cache',
  '__pycache__',
  'Library',
  'cache',
  'dev',
  'node_modules',
  'proc',
  'run',
  'sys',
  'tmp',
  'vendor',
  'target',
  'build',
  'dist',
  '.next',
};

/// Breadth-first search below [basePath] for entries whose name or path
/// contains [query] (lowercase), listing folders through [list]. Skips
/// caches, dependency folders and pseudo filesystems; bounded in depth and
/// in folders visited.
Future<List<RemoteFileEntry>> findRemoteEntries({
  required Future<List<RemoteFileEntry>> Function(String path) list,
  required String basePath,
  required String query,
  required int maxResults,
}) async {
  final results = <RemoteFileEntry>[];
  final visited = <String>{};
  final queue = Queue<_RemoteSearchDirectory>()
    ..add(_RemoteSearchDirectory(basePath, 0));

  // Process directories in parallel batches for faster searching.
  const batchSize = 6;

  while (queue.isNotEmpty &&
      results.length < maxResults &&
      visited.length < _maxRemoteSearchDirectories) {
    // Collect a batch of directories to process in parallel.
    final batch = <_RemoteSearchDirectory>[];
    while (batch.length < batchSize && queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.depth > _maxRemoteSearchDepth) continue;
      final normalizedPath = current.path.trim().isEmpty
          ? '/'
          : current.path.trim();
      if (!visited.add(normalizedPath)) continue;
      batch.add(_RemoteSearchDirectory(normalizedPath, current.depth));
    }
    if (batch.isEmpty) continue;

    // List all directories in the batch concurrently.
    final futures = batch.map(
      (dir) => _listForFind(
        list,
        dir.path,
        isBasePath: dir.depth == 0,
      ).then((entries) => (dir, entries)),
    );

    final batchResults = await Future.wait(futures);

    for (final (dir, entries) in batchResults) {
      if (results.length >= maxResults) break;

      final childDirectories = <RemoteFileEntry>[];
      for (final entry in entries) {
        if (results.length >= maxResults) break;
        final haystack = '${entry.name}\n${entry.path}'.toLowerCase();
        if (haystack.contains(query)) {
          results.add(entry);
        }
        if (entry.isDirectory &&
            !_shouldSkipRemoteSearchDirectory(entry, basePath)) {
          childDirectories.add(entry);
        }
      }

      childDirectories.sort(
        (a, b) => _remoteSearchPriority(
          a,
          query,
        ).compareTo(_remoteSearchPriority(b, query)),
      );
      for (final directory in childDirectories) {
        if (visited.length + queue.length >= _maxRemoteSearchDirectories) {
          break;
        }
        queue.add(_RemoteSearchDirectory(directory.path, dir.depth + 1));
      }
    }
  }

  return results;
}

Future<List<RemoteFileEntry>> _listForFind(
  Future<List<RemoteFileEntry>> Function(String path) list,
  String path, {
  required bool isBasePath,
}) async {
  try {
    return await list(path);
  } catch (error) {
    if (isBasePath) rethrow;
    return const [];
  }
}

int _remoteSearchPriority(RemoteFileEntry entry, String query) {
  final name = entry.name.toLowerCase();
  final path = entry.path.toLowerCase();
  var score = 100;
  if (path.contains(query) || name.contains(query)) score -= 60;
  if (_looksLikeMediaQuery(query) &&
      (name.contains('picture') ||
          name.contains('photo') ||
          name.contains('image') ||
          name.contains('screenshot') ||
          name.contains('download'))) {
    score -= 35;
  }
  if (!name.startsWith('.')) score -= 10;
  return score;
}

bool _looksLikeMediaQuery(String query) {
  return query.endsWith('.jpg') ||
      query.endsWith('.jpeg') ||
      query.endsWith('.png') ||
      query.endsWith('.gif') ||
      query.endsWith('.webp') ||
      query.endsWith('.heic') ||
      query.endsWith('.svg');
}

bool _shouldSkipRemoteSearchDirectory(RemoteFileEntry entry, String basePath) {
  final path = entry.path;
  if (path == '/' || path == basePath) return false;
  if (_remoteSearchSkippedDirectories.contains(entry.name)) return true;
  return path == '/proc' ||
      path.startsWith('/proc/') ||
      path == '/sys' ||
      path.startsWith('/sys/') ||
      path == '/dev' ||
      path.startsWith('/dev/') ||
      path == '/run' ||
      path.startsWith('/run/');
}

class _RemoteSearchDirectory {
  const _RemoteSearchDirectory(this.path, this.depth);

  final String path;
  final int depth;
}
