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
        LocalEditor(
          'Cursor',
          'cursor',
          svgAsset: 'assets/icons/editor/cursor.svg',
        ),
        LocalEditor('Zed', 'zed', svgAsset: 'assets/icons/editor/zed.svg'),
        LocalEditor(
          'Sublime Text',
          'subl',
          svgAsset: 'assets/icons/editor/sublimetext.svg',
        ),
        LocalEditor(
          'Xcode',
          'open',
          arguments: ['-a', 'Xcode'],
          svgAsset: 'assets/icons/editor/xcode.svg',
        ),
        LocalEditor('Default macOS editor', 'open', icon: Icons.edit_rounded),
      ] else if (Platform.isWindows) ...const [
        LocalEditor(
          'Visual Studio Code',
          'code.cmd',
          svgAsset: 'assets/icons/editor/vscode.svg',
        ),
        LocalEditor('Cursor', 'cursor.cmd', icon: Icons.code_rounded),
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
        LocalEditor('Gedit', 'gedit', icon: Icons.edit_rounded),
        LocalEditor('Kate', 'kate', icon: Icons.edit_rounded),
        LocalEditor('Nano', 'nano', icon: Icons.edit_rounded),
      ],
    ];

    final available = <LocalEditor>[];
    for (final editor in candidates) {
      if (await _commandExists(editor.command)) available.add(editor);
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

  Future<void> open(LocalEditor editor, String path) {
    return Process.start(editor.command, [...editor.arguments, path]);
  }

  Future<bool> _commandExists(String command) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('where', [command]);
        return result.exitCode == 0;
      }
      if (command == 'open') return Platform.isMacOS;
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
