import 'dart:io';

import 'package:flutter/material.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';

class LocalEditorService {
  Future<List<LocalEditor>> detectEditors() async {
    final candidates = <LocalEditor>[
      if (Platform.isMacOS) ...const [
        LocalEditor(
          'Visual Studio Code',
          'code',
          svgAsset: 'assets/icons/editor/vscode.svg',
        ),
        LocalEditor('Cursor', 'cursor', icon: Icons.code_rounded),
        LocalEditor('Zed', 'zed', svgAsset: 'assets/icons/editor/zed.svg'),
        LocalEditor(
          'Sublime Text',
          'subl',
          svgAsset: 'assets/icons/editor/sublimetext.svg',
        ),
        LocalEditor(
          'IntelliJ IDEA',
          'idea',
          svgAsset: 'assets/icons/editor/intellij.svg',
        ),
        LocalEditor(
          'Xcode',
          'open',
          arguments: ['-a', 'Xcode'],
          svgAsset: 'assets/icons/editor/Xcode.svg',
        ),
        LocalEditor('Default macOS editor', 'open', icon: Icons.edit_rounded),
      ] else if (Platform.isWindows) ...const [
        LocalEditor(
          'Visual Studio Code',
          'code.cmd',
          svgAsset: 'assets/icons/editor/vscode.svg',
        ),
        LocalEditor('Cursor', 'cursor.cmd', icon: Icons.code_rounded),
        LocalEditor(
          'IntelliJ IDEA',
          'idea64.exe',
          svgAsset: 'assets/icons/editor/intellij.svg',
        ),
        LocalEditor(
          'Notepad++',
          'notepad++',
          svgAsset: 'assets/icons/editor/notepad_plus.svg',
        ),
        LocalEditor('Notepad', 'notepad.exe', icon: Icons.edit_rounded),
      ] else ...const [
        LocalEditor(
          'Visual Studio Code',
          'code',
          svgAsset: 'assets/icons/editor/vscode.svg',
        ),
        LocalEditor('Cursor', 'cursor', icon: Icons.code_rounded),
        LocalEditor('Zed', 'zed', svgAsset: 'assets/icons/editor/zed.svg'),
        LocalEditor(
          'Sublime Text',
          'subl',
          svgAsset: 'assets/icons/editor/sublimetext.svg',
        ),
        LocalEditor(
          'IntelliJ IDEA',
          'idea',
          svgAsset: 'assets/icons/editor/intellij.svg',
        ),
        LocalEditor('Gedit', 'gedit', icon: Icons.edit_rounded),
        LocalEditor('Kate', 'kate', icon: Icons.edit_rounded),
        LocalEditor('Nano', 'nano', icon: Icons.edit_rounded),
        LocalEditor('xdg-open', 'xdg-open', icon: Icons.open_in_new_rounded),
      ],
    ];

    final available = <LocalEditor>[];
    for (final editor in candidates) {
      if (await _commandExists(editor.command)) available.add(editor);
    }

    // Detect Flatpak-installed editors (Linux only).
    if (!Platform.isWindows && !Platform.isMacOS) {
      final flatpakEditors = await _detectFlatpakEditors();
      for (final editor in flatpakEditors) {
        // Don't add if already found via native command.
        final alreadyFound = available.any(
          (e) => e.name.toLowerCase().contains(
            editor.name.toLowerCase().split(' ').first,
          ),
        );
        if (!alreadyFound) available.add(editor);
      }
    }

    return available;
  }

  Future<List<LocalEditor>> _detectFlatpakEditors() async {
    const knownFlatpakEditors = [
      (
        appId: 'dev.zed.Zed',
        name: 'Zed (Flatpak)',
        svgAsset: 'assets/icons/editor/zed.svg',
      ),
      (
        appId: 'com.visualstudio.code',
        name: 'VS Code (Flatpak)',
        svgAsset: 'assets/icons/editor/vscode.svg',
      ),
      (
        appId: 'com.jetbrains.IntelliJ-IDEA-Ultimate',
        name: 'IntelliJ IDEA (Flatpak)',
        svgAsset: 'assets/icons/editor/intellij.svg',
      ),
      (
        appId: 'com.jetbrains.IntelliJ-IDEA-Community',
        name: 'IntelliJ CE (Flatpak)',
        svgAsset: 'assets/icons/editor/intellij.svg',
      ),
      (
        appId: 'com.sublimetext.three',
        name: 'Sublime Text (Flatpak)',
        svgAsset: 'assets/icons/editor/sublimetext.svg',
      ),
    ];

    final available = <LocalEditor>[];
    try {
      final result = await Process.run('flatpak', [
        'list',
        '--app',
        '--columns=application',
      ]);
      if (result.exitCode != 0) return available;
      final installed = (result.stdout as String)
          .split('\n')
          .map((line) => line.trim())
          .toSet();

      for (final entry in knownFlatpakEditors) {
        if (installed.contains(entry.appId)) {
          available.add(
            LocalEditor(
              entry.name,
              'flatpak',
              arguments: ['run', entry.appId],
              svgAsset: entry.svgAsset,
            ),
          );
        }
      }
    } catch (_) {
      // flatpak not installed or not available.
    }
    return available;
  }

  Future<String> prepareRemoteFileForLocalEdit(SftpFileEntry file) async {
    final tempRoot = Directory.systemTemp.createTempSync('portix-sftp-edit-');
    final localPath = '${tempRoot.path}${Platform.pathSeparator}${file.name}';
    final placeholder = File(localPath);
    await placeholder.writeAsString(
      '# Temp copy for remote file: ${file.name}\n'
      '# TODO: replace this placeholder with bytes from ConnectionManager.readRemoteFileBytes(...)\n',
    );
    return localPath;
  }

  Future<void> open(LocalEditor editor, String path) async {
    // On macOS, if command is not in PATH but app exists, use 'open -a'
    if (Platform.isMacOS && editor.command != 'open') {
      final result = await Process.run('which', [editor.command]);
      if (result.exitCode != 0) {
        const commandToApp = {
          'code': 'Visual Studio Code',
          'cursor': 'Cursor',
          'zed': 'Zed',
          'subl': 'Sublime Text',
          'idea': 'IntelliJ IDEA',
        };
        final appName = commandToApp[editor.command];
        if (appName != null) {
          await Process.start('open', ['-a', appName, path]);
          return;
        }
      }
    }
    // On Windows, if command is not in PATH, find the exe directly
    if (Platform.isWindows) {
      final result = await Process.run('where', [editor.command]);
      if (result.exitCode != 0) {
        final exePath = _findWindowsExe(editor.command);
        if (exePath != null) {
          await Process.start(exePath, [...editor.arguments, path]);
          return;
        }
      }
    }
    await Process.start(editor.command, [...editor.arguments, path]);
  }

  String? _findWindowsExe(String command) {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final programFilesX86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

    final paths = switch (command) {
      'code.cmd' || 'code' => [
        '$localAppData\\Programs\\Microsoft VS Code\\Code.exe',
        '$programFiles\\Microsoft VS Code\\Code.exe',
      ],
      'cursor.cmd' ||
      'cursor' => ['$localAppData\\Programs\\cursor\\Cursor.exe'],
      'idea64.exe' || 'idea' => [
        '$programFiles\\JetBrains\\IntelliJ IDEA Community Edition\\bin\\idea64.exe',
        '$programFiles\\JetBrains\\IntelliJ IDEA\\bin\\idea64.exe',
      ],
      'notepad++' => [
        '$programFiles\\Notepad++\\notepad++.exe',
        '$programFilesX86\\Notepad++\\notepad++.exe',
      ],
      _ => <String>[],
    };

    for (final p in paths) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  Future<bool> _commandExists(String command) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('where', [command]);
        if (result.exitCode == 0) return true;
        return _windowsAppExists(command);
      }
      if (command == 'open') return Platform.isMacOS;
      final result = await Process.run('which', [command]);
      if (result.exitCode == 0) return true;
      // On macOS, check if the app exists in /Applications even without
      // the CLI command installed in PATH.
      if (Platform.isMacOS) {
        return _macAppExists(command);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool _macAppExists(String command) {
    const commandToApp = {
      'code': 'Visual Studio Code.app',
      'cursor': 'Cursor.app',
      'zed': 'Zed.app',
      'subl': 'Sublime Text.app',
      'idea': 'IntelliJ IDEA.app',
    };
    final appName = commandToApp[command];
    if (appName == null) return false;
    return Directory('/Applications/$appName').existsSync() ||
        Directory(
          '${Platform.environment['HOME']}/Applications/$appName',
        ).existsSync();
  }

  bool _windowsAppExists(String command) {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final programFilesX86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

    final paths = switch (command) {
      'code.cmd' || 'code' => [
        '$localAppData\\Programs\\Microsoft VS Code\\bin\\code.cmd',
        '$localAppData\\Programs\\Microsoft VS Code\\Code.exe',
        '$programFiles\\Microsoft VS Code\\bin\\code.cmd',
        '$programFiles\\Microsoft VS Code\\Code.exe',
      ],
      'cursor.cmd' || 'cursor' => [
        '$localAppData\\Programs\\cursor\\Cursor.exe',
        '$localAppData\\cursor\\Cursor.exe',
      ],
      'idea64.exe' || 'idea' => [
        '$programFiles\\JetBrains\\IntelliJ IDEA Community Edition\\bin\\idea64.exe',
        '$programFiles\\JetBrains\\IntelliJ IDEA\\bin\\idea64.exe',
      ],
      'notepad++' => [
        '$programFiles\\Notepad++\\notepad++.exe',
        '$programFilesX86\\Notepad++\\notepad++.exe',
      ],
      _ => <String>[],
    };

    for (final path in paths) {
      if (File(path).existsSync()) return true;
    }
    return false;
  }
}
