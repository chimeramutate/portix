import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/profile_secret_store.dart';
import 'package:portix/src/data/services/sftp/local_editor_service.dart';
import 'package:portix/src/data/services/sftp/local_file_browser.dart';
import 'package:portix/src/domain/entities/sftp/sftp_file_entry.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart' as domain;
import 'package:portix/src/features/sftp/controller/sftp_workspace_controller.dart';
import 'package:portix/src/sftp_client/sftp_manager.dart';
import 'package:portix/src/sftp_client/sftp_models.dart';

import 'support/fake_sftp_backend.dart';

SftpManager _manager(FakeSftpBackend backend, {ProfileSecretStore? store}) =>
    SftpManager(
      backend: backend,
      credentials: ProfileCredentials(
        secretStore: store ?? _MemorySecretStore(),
      ),
      livenessInterval: const Duration(milliseconds: 5),
    );

/// Lets the manager's liveness check notice a dropped connection.
Future<void> _waitForLivenessCheck() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  group('SftpWorkspaceController remote open regression', () {
    late FakeSftpBackend backend;
    late SftpManager sftpManager;
    late SftpWorkspaceController controller;

    setUp(() {
      backend = FakeSftpBackend();
      sftpManager = _manager(backend);
      controller = SftpWorkspaceController(
        sftpManager: sftpManager,
        localFileBrowser: _FakeLocalFileBrowser(),
        localEditorService: _FakeLocalEditorService(),
      );
    });

    tearDown(() {
      controller.dispose();
      sftpManager.dispose();
    });

    test(
      'downloads latest bytes into a unique temp file for a remote open',
      () async {
        await _attachRemoteProfile(controller);
        const remotePath = '/srv/app/config.json';
        final remoteFile = SftpFileEntry(
          name: 'config.json',
          path: remotePath,
          size: '12 B',
          modified: 'Today 12:00',
        );

        backend.remoteFiles[remotePath] = utf8.encode('{"version":1}');
        final firstLocalPath = await controller.editablePathFor(
          remoteFile,
          true,
        );
        final firstContent = await File(firstLocalPath).readAsString();

        backend.remoteFiles[remotePath] = utf8.encode('{"version":2}');
        final secondLocalPath = await controller.editablePathFor(
          remoteFile,
          true,
        );
        final secondContent = await File(secondLocalPath).readAsString();

        expect(firstLocalPath, isNot(secondLocalPath));
        expect(firstLocalPath, endsWith('.json'));
        expect(secondLocalPath, endsWith('.json'));
        expect(firstContent, '{"version":1}');
        expect(secondContent, '{"version":2}');
        expect(await File(firstLocalPath).exists(), isTrue);
        expect(await File(secondLocalPath).exists(), isTrue);
        expect(backend.downloadCalls, [remotePath, remotePath]);
      },
    );

    test('rewrite uploads only to the server the copy came from', () async {
      await _attachRemoteProfile(controller);
      const remotePath = '/srv/app/config.json';
      final remoteFile = SftpFileEntry(
        name: 'config.json',
        path: remotePath,
        size: '12 B',
        modified: 'Today 12:00',
      );
      backend.remoteFiles[remotePath] = utf8.encode('old');
      final localPath = await controller.editablePathFor(remoteFile, true);
      await File(localPath).writeAsString('new');

      await expectLater(
        controller.rewriteRemoteFileFromLocal(
          remoteFile,
          localPath,
          profileId: 'another-profile',
        ),
        throwsStateError,
      );
      expect(utf8.decode(backend.remoteFiles[remotePath]!), 'old');

      await controller.rewriteRemoteFileFromLocal(
        remoteFile,
        localPath,
        profileId: 'profile-1',
      );
      expect(utf8.decode(backend.remoteFiles[remotePath]!), 'new');
    });

    test(
      'same basename from different remote paths never collides locally',
      () async {
        await _attachRemoteProfile(controller);
        const firstRemotePath = '/srv/a/config.json';
        const secondRemotePath = '/srv/b/config.json';
        final firstFile = SftpFileEntry(
          name: 'config.json',
          path: firstRemotePath,
          size: '10 B',
          modified: 'Today 12:00',
        );
        final secondFile = SftpFileEntry(
          name: 'config.json',
          path: secondRemotePath,
          size: '10 B',
          modified: 'Today 12:00',
        );

        backend.remoteFiles[firstRemotePath] = utf8.encode('alpha');
        backend.remoteFiles[secondRemotePath] = utf8.encode('beta');

        final firstLocalPath = await controller.editablePathFor(
          firstFile,
          true,
        );
        final secondLocalPath = await controller.editablePathFor(
          secondFile,
          true,
        );

        expect(firstLocalPath, isNot(secondLocalPath));
        expect(await File(firstLocalPath).readAsString(), 'alpha');
        expect(await File(secondLocalPath).readAsString(), 'beta');
        expect(
          pathBasename(firstLocalPath),
          isNot(pathBasename(secondLocalPath)),
        );
        expect(backend.downloadCalls, [firstRemotePath, secondRemotePath]);
        expect(controller.hasRemoteSession, isTrue);
      },
    );

    test(
      'non-remote open returns original local path without backend download',
      () async {
        final localFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}portix-local-${DateTime.now().microsecondsSinceEpoch}.txt',
        );
        await localFile.writeAsString('local');
        final localEntry = SftpFileEntry(
          name: pathBasename(localFile.path),
          path: localFile.path,
          size: '5 B',
          modified: 'Today 12:00',
        );

        final resolvedPath = await controller.editablePathFor(
          localEntry,
          false,
        );

        expect(resolvedPath, localFile.path);
        expect(backend.downloadCalls, isEmpty);
        await localFile.delete();
      },
    );

    test('throws when remote session is missing before remote open', () async {
      final remoteFile = SftpFileEntry(
        name: 'config.json',
        path: '/srv/app/config.json',
        size: '12 B',
        modified: 'Today 12:00',
      );

      await expectLater(
        () => controller.editablePathFor(remoteFile, true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Remote SFTP session is not connected'),
          ),
        ),
      );
      expect(backend.downloadCalls, isEmpty);
    });

    test(
      'propagates backend read failures and does not leave a partial local file',
      () async {
        await _attachRemoteProfile(controller);
        const remotePath = '/srv/app/missing.json';
        final remoteFile = SftpFileEntry(
          name: 'missing.json',
          path: remotePath,
          size: '0 B',
          modified: 'Today 12:00',
        );
        backend.readErrorPaths.add(remotePath);

        await expectLater(
          () => controller.editablePathFor(remoteFile, true),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Failed to download remote file'),
            ),
          ),
        );
        expect(backend.downloadCalls, [remotePath]);
      },
    );

    test(
      'supports filenames without extension and still generates unique local paths',
      () async {
        await _attachRemoteProfile(controller);
        const remotePath = '/opt/bin/env';
        final remoteFile = SftpFileEntry(
          name: 'env',
          path: remotePath,
          size: '8 B',
          modified: 'Today 12:00',
        );
        backend.remoteFiles[remotePath] = utf8.encode('KEY=one');

        final firstLocalPath = await controller.editablePathFor(
          remoteFile,
          true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final secondLocalPath = await controller.editablePathFor(
          remoteFile,
          true,
        );

        expect(pathBasename(firstLocalPath), startsWith('env__'));
        expect(pathBasename(secondLocalPath), startsWith('env__'));
        expect(
          pathBasename(firstLocalPath),
          isNot(pathBasename(secondLocalPath)),
        );
      },
    );

    test(
      'shouldNotifyDisconnection is false when SFTP session is connected',
      () async {
        await _attachRemoteProfile(controller);
        expect(controller.shouldNotifyDisconnection, isFalse);
        expect(controller.isRemoteConnected, isTrue);
      },
    );

    test(
      'shouldNotifyDisconnection is false after clearRemoteSession',
      () async {
        await _attachRemoteProfile(controller);
        expect(controller.shouldNotifyDisconnection, isFalse);

        await controller.clearRemoteSession();
        expect(controller.shouldNotifyDisconnection, isFalse);
        expect(controller.hasRemoteSession, isFalse);
      },
    );

    test(
      'shouldNotifyDisconnection becomes true when backend drops the session',
      () async {
        await _attachRemoteProfile(controller);
        expect(controller.shouldNotifyDisconnection, isFalse);

        // Simulate the SFTP connection dropping (keepalive timeout or
        // remote-side disconnect).
        backend.drop(controller.remoteSessionId);
        await _waitForLivenessCheck();

        expect(controller.shouldNotifyDisconnection, isTrue);
      },
    );

    test(
      'clearDisconnectionNotification resets the flag so reconnect is clean',
      () async {
        await _attachRemoteProfile(controller);
        backend.drop(controller.remoteSessionId);
        await _waitForLivenessCheck();
        expect(controller.shouldNotifyDisconnection, isTrue);

        controller.clearDisconnectionNotification();
        expect(controller.shouldNotifyDisconnection, isFalse);
      },
    );

    test('clearRemoteSession closes the SFTP session', () async {
      await _attachRemoteProfile(controller);
      final sessionId = controller.remoteSessionId;
      expect(sessionId, isNotNull);
      expect(sftpManager.session(sessionId!), isNotNull);

      await controller.clearRemoteSession();

      expect(sftpManager.session(sessionId), isNull);
      expect(await backend.isAlive(sessionId), isFalse);
      expect(controller.hasRemoteSession, isFalse);
      expect(controller.shouldNotifyDisconnection, isFalse);
    });

    test('per-tab tabId is unique and defaults to a non-empty UUID', () async {
      final firstController = SftpWorkspaceController(sftpManager: sftpManager);
      final secondController = SftpWorkspaceController(
        sftpManager: sftpManager,
      );

      expect(firstController.tabId, isNotEmpty);
      expect(secondController.tabId, isNotEmpty);
      expect(firstController.tabId, isNot(equals(secondController.tabId)));

      firstController.dispose();
      secondController.dispose();
    });

    test('two controllers on one SftpManager are session-isolated', () async {
      // Two controllers on the shared SftpManager each own a distinct session
      // the other can't clear or corrupt; the left pane depends on this.
      final controllerA = SftpWorkspaceController(
        sftpManager: sftpManager,
        localFileBrowser: _FakeLocalFileBrowser(),
        localEditorService: _FakeLocalEditorService(),
      );
      final controllerB = SftpWorkspaceController(
        sftpManager: sftpManager,
        localFileBrowser: _FakeLocalFileBrowser(),
        localEditorService: _FakeLocalEditorService(),
      );

      final profileA = domain.SshProfile(
        id: 'profile-a',
        name: 'Host A',
        host: 'a.example.com',
        port: 22,
        username: 'deploy',
        group: 'Production',
        tags: [],
        authMethod: domain.AuthMethod.sshKey,
        credentialLabel: '~/.ssh/id_ed25519',
        defaultPath: '/srv/app',
        status: domain.ConnectionStatus.online,
        color: domain.ProfileColor.blue,
      );
      final profileB = domain.SshProfile(
        id: 'profile-b',
        name: 'Host B',
        host: 'b.example.com',
        port: 22,
        username: 'deploy',
        group: 'Production',
        tags: [],
        authMethod: domain.AuthMethod.sshKey,
        credentialLabel: '~/.ssh/id_ed25519',
        defaultPath: '/opt/data',
        status: domain.ConnectionStatus.online,
        color: domain.ProfileColor.green,
      );

      await controllerA.attachRemoteProfile(profileA, '/srv/app');
      await controllerB.attachRemoteProfile(profileB, '/opt/data');
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Both sessions are live and distinct.
      expect(controllerA.hasRemoteSession, isTrue);
      expect(controllerB.hasRemoteSession, isTrue);
      expect(controllerA.remoteSessionId, isNotNull);
      expect(controllerB.remoteSessionId, isNotNull);
      expect(
        controllerA.remoteSessionId,
        isNot(equals(controllerB.remoteSessionId)),
      );
      expect(controllerA.remotePath, '/srv/app');
      expect(controllerB.remotePath, '/opt/data');
      expect(controllerA.isRemoteConnected, isTrue);
      expect(controllerB.isRemoteConnected, isTrue);

      // Clearing A leaves B fully intact (true session isolation).
      await controllerA.clearRemoteSession();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(controllerA.hasRemoteSession, isFalse);
      expect(controllerA.remoteSessionId, isNull);
      expect(controllerA.shouldNotifyDisconnection, isFalse);
      expect(controllerB.hasRemoteSession, isTrue);
      expect(controllerB.isRemoteConnected, isTrue);
      expect(controllerB.remoteSessionId, isNotNull);
      expect(controllerB.remotePath, '/opt/data');

      controllerA.dispose();
      controllerB.dispose();
    });

    test('beginLoading sets step-indicator state so file-pane controls are '
        'hidden during the pre-connection frame', () {
      // beginLoading() before setState: the first rebuild must show the step
      // indicator, not flash the path bar and actions.
      controller.beginLoading();

      expect(controller.loadingRemote, isTrue);
      expect(controller.showConnectionSteps, isTrue);
      expect(controller.remoteStatus, equals('connecting'));
      // showSteps = true is what hides those controls in _FilePane.build.
      expect(controller.showConnectionSteps, isTrue);

      // A second beginLoading is a no-op (already loading).
      controller.beginLoading();
      expect(controller.loadingRemote, isTrue);
      expect(controller.showConnectionSteps, isTrue);
      expect(controller.remoteStatus, equals('connecting'));
    });

    test('beginLoading + attachRemoteProfile(same profile) resets loading '
        'state via the session-reuse path — step indicator does not get '
        'stuck', () async {
      await _attachRemoteProfile(controller);
      // Controller is connected: controls should be visible (showSteps = false).
      expect(controller.loadingRemote, isFalse);
      expect(controller.showConnectionSteps, isFalse);
      expect(controller.remoteStatus, equals('connected'));

      // Simulate re-selecting the same profile: the page calls beginLoading()
      // before setState, then attachRemoteProfile runs via post-frame callback.
      controller.beginLoading();
      expect(controller.loadingRemote, isTrue);
      expect(controller.showConnectionSteps, isTrue);
      expect(controller.remoteStatus, equals('connecting'));

      // Re-attach the same profile (same id → session-reuse path).
      // The session-reuse path must reset the pre-emptive beginLoading state
      // so the step indicator doesn't stay stuck on 'connecting'.
      const sameProfile = domain.SshProfile(
        id: 'profile-1',
        name: 'Remote host',
        host: 'example.com',
        port: 22,
        username: 'deploy',
        group: 'Production',
        tags: [],
        authMethod: domain.AuthMethod.sshKey,
        credentialLabel: '~/.ssh/id_ed25519',
        defaultPath: '/',
        status: domain.ConnectionStatus.online,
        color: domain.ProfileColor.blue,
      );
      await controller.attachRemoteProfile(sameProfile, controller.remotePath);

      expect(controller.remoteStatus, equals('connected'));
      expect(controller.loadingRemote, isFalse);
      expect(controller.showConnectionSteps, isFalse);
      expect(controller.remoteError, isNull);
      expect(controller.hasRemoteSession, isTrue);
    });

    test('reconnect establishes a new session without being blocked by the '
        'loading guard', () async {
      await _attachRemoteProfile(controller);
      final oldSessionId = controller.remoteSessionId;
      expect(oldSessionId, isNotNull);

      // Regression: beginLoading's pre-set 'connecting' used to trip the old
      // loading guard, so reconnect silently never started.
      const reconnectProfile = domain.SshProfile(
        id: 'profile-1',
        name: 'Remote host',
        host: 'example.com',
        port: 22,
        username: 'deploy',
        group: 'Production',
        tags: [],
        authMethod: domain.AuthMethod.sshKey,
        credentialLabel: '~/.ssh/id_ed25519',
        defaultPath: '/',
        status: domain.ConnectionStatus.online,
        color: domain.ProfileColor.blue,
      );
      await controller.reconnect(reconnectProfile);

      expect(controller.remoteStatus, equals('connected'));
      expect(controller.loadingRemote, isFalse);
      expect(controller.showConnectionSteps, isFalse);
      expect(controller.remoteError, isNull);
      expect(controller.hasRemoteSession, isTrue);
      expect(controller.remoteSessionId, isNotNull);
      expect(controller.remoteSessionId, isNot(equals(oldSessionId)));
    });

    test('left-pane profile re-select returns to the file table instead of '
        'staying on the profile gate / step indicator', () async {
      // Like the page's LEFT controller: re-selecting the connected profile must
      // reset showConnectionSteps so the file table renders, not a stuck gate.
      final leftController = SftpWorkspaceController(
        sftpManager: sftpManager,
        localFileBrowser: _FakeLocalFileBrowser(),
        localEditorService: _FakeLocalEditorService(),
      );

      await _attachRemoteProfile(leftController);
      expect(leftController.isRemoteConnected, isTrue);
      expect(leftController.showConnectionSteps, isFalse);
      expect(leftController.pendingProfile, isNull);

      // Simulate the left pane re-selecting its connected profile:
      // onSelected -> beginLoading() (pre-arms 'connecting') -> setState ->
      // _scheduleLeftSync -> attachRemoteProfile(same id).
      leftController.beginLoading();
      expect(leftController.loadingRemote, isTrue);
      expect(leftController.showConnectionSteps, isTrue);
      expect(leftController.remoteStatus, equals('connecting'));

      const sameProfile = domain.SshProfile(
        id: 'profile-1',
        name: 'Remote host',
        host: 'example.com',
        port: 22,
        username: 'deploy',
        group: 'Production',
        tags: [],
        authMethod: domain.AuthMethod.sshKey,
        credentialLabel: '~/.ssh/id_ed25519',
        defaultPath: '/',
        status: domain.ConnectionStatus.online,
        color: domain.ProfileColor.blue,
      );
      await leftController.attachRemoteProfile(
        sameProfile,
        leftController.remotePath,
      );

      expect(leftController.remoteStatus, equals('connected'));
      expect(leftController.loadingRemote, isFalse);
      expect(leftController.showConnectionSteps, isFalse);
      expect(leftController.pendingProfile, isNull);
      expect(leftController.isRemoteConnected, isTrue);
      expect(leftController.remoteError, isNull);
      expect(leftController.hasRemoteSession, isTrue);

      leftController.dispose();
    });
  });

  test('notifyListeners after dispose is a no-op (tab/page close safety)', () {
    final sftpManager = _manager(FakeSftpBackend());
    final controller = SftpWorkspaceController(
      sftpManager: sftpManager,
      localFileBrowser: _FakeLocalFileBrowser(),
      localEditorService: _FakeLocalEditorService(),
    );
    // Disposing while the constructor's loadLocalDirectory is pending must not
    // trip the "used after being disposed" assert.
    controller.dispose();
    expect(() => controller.notifyListeners(), returnsNormally);
    sftpManager.dispose();
  });

  test('failed remote listing keeps the SFTP session alive but sets an error, '
      'so the file-pane controls are hidden', () async {
    final failingBackend = _ListingFailBackend();
    final manager = _manager(failingBackend);
    final ctrl = SftpWorkspaceController(
      sftpManager: manager,
      localFileBrowser: _FakeLocalFileBrowser(),
      localEditorService: _FakeLocalEditorService(),
    );

    // 1) Initial connect + first listing succeeds: showSteps flips to
    //    false so the file pane starts rendering the path bar & actions.
    await _attachRemoteProfile(ctrl);
    expect(ctrl.loadingRemote, isFalse);
    expect(ctrl.remoteStatus, equals('connected'));
    expect(ctrl.remoteError, isNull);
    expect(ctrl.showConnectionSteps, isFalse);

    // 2) Simulate the SFTP channel silently dying — the TCP session is
    //    still "connected" but listing now fails (e.g. after a network
    //    hiccup or a server-side channel closure).
    failingBackend.failListing = true;
    await ctrl.loadRemoteDirectory(ctrl.remotePath);
    await Future.delayed(Duration.zero);

    // TCP is still up but the listing failed: status 'failed' with an error,
    // which is what makes _FilePane hide its controls.
    expect(ctrl.loadingRemote, isFalse);
    expect(ctrl.remoteStatus, equals('failed'));
    expect(ctrl.remoteError, isNotNull);
    expect(ctrl.isRemoteDisconnected, isFalse);
    expect(ctrl.showConnectionSteps, isFalse);
    expect(ctrl.loadingRemote || ctrl.remoteError == null, isFalse);

    ctrl.dispose();
    manager.dispose();
  });

  test('submitPassword suppresses a racing duplicate attachRemoteProfile so '
      'the password form is not re-shown', () async {
    final secretStore = _MemorySecretStore();
    final manager = _manager(FakeSftpBackend(), store: secretStore);
    final ctrl = SftpWorkspaceController(
      sftpManager: manager,
      localFileBrowser: _FakeLocalFileBrowser(),
      localEditorService: _FakeLocalEditorService(),
    );

    const profile = domain.SshProfile(
      id: 'p-password',
      name: 'Password Host',
      host: 'example.com',
      port: 22,
      username: 'deploy',
      group: '',
      tags: [],
      authMethod: domain.AuthMethod.password,
      credentialLabel: 'Saved password',
      defaultPath: '/',
      status: domain.ConnectionStatus.online,
      color: domain.ProfileColor.blue,
    );

    // 1) attachRemoteProfile enters 'authenticating' because no password
    //    is stored for this profile.
    final initial = ctrl.attachRemoteProfile(profile, '/');
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);
    await initial;
    expect(ctrl.remoteStatus, equals('authenticating'));
    expect(ctrl.pendingProfile, isNotNull);
    expect(ctrl.loadingRemote, isTrue);

    // 2) Begin password submission. submitPassword clears _pendingProfile,
    //    sets _passwordSubmitting = true, then awaits saveProfilePassword.
    //    We delay the save so we can inject a racing attachRemoteProfile.
    final saveGate = Completer<void>();
    secretStore.saveDelay = saveGate.future;

    final submitFuture = ctrl.submitPassword('superSecret');

    // submitPassword runs synchronously up to the save await, so the
    // flag is already set and _pendingProfile is already null.
    expect(ctrl.pendingProfile, isNull);
    expect(ctrl.remoteStatus, equals('authenticating'));

    // 3) A scheduled sync fires during the save with the ORIGINAL profile:
    //    the race that re-showed the password form.
    final duplicate = ctrl.attachRemoteProfile(profile, '/');
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);
    await duplicate;

    // 4) It must be suppressed: no new pending profile, no 'authenticating'.
    expect(
      ctrl.pendingProfile,
      isNull,
      reason:
          'Racing attachRemoteProfile with the original profile must '
          'not re-set _pendingProfile during password submission',
    );
    expect(ctrl.remoteStatus, equals('authenticating'));

    // 5) Complete the save — submitPassword proceeds to connect with the
    //    resolved profile (password embedded in credentialLabel).
    secretStore.saveDelay = null;
    saveGate.complete();
    await submitFuture;
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);

    expect(ctrl.remoteStatus, equals('connected'));
    expect(ctrl.remoteError, isNull);
    expect(ctrl.hasRemoteSession, isTrue);
    expect(ctrl.loadingRemote, isFalse);

    ctrl.dispose();
    manager.dispose();
  });
}

Future<String> _attachRemoteProfile(SftpWorkspaceController controller) async {
  const profile = domain.SshProfile(
    id: 'profile-1',
    name: 'Remote host',
    host: 'example.com',
    port: 22,
    username: 'deploy',
    group: 'Production',
    tags: [],
    authMethod: domain.AuthMethod.sshKey,
    credentialLabel: '~/.ssh/id_ed25519',
    defaultPath: '/',
    status: domain.ConnectionStatus.online,
    color: domain.ProfileColor.blue,
  );
  await controller.attachRemoteProfile(profile, '/');
  expect(controller.hasRemoteSession, isTrue);
  expect(controller.remotePath, '/');
  return controller.remotePath;
}

String pathBasename(String path) => path.split(Platform.pathSeparator).last;

class _FakeLocalEditorService extends LocalEditorService {}

class _FakeLocalFileBrowser extends LocalFileBrowser {
  @override
  String defaultPath() => Directory.systemTemp.path;

  @override
  Future<LocalDirectoryResult> readDirectory(String path) async {
    return LocalDirectoryResult(path: path, entries: const []);
  }
}

/// [FakeSftpBackend] whose listing can be made to throw: the channel is
/// alive but unreadable.
class _ListingFailBackend extends FakeSftpBackend {
  bool failListing = false;

  @override
  Future<List<RemoteFileEntry>> list(String sessionId, String path) async {
    if (failListing) {
      throw StateError('simulated listing failure');
    }
    return const [];
  }
}

/// In-memory [ProfileSecretStore] whose `savePassword` can be held open
/// ([saveDelay]) to reproduce the race with a scheduled sync.
class _MemorySecretStore extends ProfileSecretStore {
  _MemorySecretStore() : super();

  final Map<String, String> _passwords = {};

  /// When non-null, `savePassword` awaits this future before storing the
  /// credential, letting tests inject a window during which a duplicate
  /// `attachRemoteProfile` can fire.
  Future<void>? saveDelay;

  @override
  Future<void> savePassword(String profileId, String password) async {
    if (saveDelay != null) {
      await saveDelay!;
    }
    _passwords[profileId] = password;
  }

  @override
  Future<String?> readPassword(String profileId) async {
    return _passwords[profileId];
  }

  @override
  Future<void> deletePassword(String profileId) async {
    _passwords.remove(profileId);
  }
}
