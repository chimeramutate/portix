import 'dart:io';

import 'package:flutter/material.dart';

class LocalEditor {
  const LocalEditor(
    this.name,
    this.command, {
    this.arguments = const [],
    this.icon,
    this.svgAsset,
  });

  final String name;
  final String command;
  final List<String> arguments;
  final IconData? icon;
  final String? svgAsset;

  /// The OS "open with default app" entry rather than a real editor.
  bool get isSystemDefault => Platform.isWindows
      ? command == 'cmd.exe' && arguments.contains('start')
      : command == 'open' && arguments.isEmpty;
}

/// The editor to open with when the user didn't pick one: a real editor when
/// [preferCodeEditor], else the OS default on macOS/Windows, else the first.
LocalEditor? preferredLocalEditor(
  List<LocalEditor> editors, {
  required bool preferCodeEditor,
}) {
  if (editors.isEmpty) return null;
  if (preferCodeEditor) {
    for (final editor in editors) {
      if (!editor.isSystemDefault) return editor;
    }
  }
  if (Platform.isMacOS || Platform.isWindows) {
    for (final editor in editors) {
      if (editor.isSystemDefault) return editor;
    }
  }
  return editors.first;
}
