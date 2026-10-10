import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:xterm/xterm.dart';

/// Most terminal lines kept in a snapshot.
const maxSnapshotLines = 3000;

/// A saved SSH tab: its name and the terminal text at save time. Opening it
/// connects to [profileId] again with this text shown above the new prompt.
class SessionSnapshot {
  const SessionSnapshot({
    required this.id,
    required this.profileId,
    required this.title,
    required this.savedAt,
    required this.output,
  });

  factory SessionSnapshot.fromJson(Map<String, Object?> json) =>
      SessionSnapshot(
        id: json['id']! as String,
        profileId: json['profileId']! as String,
        title: json['title']! as String,
        savedAt: DateTime.parse(json['savedAt']! as String),
        output: json['output']! as String,
      );

  final String id;
  final String profileId;
  final String title;
  final DateTime savedAt;

  /// Plain terminal text, lines separated by `\n`.
  final String output;

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'title': title,
    'savedAt': savedAt.toIso8601String(),
    'output': output,
  };
}

/// The terminal's text (scrollback included) with soft-wrapped lines joined
/// and trailing blank lines dropped; at most the last [maxSnapshotLines].
///
/// ponytail: plain text, colors are lost; keep the raw output stream if
/// restored snapshots need them.
String terminalSnapshotText(Terminal terminal) {
  final lines = <String>[];
  final buffer = terminal.buffer.lines;
  for (var i = 0; i < buffer.length; i++) {
    final line = buffer[i];
    final text = line.getText().trimRight();
    if (line.isWrapped && lines.isNotEmpty) {
      lines[lines.length - 1] += text;
    } else {
      lines.add(text);
    }
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  final start = lines.length > maxSnapshotLines
      ? lines.length - maxSnapshotLines
      : 0;
  return lines.sublist(start).join('\n');
}

/// Saved snapshots in one JSON file next to the settings, newest first.
class SessionSnapshotStore {
  SessionSnapshotStore({Future<File> Function()? file})
    : _file = file ?? _defaultFile;

  final Future<File> Function() _file;

  static Future<File> _defaultFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}session_snapshots.json',
    );
  }

  Future<List<SessionSnapshot>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    if (content.trim().isEmpty) return [];
    return [
      for (final item in jsonDecode(content) as List<Object?>)
        SessionSnapshot.fromJson(item! as Map<String, Object?>),
    ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  Future<void> save(SessionSnapshot snapshot) async =>
      _write([snapshot, ...(await load()).where((s) => s.id != snapshot.id)]);

  Future<void> delete(String id) async =>
      _write((await load()).where((s) => s.id != id).toList());

  Future<void> _write(List<SessionSnapshot> snapshots) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Terminal output can hold secrets; it stays in the per-user app
    // support folder, like settings.json.
    await file.writeAsString(
      jsonEncode([for (final s in snapshots) s.toJson()]),
    );
  }
}

/// What a restored tab shows above the new session's prompt: the saved
/// text, dimmed, between two markers.
String restoredSnapshotText(SessionSnapshot snapshot) {
  final body = snapshot.output.replaceAll('\n', '\r\n');
  return '\x1b[2m── restored "${snapshot.title}" '
      '(${snapshot.savedAt.toLocal()}) ──\r\n'
      '$body\r\n'
      '── new session ──\x1b[0m\r\n';
}
