import 'dart:io';

import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/domain/repositories/rdp/index.dart';

/// Handles launching an RDP session using IronRDP (ironrdp-client CLI)
/// or falling back to the OS-native RDP client.
///
/// IronRDP CLI: https://github.com/Devolutions/IronRDP
/// Expected binary name: `ironrdp-client` (must be on PATH or configured path)
class RdpLaunchService {
  const RdpLaunchService({
    RdpProfileRepository? repository,
    String? ironRdpBinaryPath,
  }) : _repository = repository,
       _ironRdpBinaryPath = ironRdpBinaryPath ?? 'ironrdp-client';

  final RdpProfileRepository? _repository;
  final String _ironRdpBinaryPath;

  /// Launch an RDP session for the given profile.
  ///
  /// Strategy:
  /// 1. Try IronRDP CLI if available on PATH.
  /// 2. Fall back to system RDP client (mstsc on Windows, xfreerdp on Linux,
  ///    Microsoft Remote Desktop on macOS via open command).
  ///
  /// For CyberArk PSM profiles, the original .rdp file is preferred so the
  /// PSM gateway routing and alternate shell settings are preserved.
  Future<Either<Failure, RdpLaunchResult>> launch(RdpProfile profile) async {
    // If source .rdp file exists, prefer launching it directly
    if (profile.sourceRdpFilePath != null) {
      final file = File(profile.sourceRdpFilePath!);
      if (await file.exists()) {
        return _launchFromFile(profile, profile.sourceRdpFilePath!);
      }
    }

    // Export a temporary .rdp file and launch it
    if (_repository != null) {
      final exportResult = await _repository.exportToRdpFile(profile);
      if (exportResult.isRight) {
        final path = (exportResult as Right<Failure, String>).value;
        return _launchFromFile(profile, path);
      }
    }

    // Try direct IronRDP launch via CLI
    return _launchIronRdp(profile);
  }

  Future<Either<Failure, RdpLaunchResult>> _launchFromFile(
    RdpProfile profile,
    String rdpFilePath,
  ) async {
    // First try IronRDP with file
    final ironRdpAvailable = await _isIronRdpAvailable();
    if (ironRdpAvailable) {
      return _launchIronRdpWithFile(profile, rdpFilePath);
    }
    // Fall back to native OS handler for .rdp files
    return _openRdpFileWithSystem(rdpFilePath);
  }

  Future<Either<Failure, RdpLaunchResult>> _launchIronRdp(
    RdpProfile profile,
  ) async {
    final available = await _isIronRdpAvailable();
    if (!available) {
      return _launchNativeClient(profile);
    }

    try {
      final args = _buildIronRdpArgs(profile);
      final process = await Process.start(
        _ironRdpBinaryPath,
        args,
        mode: ProcessStartMode.detached,
      );
      return Right(
        RdpLaunchResult(
          method: RdpLaunchMethod.ironRdp,
          pid: process.pid,
          host: profile.host,
          port: profile.port,
        ),
      );
    } catch (error) {
      // IronRDP failed — try native as last resort
      return _launchNativeClient(profile);
    }
  }

  Future<Either<Failure, RdpLaunchResult>> _launchIronRdpWithFile(
    RdpProfile profile,
    String rdpFilePath,
  ) async {
    try {
      // ironrdp-client can accept an .rdp file as argument (planned CLI feature)
      // For now, parse the file and pass params; IronRDP GUI mode opens with file.
      final process = await Process.start(_ironRdpBinaryPath, [
        rdpFilePath,
      ], mode: ProcessStartMode.detached);
      return Right(
        RdpLaunchResult(
          method: RdpLaunchMethod.ironRdp,
          pid: process.pid,
          host: profile.host,
          port: profile.port,
        ),
      );
    } catch (_) {
      return _openRdpFileWithSystem(rdpFilePath);
    }
  }

  Future<Either<Failure, RdpLaunchResult>> _openRdpFileWithSystem(
    String rdpFilePath,
  ) async {
    try {
      ProcessResult result;
      if (Platform.isMacOS) {
        // Opens with Microsoft Remote Desktop or the system default RDP handler
        result = await Process.run('open', [rdpFilePath]);
      } else if (Platform.isWindows) {
        result = await Process.run('mstsc', [rdpFilePath]);
      } else {
        // Linux
        result = await Process.run('xdg-open', [rdpFilePath]);
      }

      if (result.exitCode != 0) {
        return Left(
          Failure('Failed to open RDP file: ${result.stderr}'.trim()),
        );
      }

      return Right(
        RdpLaunchResult(
          method: Platform.isWindows
              ? RdpLaunchMethod.mstsc
              : RdpLaunchMethod.systemDefault,
          pid: -1,
          host: rdpFilePath,
          port: 3389,
        ),
      );
    } catch (error) {
      return Left(Failure('Cannot open RDP file: $error'));
    }
  }

  Future<Either<Failure, RdpLaunchResult>> _launchNativeClient(
    RdpProfile profile,
  ) async {
    try {
      if (Platform.isWindows) {
        return _launchMstsc(profile);
      } else if (Platform.isMacOS) {
        return _launchMacRdp(profile);
      } else {
        return _launchXfreeRdp(profile);
      }
    } catch (error) {
      return Left(Failure('Failed to launch native RDP client: $error'));
    }
  }

  Future<Either<Failure, RdpLaunchResult>> _launchMstsc(
    RdpProfile profile,
  ) async {
    final args = [
      '/v:${profile.host}:${profile.port}',
      '/w:${profile.desktopWidth}',
      '/h:${profile.desktopHeight}',
      if (profile.fullScreen) '/f',
    ];
    final process = await Process.start(
      'mstsc',
      args,
      mode: ProcessStartMode.detached,
    );
    return Right(
      RdpLaunchResult(
        method: RdpLaunchMethod.mstsc,
        pid: process.pid,
        host: profile.host,
        port: profile.port,
      ),
    );
  }

  Future<Either<Failure, RdpLaunchResult>> _launchMacRdp(
    RdpProfile profile,
  ) async {
    // Try opening Microsoft Remote Desktop app if installed
    try {
      await Process.start('open', [
        '-a',
        'Microsoft Remote Desktop',
        '--args',
        '${profile.host}:${profile.port}',
      ], mode: ProcessStartMode.detached);
      return Right(
        RdpLaunchResult(
          method: RdpLaunchMethod.systemDefault,
          pid: -1,
          host: profile.host,
          port: profile.port,
        ),
      );
    } catch (_) {
      return Left(
        const Failure(
          'No RDP client found. Install Microsoft Remote Desktop from the App Store, '
          'or install IronRDP (ironrdp-client) on your PATH.',
        ),
      );
    }
  }

  Future<Either<Failure, RdpLaunchResult>> _launchXfreeRdp(
    RdpProfile profile,
  ) async {
    final userArg = profile.domain != null && profile.domain!.isNotEmpty
        ? '${profile.domain}\\${profile.username}'
        : profile.username;

    final args = [
      '/v:${profile.host}:${profile.port}',
      '/u:$userArg',
      '/w:${profile.desktopWidth}',
      '/h:${profile.desktopHeight}',
      if (profile.fullScreen) '/f',
      if (profile.redirectDrives)
        '/drive:${profile.effectiveLocalShareName},${_expandLocalSharePath(profile.effectiveLocalSharePath)}',
      if (profile.redirectClipboard) '+clipboard',
      if (!profile.enableCredSsp) '-sec-nla',
      '/from-stdin',
    ];

    final process = await Process.start(
      'xfreerdp',
      args,
      mode: ProcessStartMode.detached,
    );
    return Right(
      RdpLaunchResult(
        method: RdpLaunchMethod.xfreerdp,
        pid: process.pid,
        host: profile.host,
        port: profile.port,
      ),
    );
  }

  String _expandLocalSharePath(String path) {
    final trimmed = path.trim();
    if (!trimmed.startsWith('~')) return trimmed;

    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;

    if (trimmed == '~') return home;
    if (trimmed.startsWith('~/') || trimmed.startsWith(r'~\')) {
      return '$home${Platform.pathSeparator}${trimmed.substring(2)}';
    }

    return trimmed;
  }

  List<String> _buildIronRdpArgs(RdpProfile profile) {
    final args = <String>['--host', profile.host, '--port', '${profile.port}'];

    if (profile.username.isNotEmpty) {
      args.addAll(['--user', profile.username]);
    }
    if (profile.domain != null && profile.domain!.isNotEmpty) {
      args.addAll(['--domain', profile.domain!]);
    }
    if (profile.password != null && profile.password!.isNotEmpty) {
      args.addAll(['--password', profile.password!]);
    }
    if (profile.desktopWidth > 0) {
      args.addAll(['--width', '${profile.desktopWidth}']);
    }
    if (profile.desktopHeight > 0) {
      args.addAll(['--height', '${profile.desktopHeight}']);
    }
    if (!profile.enableCredSsp) {
      args.add('--no-nla');
    }

    return args;
  }

  Future<bool> _isIronRdpAvailable() async {
    try {
      final result = await Process.run(_ironRdpBinaryPath, [
        '--version',
      ]).timeout(const Duration(seconds: 3));
      return result.exitCode == 0 || result.exitCode == 1;
    } catch (_) {
      return false;
    }
  }
}

/// Describes how an RDP session was launched.
enum RdpLaunchMethod { ironRdp, mstsc, xfreerdp, systemDefault }

/// Result from a successful RDP launch.
class RdpLaunchResult {
  const RdpLaunchResult({
    required this.method,
    required this.pid,
    required this.host,
    required this.port,
  });

  final RdpLaunchMethod method;
  final int pid;
  final String host;
  final int port;

  String get methodLabel => switch (method) {
    RdpLaunchMethod.ironRdp => 'IronRDP',
    RdpLaunchMethod.mstsc => 'mstsc (Windows)',
    RdpLaunchMethod.xfreerdp => 'xfreerdp (Linux)',
    RdpLaunchMethod.systemDefault => 'System default',
  };
}
