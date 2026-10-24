import 'dart:async';
import 'dart:io';

/// Watches local copies of remote files opened in an external editor.
class LocalEditWatcher {
  final Map<String, Timer> _timers = {};

  /// Polls [localPath] every 2 s and runs [onSaved] after each save, never
  /// two at once. Watching a path again replaces its previous watch.
  Future<void> watch(String localPath, Future<void> Function() onSaved) async {
    final file = File(localPath);
    var lastSeen = (await file.stat()).modified;
    var running = false;
    _timers.remove(localPath)?.cancel();
    _timers[localPath] = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      try {
        final modified = (await file.stat()).modified;
        if (!modified.isAfter(lastSeen)) return;
        lastSeen = modified;
        if (running) return;
        running = true;
        await onSaved();
        running = false;
      } catch (_) {
        timer.cancel();
        _timers.remove(localPath);
      }
    });
  }

  void unwatch(String localPath) => _timers.remove(localPath)?.cancel();

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// The file's text, or null when it is unreadable or binary.
Future<String?> readTextIfPossible(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    if (bytes.contains(0)) return null;
    return String.fromCharCodes(bytes);
  } catch (_) {
    return null;
  }
}
