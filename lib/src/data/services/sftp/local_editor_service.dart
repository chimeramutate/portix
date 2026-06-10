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
        LocalEditor(
          'Default Windows app',
          'cmd.exe',
          arguments: ['/c', 'start', '""'],
          icon: Icons.open_in_new_rounded,
        ),
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
        LocalEditor('KWrite', 'kwrite', icon: Icons.edit_rounded),
        LocalEditor('Mousepad', 'mousepad', icon: Icons.edit_rounded),
        LocalEditor('Nano (terminal)', 'nano', icon: Icons.edit_rounded),
        LocalEditor(
          'System default',
          'xdg-open',
          icon: Icons.open_in_new_rounded,
        ),
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
        final alreadyFound = available.any(
          (e) => e.name.toLowerCase().contains(
            editor.name.toLowerCase().split(' ').first,
          ),
        );
        if (!alreadyFound) available.add(editor);
      }

      // Detect snap-installed editors.
      final snapEditors = await _detectSnapEditors();
      for (final editor in snapEditors) {
        final alreadyFound = available.any(
          (e) => e.name.toLowerCase().contains(
            editor.name.toLowerCase().split(' ').first,
          ),
        );
        if (!alreadyFound) available.add(editor);
      }

      // On Linux, if no editors were found at all, always offer xdg-open.
      if (available.isEmpty) {
        available.add(
          const LocalEditor(
            'System default',
            'xdg-open',
            icon: Icons.open_in_new_rounded,
          ),
        );
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

  Future<List<LocalEditor>> _detectSnapEditors() async {
    const knownSnapEditors = [
      (
        snapName: 'code',
        name: 'VS Code (Snap)',
        command: 'code',
        svgAsset: 'assets/icons/editor/vscode.svg',
      ),
      (
        snapName: 'cursor',
        name: 'Cursor (Snap)',
        command: 'cursor',
        svgAsset: null,
      ),
      (
        snapName: 'sublime-text',
        name: 'Sublime Text (Snap)',
        command: 'subl',
        svgAsset: 'assets/icons/editor/sublimetext.svg',
      ),
      (
        snapName: 'intellij-idea-community',
        name: 'IntelliJ CE (Snap)',
        command: 'intellij-idea-community',
        svgAsset: 'assets/icons/editor/intellij.svg',
      ),
    ];

    final available = <LocalEditor>[];
    try {
      final result = await Process.run('snap', ['list']);
      if (result.exitCode != 0) return available;
      final installed = (result.stdout as String)
          .split('\n')
          .map((line) => line.split(RegExp(r'\s+')).first.trim())
          .toSet();

      for (final entry in knownSnapEditors) {
        if (installed.contains(entry.snapName)) {
          // Snap commands are in /snap/bin/ which should be in PATH.
          final snapBin = '/snap/bin/${entry.command}';
          final command = File(snapBin).existsSync() ? snapBin : entry.command;
          available.add(
            LocalEditor(
              entry.name,
              command,
              svgAsset: entry.svgAsset,
              icon: entry.svgAsset == null ? Icons.code_rounded : null,
            ),
          );
        }
      }
    } catch (_) {
      // snap not available.
    }
    return available;
  }

  /// Open a file with the OS default application based on file extension.
  /// This bypasses the editor selection entirely and uses the platform's
  /// native file association mechanism.
  Future<void> openWithSystemDefault(String path) async {
    if (Platform.isWindows) {
      final escaped = path.replaceAll('/', '\\');
      // Use rundll32 which is the most reliable way to open a file with its
      // associated application on Windows without quoting issues.
      final result = await Process.run('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        escaped,
      ]);
      if (result.exitCode == 0) return;
      // Fallback: PowerShell Invoke-Item.
      await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Invoke-Item -LiteralPath \'$escaped\'',
      ]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [path]);
      return;
    }
    // Linux: try multiple mechanisms.
    // 1. gio open — works in snap via xdg-desktop-portal.
    final gioResult = await Process.run('gio', ['open', path]);
    if (gioResult.exitCode == 0) return;
    // 2. xdg-open — works in native builds.
    final xdgResult = await Process.run('xdg-open', [path]);
    if (xdgResult.exitCode == 0) return;
    // 3. Direct D-Bus portal call as final fallback.
    final uri = Uri.file(path).toString();
    await Process.run('dbus-send', [
      '--session',
      '--dest=org.freedesktop.portal.Desktop',
      '--type=method_call',
      '/org/freedesktop/portal/desktop',
      'org.freedesktop.portal.OpenURI.OpenURI',
      'string:',
      'string:$uri',
      'dict:string:variant:',
    ]);
  }

  /// Detect applications suitable for a specific file extension.
  /// Returns apps relevant to the file type (e.g. Word/WPS for .docx).
  Future<List<LocalEditor>> detectAppsForExtension(String extension) async {
    final ext = extension.toLowerCase();
    final candidates = <LocalEditor>[];

    if (Platform.isWindows) {
      candidates.addAll(_windowsAppsForExtension(ext));
    } else if (Platform.isMacOS) {
      candidates.addAll(_macAppsForExtension(ext));
    } else {
      candidates.addAll(_linuxAppsForExtension(ext));
    }

    // Always add system default as last option.
    candidates.add(
      LocalEditor(
        Platform.isWindows
            ? 'Default Windows app'
            : Platform.isMacOS
            ? 'Default macOS app'
            : 'Default app',
        '_system_default_',
        icon: Icons.open_in_new_rounded,
      ),
    );

    final available = <LocalEditor>[];
    for (final app in candidates) {
      if (app.command == '_system_default_') {
        available.add(app);
      } else if (await _commandExists(app.command)) {
        available.add(app);
      } else if (Platform.isWindows && _windowsAppExistsPath(app.command)) {
        available.add(app);
      }
    }
    return available;
  }

  List<LocalEditor> _windowsAppsForExtension(String ext) {
    return switch (ext) {
      'doc' || 'docx' || 'rtf' => const [
        LocalEditor(
          'Microsoft Word',
          r'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE',
          svgAsset: null,
          icon: Icons.description_rounded,
        ),
        LocalEditor(
          'WPS Writer',
          r'C:\Users\Public\Desktop\WPS Office', // checked via exists
          icon: Icons.description_rounded,
        ),
        LocalEditor(
          'LibreOffice Writer',
          'soffice',
          arguments: ['--writer'],
          icon: Icons.description_rounded,
        ),
      ],
      'xls' || 'xlsx' || 'csv' => const [
        LocalEditor(
          'Microsoft Excel',
          r'C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE',
          icon: Icons.table_chart_rounded,
        ),
        LocalEditor(
          'WPS Spreadsheets',
          r'C:\Users\Public\Desktop\WPS Office',
          icon: Icons.table_chart_rounded,
        ),
        LocalEditor(
          'LibreOffice Calc',
          'soffice',
          arguments: ['--calc'],
          icon: Icons.table_chart_rounded,
        ),
      ],
      'ppt' || 'pptx' => const [
        LocalEditor(
          'Microsoft PowerPoint',
          r'C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE',
          icon: Icons.slideshow_rounded,
        ),
        LocalEditor(
          'WPS Presentation',
          r'C:\Users\Public\Desktop\WPS Office',
          icon: Icons.slideshow_rounded,
        ),
        LocalEditor(
          'LibreOffice Impress',
          'soffice',
          arguments: ['--impress'],
          icon: Icons.slideshow_rounded,
        ),
      ],
      'pdf' => const [
        LocalEditor(
          'Adobe Acrobat',
          r'C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe',
          icon: Icons.picture_as_pdf_rounded,
        ),
        LocalEditor(
          'Foxit Reader',
          r'C:\Program Files (x86)\Foxit Software\Foxit PDF Reader\FoxitPDFReader.exe',
          icon: Icons.picture_as_pdf_rounded,
        ),
        LocalEditor(
          'SumatraPDF',
          'SumatraPDF',
          icon: Icons.picture_as_pdf_rounded,
        ),
      ],
      'png' || 'jpg' || 'jpeg' || 'gif' || 'bmp' || 'webp' || 'svg' => const [
        LocalEditor(
          'Photos',
          r'C:\Windows\explorer.exe',
          arguments: [
            'shell:AppsFolder\\Microsoft.Windows.Photos_8wekyb3d8bbwe!App',
          ],
          icon: Icons.image_rounded,
        ),
        LocalEditor(
          'IrfanView',
          r'C:\Program Files\IrfanView\i_view64.exe',
          icon: Icons.image_rounded,
        ),
      ],
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' => const [
        LocalEditor(
          'VLC',
          r'C:\Program Files\VideoLAN\VLC\vlc.exe',
          icon: Icons.play_circle_rounded,
        ),
        LocalEditor(
          'Windows Media Player',
          r'C:\Program Files (x86)\Windows Media Player\wmplayer.exe',
          icon: Icons.play_circle_rounded,
        ),
      ],
      'mp3' || 'wav' || 'flac' || 'ogg' || 'aac' => const [
        LocalEditor(
          'VLC',
          r'C:\Program Files\VideoLAN\VLC\vlc.exe',
          icon: Icons.music_note_rounded,
        ),
        LocalEditor(
          'Windows Media Player',
          r'C:\Program Files (x86)\Windows Media Player\wmplayer.exe',
          icon: Icons.music_note_rounded,
        ),
      ],
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => const [
        LocalEditor(
          '7-Zip',
          r'C:\Program Files\7-Zip\7zFM.exe',
          icon: Icons.folder_zip_rounded,
        ),
        LocalEditor(
          'WinRAR',
          r'C:\Program Files\WinRAR\WinRAR.exe',
          icon: Icons.folder_zip_rounded,
        ),
      ],
      _ => const [],
    };
  }

  List<LocalEditor> _macAppsForExtension(String ext) {
    return switch (ext) {
      'doc' || 'docx' || 'rtf' => const [
        LocalEditor(
          'Microsoft Word',
          'open',
          arguments: ['-a', 'Microsoft Word'],
          icon: Icons.description_rounded,
        ),
        LocalEditor(
          'Pages',
          'open',
          arguments: ['-a', 'Pages'],
          icon: Icons.description_rounded,
        ),
        LocalEditor(
          'LibreOffice Writer',
          'open',
          arguments: ['-a', 'LibreOffice'],
          icon: Icons.description_rounded,
        ),
      ],
      'xls' || 'xlsx' || 'csv' => const [
        LocalEditor(
          'Microsoft Excel',
          'open',
          arguments: ['-a', 'Microsoft Excel'],
          icon: Icons.table_chart_rounded,
        ),
        LocalEditor(
          'Numbers',
          'open',
          arguments: ['-a', 'Numbers'],
          icon: Icons.table_chart_rounded,
        ),
      ],
      'ppt' || 'pptx' => const [
        LocalEditor(
          'Microsoft PowerPoint',
          'open',
          arguments: ['-a', 'Microsoft PowerPoint'],
          icon: Icons.slideshow_rounded,
        ),
        LocalEditor(
          'Keynote',
          'open',
          arguments: ['-a', 'Keynote'],
          icon: Icons.slideshow_rounded,
        ),
      ],
      'pdf' => const [
        LocalEditor(
          'Preview',
          'open',
          arguments: ['-a', 'Preview'],
          icon: Icons.picture_as_pdf_rounded,
        ),
        LocalEditor(
          'Adobe Acrobat',
          'open',
          arguments: ['-a', 'Adobe Acrobat Reader'],
          icon: Icons.picture_as_pdf_rounded,
        ),
      ],
      'png' || 'jpg' || 'jpeg' || 'gif' || 'bmp' || 'webp' || 'svg' => const [
        LocalEditor(
          'Preview',
          'open',
          arguments: ['-a', 'Preview'],
          icon: Icons.image_rounded,
        ),
      ],
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' => const [
        LocalEditor(
          'QuickTime',
          'open',
          arguments: ['-a', 'QuickTime Player'],
          icon: Icons.play_circle_rounded,
        ),
        LocalEditor(
          'VLC',
          'open',
          arguments: ['-a', 'VLC'],
          icon: Icons.play_circle_rounded,
        ),
      ],
      _ => const [],
    };
  }

  List<LocalEditor> _linuxAppsForExtension(String ext) {
    return switch (ext) {
      'doc' || 'docx' || 'rtf' => const [
        LocalEditor(
          'LibreOffice Writer',
          'libreoffice',
          arguments: ['--writer'],
          icon: Icons.description_rounded,
        ),
      ],
      'xls' || 'xlsx' || 'csv' => const [
        LocalEditor(
          'LibreOffice Calc',
          'libreoffice',
          arguments: ['--calc'],
          icon: Icons.table_chart_rounded,
        ),
      ],
      'ppt' || 'pptx' => const [
        LocalEditor(
          'LibreOffice Impress',
          'libreoffice',
          arguments: ['--impress'],
          icon: Icons.slideshow_rounded,
        ),
      ],
      'pdf' => const [
        LocalEditor('Evince', 'evince', icon: Icons.picture_as_pdf_rounded),
        LocalEditor('Okular', 'okular', icon: Icons.picture_as_pdf_rounded),
      ],
      'png' || 'jpg' || 'jpeg' || 'gif' || 'bmp' || 'webp' || 'svg' => const [
        LocalEditor('Eye of GNOME', 'eog', icon: Icons.image_rounded),
        LocalEditor('Gwenview', 'gwenview', icon: Icons.image_rounded),
        LocalEditor('Shotwell', 'shotwell', icon: Icons.image_rounded),
      ],
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' => const [
        LocalEditor('VLC', 'vlc', icon: Icons.play_circle_rounded),
        LocalEditor('MPV', 'mpv', icon: Icons.play_circle_rounded),
      ],
      'mp3' || 'wav' || 'flac' || 'ogg' || 'aac' => const [
        LocalEditor('VLC', 'vlc', icon: Icons.music_note_rounded),
        LocalEditor('Rhythmbox', 'rhythmbox', icon: Icons.music_note_rounded),
      ],
      'xml' || 'json' || 'yaml' || 'yml' || 'toml' || 'ini' || 'conf' => const [
        LocalEditor(
          'Visual Studio Code',
          'code',
          svgAsset: 'assets/icons/editor/vscode.svg',
        ),
        LocalEditor('Kate', 'kate', icon: Icons.code_rounded),
        LocalEditor('Gedit', 'gedit', icon: Icons.edit_rounded),
        LocalEditor('Mousepad', 'mousepad', icon: Icons.edit_rounded),
      ],
      _ => const [],
    };
  }

  bool _windowsAppExistsPath(String path) {
    if (path.isEmpty) return false;
    return File(path).existsSync();
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
    // Handle system default pseudo-command.
    if (editor.command == '_system_default_') {
      await openWithSystemDefault(path);
      return;
    }
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
      // .cmd and .bat files require runInShell to execute properly
      final needsShell =
          editor.command.endsWith('.cmd') || editor.command.endsWith('.bat');

      // Special handling for "Default Windows app" (cmd.exe /c start "")
      // Detect whether PowerShell or cmd is available and use the appropriate
      // mechanism to open a file with the system default handler.
      if (editor.command == 'cmd.exe' && editor.arguments.contains('start')) {
        final escaped = path.replaceAll('/', '\\');

        // Try pwsh (PowerShell Core) first.
        if (await _commandExists('pwsh')) {
          await Process.run('pwsh', [
            '-NoProfile',
            '-Command',
            'Start-Process',
            '-FilePath',
            escaped,
          ]);
          return;
        }

        // Try Windows PowerShell (powershell.exe).
        if (await _commandExists('powershell')) {
          await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            'Start-Process',
            '-FilePath',
            escaped,
          ]);
          return;
        }

        // Fallback: cmd.exe with properly constructed command.
        // Using rundll32 avoids the quoting issues of `start`.
        await Process.run('rundll32.exe', [
          'url.dll,FileProtocolHandler',
          escaped,
        ]);
        return;
      }

      final result = await Process.run('where', [editor.command]);
      if (result.exitCode != 0) {
        final exePath = _findWindowsExe(editor.command);
        if (exePath != null) {
          await Process.start(exePath, [
            ...editor.arguments,
            path,
          ], runInShell: needsShell);
          return;
        }
      }
      await Process.start(editor.command, [
        ...editor.arguments,
        path,
      ], runInShell: needsShell);
      return;
    }

    // macOS/Linux: for `open` (macOS) or `xdg-open` (Linux), run directly.
    // For other commands (bash, zsh, fish, etc.), ensure the shell is valid.
    if (editor.command == 'xdg-open' || editor.command == 'open') {
      await Process.start(editor.command, [...editor.arguments, path]);
      return;
    }

    // For shell-based editors, try the command via the detected user shell
    // (bash, zsh, fish) to ensure PATH and environment are inherited.
    final userShell = Platform.environment['SHELL']?.trim();
    if (userShell != null &&
        userShell.isNotEmpty &&
        editor.command != userShell) {
      // Validate that the editor command exists by checking via the user shell.
      final check = await Process.run(userShell, [
        '-c',
        'command -v ${editor.command}',
      ]);
      if (check.exitCode != 0) {
        // Command not found in any shell — try common shells as fallback.
        const fallbackShells = ['/bin/zsh', '/bin/bash', '/usr/bin/fish'];
        for (final shell in fallbackShells) {
          if (!File(shell).existsSync()) continue;
          final fallbackCheck = await Process.run(shell, [
            '-c',
            'command -v ${editor.command}',
          ]);
          if (fallbackCheck.exitCode == 0) {
            await Process.start(shell, [
              '-c',
              '${editor.command} ${[...editor.arguments, path].map(_posixQuote).join(' ')}',
            ]);
            return;
          }
        }
      }
    }
    await Process.start(editor.command, [...editor.arguments, path]);
  }

  /// Quote a value safely for POSIX shells.
  static String _posixQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
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
        // cmd.exe is always available on Windows (used for 'Default Windows app')
        if (command == 'cmd.exe') return true;
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
