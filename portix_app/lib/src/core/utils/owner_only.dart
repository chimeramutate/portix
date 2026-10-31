import 'dart:io';

/// Limits [path] to its owner, for files that can hold terminal output.
/// Windows profiles already keep other users out.
void restrictToOwner(String path, {bool directory = false}) {
  if (Platform.isWindows) return;
  Process.runSync('chmod', [directory ? '700' : '600', path]);
}
