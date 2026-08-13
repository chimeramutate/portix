import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/domain/repositories/rdp/index.dart';

class RdpLaunchService {
  const RdpLaunchService({
    RdpProfileRepository? repository,
    String? ironRdpBinaryPath,
  }) : _repository = repository,
       _ironRdpBinaryPath = ironRdpBinaryPath ?? 'ironrdp-client';

  final RdpProfileRepository? _repository;
  final String _ironRdpBinaryPath;

  Future<Either<Failure, RdpLaunchResult>> launch(RdpProfile profile) async {
    if (profile.sourceRdpFilePath != null) {
      final file = File(profile.sourceRdpFilePath!);
      if (await file.exists()) {
        return _launchFromFile(profile, profile.sourceRdpFilePath!);
      }
    }

    if (_repository != null) {
      final exportResult = await _repository.exportToRdpFile(profile);
      if (exportResult.isRight) {
        final path = (exportResult as Right<Failure, String>).value;
        return _launchFromFile(profile, path);
      }
    }

    return _launchIronRdp(profile);
  }

  Future<Either<Failure, RdpLaunchResult>> _launchFromFile(
    RdpProfile profile,
    String rdpFilePath,
  ) async {
    final ironRdpAvailable = await _isIronRdpAvailable();
    if (ironRdpAvailable) {
      return _launchIronRdpWithFile(profile, rdpFilePath);
    }

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
      return _launchNativeClient(profile);
    }
  }

  Future<Either<Failure, RdpLaunchResult>> _launchIronRdpWithFile(
    RdpProfile profile,
    String rdpFilePath,
  ) async {
    try {
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
        result = await Process.run('open', [rdpFilePath]);
      } else if (Platform.isWindows) {
        result = await Process.run('mstsc', [rdpFilePath]);
      } else {
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
      if (profile.redirectDrives)
        '/drive:${profile.effectiveLocalShareName},${_expandLocalSharePath(profile.effectiveLocalSharePath)}',
      if (profile.redirectClipboard) '/clipboard',
      if (!profile.enableCredSsp) '/sec-tls',
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
    final xfreerdpAvailable = await _isXfreeRdpAvailable();
    if (xfreerdpAvailable) {
      return _launchXfreeRdp(profile);
    }

    try {
      final process = await Process.start('open', [
        '-a',
        'Microsoft Remote Desktop',
        '--args',
        '${profile.host}:${profile.port}',
      ], mode: ProcessStartMode.detached);
      if (profile.redirectDrives) {
        debugPrint(
          '[RDP] WARNING: Microsoft Remote Desktop tidak mendukung '
          'drive sharing via CLI. Install xfreerdp untuk fitur ini.',
        );
      }
      return Right(
        RdpLaunchResult(
          method: RdpLaunchMethod.systemDefault,
          pid: process.pid,
          host: profile.host,
          port: profile.port,
        ),
      );
    } catch (_) {
      return Left(
        const Failure(
          'Tidak ada RDP client yang mendukung drive sharing di macOS.\n'
          'Install xfreerdp via Homebrew: brew install freerdp\n'
          'atau install Microsoft Remote Desktop dari App Store.',
        ),
      );
    }
  }

  Future<bool> _isXfreeRdpAvailable() async {
    try {
      final result = await Process.run('which', [
        'xfreerdp',
      ]).timeout(const Duration(seconds: 3));
      if (result.exitCode == 0) return true;

      final result3 = await Process.run('which', [
        'xfreerdp3',
      ]).timeout(const Duration(seconds: 3));
      return result3.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<Either<Failure, RdpLaunchResult>> _launchXfreeRdp(
    RdpProfile profile,
  ) async {
    final binary = await _resolveXfreeRdpBinary();

    final userArg = profile.domain != null && profile.domain!.isNotEmpty
        ? '${profile.domain}\\${profile.username}'
        : profile.username;

    final localPath = _expandLocalSharePath(profile.effectiveLocalSharePath);

    if (profile.redirectDrives) {
      try {
        await Directory(localPath).create(recursive: true);
      } catch (_) {}
    }

    final args = [
      '/v:${profile.host}:${profile.port}',
      '/u:$userArg',
      if (profile.password != null && profile.password!.isNotEmpty)
        '/p:${profile.password}',
      '/w:${profile.desktopWidth}',
      '/h:${profile.desktopHeight}',
      if (profile.fullScreen) '/f',
      if (profile.redirectDrives)
        '/drive:${profile.effectiveLocalShareName},$localPath',
      if (profile.redirectClipboard) '+clipboard',
      if (!profile.enableCredSsp) '-sec-nla',
      '/cert:ignore',
    ];

    try {
      final process = await Process.start(
        binary,
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
    } catch (e) {
      return Left(Failure('Gagal menjalankan $binary: $e'));
    }
  }

  Future<String> _resolveXfreeRdpBinary() async {
    for (final bin in ['xfreerdp3', 'xfreerdp']) {
      try {
        final result = await Process.run('which', [
          bin,
        ]).timeout(const Duration(seconds: 3));
        if (result.exitCode == 0) {
          return bin;
        }
      } catch (_) {
        continue;
      }
    }
    return 'xfreerdp';
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

enum RdpLaunchMethod { ironRdp, mstsc, xfreerdp, systemDefault }

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
